--!strict
-- People in the world: realistic R15 characters (built from a HumanoidDescription, Roblox's own body) who stand at
-- their place, play an idle animation, turn to you when you come close, say a line in a speech bubble and can walk
-- somewhere. The employers stand at their WORK HERE boards (server/World.luau), the givers hand cargo over at
-- pick-ups, the receivers take it at the drops, kids board the bus, a patient boards the ambulance
-- (server/Cargo.luau). Dr. Novak at the City Clinic wears a white coat, the bank guard a uniform.
--
-- Outfits are made of colours and a few parts (no clothing assets): the body parts are coloured like a shirt, pants
-- and shoes, with a hat, hair, a vest or an apron welded on (Npcs.look gives every role its own look). A standing
-- person's root is anchored (no physics); walkTo unanchors it and lets the Humanoid walk. People are in their own
-- collision group: cars, enemies and bullets pass through them. The joints may be AnimationConstraints (Avatar Joint
-- Upgrade): nothing here touches them, the animations do.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Npcs = {}

export type Look = {
	name: string, -- shown over the head
	title: string?, -- a second line ("Rancher", "Sergeant")
	skin: { number }?, -- r, g, b
	shirt: { number }?,
	pants: { number }?,
	hat: string?, -- none | cap | cowboy | hardhat | beanie | chef | helmet
	child: boolean?, -- a kid (smaller)
	hatColor: { number }?,
	hair: { number }?, -- hair colour (nil = none showing)
	vest: { number }?, -- a vest over the shirt
	apron: { number }?, -- an apron (or overalls' bib) in front
	shoes: { number }?,
	boots: boolean?, -- the shins in the shoe colour (riding boots, army boots)
	shortSleeves: boolean?, -- forearms show the skin
	coat: { number }?, -- a long coat over everything (the doctor's white coat)
	tie: { number }?, -- a tie down the shirt front
	bandage: boolean?, -- a bandage round the head (a patient)
	walkSpeed: number?, -- studs / s (default 8, a kid 9; a patient shuffles)
}

local GROUP = "Npc"
local IDLE = "rbxassetid://507766388"
local WALK = "rbxassetid://507777826"
local GREET_RANGE = 14 -- turn to a player this close
local NAME_RANGE = 60

type State = {
	model: Model,
	humanoid: Humanoid?,
	root: BasePart,
	head: BasePart?,
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	walkRate: number, -- the walk animation's speed (fits the stride to the walk speed and the body size)
	walkToken: number,
	home: CFrame, -- the way it stands when nobody is around (set by spawn, face and walkTo)
	turn: Tween?,
	speechToken: number,
	lastGreet: number,
	greeting: boolean,
	scale: number,
}

local states: { [Model]: State } = {}
local templates: { [string]: Model } = {}
local baseRigs: { [boolean]: Model } = {} -- the plain R15 rigs (adult, child) every look is dressed on
local warmed = false
local folder: Folder? = nil
local started = false

local function rgb(c: { number }?, fallback: Color3): Color3
	return if c then Color3.fromRGB(c[1], c[2], c[3]) else fallback
end

-- The two base rigs, made once (CreateHumanoidModelFromDescription yields: World.build waits for it at server start,
-- so Npcs.spawn never yields later in the Jobs Heartbeat). A failed load means blocky people, without retries.
local function warmBases()
	if warmed then
		return
	end
	warmed = true
	for _, child in { false, true } do
		local ok, rig = pcall(function()
			local d = Instance.new("HumanoidDescription")
			if child then
				d.HeightScale = 0.72
				d.WidthScale = 0.78
				d.DepthScale = 0.78
				d.HeadScale = 0.95
			end
			return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
		end)
		if ok and rig then
			baseRigs[child] = rig
		else
			warn(`[Npcs] no R15 base rig, using blocks: {rig}`)
		end
	end
end

-- Lazy: World.build places the employers before Npcs.start runs.
local function init(): Folder
	if folder and folder.Parent then
		return folder
	end
	warmBases()
	for _, name in { GROUP, "Car", "EnemyCar", "Zombie", "Bullet", "Corpse" } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	for _, other in { "Car", "EnemyCar", "Zombie", "Bullet", "Corpse", GROUP } do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(GROUP, other, false)
		end)
	end
	local f = workspace:FindFirstChild("Npcs")
	if not f or not f:IsA("Folder") then
		f = Instance.new("Folder")
		f.Name = "Npcs"
		f.Parent = workspace
	end
	folder = f :: Folder
	return f :: Folder
end

-- ── Looks ──────────────────────────────────────────────────────────────────

local SKINS = { { 255, 224, 196 }, { 241, 194, 160 }, { 214, 160, 120 }, { 176, 122, 84 }, { 132, 88, 60 }, { 98, 66, 46 } }
local HAIRS = { { 40, 30, 24 }, { 74, 50, 32 }, { 120, 84, 50 }, { 196, 160, 100 }, { 150, 150, 150 }, { 30, 26, 26 } }
local SHIRTS = { { 70, 110, 160 }, { 160, 60, 60 }, { 90, 130, 90 }, { 200, 180, 140 }, { 120, 90, 140 }, { 60, 60, 66 }, { 210, 140, 60 } }
local PANTS = { { 50, 64, 100 }, { 60, 60, 64 }, { 110, 90, 70 }, { 40, 40, 44 }, { 150, 130, 100 } }
local BRIGHT = { { 230, 80, 70 }, { 70, 150, 230 }, { 250, 200, 60 }, { 110, 200, 110 }, { 230, 120, 200 }, { 250, 140, 50 } }

local function hash(text: string): number
	local h = 7
	for n = 1, #text do
		h = (h * 31 + string.byte(text, n)) % 1000003
	end
	return h
end

local function pick<T>(list: { T }, h: number, salt: number): T
	return list[(h // salt) % #list + 1]
end

-- A quick look for a role (consistent outfits): "rancher", "soldier", "officer", "farmer", "worker", "foreman",
-- "teacher", "kid", "shopkeeper", "grocer", "icecream", "mover", "cook", "clerk", "attendant", "rider", "doctor",
-- "nurse", "patient", "banker", "guard", anything else = a townsperson. Skin and hair come from the name, so the same person always looks the same.
function Npcs.look(role: string, name: string, title: string?): Look
	local h = hash(name .. role)
	local look: Look = {
		name = name,
		title = title,
		skin = pick(SKINS, h, 1),
		hair = pick(HAIRS, h, 7),
		shirt = pick(SHIRTS, h, 11),
		pants = pick(PANTS, h, 13),
		shoes = { 46, 38, 32 },
	}
	if role == "rancher" then
		look.hat, look.hatColor = "cowboy", { 120, 82, 50 }
		look.shirt, look.pants, look.vest = { 168, 52, 44 }, { 58, 76, 112 }, { 96, 64, 40 }
		look.boots, look.shoes = true, { 82, 54, 34 }
	elseif role == "farmer" then
		look.hat, look.hatColor = "cowboy", { 218, 190, 120 }
		look.shirt, look.pants, look.apron = { 196, 186, 156 }, { 66, 92, 136 }, { 66, 92, 136 }
		look.shortSleeves = true
	elseif role == "soldier" or role == "officer" then
		look.hat = if role == "officer" then "cap" else "helmet"
		look.hatColor = { 74, 84, 54 }
		look.shirt, look.pants, look.vest = { 92, 102, 66 }, { 78, 86, 58 }, if role == "soldier" then { 64, 70, 46 } else nil
		look.boots, look.shoes = true, { 34, 30, 26 }
	elseif role == "worker" or role == "foreman" then
		look.hat, look.hatColor = "hardhat", if role == "foreman" then { 240, 120, 30 } else { 240, 200, 40 }
		look.shirt, look.pants, look.vest = { 70, 80, 96 }, { 64, 64, 70 }, { 210, 230, 50 }
		look.boots = true
	elseif role == "teacher" then
		look.hat = "none"
		look.shirt, look.pants = { 150, 96, 120 }, { 60, 60, 72 }
	elseif role == "kid" then
		look.child = true
		look.hat = if h % 3 == 0 then "cap" else if h % 3 == 1 then "beanie" else "none"
		look.hatColor = pick(BRIGHT, h, 17)
		look.shirt, look.pants = pick(BRIGHT, h, 19), pick(PANTS, h, 23)
		look.shortSleeves = true
	elseif role == "shopkeeper" or role == "grocer" then
		look.hat = if role == "grocer" then "cap" else "none"
		look.hatColor = { 60, 120, 60 }
		look.shirt, look.pants, look.apron = { 120, 160, 200 }, { 60, 60, 64 }, if role == "grocer" then { 70, 130, 70 } else { 230, 226, 214 }
	elseif role == "icecream" then
		look.hat, look.hatColor = "cap", { 250, 150, 200 }
		look.shirt, look.pants, look.apron = { 245, 245, 250 }, { 80, 120, 180 }, { 250, 170, 210 }
		look.shortSleeves = true
	elseif role == "mover" then
		look.hat, look.hatColor = "cap", { 230, 120, 40 }
		look.shirt, look.pants = { 230, 120, 40 }, { 60, 60, 70 }
		look.shortSleeves, look.boots = true, true
	elseif role == "cook" then
		look.hat, look.hatColor = "chef", { 248, 248, 248 }
		look.shirt, look.pants, look.apron = { 240, 240, 240 }, { 40, 40, 44 }, { 250, 250, 250 }
	elseif role == "clerk" then
		look.hat = "none"
		look.shirt, look.pants, look.vest = { 236, 236, 240 }, { 44, 46, 58 }, { 44, 54, 84 }
		look.shoes = { 24, 24, 26 }
	elseif role == "attendant" then
		look.hat, look.hatColor = "cap", { 200, 40, 40 }
		look.shirt, look.pants = { 200, 44, 40 }, { 50, 50, 56 }
		look.shortSleeves = true
	elseif role == "rider" then
		look.hat, look.hatColor = "helmet", { 30, 30, 34 }
		look.shirt, look.pants, look.vest = { 236, 236, 236 }, { 214, 196, 160 }, { 40, 60, 90 }
		look.boots, look.shoes = true, { 26, 22, 20 }
	elseif role == "doctor" then
		look.hat = "none"
		look.shirt, look.pants, look.coat, look.tie = { 150, 196, 220 }, { 60, 66, 80 }, { 246, 246, 248 }, { 40, 80, 140 }
		look.shoes = { 30, 30, 32 }
	elseif role == "nurse" then
		look.hat = "none"
		look.shirt, look.pants = { 96, 176, 176 }, { 96, 176, 176 }
		look.shortSleeves, look.shoes = true, { 240, 240, 240 }
	elseif role == "patient" then
		-- A hospital gown, a bandaged head, slow on the feet.
		look.hat = "none"
		look.shirt, look.pants = { 176, 206, 226 }, { 176, 206, 226 }
		look.shortSleeves, look.bandage, look.walkSpeed = true, true, 4.5
		look.shoes = { 220, 220, 216 }
	elseif role == "banker" then
		look.hat = "none"
		look.shirt, look.pants, look.vest, look.tie = { 236, 236, 240 }, { 34, 36, 46 }, { 34, 36, 46 }, { 196, 156, 50 }
		look.shoes = { 20, 20, 22 }
	elseif role == "guard" then
		look.hat, look.hatColor = "cap", { 30, 40, 70 }
		look.shirt, look.pants, look.vest = { 60, 76, 120 }, { 30, 34, 50 }, { 34, 38, 48 }
		look.boots, look.shoes = true, { 24, 22, 20 }
	else
		look.hat = if h % 5 == 0 then "cap" elseif h % 5 == 1 then "beanie" else "none"
		look.hatColor = pick(SHIRTS, h, 29)
		look.shortSleeves = h % 2 == 0
	end
	return look
end

-- ── The body ───────────────────────────────────────────────────────────────

local function bodyPart(model: Model, name: string): BasePart?
	local p = model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

-- A part welded onto `on` at `offset` (cosmetic: no mass, no collisions, not hit by rays).
local function wear(model: Model, on: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, mesh: Enum.MeshType?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.CFrame = on.CFrame * offset
	if mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = mesh
		m.Parent = p
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = on
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up

local function dress(model: Model, look: Look)
	local skin = rgb(look.skin, Color3.fromRGB(241, 194, 160))
	local shirt = rgb(look.shirt, Color3.fromRGB(90, 110, 140))
	local pants = rgb(look.pants, Color3.fromRGB(60, 60, 66))
	local shoes = rgb(look.shoes, Color3.fromRGB(46, 38, 32))
	local function paint(names: { string }, color: Color3)
		for _, name in names do
			local p = bodyPart(model, name)
			if p then
				p.Color = color
			end
		end
	end
	local sleeve = if look.coat then rgb(look.coat, shirt) else shirt
	paint({ "UpperTorso" }, shirt)
	paint({ "LeftUpperArm", "RightUpperArm" }, sleeve)
	paint({ "LeftLowerArm", "RightLowerArm" }, if look.shortSleeves and not look.coat then skin else sleeve)
	paint({ "LeftHand", "RightHand", "Head" }, skin)
	paint({ "LowerTorso", "LeftUpperLeg", "RightUpperLeg" }, pants)
	paint({ "LeftLowerLeg", "RightLowerLeg" }, if look.boots then shoes else pants)
	paint({ "LeftFoot", "RightFoot" }, shoes)

	local torso = bodyPart(model, "UpperTorso")
	local lower = bodyPart(model, "LowerTorso")
	if torso then
		local s = torso.Size
		if look.vest then
			local vest = wear(model, torso, "Vest", Vector3.new(s.X * 1.04, s.Y * 0.92, s.Z * 1.12), CFrame.new(0, -s.Y * 0.03, 0), rgb(look.vest, shirt))
			if look.vest[1] > 190 and look.vest[2] > 190 then
				-- Hi-vis: reflective stripes.
				vest.Material = Enum.Material.SmoothPlastic
				wear(model, torso, "Stripe", Vector3.new(s.X * 1.06, s.Y * 0.08, s.Z * 1.14), CFrame.new(0, -s.Y * 0.2, 0), Color3.fromRGB(220, 220, 220), Enum.Material.Neon)
			end
		end
		if look.apron then
			wear(model, torso, "Apron", Vector3.new(s.X * 0.7, s.Y * 0.8, 0.06), CFrame.new(0, -s.Y * 0.08, -s.Z * 0.53), rgb(look.apron, shirt))
		end
		if look.tie then
			wear(model, torso, "Tie", Vector3.new(s.X * 0.12, s.Y * 0.72, 0.05), CFrame.new(0, s.Y * 0.06, -s.Z * 0.54), rgb(look.tie, shirt), Enum.Material.SmoothPlastic)
		end
		if look.coat then
			-- An open coat: the back and both sides, the shirt (and the tie) showing down the middle.
			local coat = rgb(look.coat, shirt)
			wear(model, torso, "CoatBack", Vector3.new(s.X * 1.08, s.Y * 1.02, 0.08), CFrame.new(0, -s.Y * 0.02, s.Z * 0.56), coat)
			for _, side in { -1, 1 } do
				wear(model, torso, "CoatFront", Vector3.new(s.X * 0.36, s.Y * 1.02, s.Z * 1.16), CFrame.new(side * s.X * 0.36, -s.Y * 0.02, 0), coat)
			end
			wear(model, torso, "Pocket", Vector3.new(s.X * 0.18, s.Y * 0.16, 0.04), CFrame.new(-s.X * 0.32, s.Y * 0.16, -s.Z * 0.6), Color3.fromRGB(60, 120, 200), Enum.Material.SmoothPlastic)
		end
		-- A collar.
		wear(model, torso, "Collar", Vector3.new(s.X * 0.42, s.Y * 0.08, s.Z * 0.9), CFrame.new(0, s.Y * 0.48, 0), shirt:Lerp(Color3.new(0, 0, 0), 0.15))
	end
	if lower then
		local s = lower.Size
		wear(model, lower, "Belt", Vector3.new(s.X * 1.04, s.Y * 0.22, s.Z * 1.08), CFrame.new(0, s.Y * 0.32, 0), Color3.fromRGB(40, 30, 24), Enum.Material.Leather)
		if look.apron then
			wear(model, lower, "ApronSkirt", Vector3.new(s.X * 0.8, s.Y * 1.6, 0.06), CFrame.new(0, -s.Y * 0.35, -s.Z * 0.55), rgb(look.apron, shirt))
		end
		if look.coat then
			-- The coat's tails down to the knees (open at the front).
			local coat = rgb(look.coat, shirt)
			local drop = s.Y * 3.2
			wear(model, lower, "CoatTail", Vector3.new(s.X * 1.12, drop, 0.08), CFrame.new(0, s.Y * 0.4 - drop / 2, s.Z * 0.6), coat)
			for _, side in { -1, 1 } do
				wear(model, lower, "CoatTail", Vector3.new(0.08, drop, s.Z * 1.2), CFrame.new(side * s.X * 0.57, s.Y * 0.4 - drop / 2, 0), coat)
				wear(model, lower, "CoatTail", Vector3.new(s.X * 0.24, drop, 0.08), CFrame.new(side * s.X * 0.45, s.Y * 0.4 - drop / 2, -s.Z * 0.6), coat)
			end
		end
	end

	local head = bodyPart(model, "Head")
	if not head then
		return
	end
	-- The default R15 head is about 1.2 studs every way (an older block head is 2 x 1 x 1 with a smaller mesh).
	local h = Vector3.one * math.min(head.Size.X, head.Size.Y, head.Size.Z) * (if head.Size.X > head.Size.Y * 1.5 then 1.2 else 1)
	local hat = look.hat or "none"
	local hatColor = rgb(look.hatColor, Color3.fromRGB(60, 60, 66))
	if look.hair and hat ~= "helmet" and hat ~= "beanie" then
		-- Hair: an ellipsoid over the top and the back of the head.
		wear(model, head, "Hair", Vector3.new(h.X * 1.04, h.Y * 0.62, h.Z * 1.06), CFrame.new(0, h.Y * 0.24, h.Z * 0.06), rgb(look.hair, Color3.new(0, 0, 0)), Enum.Material.SmoothPlastic, Enum.MeshType.Sphere)
	end
	if look.bandage then
		-- A white band round the forehead, a plaster on the cheek.
		wear(model, head, "Bandage", Vector3.new(h.Y * 0.24, h.X * 1.08, h.Z * 1.1), CFrame.new(0, h.Y * 0.2, 0) * UPRIGHT, Color3.fromRGB(246, 244, 238), Enum.Material.Fabric, nil, Enum.PartType.Cylinder)
		wear(model, head, "Plaster", Vector3.new(h.X * 0.22, h.Y * 0.14, 0.04), CFrame.new(h.X * 0.22, -h.Y * 0.12, -h.Z * 0.5), Color3.fromRGB(226, 196, 160), Enum.Material.Fabric)
	end
	if hat == "cowboy" then
		wear(model, head, "HatBrim", Vector3.new(0.08, h.X * 1.9, h.Z * 1.9), CFrame.new(0, h.Y * 0.36, 0) * UPRIGHT, hatColor, Enum.Material.Leather, nil, Enum.PartType.Cylinder)
		wear(model, head, "HatCrown", Vector3.new(h.Y * 0.5, h.X * 0.95, h.Z * 0.95), CFrame.new(0, h.Y * 0.6, 0) * UPRIGHT, hatColor, Enum.Material.Leather, nil, Enum.PartType.Cylinder)
		wear(model, head, "HatBand", Vector3.new(h.Y * 0.1, h.X * 0.97, h.Z * 0.97), CFrame.new(0, h.Y * 0.44, 0) * UPRIGHT, hatColor:Lerp(Color3.new(0, 0, 0), 0.6), Enum.Material.Leather, nil, Enum.PartType.Cylinder)
	elseif hat == "cap" then
		wear(model, head, "Cap", Vector3.new(h.X * 1.06, h.Y * 0.5, h.Z * 1.06), CFrame.new(0, h.Y * 0.32, 0), hatColor, Enum.Material.Fabric, Enum.MeshType.Sphere)
		wear(model, head, "Visor", Vector3.new(h.X * 0.8, 0.06, h.Z * 0.5), CFrame.new(0, h.Y * 0.3, -h.Z * 0.62) * CFrame.Angles(math.rad(8), 0, 0), hatColor:Lerp(Color3.new(0, 0, 0), 0.2))
	elseif hat == "hardhat" then
		wear(model, head, "Hardhat", Vector3.new(h.X * 1.14, h.Y * 0.62, h.Z * 1.16), CFrame.new(0, h.Y * 0.36, 0), hatColor, Enum.Material.SmoothPlastic, Enum.MeshType.Sphere)
		wear(model, head, "HardhatBrim", Vector3.new(0.06, h.X * 1.3, h.Z * 1.34), CFrame.new(0, h.Y * 0.2, -0.04) * UPRIGHT, hatColor, Enum.Material.SmoothPlastic, nil, Enum.PartType.Cylinder)
	elseif hat == "beanie" then
		wear(model, head, "Beanie", Vector3.new(h.X * 1.08, h.Y * 0.7, h.Z * 1.08), CFrame.new(0, h.Y * 0.28, 0.02), hatColor, Enum.Material.Fabric, Enum.MeshType.Sphere)
	elseif hat == "helmet" then
		wear(model, head, "Helmet", Vector3.new(h.X * 1.18, h.Y * 0.72, h.Z * 1.22), CFrame.new(0, h.Y * 0.3, 0.03), hatColor, Enum.Material.SmoothPlastic, Enum.MeshType.Sphere)
	elseif hat == "chef" then
		wear(model, head, "ChefHat", Vector3.new(h.Y * 0.8, h.X * 0.92, h.Z * 0.92), CFrame.new(0, h.Y * 0.8, 0) * UPRIGHT, hatColor, Enum.Material.Fabric, nil, Enum.PartType.Cylinder)
		wear(model, head, "ChefPuff", Vector3.new(h.X * 1.1, h.Y * 0.5, h.Z * 1.1), CFrame.new(0, h.Y * 1.2, 0), hatColor, Enum.Material.Fabric, Enum.MeshType.Sphere)
	end
end

local function lookKey(look: Look): string
	local function c(v: { number }?): string
		return if v then `{v[1]},{v[2]},{v[3]}` else "-"
	end
	return table.concat({
		c(look.skin), c(look.shirt), c(look.pants), c(look.hatColor), c(look.hair), c(look.vest), c(look.apron), c(look.shoes),
		look.hat or "none", tostring(look.child == true), tostring(look.boots == true), tostring(look.shortSleeves == true),
		c(look.coat), c(look.tie), tostring(look.bandage == true),
	}, "|")
end

-- One R15 body per look, cloned for every person who wears it.
local function r15Body(look: Look): Model?
	local key = lookKey(look)
	local cached = templates[key]
	if cached then
		return cached:Clone()
	end
	local base = baseRigs[look.child == true]
	if not base then
		return nil -- no base rig: blockyBody, no yield
	end
	local model = base:Clone()
	local colors = model:FindFirstChildOfClass("BodyColors")
	if colors then
		colors:Destroy() -- dress() paints every body part; the base rig's colours must not paint over it
	end
	dress(model, look)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = GROUP
			d.CanTouch = false -- no seats grab them, no kill bricks
			d.CanQuery = false -- not in the way of the crosshair and the shots
		elseif d:IsA("Accessory") then
			d:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.MaxHealth = 1e6
		humanoid.Health = 1e6
		for _, state in { Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming } do
			humanoid:SetStateEnabled(state, false)
		end
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end
	templates[key] = model
	return model:Clone()
end

-- When no R15 body can be made: a simple blocky person (a statue that still talks, turns and slides along).
local function blockyBody(look: Look): Model
	local model = Instance.new("Model")
	local s = if look.child then 0.75 else 1
	local function block(name: string, size: Vector3, offset: CFrame, color: Color3, root: BasePart?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * s
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CollisionGroup = GROUP
		p.CanTouch = false
		p.CanCollide = root == nil
		p.CanQuery = root == nil
		if root then
			p.CFrame = root.CFrame * CFrame.new(offset.Position * s)
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		else
			p.CFrame = offset
		end
		p.Parent = model
		return p
	end
	local skin = rgb(look.skin, Color3.fromRGB(241, 194, 160))
	local shirt = rgb(look.shirt, Color3.fromRGB(90, 110, 140))
	local pants = rgb(look.pants, Color3.fromRGB(60, 60, 66))
	local root = block("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3 * s, 0), shirt)
	root.Transparency = 1
	block("UpperTorso", Vector3.new(2, 2, 1), CFrame.new(0, 0, 0), shirt, root)
	block("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.6, 0), skin, root)
	block("LeftArm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0), shirt, root)
	block("RightHand", Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0), shirt, root)
	block("LeftLeg", Vector3.new(1, 2, 1), CFrame.new(-0.5, -2, 0), pants, root)
	block("RightLeg", Vector3.new(1, 2, 1), CFrame.new(0.5, -2, 0), pants, root)
	model.PrimaryPart = root
	return model
end

-- ── Name tag and speech ────────────────────────────────────────────────────

local function nameTag(head: BasePart, look: Look)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(240, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y * 0.5 + 0.9, 0)
	gui.SizeOffset = Vector2.new(0, 0.5) -- stands on that point
	gui.MaxDistance = NAME_RANGE
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = head
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 24)
	name.BackgroundTransparency = 1
	name.Text = look.name
	name.TextSize = 20
	name.Font = Enum.Font.GothamBold
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.35
	name.Parent = gui
	if look.title and look.title ~= "" then
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 18)
		title.Position = UDim2.fromOffset(0, 25)
		title.BackgroundTransparency = 1
		title.Text = look.title
		title.TextSize = 15
		title.Font = Enum.Font.GothamMedium
		title.TextColor3 = Color3.fromRGB(255, 214, 110)
		title.TextStrokeTransparency = 0.4
		title.Parent = gui
	end
end

-- A line in a speech bubble over the head for a few seconds.
function Npcs.say(npc: Model, text: string, seconds: number?)
	local state = states[npc]
	local head = if state then state.head or state.root else nil
	if not state or not head then
		return
	end
	state.speechToken += 1
	local token = state.speechToken
	local old = head:FindFirstChild("Speech")
	if old then
		old:Destroy()
	end
	-- The bubble takes the name tag's place while it is up.
	local tag = head:FindFirstChild("NameTag")
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = false
	end
	local bounds = Vector2.new(220, 40)
	pcall(function()
		bounds = TextService:GetTextSize(text, 16, Enum.Font.GothamMedium, Vector2.new(240, 400))
	end)
	local width, height = math.ceil(bounds.X) + 24, math.ceil(bounds.Y) + 16
	local gui = Instance.new("BillboardGui")
	gui.Name = "Speech"
	gui.Size = UDim2.fromOffset(width, height + 10)
	gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y * 0.5 + 0.9, 0)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.MaxDistance = NAME_RANGE
	gui.LightInfluence = 0
	gui.Parent = head
	local bubble = Instance.new("Frame")
	bubble.Size = UDim2.new(1, 0, 0, height)
	bubble.BackgroundColor3 = Color3.fromRGB(250, 250, 246)
	bubble.BorderSizePixel = 0
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bubble
	local tail = Instance.new("Frame")
	tail.Size = UDim2.fromOffset(12, 12)
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, 0, 0, height)
	tail.Rotation = 45
	tail.BackgroundColor3 = bubble.BackgroundColor3
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -24, 1, -16)
	label.Position = UDim2.fromOffset(12, 8)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextWrapped = true
	label.TextSize = 16
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.fromRGB(30, 30, 34)
	label.Parent = bubble
	task.delay(seconds or math.clamp(2.5 + #text / 18, 3, 9), function()
		if state.speechToken == token and gui.Parent then
			gui:Destroy()
			if tag and tag:IsA("BillboardGui") then
				tag.Enabled = true
			end
		end
	end)
end

-- ── Moving ─────────────────────────────────────────────────────────────────

local function flatLook(from: Vector3, point: Vector3): CFrame?
	local flat = Vector3.new(point.X - from.X, 0, point.Z - from.Z)
	if flat.Magnitude < 0.05 then
		return nil
	end
	return CFrame.lookAt(from, from + flat)
end

-- Turn on the spot (anchored root: the whole body follows it).
local function turnTo(state: State, point: Vector3, setHome: boolean)
	if state.walkToken > 0 and not state.root.Anchored then
		return -- walking: the Humanoid turns it
	end
	local target = flatLook(state.root.Position, point)
	if not target then
		return
	end
	if setHome then
		state.home = target
	end
	if state.turn then
		state.turn:Cancel()
	end
	local angle = math.acos(math.clamp(state.root.CFrame.LookVector:Dot(target.LookVector), -1, 1))
	local tween = TweenService:Create(state.root, TweenInfo.new(0.15 + angle * 0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = target })
	state.turn = tween
	tween:Play()
end

-- Turn to face a point (smoothly, on the spot). It keeps facing that way when nobody is around.
function Npcs.face(npc: Model, point: Vector3)
	local state = states[npc]
	if state then
		turnTo(state, point, true)
	end
end

-- Look at a point for a moment (a player who talks to them); they turn back to their own way later.
function Npcs.glance(npc: Model, point: Vector3)
	local state = states[npc]
	if state then
		state.lastGreet = os.clock()
		state.greeting = true
		turnTo(state, point, false)
	end
end

local function play(state: State, walking: boolean)
	if walking then
		if state.walk and not state.walk.IsPlaying then
			state.walk:Play(0.25, 1, state.walkRate)
		end
		if state.idle and state.idle.IsPlaying then
			state.idle:Stop(0.25)
		end
	else
		if state.walk and state.walk.IsPlaying then
			state.walk:Stop(0.25)
		end
		if state.idle and not state.idle.IsPlaying then
			state.idle:Play(0.25)
		end
	end
end

local function stand(state: State)
	local root = state.root
	if state.humanoid then
		state.humanoid:Move(Vector3.zero)
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local upright = if flat.Magnitude > 0.01 then CFrame.lookAt(root.Position, root.Position + flat) else CFrame.new(root.Position)
	root.Anchored = true
	root.CFrame = upright
	state.home = upright
	play(state, false)
end

-- Walk to a point (walk animation), then call `arrived` (false if it could not get there within `timeout` s).
function Npcs.walkTo(npc: Model, point: Vector3, arrived: ((boolean) -> ())?, timeout: number?)
	local state = states[npc]
	if not state then
		if arrived then
			task.spawn(arrived, false)
		end
		return
	end
	state.walkToken += 1
	local token = state.walkToken
	if state.turn then
		state.turn:Cancel()
		state.turn = nil
	end
	local root = state.root
	local humanoid = state.humanoid
	local distance = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z).Magnitude
	local speed = if humanoid then humanoid.WalkSpeed else 8
	local limit = timeout or (distance / math.max(speed, 1) * 2 + 4)
	if not humanoid then
		-- The blocky fallback slides there.
		local target = flatLook(root.Position, point) or root.CFrame
		root.CFrame = target
		local goal = CFrame.new(Vector3.new(point.X, root.Position.Y, point.Z)) * target.Rotation
		local tween = TweenService:Create(root, TweenInfo.new(math.min(distance / speed, limit), Enum.EasingStyle.Linear), { CFrame = goal })
		tween:Play()
		tween.Completed:Once(function()
			if state.walkToken == token and arrived then
				arrived(true)
			end
		end)
		return
	end
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	play(state, true)
	task.spawn(function()
		local startedAt = os.clock()
		local ordered = -10
		local ok = false
		while npc.Parent and state.walkToken == token do
			local p = root.Position
			if Vector3.new(point.X - p.X, 0, point.Z - p.Z).Magnitude < 1.6 then
				ok = true
				break
			end
			if os.clock() - startedAt > limit then
				break
			end
			-- MoveTo gives up after 8 s: order it again now and then.
			if os.clock() - ordered > 4 then
				humanoid:MoveTo(point)
				ordered = os.clock()
			end
			task.wait(0.1)
		end
		if not npc.Parent or state.walkToken ~= token then
			return
		end
		stand(state)
		if arrived then
			arrived(ok)
		end
	end)
end

function Npcs.remove(npc: Model)
	local state = states[npc]
	if state then
		state.walkToken += 1
		if state.turn then
			state.turn:Cancel()
		end
		states[npc] = nil
	end
	npc:Destroy()
end

-- ── Spawning ───────────────────────────────────────────────────────────────

local function loadTrack(animator: Animator, id: string): AnimationTrack?
	local ok, track = pcall(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		return track
	end
	return nil
end

-- A person standing at `at` (feet on the ground at at.Position, facing at.LookVector). Parented to workspace.Npcs.
function Npcs.spawn(look: Look, at: CFrame): Model
	local parent = init()
	local model = r15Body(look) or blockyBody(look)
	model.Name = look.name
	local root = (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) :: BasePart
	model.PrimaryPart = root
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local scale = if look.child then 0.72 else 1
	local flat = Vector3.new(at.LookVector.X, 0, at.LookVector.Z)
	local facing = if flat.Magnitude > 0.01 then CFrame.lookAt(at.Position, at.Position + flat) else CFrame.new(at.Position)
	-- The root floats HipHeight over the ground (R15).
	local lift = if humanoid then humanoid.HipHeight + root.Size.Y / 2 else 3 * scale
	root.Anchored = true
	model:PivotTo(facing * CFrame.new(0, lift, 0))
	local head = model:FindFirstChild("Head") :: BasePart?
	if head then
		nameTag(head, look)
	end
	model:SetAttribute("Npc", true)
	model.Parent = parent

	local state: State = {
		model = model,
		humanoid = humanoid,
		root = root,
		head = head,
		walkRate = 1,
		walkToken = 0,
		home = root.CFrame,
		speechToken = 0,
		lastGreet = 0,
		greeting = false,
		scale = scale,
	}
	if humanoid then
		humanoid.WalkSpeed = look.walkSpeed or (if look.child then 9 else 8)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			state.idle = loadTrack(animator, IDLE)
			state.walk = loadTrack(animator, WALK)
			-- The animation's stride fits a fast walk: slow it to the person's speed and size.
			state.walkRate = humanoid.WalkSpeed / (11 * scale)
			if state.idle then
				state.idle:Play(0)
				-- Not everybody breathes in step.
				state.idle.TimePosition = math.random() * math.max(state.idle.Length, 0.1)
			end
		end
	end
	states[model] = state
	model.Destroying:Connect(function()
		states[model] = nil
	end)
	return model
end

-- ── Greeting ───────────────────────────────────────────────────────────────
-- A standing person turns to a player who comes close, and back to their own way when they leave.

local function greet()
	local players = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(players, root.Position)
		end
	end
	local now = os.clock()
	for _, state in states do
		if not state.root.Anchored or state.model:GetAttribute("Busy") then
			continue
		end
		local from = state.root.Position
		local nearest: Vector3? = nil
		local best = GREET_RANGE
		for _, p in players do
			local d = Vector3.new(p.X - from.X, 0, p.Z - from.Z).Magnitude
			if d < best then
				nearest, best = p, d
			end
		end
		if nearest then
			local target = flatLook(from, nearest)
			if target and state.root.CFrame.LookVector:Dot(target.LookVector) < 0.9 then
				turnTo(state, nearest, false)
			end
			state.lastGreet = now
			state.greeting = true
		elseif state.greeting and now - state.lastGreet > 4 then
			state.greeting = false
			turnTo(state, state.root.Position + state.home.LookVector, false)
		end
	end
end

function Npcs.start()
	init()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(0.4)
			local ok, err = pcall(function()
				greet()
			end)
			if not ok then
				warn(`[Npcs] {err}`)
			end
		end
	end)
end

return Npcs
