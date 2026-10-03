--!strict
-- Builds the city in code when the server starts: ground, roads, blocks with buildings, parks and parking lots,
-- the depot (Zombie Delivery Co.), street lamps, wrecked cars on the roads, the quarantine wall and the dusk light.
-- The layout comes from shared/CityGrid.luau and a fixed seed, so every server has the same city.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CityGrid = require(Shared.CityGrid)

local World = {}

local B = CityGrid.Blocks
local BLOCK = CityGrid.BlockSize
local ROAD = CityGrid.RoadWidth
local CELL = CityGrid.Cell
local EDGE = CityGrid.Edge

local ROAD_TOP = 0.4
local WALK_TOP = 0.6

World.DepotCenter = Vector3.new(0, WALK_TOP, 0)
World.DepotSpawn = Vector3.new(0, WALK_TOP + 3, 26)
World.SafeRadius = Config.City.SafeRadius

local rng = Random.new(Config.City.Seed)

local BUILDING_COLORS = {
	Color3.fromRGB(122, 112, 104),
	Color3.fromRGB(140, 96, 80),
	Color3.fromRGB(96, 104, 112),
	Color3.fromRGB(150, 140, 120),
	Color3.fromRGB(86, 82, 90),
	Color3.fromRGB(120, 78, 64),
	Color3.fromRGB(104, 116, 98),
}
local BUILDING_MATERIALS = { Enum.Material.Concrete, Enum.Material.Brick, Enum.Material.SmoothPlastic, Enum.Material.Concrete }
local WRECK_COLORS = {
	Color3.fromRGB(90, 60, 50),
	Color3.fromRGB(70, 74, 80),
	Color3.fromRGB(110, 90, 60),
	Color3.fromRGB(60, 70, 60),
	Color3.fromRGB(120, 40, 36),
}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.Parent = parent
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- ── Pieces ─────────────────────────────────────────────────────────────────

local function buildRoads(parent: Instance)
	local roads = folder(parent, "Roads")
	local asphalt = Color3.fromRGB(46, 46, 50)
	local line = Color3.fromRGB(200, 170, 60)
	local length = EDGE * 2
	-- Roads along Z run the whole length; roads along X are cut into pieces between them (no overlapping faces).
	for k = -B - 1, B do
		local x = CityGrid.roadCenter(k)
		part(roads, "Road", Vector3.new(ROAD, 0.4, length), CFrame.new(x, ROAD_TOP - 0.2, 0), asphalt, Enum.Material.Asphalt)
		local stripe = part(roads, "Line", Vector3.new(0.6, 0.05, length), CFrame.new(x, ROAD_TOP + 0.02, 0), line, Enum.Material.SmoothPlastic)
		stripe.CanCollide = false
		stripe.CanQuery = false
		for i = -B, B do
			local cx = i * CELL
			part(roads, "Road", Vector3.new(BLOCK, 0.4, ROAD), CFrame.new(cx, ROAD_TOP - 0.2, x), asphalt, Enum.Material.Asphalt)
			local cross = part(roads, "Line", Vector3.new(BLOCK, 0.05, 0.6), CFrame.new(cx, ROAD_TOP + 0.02, x), line, Enum.Material.SmoothPlastic)
			cross.CanCollide = false
			cross.CanQuery = false
		end
	end
end

