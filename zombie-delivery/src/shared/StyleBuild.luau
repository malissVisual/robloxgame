--!strict
-- Puts the courier you make on Roblox instances (10.1, the character creator: shared/CharacterLooks.luau's pieces,
-- shared/StyleLooks.luau's hats and jackets): on the server for everybody (server/CourierAvatar.luau) and on the
-- creator's mannequin (client/CharacterCreator.luau, `anchored`: no welds). Every part is decorative: massless, never
-- colliding, touching, hit by rays or casting a shadow; it is welded to the body part it rides (never a joint of the
-- rig: no C0 is written).
--
--   StyleBuild.character(character, look, anchored?) -> Model?   a made courier's pieces (the hair, a hat, the top's
--       sleeves or a jacket, the belt, the face's extra) fitted to the character's real parts (StyleLooks.factors,
--       shared/KitFit.luau's fit; the head by its visible size, StyleBuild.headSize) in a Model "CourierLook" in the
--       character (an old one goes first; a piece whose body part is missing is left out); nil for the player's own
--       avatar (nothing to weld on)
--   StyleBuild.color(def, paint) -> (Color3, Enum.Material, reflectance)   a piece's paint ("main", "trim" …)
-- 10.6: the city's STYLE shop is gone: its worn hats and jackets, the vest's and the bags' dyes, the car wraps, the
-- bikes' paint and the decals.

local Config = require(script.Parent.Config)
local KitFit = require(script.Parent.KitFit)
local CharacterLooks = require(script.Parent.CharacterLooks) -- 10.1: the courier you make
local StyleLooks = require(script.Parent.StyleLooks)

local StyleBuild = {}

local DARK = { 32, 34, 38 }
local METAL = { 176, 180, 186 }
local WHITE = { 238, 238, 234 }

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

-- A piece's colour, material and reflectance: cloth (Fabric) unless its def names a material.
function StyleBuild.color(def: Config.CosmeticDef, paint: string): (Color3, Enum.Material, number)
	local cloth = Enum.Material.Fabric
	if paint == "main" then
		local m = material(def.material, cloth)
		return rgb(def.color), m, shine(m)
	elseif paint == "trim" then
		return rgb(def.trim or { def.color[1] * 0.7, def.color[2] * 0.7, def.color[3] * 0.7 }), cloth, 0
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

StyleBuild.Look = "CourierLook"

-- 10.1: the made courier's pieces (see the header), each group in its own colours (its def), fitted to the real parts.
function StyleBuild.character(character: Model, look: CharacterLooks.Look, anchored: boolean?): Model?
	local old = character:FindFirstChild(StyleBuild.Look)
	if old then
		old:Destroy()
	end
	local groups = CharacterLooks.parts(look)
	if #groups == 0 then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = StyleBuild.Look
	local bones: { [string]: BasePart } = {}
	local scales: { [string]: { number } } = {}
	for _, group in groups do
		local kept: { StyleLooks.Piece } = {}
		for _, piece in group.pieces do
			local name = piece.attach
			if not bones[name] then
				local found = character:FindFirstChild(name)
				if not found or not found:IsA("BasePart") then
					continue
				end
				local bone = found :: BasePart
				local size = if name == "Head" then StyleBuild.headSize(bone) else bone.Size
				bones[name] = bone
				scales[name] = StyleLooks.factors(name, { size.X, size.Y, size.Z })
			end
			table.insert(kept, piece)
		end
		for _, piece in KitFit.fit(kept, scales) do
			local bone = bones[piece.attach]
			part(model, piece, bone.CFrame * pose(piece.at, piece.turn), group.def, bone, anchored == true)
		end
	end
	model.Parent = character
	return model
end

return StyleBuild
