--!strict
-- 6.16, shooting and hits (the owner: "I want to upgrade the visuals and the feel"): what a shot looks like in the world on
-- this client. All of it is client-only, pooled and capped (Config.Shots; the pure rules in shared/ShotFeel.luau); the
-- server still decides every hit (server/Gun.luau).
--   * ShotFx.flash(at): the muzzle flash: a glowing ball, a small burst of flame and a real light for a blink (only
--     Flash.Lights of them at once, within Flash.LightRange of the camera; client/WorldFx.luau's night lights keep their
--     own budget, these come on top for 0.06 s). Every shot this client draws gets one: yours, and the other players'
--     from their replicated tracers (client/Shooting.luau; no new remote).
--   * ShotFx.eject(muzzle, kind, character): a shell casing ("brass" | "shell") thrown out to the gun's right, falling,
--     bouncing on the floor under it (one ray down when it is thrown, none a frame) and fading (Casings.Life; Casings.Max
--     of them, the oldest goes first). None on a phone (DeviceBudget.lite).
--   * ShotFx.shot(from, target, range, pellets, spread, exclude): your own shot's rounds, shown at once (the client's
--     guess along the same line; a shotgun's Impacts.Pellets of them, spread like the gun).
--   * ShotFx.impactAt(from, to): another shooter's round, where its tracer ends (within Impacts.Range of the camera,
--     Impacts.PerSecond of them).
--   Where a round stops: sparks on metal (a car too), sparks and dust on stone, chips off wood, dust on the ground,
--   glints on glass, a splash on water, and a small dark mark on a still wall or floor that fades (Impacts.Marks of them);
--   on a zombie or a bandit a small dark-red puff, never gore, and ShotFx.onEnemyHit (for the zombies' own reactions;
--   nothing here moves a zombie).
-- One RenderStepped step moves the flashes, the casings (workspace:BulkMoveTo) and the marks; it does nothing when none is
-- out.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ShotFeel = require(Shared.ShotFeel)
local DeviceBudget = require(script.Parent.DeviceBudget)

local ShotFx = {}

local S = Config.Shots
local F = S.Flash
local C = S.Casings
local I = S.Impacts
local player = Players.LocalPlayer
local rng = Random.new()

-- The client's own effects (client/Shooting.luau's tracers and pop-ups too): the aim rays and the camera skip it.
local folder = Instance.new("Folder")
folder.Name = "LocalEffects"
folder.Parent = workspace
ShotFx.folder = folder

