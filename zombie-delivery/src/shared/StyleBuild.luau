--!strict
-- 6.12: puts the cosmetics (Config.Cosmetics, shared/StyleLooks.luau's geometry) on Roblox instances: on the server
-- for everybody (server/StyleWear.luau) and on the local copies of the phone's STYLE preview (client/StylePreview.luau,
-- `anchored`: no welds). Every part is decorative: massless, never colliding, touching, hit by rays or casting a
-- shadow; it is welded to the body part or the chassis it rides (never a joint of the rig: no C0 is written).
--
--   StyleBuild.courier(character, def, anchored?) -> Built?   a hat or a jacket fitted to the character's real parts
--       (StyleLooks.factors, shared/KitFit.luau's fit; the head by its visible size, StyleBuild.headSize), in a
--       Model "StyleHat" / "StyleJacket" in the character; nil when a body part it needs is missing
--   StyleBuild.fits(built) -> boolean   still on the same parts of the same sizes (the avatar replaced a part?)
--   StyleBuild.hideOwn(character, hide)   the player's own hat and hair accessories hidden under a STYLE hat (their
--       Handle's Transparency kept in the attribute StyleHid) or shown again
--   StyleBuild.tint(parts, shares, def?)   recolours the parts named in `shares` (name → the share of the colour) with
--       the item's colour, or back to their own (kept in the attributes StyleBase / StyleMaterial): the Courier Vest's
--       cloth (StyleLooks.Vest) and the bag's body (StyleLooks.Bags) through KitWear's tint hook
--   StyleBuild.wrap(parts, def)   a wrap's colour on a car's painted panels (each marked StylePaint for the preview)
--   StyleBuild.paintBike(model, def?)   a bike's or the E-Scooter's frame (StyleLooks.BikeFrame), or its own colours
--   StyleBuild.survey(model, chassis) -> (panels, blocks)   a car's painted panels and every other visible part as
--       boxes in the chassis' space (StyleLooks.decals' input)
--   StyleBuild.decals(model, chassis, def?, anchored?) -> Folder?   the decal in a Folder "StyleDecals" (an old one
--       goes first; nil def: none)
--   StyleBuild.color(def, paint) -> (Color3, Enum.Material, reflectance)   a piece's paint ("main", "trim" …)

local Config = require(script.Parent.Config)
local KitFit = require(script.Parent.KitFit)
local StyleLooks = require(script.Parent.StyleLooks)

local StyleBuild = {}

export type Built = { model: Model, parts: { BasePart }, bones: { [string]: BasePart }, sizes: { [string]: Vector3 } }

StyleBuild.Names = { hat = "StyleHat", jacket = "StyleJacket" } :: { [string]: string }
StyleBuild.Decals = "StyleDecals"

local DARK = { 32, 34, 38 }
local METAL = { 176, 180, 186 }
local WHITE = { 238, 238, 234 }
local CANVAS: { [string]: boolean } = { Hood = true, CabRoof = true, CargoRoof = true, RearDeck = true, CargoSide = true, FrontFender = true }
local MOVING: { [string]: boolean } = { CarDoor = true, BackDoor = true }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function material(name: string?, fallback: Enum.Material): Enum.Material
	if not name then
		return fallback
	end
	local ok, found = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and found ~= nil then found :: Enum.Material else fallback
end

local function shine(m: Enum.Material): number
	return if m == Enum.Material.Foil then 0.12 elseif m == Enum.Material.Metal then 0.05 else 0
end

