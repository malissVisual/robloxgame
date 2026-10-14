--!strict
-- 8.0 SANDBOX, the walk-in Sprinter in the owner's own Blender model (design/blender-sprinter/sprinter.py →
-- roblox/ZDCSprinterArt.fbx). The owner imports ZDCSprinterArt.fbx once in Roblox Studio (File → Import 3D, the
-- defaults) and publishes; this finds the imported model (a top-level child of ServerStorage or Workspace named
-- ZDCSprinterArt, or one holding its markers), learns from its markers how the importer turned and scaled it, keeps its
-- MeshParts in ServerStorage and dresses every sprinter car with clones: the body on the body that sways (BodyRoot, else
-- the chassis), each door on the part its door moves, the wheel on every tyre. The parts look (style "sprinter",
-- shared/SprinterLooks.luau) stays as the fallback and as the collision: only its parts that are looks are hidden. No
-- imported model: nothing at all (no hooks, nothing hidden).
--
--   SprinterMesh.start()       at the server's start (server/Main.server.luau): takes the import out of the world, then
--                              dresses every sprinter car as it is put into the world (workspace or workspace.Cars)
--   SprinterMesh.ready()       is the import there and complete?
--   SprinterMesh.dress(model)  dresses one sprinter car model (once: again is a no-op); false: left as it was
--   SprinterMesh.Looks         each finish's colour and material
-- 8.3, the PAINT shop (server/VanPaint.luau, shared/VanLook.luau): the paint and stripe finishes (Config.VanPaint.Finishes)
-- take the van's paint: a dressed piece of one keeps its own look in its attributes FactoryColor / FactoryMaterial and
-- wears the car model's <prefix>Color / <prefix>Material / <prefix>Reflectance when it has them (paintPiece; VanLook
-- repaints the pieces when the van is painted again).
--
-- The contract with the parts model (design/blender-sprinter/NAVOD.md, its numbers in design/blender-sprinter/roblox/
-- ZDCSprinterArt.json; the axes are the car's: x right, y up, z back, from the ground under the van's middle):
-- * a sprinter is a Model whose attribute CarId is a Config.Cars / AmbientCars id of the style "sprinter" (or the
--   sandbox's Config.Sandbox.Van), or whose attribute Sprinter is true. Its PrimaryPart (the chassis) is centred over
--   the van's middle and its top is the cargo floor, 2.4 over the ground; "BodyRoot" is the body that sways, if any;
-- * a part that is only looks carries the attribute SprinterVisual = true (or sits in a Model / Folder that does): it is
--   hidden (Transparency 1, its Decals, Textures and SurfaceGuis too). Nothing else is touched: the collision, the
--   seats, the prompts, the attachments, the hinges and the lights inside hidden parts keep working;
-- * the doors are Models named BackDoorL, BackDoorR, SideDoor (and CabDoorL, CabDoorR): the model's door is welded to
--   the part that door group moves (its PrimaryPart, else its part on a Motor6D, else its biggest part), so it swings
--   or slides with it. Left = the driver's side (-x). A cab door with no group: the part on a Motor6D "DoorHinge" on
--   its side; a back door: on a Motor6D "BackHinge". A door that is open when the car is dressed is fine: the model's
--   door goes where it would be closed (Part0 * C0 * C1:Inverse()), moved as the part is;
-- * the tyres are the parts named "Tyre" on a Motor6D "WheelMotor": the model's wheel goes onto each (scaled to the
--   tyre's diameter, the model's own track), and the tyre and the non-colliding parts welded to it are hidden.
--
-- The pieces are named "<group>_<finish>" (sprinter.py export_game): the groups Body, CabDoorL, CabDoorR, SideDoor,
-- BackDoorL, BackDoorR and Wheel (the front left one). The markers SprinterMark_o / _x / _y / _z are the ground under the
-- van's middle and 10 studs to its right, up and back; SprinterMark_w is the front left wheel's centre. (Not "mark_o":
-- server/VanMesh.luau and server/FurnitureMesh.luau look for a model with that when theirs is not named.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local DayNight = require(script.Parent.DayNight)

local SprinterMesh = {}

local NAME = "ZDCSprinterArt"
local MARK = "SprinterMark"
local STYLE = "sprinter"
local FLOOR = 2.4 -- the chassis top (the cargo floor) over the ground (sprinter.py FLOOR, the parts model's chassis top)
local GROUPS = { "Body", "CabDoorL", "CabDoorR", "SideDoor", "BackDoorL", "BackDoorR", "Wheel" }
-- Each door: its fallback joint (a Motor6D of this name on that side) when the car has no door group of that name.
local DOORS: { { name: string, joint: string?, side: number } } = {
	{ name = "CabDoorL", joint = "DoorHinge", side = -1 },
	{ name = "CabDoorR", joint = "DoorHinge", side = 1 },
	{ name = "SideDoor", joint = nil, side = 1 },
	{ name = "BackDoorL", joint = "BackHinge", side = -1 },
	{ name = "BackDoorR", joint = "BackHinge", side = 1 },
}
local DOOR_NAMES: { [string]: boolean } = {}
for _, door in DOORS do
	DOOR_NAMES[door.name] = true
end

type Look = { color: Color3, material: Enum.Material, transparency: number?, reflectance: number?, lit: Color3? }
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
-- sprinter.py's materials (FINISHES); lit: a lamp (DayNight.nightLight: Neon in this colour at night).
local LOOKS: { [string]: Look } = {
	paint = { color = rgb(217, 204, 176), material = Enum.Material.SmoothPlastic }, -- the ZDC cream
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
	inside = { color = rgb(43, 45, 49), material = Enum.Material.SmoothPlastic },
	seat = { color = rgb(58, 60, 64), material = Enum.Material.Fabric },
	ply = { color = rgb(184, 153, 108), material = Enum.Material.Wood }, -- the cargo bay's plywood
	floor = { color = rgb(74, 58, 44), material = Enum.Material.DiamondPlate },
	rail = { color = rgb(169, 174, 179), material = Enum.Material.Metal },
	inner = { color = rgb(201, 196, 184), material = Enum.Material.SmoothPlastic }, -- the bay's painted steel
	lamp = { color = rgb(255, 246, 226), material = Enum.Material.Neon }, -- the bay's ceiling lights, always on
}
SprinterMesh.Looks = LOOKS

type Piece = { finish: string, part: BasePart, cf: CFrame, size: Vector3 }

-- 8.3, the PAINT shop: a piece of a painted finish (Config.VanPaint.Finishes: finish → the attributes' prefix) keeps its
-- own look (FactoryColor, FactoryMaterial) and wears the van's paint when the model has one (nil: its own look).
local function paintPiece(model: Model, part: BasePart, finish: string)
	local paint = (Config :: any).VanPaint
	local prefix = if type(paint) == "table" and type(paint.Finishes) == "table" then paint.Finishes[finish] else nil
	local look = LOOKS[finish]
	if type(prefix) ~= "string" or not look then
		return
	end
	part:SetAttribute("FactoryColor", look.color)
	part:SetAttribute("FactoryMaterial", look.material.Name)
	local color = model:GetAttribute(`{prefix}Color`)
	if typeof(color) == "Color3" then
		part.Color = color
	end
	local name = model:GetAttribute(`{prefix}Material`)
	if type(name) == "string" then
		local ok, found = pcall(function(): any
			return (Enum.Material :: any)[name]
		end)
		if ok and found ~= nil then
			part.Material = found
		end
	end
	local reflectance = model:GetAttribute(`{prefix}Reflectance`)
	if type(reflectance) == "number" then
		part.Reflectance = reflectance
	end
end

local groups: { [string]: { Piece } }? = nil
local wheelAt = Vector3.zero -- the front left wheel's centre (the car's axes, from the ground under its middle)
local wheelRadius = 1.2
local tried = false
local started = false
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

-- How tall a piece is in the car's axes (its box turned by the import's turn).
local function heightOf(piece: Piece): number
	local _, _, _, _, _, _, r10, r11, r12 = piece.cf:GetComponents()
	return math.abs(r10) * piece.size.X + math.abs(r11) * piece.size.Y + math.abs(r12) * piece.size.Z
end

local function loadArt()
	tried = true
	local art = find()
	if not art then
		return
	end
	art.Parent = ServerStorage -- out of the world: only the clones on the vans are seen
	local marks: { [string]: Vector3 } = {}
	for _, d in art:GetDescendants() do
		if d:IsA("BasePart") then
			local key = string.match(d.Name, `^{MARK}_(%a)$`)
			if key then
				marks[key] = d.Position
			end
		end
	end
	local o, x, y, z, w = marks.o, marks.x, marks.y, marks.z, marks.w
	if not (o and x and y and z and w) then
		say(`the markers {MARK}_o, _x, _y, _z and _w are missing; the Sprinter keeps its parts look`)
		return
	end
	local scale = (x - o).Magnitude / 10
	local ux = (x - o).Unit
	local uz = ux:Cross((y - o).Unit).Unit
	local uy = uz:Cross(ux).Unit
	if scale < 0.01 or uz:Dot((z - o).Unit) < 0.9 then
		say("the import came out mirrored or flat; the Sprinter keeps its parts look")
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
		if not group or not finish or group == MARK or not look then
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
		d.Material = look.material
		d.Color = look.color
		d.Transparency = look.transparency or 0
		d.Reflectance = look.reflectance or 0
		d.CastShadow = finish ~= "glass" and finish ~= "lamp"
		local rel = frame:ToObjectSpace(d.CFrame)
		local list = found[group] or {}
		found[group] = list
		table.insert(list, { finish = finish, part = d, cf = rel - rel.Position + rel.Position / scale, size = d.Size / scale })
	end
	for _, name in GROUPS do
		if not found[name] then
			say(`no pieces of the group {name}; the Sprinter keeps its parts look`)
			return
		end
	end
	local tallest = 0
	for _, piece in found.Wheel do
		tallest = math.max(tallest, heightOf(piece))
	end
	wheelRadius = if tallest > 0.2 then tallest / 2 else wheelRadius
	groups = found
end

-- Is ZDCSprinterArt imported (and complete)? The first call looks for it (and takes it out of the world).
function SprinterMesh.ready(): boolean
	if not tried then
		local ok, err = pcall(function(): any
			loadArt()
			return nil
		end)
		if not ok then
			say(tostring(err))
		end
	end
	return groups ~= nil
end

-- The car ids that are sprinters (Config.Cars and AmbientCars of the style, the sandbox's van).
local sprinterIds: { [string]: boolean }? = nil
local function idsOf(): { [string]: boolean }
	local known = sprinterIds
	if known then
		return known
	end
	local ids: { [string]: boolean } = {}
	local cfg = Config :: any
	for _, list in { cfg.Cars or {}, cfg.AmbientCars or {} } :: { any } do
		for _, def in list do
			if type(def) == "table" and def.style == STYLE and type(def.id) == "string" then
				ids[def.id] = true
			end
		end
	end
	local sandbox = cfg.Sandbox
	if type(sandbox) == "table" and type(sandbox.Van) == "string" then
		ids[sandbox.Van] = true
	end
	sprinterIds = ids
	return ids
end

local function isSprinter(model: Instance): boolean
	if not model:IsA("Model") then
		return false
	end
	if model:GetAttribute("Sprinter") == true then
		return true
	end
	local id = model:GetAttribute("CarId")
	return type(id) == "string" and idsOf()[id] == true
end

-- A part that is only looks, hidden (the lights and prompts inside it keep working).
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

-- Dresses a sprinter car model (Vehicles' build, style "sprinter") once ZDCSprinterArt is imported: the model's pieces
-- welded to its body, doors and tyres, its looks hidden. Again on a dressed model: true, nothing more. False: left as
-- it was (no import, no chassis).
function SprinterMesh.dress(model: Model): boolean
	if not SprinterMesh.ready() then
		return false
	end
	if model:GetAttribute("SprinterMesh") then
		return true
	end
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis")
	if not chassis or not chassis:IsA("BasePart") then
		return false
	end
	local art = groups :: { [string]: { Piece } }
	local ground = chassis.CFrame * CFrame.new(0, chassis.Size.Y / 2 - FLOOR, 0) -- the ground under the van's middle
	local rootPart = model:FindFirstChild("BodyRoot")
	local body: BasePart = if rootPart and rootPart:IsA("BasePart") then rootPart else chassis

	-- One pass: the joints (what moves which part), the tyres, the parts welded to them, the looks.
	local drivers: { [BasePart]: Motor6D } = {}
	local tyres: { BasePart } = {}
	local onTyre: { [BasePart]: BasePart } = {}
	local looks: { BasePart } = {}
	local doorGroups: { [string]: Instance } = {}
	for _, d in model:GetDescendants() do
		if DOOR_NAMES[d.Name] and (d:IsA("Model") or d:IsA("Folder") or d:IsA("BasePart")) and not doorGroups[d.Name] then
			doorGroups[d.Name] = d
		end
		if d:IsA("Motor6D") then
			local p1 = d.Part1
			if p1 then
				drivers[p1] = d
				if d.Name == "WheelMotor" and p1.Name == "Tyre" then
					table.insert(tyres, p1)
				end
			end
		elseif d:IsA("WeldConstraint") then
			local p0, p1 = d.Part0, d.Part1
			if p0 and p1 and p0.Name == "Tyre" then
				onTyre[p1] = p0
			end
		end
		if d:GetAttribute("SprinterVisual") == true then
			if d:IsA("BasePart") then
				table.insert(looks, d)
			else
				for _, e in d:GetDescendants() do
					if e:IsA("BasePart") then
						table.insert(looks, e)
					end
				end
			end
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "SprinterMesh"
	local function put(piece: Piece, at: CFrame, onto: BasePart)
		local p = piece.part:Clone()
		p.Size = piece.size
		p.CFrame = at * piece.cf
		p.Parent = folder
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = onto
		weld.Part1 = p
		weld.Parent = p
		local look = LOOKS[piece.finish]
		if look.lit then
			DayNight.nightLight(p, look.lit, look.color, look.material.Name)
		end
		paintPiece(model, p, piece.finish) -- 8.3: the van's paint (the PAINT shop)
	end

	-- The body (with its lamps, the cab and the cargo bay) on the body that sways.
	for _, piece in art.Body do
		put(piece, ground, body)
	end

	-- Each door on the part its door moves: where it is when closed, moved as that part is now.
	local function moverOf(group: Instance): BasePart?
		if group:IsA("BasePart") then
			return group
		end
		if group:IsA("Model") and group.PrimaryPart then
			return group.PrimaryPart
		end
		local biggest: BasePart? = nil
		for _, d in group:GetDescendants() do
			if d:IsA("BasePart") then
				if drivers[d] then
					return d
				end
				if not biggest or d.Size.Magnitude > (biggest :: BasePart).Size.Magnitude then
					biggest = d
				end
			end
		end
		return biggest
	end
	local function byJoint(joint: string, side: number): BasePart?
		for part, motor in drivers do
			if motor.Name == joint and ground:PointToObjectSpace(part.Position).X * side > 0 then
				return part
			end
		end
		return nil
	end
	for _, door in DOORS do
		local group = doorGroups[door.name]
		local mover: BasePart? = if group then moverOf(group) elseif door.joint then byJoint(door.joint, door.side) else nil
		local at, onto = ground, body
		if mover then
			local motor = drivers[mover]
			local p0 = if motor then motor.Part0 else nil
			local closed = if motor and p0 then p0.CFrame * motor.C0 * motor.C1:Inverse() else mover.CFrame
			at, onto = mover.CFrame * closed:Inverse() * ground, mover
		end
		for _, piece in art[door.name] do
			put(piece, at, onto)
		end
	end

	-- The wheel on every tyre: the model's front left wheel moved along the axle to the model's own track, turned round
	-- for the right side (its rim out), as big as the tyre.
	for _, tyre in tyres do
		local x = ground:PointToObjectSpace(tyre.Position).X
		local side = if x < 0 then -1 else 1
		local k = math.clamp(tyre.Size.Y / (2 * wheelRadius), 0.75, 1.4)
		local onto = tyre.CFrame * CFrame.new(side * math.abs(wheelAt.X) - x, 0, 0)
		if side > 0 then
			onto *= CFrame.Angles(0, math.pi, 0)
		end
		for _, piece in art.Wheel do
			local rel = CFrame.new(-wheelAt) * piece.cf
			local p = piece.part:Clone()
			p.Size = piece.size * k
			p.CFrame = onto * (rel - rel.Position + rel.Position * k)
			p.CastShadow = false
			p.Parent = folder
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = tyre
			weld.Part1 = p
			weld.Parent = p
		end
		hide(tyre)
	end
	for part, _ in onTyre do
		if not part.CanCollide then
			hide(part) -- (the parts look's hub and spoke on the tyre)
		end
	end

	-- The parts look goes: what it shows, hidden; what it does, kept.
	for _, part in looks do
		hide(part)
	end
	folder.Parent = model
	model:SetAttribute("SprinterMesh", true)
	return true
end

-- At the server's start: the import out of the world before anybody sees it, then every sprinter car dressed as it is
-- put into the world (Vehicles parents a car into workspace.Cars, else workspace, once it is built). No import: nothing.
function SprinterMesh.start()
	if started then
		return
	end
	started = true
	if not SprinterMesh.ready() then
		return
	end
	local function consider(child: Instance)
		if isSprinter(child) then
			task.defer(function()
				local ok, err = pcall(SprinterMesh.dress, child :: Model)
				if not ok then
					say(tostring(err))
				end
			end)
		end
	end
	-- A car in the Cars folder that is named after it is parented: its CarId once it comes.
	local function considerCar(child: Instance)
		if isSprinter(child) or not child:IsA("Model") or child:GetAttribute("CarId") ~= nil then
			consider(child)
			return
		end
		local named: RBXScriptConnection? = nil
		named = child:GetAttributeChangedSignal("CarId"):Connect(function()
			if named then
				named:Disconnect()
			end
			consider(child)
		end)
	end
	local watched: { [Instance]: boolean } = {}
	local function watch(folder: Instance)
		if watched[folder] then
			return
		end
		watched[folder] = true
		for _, child in folder:GetChildren() do
			considerCar(child)
		end
		folder.ChildAdded:Connect(considerCar)
	end
	local cars = workspace:FindFirstChild("Cars")
	if cars then
		watch(cars)
	end
	for _, child in workspace:GetChildren() do
		consider(child)
	end
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Cars" and child:IsA("Folder") then
			watch(child)
		else
			consider(child)
		end
	end)
end

return SprinterMesh
