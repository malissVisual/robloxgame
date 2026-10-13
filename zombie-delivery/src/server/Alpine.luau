--!strict
-- 7.1, the Alps, step 1B: builds shared/AlpineLayout.luau's mountains and forests once (World's helpers handed over;
-- Config.Alpine has the numbers). Nothing you play on moves: it only fills what is empty, after everything else is
-- built. 7.1 review: in two steps, so a new server is up long before its mountains are (PLAY and the lighting never
-- wait for the thousands of terrain fills):
--
--   Alpine.start(world, tools)   from World.build (its last piece), the cheap part at once: the valley's colours, the
--                                far silhouettes, the pass and the waterfall, and what the forests may stand on
--   Alpine.finish()              deferred (World.buildLate: Main.server.luau defers it right after World.build): the
--                                terrain's fills, then the forests, with a breath now and then so the server stays awake
--   Alpine.build(world, tools)   both at once
--
--   * The valley's open ground (World's "Ground" tiles) turns lush grass (Config.Alpine.Valley); the terrain's
--     materials get the Alps' colours (Terrain:SetMaterialColor: the grass, the rock, the limestone, the snow, the
--     glacier).
--   * "MountainSilhouettes" (a Persistent model: every client always has it): a square pyramid of four corner wedges
--     inside every big peak (a snow cap over it): with streaming on, a client gets the terrain near it only; these
--     stand in for the far mountains and hide inside the terrain once it is there. No collision, no rays, no shadows.
--     Built first: the far mountains are there from the start.
--   * The portal (the West Pass): the road from the Old Farm into the cliff, the ROAD CLOSED — EVACUATION ZONE barrier
--     at the box's edge (the world's wall stands just behind it), the tunnel's portal and its closed shutter; the
--     waterfall where the river comes out of the north gorge.
--   * The ring of mountains in workspace.Terrain: every fill the layout lists (the cones' layers, the glaciers, the
--     scree, the pass's cliff, then the tunnel's mouth cut out). Config.Alpine.SkipInStudio (a dev toggle) leaves them
--     out in a Studio Play test: the rest still stands (the slope trees on the flat ground under the mountains).
--   * The forests: every tree (a trunk that collides, one needle spire that does not: a SpecialMesh ellipsoid), the
--     meadows' wildflowers and the hay barns and huts, in one Atomic model per Config.Alpine.Trees.Chunk square
--     (streamed together, a coarse far look with LevelOfDetail StreamingMesh). Each stands on whatever a ray straight
--     down finds of what World.build made (the ground tiles, the snow) and of the terrain (the lodge's hill, the old
--     edge hills, the ring's slopes); where the ray finds anything else, or something World built already stands in
--     the tree's room (a fence, a lamp, a sign), the tree is left out (the build log counts them). Only World's own
--     parts count: the rays and the room checks include World's folder as Alpine.start found it (and the terrain),
--     never the cars, the zombies, the people or what the server added later, so the forests are the same on every
--     server, however late they are built (tests/alpinebuild_test.luau). The trees keep apart from each other by the
--     layout itself (its grid, tests/alpine_test.luau): the room check does not see the forest's own trees, whose
--     chunks go into the world at the end, in one go each.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local AlpineLayout = require(Shared.AlpineLayout)

local Alpine = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	sign: (parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?, art: string?, artHeight: number?) -> (),
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up
local BREATH = 0.05 -- seconds of work between two breaths (task.wait)

local MATERIALS: { [string]: Enum.Material } = {
	Air = Enum.Material.Air,
	Grass = Enum.Material.Grass,
	LeafyGrass = Enum.Material.LeafyGrass,
	Ground = Enum.Material.Ground,
	Rock = Enum.Material.Rock,
	Limestone = Enum.Material.Limestone,
	Snow = Enum.Material.Snow,
	Glacier = Enum.Material.Glacier,
	Wood = Enum.Material.Wood,
	WoodPlanks = Enum.Material.WoodPlanks,
	Cobblestone = Enum.Material.Cobblestone,
	Concrete = Enum.Material.Concrete,
	CorrodedMetal = Enum.Material.CorrodedMetal,
	Metal = Enum.Material.Metal,
	Asphalt = Enum.Material.Asphalt,
	Neon = Enum.Material.Neon,
	Glass = Enum.Material.Glass,
	SmoothPlastic = Enum.Material.SmoothPlastic,
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function material(name: string): Enum.Material
	return MATERIALS[name] or Enum.Material.SmoothPlastic
end

-- A breath when this piece has worked BREATH seconds since the last one.
local last = os.clock()
local function breathe()
	if os.clock() - last > BREATH then
		task.wait()
		last = os.clock()
	end
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A part from the layout's numbers, `lift` studs higher (where the ground under it really is).
local function build(tools: Tools, parent: Instance, spec: AlpineLayout.PartSpec, lift: number): Part
	local frame = CFrame.new(spec.x, spec.y + lift, spec.z) * CFrame.Angles(0, spec.yaw, 0) * CFrame.Angles(spec.pitch or 0, 0, 0)
	local p: Part
	if spec.shape == "cylinder" then
		p = tools.part(parent, spec.name, Vector3.new(spec.sy, spec.sx, spec.sz), frame * UPRIGHT, rgb(spec.color), material(spec.material))
		p.Shape = Enum.PartType.Cylinder
	else
		p = tools.part(parent, spec.name, Vector3.new(spec.sx, spec.sy, spec.sz), frame, rgb(spec.color), material(spec.material))
		if spec.shape == "wedge" then
			p.Shape = Enum.PartType.Wedge
		elseif spec.shape == "ball" then
			p.Shape = Enum.PartType.Ball
		elseif spec.shape == "ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
	end
	if not spec.collide then
		tools.deco(p)
	end
	if spec.transparency then
		p.Transparency = spec.transparency
	end
	if spec.glow then
		tools.nightLight(p, rgb(spec.color), rgb(spec.color):Lerp(Color3.new(0, 0, 0), 0.45), "Glass")
	end
	return p
end

-- ── The terrain ────────────────────────────────────────────────────────────

local function fill(ring: AlpineLayout.Ring)
	local terrain = workspace.Terrain
	for _, f in ring.fills do
		local frame = CFrame.new(f.x, f.y, f.z) * CFrame.Angles(0, f.yaw, 0) * CFrame.Angles(f.pitch, 0, 0)
		local m = material(f.material)
		if f.shape == "cylinder" then
			terrain:FillCylinder(frame, f.b, f.a, m)
		elseif f.shape == "ball" then
			terrain:FillBall(Vector3.new(f.x, f.y, f.z), f.a, m)
		elseif f.shape == "wedge" then
			terrain:FillWedge(frame, Vector3.new(f.a, f.b, f.c), m)
		elseif f.shape == "air" then
			terrain:FillBlock(frame, Vector3.new(f.a, f.b, f.c), Enum.Material.Air)
		else
			terrain:FillBlock(frame, Vector3.new(f.a, f.b, f.c), m)
		end
		breathe()
	end
end

-- A square pyramid of four corner wedges (each one's apex over its (+X, -Z) corner, put at the pyramid's middle).
local function pyramid(parent: Instance, name: string, x: number, z: number, y: number, half: number, height: number, yaw: number, color: Color3, look: Enum.Material)
	for q = 0, 3 do
		local p = Instance.new("CornerWedgePart")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = Vector3.new(half, height, half)
		p.CFrame = CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, yaw + q * math.pi / 2, 0) * CFrame.new(-half / 2, 0, half / 2)
		p.Color = color
		p.Material = look
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
	end
end

local function silhouettes(parent: Instance, ring: AlpineLayout.Ring)
	local model = Instance.new("Model")
	model.Name = "MountainSilhouettes"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local C = Config.Alpine.Colors
	for _, s in ring.silhouettes do
		if s.winter then
			pyramid(model, "Peak", s.x, s.z, s.base, s.half, s.height, s.yaw, rgb(C.Snow), Enum.Material.Snow)
		else
			pyramid(model, "Peak", s.x, s.z, s.base, s.half, s.height, s.yaw, rgb(C.Rock), Enum.Material.Rock)
			if s.capY < math.huge then
				pyramid(model, "PeakSnow", s.x, s.z, s.capY, s.capHalf, s.capHeight, s.yaw, rgb(C.Snow), Enum.Material.Snow)
			end
		end
	end
	model.Parent = parent
end

-- ── The forests ────────────────────────────────────────────────────────────

-- Where something may stand: the ground under (x, z) a ray straight down finds (the ground tiles, the winter's snow,
-- the terrain but its water), or nil when it finds anything else. The ray and the room check see World's own parts
-- only (Include: the folders World.build made, the ray the terrain too).
type Ground = { params: RaycastParams, overlap: OverlapParams }
local function groundAt(g: Ground, x: number, z: number, fallback: number): number?
	local hit = workspace:Raycast(Vector3.new(x, 1200, z), Vector3.new(0, -1300, 0), g.params)
	if hit == nil then
		return fallback -- (nothing at all: the layout's own height)
	end
	if hit.Instance == workspace.Terrain then
		return if hit.Material == Enum.Material.Water then nil else hit.Position.Y
	end
	local name = hit.Instance.Name
	if name == "Ground" or name == "Snow" then
		return hit.Position.Y
	end
	return nil
end

-- Is the room (a box `w` wide and `h` high over y) free of anything World built?
local function roomFree(g: Ground, x: number, y: number, z: number, w: number, h: number): boolean
	local found = workspace:GetPartBoundsInBox(CFrame.new(x, y + 1.5 + h / 2, z), Vector3.new(w, h, w), g.overlap)
	return #found == 0
end

local function forests(tools: Tools, parent: Instance, forest: AlpineLayout.Forest, ground: { Instance }): (number, number)
	local holder = folder(parent, "Forests")
	local chunks: { [string]: Model } = {}
	local function chunk(key: string): Model
		local found = chunks[key]
		if found then
			return found
		end
		local model = Instance.new("Model")
		model.Name = `Forest_{key}`
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		pcall(function() -- (the coarse far look: a nicety, never a reason for the forest to fail)
			model.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
		end)
		chunks[key] = model
		return model
	end
	-- (Include, not Exclude: a car, a zombie, a courier or a rental dock where a tree goes never moves the forest)
	local g: Ground = { params = RaycastParams.new(), overlap = OverlapParams.new() }
	local rays = table.clone(ground)
	table.insert(rays, workspace.Terrain)
	g.params.FilterType = Enum.RaycastFilterType.Include
	g.params.FilterDescendantsInstances = rays
	g.overlap.FilterType = Enum.RaycastFilterType.Include
	g.overlap.FilterDescendantsInstances = ground

	local placed, skipped = 0, 0
	for _, t in forest.trees do
		local y = groundAt(g, t.x, t.z, t.y)
		if y == nil or not roomFree(g, t.x, y, t.z, t.canopy * 1.4, t.height) then
			skipped += 1
			continue
		end
		local model = chunk(t.chunk)
		for _, spec in AlpineLayout.treeParts(t) do
			local p = build(tools, model, spec, y - t.y)
			p.CastShadow = t.shadow
		end
		placed += 1
		breathe()
	end
	for _, hut in forest.huts do
		local y = groundAt(g, hut.x, hut.z, 0)
		if y == nil or not roomFree(g, hut.x, y, hut.z, hut.w + 2, hut.h) then
			continue
		end
		local model = chunk(hut.chunk)
		for _, spec in AlpineLayout.hutParts(hut) do
			build(tools, model, spec, y)
		end
	end
	for _, patch in forest.patches do
		local y = groundAt(g, patch.x, patch.z, 0)
		if y == nil then
			continue
		end
		local model = chunk(patch.chunk)
		for _, f in patch.flowers do
			local bloom = tools.part(model, "Flower", Vector3.new(f.size, f.size, f.size), CFrame.new(f.x, y + f.size * 0.3, f.z), rgb(f.color), Enum.Material.SmoothPlastic)
			bloom.Shape = Enum.PartType.Ball
			bloom.CastShadow = false
			tools.deco(bloom)
		end
	end
	for _, model in chunks do
		model.Parent = holder
	end
	return placed, skipped
end

-- ── The pass and the waterfall ─────────────────────────────────────────────

local function portals(tools: Tools, parent: Instance, ring: AlpineLayout.Ring)
	for _, p in ring.portals do
		local holder = folder(parent, `Pass_{p.id}`)
		local parts, signs = AlpineLayout.portalParts(p)
		for _, spec in parts do
			build(tools, holder, spec, 0)
		end
		for _, s in signs do
			local frame = CFrame.new(s.x, s.y, s.z) * CFrame.Angles(0, s.yaw, 0)
			tools.sign(holder, s.text, Vector3.new(s.w, s.h, 0.3), frame, rgb(s.color), if s.background then rgb(s.background) else nil)
		end
	end
	local fall = AlpineLayout.waterfallParts(ring)
	if #fall > 0 then
		local holder = folder(parent, "Waterfall")
		for _, spec in fall do
			build(tools, holder, spec, 0)
		end
	end
end

-- ── The build ──────────────────────────────────────────────────────────────

-- What Alpine.start leaves to Alpine.finish.
type Pending = { tools: Tools, alps: Folder, ring: AlpineLayout.Ring, ground: { Instance } }
local pending: Pending? = nil

-- The cheap part, at once (World.build's last piece): the valley, the terrain's colours, the silhouettes, the pass.
function Alpine.start(world: Instance, tools: Tools)
	local started = os.clock()
	local A = Config.Alpine
	-- (what the forests may stand on: World's folder as World.build made it, before the Alps' own folder)
	local ground = world:GetChildren()
	local alps = folder(world, "Alps")
	-- The valley: the open ground lush grass.
	for _, child in ground do
		if child.Name == "Ground" and child:IsA("BasePart") then
			child.Color = rgb(A.Valley.Color)
			child.Material = material(A.Valley.Material)
		end
	end
	for name, color in A.Colors do
		local m = MATERIALS[name]
		if m then
			workspace.Terrain:SetMaterialColor(m, rgb(color))
		end
	end
	local ring = AlpineLayout.ring()
	silhouettes(alps, ring)
	portals(tools, alps, ring)
	pending = { tools = tools, alps = alps, ring = ring, ground = ground }
	print(string.format("[Alpine] %d silhouettes and the pass in %.2f s (the terrain and the forests follow)", #ring.silhouettes, os.clock() - started))
end

-- The rest, deferred (World.buildLate), once: the terrain's fills (none in a Studio test with SkipInStudio on), then
-- the forests on them.
function Alpine.finish()
	local job = pending
	if job == nil then
		return
	end
	pending = nil
	local started = os.clock()
	last = started
	local ring = job.ring
	local skip = Config.Alpine.SkipInStudio and RunService:IsStudio()
	if not skip then
		fill(ring)
	end
	local filled = os.clock() - started
	local forest = AlpineLayout.forest()
	local placed, skipped = forests(job.tools, job.alps, forest, job.ground)
	local terrain = if skip
		then "the terrain's fills skipped (Config.Alpine.SkipInStudio)"
		else string.format("%d terrain fills (%.1f billion studs³, %.1f s)", #ring.fills, AlpineLayout.volume(ring.fills) / 1e9, filled)
	print(string.format(
		"[Alpine] %d mountains, %s, %d trees (%d left out), %d meadows, %d huts, in %.1f s",
		#ring.cones,
		terrain,
		placed,
		skipped,
		#forest.patches,
		#forest.huts,
		os.clock() - started
	))
end

-- Both at once.
function Alpine.build(world: Instance, tools: Tools)
	Alpine.start(world, tools)
	Alpine.finish()
end

return Alpine
