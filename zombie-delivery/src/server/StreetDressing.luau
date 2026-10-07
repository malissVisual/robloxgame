--!strict
-- 5.7, the street props (shared/StreetProps.luau has where; Config.LivingCity.Street): built once by
-- server/World.luau (its build list: "street props"), after the districts, the bus stops and the alleys. A Folder
-- "StreetProps" with a Model per block (Atomic streaming: a block's props come and go together), native parts only:
--   bin        a street bin with its lid (2 parts, solid)
--   hydrant    a red fire hydrant, its nozzles (2, solid)
--   barricade  an orange board on two legs (3, solid)
--   sandbags   two rows of sandbags (2, solid)
--   debris     a broken slab and a plank (2, flat: you walk over them)
--   bags       black trash bags against a tower's wall (3)
--   boarded    plywood sheets leaning on a tower's ground floor (2)
--   car        an abandoned car at the kerb, a little askew, its tyres flat (4, solid: drive round it)
--   flare      a red flare burning on the ground (1, its red light at night; it flickers: client/WorldFx.luau)
-- Only the solid ones collide; nothing but the cars is hit by a ray (the camera, the guns go through).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Map = require(Shared.Map)
local StreetProps = require(Shared.StreetProps)
local DayNight = require(script.Parent.DayNight)
local StreetArt = require(script.Parent.StreetArt.Geometry) -- 5.9: Codex's worn props (design/street-props/)
local PolishBuilder = require(script.Parent.PolishArt.Builder)

local StreetDressing = {}

local WALK_TOP = Map.WalkTop
local ROAD_TOP = Map.RoadTop
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up

local BINS = { Color3.fromRGB(46, 70, 52), Color3.fromRGB(62, 64, 68), Color3.fromRGB(40, 54, 82) }
local CARS = { Color3.fromRGB(96, 64, 52), Color3.fromRGB(70, 76, 82), Color3.fromRGB(112, 92, 62), Color3.fromRGB(58, 70, 60), Color3.fromRGB(122, 44, 40), Color3.fromRGB(150, 146, 136) }
local HYDRANT = Color3.fromRGB(176, 42, 36)
local ORANGE = Color3.fromRGB(222, 112, 34)
local STEEL = Color3.fromRGB(64, 66, 70)
local SAND = Color3.fromRGB(152, 134, 98)
local BAG = Color3.fromRGB(24, 26, 28)
local PLYWOOD = Color3.fromRGB(160, 128, 90)
local TYRE = Color3.fromRGB(26, 26, 26)
local FLARE = Color3.fromRGB(255, 60, 44)

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CastShadow = size.Magnitude > 4
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material, solid: boolean?): Part
	local p = part(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material, solid)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = part(parent, name, size, cframe, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- One prop. `frame`: on the ground at its middle, -Z (LookVector) toward the street, X along the kerb.
-- 5.9: Codex's prop for this spot (StreetArt.pieces in the same ground frame: X along the kerb, -Z to the street),
-- built by PolishArt.Builder; the flare keeps our one red light and its Flare tag on the FlareTip. False: not built.
local function buildArt(model: Instance, prop: StreetProps.Prop, frame: CFrame): boolean
	local ok, err = pcall(function()
		local made = PolishBuilder.build(model, frame, {
			id = prop.kind,
			pieces = StreetArt.pieces(prop.kind, prop.seed, prop.width) :: any,
		}, { nightLight = DayNight.nightLight })
		if prop.kind == "flare" then
			local tip = made:FindFirstChild("FlareTip", true)
			if tip and tip:IsA("BasePart") then
				local light = Instance.new("PointLight")
				light.Color = FLARE
				light.Range = 14
				light.Brightness = 1.6
				light.Shadows = false
				light.Parent = tip
				DayNight.nightLight(light)
				CollectionService:AddTag(tip, "Flare")
			end
		end
	end)
	if not ok then
		warn(`[StreetDressing] the {prop.kind} art failed, the simple one stands: {err}`)
	end
	return ok
end

local function build(model: Instance, prop: StreetProps.Prop)
	local rand = Random.new(prop.seed)
	local ground = if prop.road then ROAD_TOP else WALK_TOP
	local at = Vector3.new(prop.x, ground, prop.z)
	-- (a car only a hair askew: its ends stay out of the traffic's lane)
	local frame = CFrame.lookAt(at, at + Vector3.new(prop.nx, 0, prop.nz)) * CFrame.Angles(0, if prop.road then 0 else prop.turn, 0)
	local kind = prop.kind
	if buildArt(model, prop, frame) then
		return
	end
	if kind == "bin" then
		local color = BINS[rand:NextInteger(1, #BINS)]
		part(model, "Bin", Vector3.new(1.4, 2.2, 1.4), frame * CFrame.new(0, 1.1, 0), color, Enum.Material.Metal, true)
		part(model, "BinLid", Vector3.new(1.6, 0.25, 1.6), frame * CFrame.new(0, 2.32, 0) * CFrame.Angles(rand:NextNumber(-0.15, 0.05), 0, 0), color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Metal)
	elseif kind == "hydrant" then
		cylinder(model, "Hydrant", 2.2, 0.9, frame * CFrame.new(0, 1.1, 0) * UPRIGHT, HYDRANT, Enum.Material.Metal, true)
		cylinder(model, "HydrantNozzles", 1.5, 0.42, frame * CFrame.new(0, 1.45, 0), HYDRANT:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Metal)
	elseif kind == "barricade" then
		part(model, "Barricade", Vector3.new(4.6, 1, 0.25), frame * CFrame.new(0, 2.3, 0), ORANGE, Enum.Material.SmoothPlastic, true)
		for _, side in { -1, 1 } do
			part(model, "BarricadeLeg", Vector3.new(0.3, 2.6, 1.3), frame * CFrame.new(side * 1.9, 1.3, 0), STEEL, Enum.Material.Metal, true)
		end
	elseif kind == "sandbags" then
		part(model, "Sandbags", Vector3.new(4, 0.9, 1.4), frame * CFrame.new(0, 0.45, 0), SAND, Enum.Material.Fabric, true)
		part(model, "Sandbags", Vector3.new(3.2, 0.8, 1.2), frame * CFrame.new(rand:NextNumber(-0.3, 0.3), 1.3, 0.05) * CFrame.Angles(0, rand:NextNumber(-0.08, 0.08), 0), SAND:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Fabric, true)
	elseif kind == "debris" then
		part(model, "Rubble", Vector3.new(2.4, 0.4, 1.6), frame * CFrame.new(-0.4, 0.25, 0) * CFrame.Angles(rand:NextNumber(-0.15, 0.15), rand:NextNumber(0, 3), rand:NextNumber(-0.2, 0.2)), Color3.fromRGB(118, 116, 110), Enum.Material.Concrete)
		part(model, "Plank", Vector3.new(3, 0.2, 0.5), frame * CFrame.new(0.6, 0.2, 0.2) * CFrame.Angles(0, rand:NextNumber(-1, 1), rand:NextNumber(-0.12, 0.12)), Color3.fromRGB(112, 86, 60), Enum.Material.WoodPlanks)
	elseif kind == "bags" then
		ball(model, "TrashBag", Vector3.new(1.8, 1.6, 1.7), frame * CFrame.new(-0.7, 0.75, 0.2), BAG, Enum.Material.Plastic)
		ball(model, "TrashBag", Vector3.new(1.6, 1.5, 1.6), frame * CFrame.new(0.8, 0.7, 0.3), BAG, Enum.Material.Plastic)
		ball(model, "TrashBag", Vector3.new(1.2, 1.1, 1.2), frame * CFrame.new(0.1, 1.55, 0.4), Color3.fromRGB(40, 44, 40), Enum.Material.Plastic)
	elseif kind == "boarded" then
		-- (the wall is 0.35 behind the prop's middle: +Z)
		local sheet = math.max(2, prop.width / 2 - 0.2)
		for _, side in { -1, 1 } do
			local lean = CFrame.Angles(-rand:NextNumber(0.06, 0.12), 0, rand:NextNumber(-0.03, 0.03))
			part(model, "Plywood", Vector3.new(sheet, 6.4, 0.2), frame * CFrame.new(side * (sheet / 2 + 0.1), 3.2, 0.1) * lean, PLYWOOD:Lerp(Color3.new(0, 0, 0), rand:NextNumber(0, 0.2)), Enum.Material.WoodPlanks)
		end
	elseif kind == "car" then
		-- Its long side along the kerb, askew, sagging on its flat tyres on the street's side.
		local color = CARS[rand:NextInteger(1, #CARS)]
		local body = frame * CFrame.Angles(0, math.pi / 2 + rand:NextNumber(-0.04, 0.04), 0) * CFrame.Angles(0, 0, math.rad(rand:NextNumber(2, 5)))
		local hull = part(model, "AbandonedCar", Vector3.new(4.8, 2.4, 11), body * CFrame.new(0, 1.55, 0), color, Enum.Material.CorrodedMetal, true)
		hull.CanQuery = true -- (a car stops a bullet)
		part(model, "CarCabin", Vector3.new(4.4, 1.9, 5.4), body * CFrame.new(0, 3.7, 0.4), color:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.CorrodedMetal)
		for _, along in { -3.6, 3.6 } do
			cylinder(model, "CarTyres", 5.2, 2, body * CFrame.new(0, 0.9, along), TYRE, Enum.Material.Rubber)
		end
	elseif kind == "flare" then
		local stick = part(model, "Flare", Vector3.new(1, 0.25, 0.25), frame * CFrame.new(0, 0.13, 0) * CFrame.Angles(0, rand:NextNumber(0, math.pi), 0), FLARE, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = FLARE
		light.Range = 14
		light.Brightness = 1.6
		light.Shadows = false
		light.Parent = stick
		DayNight.nightLight(light)
		CollectionService:AddTag(stick, "Flare")
	end
end

function StreetDressing.build(world: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "StreetProps"
	local count = 0
	for _, block in StreetProps.blocks() do
		local model = Instance.new("Model")
		model.Name = `Street {block.district} {block.i},{block.j}`
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		for _, prop in block.props do
			build(model, prop)
			count += 1
		end
		model.Parent = folder
	end
	folder.Parent = world
	print(`[StreetDressing] {count} props on {#StreetProps.blocks()} blocks`)
end

return StreetDressing
