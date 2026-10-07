-- Execute the real rig factory against the native-part recorder. BuildRigFromAttachments is recorded, not simulated.
local Mock = require("./mock")
local Geometry = require("./Geometry")
local Rig = require("./Rig")
local Config = require("./Config")
local function encode(v)
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
	if type(v) == "table" then
		local out = {}
		if #v > 0 then
			for _, x in v do table.insert(out, encode(x)) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		for k, x in v do table.insert(out, encode(k) .. ":" .. encode(x)) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	error("Unsupported art record")
end
local function v(a) return { a.X, a.Y, a.Z } end
for _, id in Geometry.ids do
	local def = Config.Zombies[id]
	local spec = if def then Geometry.spec(id, def.scale, def.skin, def.shirt, def.pants) else Geometry.spec(id)
	local model = Rig.build(spec)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid and humanoid.built == true and humanoid.RigType == "R15")
	assert(not humanoid.AutomaticScalingEnabled and humanoid.HipHeight == spec.hipHeight)
	assert(humanoid:FindFirstChildOfClass("Animator"))
	-- Factory coordinates are root-relative. Lift the display clone so its actual sole rests on the render floor.
	model:PivotTo(Mock.CFrame.new(0, spec.hipHeight + model.PrimaryPart.Size.Y / 2, 0))
	local named, parts = {}, {}
	for _, p in model:GetDescendants() do
		assert(p.ClassName ~= "MeshPart" and p.ClassName ~= "SpecialMesh")
		if not p:IsA("BasePart") then continue end
		assert(not p.Anchored)
		named[p.Name] = p
		if p:GetAttribute("CharacterDecoration") then
			assert(p.Massless and not p.CanCollide and not p.CanQuery and not p.CanTouch)
			local weld = p:FindFirstChild("CharacterWeld")
			assert(weld and weld.Part1 == p and weld.Part0.Parent == model)
		else
			assert(p.CanCollide == (p.Name == "UpperTorso" or p.Name == "LowerTorso"))
		end
		table.insert(parts, { id = p.uid, name = p.Name, class = p.ClassName,
			position = v(p.Position), rotation = p.CFrame.R, size = v(p.Size),
			color = { p.Color.R, p.Color.G, p.Color.B }, material = p.Material, shape = p.Shape or "Block", opacity = 1 - p.Transparency })
	end
	assert(#parts == #spec.bones + #spec.pieces and #parts <= spec.budget)
	for _, j in spec.joints do
		local parent, child = named[j.parent], named[j.child]
		local a, b = parent:FindFirstChild(j.name .. "RigAttachment"), child:FindFirstChild(j.name .. "RigAttachment")
		assert(a and b)
		assert(((parent.CFrame * a.CFrame).Position - (child.CFrame * b.CFrame).Position).Magnitude < 1e-6)
	end
	for _, piece in spec.pieces do
		local p = named[piece.name]
		local at = named[piece.attach].CFrame:ToObjectSpace(p.CFrame).Position
		assert((at - Mock.Vector3.new(piece.at[1], piece.at[2], piece.at[3])).Magnitude < 1e-6)
	end
	assert(named.HumanoidRootPart.Transparency == 1 and named.HumanoidRootPart.RootPriority == 127)
	assert(named.RightHand:FindFirstChild("RightGripAttachment"))
	-- Rojo/respawn clones must retain the art-to-bone references inside their own model, not the template.
	local clone = model:Clone()
	for _, p in clone:GetDescendants() do
		if p:GetAttribute("CharacterDecoration") then
			local weld = p:FindFirstChild("CharacterWeld")
			assert(weld.Part0.Parent == clone and weld.Part1 == p)
		end
	end
	clone:Destroy()
	model:Destroy()
	assert(model.Parent == nil and #model:GetChildren() == 0)
	print(encode({ id = id, parts = parts, spec = spec, camera = "front" }))
end
