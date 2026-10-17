--!strict
-- The lamps' look. 10.6 (only the sandbox is the game): its day never turns (server/SandboxWorld.luau's fixed
-- afternoon, Config.Sandbox's Light.Clock), so the city's clock, its Night attribute, the weather and the night lights'
-- switching are gone; what registered a night light shows its day look at once. The name stays: the vehicle, house and
-- site builders pass DayNight.nightLight on, and the tests' and the art tools' stand-ins replace this module by it.
--
--   DayNight.nightLight(item, lit?, dim?, dimMaterial?)   a part that glowed at night (Neon in `lit`): its `dim` colour
--                             (when both are given) in `dimMaterial` (Glass, SmoothPlastic, Metal, Plastic; default
--                             SmoothPlastic), the Lights inside it off; a Light alone is only switched off
--   DayNight.nightFactor()    0: the sandbox's afternoon is full day (Zombies' night share of the roamers and kinds)

local DayNight = {}

local DIM_MATERIALS: { [string]: Enum.Material } = {
	Glass = Enum.Material.Glass,
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Plastic = Enum.Material.Plastic,
}

function DayNight.nightLight(item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?)
	if item:IsA("Light") then
		item.Enabled = false
		return
	end
	if item:IsA("BasePart") then
		if lit and dim then
			item.Color = dim
		end
		item.Material = if dimMaterial and DIM_MATERIALS[dimMaterial] then DIM_MATERIALS[dimMaterial] else Enum.Material.SmoothPlastic
	end
	for _, child in item:GetChildren() do
		if child:IsA("Light") then
			child.Enabled = false
		end
	end
end

function DayNight.nightFactor(): number
	return 0
end

return DayNight
