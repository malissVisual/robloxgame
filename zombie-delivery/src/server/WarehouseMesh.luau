--!strict
-- 8.2 SANDBOX, the ZDC warehouse in the owner's own Blender model (design/blender-warehouse/warehouse.py →
-- roblox/ZDCWarehouseArt.fbx). The owner imports ZDCWarehouseArt.fbx once in Roblox Studio (File → Import 3D, the
-- defaults) and publishes. server/Main.server.luau takes the import out of the Workspace first thing (into ServerStorage);
-- this finds it there (or still in the Workspace: a top-level child named ZDCWarehouseArt, or one holding its markers),
-- learns from its markers how the importer turned and scaled it, and dresses every plot's warehouse with clones:
-- server/Warehouse.luau hands each warehouse Model here once it has built it.
-- The parts warehouse (shared/WarehouseLayout.luau) stays as the fallback and as the collision. Only its parts that are
-- just looks (the attribute WarehouseVisual: the layout's `visual` pieces, i.e. the shell's walls, gables, roof, ribs,
-- bands, trims, gutters and downpipes, the roller door and its bollards, the ZDC sign, the floor, the hall's beams, posts
-- and lamp housings) are hidden, and the solid ones among them still collide where they did. Everything that works keeps
-- working and is seen: the owner's sign over the door and the STOCK board (their words are rewritten), the stands, the
-- UPGRADES desk and its sign, the floor's paint, the bay, the prompts, the hall's lamp glows and their lights. No import,
-- or a warehouse of another size: nothing changes at all.
--
--   WarehouseMesh.ready()       is the import there and complete? (the first call looks for it, out of the world)
--   WarehouseMesh.dress(model)  dresses one plot's warehouse (Warehouse's Model, its attribute Plot); again: true and
--                               nothing more; false: left as it was
--   WarehouseMesh.Looks         each finish's colour and material
--   WarehouseMesh.Attribute     the attribute of a part that is only looks ("WarehouseVisual")
--
-- The pieces are named "warehouse_<finish>" ("warehouse2_<finish>" ... where a finish has more than 10,000 triangles;
-- warehouse.py export_game), all in the building's frame: the middle of its bottom, x east, y up, z south (the door's
-- side). The markers WarehouseMark_o / _x / _y / _z are that origin and 10 studs east, up and south; WarehouseMark_b is
-- the walls' corner (W / 2, H, D / 2) and WarehouseMark_r the ridge (0, H + Ridge, 0): the warehouse the model was made
-- for. (Not "mark_o": FurnitureMesh, HouseMesh and VanMesh look for a model with that when theirs is not named.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local SandboxMap = require(ReplicatedStorage:WaitForChild("Shared").SandboxMap)
local WarehouseLayout = require(ReplicatedStorage:WaitForChild("Shared").WarehouseLayout)
local DayNight = require(script.Parent.DayNight)

local WarehouseMesh = {}

local NAME = "ZDCWarehouseArt"
local MARK = "WarehouseMark"
local ATTRIBUTE = "WarehouseVisual"
WarehouseMesh.Attribute = ATTRIBUTE

type Look = { color: Color3, material: Enum.Material, transparency: number?, reflectance: number?, night: Color3?, shadow: boolean? }
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local P, METAL, GLASS = Enum.Material.SmoothPlastic, Enum.Material.Metal, Enum.Material.Glass
-- warehouse.py's FINISHES (the model has no texture coordinates: smooth colours); night: glows (DayNight.nightLight);
-- shadow false: casts none (the floor and the linings inside, the skylights, the lamps' lenses).
local LOOKS: { [string]: Look } = {
	clad = { color = rgb(188, 194, 200), material = P }, -- the walls' corrugated sheet (the parts' CLAD)
	rib = { color = rgb(160, 167, 175), material = P }, -- its ribs (RIBS)
	orange = { color = rgb(240, 132, 44), material = P }, -- the ZDC stripe, the door's slats, the sign's frame
	concrete = { color = rgb(168, 166, 158), material = P }, -- the plinth
	trim = { color = rgb(42, 45, 50), material = P }, -- corners, gutters, downpipes, barge boards, the sign, the lamps
	roof = { color = rgb(118, 124, 132), material = P },
	roofin = { color = rgb(201, 204, 203), material = P, shadow = false }, -- the roof's underside (the ceiling, the soffits)
	skylight = { color = rgb(207, 227, 234), material = GLASS, transparency = 0.4, shadow = false },
	steel = { color = rgb(74, 78, 86), material = METAL }, -- the portal frames, the door's rails
	galv = { color = rgb(150, 156, 160), material = METAL }, -- the purlins
	liner = { color = rgb(214, 216, 212), material = P, shadow = false }, -- the walls' lining inside
	seam = { color = rgb(180, 184, 182), material = P, shadow = false },
	kick = { color = rgb(142, 140, 134), material = P, shadow = false },
	floor = { color = rgb(150, 152, 150), material = P, shadow = false }, -- the concrete floor's slabs and joints
	floor2 = { color = rgb(140, 142, 140), material = P, shadow = false },
	floor3 = { color = rgb(162, 163, 160), material = P, shadow = false },
	joint = { color = rgb(108, 110, 110), material = P, shadow = false },
	rubber = { color = rgb(26, 27, 29), material = Enum.Material.Rubber },
	yellow = { color = rgb(242, 198, 42), material = P }, -- the bollards
	white = { color = rgb(238, 238, 232), material = P },
	logo = { color = rgb(240, 132, 44), material = P, night = rgb(255, 150, 60) }, -- the sign's ZDC letters
	glow = { color = rgb(214, 208, 192), material = P, night = rgb(255, 236, 200), shadow = false }, -- the wall lights
	red = { color = rgb(200, 50, 46), material = P }, -- the fire bell
}
WarehouseMesh.Looks = LOOKS

type Piece = { finish: string, part: BasePart, cf: CFrame, size: Vector3 }

local pieces: { Piece }? = nil
local box: Vector3? = nil -- the warehouse the model was made for: its walls (W, H, D)
local ridge = 0 -- ... and its ridge's height
local tried = false
local function say(text: string)
	pcall(warn, `{NAME}: {text}`) -- (Studio's output; nothing outside Roblox)
end

-- The imported model: by its name, else any top-level model with the markers in it.
local function find(): Instance?
	for _, place in { ServerStorage, workspace } :: { Instance } do
		local named = place:FindFirstChild(NAME)
		if named then
			return named
		end
	end
	for _, place in { ServerStorage, workspace } :: { Instance } do
		for _, child in place:GetChildren() do
			if child:IsA("Model") and child:FindFirstChild(`{MARK}_o`, true) then
				return child
			end
		end
	end
	return nil
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
		if d:IsA("BasePart") then
			local key = string.match(d.Name, `^{MARK}_(%a)$`)
			if key then
				marks[key] = d.Position
			end
		end
	end
	local o, x, y, z, corner, top = marks.o, marks.x, marks.y, marks.z, marks.b, marks.r
	if not (o and x and y and z and corner and top) then
		say(`the markers {MARK}_o, _x, _y, _z, _b and _r are missing; the warehouses keep their own look`)
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
	local frame = CFrame.fromMatrix(o, ux, uy, uz) -- the building's bottom middle, the game's axes, as the importer placed it
	local found: { Piece } = {}
	for _, d in art:GetDescendants() do
		if not d:IsA("BasePart") or string.sub(d.Name, 1, #MARK) == MARK then
			continue
		end
		local finish = string.match(d.Name, "^warehouse%d*_(%w+)$")
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
		local rel = frame:ToObjectSpace(d.CFrame)
		table.insert(found, { finish = finish, part = d, cf = rel - rel.Position + rel.Position / scale, size = d.Size / scale })
	end
	if #found == 0 then
		say("no pieces named warehouse_<finish>; the warehouses keep their own look")
		return
	end
	local c = frame:PointToObjectSpace(corner) / scale
	pieces = found
	box = Vector3.new(math.abs(c.X) * 2, c.Y, math.abs(c.Z) * 2)
	ridge = (frame:PointToObjectSpace(top) / scale).Y
end

function WarehouseMesh.ready(): boolean
	if not tried then
		local ok, err = pcall(function(): any
			loadArt()
			return nil
		end)
		if not ok then
			say(tostring(err))
		end
	end
	return pieces ~= nil
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

local function dressNow(model: Model): boolean
	local id = model:GetAttribute("Plot")
	local plot = if type(id) == "number" then SandboxMap.Plots[id] else nil
	local want = box
	if not plot or not want then
		return false
	end
	-- the warehouse as the layout builds it on this plot: its walls' box and its ridge (only moved: every one looks south)
	local outline = WarehouseLayout.outline(plot)
	local have = Vector3.new(outline.x1 - outline.x0, plot.warehouse.sy, outline.z1 - outline.z0)
	if (have - want).Magnitude > 0.05 or math.abs(outline.top - ridge) > 0.05 then
		say(`plot {id}: the warehouse is {have} (its ridge {outline.top}), the model was made for {want} (its ridge {ridge}); it keeps its own look`)
		return false
	end
	local base = CFrame.new((outline.x0 + outline.x1) / 2, 0, (outline.z0 + outline.z1) / 2)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute(ATTRIBUTE) == true then
			hide(d)
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "WarehouseMesh"
	for _, item in pieces :: { Piece } do
		local p = item.part:Clone()
		p.Size = item.size
		p.CFrame = base * item.cf
		p.Parent = folder
		local look = LOOKS[item.finish]
		if look.night then
			DayNight.nightLight(p, look.night, look.color, look.material.Name)
		end
	end
	folder.Parent = model
	model:SetAttribute("MeshArt", true)
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