-- Set by whoever wants it (the zombies' own flinch): a round shown hitting a zombie or a bandit on this client (yours:
-- mine, the client's guess; another shooter's: where the server's tracer ended). Nothing here moves the zombie.
ShotFx.onEnemyHit = nil :: ((enemy: Model, part: BasePart, position: Vector3, direction: Vector3, mine: boolean) -> ())?

local function effectPart(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	return p
end

local function sequence(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

-- A burst-only emitter (Emit; it never streams), its particles left in the world where they were made.
local function emitter(parent: Attachment, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Enabled = false
	e.LockedToPart = false
	e.EmissionDirection = Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, 360)
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

-- The rays: the server's bullets skip the players' cars and the dead bodies ("Bullet"); so do these when it is there.
local bulletGroup = false
pcall(function()
	bulletGroup = PhysicsService:IsCollisionGroupRegistered("Bullet")
end)
local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if bulletGroup then
		params.CollisionGroup = "Bullet"
	end
	return params
end
local shotParams = rayParams()
local otherParams = rayParams()
otherParams.FilterDescendantsInstances = { folder }
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude

local busy = 0 -- flashes, casings and marks out (the step does nothing at 0)

-- ── The muzzle flash ──────────────────────────────────────────────────────

type Flash = { ball: Part, light: PointLight, born: number, seen: boolean, live: boolean }
local flashes: { Flash } = {}
local flashRing = ShotFeel.ring(F.Pool)
local flame: ParticleEmitter? = nil
local flameAt: Attachment? = nil

local function makeFlashes()
	for _ = 1, F.Pool do
		local ball = effectPart("MuzzleFlash")
		ball.Shape = Enum.PartType.Ball
		ball.Material = Enum.Material.Neon
		ball.Color = Color3.fromRGB(255, 214, 130)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 110)
		light.Range = F.LightReach
		light.Brightness = F.LightBrightness
		light.Shadows = false
		light.Enabled = false
		light.Parent = ball
		ball.Parent = folder
		table.insert(flashes, { ball = ball, light = light, born = 0, seen = false, live = false })
	end
	local at = Instance.new("Attachment")
	at.Name = "MuzzleBurst"
	at.Parent = workspace.Terrain
	flameAt = at
	flame = emitter(at, {
		Texture = FIRE,
		EmissionDirection = Enum.NormalId.Front,
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(255, 140, 50)),
		LightEmission = 1,
		LightInfluence = 0,
		Size = sequence(0.75, 0.15),
		Transparency = sequence(0.05, 1),
		Lifetime = NumberRange.new(0.04, 0.08),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(14, 14),
		ZOffset = 0.5,
	})
end

-- A flash at `at` (the muzzle, looking where the barrel points).
function ShotFx.flash(at: CFrame)
	if #flashes == 0 then
		makeFlashes()
	end
	local slot = flashes[ShotFeel.take(flashRing)]
	local camera = workspace.CurrentCamera
	local near = camera ~= nil and (camera.CFrame.Position - at.Position).Magnitude <= F.LightRange
	local lit = 0
	for _, other in flashes do
		if other ~= slot and other.light.Enabled then
			lit += 1
		end
	end
	if not slot.live then
		busy += 1
	end
	slot.live = true
	slot.seen = false
	slot.born = os.clock()
	slot.ball.CFrame = at
	slot.ball.Size = Vector3.new(0.5, 0.5, 0.5)
	slot.ball.Transparency = 0
	slot.light.Brightness = F.LightBrightness
	slot.light.Enabled = near and lit < (if DeviceBudget.lite then F.LiteLights else F.Lights)
	local burst, burstAt = flame, flameAt
	if burst and burstAt and F.Burst > 0 then
		burstAt.WorldCFrame = at
		burst:Emit(F.Burst)
	end
end

local function stepFlashes(now: number)
	for _, slot in flashes do
		if slot.live then
			local k = (now - slot.born) / F.Seconds
			if k >= 1 and slot.seen then
				slot.live = false
				busy -= 1
				slot.ball.Transparency = 1
				slot.light.Enabled = false
			else
				-- (shown for one frame at least, however slow the frames come)
				slot.seen = true
				k = math.min(k, 0.95)
				slot.ball.Transparency = k
				slot.ball.Size = Vector3.one * (0.5 + 0.5 * k)
				slot.light.Brightness = F.LightBrightness * (1 - k)
			end
		end
	end
end

-- ── Shell casings ─────────────────────────────────────────────────────────

type Casing = { part: Part, fall: ShotFeel.Fall, born: number, live: boolean, axis: Vector3, spin: number, angle: number }
local casings: { Casing } = {}
local casingRing = ShotFeel.ring(C.Max)
local BRASS = Color3.fromRGB(214, 168, 72)
local SHELL = Color3.fromRGB(176, 40, 32)

-- A casing thrown out of the gun whose muzzle is `muzzle` (in a character's hand).
function ShotFx.eject(muzzle: Attachment, kind: string, character: Model?)
	if DeviceBudget.lite or C.Max <= 0 or not muzzle.Parent then
		return
	end
	local frame = muzzle.WorldCFrame
	local camera = workspace.CurrentCamera
	if not camera or (character ~= player.Character and (camera.CFrame.Position - frame.Position).Magnitude > C.Range) then
		return
	end
	-- The port: a little back from the muzzle toward the hand, on top.
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local port = if hand and hand:IsA("BasePart") then hand.Position:Lerp(frame.Position, 0.4) + frame.UpVector * 0.15 else frame.Position - frame.LookVector * 0.6
	local velocity = frame.RightVector * rng:NextNumber(C.Side[1], C.Side[2])
		+ Vector3.yAxis * rng:NextNumber(C.Up[1], C.Up[2])
		+ frame.LookVector * rng:NextNumber(-1.5, 0.5)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		velocity += root.AssemblyLinearVelocity
	end
	local exclude: { Instance } = { folder }
	if character then
		table.insert(exclude, character)
	end
	floorParams.FilterDescendantsInstances = exclude
	local below = workspace:Raycast(port, Vector3.new(0, -14, 0), floorParams)
	local shell = kind == "shell"
	local radius = if shell then 0.065 else 0.035
	local floor = (if below then below.Position.Y else port.Y - 6) + radius
	local index = ShotFeel.take(casingRing)
	local casing = casings[index]
	if not casing then
		local part = effectPart("Casing")
		part.Shape = Enum.PartType.Cylinder
		part.Parent = folder
		casing = { part = part, fall = { x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, floor = 0, resting = false }, born = 0, live = false, axis = Vector3.xAxis, spin = 0, angle = 0 }
		casings[index] = casing
	end
	assert(casing)
	if not casing.live then
		busy += 1
	end
	local part = casing.part
	part.Size = if shell then Vector3.new(0.3, 0.13, 0.13) else Vector3.new(0.2, 0.07, 0.07)
	part.Color = if shell then SHELL else BRASS
	part.Material = if shell then Enum.Material.SmoothPlastic else Enum.Material.Metal
	part.Transparency = 0
	local fall = casing.fall
	fall.x, fall.y, fall.z = port.X, port.Y, port.Z
	fall.vx, fall.vy, fall.vz = velocity.X, velocity.Y, velocity.Z
	fall.floor = floor
	fall.resting = false
	casing.live = true
	casing.born = os.clock()
	casing.axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit
	casing.spin = rng:NextNumber(0.5, 1) * C.Spin
	casing.angle = 0
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function stepCasings(now: number, dt: number)
	table.clear(moveParts)
	table.clear(moveFrames)
	for _, casing in casings do
		if casing.live then
			local age = now - casing.born
			if age >= C.Life then
				casing.live = false
				busy -= 1
				casing.part.Transparency = 1
			else
				local fall = casing.fall
				ShotFeel.fall(fall, dt)
				local at = Vector3.new(fall.x, fall.y, fall.z)
				local frame: CFrame
				if fall.resting then
					frame = CFrame.new(at) * CFrame.Angles(0, casing.angle, 0) -- lying on its side
				else
					casing.angle += casing.spin * dt
					frame = CFrame.new(at) * CFrame.fromAxisAngle(casing.axis, casing.angle)
				end
				table.insert(moveParts, casing.part)
				table.insert(moveFrames, frame)
				local fadeFrom = C.Life - C.Fade
				if age > fadeFrom then
					casing.part.Transparency = (age - fadeFrom) / C.Fade
				end
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ── Impacts ───────────────────────────────────────────────────────────────

type Spot = { at: Attachment, sparks: ParticleEmitter, dust: ParticleEmitter, chips: ParticleEmitter, splat: ParticleEmitter, splash: ParticleEmitter }
local spots: { Spot } = {}
local spotRing = ShotFeel.ring(I.Emitters)

local function makeSpots()
	for _ = 1, math.max(1, I.Emitters) do
		local at = Instance.new("Attachment")
		at.Name = "ImpactSpot"
		at.Parent = workspace.Terrain
		table.insert(spots, {
			at = at,
			sparks = emitter(at, {
				Texture = SPARK,
				Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 130, 40)),
				LightEmission = 1,
				LightInfluence = 0,
				Size = sequence(0.22, 0),
				Lifetime = NumberRange.new(0.15, 0.35),
				Speed = NumberRange.new(14, 28),
				SpreadAngle = Vector2.new(55, 55),
				Acceleration = Vector3.new(0, -60, 0),
				Drag = 3,
			}),
			dust = emitter(at, {
				Texture = SMOKE,
				Color = ColorSequence.new(Color3.fromRGB(176, 166, 150)),
				LightInfluence = 1,
				Size = sequence(0.4, 1.6),
				Transparency = sequence(0.35, 1),
				Lifetime = NumberRange.new(0.4, 0.8),
				Speed = NumberRange.new(3, 7),
				SpreadAngle = Vector2.new(35, 35),
				Acceleration = Vector3.new(0, 1.5, 0),
				Drag = 4,
				RotSpeed = NumberRange.new(-40, 40),
			}),
			chips = emitter(at, {
				Texture = SMOKE,
				Color = ColorSequence.new(Color3.fromRGB(118, 84, 52)),
				LightInfluence = 1,
				Size = sequence(0.18, 0.1),
				Lifetime = NumberRange.new(0.3, 0.5),
				Speed = NumberRange.new(8, 14),
				SpreadAngle = Vector2.new(40, 40),
				Acceleration = Vector3.new(0, -50, 0),
			}),
			-- Stylised, not gory: a soft dark-red puff that is gone in half a second.
			splat = emitter(at, {
				Texture = SMOKE,
				Color = ColorSequence.new(Color3.fromRGB(112, 16, 20), Color3.fromRGB(64, 10, 12)),
				LightInfluence = 1,
				Size = sequence(0.35, 1.1),
				Transparency = sequence(0.15, 1),
				Lifetime = NumberRange.new(0.25, 0.45),
				Speed = NumberRange.new(2, 6),
				SpreadAngle = Vector2.new(50, 50),
				Acceleration = Vector3.new(0, -8, 0),
				Drag = 5,
			}),
			splash = emitter(at, {
				Texture = SMOKE,
				Color = ColorSequence.new(Color3.fromRGB(222, 232, 240)),
				LightInfluence = 1,
				Size = sequence(0.3, 1.2),
				Transparency = sequence(0.3, 1),
				Lifetime = NumberRange.new(0.4, 0.6),
				Speed = NumberRange.new(8, 12),
				SpreadAngle = Vector2.new(20, 20),
				Acceleration = Vector3.new(0, -40, 0),
			}),
		})
	end