-- A piece's colour, material and reflectance. A vehicle's main defaults to SmoothPlastic, the courier's cloth to Fabric.
function StyleBuild.color(def: Config.CosmeticDef, paint: string): (Color3, Enum.Material, number)
	local vehicle = def.slot == "wrap" or def.slot == "decal" or def.slot == "bikepaint"
	local cloth = if vehicle then Enum.Material.SmoothPlastic else Enum.Material.Fabric
	if paint == "main" then
		local m = material(def.material, cloth)
		return rgb(def.color), m, shine(m)
	elseif paint == "trim" then
		return rgb(def.trim or { def.color[1] * 0.7, def.color[2] * 0.7, def.color[3] * 0.7 }), if vehicle then Enum.Material.SmoothPlastic else cloth, 0
	elseif paint == "shade" then
		local m = material(def.material, cloth)
		return rgb({ math.floor(def.color[1] * 0.78), math.floor(def.color[2] * 0.78), math.floor(def.color[3] * 0.78) }), m, 0
	elseif paint == "metal" then
		return rgb(METAL), Enum.Material.Metal, 0.05
	elseif paint == "white" then
		return rgb(WHITE), cloth, 0
	end
	return rgb(DARK), cloth, 0
end

local function pose(at: { number }, turn: { number }?): CFrame
	local r = turn or { 0, 0, 0 }
	return CFrame.new(at[1], at[2], at[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
end

-- One decorative part (welded to `to` unless anchored).
local function part(parent: Instance, piece: StyleLooks.Piece, cframe: CFrame, def: Config.CosmeticDef, to: BasePart?, anchored: boolean): BasePart
	local p: BasePart = Instance.new(if piece.shape == "Wedge" then "WedgePart" else "Part") :: any
	p.Name = piece.name
	p.Size = Vector3.new(piece.size[1], piece.size[2], piece.size[3])
	p.CFrame = cframe
	local color, m, reflect = StyleBuild.color(def, piece.paint)
	p.Color, p.Material, p.Reflectance = color, m, reflect
	p.Anchored = anchored
	p.Massless, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if piece.shape == "Cylinder" then
		(p :: Part).Shape = Enum.PartType.Cylinder
	elseif piece.shape == "Ball" then
		(p :: Part).Shape = Enum.PartType.Ball
	end
	p:SetAttribute("StyleLook", def.id)
	p.Parent = parent
	if to and not anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Name = "StyleWeld"
		weld.Part0 = to
		weld.Part1 = p
		weld.Parent = p
	end
	return p
end

-- ── The courier ───────────────────────────────────────────────────────────

-- The head's visible size: a classic head mesh (a SpecialMesh of the Head type) by its scale, else the part's size.
function StyleBuild.headSize(head: BasePart): Vector3
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.Head then
		return mesh.Scale
	end
	return head.Size
end

function StyleBuild.courier(character: Model, def: Config.CosmeticDef, anchored: boolean?): Built?
	local pieces = StyleLooks.courier(def)
	if not pieces then
		return nil
	end
	local bones: { [string]: BasePart } = {}
	local sizes: { [string]: Vector3 } = {}
	local scales: { [string]: { number } } = {}
	for _, piece in pieces do
		local name = piece.attach
		if not bones[name] then
			local found = character:FindFirstChild(name)
			if not found or not found:IsA("BasePart") then
				return nil
			end
			local bone = found :: BasePart
			local size = if name == "Head" then StyleBuild.headSize(bone) else bone.Size
			bones[name], sizes[name] = bone, bone.Size
			scales[name] = StyleLooks.factors(name, { size.X, size.Y, size.Z })
		end
	end
	local model = Instance.new("Model")
	model.Name = StyleBuild.Names[def.slot] or "StyleLook"
	model:SetAttribute("StyleLook", def.id)
	local built: Built = { model = model, parts = {}, bones = bones, sizes = sizes }
	for _, piece in KitFit.fit(pieces, scales) do
		local bone = bones[piece.attach]
		table.insert(built.parts, part(model, piece, bone.CFrame * pose(piece.at, piece.turn), def, bone, anchored == true))
	end
	model.Parent = character
	return built
end

function StyleBuild.fits(built: Built): boolean
	local character = built.model.Parent
	if not character then
		return false
	end
	for name, bone in built.bones do
		if bone.Parent ~= character or bone.Size ~= built.sizes[name] or character:FindFirstChild(name) ~= bone then
			return false
		end
	end
	return true
end

-- The accessories a STYLE hat covers: hats and hair (their type, or the attachment they hang from).
local function onHead(accessory: Instance, handle: Instance): boolean
	local kind = (accessory :: any).AccessoryType
	if kind == Enum.AccessoryType.Hat or kind == Enum.AccessoryType.Hair then
		return true
	end
	return handle:FindFirstChild("HatAttachment") ~= nil or handle:FindFirstChild("HairAttachment") ~= nil
end

function StyleBuild.hideOwn(character: Instance, hide: boolean)
	for _, child in character:GetChildren() do
		if not child:IsA("Accessory") then
			continue
		end
		local handle = child:FindFirstChild("Handle")
		if not handle or not handle:IsA("BasePart") or not onHead(child, handle) then
			continue
		end
		local was = handle:GetAttribute("StyleHid")
		if hide then
			if type(was) ~= "number" then
				handle:SetAttribute("StyleHid", handle.Transparency)
			end
			handle.Transparency = 1
		elseif type(was) == "number" then
			handle.Transparency = was
			handle:SetAttribute("StyleHid", nil)
		end
	end
end

-- ── Colours on parts that are not ours ───────────────────────────────────

function StyleBuild.tint(parts: { Instance }, shares: { [string]: number }, def: Config.CosmeticDef?)
	for _, p in parts do
		local share = shares[p.Name]
		if not share or not p:IsA("BasePart") then
			continue
		end
		local base = p:GetAttribute("StyleBase")
		if def then
			if base == nil then
				p:SetAttribute("StyleBase", p.Color)
				p:SetAttribute("StyleMaterial", (p.Material :: any).Name or tostring(p.Material))
			end
			local c = def.color
			p.Color = rgb({ math.floor(c[1] * share), math.floor(c[2] * share), math.floor(c[3] * share) })
			-- a dye without a material of its own: the part's own one (stored), not the last dye's
			local own = p:GetAttribute("StyleMaterial")
			p.Material = material(def.material, material(if type(own) == "string" then own else nil, p.Material))
		elseif typeof(base) == "Color3" then
			p.Color = base
			local m = p:GetAttribute("StyleMaterial")
			p.Material = material(if type(m) == "string" then m else nil, p.Material)
			p:SetAttribute("StyleBase", nil)
			p:SetAttribute("StyleMaterial", nil)
		end
	end
end

function StyleBuild.wrap(parts: { BasePart }, def: Config.CosmeticDef)
	local color, m, reflect = StyleBuild.color(def, "main")
	for _, p in parts do
		p.Color, p.Material, p.Reflectance = color, m, reflect
		p:SetAttribute("StylePaint", true)
	end
end

local FRAME: { [string]: number } = {}
for _, name in StyleLooks.BikeFrame do
	FRAME[name] = 1
end

function StyleBuild.paintBike(model: Instance, def: Config.CosmeticDef?)
	local parts: { Instance } = {}
	for _, d in model:GetDescendants() do
		if FRAME[d.Name] and d:IsA("BasePart") and d.Parent and string.sub(d.Parent.Name, -3) == "Art" then
			table.insert(parts, d)
		end
	end
	StyleBuild.tint(parts, FRAME, def)
end

-- ── Decals ────────────────────────────────────────────────────────────────

-- A part's box in `frame`'s space.
local function box(frame: CFrame, p: BasePart): StyleLooks.Box
	local rel = frame:ToObjectSpace(p.CFrame)
	local o = rel.Position
	local x = rel * Vector3.new(1, 0, 0) - o
	local y = rel * Vector3.new(0, 1, 0) - o
	local z = rel * Vector3.new(0, 0, 1) - o
	local h = p.Size / 2
	local e = {
		math.abs(x.X) * h.X + math.abs(y.X) * h.Y + math.abs(z.X) * h.Z,
		math.abs(x.Y) * h.X + math.abs(y.Y) * h.Y + math.abs(z.Y) * h.Z,
		math.abs(x.Z) * h.X + math.abs(y.Z) * h.Y + math.abs(z.Z) * h.Z,
	}
	return { min = { o.X - e[1], o.Y - e[2], o.Z - e[3] }, max = { o.X + e[1], o.Y + e[2], o.Z + e[3] } }
end
StyleBuild.box = box

local function moving(p: Instance, model: Instance): boolean
	local at: Instance? = p
	while at and at ~= model do
		if MOVING[at.Name] then
			return true
		end
		at = at.Parent
	end
	return false
end

function StyleBuild.survey(model: Instance, chassis: BasePart): ({ StyleLooks.Panel }, { StyleLooks.Box })
	local frame = chassis.CFrame
	local panels: { StyleLooks.Panel } = {}
	local blocks: { StyleLooks.Box } = {}
	local skip = model:FindFirstChild(StyleBuild.Decals)
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") or d.Transparency >= 0.95 or (skip and d:IsDescendantOf(skip)) then
			continue
		end
		local b = box(frame, d)
		if CANVAS[d.Name] and d:GetAttribute("FleetFinish") == "paint" and not moving(d, model) then
			table.insert(panels, { name = d.Name, min = b.min, max = b.max })
		else
			table.insert(blocks, b)
		end
	end
	return panels, blocks
end

-- The checker's squares on the strip's outer face (a SurfaceGui of Frames: no uploaded image).
local function checker(p: BasePart, piece: StyleLooks.Piece, def: Config.CosmeticDef)
	local spec = piece.checker :: { rows: number, size: number }
	local gui = Instance.new("SurfaceGui")
	gui.Name = "StyleChecker"
	gui.Face = (Enum.NormalId :: any)[piece.face or "Right"]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	local columns = math.max(1, math.floor(piece.size[3] / spec.size + 0.5))
	local dark = rgb(def.trim or DARK)
	for row = 0, spec.rows - 1 do
		for column = 0, columns - 1 do
			if (row + column) % 2 == 0 then
				local square = Instance.new("Frame")
				square.BorderSizePixel = 0
				square.BackgroundColor3 = dark
				square.Size = UDim2.fromScale(1 / columns, 1 / spec.rows)
				square.Position = UDim2.fromScale(column / columns, row / spec.rows)
				square.Parent = gui
			end
		end
	end
	gui.Parent = p
end

local function label(p: BasePart, piece: StyleLooks.Piece, def: Config.CosmeticDef)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "StyleLabel"
	gui.Face = (Enum.NormalId :: any)[piece.face or "Right"]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(0.62, 0.42)
	text.Position = UDim2.fromScale(0.19, 0.29)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.Text = piece.text or ""
	text.TextColor3 = rgb(def.trim or DARK)
	text.Parent = gui
	gui.Parent = p
end

function StyleBuild.decals(model: Instance, chassis: BasePart, def: Config.CosmeticDef?, anchored: boolean?): Folder?
	local old = model:FindFirstChild(StyleBuild.Decals)
	if old then
		old:Destroy()
	end
	if not def then
		return nil
	end
	local panels, blocks = StyleBuild.survey(model, chassis)
	local pieces = StyleLooks.decals(def.look, panels, blocks)
	local folder = Instance.new("Folder")
	folder.Name = StyleBuild.Decals
	folder:SetAttribute("StyleLook", def.id)
	local frame = chassis.CFrame
	for n, piece in pieces do
		if n > Config.Cosmetics.Fit.Budget then
			break
		end
		local p = part(folder, piece, frame * pose(piece.at, piece.turn), def, chassis, anchored == true)
		if piece.checker then
			checker(p, piece, def)
		elseif piece.text then
			label(p, piece, def)
		end
	end
	folder.Parent = model
	return folder
end

return StyleBuild
