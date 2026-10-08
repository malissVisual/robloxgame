--!strict
-- Builds the pure CharacterArt spec as a native R15 humanoid. Roblox builds the joints from paired attachments;
-- no C0/C1 writes. Clothing and printed-face pieces are massless, non-colliding/non-queryable decoration.
-- 6.7: the shapes of the realistic body: "Ball" and "Cylinder" parts, "Wedge" parts and "Ellipsoid" (a block part with
-- a SpecialMesh sphere: Roblox's own shape, stretched to the part's size; on a bone too: the head). A grip attachment
-- in each hand where the spec says (spec.grips: LeftGripAttachment / RightGripAttachment), and the colour group of
-- every part (`paint`) as its BodyPaint attribute (server/Npcs.luau dresses a person by it).
local Geometry = require(script.Parent.Geometry)
local Rig = {}

local function vector(a: Geometry.Triple): Vector3
	return Vector3.new(a[1], a[2], a[3])
end
local function paint(p: BasePart, rgb: Geometry.Triple)
	p.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- 6.7: a part's shape (an ellipsoid: the part stays a block, a sphere mesh stretched over it).
local function shape(p: BasePart, kind: string?)
	if kind == "Ball" and p:IsA("Part") then
		p.Shape = Enum.PartType.Ball
	elseif kind == "Cylinder" and p:IsA("Part") then
		p.Shape = Enum.PartType.Cylinder
	elseif kind == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
end

function Rig.build(spec: Geometry.Spec): Model
	local model = Instance.new("Model")
	model.Name = spec.id
	model:SetAttribute("CharacterArt", spec.id)
	local bones: { [string]: Part } = {}
	for _, b in spec.bones do
		local p = Instance.new("Part")
		p.Name = b.name
		p.Size = vector(b.size)
		p.CFrame = CFrame.new(vector(b.at))
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.SmoothPlastic
		paint(p, b.color)
		shape(p, b.shape)
		if b.paint then
			p:SetAttribute("BodyPaint", b.paint)
		end
		p.CanCollide = b.name == "UpperTorso" or b.name == "LowerTorso"
		p.CanTouch = false
		p.Massless = b.name ~= "HumanoidRootPart"
		if b.name == "HumanoidRootPart" then
			p.Transparency = 1
			p.CanQuery = false
			p.RootPriority = 127
		end
		p.Parent = model
		bones[b.name] = p
	end
	model.PrimaryPart = bones.HumanoidRootPart
	for _, j in spec.joints do
		for _, name in { j.parent, j.child } do
			local a = Instance.new("Attachment")
			a.Name = j.name .. "RigAttachment"
			a.CFrame = bones[name].CFrame:ToObjectSpace(CFrame.new(vector(j.at)))
			a.Parent = bones[name]
		end
	end
	-- The familiar R15 grip mounts (6.7: in both fists, where a handle sits; the 6.0 block body's right hand: its
	-- bottom). The guns weld below the hand (shared/GunModels.luau gripOn); the phone/kit attach to the named bones.
	for hand, at in spec.grips do
		local grip = Instance.new("Attachment")
		grip.Name = (if hand == "LeftHand" then "Left" else "Right") .. "GripAttachment"
		grip.CFrame = CFrame.new(vector(at))
		grip.Parent = bones[hand]
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	humanoid.RequiresNeck = true
	humanoid.HipHeight = spec.hipHeight
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	humanoid:BuildRigFromAttachments()
	for _, piece in spec.pieces do
		local p: BasePart = if piece.shape == "Wedge" then Instance.new("WedgePart") else Instance.new("Part")
		p.Name = piece.name
		p.Size = vector(piece.size)
		shape(p, piece.shape)
		if piece.paint then
			p:SetAttribute("BodyPaint", piece.paint)
		end
		local turn = piece.turn or { 0, 0, 0 }
		p.CFrame = bones[piece.attach].CFrame * CFrame.new(vector(piece.at)) * CFrame.Angles(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
		paint(p, piece.color)
		p.Material = if piece.material == "Fabric" then Enum.Material.Fabric elseif piece.material == "Neon" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Massless = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.CastShadow = false
		p:SetAttribute("CharacterDecoration", true)
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Name = "CharacterWeld"
		weld.Part0, weld.Part1 = bones[piece.attach], p
		weld.Parent = p
	end
	return model
end

return Rig
