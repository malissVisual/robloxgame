--!strict
-- THE MAGE'S BODY LANGUAGE (client side, 60 fps). The server only moves the mage (position, lean) and tells, in
-- attributes on its model, what it is doing: `Glide` (0 … 1, floating while it moves), `Cast` ("kind|duration|hand")
-- with `CastId` (a new cast), `Blink` (a teleport happened). This module poses the R15 joints of every Mage model
-- in the world procedurally (no animation assets): a living idle (breathing, the head looking around), the glide
-- (the legs dangle and "breathe", the arms open, the body sways), one gesture per spell kind (a bolt is thrust
-- from alternating hands with a twist of the torso; an area spell raises both arms and slams them down; a chain
-- sweeps the arm across; a knockback spins the whole body with the arms out; a barrier / heal raises both arms
-- slowly; a pull drags the hands back) and an AURA: shards orbiting the mage (more and faster with the level and
-- while it glides) and a glowing disc under it. Everything scales with the model.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Levels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Levels"))
local Wizards = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Wizards"))

local MageAnimator = {}

local JOINTS = { "Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftWrist", "RightWrist", "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle" }
local RECOVER = 0.4 -- seconds a gesture takes to settle after the spell fired
local RECOVER_BOLT = 0.6 -- the bolt's throw holds its stretch longer (big, readable)

type Cast = { kind: string, duration: number, hand: string, startedAt: number }
type Shard = { part: Part, angle: number, height: number, speed: number }
type Rig = {
	model: Model,
	joints: { [string]: Motor6D },
	base: { [string]: CFrame },
	phase: number,
	castId: number,
	cast: Cast?,
	blink: number,
	blinkAt: number,
	shards: { Shard },
	disc: Part?,
	folder: Folder,
	glideShown: number,
}
local rigs: { [Model]: Rig } = {}
local fxFolder: Folder? = nil

local function fx(): Folder
	if not fxFolder or not fxFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "MageAuras"
		f.Parent = workspace
		fxFolder = f
	end
	return fxFolder :: Folder
end