local function buildTree(parent: Instance, x: number, z: number)
	local height = rng:NextNumber(7, 12)
	local trunk = part(parent, "Trunk", Vector3.new(height, 1.4, 1.4), CFrame.new(x, WALK_TOP + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 60, 44), Enum.Material.Wood)
	trunk.Shape = Enum.PartType.Cylinder
	local size = rng:NextNumber(7, 11)
	local leaves = part(parent, "Leaves", Vector3.new(size, size, size), CFrame.new(x, WALK_TOP + height + size * 0.25, z), Color3.fromRGB(64, 84, 46), Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
	leaves.CanCollide = false
end

local function buildWreck(parent: Instance, cframe: CFrame)
	local model = Instance.new("Model")
	model.Name = "Wreck"
	local color = WRECK_COLORS[rng:NextInteger(1, #WRECK_COLORS)]
	local body = part(model, "Body", Vector3.new(6, 2.6, 12), cframe * CFrame.new(0, 1.7, 0), color, Enum.Material.CorrodedMetal)
	part(model, "Cabin", Vector3.new(5.4, 2, 6), cframe * CFrame.new(0, 3.9, 0.5) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6))), color, Enum.Material.CorrodedMetal)
	local glass = part(model, "Glass", Vector3.new(5.6, 1.6, 0.2), cframe * CFrame.new(0, 3.9, -2.6), Color3.fromRGB(40, 50, 55), Enum.Material.Glass)
	glass.Transparency = 0.3
	for _, offset in { Vector3.new(-3, 0.9, -3.8), Vector3.new(3, 0.9, -3.8), Vector3.new(-3, 0.9, 3.8), Vector3.new(3, 0.9, 3.8) } do
		local wheel = part(model, "Tire", Vector3.new(1, 2, 2), cframe * CFrame.new(offset), Color3.fromRGB(25, 25, 25), Enum.Material.Rubber)
		wheel.Shape = Enum.PartType.Cylinder
		wheel.CanCollide = false
	end
	if rng:NextNumber() < 0.3 then
		local fire = Instance.new("Fire")
		fire.Size = 6
		fire.Heat = 8
		fire.Parent = body
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 140, 60)
		light.Range = 24
		light.Brightness = 2
		light.Parent = body
	end
	model.PrimaryPart = body
	model.Parent = parent
end

