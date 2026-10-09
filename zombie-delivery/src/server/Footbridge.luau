--!strict
-- 6.12.15, the footbridge over Bone St (Map.Footbridge) mid-block between the Central Park (south,
-- server/CentralPark.luau) and the Lantern Garden (north, server/LanternGarden.luau). server/World.luau builds it as a
-- piece of the world (Footbridge.build, with World's helpers handed over: no new top-level locals there, the -O0
-- register limit).
-- 6.12.16 (the owner: "good for walking, only I walk through this [a timber of the arch]. I'd make it wider, for two
-- people at least, and don't be afraid to make it curve a bit"): one curved walkway 10 studs wide between vermilion
-- railings, up from the park's east path round its north-east corner, along its north lawn, in a soft S over the street
-- (a taiko-bridge hump, a torii at each end of the span) and down the garden's south and west edges to its path. Every
-- piece of it is shared/FootbridgeShape.luau's (plain numbers, tested in tests/garden_test.luau: nothing at all stands
-- in the walkway up to 9 studs over it, no step in the walking surface, the clearance over the street); this makes a
-- part of each. Solid: the walking surface and the railings; the rest is decoration (no collision, no ray hits).
-- 6.12.16 review: where a ramp is lower than 9 studs over the ground, a planted bed under it closed by solid clipped
-- hedges (nobody walks or rides under it there; the park's path to its north-east corner ends before it). About 930
-- parts, three lights.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FootbridgeShape = require(Shared.FootbridgeShape)

local Footbridge = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	sign: (parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?, art: string?, artHeight: number?) -> (),
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
}

local LANTERN_LIT = Color3.fromRGB(255, 178, 96)
local LIGHT = Color3.fromRGB(255, 196, 130)

local function vector(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end
local function color(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Footbridge.build(parent: Instance, tools: Tools)
	local folder = Instance.new("Folder")
	folder.Name = "Footbridge"
	folder.Parent = parent
	for _, piece in FootbridgeShape.pieces() do
		local frame = CFrame.fromMatrix(vector(piece.at), vector(piece.right), vector(piece.up), vector(piece.back))
		local material = (Enum.Material :: any)[piece.material] :: Enum.Material
		local p = tools.part(folder, piece.name, vector(piece.size), frame, color(piece.color), material)
		if not piece.solid then
			tools.deco(p)
		end
		if piece.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif piece.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		end
		if piece.glow then
			tools.nightLight(p, LANTERN_LIT, color(piece.color), if piece.glow == "glass" then "Glass" else "SmoothPlastic")
		end
		if piece.light then
			local light = Instance.new("PointLight")
			light.Range = piece.light
			light.Brightness = 1.2
			light.Color = LIGHT
			light.Shadows = false
			light.Parent = p
		end
	end
end

return Footbridge