local function neon(size: Vector3, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Parent = fx()
	return p
end

-- Picks a Mage model up when it appears (its joints and their rest C0s).
local function adopt(model: Model)
	if rigs[model] then
		return
	end
	local joints: { [string]: Motor6D } = {}
	local base: { [string]: CFrame } = {}
	for _, name in JOINTS do
		local joint = model:FindFirstChild(name, true)
		if joint and joint:IsA("Motor6D") then
			joints[name] = joint
			base[name] = joint.C0
		end
	end
	if not joints.Waist then
		return -- a block model or a statue
	end
	rigs[model] = {
		model = model,
		joints = joints,
		base = base,
		phase = math.random() * math.pi * 2,
		castId = (model:GetAttribute("CastId") :: number?) or 0,
		cast = nil,
		blink = (model:GetAttribute("Blink") :: number?) or 0,
		blinkAt = -10,
		shards = {},
		disc = nil,
		folder = fx(),
		glideShown = 0,
	}
end

local function drop(rig: Rig)
	for _, s in rig.shards do
		s.part:Destroy()
	end
	if rig.disc then
		rig.disc:Destroy()
	end
	rigs[rig.model] = nil
end

-- Every half second: find the Mage models in the world, forget the gone ones.
task.spawn(function()
	while true do
		local plots = workspace:FindFirstChild("Plots")
		if plots then
			for _, d in plots:GetDescendants() do
				if d:IsA("Model") and d:GetAttribute("Class") == "Mage" and not rigs[d] then
					adopt(d)
				end
			end
		end
		for model, rig in rigs do
			if not model.Parent or not model:IsDescendantOf(workspace) then
				drop(rig)
			end
		end
		task.wait(0.5)
	end
end)

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function outBack(t: number): number
	t = math.clamp(t, 0, 1)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- The gesture of a spell kind at progress `w` (0 … 1 while winding up) / `r` (1 … 0 settling after the release),
-- for the casting hand `hand` ("L" | "R"). Adds angle offsets into `o` (per joint: x pitch, y yaw, z roll).
local function gesture(o: { [string]: Vector3 }, kind: string, w: number, r: number, hand: string)
	local function add(name: string, x: number, y: number, z: number)
		local v = o[name] or Vector3.zero
		o[name] = v + Vector3.new(x, y, z)
	end
	local side = if hand == "L" then 1 else -1 -- roll sign: the left arm opens to +z, the right to -z
	local arm = if hand == "L" then "LeftShoulder" else "RightShoulder"
	local other = if hand == "L" then "RightShoulder" else "LeftShoulder"
	local elbow = if hand == "L" then "LeftElbow" else "RightElbow"
	if kind == "bolt" then
		-- A BIG throw. Wind-up: the hand swings far back and up behind the head, the elbow bends, the torso coils
		-- away and leans back, the other arm reaches forward to aim. Release: the arm whips forward fully stretched
		-- at the target, the torso unwinds past the middle and bows into the throw, the other arm swings back; it
		-- holds the stretch a moment and settles (RECOVER_BOLT).
		add(arm, 1.5 * w - 2.9 * r, 0, side * (0.45 * w + 0.15 * r))
		add(elbow, 1.4 * w - 0.1 * r, 0, 0)
		add("Waist", -0.18 * w + 0.32 * r, -side * (0.7 * w - 0.6 * r), 0)
		add("Root", 0, -side * (0.25 * w - 0.2 * r), 0)
		add("Neck", 0.1 * w - 0.2 * r, side * (0.3 * w - 0.15 * r), 0)
		add(other, -1.1 * w + 0.7 * r, 0, -side * (0.2 * w + 0.45 * r))
		add(if hand == "L" then "RightElbow" else "LeftElbow", 0.5 * w, 0, 0)
	elseif kind == "aoe" or kind == "pull" then
		-- Both arms rise over the head, then slam down (aoe) / yank back (pull); the torso bows.
		local up = -2.5 * w
		add("LeftShoulder", up - 0.6 * r, 0, 0.35 * w + 0.5 * r)
		add("RightShoulder", up - 0.6 * r, 0, -0.35 * w - 0.5 * r)
		add("LeftElbow", 0.4 * w, 0, 0)
		add("RightElbow", 0.4 * w, 0, 0)
		add("Waist", -0.15 * w + 0.4 * r, 0, 0)
		add("Neck", -0.25 * w + 0.2 * r, 0, 0)
	elseif kind == "chain" then
		-- The arm sweeps across the body from the far side to the near one and the torso turns with it.
		local sweep = (w * 2 - 1) -- -1 … 1
		add(arm, -1.4 * w - 1.5 * r, 0, side * (1.1 * sweep * w + 0.4 * r))
		add(elbow, 0.5 * w, 0, 0)
		add("Waist", 0, side * (0.5 * sweep * w + 0.35 * r), 0)
		add("Neck", -0.15 * (w + r), -side * 0.2 * sweep * w, 0)
		add(other, 0.3 * w, 0, -side * 0.5 * w)
	elseif kind == "repel" then
		-- A burst: the arms cross in front of the chest and the body curls in; on the release the arms fling wide
		-- and the chest opens up (the shockwave leaves the mage), then it settles.
		add("LeftShoulder", -1.1 * w - 0.2 * r, 0, -0.8 * w + 1.4 * r)
		add("RightShoulder", -1.1 * w - 0.2 * r, 0, 0.8 * w - 1.4 * r)
		add("LeftElbow", 0.9 * w, 0, 0)
		add("RightElbow", 0.9 * w, 0, 0)
		add("Waist", 0.3 * w - 0.2 * r, 0, 0)
		add("Neck", 0.2 * w - 0.25 * r, 0, 0)
	elseif kind == "shield" or kind == "ward" or kind == "heal" then
		-- A slow rise of both arms, palms up, the head lifting; it stays a moment and comes down softly.
		add("LeftShoulder", -2.0 * w - 1.6 * r, 0, 0.7 * w + 0.5 * r)
		add("RightShoulder", -2.0 * w - 1.6 * r, 0, -0.7 * w - 0.5 * r)
		add("LeftElbow", -0.3 * w, 0, 0)
		add("RightElbow", -0.3 * w, 0, 0)
		add("Neck", -0.35 * (w + r), 0, 0)
		add("Waist", 0.08 * (w + r), 0, 0)
	elseif kind == "blink" then
		-- Arms cross over the chest and the body folds a little; the blink itself is a flash (see `blink`).
		add("LeftShoulder", -1.2 * w, 0, -0.9 * w)
		add("RightShoulder", -1.2 * w, 0, 0.9 * w)
		add("Waist", 0.25 * w, 0, 0)
	end
end

local function updateRig(rig: Rig, now: number, dt: number)
	local model = rig.model
	local glide = (model:GetAttribute("Glide") :: number?) or 0
	local level = (model:GetAttribute("Tier") :: number?) or 1
	local scale = model:GetScale()
	local t = now + rig.phase

	-- A new cast?
	local castId = (model:GetAttribute("CastId") :: number?) or 0
	if castId ~= rig.castId then
		rig.castId = castId
		local raw = model:GetAttribute("Cast")
		if type(raw) == "string" then
			local kind, duration, hand = string.match(raw, "^([%w]+)|([%d%.]+)|([LR])$")
			if kind then
				rig.cast = { kind = kind, duration = math.max(0.12, tonumber(duration) or 0.4), hand = hand or "R", startedAt = now }
			end
		end
	end
	local blink = (model:GetAttribute("Blink") :: number?) or 0
	if blink ~= rig.blink then
		rig.blink = blink
		rig.blinkAt = now
	end

	-- The pose: idle + glide + the gesture.
	local o: { [string]: Vector3 } = {}
	local function add(name: string, x: number, y: number, z: number)
		local v = o[name] or Vector3.zero
		o[name] = v + Vector3.new(x, y, z)
	end
	-- Idle: breathing, a wandering gaze, the arms alive.
	add("Waist", math.sin(t * 1.3) * 0.025, math.sin(t * 0.37) * 0.04, 0)
	add("Neck", math.sin(t * 0.9) * 0.04, math.sin(t * 0.53) * 0.12, math.sin(t * 0.71) * 0.03)
	add("LeftShoulder", math.sin(t * 1.3) * 0.03, 0, 0.06 + math.sin(t * 1.3 + 1) * 0.03)
	add("RightShoulder", math.sin(t * 1.3 + 0.5) * 0.03, 0, -0.06 - math.sin(t * 1.3) * 0.03)
	add("LeftElbow", 0.15 + math.sin(t * 1.1) * 0.03, 0, 0)
	add("RightElbow", 0.15 + math.sin(t * 1.1 + 2) * 0.03, 0, 0)
	-- Glide: the legs hang and breathe (out of step with each other), knees bent, toes down; the arms open a
	-- little and the body sways with the float.
	if glide > 0.001 then
		local g = glide
		local swing = math.sin(t * 2.4) * 0.14 * g
		add("LeftHip", -0.3 * g + swing, 0, 0.1 * g)
		add("RightHip", -0.3 * g - swing, 0, -0.1 * g)
		add("LeftKnee", 0.55 * g + math.sin(t * 2.4 + 1.2) * 0.1 * g, 0, 0)
		add("RightKnee", 0.55 * g - math.sin(t * 2.4 + 1.2) * 0.1 * g, 0, 0)
		add("LeftAnkle", 0.35 * g, 0, 0)
		add("RightAnkle", 0.35 * g, 0, 0)
		add("LeftShoulder", -0.2 * g, 0, 0.45 * g + math.sin(t * 2.0) * 0.06 * g)
		add("RightShoulder", -0.2 * g, 0, -0.45 * g - math.sin(t * 2.0 + 0.7) * 0.06 * g)
		add("Waist", -0.06 * g, 0, math.sin(t * 2.4) * 0.05 * g)
		add("Neck", 0.08 * g, 0, -math.sin(t * 2.4) * 0.04 * g)
	end
	-- The gesture of the spell being cast (wind-up until the release, then the recovery).
	local cast = rig.cast
	if cast then
		local since = now - cast.startedAt
		local recover = if cast.kind == "bolt" then RECOVER_BOLT else RECOVER
		if since <= cast.duration then
			gesture(o, cast.kind, smooth(since / cast.duration), 0, cast.hand)
		elseif since <= cast.duration + recover then
			local k = 1 - (since - cast.duration) / recover
			-- The release: a quick snap into the full stretch (the first 15 %), held, then eased back.
			local snap = math.clamp((1 - k) / 0.15, 0, 1)
			local amount = if cast.kind == "bolt" then math.min(smooth(snap), smooth(k / 0.6)) else outBack(k) * k
			gesture(o, cast.kind, 0, amount, cast.hand)
		else
			rig.cast = nil
		end
	end
	for name, joint in rig.joints do
		local base = rig.base[name]
		local v = o[name]
		if base and v and joint.Parent then
			joint.C0 = base * CFrame.Angles(v.X, v.Y, v.Z)
		elseif base and joint.Parent then
			joint.C0 = base
		end
	end

	-- The aura: shards orbiting the waist, a disc on the ground. More shards, higher and faster with the level
	-- and while gliding; a blink flashes them wide.
	local wanted = math.clamp(2 + level // 4, 2, 6)
	-- A wizard type (the "Variant" attribute) colors its aura; otherwise the level color.
	local variant = model:GetAttribute("Variant")
	local color = if Wizards.isValid(variant) then Wizards.Types[variant :: string].color else Levels.color(level)
	local shardColor = color:Lerp(Color3.new(1, 1, 1), 0.3)
	while #rig.shards < wanted do
		local i = #rig.shards + 1
		table.insert(rig.shards, { part = neon(Vector3.new(0.22, 0.22, 0.55) * scale, shardColor, 0.3), angle = i / wanted * math.pi * 2, height = 0.9 + (i % 3) * 0.35, speed = 1.4 + (i % 2) * 0.5 })
	end
	local pivot = model:GetPivot()
	local sinceBlink = now - rig.blinkAt
	local flash = if sinceBlink < 0.35 then 1 - sinceBlink / 0.35 else 0
	local radius = (1.5 + level * 0.06 + glide * 0.4 + flash * 3) * scale
	local spin = (1.5 + glide * 3 + level * 0.08) * dt
	for _, s in rig.shards do
		s.angle += spin * s.speed
		local pos = pivot.Position + Vector3.new(math.cos(s.angle) * radius, (s.height + math.sin(t * 2 + s.angle) * 0.18) * scale - 1 * scale, math.sin(s.angle) * radius)
		local tangent = Vector3.new(-math.sin(s.angle), 0, math.cos(s.angle))
		s.part.CFrame = CFrame.lookAt(pos, pos + tangent)
		s.part.Color = shardColor
		s.part.Transparency = 0.35 - glide * 0.2 - flash * 0.3
	end
	local foot = model:FindFirstChild("LeftFoot")
	if foot and foot:IsA("BasePart") then
		if not rig.disc then
			rig.disc = neon(Vector3.new(0.05, 3.2, 3.2) * scale, color, 0.8, Enum.PartType.Cylinder)
		end
		local disc = rig.disc :: Part
		local groundY = foot.Position.Y - foot.Size.Y / 2 - glide * 0.7 * scale + 0.03
		disc.CFrame = CFrame.new(pivot.Position.X, groundY, pivot.Position.Z) * CFrame.Angles(0, t * 0.6, math.rad(90))
		disc.Size = Vector3.new(0.05, 3.2 + glide * 1.2 + flash * 2, 3.2 + glide * 1.2 + flash * 2) * scale
		disc.Color = color
		disc.Transparency = 0.82 - glide * 0.25 - flash * 0.3
	end
end

function MageAnimator.start()
	local last = os.clock()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = math.min(0.1, now - last)
		last = now
		for _, rig in rigs do
			if rig.model.Parent then
				updateRig(rig, now, dt)
			end
		end
	end)
end

return MageAnimator
