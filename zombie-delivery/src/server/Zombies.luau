--!strict
-- The zombies of a run (10.6: only the sandbox is the game), built in code. Who calls Zombies.spawn brings them: a run's
-- danger (server/RunDanger.luau: Config.Runs.Danger has none since 10.5, its code stays switched off) and a move's
-- horde and roamers (server/Moving.luau: Config.Moving.Sandbox Horde and Roam, off). The city's bandits and soldiers,
-- its residents' camps, roadblocks, missions, live events, the Blood Moon and every car a zombie grabbed, rammed or bit
-- went with the city: a zombie goes after a player on foot (or a body Zombies.extraTargets adds: a run's helper,
-- server/MoveHelper.luau), never a van (they are parked: nobody's target).
--
--   * a roamer (Config.Horde.Roam's walk) shambles around its spot; it hunts a player who comes close or hits it, and
--     calms down when it loses them; `resident` ones never despawn (a run's). A march's zombie (Zombies.march: a
--     move's horde) goes at its spot and after a player within MARCH_REACH of it.
--   * the old safe zone (isSafe: the city's middle, SAFE_HALF) is never entered; nothing of the game's world is in it,
--     it matters only if a horde ever got there.
--   * the limbs are animated on the clients (client/ZombieAnimator.luau), the server only moves the bodies; R15 bodies
--     (server/CharacterArt) play their walk here, the blocky fallback is the clients'.
--
-- 6.16, zombies with a life of their own (looks only: nothing here changes what a zombie does):
--   * every zombie wears one of its kind's looks (shared/ZombieStyle.luau, picked from its id: the model's Seed
--     attribute, which the clients read for its gait and voice too); a template is built once per kind and look;
--   * the Hit attribute marks a hit that did not kill (how: ZombieStyle.hitMark; at most every
--     Config.ZombieLife.HitEvery s a zombie, a hard one always) and Attack counts its bites and swipes: the clients'
--     flinch and lunge (client/ZombieAnimator.luau) and grunts (client/ZombieLife.luau);
--   * a death falls its own way (ZombieStyle.death): knocked back (a headshot, a punch), forward on its face, a spin,
--     a crumple where it stands; a blast still flings the parts. The 6 s clean-up and the counting are unchanged.
--
-- 6.24, the special zombies (the numbers are Config.Zombies' and Config.ZombieTypes', the rules shared/ZombieKinds
-- .luau's; the looks and moves on the clients: client/ZombieAnimator.luau, client/ZombieFx.luau):
--   * the runner (ZombieDef.lunge) leaps at a player on foot a few strides away (the Lunge attribute: the clients' dive
--     and shriek); its strike lands once a leap;
--   * the brute (armour) takes less from the front (Zombies.damage: ZombieKinds.armourShare; a headshot, a blast do it
--     all; the Clank attribute: the clients' clink); its bite throws a player back (shove: the Knock remote);
--   * the bloater (blast) never bites: next to you it hisses and swells for blast.fuse s and goes off; killed (with a
--     cause: not the admin's) it goes off blast.deathFuse s later. The blast (an Explosion for the looks, the sound
--     and the camera's shake) hurts every zombie round it (a chain: another bloater goes off too; the kills are its
--     killer's) and the players on foot (thrown away). The Fuse attribute (the server time it goes off) shows the
--     warning on the clients;
--   * every random pick of a kind (a move's horde and its roamers) goes through Zombies.pickKind: the night (never:
--     DayNight.nightFactor 0), the danger (how far from the old city's depot, DEPOT), and MaxAlive of a special kind in
--     the server at most (a run's danger picks its own: shared/DangerRules.luau).
--   * a kill pays its money (the "KillReward") and counts in the profile's kills.
--
-- 10.x danger, a run's zombies (server/RunDanger.luau sets these; nothing changes without them):
--   * Zombies.steer(z, from, goal) -> Vector3?: where a zombie walking from `from` to `goal` steps now (a run's house:
--     its way through the doorways, shared/HouseRoute.luau); nil: straight at the goal, as ever
--   * Zombies.onBite(player, humanoid, z): a bite (or a runner's leap) landed on a player's or a helper's body
--   * Zombie.aggro: studs a calm zombie notices a player on foot at (nil: Roam.aggro)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Joints = require(Shared.Joints)
local DangerRules = require(Shared.DangerRules) -- (its pickKind: a kind by the weights)
local PlayerData = require(script.Parent.PlayerData)
local DayNight = require(script.Parent.DayNight) -- (10.6: nightFactor 0, the game's day)
local Armour = require(script.Parent.Armour) -- 6.0: every bite and blast on a player goes through here
local ZombieStyle = require(Shared.ZombieStyle) -- 6.16: the looks, the falls, the Hit attribute
local Kinds = require(Shared.ZombieKinds) -- 6.24: the special zombies' rules

-- 10.6 (the city's server/World.luau and shared/Map.luau went): the old road level (World.RoadTop: a road spot's
-- height), the old safe zone round the middle (Config.City.SafeHalf: |x|, |z| below it; nothing of the game's world is
-- in it, it matters only if a horde ever gets there), the old depot (Map.Depot: the special kinds' danger grows with
-- the distance from it, ZombieKinds.danger) and how far a march's zombie goes after a player (Config.LiveEvents.Reach).
local ROAD_TOP = 0.4
local SAFE_HALF = 235
local DEPOT = Vector3.new(144, 0, -144)
local MARCH_REACH = 140

local function isSafe(position: Vector3): boolean
	return math.abs(position.X) < SAFE_HALF and math.abs(position.Z) < SAFE_HALF
end

local Horde = Config.Horde
local Roam = Horde.Roam
local Types = Config.ZombieTypes -- 6.24
local Special = {} -- 6.24: the special zombies' moves (filled further down: the leap, the clink, the shove, the blast)

export type Zombie = {
	id: number,
	kind: string,
	def: Config.ZombieDef,
	model: Model,
	humanoid: Humanoid,
	root: Part,
	torso: Part,
	owner: Player?, -- whose run spawned it (for the clean-up)
	resident: boolean, -- never despawns (a run's)
	dead: boolean,
	nextAttack: number,
	nextPath: number,
	lastHitBy: Player?,
	home: Vector3, -- where it wanders around
	roamer: boolean, -- roams around its spot (Config.Horde.Roam)
	hunting: boolean, -- a roamer that noticed somebody (else it wanders)
	lostSince: number?, -- hunting, but nobody in reach since
	nextWander: number,
	walkSpeed: number, -- its full speed (it shambles slower while it wanders)
	march: Vector3?, -- 6.15: a march's zombie (a move's horde): where it walks to and waits (Zombies.march)
	-- 6.16 (looks only): its Hit and Attack attributes' counts, when it last showed a hit
	hits: number?,
	hitShown: number?,
	attacks: number?,
	-- 6.24, the special zombies: the runner's leap (when it may leap again, until when it is in the air, whether its
	-- strike landed, the Lunge attribute's count), the bloater's fuse (when it goes off, whether it went, who set it off:
	-- the blast's kills are theirs), the brute's clinks (the Clank attribute) and when it may shove again
	nextLunge: number?,
	lungeUntil: number?,
	lungeHit: boolean?,
	lunges: number?,
	fuseAt: number?,
	blasted: boolean?,
	blastBy: Player?,
	clanks: number?,
	clankShown: number?,
	nextShove: number?,
	aggro: number?, -- 10.x danger: studs it notices a player on foot at while calm (nil: Roam.aggro)
}

local Zombies = {}

local zombies: { Zombie } = {}
local nextId = 0
local rng = Random.new()
local rewardRemote = Net.get("Reward")
Special.knockRemote = Net.get("Knock") -- 6.24
Special.knockedAt = {} :: { [Player]: number }

-- Set by server/MoveHelper.luau: more bodies on foot to go after (a run's helpers), each with the player it belongs to.
export type ExtraTarget = { position: Vector3, velocity: Vector3, humanoid: Humanoid, player: Player }
Zombies.extraTargets = nil :: (() -> { ExtraTarget })?
-- 10.x danger (server/RunDanger.luau): a run's zombies' way inside its house, and who a bite landed on.
Zombies.steer = nil :: ((Zombie, Vector3, Vector3) -> Vector3?)?
Zombies.onBite = nil :: ((Player, Humanoid, Zombie) -> ())?

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

-- 5.7: the Humanoid states an enemy never needs are off (each one the Humanoid would otherwise test every physics
-- step): no climbing, swimming or sitting (a car seat, a bench), no flying, and no falling down and getting up (a
-- ram is computed, a death ragdolls by hand). PlatformStanding stays: a latched or stunned zombie uses it.
local UNUSED_STATES = {
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.StrafingNoPhysics,
}
local function quietStates(humanoid: Humanoid)
	for _, state in UNUSED_STATES do
		humanoid:SetStateEnabled(state, false)
	end
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
	for _, side in { -1, 1 } do
		local eye = limb(model, "Eye", Vector3.new(0.22, 0.18, 0.1) * s, Color3.fromRGB(255, 60, 40), Enum.Material.Neon)
		eye.Massless = true
		eye:SetAttribute("HeadPart", true) -- a hit here is a headshot
		motor("Eye", head, eye, CFrame.new(0.28 * side * s, 0.12 * s, -0.6 * s), CFrame.identity)
	end
	if kind == "brute" then
		local jaw = limb(model, "Jaw", Vector3.new(1, 0.3, 0.4) * s, Color3.fromRGB(60, 20, 20))
		jaw.Massless = true
		jaw:SetAttribute("HeadPart", true) -- a hit here is a headshot
		motor("Jaw", head, jaw, CFrame.new(0, -0.35 * s, -0.5 * s), CFrame.identity)
	end

	-- Plain joints (no rotation in C0 / C1): the client sets Transform to swing them.
	motor("RootJoint", root, torso, CFrame.identity, CFrame.identity)
	local tilt = CFrame.Angles(math.rad(-12), 0, math.rad(rng:NextNumber(-15, 15)))
	motor("Neck", torso, head, CFrame.new(0, s, 0) * tilt, CFrame.new(0, -0.6 * s, 0))
	local reach = CFrame.Angles(math.rad(80), 0, 0) -- arms forward: the zombie pose
	motor("Left Shoulder", torso, leftArm, CFrame.new(-1.5 * s, 0.5 * s, 0) * reach, CFrame.new(0, 0.5 * s, 0))
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
	quietStates(humanoid)
	humanoid.Parent = model

	model.PrimaryPart = root
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	model:SetAttribute("Zombie", kind)
	return model, humanoid, root, torso
end

-- ── Realistic bodies: R15 characters with animations ───────────────────────
-- Native infected rigs (server/CharacterArt) match the approved thumbnail, with the Animator, the scales and the
-- ragdoll path. Templates are built once per kind and look, then cloned.

local CharacterGeometry = require(script.Parent.CharacterArt.Geometry)
local CharacterRig = require(script.Parent.CharacterArt.Rig)

local ANIMATIONS: { [string]: { [string]: string } } = {
	zombie = { idle = "rbxassetid://616158929", walk = "rbxassetid://616168032", run = "rbxassetid://616163682" },
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

-- 6.16: one template per kind and look (shared/ZombieStyle.luau).
local function template(kind: string, def: Config.ZombieDef, look: ZombieStyle.Look): Model?
	local key = kind .. "#" .. look.variant
	if templates[key] or noTemplate[kind] then
		return templates[key]
	end
	local s = def.scale
	local ok, result = pcall(function()
		return CharacterRig.build(CharacterGeometry.spec(kind, s, look.skin, look.shirt, look.pants, look.outfit))
	end)
	if not ok or not result then
		warn(`[Zombies] no R15 body for {kind}, using blocks: {result}`)
		noTemplate[kind] = true
		return nil
	end
	local model = result :: Model
	model.Name = def.name
	local head = model:FindFirstChild("Head") :: BasePart?
	if head then
		local face = head:FindFirstChildOfClass("Decal")
		if model:GetAttribute("CharacterArt") == nil then
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
	templates[key] = model
	return model
end

-- seed (6.16): the zombie's id: its look (shared/ZombieStyle.luau).
local function buildBody(kind: string, def: Config.ZombieDef, at: Vector3, seed: number): (Model, Humanoid, Part, Part)
	local look = ZombieStyle.look(kind, seed)
	local source = template(kind, def, look)
	if not source then
		return buildBlocky(kind, def, at)
	end
	local model = source:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: Part
	local torso = (model:FindFirstChild("UpperTorso") or root) :: Part
	-- Every zombie a little different (6.16: the classic look; the others have their own colours).
	local tint = if look.variant == 1 then rng:NextNumber(-0.1, 0.1) else 0
	for _, name in { "UpperTorso", "LowerTorso" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") and tint ~= 0 then
			part.Color = part.Color:Lerp(if tint > 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), math.abs(tint) * 2)
		end
	end
	humanoid.MaxHealth = def.health
	humanoid.Health = def.health
	humanoid.WalkSpeed = def.speed * rng:NextNumber(0.9, 1.1)
	quietStates(humanoid)
	model.PrimaryPart = root
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	return model, humanoid, root, torso
end

type Moves = { idle: AnimationTrack?, walk: AnimationTrack?, run: AnimationTrack?, rate: number? }
local moves: { [Model]: Moves } = {}

local function loadMoves(model: Model, humanoid: Humanoid)
	if not model:FindFirstChild("UpperTorso") then
		return -- the blocky body is animated by the clients
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks: Moves = {}
	for key, id in ANIMATIONS.zombie do
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
		-- (a track's speed replicates: only a real change is sent, not a new value every pass)
		local rate = math.clamp(speed / (if runner then 24 else 12), 0.5, 2)
		if not tracks.rate or math.abs(rate - tracks.rate) > 0.1 then
			tracks.rate = rate
			moving:AdjustSpeed(rate)
		end
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

-- The zombies that wander and hunt only what they notice: roamers and a run's own.
local function roams(z: Zombie): boolean
	return z.roamer or z.resident
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

local function remove(z: Zombie)
	z.dead = true
	local index = table.find(zombies, z)
	if index then
		table.remove(zombies, index)
	end
end

-- 6.16, looks only: the clients' flinch (the Hit attribute: how it was hit, ZombieStyle.hitMark; a plain body shot at
-- most every Config.ZombieLife.HitEvery s a zombie) and lunge (Attack: a count of its bites and swipes).
local Life = Config.ZombieLife
local function showHit(z: Zombie, code: number)
	local now = os.clock()
	if code <= 1 and z.hitShown and now - (z.hitShown :: number) < Life.HitEvery then -- (6.16 review: a headshot too)
		return
	end
	z.hitShown = now
	z.hits = (z.hits or 0) + 1
	z.model:SetAttribute("Hit", ZombieStyle.hitMark(z.hits :: number, code))
end
local function showAttack(z: Zombie)
	z.attacks = (z.attacks or 0) + 1
	z.model:SetAttribute("Attack", z.attacks)
end

-- 6.16: how a dead body falls (ZombieStyle.death's style; not "flung"): every part set moving as one body tipping over
-- about its feet (and turning round its middle on a spin), so the ragdoll falls that way. Knocked back: away from the
-- shot (its push, else from the killer), a headshot's head a little more; forward: onto its face; a spin; a crumple:
-- it sinks where it stands.
local function deathMotion(z: Zombie, style: string, push: Vector3?, killer: Player?, headshot: boolean?): (BasePart) -> ()
	local D = Life.Death
	local cf = z.root.CFrame
	local up = Vector3.yAxis
	local feet = cf.Position - up * (z.humanoid.HipHeight + z.root.Size.Y / 2)
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local forward = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	local away = -forward
	local flat = if push then Vector3.new(push.X, 0, push.Z) else Vector3.zero
	if flat.Magnitude > 0.1 then
		away = flat.Unit
	else
		local character = killer and killer.Character
		local from = character and character:FindFirstChild("HumanoidRootPart")
		if from and from:IsA("BasePart") then
			local d = cf.Position - from.Position
			d = Vector3.new(d.X, 0, d.Z)
			if d.Magnitude > 0.1 then
				away = d.Unit
			end
		end
	end
	local fall = D.Fall / math.max(z.def.scale, 0.5)
	local base, tip, spin = Vector3.zero, Vector3.zero, Vector3.zero
	if style == "back" then
		tip = up:Cross(away) * fall -- (the top goes `away`)
		base = away * D.Back + up * D.Lift
	elseif style == "forward" then
		tip = up:Cross(forward) * fall
		base = forward * 2
	elseif style == "spin" then
		local turn = if z.id % 2 == 0 then 1 else -1
		local side = forward:Cross(up) * turn
		spin = up * D.Spin * turn
		tip = up:Cross(side) * fall * 0.7
		base = side * 3 + up * D.Lift * 0.5
	else
		tip = up:Cross(forward) * fall * 0.35
		base = Vector3.new(0, -D.Slump, 0)
	end
	base += z.root.AssemblyLinearVelocity -- (its own run carries on)
	local centre = cf.Position
	local head = if headshot and style == "back" then z.model:FindFirstChild("Head") else nil
	return function(part: BasePart)
		local at = part.Position
		local v = base + tip:Cross(at - feet) + spin:Cross(at - centre)
		if head and (part == head or part.AssemblyRootPart == head) then
			v += away * D.HeadBack
		end
		part.AssemblyLinearVelocity = v
		part.AssemblyAngularVelocity = tip + spin
	end
end

-- killer = nil: no reward (despawn, the safe zone). push = velocity for the flying parts. cause and headshot: how it
-- falls (ZombieStyle.death).
local function kill(z: Zombie, killer: Player?, push: Vector3?, cause: string?, headshot: boolean?)
	if z.dead then
		return
	end
	remove(z)
	-- 6.16: how it falls (before the ragdoll: from where it stands)
	local style = ZombieStyle.death(z.id, cause, headshot, push ~= nil)
	local fall = if style ~= "flung" then deathMotion(z, style, push, killer, headshot) else nil
	z.humanoid.Health = 0
	ragdoll(z.model)
	-- The body collapses: collides only with the ground and buildings, never with the vans or players.
	for _, d in z.model:GetDescendants() do
		if d:IsA("BasePart") then
			local decoration = d:GetAttribute("CharacterDecoration") == true
			d.CanCollide = not decoration and d.Name ~= "HumanoidRootPart"
			d.CollisionGroup = "Corpse"
			d.Massless = decoration -- the thin face/clothing skin stays nonblocking even on a corpse
			if fall then
				fall(d)
			elseif push then
				d.AssemblyLinearVelocity = push + Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(10, 25), rng:NextNumber(-8, 8))
			end
		end
	end
	if killer then
		local profile = PlayerData.get(killer)
		if profile then
			profile.kills += 1
		end
		PlayerData.addMoney(killer, z.def.reward, "KillReward")
		rewardRemote:FireClient(killer, z.root.Position + Vector3.new(0, 4, 0), z.def.reward)
	end
	-- 6.24: a bloater killed by something (a hit, a punch, a blast: not burnt, not the admin's) goes off soon
	local blast = z.def.blast
	if blast and cause ~= nil and cause ~= "other" then
		Special.fuse(z, blast.deathFuse, killer)
	elseif blast then
		-- (6.24 review: a plain death: a fuse already lit goes out too)
		z.blasted = true
		z.fuseAt = nil
		z.model:SetAttribute("Fuse", nil)
	end
	local leap = z.root:FindFirstChild("Leap") -- (6.24 review: a dead runner's leap stops pushing)
	if leap then
		leap:Destroy()
	end
	task.delay(6, function()
		z.model:Destroy()
	end)
end

-- cause (3.1): "splash" (a blast), "melee" (3.9: the bat, a helper's blow); nil = a hit of old (a gun's). 6.24: pellets =
-- a shot's pellets (a brute's plates take a single round); push = the way the hit travels (a plate takes the ones on
-- its front). "other": the admin's (a bloater does not go off).
export type HitInfo = { crit: boolean?, push: Vector3?, cause: string?, pellets: number? }

-- Returns true when the hit killed it.
function Zombies.damage(z: Zombie, amount: number, by: Player?, info: HitInfo?): boolean
	if z.dead or amount <= 0 then
		return false
	end
	-- 6.24: the brute's plates (shared/ZombieKinds.luau armourShare): from the front, or a small gun's round, less
	local armour = z.def.armour
	if armour and amount < math.huge then
		local hit = Special.hitOf(z, amount, info, armour.angle)
		local share = Kinds.armourShare(armour, hit)
		if share < 1 then
			amount *= share
			if hit.front then
				Special.clank(z) -- (on its plates: the clients' clink)
			end
		end
	end
	z.lastHitBy = by or z.lastHitBy
	if roams(z) then
		wake(z) -- hit: now it hunts
	end
	local health = z.humanoid.Health - amount
	if health <= 0 then
		kill(z, by, info and info.push, if info then info.cause or "gun" else "gun", info ~= nil and info.crit == true)
		return true
	end
	z.humanoid.Health = health
	showHit(z, ZombieStyle.hitCode(info and info.cause, info ~= nil and info.crit == true)) -- 6.16: the clients' flinch
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

-- A march's zombie (a move's horde, server/Moving.luau) walks to `at` and waits there (never despawning, going after a
-- player within MARCH_REACH); `at` nil lets it go: it roams on like a roamer (and despawns like one).
function Zombies.march(z: Zombie, at: Vector3?)
	if z.dead then
		return
	end
	if at then
		z.march = at
		return
	end
	if z.march == nil then
		return
	end
	z.march = nil
	z.roamer = true
	z.home = z.root.Position
	z.hunting = true -- (it calms down once it lost everybody, like a roamer)
	z.lostSince = nil
end

-- owner: whose run it is (Zombies.clearOwner); resident: it never despawns (a run's); roamer: it wanders until it
-- notices you (Config.Horde.Roam). Nil when the server's cap (Horde.MaxTotal) is reached.
function Zombies.spawn(kind: string, at: Vector3, owner: Player?, resident: boolean?, roamer: boolean?): Zombie?
	if #zombies >= Horde.MaxTotal then
		return nil
	end
	local def = Config.Zombies[kind] or Config.Zombies.walker
	local model, humanoid, root, torso = buildBody(kind, def, at + Vector3.new(0, 3 * def.scale, 0), nextId + 1)
	nextId += 1
	model:SetAttribute("Seed", nextId) -- 6.16: its look, gait and voice (shared/ZombieStyle.luau)
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
		nextAttack = 0,
		nextPath = 0,
		lastHitBy = nil,
		home = at,
		roamer = roamer == true,
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
	loadMoves(model, humanoid)
	humanoid.Died:Connect(function()
		if not z.dead then
			kill(z, z.lastHitBy, nil)
		end
	end)
	table.insert(zombies, z)
	return z
end

-- A free spot somewhere around `center` (10.5: on the ground at its distance; the city's snapped it to its nearest
-- road), out of the safe zone and not right next to a player.
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
		local spot = Vector3.new(px, ROAD_TOP, pz)
		if isSafe(spot) or (spot - center).Magnitude < low * 0.6 then
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

-- One of them gone without dying (a run's, its run over: server/RunDanger.luau).
function Zombies.despawn(z: Zombie)
	if z.dead then
		return
	end
	remove(z)
	z.model:Destroy()
end

-- The player left: their zombies go too.
function Zombies.clearOwner(owner: Player)
	for _, z in table.clone(zombies) do
		if z.owner == owner then
			remove(z)
			z.model:Destroy()
		end
	end
	Special.knockedAt[owner] = nil -- 6.24
end

-- ── Behaviour ──────────────────────────────────────────────────────────────

-- Somebody on foot to go after: player = who it is (a helper's: whose helper).
type Target = { position: Vector3, velocity: Vector3, humanoid: Humanoid?, player: Player }

local function gatherTargets(): { Target }
	local targets: { Target } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and rootPart and humanoid.Health > 0 and not humanoid.SeatPart and not isSafe(rootPart.Position) and player:GetAttribute("AdminHidden") ~= true then
			table.insert(targets, { position = rootPart.Position, velocity = rootPart.AssemblyLinearVelocity, humanoid = humanoid, player = player })
		end
	end
	-- a run's helpers (server/MoveHelper.luau), bitten like players on foot
	local extra = Zombies.extraTargets
	if extra then
		local ok, list = pcall(extra)
		if ok then
			for _, t in list do
				if not isSafe(t.position) then
					table.insert(targets, { position = t.position, velocity = t.velocity, humanoid = t.humanoid, player = t.player })
				end
			end
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

-- ── 10.x danger: a run's zombies (server/RunDanger.luau) ─────────────────────

-- Where `z` steps from `from` toward `goal`: Zombies.steer's (a run's house: its way through the doorways), else `goal`.
function Special.steer(z: Zombie, from: Vector3, goal: Vector3): Vector3
	local steer = Zombies.steer
	if steer then
		local ok, to = pcall(steer, z, from, goal)
		if ok and typeof(to) == "Vector3" then
			return to
		end
	end
	return goal
end

-- A bite (or a leap's strike) landed on `humanoid`: Zombies.onBite hears it.
function Special.bit(z: Zombie, player: Player, humanoid: Humanoid)
	local onBite = Zombies.onBite
	if onBite then
		local ok, err = pcall(onBite :: any, player, humanoid, z)
		if not ok then
			warn(`[Zombies] onBite: {err}`)
		end
	end
end

-- ── 6.24: the special zombies ──────────────────────────────────────────────

-- What the plates see of a hit: a headshot, its cause and pellets, its damage, and whether it struck the front (the way
-- it travels, HitInfo.push, against where the body faces).
function Special.hitOf(z: Zombie, amount: number, info: HitInfo?, angle: number): Kinds.Hit
	local way = info and info.push
	local look = z.root.CFrame.LookVector
	return {
		crit = info ~= nil and info.crit == true,
		cause = info and info.cause,
		pellets = info and info.pellets or 1,
		damage = amount,
		front = way ~= nil and Kinds.isFront(look.X, look.Z, way.X, way.Z, angle),
	}
end

-- A hit the plates took: the clients' clink (the Clank attribute, a count), at most every Life.HitEvery s.
function Special.clank(z: Zombie)
	local now = os.clock()
	if z.clankShown and now - (z.clankShown :: number) < Life.HitEvery then
		return
	end
	z.clankShown = now
	z.clanks = (z.clanks or 0) + 1
	z.model:SetAttribute("Clank", z.clanks)
end

-- A player on foot thrown `speed` studs / s along `away` (flat) and `up` up: their own client pushes their body (the
-- Knock remote); at most every Types.KnockEvery s a player, never a seated one or a helper.
function Special.knock(player: Player, humanoid: Humanoid, away: Vector3, speed: number, up: number)
	if speed <= 0 or humanoid.Parent ~= player.Character or humanoid.SeatPart ~= nil or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if now - (Special.knockedAt[player] or -math.huge) < Types.KnockEvery then
		return
	end
	Special.knockedAt[player] = now
	local flat = Vector3.new(away.X, 0, away.Z)
	local way = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zero
	Special.knockRemote:FireClient(player, way * speed + Vector3.new(0, up, 0))
end

-- The runner's leap at `best` (on foot, `distance` away): in the air its strike lands once within lunge.reach (looked at
-- every frame or so); on the ground, within lunge.range and rested, it leaps (the Lunge attribute: the clients' dive).
function Special.lunge(z: Zombie, best: Target, distance: number, lunge: Config.LungeDef, now: number)
	local humanoid = best.humanoid
	if not humanoid then
		return
	end
	if z.lungeUntil and now < (z.lungeUntil :: number) then
		z.nextPath = now + 0.05
		if not z.lungeHit and distance < lunge.reach then
			z.lungeHit = true
			z.nextAttack = now + z.def.attackEvery -- (6.24 review: the leap's strike is its bite: one hit a leap)
			showAttack(z)
			Armour.hurt(humanoid, lunge.damage)
			Special.bit(z, best.player, humanoid) -- 10.x danger
		end
		return
	end
	z.lungeUntil = nil
	if distance < lunge.range[1] or distance > lunge.range[2] or now < (z.nextLunge or 0) or z.humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	local from = z.root.Position
	local to = Vector3.new(best.position.X - from.X, 0, best.position.Z - from.Z)
	if to.Magnitude < 1 then
		return
	end
	z.nextLunge = now + lunge.every * rng:NextNumber(0.85, 1.15)
	z.lungeUntil = now + lunge.time
	z.lungeHit = false
	z.nextPath = now + 0.05
	z.root.CFrame = CFrame.lookAt(from, from + to)
	-- (pushed for lunge.push s: a velocity set on the root alone would be taken back by its walk at once)
	local attachment = z.root:FindFirstChild("LeapAttachment")
	if not attachment then
		local made = Instance.new("Attachment")
		made.Name = "LeapAttachment"
		made.Parent = z.root
		attachment = made
	end
	local push = Instance.new("LinearVelocity")
	push.Name = "Leap"
	push.Attachment0 = attachment :: Attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	push.VectorVelocity = to.Unit * lunge.speed + Vector3.new(0, lunge.up, 0)
	push.MaxForce = math.max(1, z.root.AssemblyMass) * 4000
	push.Parent = z.root
	task.delay(lunge.push, function()
		push:Destroy()
	end)
	z.lunges = (z.lunges or 0) + 1
	z.model:SetAttribute("Lunge", z.lunges)
end

-- The bloater's fuse: it goes off `seconds` from now (never later than one burning already). `by`: who set it off (the
-- blast's kills are theirs). The Fuse attribute (the server time it goes off) shows the warning on the clients.
function Special.fuse(z: Zombie, seconds: number, by: Player?)
	if z.blasted or not z.def.blast then
		return
	end
	local now = os.clock()
	local at = Kinds.fuseLeft(z.fuseAt, now, seconds)
	z.blastBy = by or z.blastBy
	if z.fuseAt and at >= (z.fuseAt :: number) then
		return -- (one as soon or sooner is burning)
	end
	z.fuseAt = at
	z.model:SetAttribute("Fuse", workspace:GetServerTimeNow() + (at - now))
	task.delay(at - now, function()
		if z.fuseAt == at then
			Special.detonate(z)
		end
	end)
end

-- It goes off: dead (no reward when it blew itself up), blown apart, the blast round it. Nothing when its body is
-- gone (despawned, its run over) or in the safe zone (it fizzles).
function Special.detonate(z: Zombie)
	local blast = z.def.blast
	if z.blasted or not blast then
		return
	end
	z.blasted = true
	if not z.root.Parent then
		return
	end
	local at = z.root.Position
	if not z.dead then
		kill(z, nil, nil, "blast")
	end
	if isSafe(at) then
		z.model:SetAttribute("Fuse", nil)
		return
	end
	local boom = Instance.new("Explosion")
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.BlastRadius = blast.radius
	boom.Position = at
	boom.Parent = workspace
	z.model:Destroy()
	Special.blast(z, at, blast)
end

-- The blast at `at` (shared/ZombieKinds.luau blastShare): every other zombie (no armour helps; a bloater among them goes
-- off too: the chain) and the bodies on foot (hurt, thrown away) within its radius; never in the safe zone.
function Special.blast(z: Zombie, at: Vector3, blast: Config.BlastDef)
	local by = z.blastBy
	for _, other in table.clone(zombies) do
		if other.dead or other == z then
			continue
		end
		local offset = other.root.Position - at
		local share = Kinds.blastShare(blast, offset.Magnitude)
		if share > 0 then
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local push = (if flat.Magnitude > 0.1 then flat.Unit else Vector3.zero) * 45 + Vector3.new(0, 35, 0)
			Zombies.damage(other, blast.zombie * share, by, { push = push, cause = "splash" })
		end
	end
	for _, t in gatherTargets() do
		local offset = t.position - at
		local share = Kinds.blastShare(blast, offset.Magnitude)
		if share <= 0 then
			continue
		end
		if t.humanoid then
			Armour.hurt(t.humanoid, blast.player * share)
			Special.knock(t.player, t.humanoid, offset, blast.knock * share, blast.knockUp * share)
		end
	end
end

-- 6.24: a random kind from a kinds table for a spot (shared/ZombieKinds.luau weights: the night, the danger;
-- Config.ZombieTypes); a special kind at its MaxAlive comes as a walker. (10.6: no job's tier, no level, no Blood
-- Moon: the city's.)
function Zombies.pickKind(kinds: { [string]: number }, at: Vector3?, _owner: Player?): string
	local distance = if at then Vector3.new(at.X - DEPOT.X, 0, at.Z - DEPOT.Z).Magnitude else nil
	local weights = Kinds.weights(kinds, {
		night = DayNight.nightFactor(),
		danger = Kinds.danger(nil, distance),
		level = nil,
		bloodMoon = false,
	})
	local kind = DangerRules.pickKind(weights, rng:NextNumber())
	if Types.MaxAlive[kind] then
		local alive = 0
		for _, z in zombies do
			if z.kind == kind and not z.dead then
				alive += 1
			end
		end
		if Kinds.capped(kind, alive) then
			return "walker"
		end
	end
	return kind
end

-- ── Who notices whom ───────────────────────────────────────────────────────

-- The nearest target within reach.
local function nearestTarget(position: Vector3, targets: { Target }, reach: number): (Target?, number)
	local best: Target? = nil
	local bestDistance = reach
	for _, t in targets do
		local d = (t.position - position).Magnitude
		if d < bestDistance then
			best, bestDistance = t, d
		end
	end
	return best, bestDistance
end

-- A calm zombie notices a player on foot within Roam.aggro (or its own aggro).
local function noticed(position: Vector3, targets: { Target }, aggro: number?): (Target?, number)
	local best: Target? = nil
	local bestDistance = math.huge
	for _, t in targets do
		local reach = aggro or Roam.aggro
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
	if not isSafe(goal) then
		z.humanoid:MoveTo(Special.steer(z, position, goal)) -- (10.x danger: in a run's house, through its doorways)
	end
end

local nextSlow = 0 -- 4.2: the walk animations and the despawn check run 5 times a second, not every frame
-- 5.7: the targets' list is made at Config.Robust.Zombies.TouchEvery (20 Hz), not every frame; the list of zombies to
-- walk through is one table filled again each frame (no new table per frame).
local nextTouch = 0
local TOUCH_EVERY = Config.Robust.Zombies.TouchEvery
local targets: { Target } = {}
local walk: { Zombie } = {}

local function step()
	local now = os.clock()
	local slow = now >= nextSlow
	if slow then
		nextSlow = now + 0.2
	end
	if now >= nextTouch then
		nextTouch = now + TOUCH_EVERY
		targets = gatherTargets()
	end
	table.clear(walk)
	table.move(zombies, 1, #zombies, 1, walk)
	for _, z in walk do
		if z.dead then
			continue
		end
		local position = z.root.Position
		if slow then
			animate(z.model, z.root, z.humanoid.WalkSpeed > 20) -- a wandering runner walks
		end

		-- Too far from everybody: gone (never a run's own, nor a march's).
		if slow and (position.Y < -8 or not z.resident and not z.march and nearestPlayerDistance(position) > (if z.roamer then Roam.despawn else Horde.DespawnDistance)) then
			-- fallen off the world, or nobody around
			remove(z)
			z.model:Destroy()
			continue
		end
		if isSafe(position) then
			-- Wandered into the old safe zone: it burns.
			kill(z, nil, nil)
			continue
		end

		if z.fuseAt then
			-- 6.24: a bloater about to go off stands where it is, swelling
			if now >= z.nextPath then
				z.nextPath = now + 0.3
				z.humanoid:MoveTo(position)
			end
			continue
		end

		if now < z.nextPath then
			continue
		end
		z.nextPath = now + Horde.RepathEvery * rng:NextNumber(0.8, 1.2)

		-- Chase the nearest target.
		local best: Target?, bestDistance: number
		if roams(z) then
			if not z.hunting then
				-- Calm: shamble around its spot and look around now and then.
				z.nextPath = now + Roam.think * rng:NextNumber(0.8, 1.2)
				best, bestDistance = noticed(position, targets, z.aggro) -- (10.x danger: a run's inside zombie's own)
				if not best then
					wander(z, position, now)
					continue
				end
				wake(z)
			else
				best, bestDistance = nearestTarget(position, targets, Roam.chase)
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
			local march = z.march
			best, bestDistance = nearestTarget(position, targets, if march then MARCH_REACH elseif z.resident then 160 else 400)
			if not best then
				if march then
					-- 6.15: a march's zombie walks to its spot (the house's door) and waits round it; never into the safe zone
					z.nextPath = now + rng:NextNumber(1, 2)
					if not isSafe(march) and Vector3.new(march.X - position.X, 0, march.Z - position.Z).Magnitude > 8 then
						z.humanoid:MoveTo(Special.steer(z, position, Vector3.new(march.X + rng:NextNumber(-5, 5), position.Y, march.Z + rng:NextNumber(-5, 5))))
					end
				else
					z.nextPath = now + rng:NextNumber(2, 4) -- shamble around
					z.humanoid:MoveTo(position + Vector3.new(rng:NextNumber(-20, 20), 0, rng:NextNumber(-20, 20)))
				end
				continue
			end
		end
		if not best then
			continue
		end
		local lead = Vector3.new(best.velocity.X, 0, best.velocity.Z) * math.clamp(bestDistance / 60, 0, 0.8)
		local goal = best.position + lead
		if isSafe(goal) then
			continue
		end
		z.humanoid:MoveTo(Special.steer(z, position, goal)) -- (10.x danger: in a run's house, through its doorways)

		-- 6.24: a bloater next to you lights its fuse (it never bites); a runner leaps at you.
		local blast = z.def.blast
		if blast then
			if bestDistance < blast.trigger then
				Special.fuse(z, blast.fuse, nil)
			end
			continue
		end
		local lunge = z.def.lunge
		if lunge then
			Special.lunge(z, best, bestDistance, lunge, now)
		end
		-- Bite a player on foot.
		local humanoid = best.humanoid
		if humanoid and bestDistance < Horde.BiteReach * z.def.scale + 1 and now >= z.nextAttack then
			z.nextAttack = now + z.def.attackEvery
			showAttack(z) -- 6.16: the clients' lunge
			Armour.hurt(humanoid, z.def.damage)
			Special.bit(z, best.player, humanoid) -- 10.x danger: a bite on a run drops what you carry
			-- 6.24: a brute's blow throws you back
			local shove = z.def.shove
			if shove and now >= (z.nextShove or 0) then
				z.nextShove = now + shove.every
				Special.knock(best.player, humanoid, best.position - position, shove.speed, shove.up)
			end
		end
	end
end

function Zombies.all(): { Zombie }
	return zombies
end

function Zombies.start()
	-- Build the R15 bodies up front (it can take a moment), not in the middle of a fight. (10.6: the city's people,
	-- ZombieDef.ranged and jobOnly, never come: no bodies for them.)
	task.spawn(function()
		for kind, def in Config.Zombies do
			if def.ranged or def.jobOnly then
				continue
			end
			for variant = 1, ZombieStyle.count(kind) do
				template(kind, def, ZombieStyle.variant(kind, variant)) -- 6.16: every look
				task.wait() -- (a look a frame)
			end
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return Zombies
