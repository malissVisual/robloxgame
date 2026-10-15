--!strict
-- 8.9 SANDBOX, Jinočany step 1 (design/jinocany/NAVRH.md §4): builds the village into the sandbox's map in place of
-- the Alps, from shared/VillageScenery.luau (where everything stands) and shared/VillageLooks.luau (its art: each
-- piece a part). server/SandboxWorld.luau calls it once, after its ground, roads, farmstead and scenery. Everything is
-- anchored, in workspace.Sandbox:
--
--   Ground     (SandboxWorld's) the fields in their crops' colours with their rows and the village's lawns
--              (VillageLawn, Config.VillageWorld.Lawn), flat, flush with the meadow
--   Village    the houses (a Model "VillageHouse" each, attribute VillageHouse its plan id; a terraced group one, its
--              ids in VillageHouses), the landmarks (a Model "Landmark_<id>", attribute VillageLandmark: the chapel
--              green with its MOVING CONTRACTS noticeboard (attribute VillageContracts: decoration for now; the kiosks
--              at the warehouses take the moves), the chapel, the Little Pond, the Corner Drugstore, Hornická's ROAD
--              CLOSED barrier) and the trees of the tree lines and the orchard, in one Atomic model per chunk
--              ("Village_<chunk>", Config.Village.Chunk: with StreamingEnabled each streams whole)
--   Motorway   (a Persistent model: every client always has it, client/VillageTraffic.luau's cars run on it) the D5 at
--              the east edge: its embankment, carriageways, crash barrier and noise wall
--   Far        (a Persistent model) outside the Bounds: VillageLooks.horizon's far fields, tree lines, the power line,
--              the D5 going on, the far roofs and a church tower; no shadows, nothing but its fields collide
-- A piece's words (its `text`) are on its +Z face (Enum.NormalId.Back). Decoration (a piece not solid) never collides
-- nor stops a ray; a shadow only from a mass or a tree's crown big enough to throw one you notice
-- (Config.VillageWorld.Shadow, SandboxScenery.Shadow, RenderBudget).
--
--   VillageWorld.build(world)   builds it into workspace.Sandbox's folder `world` (before it is parented); returns
--                               the houses, the landmarks and the trees it made
--   VillageWorld.model(name, pieces)   a Model (unparented) of VillageLooks pieces on the map (VillageLooks.place's),
--                               one part each, the way build makes them (the six houses to empty will be dressed so)
--   VillageWorld.chunk(world, key)     the Atomic chunk model Village_<key> (VillageLooks.chunkOf) in world.Village,
--                               made when first wanted (where such a house goes)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RenderBudget = require(Shared.RenderBudget)
local SandboxMap = require(Shared.SandboxMap)
local SandboxScenery = require(Shared.SandboxScenery)
local VillageLooks = require(Shared.VillageLooks)
local VillageScenery = require(Shared.VillageScenery)

local VillageWorld = {}

local S = SandboxScenery
local W = Config.VillageWorld
local WORDS = Color3.fromRGB(250, 246, 234)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function material(name: string): Enum.Material
	local ok, found = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and found then found :: Enum.Material else Enum.Material.SmoothPlastic
end

-- A shadow only from a part big enough to throw one you notice (SandboxScenery.Shadow, then RenderBudget's rule).
local function shadowFor(size: Vector3, cframe: CFrame): boolean
	local long = math.max(size.X, size.Y, size.Z)
	local short = math.min(size.X, size.Y, size.Z)
	local middle = size.X + size.Y + size.Z - long - short
	return long >= S.Shadow.Long and middle >= S.Shadow.Wide and RenderBudget.shadowFor(size, cframe)
end

-- A piece's words on its +Z face.
local function label(board: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.4
	gui.MaxDistance = 260
	gui.Parent = board
	local words = Instance.new("TextLabel")
	words.Name = "Label"
	words.BackgroundTransparency = 1
	words.Position = UDim2.fromScale(0.04, 0.1)
	words.Size = UDim2.fromScale(0.92, 0.8)
	words.Text = text
	words.TextScaled = true
	words.Font = Enum.Font.GothamBlack
	words.TextColor3 = WORDS
	words.Parent = gui
end

-- A part of a piece on the map (VillageLooks.place's: at on the map, y from the ground's top, yaw then turn).
local function part(parent: Instance, p: VillageLooks.Piece, far: boolean?): BasePart
	local made: BasePart
	if p.shape == "Wedge" then
		made = Instance.new("WedgePart")
	elseif p.shape == "CornerWedge" then
		made = Instance.new("CornerWedgePart")
	else
		local block = Instance.new("Part")
		if p.shape == "Cylinder" then
			block.Shape = Enum.PartType.Cylinder
		elseif p.shape == "Ball" then
			block.Shape = Enum.PartType.Ball
		elseif p.shape == "Ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = block
		end
		made = block
	end
	local turn = p.turn or { 0, 0, 0 }
	local size = Vector3.new(p.size[1], p.size[2], p.size[3])
	local cframe = CFrame.new(p.at[1], SandboxMap.GroundTop + p.at[2], p.at[3]) * CFrame.Angles(0, math.rad(p.yaw), 0)
		* CFrame.Angles(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
	made.Name = p.name
	made.Anchored = true
	made.Size = size
	made.CFrame = cframe
	made.Color = rgb(p.color)
	made.Material = material(p.material)
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	made.CanTouch = false
	made.Transparency = p.alpha or 0
	local _, _, y0, y1 = VillageLooks.box(p)
	local mass = p.solid and p.tag ~= "door" and p.name ~= "Trunk"
	local crown = p.name == "Crown"
	made.CastShadow = not far and not p.ground and made.Transparency < 1 and (mass or crown) and y1 - y0 >= W.Shadow.Low and shadowFor(size, cframe)
	if not p.solid then
		made.CanCollide = false
		made.CanQuery = false
	end
	if p.text then
		label(made, p.text)
	end
	if p.tag == "contracts" then
		made:SetAttribute("VillageContracts", true)
	end
	made.Parent = parent
	return made
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- One Atomic model per chunk (Config.Village.Chunk's cells), made when first wanted.
local function chunkOf(holder: Instance, chunks: { [string]: Model }, key: string): Model
	local model = chunks[key] or holder:FindFirstChild(`Village_{key}`) :: Model?
	if not model then
		local made = Instance.new("Model")
		made.Name = `Village_{key}`
		made.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		made.Parent = holder
		model = made
	end
	chunks[key] = model :: Model
	return model :: Model
end

function VillageWorld.model(name: string, pieces: { VillageLooks.Piece }): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, p in pieces do
		part(model, p)
	end
	return model
end

function VillageWorld.chunk(world: Instance, key: string): Model
	local village = world:FindFirstChild("Village") or folder(world, "Village")
	return chunkOf(village, {}, key)
end

-- ── The build ──────────────────────────────────────────────────────────────

export type Built = { houses: number, landmarks: number, trees: number }

function VillageWorld.build(world: Instance): Built
	-- the ground: the fields, the village's lawns (SandboxWorld's meadow leaves their holes)
	local ground = world:FindFirstChild("Ground") or folder(world, "Ground")
	for _, f in VillageScenery.fields() do
		for _, p in VillageLooks.field(f.kind, f.rect, f.seed) do
			part(ground, p)
		end
	end
	local L = W.Lawn
	for _, r in SandboxMap.Lawns do
		local lawn = Instance.new("Part")
		lawn.Name = "VillageLawn"
		lawn.Anchored = true
		lawn.Size = Vector3.new(r.x1 - r.x0, 2, r.z1 - r.z0)
		lawn.CFrame = CFrame.new((r.x0 + r.x1) / 2, SandboxMap.GroundTop - 1, (r.z0 + r.z1) / 2)
		lawn.Color = rgb(L.Color)
		lawn.Material = material(L.Material)
		lawn.TopSurface = Enum.SurfaceType.Smooth
		lawn.BottomSurface = Enum.SurfaceType.Smooth
		lawn.CanTouch = false
		lawn.CastShadow = false
		lawn.Parent = ground
	end

	-- the village: its houses, landmarks and trees in their chunks
	local village = folder(world, "Village")
	local chunks: { [string]: Model } = {}
	local built: Built = { houses = 0, landmarks = 0, trees = 0 }
	for _, h in VillageScenery.houses() do
		local pieces = VillageScenery.pieces(h)
		local model = VillageWorld.model("VillageHouse", pieces)
		model:SetAttribute("VillageHouse", h.id)
		model:SetAttribute("Street", h.street)
		if #h.ids > 1 then
			model:SetAttribute("VillageHouses", table.concat(h.ids, ","))
		end
		model.Parent = chunkOf(village, chunks, if pieces[1] then pieces[1].chunk else VillageLooks.chunkOf(h.box.x0, h.box.z0))
		built.houses += 1
	end
	local motorway = Instance.new("Model")
	motorway.Name = "Motorway"
	motorway.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	for _, m in VillageScenery.landmarks() do
		local pieces = VillageScenery.pieces(m)
		local model = VillageWorld.model(`Landmark_{m.id}`, pieces)
		model:SetAttribute("VillageLandmark", m.id)
		model.Parent = if m.far then motorway else chunkOf(village, chunks, if pieces[1] then pieces[1].chunk else "far")
		built.landmarks += 1
	end
	motorway.Parent = world
	for _, t in VillageScenery.trees() do
		local key = VillageLooks.chunkOf(t.x, t.z)
		for _, p in VillageLooks.tree(t.kind, t.x, t.z, t.seed, key) do
			part(chunkOf(village, chunks, key), p)
		end
		built.trees += 1
	end

	-- far away: outside the Bounds, on every client
	local far = Instance.new("Model")
	far.Name = "Far"
	far.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	for _, p in VillageScenery.far() do
		local made = part(far, p, true)
		made.CanQuery = false
		made.CanCollide = p.ground == true
	end
	far.Parent = world
	return built
end

return VillageWorld
