--!strict
-- 8.2 SANDBOX, the ZDC warehouse in the owner's own Blender model (design/blender-warehouse/warehouse.py →
-- roblox/ZDCWarehouseArt.fbx: the warehouse in five levels, 8.0.4). The owner imports ZDCWarehouseArt.fbx once in
-- Roblox Studio (File → Import 3D, the defaults) and publishes. server/Main.server.luau takes the import out of the
-- Workspace first thing (into ServerStorage); this finds it there (or still in the Workspace: a top-level child named
-- ZDCWarehouseArt, or one holding its markers), learns from its markers how the importer turned and scaled it and
-- dresses every plot's warehouse with one level's clones: server/Warehouse.luau hands each warehouse Model here once it
-- has built it. The level is WarehouseMesh.level(plot) (today Config.Warehouse.ArtLevel, 4: the size the game's
-- warehouse is; a later "warehouse level" upgrade answers it per plot).
-- The parts warehouse (shared/WarehouseLayout.luau) stays as the fallback and as the collision. Only its parts that are
-- just looks (the attribute WarehouseVisual: the layout's `visual` pieces, i.e. the shell's walls, gables, roof, ribs,
-- bands, trims, gutters and downpipes, the roller door and its bollards, the ZDC sign, the floor, the hall's beams, posts,
-- lamp housings and lamp glows) are hidden: the solid ones still collide where they did, the glows' lights still shine.
-- Everything else keeps working and is seen: the owner's sign over the door and the STOCK board (their words are
-- rewritten), the stands, the UPGRADES desk and its sign, the floor's paint, the bay, the prompts. The level's things
-- outside the walls that one bumps into (level 4: the office annex) get an unseen solid block each. No import, a level
-- the import lacks, or a warehouse of another size than the level: nothing changes at all.
--
--   WarehouseMesh.ready()        is the import there (any level complete)? (the first call looks, out of the world)
--   WarehouseMesh.level(plot)    the level a plot's warehouse wears (1 … 5)
--   WarehouseMesh.dress(model)   dresses one plot's warehouse (Warehouse's Model, its attribute Plot); again: true and
--                                nothing more; false: left as it was
--   WarehouseMesh.Looks          each finish's colour and material
--   WarehouseMesh.Attribute      the attribute of a part that is only looks ("WarehouseVisual")
--
-- The import (warehouse.py export_game; design/blender-warehouse/NAVOD.md): the pieces "lvl<N>_<finish>" (past 10,000
-- triangles "lvl<N>b_<finish>" ...), each level from its origin: the roller door's middle on the ground, x to the right
-- seen from outside, y up, z into the building. mark_o / mark_x / mark_y / mark_z are those axes (10 studs each);
-- mark_lvl<N> each level's origin; mark_lvl<N>_box the building's corner (W / 2, H, D), mark_lvl<N>_door the door's
-- (its half width, its height, 0) and mark_lvl<N>_top the roof's top (0, H + its rise, 0): the warehouse that level is.
-- collide_lvl<N>_<k> are boxes (a prop's: the game makes an unseen solid block of each).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local SandboxMap = require(ReplicatedStorage:WaitForChild("Shared").SandboxMap)
local WarehouseLayout = require(ReplicatedStorage:WaitForChild("Shared").WarehouseLayout)

local WarehouseMesh = {}

local NAME = "ZDCWarehouseArt"
local ATTRIBUTE = "WarehouseVisual"
local LEVELS = 5
WarehouseMesh.Attribute = ATTRIBUTE

type Look = { color: Color3, material: Enum.Material, transparency: number?, reflectance: number?, shadow: boolean? }
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local P, METAL, GLASS = Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Glass
-- warehouse.py's FINISHES (the model has no texture coordinates: smooth colours). shadow false: casts none.
local LOOKS: { [string]: Look } = {
	plaster = { color = rgb(216, 212, 204), material = P },
	metal = { color = rgb(142, 154, 166), material = P }, -- the corrugated sheet
	metal2 = { color = rgb(111, 124, 136), material = P }, -- the darker sheet, the roof's seams, the ridge
	concrete = { color = rgb(167, 163, 155), material = P }, -- the plinth, ramps, planters
	floor = { color = rgb(156, 154, 148), material = P, shadow = false }, -- the concrete floor's slabs and joints
	floor2 = { color = rgb(148, 146, 140), material = P, shadow = false },
	floor3 = { color = rgb(166, 164, 158), material = P, shadow = false },
	joint = { color = rgb(116, 114, 110), material = P, shadow = false },
	orange = { color = rgb(232, 118, 43), material = P }, -- ZDC's: the band, the corners, the door's frame, the letters
	trim = { color = rgb(237, 235, 230), material = P },
	steel = { color = rgb(90, 96, 104), material = METAL }, -- the trusses, the rails, the canopy
	dark = { color = rgb(42, 45, 49), material = P },
	roof = { color = rgb(75, 80, 87), material = P },
	glass = { color = rgb(47, 66, 82), material = GLASS, reflectance = 0.2 },
	glasslit = { color = rgb(191, 214, 226), material = P, shadow = false }, -- the windows seen from inside
	skylight = { color = rgb(216, 230, 234), material = GLASS, reflectance = 0.1 },
	glow = { color = Color3.fromRGB(table.unpack(Config.SandboxLight.Warehouse.MeshGlow)), material = Enum.Material.Neon, shadow = false }, -- the lamps (the hall's always lit; 8.3: Config.SandboxLight)
	yellow = { color = rgb(242, 194, 48), material = P }, -- the bollards
	door = { color = rgb(201, 204, 208), material = P, reflectance = 0.05 },
	wood = { color = rgb(154, 117, 80), material = P },
	rubber = { color = rgb(26, 26, 28), material = Enum.Material.Rubber },
	solar = { color = rgb(30, 46, 74), material = GLASS, reflectance = 0.2 },
	green = { color = rgb(79, 127, 59), material = P },
	red = { color = rgb(200, 50, 46), material = P },
	white = { color = rgb(246, 244, 238), material = P },
	zinc = { color = rgb(155, 162, 166), material = METAL }, -- the gutters and downpipes
}
WarehouseMesh.Looks = LOOKS

type Piece = { finish: string, part: BasePart, cf: CFrame, size: Vector3 }
type Solid = { cf: CFrame, size: Vector3 }
type Level = { pieces: { Piece }, solids: { Solid }, box: Vector3?, door: Vector3?, top: Vector3? }

local levels: { [number]: Level } = {}
local tried = false
local function say(text: string)
	pcall(warn, `{NAME}: {text}`) -- (Studio's output; nothing outside Roblox)
end

-- The imported model: by its name, else any top-level model with its markers in it.
local function find(): Instance?
	for _, place in { ServerStorage, workspace } :: { Instance } do
		local named = place:FindFirstChild(NAME)
		if named then
			return named
		end
	end
	for _, place in { ServerStorage, workspace } :: { Instance } do
		for _, child in place:GetChildren() do
			if child:IsA("Model") and child:FindFirstChild("mark_o", true) and child:FindFirstChild("mark_lvl1", true) then
				return child
			end
		end
	end
	return nil
end

local function levelOf(n: number): Level
	local lv = levels[n]
	if not lv then
		lv = { pieces = {}, solids = {}, box = nil, door = nil, top = nil }
		levels[n] = lv
	end
	return lv
end

local function loadArt()
	tried = true
	local art = find()
	if not art then
		return
	end
	art.Parent = ServerStorage -- out of the world: only the clones on the warehouses are seen
	local marks: { [string]: Vector3 } = {}
	for _, d in art:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 5) == "mark_" then
			marks[string.sub(d.Name, 6)] = d.Position
		end
	end
	local o, x, y, z = marks.o, marks.x, marks.y, marks.z
	if not (o and x and y and z) then
		say("the markers mark_o, mark_x, mark_y and mark_z are missing; the warehouses keep their own look")
		return
	end
	local scale = (x - o).Magnitude / 10
	local ux = (x - o).Unit
	local uz = ux:Cross((y - o).Unit).Unit
	local uy = uz:Cross(ux).Unit
	if scale < 0.01 or uz:Dot((z - o).Unit) < 0.9 then
		say("the import came out mirrored or flat; the warehouses keep their own look")
		return
	end
	local frame = CFrame.fromMatrix(o, ux, uy, uz) -- the export's axes as the importer placed them
	-- each level's origin, its markers from there
	local origins: { [number]: Vector3 } = {}
	for n = 1, LEVELS do
		local at = marks[`lvl{n}`]
		if at then
			local origin = frame:PointToObjectSpace(at) / scale
			origins[n] = origin
			local lv = levelOf(n)
			local function mark(key: string): Vector3?
				local p = marks[`lvl{n}_{key}`]
				return if p then frame:PointToObjectSpace(p) / scale - origin else nil
			end
			lv.box, lv.door, lv.top = mark("box"), mark("door"), mark("top")
		end
	end
	for _, d in art:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local n, finish = string.match(d.Name, "^lvl(%d+)%l?_(%w+)$")
		local solidOf = string.match(d.Name, "^collide_lvl(%d+)_%d+$")
		local level = tonumber(n or solidOf)
		local origin = if level then origins[level] else nil
		if not level or not origin then
			continue
		end
		local rel = frame:ToObjectSpace(d.CFrame)
		local cf = rel - rel.Position + (rel.Position / scale - origin)
		if solidOf then
			table.insert(levelOf(level).solids, { cf = cf, size = d.Size / scale })
			continue
		end
		local look = if finish then LOOKS[finish] else nil
		if not finish or not look then
			continue
		end
		for _, extra in d:GetChildren() do
			if extra:IsA("SurfaceAppearance") or extra:IsA("Decal") or extra:IsA("Texture") then
				extra:Destroy() -- (the importer's own material: the finish below is the look)
			end
		end
		if d:IsA("MeshPart") then
			pcall(function()
				d.TextureID = ""
			end)
		end
		d.Anchored = true
		d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		d.Material = look.material
		d.Color = look.color
		d.Transparency = look.transparency or 0
		d.Reflectance = look.reflectance or 0
		d.CastShadow = look.shadow ~= false
		table.insert(levelOf(level).pieces, { finish = finish, part = d, cf = cf, size = d.Size / scale })
	end
	local complete = 0
	for n, lv in levels do
		if #lv.pieces > 0 and lv.box and lv.door and lv.top then
			complete += 1
		else
			levels[n] = nil
		end
	end
	if complete == 0 then
		say("no level has its pieces lvl<N>_<finish> and its markers mark_lvl<N>, _box, _door, _top; the warehouses keep their own look")
	end
end

function WarehouseMesh.ready(): boolean
	if not tried then
		local ok, err = pcall(function(): any
			loadArt()
			return nil
		end)
		if not ok then
			say(tostring(err))
			table.clear(levels)
		end
	end
	return next(levels) ~= nil
end

-- The level a plot's warehouse wears: Config.Warehouse.ArtLevel (the size the game's warehouse is today). The one
-- place a later "warehouse level" upgrade answers per plot.
function WarehouseMesh.level(_plot: number?): number
	local want = (Config.Warehouse :: any).ArtLevel
	if type(want) ~= "number" or want ~= want then
		return 4
	end
	return math.clamp(math.floor(want), 1, LEVELS)
end

-- A part that is only looks, hidden (it still collides and is queried if it did; its lights keep shining).
local function hide(part: BasePart)
	part.Transparency = 1
	part.CastShadow = false
	for _, d in part:GetChildren() do
		if d:IsA("Decal") then -- (a Texture is a Decal too)
			d.Transparency = 1
		elseif d:IsA("SurfaceGui") then
			d.Enabled = false
		end
	end
end

local function close(a: number, b: number): boolean
	return math.abs(a - b) < 0.05
end

local function dressNow(model: Model): boolean
	local id = model:GetAttribute("Plot")
	local plot = if type(id) == "number" then SandboxMap.Plots[id] else nil
	if not plot then
		return false
	end
	local n = WarehouseMesh.level(plot.id)
	local lv = levels[n]
	if not lv then
		say(`plot {plot.id}: the import has no level {n}; it keeps its own look`)
		return false
	end
	-- the warehouse as the layout builds it on this plot (its door looks south: only moved) against the level
	local outline = WarehouseLayout.outline(plot)
	local door = WarehouseLayout.door(plot)
	local box, gap, top = lv.box :: Vector3, lv.door :: Vector3, lv.top :: Vector3
	if not (close(math.abs(box.X) * 2, outline.x1 - outline.x0) and close(box.Y, plot.warehouse.sy) and close(box.Z, outline.z1 - outline.z0)
		and close(math.abs(gap.X) * 2, door.width) and close(gap.Y, door.height) and close(top.Y, outline.top)) then
		say(`plot {plot.id}: the warehouse is {outline.x1 - outline.x0} × {plot.warehouse.sy} × {outline.z1 - outline.z0} (door {door.width} × {door.height}, ridge {outline.top}), level {n} is {math.abs(box.X) * 2} × {box.Y} × {box.Z} (door {math.abs(gap.X) * 2} × {gap.Y}, top {top.Y}); it keeps its own look`)
		return false
	end
	-- the level's origin on the door's middle, on the ground; its z into the building (north)
	local base = CFrame.new(door.x, 0, door.z) * CFrame.Angles(0, math.pi, 0)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute(ATTRIBUTE) == true then
			hide(d)
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "WarehouseMesh"
	for _, item in lv.pieces do
		local p = item.part:Clone()
		p.Size = item.size
		p.CFrame = base * item.cf
		p.Parent = folder
	end
	for k, s in lv.solids do
		local block = Instance.new("Part")
		block.Name = `WarehouseSolid{k}`
		block.Size = s.size
		block.CFrame = base * s.cf
		block.Anchored = true
		block.CanCollide, block.CanQuery, block.CanTouch = true, true, false
		block.Transparency = 1
		block.CastShadow = false
		block.Parent = folder
	end
	folder.Parent = model
	model:SetAttribute("MeshArt", true)
	model:SetAttribute("WarehouseLevel", n)
	return true
end

-- Dresses one plot's warehouse (server/Warehouse.luau, once it is built). Never throws: false leaves it as it was.
function WarehouseMesh.dress(model: Model): boolean
	if model:GetAttribute("MeshArt") == true then
		return true
	end
	if not WarehouseMesh.ready() then
		return false
	end
	local ok, result = pcall(dressNow, model)
	if not ok then
		say(tostring(result))
		return false
	end
	return result == true
end

return WarehouseMesh
