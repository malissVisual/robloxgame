--!strict
-- 6.24, the special zombies on this client (the owner: "new zombies, so the fighting isn't always the same"): what
-- server/Zombies.luau tells through the bodies' attributes and the Knock remote. Cosmetic only (the damage is the
-- server's); the numbers are Config.ZombieTypes'.
--   * The bloater: its glowing boils (the Neon Boil1 …, NeckBoil: server/CharacterArt/Geometry.luau) pulse Bloater.Pulse
--     times a second while it walks; its fuse (the Fuse attribute: the server time it goes off) swells its Belly and
--     its Hump up to Swell × their size and the boils up to BoilSwell × theirs (so they stay on top of the belly),
--     flashes the boils from FlashHz to FlashEnd times a second (white at the end)
--     and hisses (a sound of the sheet pitched: client/Sounds.luau plays nothing when the sheet has none). The pose
--     (arched back, the arms out, trembling) is client/ZombieAnimator.luau's. Within Range of the camera, the nearest
--     Most of them (a burning fuse first), picked four times a second; one that leaves the pick gets its look back.
--   * The brute: a hit its plates took (the Clank attribute): a clink (a step's metal sound pitched up) and a spark on
--     its chest plate.
--   * The runner: its leap (the Lunge attribute): a shriek (a zombie voice pitched up).
--   * The Knock remote (a brute's blow, a blast): your body is thrown that way (a LinearVelocity on your root for
--     KnockTime s, so the walk cannot cancel it) and the camera shakes. Never in a seat.
-- The zombies come from the Zombies folder (ChildAdded / ChildRemoved: the ones that stream in and out too); only the
-- special kinds (Config.Zombies with a lunge, armour or a blast) are watched, each with its own attribute signals,
-- dropped when it goes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Sounds = require(script.Parent.Sounds)
local CameraRig = require(script.Parent.CameraRig)

local ZombieFx = {}

local Types = Config.ZombieTypes
local B = Types.Bloater
local player = Players.LocalPlayer
local PICK = 0.25 -- seconds between the picks of the bloaters animated
local PULSE_EVERY = 1 / 15 -- a walking bloater's boils are painted this often (a fuse's every frame)
local WHITE = Color3.new(1, 1, 1)
local SPARK = Color3.fromRGB(255, 226, 150)
local BOILS = { "Boil1", "Boil2", "Boil3", "Boil4", "Boil5", "NeckBoil" }
local SWELLS = { "Belly", "Hump" }

type Glow = { part: BasePart, color: Color3, dim: Color3, size: Vector3 }
type Swell = { part: BasePart, size: Vector3 }
local NO_GLOWS: { Glow } = {}
local NO_SWELLS: { Swell } = {}
type Watched = {
	model: Model,
	kind: string,
	links: { RBXScriptConnection },
	boils: { Glow }?, -- a bloater's, looked up when it is first animated
	swells: { Swell }?,
	fuseFrom: number?, -- its fuse, seen then (os.clock) …
	fuseTo: number?, -- … going off then
	flash: number, -- the flashing's phase (radians)
	painted: number, -- when its boils were last painted
	swollen: boolean, -- its Belly and Hump are not their own size now
	active: boolean,
	distance: number,
}

local watched: { [Model]: Watched } = {}
local active: { Watched } = {} -- the bloaters animated now
local order: { Watched } = {}
local started = false
local lastFrame = os.clock()

local function special(kind: string): boolean
	local def = Config.Zombies[kind]
	return def ~= nil and (def.lunge ~= nil or def.armour ~= nil or def.blast ~= nil)
end

local function partOf(model: Model, names: { string }): BasePart?
	for _, name in names do
		local found = model:FindFirstChild(name)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

local function camera(): Vector3?
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position else nil
end

-- A sound at a zombie within `range` of the camera.
local function soundAt(model: Model, name: string, volume: number, pitch: number, range: number)
	local at = partOf(model, { "UpperTorso", "HumanoidRootPart", "Torso" })
	local eye = camera()
	if at and eye and (at.Position - eye).Magnitude <= range then
		Sounds.playAt(name, at.Position, volume, pitch, range + 20)
	end
end

-- ── The bloater ────────────────────────────────────────────────────────────

local function lookUp(w: Watched)
	if w.boils then
		return
	end
	local boils: { Glow } = {}
	for _, name in BOILS do
		local part = w.model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(boils, { part = part, color = part.Color, dim = part.Color:Lerp(Color3.new(0, 0, 0), 0.55), size = part.Size })
		end
	end
	local swells: { Swell } = {}
	for _, name in SWELLS do
		local part = w.model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(swells, { part = part, size = part.Size })
		end
	end
	w.boils, w.swells = boils, swells
