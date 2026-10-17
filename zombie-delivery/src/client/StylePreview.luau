--!strict
-- The character creator's stand-in body (client/CharacterCreator.luau): StylePreview.mannequin(), the classic R15 block
-- body in the courier's workwear (shared/AvatarLook.luau), standing, facing -Z, anchored and inert. (The name is the
-- old STYLE app's live preview's, of which this is what is left.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarLook = require(Shared.AvatarLook)

local StylePreview = {}

-- The classic R15 block body (server/CharacterArt "walker"'s parts with the 1.2 head), standing, for the mannequin.
local BODY: { { any } } = {
	{ "LowerTorso", { 2, 0.4, 1 }, { 0, -0.75, 0 }, "TorsoColor" },
	{ "UpperTorso", { 2, 1.6, 1 }, { 0, 0.25, 0 }, "TorsoColor" },
	{ "Head", { 1.2, 1.2, 1.2 }, { 0, 1.65, 0 }, "HeadColor" },
	{ "LeftUpperArm", { 1, 1.17, 1 }, { -1.5, 0.465, 0 }, "TorsoColor" },
	{ "RightUpperArm", { 1, 1.17, 1 }, { 1.5, 0.465, 0 }, "TorsoColor" },
	{ "LeftLowerArm", { 1, 0.53, 1 }, { -1.5, -0.385, 0 }, "LeftArmColor" },
	{ "RightLowerArm", { 1, 0.53, 1 }, { 1.5, -0.385, 0 }, "RightArmColor" },
	{ "LeftHand", { 1, 0.3, 1 }, { -1.5, -0.8, 0 }, "LeftArmColor" },
	{ "RightHand", { 1, 0.3, 1 }, { 1.5, -0.8, 0 }, "RightArmColor" },
	{ "LeftUpperLeg", { 1, 0.95, 1 }, { -0.5, -1.425, 0 }, "LeftLegColor" },
	{ "RightUpperLeg", { 1, 0.95, 1 }, { 0.5, -1.425, 0 }, "RightLegColor" },
	{ "LeftLowerLeg", { 1, 0.77, 1 }, { -0.5, -2.285, 0 }, "LeftLegColor" },
	{ "RightLowerLeg", { 1, 0.77, 1 }, { 0.5, -2.285, 0 }, "RightLegColor" },
	{ "LeftFoot", { 1, 0.3, 1.2 }, { -0.5, -2.82, -0.1 }, "LeftLegColor" },
	{ "RightFoot", { 1, 0.3, 1.2 }, { 0.5, -2.82, -0.1 }, "RightLegColor" },
}

-- The mannequin: the classic R15 block body in the workwear, facing -Z.
function StylePreview.mannequin(): Model
	local model = Instance.new("Model")
	model.Name = "Mannequin"
	for _, b in BODY do
		local p = Instance.new("Part")
		p.Name = b[1]
		p.Size = Vector3.new(b[2][1], b[2][2], b[2][3])
		p.CFrame = CFrame.new(b[3][1], b[3][2], b[3][3])
		local c = AvatarLook.Workwear[b[4]] or { 120, 120, 120 }
		p.Color = Color3.fromRGB(c[1], c[2], c[3])
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = model
	end
	model.PrimaryPart = model:FindFirstChild("UpperTorso") :: BasePart
	return model
end

return StylePreview