end

-- The attachment at `position`, its up (where the particles fly) along `up`.
local function place(spot: Spot, position: Vector3, up: Vector3)
	local side = up:Cross(if math.abs(up.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis).Unit
	spot.at.WorldCFrame = CFrame.fromMatrix(position, side, up)
end

-- The marks on the walls.
type Mark = { part: Part, born: number, live: boolean }
local marks: { Mark } = {}
local markRing = ShotFeel.ring(math.max(1, if DeviceBudget.lite then I.LiteMarks else I.Marks))
local MARK_COLOR = Color3.fromRGB(28, 25, 23)

local function mark(position: Vector3, normal: Vector3)
	local index = ShotFeel.take(markRing)
	local slot = marks[index]
	if not slot then
		local part = effectPart("ShotMark")
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.SmoothPlastic
		part.Color = MARK_COLOR
		part.Parent = folder
		slot = { part = part, born = 0, live = false }
		marks[index] = slot
	end
	assert(slot)
	if not slot.live then
		busy += 1
	end
	slot.live = true
	slot.born = os.clock()
	local size = I.MarkSize * rng:NextNumber(0.8, 1.2)
	local side = normal:Cross(if math.abs(normal.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis).Unit
	slot.part.Size = Vector3.new(0.04, size, size)
	slot.part.CFrame = CFrame.fromMatrix(position + normal * 0.025, normal, side) -- (a cylinder's axis is its X)
	slot.part.Transparency = 0.15
end

local function stepMarks(now: number)
	local fadeFrom = I.MarkLife - I.MarkFade
	for _, slot in marks do
		if slot.live then
			local age = now - slot.born
			if age >= I.MarkLife then
				slot.live = false
				busy -= 1
				slot.part.Transparency = 1
			elseif age > fadeFrom then
				slot.part.Transparency = 0.15 + 0.85 * (age - fadeFrom) / I.MarkFade
			end
		end
	end
end

-- What a round shows on what it hit: "flesh" (a zombie or a bandit: that model), "metal" (a car: no mark), "none" (a
-- person or an animal: nothing), else the material's (ShotFeel.surface). And whether a mark may stay on it (still).
local VEHICLES: { [string]: boolean } = { BanditCars = true, Cars = true, Traffic = true }
local function classify(instance: Instance, material: Enum.Material): (string, Model?, boolean)
	local node: Instance? = instance.Parent
	while node and node ~= workspace do
		if node:IsA("Model") then
			if node:GetAttribute("Zombie") ~= nil or node:GetAttribute("Bandit") ~= nil then
				return if node:FindFirstChildOfClass("Humanoid") then "flesh" else "metal", node :: Model, false
			end
			if node:FindFirstChildOfClass("Humanoid") then
				return "none", nil, false
			end
		elseif node.Parent == workspace then
			if VEHICLES[node.Name] then
				return "metal", nil, false
			elseif node.Name == "Animals" then
				return "none", nil, false
			end
		end
		node = node.Parent
	end
	local still = instance:IsA("Terrain") or (instance:IsA("BasePart") and instance.Anchored and instance.Transparency < 0.8)
	return ShotFeel.surface(material.Name), nil, still
end

local function hit(result: RaycastResult, direction: Vector3, mine: boolean)
	local instance = result.Instance
	local kind, enemy, still = classify(instance, result.Material)
	if kind == "none" then
		return
	end
	if #spots == 0 then
		makeSpots()
	end
	local spot = spots[ShotFeel.take(spotRing)]
	local position = result.Position
	if kind == "flesh" then
		place(spot, position, -direction) -- the puff comes back toward the shooter
		spot.splat:Emit(I.Splat)
		local onHit = ShotFx.onEnemyHit
		if onHit and enemy and instance:IsA("BasePart") then
			task.spawn(onHit, enemy, instance, position, direction, mine)
		end
		return
	end
	place(spot, position, result.Normal)
	if kind == "metal" then
		spot.sparks:Emit(I.Sparks)
	elseif kind == "stone" then
		spot.sparks:Emit(I.StoneSparks)
		spot.dust:Emit(math.ceil(I.Dust / 2))
	elseif kind == "wood" then
		spot.chips:Emit(I.Dust)
		spot.dust:Emit(math.ceil(I.Dust / 2))
	elseif kind == "glass" then
		spot.sparks:Emit(I.StoneSparks)
	elseif kind == "water" then
		spot.splash:Emit(I.Dust)
	else
		spot.dust:Emit(I.Dust) -- soft: the ground, grass, sand
	end
	if still and ShotFeel.marks(kind) then
		mark(position, result.Normal)
	end
end

local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local spread = math.rad(degrees)
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)).LookVector
end

-- Your own shot from `from` at `target` (client/Shooting.luau), its rounds shown at once: the client's guess along the
-- line the server shoots too (its own hits arrive a moment later). exclude: your character, your car.
function ShotFx.shot(from: Vector3, target: Vector3, range: number, pellets: number, spread: number, exclude: { Instance })
	local offset = target - from
	if offset.Magnitude < 0.5 then
		return
	end
	local direction = offset.Unit
	local skip = table.clone(exclude)
	table.insert(skip, folder)
	shotParams.FilterDescendantsInstances = skip
	local rounds = math.max(1, math.min(pellets, if DeviceBudget.lite then 2 else I.Pellets))
	for _ = 1, rounds do
		local d = if pellets > 1 then spreadDirection(direction, spread) else direction
		local result = workspace:Raycast(from, d * range, shotParams)
		if result then
			hit(result, d, true)
		end
	end
end

-- Another shooter's round (a tracer from the server: a player, a bandit, a buddy) that ended at `to`.
local others = ShotFeel.bucket(I.Burst)
function ShotFx.impactAt(from: Vector3, to: Vector3)
	local camera = workspace.CurrentCamera
	local offset = to - from
	if not camera or offset.Magnitude < 1 or (to - camera.CFrame.Position).Magnitude > DeviceBudget.range(I.Range) then
		return
	end
	if not ShotFeel.allow(others, os.clock(), I.PerSecond, I.Burst) then
		return
	end
	local direction = offset.Unit
	local result = workspace:Raycast(to - direction * 1.5, direction * 3, otherParams)
	if result then
		hit(result, direction, false)
	end
end

-- ── The step ──────────────────────────────────────────────────────────────

function ShotFx.start()
	RunService.RenderStepped:Connect(function(dt: number)
		if busy <= 0 then
			return
		end
		local now = os.clock()
		stepFlashes(now)
		stepCasings(now, math.min(dt, 0.1))
		stepMarks(now)
	end)
end

return ShotFx
