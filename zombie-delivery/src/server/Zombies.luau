--!strict
-- The enemies: zombies and bandits, built in code (blocky bodies). Zombies chase the nearest car or player on foot;
-- bandits (Config.Zombies with ranged = true) keep their distance and shoot.
--
--   * a car going fast (Horde.RamMinSpeed or more) runs them over: damage = speed × ramPower, a survivor slows it down
--   * a slow or standing car gets grabbed: the zombie hangs on its side / back / roof (welded) and bites it until shot
--   * a player on foot gets bitten
--   * the safe zone (isSafe: the old city's middle, SAFE_HALF) is never entered, zombies hanging on a car die when it
--     drives in
--
-- Who goes after whom (10.6: only who calls Zombies.spawn brings any: a run's horde and its danger; the city's
-- residents, roamers round every player and roadblocks are gone):
--   * a roamer (Config.Horde.Roam's walk) shambles around its spot; it hunts a player who comes close, shoots nearby
--     or hits it, and calms down when it loses them. A march's zombie (Zombies.march: a run's horde) goes at its spot.
--   * people (ZombieDef.jobOnly: bandits, gunners, the base's soldiers) only go after players on a job
--     (Zombies.hunts, set by Main): without one they stand guard, never shoot, chase, grab or steal.
--   * 6.15, a mission's enemies (server/MissionEnemies.luau: Zombie.leash, the model's MissionRun attribute) guard
--     their spot: they go after somebody close (Config.Missions.Fixed Aggro) who stays within their leash of it, and
--     walk back to it when there is nobody. A kill sets Zombie.killed (the mission counts it); Zombies.despawn takes
--     one away without a kill. 6.15 review: they never
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
--   * Zombies.setFrenzy(speedOf, spared): every zombie's full speed through speedOf (the Blood Moon's, capped), but the
--     people's and the ones `spared` says (a mission's); nil: back to their own speed (Zombie.baseSpeed).
--   * Zombies.march(z, at): an event's zombie (the horde at the gates, a supply drop's guards): it never despawns, goes
--     after a player within Config.LiveEvents.Reach, else walks to `at` (never into the safe zone) and waits there;
--     nil lets it go (it roams on and despawns as a roamer does). Zombie.event says whose it is ("horde", "supply").
--   * 6.15 review: Zombies.trimRoamers(n) (calm roamers far from everybody go, to make room for the event's), Zombies.eventSpared
--     (players an event's zombie leaves alone: on a mission) and Zombies.retreat(z, at) (an ended event's zombie walks
--     away after nobody; server/LiveEvents.luau takes it away).
--
-- 6.24, the special zombies (the owner: "new zombies, so the fighting isn't always the same"; the numbers are
-- Config.Zombies' and Config.ZombieTypes', the rules shared/ZombieKinds.luau's; the looks and moves on the clients:
-- client/ZombieAnimator.luau, client/ZombieFx.luau):
--   * the runner (ZombieDef.lunge) leaps at a player on foot a few strides away (the Lunge attribute: the clients' dive
--     and shriek); its strike lands once a leap;
--   * the brute (armour) takes less from the front and from a small gun's round (Zombies.damage: ZombieKinds.armourShare;
--     a headshot, a shotgun, a blast, a car do it all; the Clank attribute: the clients' clink); its bite throws a player
--     on foot back (shove: the Knock remote), its blow on a car dents it hard and slows it (carDamage, carBump);
--   * the bloater (blast) never bites: next to you (or touching your car) it hisses and swells for blast.fuse s and goes
--     off; killed (with a cause: not burnt in the safe zone, not the admin's) it goes off blast.deathFuse s later. The
--     blast (an Explosion for the looks, the sound and the camera's shake) hurts every zombie round it (a chain: another
--     bloater goes off too; the kills are its killer's), the players on foot (through the vest, thrown away) and the
--     cars. The Fuse attribute (the server time it goes off) shows the warning on the clients;
--   * every random pick of a kind (a run's horde and its danger's) goes through Zombies.pickKind: the night (10.6:
--     never: DayNight.nightFactor 0), the danger (a job's tier from Zombies.tierOf; else how far from the old city's
--     depot, DEPOT), the player's level, and MaxAlive of a special kind in the server at most.
--   * a kill pays ZombieDef.xp XP on top (the money stays the "KillReward").
--
-- 10.x danger, a run's zombies (server/RunDanger.luau sets these; nothing changes without them):
--   * Zombies.steer(z, from, goal) -> Vector3?: where a zombie walking from `from` to `goal` steps now (a run's house:
--     its way through the doorways, shared/HouseRoute.luau); nil: straight at the goal, as ever
--   * Zombies.onBite(player, humanoid, z): a bite (or a runner's leap) landed on a player's or a buddy's body
--   * Zombie.aggro: studs a calm zombie notices a player on foot at (nil: Roam.aggro)
--   * a run's parked truck (its model's Config.Runs.Truck.Attribute) is nobody's target: never grabbed, never bitten

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local Joints = require(Shared.Joints)
local GunModels = require(Shared.GunModels)
local Vehicles = require(script.Parent.Vehicles)
local PlayerData = require(script.Parent.PlayerData)
local DayNight = require(script.Parent.DayNight) -- (10.6: nightFactor 0, the sandbox's day)
local Armour = require(script.Parent.Armour) -- 6.0: every bite and bullet on a player goes through the vest
local ZombieStyle = require(Shared.ZombieStyle) -- 6.16: the looks, the falls, the Hit attribute
local Kinds = require(Shared.ZombieKinds) -- 6.24: the special zombies' rules

-- 10.6 (the city's server/World.luau and shared/Map.luau went): the old road level (World.RoadTop: a road spot's
-- height), the old safe zone round the middle (Config.City.SafeHalf: |x|, |z| below it; nothing of the sandbox's
-- world is in it, it matters only if a horde ever gets there) and the old depot (Map.Depot: the special kinds' danger
-- grows with the distance from it, ZombieKinds.danger).
local ROAD_TOP = 0.4
local SAFE_HALF = 235
local DEPOT = Vector3.new(144, 0, -144)

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
local bump = Net.get("Bump")
local rewardRemote = Net.get("Reward")
Special.knockRemote = Net.get("Knock") -- 6.24
Special.knockedAt = {} :: { [Player]: number }

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
-- 6.15 review (server/LiveEvents.luau): the players a live event's zombies leave alone (on a mission: missions are
-- never touched).
Zombies.eventSpared = {} :: { [Player]: boolean }
-- 6.24: the danger of a player's job (its tier, 1 … 4; nil: none) for the special zombies' weights.
Zombies.tierOf = function(_player: Player): number?
	return nil
end
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
		local xp = z.def.xp -- 6.24: the special ones' XP
		if xp and xp > 0 then
			PlayerData.addXp(killer, xp)
		end
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
	-- 6.24: a bloater killed by something (a shot, a car, a punch, a blast: not burnt, not the admin's) goes off soon
	local blast = z.def.blast
	if blast and cause ~= nil and cause ~= "other" then
		Special.fuse(z, blast.deathFuse, killer)
	elseif blast then
		-- (6.24 review: the admin's KILL ALL / CLEAR, a mission's end, a plain death: a fuse already lit goes out too)
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

-- cause (3.1): "car" (run over), "splash" (a blast or a fire), "melee" (3.9); nil = a gun's hit. from (3.1): the gun fired from a car
-- seat ("cargun", "window"; Zombies.KillInfo). 6.24: pellets = the gun's pellets a shot (a shotgun's go through a
-- brute's plates); push = the way the hit travels (a plate takes the ones on its front). "other": the admin's (a bloater
-- does not go off).
export type HitInfo = { crit: boolean?, push: Vector3?, cause: string?, from: string?, pellets: number? }

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

-- Returns how many really appeared (no road spot, or the server's cap reached).
function Zombies.spawnAround(owner: Player, center: Vector3, heading: Vector3?, count: number, kinds: { [string]: number }): number
	local made = 0
	for _ = 1, count do
		local spot = Zombies.findSpot(center, heading)
		if spot and Zombies.spawn(Zombies.pickKind(kinds, spot, owner), spot, owner, false) then
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
		Zombies.spawn(Zombies.pickKind(kinds, at, owner), at + offset, owner, true)
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
	noiseAt[owner] = nil
	Special.knockedAt[owner] = nil -- 6.24
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
	local safe = isSafe(at)
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
	local leap = z.root:FindFirstChild("Leap") -- (6.24 review: a runner's leap must not drag the car it lands on)
	if leap then
		leap:Destroy()
	end
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
		if not isSafe(position) and car.owner:GetAttribute("AdminHidden") ~= true and not Special.parked(car) then
			table.insert(targets, { position = position, velocity = car.chassis.AssemblyLinearVelocity, car = car, player = car.owner })
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and rootPart and humanoid.Health > 0 and not humanoid.SeatPart and not isSafe(rootPart.Position) and player:GetAttribute("AdminHidden") ~= true then
			table.insert(targets, { position = rootPart.Position, velocity = rootPart.AssemblyLinearVelocity, humanoid = humanoid, player = player })
		end
	end
	-- 4.5: the admin's buddies (server/Buddy.luau), bitten and shot like players on foot.
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

-- A run's truck parked at its house (Config.Runs.Truck.Attribute): nobody's target, never grabbed.
function Special.parked(car: Vehicles.Car): boolean
	return car.model:GetAttribute(Config.Runs.Truck.Attribute) == true
end

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
-- Knock remote); at most every Types.KnockEvery s a player, never a seated one or a buddy.
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

-- It goes off: dead (no reward when it blew itself up; a mission counts it), blown apart, the blast round it. Nothing
-- when its body is gone (despawned, its mission over) or in the safe zone (it fizzles).
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
-- off too: the chain), the players on foot (through the vest, thrown away) and the cars (a dent, a jolt) within its
-- radius; never in the safe zone, never a player an event's zombie spares.
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
		if z.event and Zombies.eventSpared[t.player] then
			continue
		end
		local offset = t.position - at
		local share = Kinds.blastShare(blast, offset.Magnitude)
		if share <= 0 then
			continue
		end
		local car = t.car
		if car then
			local dent = Vehicles.damage(car, blast.car * share, "A bloater blew your car apart!", "blast")
			if dent > 0 then
				Zombies.onCarDamaged(car.owner, dent)
			end
			bump:FireClient(car.owner, blast.carBump)
		elseif t.humanoid then
			Armour.hurt(t.humanoid, blast.player * share)
			Special.knock(t.player, t.humanoid, offset, blast.knock * share, blast.knockUp * share)
		end
	end
end

-- 6.24: a random kind from a kinds table for a spot (shared/ZombieKinds.luau weights: the night, the danger, the level,
-- the Blood Moon; Config.ZombieTypes); a special kind at its MaxAlive comes as a walker. owner: whose job or area (its
-- tier and level; nil: the lowest level in the server).
function Zombies.pickKind(kinds: { [string]: number }, at: Vector3?, owner: Player?): string
	local tier: number? = nil
	local level: number? = nil
	if owner then
		local ok, value = pcall(Zombies.tierOf, owner)
		tier = if ok and type(value) == "number" then value else nil
		level = PlayerData.level(owner)
	else
		for _, player in Players:GetPlayers() do
			local each = PlayerData.level(player)
			level = if level then math.min(level :: number, each) else each
		end
	end
	local distance = if at then Vector3.new(at.X - DEPOT.X, 0, at.Z - DEPOT.Z).Magnitude else nil
	local weights = Kinds.weights(kinds, {
		night = DayNight.nightFactor(),
		danger = Kinds.danger(tier, distance),
		level = level,
		bloodMoon = false, -- (the city's live events' Blood Moon went)
	})
	local kind = Economy.pickKind(weights, rng:NextNumber())
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
	-- 6.24: a bloater touching a car: its fuse (it never hangs on one, never bites)
	local blast = z.def.blast
	if blast then
		Special.fuse(z, blast.fuse, nil)
		return
	end
	-- Brutes are too heavy to hang on a car, they hit it from the ground (6.24: ZombieDef.noLatch).
	if not z.def.noLatch and latch(z, car) then
		return
	end
	-- No room on the car: bite it from the ground.
	if now >= z.nextAttack then
		z.nextAttack = now + z.def.attackEvery
		showAttack(z) -- 6.16: the clients' lunge
		Zombies.onCarDamaged(car.owner, Vehicles.damage(car, z.def.carDamage or z.def.damage)) -- (6.20: what it took after Tough Body)
		local carBump = z.def.carBump -- 6.24: a brute's blow jolts the car
		if carBump then
			bump:FireClient(car.owner, carBump)
		end
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
local function noticed(position: Vector3, targets: { Target }, aggro: number?): (Target?, number)
	local best: Target? = nil
	local bestDistance = math.huge
	for _, t in targets do
		local reach = if t.car then math.min(Roam.aggroCar + flatSpeed(t.velocity) * Roam.aggroPerSpeed, Roam.aggroCarMax) else aggro or Roam.aggro
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
			elseif isSafe(car.chassis.Position) then
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
		if isSafe(position) then
			-- Wandered into the depot (pushed in by a car): it burns.
			kill(z, nil, nil)
			continue
		end

		-- Touching a car? (5.7: tested at 20 Hz, a car gone since the last list skipped; in between it keeps the answer)
		if touch then
			z.touching = false
			for _, c in cars do
				if not c.wrecked and c.chassis.Parent and not Special.parked(c) and touches(c, position, Horde.LatchReach * z.def.scale) then
					z.touching = true
					hitByCar(z, c, now)
					break
				end
			end
		end
		if z.touching or z.dead or z.car then
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
				best, bestDistance = noticed(position, targets, z.aggro) -- (10.x danger: a run's inside zombie's own)
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
					if not isSafe(march) and Vector3.new(march.X - position.X, 0, march.Z - position.Z).Magnitude > 8 then
						z.humanoid:MoveTo(Special.steer(z, position, Vector3.new(march.X + rng:NextNumber(-5, 5), position.Y, march.Z + rng:NextNumber(-5, 5))))
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
				if not isSafe(goal) then
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
					if not isSafe(goal) then
						z.humanoid:MoveTo(goal)
					end
				end
			end
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
end

return Zombies
