--!strict
-- 7.1, the Alps step 1: builds the Suburbs houses as Austrian chalets and dresses the houses for sale on the Suburbs
-- lots, from shared/ChaletLooks.luau's pieces (plain numbers, tested in tests/chalet_test.luau). server/World.luau calls
-- it with its own helpers handed over (no new top-level locals there, the -O0 register limit):
--
--   Chalets.house(parent, frame, spec, lit, tools)    a house of Map.Homes (World's buildHouse): `frame` its door's
--                                                     frame (the middle of the front wall on the walk, -Z out to the
--                                                     street), `spec` its lot and the world's dice, `lit` the world's
--                                                     two window dice (a lit window glows at night: DayNight)
--   Chalets.estate(parent, frame, layout, tools)      a house for sale on a Suburbs lot (World's estateHouse): the
--                                                     timber band, the shutters, the geraniums, the firewood and, on
--                                                     a two-storey house, the balcony
--
-- The solid pieces (the house's body, its gable and its door) are World's part() as the house's were before 7.1: the
-- "Door" swings open for a delivery (server/Cargo.luau finds it by its name); everything else is decoration (no
-- collision, no ray hits).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChaletLooks = require(Shared.ChaletLooks)

local Chalets = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
}

local WINDOW_LIT = Color3.fromRGB(255, 210, 120)

local function make(parent: Instance, frame: CFrame, piece: ChaletLooks.Piece, tools: Tools): Part
	local turn = piece.turn or { 0, 0, 0 }
	local at, size, c = piece.at, piece.size, piece.color
	local cframe = frame * CFrame.new(at[1], at[2], at[3]) * CFrame.Angles(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
	local material = (Enum.Material :: any)[piece.material] :: Enum.Material
	local p = tools.part(parent, piece.name, Vector3.new(size[1], size[2], size[3]), cframe, Color3.fromRGB(c[1], c[2], c[3]), material)
	if piece.shape == "Wedge" then
		p.Shape = Enum.PartType.Wedge
	elseif piece.shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	if not piece.solid then
		tools.deco(p)
	end
	return p
end

function Chalets.house(parent: Instance, frame: CFrame, spec: ChaletLooks.Spec, lit: { boolean }, tools: Tools)
	for _, piece in ChaletLooks.house(spec) do
		local p = make(parent, frame, piece, tools)
		local die = piece.window
		if die and lit[die] then
			tools.nightLight(p, WINDOW_LIT, p.Color, "Glass")
		end
	end
end

function Chalets.estate(parent: Instance, frame: CFrame, layout: ChaletLooks.EstateLayout, tools: Tools)
	for _, piece in ChaletLooks.estate(layout) do
		make(parent, frame, piece, tools)
	end
end

return Chalets
