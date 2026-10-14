--!strict
-- 7.1, the moves' furniture in the owner's own Blender models (the owner: "nicer things, the models you carry out";
-- design/blender-furniture/furniture.py → roblox/ZDCFurnitureArt.fbx). The owner imports ZDCFurnitureArt.fbx once in
-- Roblox Studio (File → Import 3D, the defaults) and publishes; this finds the imported model (a top-level child of
-- ServerStorage or Workspace named ZDCFurnitureArt, or one holding its markers), learns from the markers how the
-- importer turned and scaled it, keeps its MeshParts in ServerStorage and dresses every piece server/HouseInterior.luau
-- builds (FurnitureLooks.build) with clones on its Root: the Root (the box that collides, is carried and is packed) and
-- the labels stay, FurnitureLooks' parts go. No imported model, or an item it lacks: FurnitureLooks' look.
--
--   FurnitureMesh.start()                    at the server's start: finds the import and takes it out of the world
--   FurnitureMesh.has(id)                    has the import this item (a FurnitureLooks id)?
--   FurnitureMesh.dress(piece, id, variant)  dresses FurnitureLooks.build(id, variant)'s model; false: left as it was
--   FurnitureMesh.Looks                      each finish's colour and material
--
-- The pieces are named "<item id>_<finish>" (furniture.py export_game); "mark_<item id>" is the bottom middle of that
-- item's box, mark_o / mark_x / mark_y / mark_z the origin and 10 studs to the right, up and back (the game's axes: the
-- front of a piece is -Z). The finish is the look below; fabric, fabric2, wood, wood2, paint, accent and appliance take
-- the piece's variant colour (FurnitureLooks.Palettes, the builders' own lists), and so do 8.1's gilt, velvet, lacquer,
-- neon and fur (the 12 collectibles, FurnitureLooks.Collectibles, are in the import since 8.1).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FurnitureLooks = require(ReplicatedStorage:WaitForChild("Shared").FurnitureLooks)

local FurnitureMesh = {}

local NAME = "ZDCFurnitureArt"

type Look = { color: Color3?, material: Enum.Material, palette: string?, salt: number?, transparency: number?, reflectance: number? }
local function hex(code: string): Color3
	return Color3.fromRGB(tonumber(code:sub(1, 2), 16) :: number, tonumber(code:sub(3, 4), 16) :: number, tonumber(code:sub(5, 6), 16) :: number)