end

-- Its own look again (out of the pick, or its fuse gone).
local function restore(w: Watched)
	for _, g in w.boils or NO_GLOWS do
		g.part.Color = g.color
	end
	if w.swollen then
		for _, s in w.swells or NO_SWELLS do
			s.part.Size = s.size
		end
		for _, g in w.boils or NO_GLOWS do
			g.part.Size = g.size
		end
		w.swollen = false
	end
end

local function smooth(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

local function animate(w: Watched, now: number, dt: number)
	lookUp(w)
	local from, to = w.fuseFrom, w.fuseTo
	local fusing = from ~= nil and to ~= nil and now < to + 0.5
	if not fusing then
		if w.swollen then
			restore(w)
		end
		if now - w.painted < PULSE_EVERY then
			return
		end
		w.painted = now
		local glow = 0.5 + 0.5 * math.sin((now * B.Pulse + w.flash) * 2 * math.pi)
		for _, g in w.boils or NO_GLOWS do
			g.part.Color = g.dim:Lerp(g.color, glow)
		end
		return
	end
	local f = math.clamp((now - (from :: number)) / math.max(0.05, (to :: number) - (from :: number)), 0, 1)
	w.flash += dt * (B.FlashHz + (B.FlashEnd - B.FlashHz) * f) * 2 * math.pi
	local on = math.sin(w.flash) > 0
	for _, g in w.boils or NO_GLOWS do
		g.part.Color = if on and f > 0.6 then g.color:Lerp(WHITE, 0.75) elseif on then g.color else g.dim
	end
	local grow = smooth(f)
	for _, s in w.swells or NO_SWELLS do
		s.part.Size = s.size * (1 + (B.Swell - 1) * grow)
	end
	for _, g in w.boils or NO_GLOWS do
		g.part.Size = g.size * (1 + (B.BoilSwell - 1) * grow)
	end
	w.swollen = true
end

local function onFuse(w: Watched)
	local at = w.model:GetAttribute("Fuse")
	if type(at) ~= "number" then
		w.fuseFrom, w.fuseTo = nil, nil
		return
	end
	local now = os.clock()
	local fresh = w.fuseTo == nil
	w.fuseFrom = if fresh then now else w.fuseFrom
	w.fuseTo = now + math.max(0.05, at - workspace:GetServerTimeNow())
	if fresh then
		soundAt(w.model, "bus_brake", B.HissVolume, B.HissPitch, B.Range) -- (an air brake's hiss)
	end
end

-- The bloaters animated: a burning fuse first, then the nearest, at most B.Most within B.Range of the camera.
local function pick()
	local eye = camera()
	table.clear(order)
	if eye then
		for _, w in watched do
			if w.kind ~= "bloater" or not w.model.Parent then
				continue
			end
			local root = partOf(w.model, { "HumanoidRootPart", "UpperTorso" })
			w.distance = if root then (root.Position - eye).Magnitude else math.huge
			if w.distance <= B.Range then
				table.insert(order, w)
			end
		end
	end
	local now = os.clock()
	table.sort(order, function(a: Watched, b: Watched): boolean
		local fa = a.fuseTo ~= nil and now < (a.fuseTo :: number) + 0.5
		local fb = b.fuseTo ~= nil and now < (b.fuseTo :: number) + 0.5
		if fa ~= fb then
			return fa
		end
		return a.distance < b.distance
	end)
	for i = B.Most + 1, #order do
		order[i] = nil
	end
	for _, w in active do
		if w.active and not table.find(order, w) then
			w.active = false
			restore(w)
		end
	end
	table.clear(active)
	for _, w in order do
		w.active = true
		table.insert(active, w)
	end
end

local function step()
	local now = os.clock()
	local dt = math.clamp(now - lastFrame, 0, 0.1)
	lastFrame = now
	for _, w in active do
		if w.active and w.model.Parent then
			animate(w, now, dt)
		end
	end
end

-- ── The brute, the runner ──────────────────────────────────────────────────

local function onClank(w: Watched)
	local C = Types.Clank
	soundAt(w.model, "step_metal_a", C.Volume, C.Pitch, C.Range)
	local plate = partOf(w.model, { "ChestPlate", "UpperTorso", "Torso" })
	local eye = camera()
	if not plate or not eye or (plate.Position - eye).Magnitude > C.Range then
		return
	end
	local spark = Instance.new("Part")
	spark.Name = "ArmourSpark"
	spark.Shape = Enum.PartType.Ball
	spark.Size = Vector3.new(0.6, 0.6, 0.6)
	spark.Color = SPARK
	spark.Material = Enum.Material.Neon
	spark.Anchored = true
	spark.CanCollide, spark.CanQuery, spark.CanTouch = false, false, false
	spark.CastShadow = false
	local side = (math.random() - 0.5) * plate.Size.X * 0.6
	spark.CFrame = plate.CFrame * CFrame.new(side, (math.random() - 0.5) * plate.Size.Y * 0.6, -plate.Size.Z * 0.6)
	spark.Parent = workspace
	task.delay(0.08, function()
		spark:Destroy()
	end)
end

local function onLunge(w: Watched)
	local S = Types.Shriek
	soundAt(w.model, "zombie_a", S.Volume, S.Pitch, S.Range)
end

-- ── Watching the special ones ──────────────────────────────────────────────

local function unwatch(child: Instance)
	if not child:IsA("Model") then
		return
	end
	local w = watched[child]
	if not w then
		return
	end
	watched[child] = nil
	w.active = false
	for _, link in w.links do
		link:Disconnect()
	end
end

local function watch(child: Instance)
	if not child:IsA("Model") or watched[child] then
		return
	end
	local kind = child:GetAttribute("Zombie")
	if type(kind) ~= "string" or not special(kind) then
		return
	end
	local def = Config.Zombies[kind]
	local w: Watched = {
		model = child,
		kind = kind,
		links = {},
		boils = nil,
		swells = nil,
		fuseFrom = nil,
		fuseTo = nil,
		flash = math.random(),
		painted = -math.huge,
		swollen = false,
		active = false,
		distance = math.huge,
	}
	watched[child] = w
	if def.lunge then
		table.insert(w.links, child:GetAttributeChangedSignal("Lunge"):Connect(function()
			onLunge(w)
		end))
	end
	if def.armour then
		table.insert(w.links, child:GetAttributeChangedSignal("Clank"):Connect(function()
			onClank(w)
		end))
	end
	if def.blast then
		table.insert(w.links, child:GetAttributeChangedSignal("Fuse"):Connect(function()
			onFuse(w)
		end))
		if child:GetAttribute("Fuse") ~= nil then
			onFuse(w)
		end
	end
end

local function hook(folder: Instance)
	for _, child in folder:GetChildren() do
		watch(child)
	end
	folder.ChildAdded:Connect(watch)
	folder.ChildRemoved:Connect(unwatch)
end

-- ── The knock ──────────────────────────────────────────────────────────────

local mover: LinearVelocity? = nil

local function knock(velocity: any)
	if typeof(velocity) ~= "Vector3" or velocity ~= velocity then
		return
	end
	local push = velocity :: Vector3
	if push.Magnitude > 150 then
		push = push.Unit * 150
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.SeatPart ~= nil or humanoid.Health <= 0 then
		return
	end
	local attachment = root:FindFirstChild("ZombieKnockAttachment")
	if not attachment then
		local made = Instance.new("Attachment")
		made.Name = "ZombieKnockAttachment"
		made.Parent = root
		attachment = made
	end
	if mover then
		mover:Destroy()
	end
	local made = Instance.new("LinearVelocity")
	made.Name = "ZombieKnock"
	made.Attachment0 = attachment :: Attachment
	made.RelativeTo = Enum.ActuatorRelativeTo.World
	made.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	made.VectorVelocity = push
	made.MaxForce = math.max(1, root.AssemblyMass) * 5000
	made.Parent = root
	mover = made
	task.delay(Types.KnockTime, function()
		made:Destroy()
		if mover == made then
			mover = nil
		end
	end)
	CameraRig.shake(math.clamp(push.Magnitude / 120, 0.15, 0.6))
end

function ZombieFx.start()
	if started then
		return
	end
	started = true
	Net.get("Knock").OnClientEvent:Connect(knock)
	local folder = workspace:FindFirstChild("Zombies")
	if folder then
		hook(folder)
	else
		local link: RBXScriptConnection? = nil
		link = workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Zombies" then
				if link then
					link:Disconnect()
				end
				hook(child)
			end
		end)
	end
	RunService.Heartbeat:Connect(step)
	task.spawn(function()
		while true do
			task.wait(PICK)
			local ok, err = pcall(function()
				pick()
			end)
			if not ok then
				warn(`[ZombieFx] {err}`)
			end
		end
	end)
end

return ZombieFx
