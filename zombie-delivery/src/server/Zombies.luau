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
--   * 6.15, a mission's enemies (server/MissionEnemies.luau: Zombie.leash, the model's MissionRun attribute) guard
--     their spot: they go after somebody close (Config.Missions.Fixed Aggro) who stays within their leash of it, and
--     walk back to it when there is nobody. A kill sets Zombie.killed (the mission counts it); Zombies.despawn takes
--     one away without a kill; Zombies.barricade is a roadblock's bandit car on its own. 6.15 review: they never
--     despawn here for distance (MissionEnemies parks them when their crew is far); Zombies.missionReserve keeps room
--     for them under Horde.MaxTotal (Zombies.spawn's `reserved`); the world's own people (resident bandits, the base's
--     soldiers) leave a mission's crew alone (Zombies.spares).
--
-- The limbs are animated on the clients (client/ZombieAnimator.luau), the server only moves the bodies.
--
-- 6.16, zombies with a life of their own (looks only: nothing here changes what an enemy does):
--   * every zombie wears one of its kind's looks (shared/ZombieStyle.luau, picked from its id: the model's Seed
--     attribute, which the clients read for its gait and voice too); a template is built once per kind and look;
--   * the Hit attribute marks a hit that did not kill (how: ZombieStyle.hitMark; at most every
--     Config.ZombieLife.HitEvery s a zombie, a hard one always) and Attack counts its bites and swipes: the clients'
--     flinch and lunge (client/ZombieAnimator.luau) and grunts (client/ZombieLife.luau);
--   * a death falls its own way (ZombieStyle.death): knocked back (a headshot, a punch), forward on its face, a spin,
--     a crumple where it stands; a car or a blast still flings the parts as before. The 6 s clean-up and the counting
--     are unchanged.
--
-- 6.15, the live events (server/LiveEvents.luau sets these; shared/LiveEvents.luau has the numbers' rules):
--   * Zombies.roamBoost: × the roamers wanted around every player (the Blood Moon's, on top of the night's).
--   * Zombies.setFrenzy(speedOf, spared): every zombie's full speed through speedOf (the Blood Moon's, capped), but the
--     people's and the ones `spared` says (a mission's); nil: back to their own speed (Zombie.baseSpeed).
--   * Zombies.march(z, at): an event's zombie (the horde at the gates, a supply drop's guards): it never despawns, goes
--     after a player within Config.LiveEvents.Reach, else walks to `at` (never into the safe zone) and waits there;
--     nil lets it go (it roams on and despawns as a roamer does). Zombie.event says whose it is ("horde", "supply").
--   * 6.15 review: Zombies.eventReserve (what the event still wants: the roamers stop that much lower),
--     Zombies.trimRoamers(n) (calm roamers far from everybody go, to make room for the event's), Zombies.eventSpared
--     (players an event's zombie leaves alone: on a mission) and Zombies.retreat(z, at) (an ended event's zombie walks
--     away after nobody; server/LiveEvents.luau takes it away).

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
local Armour = require(script.Parent.Armour) -- 6.0: every bite and bullet on a player goes through the vest
local ZombieStyle = require(Shared.ZombieStyle) -- 6.16: the looks, the falls, the Hit attribute

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
	seenSince: number?, -- 4.0.4, a bandit: since when it has a clear line to its target (it fires only after Horde.SpotTime)
	touching: boolean?, -- 5.7: it touched a car at the last car-touch test (Config.Robust.Zombies.TouchEvery)
	-- 6.15, a mission's enemy (server/MissionEnemies.luau): it guards `home` and goes after nobody farther than `leash`
	-- from it (leashTarget); `alertAt`: when it was last hit (it goes after the shooter within its leash a while)
	leash: number?,
	alertAt: number?,
	mission: string?, -- its mission run (the model's MissionRun attribute)
	killed: boolean?, -- it died (kill), not just went (a despawn): the mission counts it
	baseSpeed: number, -- 6.15: its own full speed (walkSpeed is this, or the Blood Moon's frenzy of it)
	march: Vector3?, -- 6.15: an event's zombie: where it walks to and waits (Zombies.march)
	event: string?, -- 6.15: the live event it belongs to ("horde", "supply")
	retreat: boolean?, -- 6.15 review: an ended event's zombie walking away (Zombies.retreat): after nobody
	-- 6.16 (looks only): its Hit and Attack attributes' counts, when it last showed a hit
	hits: number?,
	hitShown: number?,
	attacks: number?,
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
-- 6.15 review, set by Main (Jobs.onMission): a mission's crew. The world's own people (the resident bandits at their
-- camps, the Military Base's soldiers: placed by chance, never counted) leave them alone; a mission's enemies are its
-- plan's (the mission's own bandits still go after them: Zombies.hunts).
Zombies.spares = function(_player: Player): boolean
	return false
end
-- 6.15 review, set by server/MissionEnemies.luau: while a mission runs, every other enemy stops this many short of
-- Config.Horde.MaxTotal (Zombies.spawn's `reserved`: a mission's own may use them).
Zombies.missionReserve = 0
-- 4.5, set by server/Buddy.luau: more people on foot to go after (the admin's NPC buddies), each with the player it
-- belongs to (the people, ZombieDef.jobOnly, go after a buddy only when they go after its owner: Zombies.hunts).
export type ExtraTarget = { position: Vector3, velocity: Vector3, humanoid: Humanoid, player: Player }
Zombies.extraTargets = nil :: (() -> { ExtraTarget })?
-- 4.5, the admin tools (server/Admin.luau): FREEZE stops every enemy where it stands (no steps, no bites, no shots).
-- A player with the attribute AdminHidden is no target for anybody (on foot or in their car).
Zombies.frozen = false
-- 6.15, a live event (server/LiveEvents.luau): × the roamers wanted around every player (the Blood Moon's).
Zombies.roamBoost = 1
-- 6.15 review (server/LiveEvents.luau): the zombies a live event still wants to place (the roamers stop that much
-- lower under the cap), and the players its zombies leave alone (on a mission: missions are never touched).
Zombies.eventReserve = 0
Zombies.eventSpared = {} :: { [Player]: boolean }

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
	quietStates(humanoid)
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
-- Native infected rigs match the approved thumbnail; human bandits retain their existing bodies and guns.
-- Both keep the existing Animator, AI, scales and ragdoll path. Templates are built once per kind, then cloned.

local CharacterGeometry = require(script.Parent.CharacterArt.Geometry)
local CharacterRig = require(script.Parent.CharacterArt.Rig)

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

-- 6.16: one template per kind and look (shared/ZombieStyle.luau; the people have only their classic one).
local function template(kind: string, def: Config.ZombieDef, look: ZombieStyle.Look): Model?
	local key = kind .. "#" .. look.variant
	if templates[key] or noTemplate[kind] then
		return templates[key]
	end
	local s = def.scale
	local bandit = def.ranged == true
	local ok, result = pcall(function()
		if not bandit then
			return CharacterRig.build(CharacterGeometry.spec(kind, s, look.skin, look.shirt, look.pants, look.outfit))
		end
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
		elseif model:GetAttribute("CharacterArt") == nil then
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
	base += z.root.AssemblyLinearVelocity -- (its own run, or the car it hung on, carries on)
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

-- killer = nil: no reward (despawn, the safe zone). push = velocity for the flying parts. cause, headshot and from:
-- how (Zombies.onKillInfo).
local function kill(z: Zombie, killer: Player?, push: Vector3?, cause: string?, headshot: boolean?, from: string?)
	if z.dead then
		return
	end
	z.killed = true -- (6.15: a mission counts it, whoever or whatever killed it)
	remove(z)
	-- 6.16: how it falls (before the ragdoll: from where it stands)
	local style = ZombieStyle.death(z.id, cause, headshot, push ~= nil)
	local fall = if style ~= "flung" then deathMotion(z, style, push, killer, headshot) else nil
	z.humanoid.Health = 0
	ragdoll(z.model)
	-- The body collapses: collides only with the ground and buildings, never with cars or players.
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
	elseif z.leash then
		z.alertAt = os.clock() -- 6.15: a mission's enemy goes after the shooter within its leash a while
	end
	local health = z.humanoid.Health - amount
	if health <= 0 then
		kill(z, by, info and info.push, if info then info.cause or "gun" else "gun", info ~= nil and info.crit == true, info and info.from)
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

-- ── 6.15: the live events ──────────────────────────────────────────────────

local frenzySpeed: ((number) -> number)? = nil
local frenzySpared: ((Zombie) -> boolean)? = nil

-- Its full speed as the frenzy says (its own without one, for the people and the spared), at once.
local function frenzy(z: Zombie)
	local speedOf = frenzySpeed
	local speed = z.baseSpeed
	if speedOf and z.def.jobOnly ~= true then
		local spared = frenzySpared
		local ok, skip = true, false
		if spared then
			ok, skip = pcall(spared, z)
		end
		if ok and not skip then
			speed = speedOf(z.baseSpeed)
		end
	end
	if speed == z.walkSpeed then
		return
	end
	z.walkSpeed = speed
	z.humanoid.WalkSpeed = if roams(z) and not z.hunting then math.min(Roam.wanderSpeed, speed) else speed
end

-- The Blood Moon's frenzy on (speedOf: a zombie's own full speed → its speed now; spared: a zombie that keeps its own)
-- or off (nil): every living zombie now, every new one as it comes.
function Zombies.setFrenzy(speedOf: ((number) -> number)?, spared: ((Zombie) -> boolean)?)
	frenzySpeed, frenzySpared = speedOf, spared
	for _, z in zombies do
		if not z.dead then
			frenzy(z)
		end
	end
end

-- An event's zombie (`event`: "horde", "supply") walks to `at` and waits there (never despawning, going after a player
-- within Config.LiveEvents.Reach); `at` nil lets it go: it roams on like a roamer (and despawns like one).
function Zombies.march(z: Zombie, at: Vector3?, event: string?)
	if z.dead then
		return
	end
	if at then
		z.march = at
		z.event = event or z.event
		return
	end
	if z.march == nil then
		return
	end
	z.march = nil
	z.event = nil
	if z.def.jobOnly ~= true then
		z.roamer = true
		z.home = z.root.Position
		z.hunting = true -- (it calms down once it lost everybody, like a roamer)
		z.lostSince = nil
	end
end

-- 6.15 review: up to `count` calm roamers (not hunting, on no car, nobody's guard or event) go, the farthest from
-- every player first and none within 100 studs of one: room for a live event's zombies. Returns how many went.
function Zombies.trimRoamers(count: number): number
	if count <= 0 then
		return 0
	end
	local spots: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			table.insert(spots, rootPart.Position)
		end
	end
	local calmOnes: { { z: Zombie, far: number } } = {}
	for _, z in zombies do
		if z.dead or not z.roamer or z.resident or z.hunting or z.car or z.march or z.leash then
			continue
		end
		local far = math.huge
		for _, at in spots do
			far = math.min(far, (z.root.Position - at).Magnitude)
		end
		if far >= 100 then
			table.insert(calmOnes, { z = z, far = far })
		end
	end
	table.sort(calmOnes, function(a, b)
		return a.far > b.far
	end)
	local gone = 0
	for _, entry in calmOnes do
		if gone >= count then
			break
		end
		Zombies.despawn(entry.z)
		gone += 1
	end
	return gone
end

-- 6.15 review: an ended event's zombie walks away to `at` after nobody (server/LiveEvents.luau takes it away once
-- nobody is near or its time is up).
function Zombies.retreat(z: Zombie, at: Vector3)
	if z.dead then
		return
	end
	z.march = at
	z.retreat = true
	z.hunting = false
	z.lostSince = nil
	z.guard = false
	z.humanoid.WalkSpeed = z.walkSpeed
end

-- roamer = one of the zombies around a player without a job (Config.Horde.Roam): it wanders until it notices you.
-- 6.15 review: reserved = a mission's own (server/MissionEnemies.luau): it may use Zombies.missionReserve, the others not.
function Zombies.spawn(kind: string, at: Vector3, owner: Player?, guard: boolean?, resident: boolean?, roamer: boolean?, reserved: boolean?): Zombie?
	if #zombies >= Horde.MaxTotal - (if reserved then 0 else Zombies.missionReserve) then
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
		baseSpeed = humanoid.WalkSpeed,
	}
	frenzy(z) -- 6.15: a Blood Moon's speed (nothing without one)
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

-- 6.15: one of them gone without dying (a mission's enemy nobody is near, or its mission over: server/MissionEnemies.luau).
function Zombies.despawn(z: Zombie)
	if z.dead then
		return
	end
	remove(z)
	z.model:Destroy()
end

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
		z.leash = nil -- (6.15: a mission's enemy left behind is an ordinary one now; MissionEnemies takes them away first)
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

local spared: { [Player]: boolean } = {} -- 6.15 review: Zombies.spares (a mission's crew), asked with `hunted`

local function refreshHunted(now: number)
	if now < nextHuntCheck then
		return
	end
	nextHuntCheck = now + 0.25
	table.clear(hunted)
	table.clear(spared)
	for _, player in Players:GetPlayers() do
		local ok, result = pcall(Zombies.hunts, player)
		hunted[player] = ok and result == true
		local fine, spare = pcall(Zombies.spares, player)
		spared[player] = fine and spare == true
	end
end

-- Do the people (jobOnly) go after this player: the hunted, but a resident never after a mission's crew (6.15 review)?
local function huntedBy(z: Zombie, player: Player): boolean
	return hunted[player] == true and not (z.resident and spared[player] == true)
end

local function gatherTargets(): { Target }
	local targets: { Target } = {}
	for _, car in Vehicles.all() do
		local position = car.chassis.Position
		if not World.isSafe(position) and car.owner:GetAttribute("AdminHidden") ~= true then
			table.insert(targets, { position = position, velocity = car.chassis.AssemblyLinearVelocity, car = car, player = car.owner })
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and rootPart and humanoid.Health > 0 and not humanoid.SeatPart and not World.isSafe(rootPart.Position) and player:GetAttribute("AdminHidden") ~= true then
			table.insert(targets, { position = rootPart.Position, velocity = rootPart.AssemblyLinearVelocity, humanoid = humanoid, player = player })
		end
	end
	-- 4.5: the admin's buddies (server/Buddy.luau), bitten and shot like players on foot.
	local extra = Zombies.extraTargets
	if extra then
		local ok, list = pcall(extra)
		if ok then
			for _, t in list do
				if not World.isSafe(t.position) then
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

nearestPlayerDistanceFn = nearestPlayerDistance

-- Is the zombie touching this car? (car space box test)
local function touches(car: Vehicles.Car, position: Vector3, reach: number): boolean
	local p = car.chassis.CFrame:PointToObjectSpace(position)
	local size = car.size
	return math.abs(p.X) < size.X / 2 + reach and math.abs(p.Z) < size.Z / 2 + reach and p.Y > -6 and p.Y < size.Y + 4
end

local function hitByCar(z: Zombie, car: Vehicles.Car, now: number)
	local speed = Vehicles.ramSpeed(car)
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
			-- Something big: the car bounces off it and takes a dent (6.7: × the Ram Plow's guard, Economy.ramGuard).
			bump:FireClient(car.owner, Horde.RamSlowdown)
			-- (6.20: "ram": ★ Stuntman's car takes nothing, Tough Body less: what it really took is told)
			local dent = Vehicles.damage(car, health * Horde.RamSelfDamage * car.stats.ramGuard, nil, "ram")
			if dent > 0 then
				Zombies.onCarDamaged(car.owner, dent)
			end
			z.root.AssemblyLinearVelocity = velocity * 0.6 + Vector3.new(0, 15, 0)
		end
		return
	end
	if z.def.ranged or car.owner:GetAttribute("AdminHidden") == true then
		return -- bandits do not grab cars, they shoot them (4.5: nobody touches an admin's hidden car)
	end
	if z.def.jobOnly and not huntedBy(z, car.owner) then
		return -- a soldier leaves the car of somebody without a job alone (6.15 review: a resident one a mission's too)
	end
	-- Brutes are too heavy to hang on a car, they hit it from the ground.
	if z.kind ~= "brute" and latch(z, car) then
		return
	end
	-- No room on the car: bite it from the ground.
	if now >= z.nextAttack then
		z.nextAttack = now + z.def.attackEvery
		showAttack(z) -- 6.16: the clients' lunge
		Zombies.onCarDamaged(car.owner, Vehicles.damage(car, z.def.damage)) -- (6.20: what it took after Tough Body)
	end
end

local tracer = Net.get("Tracer")
local BANDIT_TRACER = Color3.fromRGB(255, 80, 60)

-- 4.0.4: does this bandit see its target: a clear line from its head (not from a point in front of it, which can be on
-- the far side of a wall it stands at) to the target, nothing solid in between?
-- (5.7: one RaycastParams for every look, its filter the Zombies folder; set again only if that folder is missing)
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
local sightFilter: Instance? = nil
local function seesTarget(z: Zombie, target: Target): (boolean, Vector3, Vector3)
	local from = z.root.Position + Vector3.new(0, 1.2 * z.def.scale, 0)
	local aim = target.position + Vector3.new(0, 1.5, 0)
	local folder = workspace:FindFirstChild("Zombies")
	local filter: Instance = folder or z.model
	if filter ~= sightFilter or not folder then
		sightFilter = filter
		sightParams.FilterDescendantsInstances = { filter }
	end
	local result = workspace:Raycast(from, aim - from, sightParams)
	local targetModel: Instance? = if target.car then target.car.model elseif target.humanoid then target.humanoid.Parent else nil
	return result == nil or (targetModel ~= nil and result.Instance:IsDescendantOf(targetModel)), from, aim
end

-- A bandit's shot: needs a clear line, hits less often at a fast target.
function shoot(z: Zombie, target: Target)
	local position = z.root.Position
	local flat = Vector3.new(target.position.X, position.Y, target.position.Z)
	z.root.CFrame = CFrame.lookAt(position, flat)
	local clear, from, aim = seesTarget(z, target)
	if not clear then
		return -- no clear line of fire
	end
	local speed = Vector3.new(target.velocity.X, 0, target.velocity.Z).Magnitude
	local chance = (z.def.accuracy or 0.6) * math.clamp(1 - speed / 120, 0.3, 1)
	local damage = z.def.shotDamage or 6
	if rng:NextNumber() < chance then
		tracer:FireAllClients(from, aim, BANDIT_TRACER, 0)
		local car = target.car
		if car then
			Zombies.onCarDamaged(car.owner, Vehicles.damage(car, damage, "The bandits shot your car to pieces!"))
		elseif target.humanoid then
			Armour.hurt(target.humanoid, damage)
		end
	else
		local miss = aim + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-2, 4), rng:NextNumber(-6, 6))
		tracer:FireAllClients(from, miss, BANDIT_TRACER, 0)
	end
end

-- ── Roadblocks ─────────────────────────────────────────────────────────────

type Roadblock = { model: Model, owner: Player, born: number }
local roadblocks: { Roadblock } = {}

-- A bandit car across one lane (`lane` -1 | 1: which side of the road's middle) and two barrels. at = on the road,
-- along = the road's direction. Returns the model (in the Effects folder; the caller keeps or cleans it), its middle
-- (y 0) and the way across the road. 6.15: a mission's roadblock (server/MissionEnemies.luau) is one of these too.
function Zombies.barricade(at: Vector3, along: Vector3, lane: number): (Model, Vector3, Vector3)
	local model = Instance.new("Model")
	model.Name = "Roadblock"
	local side = Vector3.new(-along.Z, 0, along.X)
	-- (6.10: the frame on the ground, y 0: the pieces add World.RoadTop themselves; `at` comes at road height and
	-- the car and the barrels floated RoadTop over the road)
	local center = Vector3.new(at.X, 0, at.Z) + side * lane * 7
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
	return model, center, side
end

-- A bandit car across one lane and bandits behind it. at = on the road, along = the road's direction.
function Zombies.roadblock(owner: Player, at: Vector3, along: Vector3, count: number)
	local model, center, side = Zombies.barricade(at, along, if rng:NextNumber() < 0.5 then -1 else 1)
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

-- 6.15 review: an event's zombie's target: the nearest within reach, never a player on a mission (Zombies.eventSpared)
-- nor anybody once it retreats.
local function eventTarget(z: Zombie, position: Vector3, targets: { Target }, reach: number): (Target?, number)
	local best: Target? = nil
	local bestDistance = if z.retreat then 0 else reach
	for _, t in targets do
		if Zombies.eventSpared[t.player] then
			continue
		end
		local d = (t.position - position).Magnitude
		if d < bestDistance then
			best, bestDistance = t, d
		end
	end
	return best, bestDistance
end

-- The nearest target within reach. people = only the players they go after (Zombies.hunts); 6.15 review: `resident`
-- (the world's own people) not a mission's crew (Zombies.spares).
local function nearestTarget(position: Vector3, targets: { Target }, reach: number, people: boolean, resident: boolean?): (Target?, number)
	local best: Target? = nil
	local bestDistance = reach
	for _, t in targets do
		if people and (not hunted[t.player] or (resident and spared[t.player])) then
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

local nextSlow = 0 -- 4.2: the walk animations and the despawn check run 5 times a second, not every frame
-- 5.7: the targets' list and the car-touch test run at Config.Robust.Zombies.TouchEvery (20 Hz), not every frame;
-- the list of zombies to walk through is one table filled again each frame (no new table per frame).
local nextTouch = 0
local TOUCH_EVERY = Config.Robust.Zombies.TouchEvery
local targets: { Target } = {}
local cars: { Vehicles.Car } = {}
local walk: { Zombie } = {}

-- 6.15, a mission's enemy (z.leash, server/MissionEnemies.luau) guards its spot: it goes after the nearest target
-- within Config.Missions.Fixed.Aggro of it (a bandit or a gunner: its range + 40; hit a moment ago: its whole leash)
-- while that target is within its leash of the spot. The people (jobOnly) still only after the hunted.
local MissionFixed = Config.Missions.Fixed
local function leashTarget(z: Zombie, position: Vector3, now: number): (Target?, number)
	local leash = z.leash or 0
	local reach = if z.def.ranged then (z.def.range or 0) + 40 else MissionFixed.Aggro
	if z.alertAt and now - z.alertAt < MissionFixed.AlertTime then
		reach = math.max(reach, leash)
	end
	local home = z.home
	local best: Target? = nil
	local bestDistance = reach
	for _, t in targets do
		if z.def.jobOnly and not hunted[t.player] then
			continue
		end
		local d = (t.position - position).Magnitude
		if d < bestDistance and Vector3.new(t.position.X - home.X, 0, t.position.Z - home.Z).Magnitude <= leash then
			best, bestDistance = t, d
		end
	end
	return best, bestDistance
end

-- … and with nobody to go after it walks back to its spot and waits there.
local function homeward(z: Zombie, position: Vector3, now: number)
	z.seenSince = nil
	if Vector3.new(position.X - z.home.X, 0, position.Z - z.home.Z).Magnitude > 6 then
		z.humanoid:MoveTo(z.home)
	else
		z.humanoid:MoveTo(position)
		z.nextPath = now + rng:NextNumber(0.8, 1.6)
	end
end

local function step()
	local now = os.clock()
	local slow = now >= nextSlow
	if slow then
		nextSlow = now + 0.2
	end
	local touch = now >= nextTouch
	if touch then
		nextTouch = now + TOUCH_EVERY
	end
	if Zombies.frozen then
		-- 4.5, the admin's FREEZE: everybody stands where they are (a step order to their own spot, 5 times a second).
		if slow then
			for _, z in zombies do
				if not z.dead and not z.car then
					z.humanoid:MoveTo(z.root.Position)
				end
			end
		end
		return
	end
	refreshHunted(now)
	if touch then
		targets = gatherTargets()
		cars = Vehicles.all()
	end
	table.clear(walk)
	table.move(zombies, 1, #zombies, 1, walk)
	for _, z in walk do
		if z.dead then
			continue
		end
		local position = z.root.Position
		if slow and not z.car then
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
			elseif (z.def.jobOnly and not huntedBy(z, car.owner)) or car.owner:GetAttribute("AdminHidden") == true then
				-- The job is over: a soldier lets go (4.5: everybody lets go of an admin's HIDDEN car).
				unlatch(z)
				z.humanoid.PlatformStand = false
			elseif now >= z.nextAttack then
				z.nextAttack = now + z.def.attackEvery
				showAttack(z) -- 6.16
				Zombies.onCarDamaged(car.owner, Vehicles.damage(car, z.def.damage))
			end
			continue
		end

		-- Too far from everybody: gone. (6.15 review: a mission's own, z.leash, only by server/MissionEnemies.luau: when its
		-- crew is far, so the alive cap follows them and nothing comes back and goes again every tick)
		if slow and (position.Y < -8 or not z.resident and not z.march and not z.leash and nearestPlayerDistance(position) > (if z.roamer then Roam.despawn else Horde.DespawnDistance)) then
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

		-- Touching a car? (5.7: tested at 20 Hz, a car gone since the last list skipped; in between it keeps the answer)
		if touch then
			z.touching = false
			for _, c in cars do
				if not c.wrecked and c.chassis.Parent and touches(c, position, Horde.LatchReach * z.def.scale) then
					z.touching = true
					hitByCar(z, c, now)
					break
				end
			end
		end
		if z.touching or z.dead or z.car then
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
		if z.leash then
			-- 6.15: a mission's enemy guards its spot (leashTarget), else back to it
			best, bestDistance = leashTarget(z, position, now)
			if not best then
				homeward(z, position, now)
				continue
			end
		elseif roams(z) then
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
			local march = z.march
			local reach = if ranged then range + 40 elseif march then Config.LiveEvents.Reach elseif z.guard then 90 elseif z.resident then 160 else 400
			if march then
				best, bestDistance = eventTarget(z, position, targets, reach) -- (6.15 review: missions spared)
			else
				best, bestDistance = nearestTarget(position, targets, reach, z.def.jobOnly == true, z.resident)
			end
			if not best then
				if z.def.jobOnly then
					standGuard(z, position, now)
				elseif march then
					-- 6.15: an event's zombie walks to its spot (the gate, the crate) and waits round it; never into the safe zone
					z.nextPath = now + rng:NextNumber(1, 2)
					if not World.isSafe(march) and Vector3.new(march.X - position.X, 0, march.Z - position.Z).Magnitude > 8 then
						z.humanoid:MoveTo(Vector3.new(march.X + rng:NextNumber(-5, 5), position.Y, march.Z + rng:NextNumber(-5, 5)))
					end
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
				z.seenSince = nil
				local goal = position + (best.position - position).Unit * (bestDistance - range * 0.6)
				if not World.isSafe(goal) then
					z.humanoid:MoveTo(goal)
				end
			elseif seesTarget(z, best) then
				z.humanoid:MoveTo(position)
				-- Right next to a car: they grab what they can from the cargo.
				local targetCar = best.car
				if targetCar and bestDistance < 14 then
					Zombies.onSteal(targetCar.owner, Config.BanditCar.StealPerSecond * Horde.RepathEvery)
				end
				-- 4.0.4: it fires only once it has had you in sight a moment (no snap shots through a doorway).
				z.seenSince = z.seenSince or now
				if now >= z.nextAttack and now - (z.seenSince :: number) >= Horde.SpotTime then
					z.nextAttack = now + (z.def.fireEvery or 1.5) * rng:NextNumber(0.85, 1.15)
					shoot(z, best)
				end
			else
				-- 4.0.4: a wall in the way: no shots into it. Move round for a line: closer, and a step to the side.
				z.seenSince = nil
				local toward = best.position - position
				local flatToward = Vector3.new(toward.X, 0, toward.Z)
				if flatToward.Magnitude > 1 then
					local dir = flatToward.Unit
					local side = Vector3.new(-dir.Z, 0, dir.X) * (if z.id % 2 == 0 then 1 else -1)
					local goal = position + dir * math.min(12, flatToward.Magnitude * 0.5) + side * 10
					if not World.isSafe(goal) then
						z.humanoid:MoveTo(goal)
					end
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
			showAttack(z) -- 6.16: the clients' lunge
			Armour.hurt(humanoid, z.def.damage)
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
		if #zombies >= Horde.MaxTotal - Roam.reserve - Zombies.eventReserve then
			return -- the rest is for the jobs' waves (6.15 review: and what a live event still wants)
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
		local want = math.floor(base * night * Zombies.roamBoost + 0.5) -- (6.15: a Blood Moon's more)
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
			for variant = 1, ZombieStyle.count(kind) do
				template(kind, def, ZombieStyle.variant(kind, variant)) -- 6.16: every look
				task.wait() -- (a look a frame)
			end
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