local function buildBuilding(parent: Instance, cx: number, cz: number, lot: number, height: number)
	local w = lot - rng:NextNumber(2, 9)
	local d = lot - rng:NextNumber(2, 9)
	local color = BUILDING_COLORS[rng:NextInteger(1, #BUILDING_COLORS)]
	local material = BUILDING_MATERIALS[rng:NextInteger(1, #BUILDING_MATERIALS)]
	local model = Instance.new("Model")
	model.Name = "Building"
	part(model, "Walls", Vector3.new(w, height, d), CFrame.new(cx, WALK_TOP + height / 2, cz), color, material)
	-- Window strips, a few of them still lit.
	local floors = math.min(math.floor((height - 4) / 9), 6)
	for f = 1, floors do
		local y = WALK_TOP + f * 9
		for side = 0, 3 do
			local angle = side * math.pi / 2
			local faceWidth = if side % 2 == 0 then w else d
			local faceDepth = if side % 2 == 0 then d else w
			local lit = rng:NextNumber() < 0.25
			local window = part(
				model,
				"Window",
				Vector3.new(faceWidth - 4, 3, 0.3),
				CFrame.new(cx, y, cz) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, faceDepth / 2 + 0.1),
				if lit then Color3.fromRGB(255, 210, 120) else Color3.fromRGB(30, 36, 44),
				if lit then Enum.Material.Neon else Enum.Material.Glass
			)
			window.CanCollide = false
			window.CanQuery = false
		end
	end
	if rng:NextNumber() < 0.5 then
		part(model, "RoofBox", Vector3.new(6, 3, 6), CFrame.new(cx + rng:NextNumber(-w / 4, w / 4), WALK_TOP + height + 1.5, cz + rng:NextNumber(-d / 4, d / 4)), Color3.fromRGB(90, 90, 90), Enum.Material.Metal)
	end
	model.Parent = parent
end

local function buildBlock(parent: Instance, i: number, j: number)
	local cx, cz = CityGrid.blockCenter(i, j)
	local block = folder(parent, `Block_{i}_{j}`)
	part(block, "Sidewalk", Vector3.new(BLOCK, WALK_TOP, BLOCK), CFrame.new(cx, WALK_TOP / 2, cz), Color3.fromRGB(150, 150, 146), Enum.Material.Concrete)
	local inset = 6
	local lot = (BLOCK - inset * 2) / 2
	local centerFactor = 1 - math.max(math.abs(i), math.abs(j)) / (B + 1) -- taller in the middle of the city
	for a = 0, 1 do
		for b = 0, 1 do
			local lx = cx - BLOCK / 2 + inset + lot * (a + 0.5)
			local lz = cz - BLOCK / 2 + inset + lot * (b + 0.5)
			local roll = rng:NextNumber()
			if roll < 0.7 then
				buildBuilding(block, lx, lz, lot, rng:NextNumber(16, 34) + 50 * centerFactor * rng:NextNumber())
			elseif roll < 0.85 then
				local grass = part(block, "Grass", Vector3.new(lot - 2, 0.1, lot - 2), CFrame.new(lx, WALK_TOP + 0.05, lz), Color3.fromRGB(70, 88, 52), Enum.Material.Grass)
				grass.CanCollide = false
				for _ = 1, rng:NextInteger(2, 4) do
					buildTree(block, lx + rng:NextNumber(-lot / 3, lot / 3), lz + rng:NextNumber(-lot / 3, lot / 3))
				end
			else
				local lotPart = part(block, "Parking", Vector3.new(lot - 2, 0.1, lot - 2), CFrame.new(lx, WALK_TOP + 0.05, lz), Color3.fromRGB(60, 60, 64), Enum.Material.Asphalt)
				lotPart.CanCollide = false
				buildWreck(block, CFrame.new(lx, WALK_TOP, lz) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
			end
		end
	end
end

local function sign(parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3)
	local board = part(parent, "Sign", size, cframe, Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.Parent = gui
end

local function buildDepot(parent: Instance)
	local depot = folder(parent, "Depot")
	part(depot, "Yard", Vector3.new(BLOCK, WALK_TOP, BLOCK), CFrame.new(0, WALK_TOP / 2, 0), Color3.fromRGB(120, 120, 116), Enum.Material.Concrete)
	-- The warehouse at the back, its open front faces +Z (the yard and the road).
	local wallColor = Color3.fromRGB(170, 120, 60)
	local depth, width, height = 40, 80, 22
	local backZ = -BLOCK / 2 + 6
	part(depot, "Back", Vector3.new(width, height, 2), CFrame.new(0, WALK_TOP + height / 2, backZ + 1), wallColor, Enum.Material.Metal)
	part(depot, "Left", Vector3.new(2, height, depth), CFrame.new(-width / 2 + 1, WALK_TOP + height / 2, backZ + depth / 2), wallColor, Enum.Material.Metal)
	part(depot, "Right", Vector3.new(2, height, depth), CFrame.new(width / 2 - 1, WALK_TOP + height / 2, backZ + depth / 2), wallColor, Enum.Material.Metal)
	part(depot, "Roof", Vector3.new(width, 2, depth), CFrame.new(0, WALK_TOP + height + 1, backZ + depth / 2), Color3.fromRGB(90, 70, 50), Enum.Material.Metal)
	sign(depot, "ZOMBIE DELIVERY CO.", Vector3.new(60, 8, 1), CFrame.new(0, WALK_TOP + height + 6, backZ + depth - 2) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(255, 190, 60))
	-- Crates inside.
	for n = 1, 10 do
		local s = rng:NextNumber(3, 5)
		part(depot, "Crate", Vector3.new(s, s, s), CFrame.new(rng:NextNumber(-34, 34), WALK_TOP + s / 2, backZ + rng:NextNumber(4, 18)) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
		if n > 7 then
			part(depot, "Crate", Vector3.new(s * 0.8, s * 0.8, s * 0.8), CFrame.new(rng:NextNumber(-34, 34), WALK_TOP + s * 1.4, backZ + rng:NextNumber(4, 18)), Color3.fromRGB(140, 100, 64), Enum.Material.WoodPlanks)
		end
	end
	-- The safe zone ring: zombies never come in here.
	local ring = part(depot, "SafeZone", Vector3.new(0.2, World.SafeRadius * 2, World.SafeRadius * 2), CFrame.new(0, WALK_TOP + 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 255, 140), Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.85
	ring.CanCollide = false
	ring.CanQuery = false
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DepotSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(World.DepotSpawn.X, WALK_TOP + 0.2, World.DepotSpawn.Z)
	spawn.Color = Color3.fromRGB(255, 190, 60)
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.4
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = depot
end

local function buildLamps(parent: Instance)
	local lamps = folder(parent, "Lamps")
	for kx = -B - 1, B do
		for kz = -B - 1, B do
			local x = CityGrid.roadCenter(kx) + ROAD / 2 + 2
			local z = CityGrid.roadCenter(kz) + ROAD / 2 + 2
			if math.abs(x) > EDGE or math.abs(z) > EDGE then
				continue
			end
			part(lamps, "Pole", Vector3.new(0.6, 16, 0.6), CFrame.new(x, WALK_TOP + 8, z), Color3.fromRGB(50, 50, 54), Enum.Material.Metal)
			local head = part(lamps, "Lamp", Vector3.new(1.6, 0.6, 1.6), CFrame.new(x, WALK_TOP + 16, z), Color3.fromRGB(255, 220, 160), Enum.Material.Neon)
			head.CanCollide = false
			local light = Instance.new("PointLight")
			light.Range = 40
			light.Brightness = 1.4
			light.Color = Color3.fromRGB(255, 210, 150)
			light.Shadows = false
			light.Parent = head
		end
	end
end

-- Wrecks on the roads, never on a crossing and always leaving one lane free.
local function buildRoadWrecks(parent: Instance)
	local wrecks = folder(parent, "RoadWrecks")
	for _ = 1, 26 do
		local k = rng:NextInteger(-B - 1, B)
		local i = rng:NextInteger(-B, B)
		local along = i * CELL + rng:NextNumber(-BLOCK / 2 + 16, BLOCK / 2 - 16)
		local lane = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(7, 10)
		local x, z, yaw
		if rng:NextNumber() < 0.5 then
			x, z, yaw = CityGrid.roadCenter(k) + lane, along, rng:NextNumber(-0.5, 0.5)
		else
			x, z, yaw = along, CityGrid.roadCenter(k) + lane, math.pi / 2 + rng:NextNumber(-0.5, 0.5)
		end
		if math.abs(x) < 90 and math.abs(z) < 90 then
			continue -- keep the depot exit clear
		end
		buildWreck(wrecks, CFrame.new(x, ROAD_TOP, z) * CFrame.Angles(0, yaw, 0))
	end
end

local function buildWall(parent: Instance)
	local walls = folder(parent, "QuarantineWall")
	local size = EDGE * 2 + 8
	local d = EDGE + 3
	local color = Color3.fromRGB(110, 110, 104)
	for _, info in { { Vector3.new(size, 14, 2), Vector3.new(0, 7, d) }, { Vector3.new(size, 14, 2), Vector3.new(0, 7, -d) }, { Vector3.new(2, 14, size), Vector3.new(d, 7, 0) }, { Vector3.new(2, 14, size), Vector3.new(-d, 7, 0) } } do
		part(walls, "Wall", info[1], CFrame.new(info[2]), color, Enum.Material.Concrete)
		local stripe = part(walls, "Stripe", info[1] * Vector3.new(1, 0, 1) + Vector3.new(0.2, 1.2, 0.2), CFrame.new(info[2] + Vector3.new(0, 4, 0)), Color3.fromRGB(220, 180, 40), Enum.Material.SmoothPlastic)
		stripe.CanCollide = false
		local invisible = part(walls, "Invisible", info[1] + Vector3.new(0, 120, 0), CFrame.new(info[2] + Vector3.new(0, 60, 0)), color)
		invisible.Transparency = 1
		invisible.CanQuery = false
	end
end

local function setLighting()
	Lighting.ClockTime = 18.6
	Lighting.Brightness = 1.6
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 110)
	Lighting.FogColor = Color3.fromRGB(110, 120, 110)
	Lighting.FogStart = 120
	Lighting.FogEnd = 650
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Color = Color3.fromRGB(150, 160, 140)
	atmosphere.Decay = Color3.fromRGB(90, 100, 80)
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting
	local grade = Lighting:FindFirstChild("ZombieGrade") :: ColorCorrectionEffect? or Instance.new("ColorCorrectionEffect")
	grade.Name = "ZombieGrade"
	grade.Saturation = -0.25
	grade.Contrast = 0.1
	grade.TintColor = Color3.fromRGB(235, 245, 225)
	grade.Parent = Lighting
end

function World.build()
	-- A fresh Baseplate place: its plate and spawn would sit inside the city.
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local city = folder(workspace, "City")
	part(city, "Ground", Vector3.new(EDGE * 2 + 600, 4, EDGE * 2 + 600), CFrame.new(0, -2, 0), Color3.fromRGB(78, 80, 58), Enum.Material.Ground)
	buildRoads(city)
	for i = -B, B do
		for j = -B, B do
			if i == 0 and j == 0 then
				buildDepot(city)
			else
				buildBlock(city, i, j)
			end
		end
	end
	buildLamps(city)
	buildRoadWrecks(city)
	buildWall(city)
	setLighting()

	folder(workspace, "Cars")
	folder(workspace, "Zombies")
	folder(workspace, "Effects")
end

function World.isSafe(position: Vector3): boolean
	return Vector3.new(position.X - World.DepotCenter.X, 0, position.Z - World.DepotCenter.Z).Magnitude < World.SafeRadius
end

-- The ground height on a road.
World.RoadTop = ROAD_TOP

return World
