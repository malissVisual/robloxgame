--!strict
-- 8.3 SANDBOX, the PAINT shop: a Sprinter van model put in a look (shared/VanPaintRules.luau's Look). The server paints
-- every player's van with it (server/VanPaint.luau: as it is built, and when its owner wears something else), the
-- window paints its 3D picture's copy of your van with it (client/VanPaintPreview.luau). Only colours, materials and a
-- few thin parts that are only looks: nothing that collides, no seat, door, prompt or the cargo bay changes.
--
--   VanLook.apply(model, look, options?)   the model in the look:
--     * the body panels (the parts look's "paint" pieces: server/Vehicles.luau's car.paintParts, given the first time
--       as options.paintParts and tagged with the attribute VanPaintRole = "body", so a copy of the model knows them)
--       take the body's colour, material and reflectance;
--     * the stripes (FleetFinish "stripe": the ZDC band all round, the doors' bands, the nose badge) take the stripe's,
--       and the ZDC logos' letters (VanPaintRules.inked) its colour;
--     * the owner's Blender look (server/SprinterMesh.luau's pieces "<group>_<finish>" in the folder "SprinterMesh"):
--       the paint and stripe finishes (Config.VanPaint.Finishes) take the body's and the stripe's, or their factory
--       look again (the pieces' attributes FactoryColor / FactoryMaterial) for the factory's paint or livery; the
--       model's attributes <prefix>Color / <prefix>Material / <prefix>Reflectance (nil: the factory's) tell a van
--       SprinterMesh dresses later;
--     * the livery's roof stripes: the folder "VanLivery" (made anew), thin parts in the van's frame (the ground under
--       its middle: the chassis' top is Config.Sprinter.Bay.Floor over it), welded to the body that sways ("BodyRoot",
--       else the chassis), or anchored (options.anchored: a ViewportFrame's copy);
--     * the model's attributes VanPaint and VanLivery: the ids it wears.
--   VanLook.Folder                         "VanLivery"
--   VanLook.ground(model)                  the van's frame (the ground under its middle), nil without a chassis

local Config = require(script.Parent.Config)
local Rules = require(script.Parent.VanPaintRules)

local VanLook = {}

VanLook.Folder = "VanLivery"

export type Options = { paintParts: { BasePart }?, anchored: boolean? }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- A Roblox material by its name (nil: none of that name).
local function material(name: any): Enum.Material?
	if type(name) ~= "string" then
		return nil
	end
	local ok, found = pcall(function(): any
		return (Enum.Material :: any)[name]
	end)
	return if ok and found ~= nil then found :: Enum.Material else nil
end

local function finishPart(part: BasePart, color: Color3, mat: Enum.Material?, reflectance: number)
	part.Color = color
	if mat then
		part.Material = mat
	end
	part.Reflectance = reflectance
end

function VanLook.ground(model: Model): CFrame?
	local primary = model.PrimaryPart
	local chassis: Instance? = if primary then primary else model:FindFirstChild("Chassis")
	if not chassis or not chassis:IsA("BasePart") then
		return nil
	end
	return chassis.CFrame * CFrame.new(0, chassis.Size.Y / 2 - Config.Sprinter.Bay.Floor, 0)
end

-- The livery's roof stripes, made anew.
local function roof(model: Model, look: Rules.Look, anchored: boolean)
	local old = model:FindFirstChild(VanLook.Folder)
	if old then
		old:Destroy()
	end
	local ground = VanLook.ground(model)
	if #look.roof == 0 or not ground then
		return
	end
	local root = model:FindFirstChild("BodyRoot")
	local body: Instance? = if root and root:IsA("BasePart") then root else model.PrimaryPart
	local folder = Instance.new("Folder")
	folder.Name = VanLook.Folder
	for _, piece in look.roof do
		local p = Instance.new("Part")
		p.Name = piece.name
		p.Size = Vector3.new(piece.size[1], piece.size[2], piece.size[3])
		p.CFrame = ground * CFrame.new(piece.at[1], piece.at[2], piece.at[3])
		p.Color = rgb(piece.color)
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.CastShadow = false
		p.Anchored = anchored
		p.Parent = folder
		if not anchored and body and body:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = p
			weld.Parent = p
		end
	end
	folder.Parent = model
end

function VanLook.apply(model: Model, look: Rules.Look, options: Options?)
	local opts: Options = options or {}
	local bodyColor, stripeColor = rgb(look.body), rgb(look.stripe)
	local bodyMaterial, stripeMaterial = material(look.bodyMaterial), material(look.stripeMaterial)
	local panels: { BasePart } = opts.paintParts or {}
	for _, part in panels do
		part:SetAttribute("VanPaintRole", "body")
	end
	local finishes = Config.VanPaint.Finishes
	model:SetAttribute("VanPaint", look.paint)
	model:SetAttribute("VanLivery", look.livery)
	model:SetAttribute(`{finishes.paint}Color`, if look.factoryPaint then nil else bodyColor)
	model:SetAttribute(`{finishes.paint}Material`, if look.factoryPaint then nil else look.bodyMaterial)
	model:SetAttribute(`{finishes.paint}Reflectance`, if look.factoryPaint then nil else look.bodyReflectance)
	model:SetAttribute(`{finishes.stripe}Color`, if look.factoryLivery then nil else stripeColor)
	model:SetAttribute(`{finishes.stripe}Material`, if look.factoryLivery then nil else look.stripeMaterial)
	model:SetAttribute(`{finishes.stripe}Reflectance`, if look.factoryLivery then nil else look.stripeReflectance)
	local inked = Rules.inked()
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local parent = d.Parent
		if parent and parent.Name == "SprinterMesh" then
			-- the owner's Blender look: its painted finishes, or their factory look again
			local finish = string.match(d.Name, "^%a+_(%a+)$")
			local factory = if finish == "paint" then look.factoryPaint elseif finish == "stripe" then look.factoryLivery else nil
			if factory == true then
				local own = d:GetAttribute("FactoryColor")
				if typeof(own) == "Color3" then
					finishPart(d, own, material(d:GetAttribute("FactoryMaterial")), 0)
				end
			elseif factory == false then
				if finish == "paint" then
					finishPart(d, bodyColor, bodyMaterial, look.bodyReflectance)
				else
					finishPart(d, stripeColor, stripeMaterial, look.stripeReflectance)
				end
			end
		elseif d:GetAttribute("VanPaintRole") == "body" then
			finishPart(d, bodyColor, bodyMaterial, look.bodyReflectance)
		elseif d:GetAttribute("FleetFinish") == "stripe" then
			finishPart(d, stripeColor, stripeMaterial, look.stripeReflectance)
		elseif inked[d.Name] then
			local gui = d:FindFirstChild("FleetLabel")
			local label = gui and gui:FindFirstChildOfClass("TextLabel")
			if label then
				label.TextColor3 = stripeColor
			end
		end
	end
	roof(model, look, opts.anchored == true)
end

return VanLook