end
local M = Enum.Material
-- furniture.py's FINISHES (the colours of variant 1 there; a palette finish takes the variant's).
local LOOKS: { [string]: Look } = {
	fabric = { material = M.Fabric, palette = "fabric" },
	fabric2 = { material = M.Fabric, palette = "fabric", salt = 3 },
	wood = { material = M.Wood, palette = "wood" },
	wood2 = { material = M.Wood, palette = "wood", salt = 1 },
	paint = { material = M.SmoothPlastic, palette = "paint" },
	accent = { material = M.SmoothPlastic, palette = "accent" },
	appliance = { material = M.SmoothPlastic, palette = "appliance" },
	cream = { color = hex("F4EEDE"), material = M.SmoothPlastic },
	brass = { color = hex("CCA448"), material = M.Metal, reflectance = 0.15 },
	steel = { color = hex("AAB0B4"), material = M.Metal },
	chrome = { color = hex("D7DBDF"), material = M.Metal, reflectance = 0.3 },
	dark = { color = hex("242428"), material = M.SmoothPlastic },
	white = { color = hex("F6F4EE"), material = M.SmoothPlastic },
	glass = { color = hex("28343E"), material = M.Glass, transparency = 0.25 },
	mirror = { color = hex("C4D6E0"), material = M.Glass, reflectance = 0.5 },
	leather = { color = hex("6E3C28"), material = M.Leather },
	card = { color = hex("C49E6C"), material = M.Cardboard },
	tape = { color = hex("DEC8A0"), material = M.SmoothPlastic },
	rubber = { color = hex("18181A"), material = M.Rubber },
	ceramic = { color = hex("F6F4EE"), material = M.SmoothPlastic, reflectance = 0.1 },
	terracotta = { color = hex("B8603E"), material = M.SmoothPlastic },
	soil = { color = hex("463224"), material = M.Ground },
	leaf = { color = hex("40824A"), material = M.SmoothPlastic },
	leaf2 = { color = hex("62A452"), material = M.SmoothPlastic },
	gold = { color = hex("C8A046"), material = M.Metal, reflectance = 0.15 },
	sky = { color = hex("8CBEE6"), material = M.SmoothPlastic },
	grass = { color = hex("6EA05A"), material = M.SmoothPlastic },
	sun = { color = hex("FAD26E"), material = M.SmoothPlastic },
	book1 = { color = hex("AA3430"), material = M.SmoothPlastic },
	book2 = { color = hex("34568C"), material = M.SmoothPlastic },
	book3 = { color = hex("3C784C"), material = M.SmoothPlastic },
	book4 = { color = hex("D6AA3C"), material = M.SmoothPlastic },
	glow = { color = hex("FFECC8"), material = M.Neon },
	red = { color = hex("C8322E"), material = M.SmoothPlastic },
	wicker = { color = hex("BE9664"), material = M.Fabric },
	black = { color = hex("141416"), material = M.SmoothPlastic },
	-- 8.1, the collectibles: polished gold, velvet, lacquer, the arcade's neon and a stag's coat in the variant's colours;
	-- antlers, marble, porcelain and its cobalt, the jukebox's glowing tubes, clear glass, the old globe's sea and
	-- parchment, the oil painting's peach, rock and slate.
	gilt = { material = M.Metal, palette = "gilt", reflectance = 0.25 },
	velvet = { material = M.Fabric, palette = "velvet" },
	lacquer = { material = M.SmoothPlastic, palette = "lacquer", reflectance = 0.1 },
	neon = { material = M.Neon, palette = "neon" },
	fur = { material = M.Fabric, palette = "fur" },
	bone = { color = hex("DCCDA8"), material = M.SmoothPlastic },
	marble = { color = hex("E8E4DC"), material = M.Marble },
	porcelain = { color = hex("F4F2EA"), material = M.SmoothPlastic, reflectance = 0.12 },
	cobalt = { color = hex("27448F"), material = M.SmoothPlastic, reflectance = 0.08 },
	amber = { color = hex("FF9A3C"), material = M.Neon },
	ember = { color = hex("FF4A32"), material = M.Neon },
	crystal = { color = hex("EEF6F4"), material = M.Glass, transparency = 0.6, reflectance = 0.1 },
	ocean = { color = hex("5E8FA8"), material = M.SmoothPlastic, reflectance = 0.05 },
	parchment = { color = hex("E6D3A3"), material = M.SmoothPlastic },
	peach = { color = hex("F2B48C"), material = M.SmoothPlastic },
	rock = { color = hex("8A8DAE"), material = M.SmoothPlastic },
	slate = { color = hex("5E6682"), material = M.SmoothPlastic },
}
-- The finishes light passes through: they cast no shadow.
local CLEAR: { [string]: boolean } = { glass = true, glow = true, crystal = true }
FurnitureMesh.Looks = LOOKS

type Piece = { finish: string, part: BasePart, cf: CFrame, size: Vector3 }

