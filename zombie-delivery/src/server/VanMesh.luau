--!strict
-- 6.25, the ZDC Van in the owner's own Blender model (design/blender-van/van.py → roblox/ZDCVanArt.fbx). The owner
-- imports ZDCVanArt.fbx once in Roblox Studio (File → Import 3D, the defaults) and publishes; this finds the imported
-- model (a top-level child of ServerStorage or Workspace named ZDCVanArt, or one holding the markers), learns from its
-- markers how the importer turned and scaled it, keeps its MeshParts in ServerStorage and dresses every ZDC Van
-- (Vehicles build, STYLES.zdcvan) with clones: the body and the kit on the body that sways, each door on its hinged
-- panel, the wheel on every tyre. No imported model: Vehicles gives the van the fleet's panelled skin (VehicleArt).
--
-- The pieces are named "<group>_<finish>" (van.py export_game): the groups body, kit, doorL / doorR (the cab doors,
-- left = the driver's), rearL / rearR (the back doors) and wheel (the front left one); the finish is the look below
-- ("paint" takes the car's paint). The markers mark_o / mark_x / mark_y / mark_z are the ground under the middle of the
-- van and 10 studs to its right, up and back (the car's axes: the front is -Z); mark_w is the front left wheel's centre.
local ServerStorage = game:GetService("ServerStorage")

local VanMesh = {}

local STYLE = "zdcvan"
local NAME = "ZDCVanArt"
local TOP = 2.1 -- the chassis top over the ground in the model (van.py FLOOR: STYLES.zdcvan's clearance 0.9 + the chassis' 1.2)

type Look = { color: Color3?, material: Enum.Material, transparency: number?, reflectance: number?, lit: Color3? }
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
-- van.py's materials (FINISHES); lit: a lamp (DayNight.nightLight: Neon in this colour at night).
local LOOKS: { [string]: Look } = {
	paint = { material = Enum.Material.SmoothPlastic },
	stripe = { color = rgb(179, 38, 30), material = Enum.Material.SmoothPlastic },
	trim = { color = rgb(32, 35, 38), material = Enum.Material.SmoothPlastic },
	rubber = { color = rgb(22, 23, 24), material = Enum.Material.Rubber },
	glass = { color = rgb(22, 33, 42), material = Enum.Material.Glass, transparency = 0.3, reflectance = 0.1 },
	chrome = { color = rgb(213, 217, 221), material = Enum.Material.Metal, reflectance = 0.3 },
	rim = { color = rgb(185, 189, 193), material = Enum.Material.Metal },
	under = { color = rgb(42, 44, 46), material = Enum.Material.SmoothPlastic },
	plate = { color = rgb(241, 239, 230), material = Enum.Material.SmoothPlastic },
	head = { color = rgb(201, 196, 178), material = Enum.Material.Glass, lit = rgb(255, 246, 214) },
	amber = { color = rgb(206, 132, 48), material = Enum.Material.Glass, lit = rgb(255, 166, 52) },
	red = { color = rgb(130, 26, 22), material = Enum.Material.SmoothPlastic, lit = rgb(255, 36, 30) },
	gun = { color = rgb(59, 62, 66), material = Enum.Material.Metal },
	canred = { color = rgb(163, 34, 26), material = Enum.Material.SmoothPlastic },
	canolive = { color = rgb(78, 90, 42), material = Enum.Material.SmoothPlastic },
	wood = { color = rgb(138, 98, 56), material = Enum.Material.WoodPlanks },
	inside = { color = rgb(43, 45, 49), material = Enum.Material.SmoothPlastic },
	bay = { color = rgb(122, 106, 85), material = Enum.Material.WoodPlanks },
	seat = { color = rgb(58, 60, 64), material = Enum.Material.Fabric },
}

type Piece = { finish: string, part: BasePart, cf: CFrame, size: Vector3 }
type Context = { weld: (BasePart, BasePart) -> (), nightLight: (Instance, Color3?, Color3?, string?) -> () }

local groups: { [string]: { Piece } }? = nil
local function say(text: string)
	pcall(warn, `{NAME}: {text}`) -- (Studio's output; nothing outside Roblox)
end
local wheelAt = Vector3.zero -- the front left wheel's centre (the car's axes, from the ground under its middle)
local tried = false

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
			if child:IsA("Model") and child:FindFirstChild("mark_o", true) then
				return child
			end
		end
	end
	return nil
end

local function load()
	tried = true
	local art = find()
	if not art then
		return
	end
	art.Parent = ServerStorage -- out of the world: only the clones on the vans are seen
	local function at(name: string): Vector3?
		local p = art:FindFirstChild(name, true)
		return if p and p:IsA("BasePart") then p.Position else nil
	end
	local o, x, y, z, w = at("mark_o"), at("mark_x"), at("mark_y"), at("mark_z"), at("mark_w")
	if not (o and x and y and z and w) then
		say("the markers mark_o, mark_x, mark_y, mark_z and mark_w are missing; the ZDC Van keeps its panelled look")
		return
	end
	local scale = (x - o).Magnitude / 10
	local ux = (x - o).Unit
	local uz = ux:Cross((y - o).Unit).Unit
	local uy = uz:Cross(ux).Unit
	if scale < 0.01 or uz:Dot((z - o).Unit) < 0.9 then
		say("the import came out mirrored or flat; the ZDC Van keeps its panelled look")
		return
	end
	local frame = CFrame.fromMatrix(o, ux, uy, uz) -- the car's axes as the importer placed them
	wheelAt = frame:PointToObjectSpace(w) / scale
	local found: { [string]: { Piece } } = {}
	for _, d in art:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local group, finish = string.match(d.Name, "^(%a+)_(%a+)$")
		local look = if finish then LOOKS[finish] else nil
		if not group or not finish or group == "mark" or not look then
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
		d.Anchored = false
		d.CanCollide, d.CanQuery, d.CanTouch, d.Massless = false, false, false, true
		d.CollisionGroup = "Car"
		d.Material = look.material
		if look.color then
			d.Color = look.color
		end
		d.Transparency = look.transparency or 0
		d.Reflectance = look.reflectance or 0
		d.CastShadow = finish ~= "glass"
		local rel = frame:ToObjectSpace(d.CFrame)
		local list = found[group] or {}
		found[group] = list
		table.insert(list, { finish = finish, part = d, cf = rel - rel.Position + rel.Position / scale, size = d.Size / scale })
	end
	if not (found.body and found.wheel and found.doorL and found.doorR and found.rearL and found.rearR) then
		say("a body, a wheel and the four doors are needed; the ZDC Van keeps its panelled look")
		return
	end
	groups = found
end

-- Does this style wear the imported model (the ZDC Van, once ZDCVanArt is in the place)?
function VanMesh.ready(style: string): boolean
	if style ~= STYLE then
		return false
	end
	if not tried then
		local ok, err = pcall(load)
		if not ok then
			say(tostring(err))
		end
	end
	return groups ~= nil
end

-- One group's pieces where `at` (the ground under the car's middle, the car's axes) puts them, welded to `to`.
local function dress(parent: Instance, group: string, at: CFrame, to: BasePart, paint: Color3, paintParts: { BasePart }, context: Context)
	local list = if groups then groups[group] else nil
	for _, piece in list or {} do
		local p = piece.part:Clone()
		p.Size = piece.size
		p.CFrame = at * piece.cf
		if piece.finish == "paint" then
			p.Color = paint
			table.insert(paintParts, p)
		end
		p.Parent = parent
		context.weld(to, p)
		local look = LOOKS[piece.finish]
		if look.lit then
			context.nightLight(p, look.lit, look.color, look.material.Name)
		end
	end
end

local function folder(model: Instance, name: string): Instance
	local f = model:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
	end
	return f :: Instance
end

-- The body (with its lamps, the interior and the kit) on the body that sways; top: the chassis top centre.
function VanMesh.body(model: Model, look: BasePart, top: CFrame, paint: Color3, paintParts: { BasePart }, context: Context)
	local f = folder(model, "VanMesh")
	local ground = top * CFrame.new(0, -TOP, 0)
	dress(f, "body", ground, look, paint, paintParts, context)
	dress(f, "kit", ground, look, paint, paintParts, context)
end

-- A cab door (side -1: the driver's, left) on its panel, or a back door (`back`), closed as the car is built.
function VanMesh.door(model: Model, panel: BasePart, side: number, back: boolean, top: CFrame, paint: Color3, paintParts: { BasePart }, context: Context)
	local group = (if back then "rear" else "door") .. (if side < 0 then "L" else "R")
	dress(folder(model, "VanMesh"), group, top * CFrame.new(0, -TOP, 0), panel, paint, paintParts, context)
end

-- The wheel on a tyre (the tyre's centre and the car's axes, x: its offset from the middle): the model's front left
-- wheel moved along the axle onto the tyre, turned round for the right side (its rim faces out).
function VanMesh.wheel(model: Model, tyre: BasePart, x: number, context: Context)
	local f = folder(model, "VanMesh")
	local side = if x < 0 then -1 else 1
	local onto = tyre.CFrame * CFrame.new(side * math.abs(wheelAt.X) - x, 0, 0)
	if side > 0 then
		onto *= CFrame.Angles(0, math.pi, 0)
	end
	local list = if groups then groups.wheel else nil
	for _, piece in list or {} do
		local p = piece.part:Clone()
		p.Size = piece.size
		p.CFrame = onto * CFrame.new(-wheelAt) * piece.cf
		p.CastShadow = false
		p.Parent = f
		context.weld(tyre, p)
	end
end

return VanMesh