local items: { [string]: { Piece } }? = nil
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
			if child:IsA("Model") and child:FindFirstChild("mark_o", true) and child:FindFirstChild("mark_sofa", true) then
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
	art.Parent = ServerStorage -- out of the world: only the clones in the houses are seen
	local marks: { [string]: Vector3 } = {}
	for _, d in art:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(1, 5) == "mark_" then
			marks[d.Name:sub(6)] = d.Position
		end
	end
	local o, x, y, z = marks.o, marks.x, marks.y, marks.z
	if not (o and x and y and z) then
		say("the markers mark_o, mark_x, mark_y and mark_z are missing; the furniture keeps its own look")
		return
	end
	local scale = (x - o).Magnitude / 10
	local ux = (x - o).Unit
	local uz = ux:Cross((y - o).Unit).Unit
	local uy = uz:Cross(ux).Unit
	if scale < 0.01 or uz:Dot((z - o).Unit) < 0.9 then
		say("the import came out mirrored or flat; the furniture keeps its own look")
		return
	end
	local axes = CFrame.fromMatrix(Vector3.zero, ux, uy, uz) -- the game's axes as the importer turned them
	local found: { [string]: { Piece } } = {}
	local count = 0
	for _, d in art:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local id, finish = string.match(d.Name, "^(.+)_(%w+)$")
		local look = if finish then LOOKS[finish] else nil
		local origin = if id then marks[id] else nil
		if not id or not finish or not look or not origin or id == "mark" then
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
		if look.color then
			d.Color = look.color
		end
		d.Transparency = look.transparency or 0
		d.Reflectance = look.reflectance or 0
		d.CastShadow = not CLEAR[finish]
		local frame = CFrame.new(origin) * axes -- the item's bottom middle, the game's axes
		local rel = frame:ToObjectSpace(d.CFrame)
		local list = found[id] or {}
		found[id] = list
		table.insert(list, { finish = finish, part = d, cf = rel - rel.Position + rel.Position / scale, size = d.Size / scale })
		count += 1
	end
	if count == 0 then
		say("no pieces named <item>_<finish>; the furniture keeps its own look")
		return
	end
	items = found
end

-- Has the imported model this item (FurnitureLooks id)?
function FurnitureMesh.has(id: string): boolean
	if not tried then
		local ok, err = pcall(function(): any
			loadArt()
			return nil
		end)
		if not ok then
			say(tostring(err))
		end
	end
	return items ~= nil and (items :: { [string]: { Piece } })[id] ~= nil
end

-- The colour of a finish on a piece of this variant (a palette finish: the variant's, turned by the item's id so the
-- pieces of one house differ like FurnitureLooks' own).
local function colourOf(look: Look, id: string, variant: number): Color3?
	local palettes = (FurnitureLooks :: any).Palettes
	local list = if look.palette and palettes then palettes[look.palette] else nil
	if list and #list > 0 then
		return list[(variant + (look.salt or 0) + #id - 1) % #list + 1]
	end
	return look.color
end

-- At the server's start (server/Main.server.luau): the imported model out of the world before anybody sees it (the
-- houses are built only when a move starts).
function FurnitureMesh.start()
	FurnitureMesh.has("sofa")
end

-- Dresses a piece FurnitureLooks.build(id, variant) made (at the origin, unanchored): the model's pieces welded to its
-- Root, its own parts gone but the ones with a label (their text stays on the model's faces). False: left as it was.
function FurnitureMesh.dress(piece: Model, id: string, variant: number?): boolean
	if not FurnitureMesh.has(id) then
		return false
	end
	local root = piece.PrimaryPart
	if not root then
		return false
	end
	local v = math.max(1, math.floor(variant or 1))
	for _, d in piece:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			if d:FindFirstChildWhichIsA("SurfaceGui") then
				d.Transparency = 1
			else
				d:Destroy()
			end
		end
	end
	local base = root.CFrame * CFrame.new(0, -root.Size.Y / 2, 0)
	for _, item in (items :: { [string]: { Piece } })[id] do
		local p = item.part:Clone()
		p.Size = item.size
		p.CFrame = base * item.cf
		local colour = colourOf(LOOKS[item.finish], id, v)
		if colour then
			p.Color = colour
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = piece
	end
	piece:SetAttribute("MeshArt", true)
	return true
end

return FurnitureMesh
