--!strict
-- Builds the world in code when the server starts, from the layout in shared/Map.luau and a fixed seed (every server
-- gets the same world): the land, the river and the sea (terrain water), the three districts (Downtown, Harbor,
-- Suburbs), the bridges, the highways with the mountain tunnel (terrain), the far places (Military Base, Radio
-- Station, Old Farm, Harbor Docks, Gas Station), the depot and the four shops, lamps, wrecks, forests and the light.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)

local World = {}

local BLOCK = Map.BlockSize
local ROAD = Map.RoadWidth
local CELL = Map.Cell
local ROAD_TOP = Map.RoadTop
local WALK_TOP = Map.WalkTop

World.RoadTop = ROAD_TOP
World.DepotSpawn = Vector3.new(0, WALK_TOP + 3, 26)
World.ShopPrompts = {} :: { { prompt: ProximityPrompt, shop: string } }
World.EmployerPrompts = {} :: { { prompt: ProximityPrompt, employer: string } }
World.DealerSlots = {} :: { CFrame }
World.RepairSpots = { Vector3.new(0, 0, 0) } :: { Vector3 }

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
local CONTAINER_COLORS = {
	Color3.fromRGB(170, 60, 40),
	Color3.fromRGB(40, 90, 150),
	Color3.fromRGB(60, 120, 70),
	Color3.fromRGB(200, 150, 40),
	Color3.fromRGB(120, 120, 124),
	Color3.fromRGB(150, 80, 120),
}
local ASPHALT = Color3.fromRGB(46, 46, 50)
local LINE = Color3.fromRGB(200, 170, 60)

-- ── Helpers ────────────────────────────────────────────────────────────────

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

local function deco(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	return p
end

local function cylinder(parent: Instance, name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Parts can be at most 2048 studs long: big flat things are laid as tiles.
local TILE = 2000
local function tiled(parent: Instance, name: string, x0: number, x1: number, z0: number, z1: number, y: number, height: number, color: Color3, material: Enum.Material): { Part }
	local list = {}
	local nx = math.ceil((x1 - x0) / TILE)
	local nz = math.ceil((z1 - z0) / TILE)
	local w, d = (x1 - x0) / nx, (z1 - z0) / nz
	for a = 0, nx - 1 do
		for b = 0, nz - 1 do
			table.insert(list, part(parent, name, Vector3.new(w, height, d), CFrame.new(x0 + w * (a + 0.5), y, z0 + d * (b + 0.5)), color, material))
		end
	end
	return list
end

local function light(parent: Instance, range: number, brightness: number, color: Color3)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color
	l.Shadows = false
	l.Parent = parent
end

local function sign(parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?)
	local board = part(parent, "Sign", size, cframe, background or Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
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

local function prompt(parent: BasePart, shop: string, action: string, object: string)
	local p = Instance.new("ProximityPrompt")
	p.Name = "ShopPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p:SetAttribute("Shop", shop)
	p.Parent = parent
	table.insert(World.ShopPrompts, { prompt = p, shop = shop })
end

local function tree(parent: Instance, x: number, z: number, y: number?)
	local base = y or WALK_TOP
	if Map.isWinter(x, z) then
		-- A snowy pine: stacked dark balls with snow on top.
		local height = rng:NextNumber(10, 16)
		cylinder(parent, "Trunk", height, 1.2, CFrame.new(x, base + height / 2, z) * UPRIGHT, Color3.fromRGB(70, 52, 40), Enum.Material.Wood)
		for n = 0, 2 do
			local size = 9 - n * 2.5
			local ball = part(parent, "Needles", Vector3.new(size, size * 0.8, size), CFrame.new(x, base + height * 0.45 + n * 3.2, z), Color3.fromRGB(40, 64, 46), Enum.Material.Grass)
			ball.Shape = Enum.PartType.Ball
			ball.CanCollide = false
		end
		local cap = part(parent, "Snow", Vector3.new(3, 2.4, 3), CFrame.new(x, base + height * 0.45 + 8.4, z), Color3.fromRGB(245, 248, 250), Enum.Material.Snow)
		cap.Shape = Enum.PartType.Ball
		cap.CanCollide = false
		return
	end
	local height = rng:NextNumber(7, 13)
	cylinder(parent, "Trunk", height, 1.4, CFrame.new(x, base + height / 2, z) * UPRIGHT, Color3.fromRGB(80, 60, 44), Enum.Material.Wood)
	local size = rng:NextNumber(7, 12)
	local leaves = part(parent, "Leaves", Vector3.new(size, size, size), CFrame.new(x, base + height + size * 0.25, z), Color3.fromRGB(58 + rng:NextInteger(0, 20), 80 + rng:NextInteger(0, 20), 44), Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
	leaves.CanCollide = false
end

local function wreck(parent: Instance, cframe: CFrame, color: Color3?)
	local model = Instance.new("Model")
	model.Name = "Wreck"
	local c = color or WRECK_COLORS[rng:NextInteger(1, #WRECK_COLORS)]
	local body = part(model, "Body", Vector3.new(6, 2.6, 12), cframe * CFrame.new(0, 1.7, 0), c, Enum.Material.CorrodedMetal)
	part(model, "Cabin", Vector3.new(5.4, 2, 6), cframe * CFrame.new(0, 3.9, 0.5) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6))), c, Enum.Material.CorrodedMetal)
	local glass = deco(part(model, "Glass", Vector3.new(5.6, 1.6, 0.2), cframe * CFrame.new(0, 3.9, -2.6), Color3.fromRGB(40, 50, 55), Enum.Material.Glass))
	glass.Transparency = 0.3
	for _, offset in { Vector3.new(-3, 0.9, -3.8), Vector3.new(3, 0.9, -3.8), Vector3.new(-3, 0.9, 3.8), Vector3.new(3, 0.9, 3.8) } do
		deco(cylinder(model, "Tire", 1, 2, cframe * CFrame.new(offset), Color3.fromRGB(25, 25, 25), Enum.Material.Rubber))
	end
	if rng:NextNumber() < 0.25 then
		local fire = Instance.new("Fire")
		fire.Size = 6
		fire.Heat = 8
		fire.Parent = body
		light(body, 24, 2, Color3.fromRGB(255, 140, 60))
	end
	model.PrimaryPart = body
	model.Parent = parent
end

local function lamp(parent: Instance, x: number, z: number, base: number?)
	local y = base or WALK_TOP
	part(parent, "Pole", Vector3.new(0.6, 16, 0.6), CFrame.new(x, y + 8, z), Color3.fromRGB(50, 50, 54), Enum.Material.Metal)
	local head = deco(part(parent, "Lamp", Vector3.new(1.6, 0.6, 1.6), CFrame.new(x, y + 16, z), Color3.fromRGB(255, 220, 160), Enum.Material.Neon))
	light(head, 42, 1.4, Color3.fromRGB(255, 210, 150))
end

-- A closed building with a door in the front wall. frame: origin at the floor centre, -Z (LookVector) = the front.
local function building(parent: Instance, frame: CFrame, w: number, d: number, h: number, color: Color3, material: Enum.Material, door: number, doorHeight: number, glass: boolean?)
	local wallMaterial = if glass then Enum.Material.Glass else material
	local wallColor = if glass then Color3.fromRGB(150, 190, 210) else color
	local function wall(name: string, size: Vector3, offset: CFrame)
		local p = part(parent, name, size, frame * offset, wallColor, wallMaterial)
		if glass then
			p.Transparency = 0.55
		end
	end
	part(parent, "Floor", Vector3.new(w, 0.3, d), frame * CFrame.new(0, 0.15, 0), Color3.fromRGB(110, 110, 112), Enum.Material.Concrete)
	wall("Back", Vector3.new(w, h, 1), CFrame.new(0, h / 2, d / 2 - 0.5))
	wall("Side", Vector3.new(1, h, d), CFrame.new(-w / 2 + 0.5, h / 2, 0))
	wall("Side", Vector3.new(1, h, d), CFrame.new(w / 2 - 0.5, h / 2, 0))
	local piece = (w - door) / 2
	wall("Front", Vector3.new(piece, h, 1), CFrame.new(-(door / 2 + piece / 2), h / 2, -d / 2 + 0.5))
	wall("Front", Vector3.new(piece, h, 1), CFrame.new(door / 2 + piece / 2, h / 2, -d / 2 + 0.5))
	wall("Lintel", Vector3.new(door, h - doorHeight, 1), CFrame.new(0, doorHeight + (h - doorHeight) / 2, -d / 2 + 0.5))
	-- Glass walls get solid corner posts and a solid roof.
	part(parent, "Roof", Vector3.new(w + 2, 1, d + 2), frame * CFrame.new(0, h + 0.5, 0), color:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal)
	if glass then
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				part(parent, "Post", Vector3.new(1.4, h, 1.4), frame * CFrame.new(sx * (w / 2 - 0.5), h / 2, sz * (d / 2 - 0.5)), color, Enum.Material.Metal)
			end
		end
	end
	local ceiling = deco(part(parent, "CeilingLight", Vector3.new(w * 0.5, 0.3, 2), frame * CFrame.new(0, h - 0.4, 0), Color3.fromRGB(255, 245, 220), Enum.Material.Neon))
	light(ceiling, math.max(w, d), 1.2, Color3.fromRGB(255, 240, 220))
end

-- A wedge roof over a box: two wedges, ridge along X.
local function gableRoof(parent: Instance, frame: CFrame, w: number, d: number, h: number, color: Color3)
	local half = d / 2
	part(parent, "Roof", Vector3.new(w, h, half), frame * CFrame.new(0, h / 2, -half / 2), color, Enum.Material.Slate).Shape = Enum.PartType.Wedge
	part(parent, "Roof", Vector3.new(w, h, half), frame * CFrame.new(0, h / 2, half / 2) * CFrame.Angles(0, math.pi, 0), color, Enum.Material.Slate).Shape = Enum.PartType.Wedge
end

-- ── Ground and water ───────────────────────────────────────────────────────

local function buildGround(world: Instance)
	local b = Map.Bounds
	local grass = Color3.fromRGB(78, 80, 58)
	local margin = 700
	local z0, z1 = b.z0 - margin, b.z1 + margin
	local seaX1 = b.x1 + margin
	tiled(world, "Ground", b.x0 - margin, Map.River.x0, z0, z1, -2, 4, grass, Enum.Material.Ground)
	tiled(world, "Ground", Map.River.x1, Map.Sea.x0, z0, z1, -2, 4, grass, Enum.Material.Ground)
	local bottom = Color3.fromRGB(60, 56, 44)
	tiled(world, "RiverBed", Map.River.x0, Map.River.x1, z0, z1, -30, 4, bottom, Enum.Material.Mud)
	tiled(world, "SeaBed", Map.Sea.x0, seaX1, z0, z1, -30, 4, bottom, Enum.Material.Sand)
	-- Embankments.
	local wallColor = Color3.fromRGB(110, 110, 104)
	for _, x in { Map.River.x0 + 1, Map.River.x1 - 1, Map.Sea.x0 + 1 } do
		tiled(world, "Embankment", x - 1, x + 1, z0, z1, -14, 28, wallColor, Enum.Material.Concrete)
	end
	-- Terrain water (players can swim, cars sink), in chunks.
	local terrain = workspace.Terrain
	local depth = Map.WaterLevel + 28
	local wz0, wz1 = b.z0 - 300, b.z1 + 300
	local function water(x0: number, x1: number)
		local chunk = 1000
		local z = wz0
		while z < wz1 do
			local length = math.min(chunk, wz1 - z)
			terrain:FillBlock(CFrame.new((x0 + x1) / 2, -28 + depth / 2, z + length / 2), Vector3.new(x1 - x0, depth, length), Enum.Material.Water)
			z += length
		end
	end
	water(Map.River.x0 + 2, Map.River.x1 - 2)
	water(Map.Sea.x0 + 2, b.x1 + 250)
	-- Hills around the edges hide the end of the world.
	local hills = {
		{ b.x0 - 60, -2500 },
		{ b.x0 - 60, -1400 },
		{ b.x0 - 60, -300 },
		{ b.x0 - 60, 900 },
		{ -1500, b.z1 + 60 },
		{ -500, b.z1 + 60 },
		{ 500, b.z1 + 60 },
		{ -1500, b.z0 - 60 },
		{ -500, b.z0 - 60 },
		{ 900, b.z0 - 60 },
	}
	for _, h in hills do
		local material = if Map.isWinter(h[1], h[2]) then Enum.Material.Snow else Enum.Material.Grass
		terrain:FillBall(Vector3.new(h[1], -40, h[2]), rng:NextNumber(120, 150), material)
	end
end

-- ── Districts ──────────────────────────────────────────────────────────────

local function buildDistrictRoads(parent: Instance, d: Map.District)
	local _, x1, z0, z1 = Map.districtEdges(d)
	for k = d.i0 - 1, d.i1 do
		local x = d.ox + (k + 0.5) * CELL
		local length = z1 - z0 + ROAD
		part(parent, "Road", Vector3.new(ROAD, 0.4, length), CFrame.new(x, ROAD_TOP - 0.2, (z0 + z1) / 2), ASPHALT, Enum.Material.Asphalt)
		deco(part(parent, "Line", Vector3.new(0.6, 0.05, length - ROAD), CFrame.new(x, ROAD_TOP + 0.02, (z0 + z1) / 2), LINE))
	end
	for k = d.j0 - 1, d.j1 do
		local z = d.oz + (k + 0.5) * CELL
		for i = d.i0, d.i1 do
			local cx = d.ox + i * CELL
			part(parent, "Road", Vector3.new(BLOCK, 0.4, ROAD), CFrame.new(cx, ROAD_TOP - 0.2, z), ASPHALT, Enum.Material.Asphalt)
			deco(part(parent, "Line", Vector3.new(BLOCK, 0.05, 0.6), CFrame.new(cx, ROAD_TOP + 0.02, z), LINE))
		end
	end
	-- Lamps at the crossings.
	for kx = d.i0 - 1, d.i1 do
		for kz = d.j0 - 1, d.j1 do
			local x = d.ox + (kx + 0.5) * CELL + ROAD / 2 + 2
			local z = d.oz + (kz + 0.5) * CELL + ROAD / 2 + 2
			if x < x1 and z < z1 and (d.style == "downtown" or (kx + kz) % 2 == 0) then
				lamp(parent, x, z)
			end
		end
	end
end

local function windowStrips(parent: Instance, cx: number, cz: number, w: number, d: number, height: number)
	local floors = math.min(math.floor((height - 4) / 9), 6)
	for f = 1, floors do
		local y = WALK_TOP + f * 9
		for side = 0, 3 do
			local faceWidth = if side % 2 == 0 then w else d
			local faceDepth = if side % 2 == 0 then d else w
			local lit = rng:NextNumber() < 0.25
			deco(part(
				parent,
				"Window",
				Vector3.new(faceWidth - 4, 3, 0.3),
				CFrame.new(cx, y, cz) * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0, faceDepth / 2 + 0.1),
				if lit then Color3.fromRGB(255, 210, 120) else Color3.fromRGB(30, 36, 44),
				if lit then Enum.Material.Neon else Enum.Material.Glass
			))
		end
	end
end

local function tower(parent: Instance, cx: number, cz: number, lot: number, height: number)
	local w = lot - rng:NextNumber(2, 9)
	local d = lot - rng:NextNumber(2, 9)
	local model = Instance.new("Model")
	model.Name = "Building"
	part(model, "Walls", Vector3.new(w, height, d), CFrame.new(cx, WALK_TOP + height / 2, cz), BUILDING_COLORS[rng:NextInteger(1, #BUILDING_COLORS)], BUILDING_MATERIALS[rng:NextInteger(1, #BUILDING_MATERIALS)])
	windowStrips(model, cx, cz, w, d, height)
	if rng:NextNumber() < 0.5 then
		part(model, "RoofBox", Vector3.new(6, 3, 6), CFrame.new(cx + rng:NextNumber(-w / 4, w / 4), WALK_TOP + height + 1.5, cz + rng:NextNumber(-d / 4, d / 4)), Color3.fromRGB(90, 90, 90), Enum.Material.Metal)
	end
	model.Parent = parent
end

local function sidewalk(parent: Instance, cx: number, cz: number, color: Color3?)
	part(parent, "Sidewalk", Vector3.new(BLOCK, WALK_TOP, BLOCK), CFrame.new(cx, WALK_TOP / 2, cz), color or Color3.fromRGB(150, 150, 146), Enum.Material.Concrete)
end

local function downtownBlock(parent: Instance, cx: number, cz: number, centerFactor: number)
	sidewalk(parent, cx, cz)
	local inset = 6
	local lot = (BLOCK - inset * 2) / 2
	for a = 0, 1 do
		for b = 0, 1 do
			local lx = cx - BLOCK / 2 + inset + lot * (a + 0.5)
			local lz = cz - BLOCK / 2 + inset + lot * (b + 0.5)
			local roll = rng:NextNumber()
			if roll < 0.7 then
				tower(parent, lx, lz, lot, rng:NextNumber(16, 34) + 55 * centerFactor * rng:NextNumber())
			elseif roll < 0.85 then
				deco(part(parent, "Grass", Vector3.new(lot - 2, 0.1, lot - 2), CFrame.new(lx, WALK_TOP + 0.05, lz), Color3.fromRGB(70, 88, 52), Enum.Material.Grass))
				for _ = 1, rng:NextInteger(2, 4) do
					tree(parent, lx + rng:NextNumber(-lot / 3, lot / 3), lz + rng:NextNumber(-lot / 3, lot / 3))
				end
			else
				deco(part(parent, "Parking", Vector3.new(lot - 2, 0.1, lot - 2), CFrame.new(lx, WALK_TOP + 0.05, lz), Color3.fromRGB(60, 60, 64), Enum.Material.Asphalt))
				wreck(parent, CFrame.new(lx, WALK_TOP, lz) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
			end
		end
	end
end

local function container(parent: Instance, cframe: CFrame)
	part(parent, "Container", Vector3.new(8, 8.5, 20), cframe, CONTAINER_COLORS[rng:NextInteger(1, #CONTAINER_COLORS)], Enum.Material.CorrodedMetal)
end

local function harborBlock(parent: Instance, cx: number, cz: number)
	sidewalk(parent, cx, cz, Color3.fromRGB(120, 120, 116))
	-- A warehouse on one half, stacked containers on the other.
	local flip = if rng:NextNumber() < 0.5 then -1 else 1
	local w, d, h = BLOCK - 14, BLOCK / 2 - 8, rng:NextNumber(16, 24)
	local wz = cz + flip * (BLOCK / 4)
	part(parent, "Warehouse", Vector3.new(w, h, d), CFrame.new(cx, WALK_TOP + h / 2, wz), Color3.fromRGB(110 + rng:NextInteger(-20, 20), 100, 90), Enum.Material.CorrodedMetal)
	part(parent, "WarehouseRoof", Vector3.new(w + 2, 1.5, d + 2), CFrame.new(cx, WALK_TOP + h + 0.75, wz), Color3.fromRGB(70, 70, 74), Enum.Material.Metal)
	sign(parent, "WAREHOUSE " .. tostring(rng:NextInteger(1, 40)), Vector3.new(24, 4, 0.4), CFrame.new(cx, WALK_TOP + h - 3, wz - flip * (d / 2 + 0.3)) * CFrame.Angles(0, if flip > 0 then 0 else math.pi, 0), Color3.fromRGB(240, 240, 240), Color3.fromRGB(60, 60, 64))
	local sz = cz - flip * (BLOCK / 4)
	for row = -1, 1, 2 do
		for col = -2, 2 do
			if rng:NextNumber() < 0.75 then
				local stack = rng:NextInteger(1, 3)
				for level = 0, stack - 1 do
					container(parent, CFrame.new(cx + col * 9.5, WALK_TOP + 4.25 + level * 8.6, sz + row * 11) * CFrame.Angles(0, math.rad(rng:NextNumber(-2, 2)), 0))
				end
			end
		end
	end
end

local HOUSE_COLORS = {
	Color3.fromRGB(200, 190, 170),
	Color3.fromRGB(170, 190, 200),
	Color3.fromRGB(210, 180, 150),
	Color3.fromRGB(190, 200, 170),
	Color3.fromRGB(220, 210, 200),
}

local function house(parent: Instance, frame: CFrame)
	local w, d, h = rng:NextNumber(20, 26), rng:NextNumber(16, 20), rng:NextNumber(11, 14)
	local color = HOUSE_COLORS[rng:NextInteger(1, #HOUSE_COLORS)]
	part(parent, "House", Vector3.new(w, h, d), frame * CFrame.new(0, h / 2, 0), color, Enum.Material.WoodPlanks)
	gableRoof(parent, frame * CFrame.new(0, h, 0), w + 2, d + 2, 6, Color3.fromRGB(100 + rng:NextInteger(-30, 30), 60, 50))
	part(parent, "Door", Vector3.new(4, 7, 0.4), frame * CFrame.new(0, 3.5, -d / 2 - 0.2), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	for _, x in { -w / 3, w / 3 } do
		local lit = rng:NextNumber() < 0.3
		deco(part(parent, "Window", Vector3.new(4, 3.5, 0.3), frame * CFrame.new(x, h * 0.55, -d / 2 - 0.15), if lit then Color3.fromRGB(255, 210, 120) else Color3.fromRGB(40, 50, 60), if lit then Enum.Material.Neon else Enum.Material.Glass))
	end
end

local function suburbsBlock(parent: Instance, cx: number, cz: number)
	sidewalk(parent, cx, cz)
	local inset = 5
	local lot = (BLOCK - inset * 2) / 2
	for a = 0, 1 do
		for b = 0, 1 do
			local lx = cx - BLOCK / 2 + inset + lot * (a + 0.5)
			local lz = cz - BLOCK / 2 + inset + lot * (b + 0.5)
			deco(part(parent, "Lawn", Vector3.new(lot - 2, 0.1, lot - 2), CFrame.new(lx, WALK_TOP + 0.05, lz), Color3.fromRGB(76, 100, 54), Enum.Material.Grass))
			-- The house faces the nearer road (north or south).
			local facing = if b == 0 then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1)
			local origin = Vector3.new(lx, WALK_TOP, lz - facing.Z * 4)
			if rng:NextNumber() < 0.85 then
				house(parent, CFrame.lookAt(origin, origin + facing))
			else
				wreck(parent, CFrame.new(lx, WALK_TOP, lz) * CFrame.Angles(0, rng:NextNumber(0, 6), 0))
			end
			if rng:NextNumber() < 0.6 then
				tree(parent, lx + rng:NextNumber(-lot / 3, lot / 3), lz + facing.Z * (lot / 2 - 5))
			end
			-- A low fence at the back of the lot.
			deco(part(parent, "Fence", Vector3.new(lot - 4, 2.5, 0.4), CFrame.new(lx, WALK_TOP + 1.25, lz - facing.Z * (lot / 2 - 1.5)), Color3.fromRGB(230, 230, 225), Enum.Material.WoodPlanks)).CanCollide = true
		end
	end
end

-- ── The depot and the shops ────────────────────────────────────────────────

local function buildDepot(parent: Instance)
	local depot = folder(parent, "Depot")
	sidewalk(depot, 0, 0, Color3.fromRGB(120, 120, 116))
	local wallColor = Color3.fromRGB(170, 120, 60)
	local depth, width, height = 40, 80, 22
	local backZ = -BLOCK / 2 + 6
	part(depot, "Back", Vector3.new(width, height, 2), CFrame.new(0, WALK_TOP + height / 2, backZ + 1), wallColor, Enum.Material.Metal)
	part(depot, "Left", Vector3.new(2, height, depth), CFrame.new(-width / 2 + 1, WALK_TOP + height / 2, backZ + depth / 2), wallColor, Enum.Material.Metal)
	part(depot, "Right", Vector3.new(2, height, depth), CFrame.new(width / 2 - 1, WALK_TOP + height / 2, backZ + depth / 2), wallColor, Enum.Material.Metal)
	part(depot, "Roof", Vector3.new(width, 2, depth), CFrame.new(0, WALK_TOP + height + 1, backZ + depth / 2), Color3.fromRGB(90, 70, 50), Enum.Material.Metal)
	sign(depot, "ZOMBIE DELIVERY CO.", Vector3.new(60, 8, 1), CFrame.new(0, WALK_TOP + height + 6, backZ + depth - 2) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(255, 190, 60))
	for n = 1, 10 do
		local s = rng:NextNumber(3, 5)
		part(depot, "Crate", Vector3.new(s, s, s), CFrame.new(rng:NextNumber(-34, 34), WALK_TOP + s / 2, backZ + rng:NextNumber(4, 14)) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
		if n > 7 then
			part(depot, "Crate", Vector3.new(s * 0.8, s * 0.8, s * 0.8), CFrame.new(rng:NextNumber(-34, 34), WALK_TOP + s * 1.4, backZ + rng:NextNumber(4, 14)), Color3.fromRGB(140, 100, 64), Enum.Material.WoodPlanks)
		end
	end
	-- The job board and the garage terminal.
	local board = part(depot, "JobBoard", Vector3.new(14, 8, 1), CFrame.new(-18, WALK_TOP + 5, backZ + 24) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(110, 80, 50), Enum.Material.Wood)
	sign(depot, "JOBS", Vector3.new(10, 3, 0.3), board.CFrame * CFrame.new(0, 2, -0.7), Color3.fromRGB(255, 220, 80))
	prompt(board, "jobs", "Job Board", "Dispatcher")
	local terminal = part(depot, "GarageTerminal", Vector3.new(6, 7, 3), CFrame.new(18, WALK_TOP + 3.5, backZ + 24), Color3.fromRGB(60, 70, 80), Enum.Material.Metal)
	sign(depot, "GARAGE", Vector3.new(6, 2, 0.3), terminal.CFrame * CFrame.new(0, 2.5, 1.6) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(120, 200, 255))
	prompt(terminal, "depot", "Switch car", "Depot Garage")

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

local function shopFrame(cx: number, cz: number, facing: Vector3, back: number): CFrame
	local origin = Vector3.new(cx, WALK_TOP, cz) - facing * back
	return CFrame.lookAt(origin, origin + facing)
end

local function counter(parent: Instance, frame: CFrame, d: number, shop: string, name: string): Part
	local desk = part(parent, "Counter", Vector3.new(16, 4, 3), frame * CFrame.new(0, 2, d / 2 - 8), Color3.fromRGB(120, 90, 60), Enum.Material.Wood)
	prompt(desk, shop, "Shop", name)
	return desk
end

local function buildDealer(parent: Instance)
	local shop = folder(parent, "DeadEndMotors")
	local cx, cz = Map.Shops.dealer.x, Map.Shops.dealer.z
	sidewalk(shop, cx, cz, Color3.fromRGB(70, 70, 74))
	local facing = Vector3.new(-1, 0, 0)
	local w, d, h = 84, 52, 18
	local frame = shopFrame(cx, cz, facing, 22)
	building(shop, frame, w, d, h, Color3.fromRGB(40, 44, 52), Enum.Material.Metal, 16, 12, true)
	sign(shop, "DEAD END MOTORS", Vector3.new(60, 7, 0.5), frame * CFrame.new(0, h + 4.5, -d / 2), Color3.fromRGB(255, 80, 60))
	counter(shop, frame, d, "dealer", "Dead End Motors")
	-- Display spots: three inside, four on the lot in front.
	for _, x in { -26, 0, 26 } do
		local pad = cylinder(shop, "Turntable", 0.3, 18, frame * CFrame.new(x, 0.45, 4) * UPRIGHT, Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		pad.CanCollide = false
		table.insert(World.DealerSlots, frame * CFrame.new(x, 0.6, 4))
	end
	for _, z in { -42, -15, 15, 42 } do
		local spot = CFrame.lookAt(Vector3.new(cx - 40, WALK_TOP, z), Vector3.new(cx - 80, WALK_TOP, z))
		table.insert(World.DealerSlots, spot)
	end
	-- Flags on the lot.
	for _, z in { -52, 52 } do
		part(shop, "FlagPole", Vector3.new(0.5, 16, 0.5), CFrame.new(cx - 52, WALK_TOP + 8, z), Color3.fromRGB(200, 200, 200), Enum.Material.Metal)
		deco(part(shop, "Flag", Vector3.new(0.2, 4, 7), CFrame.new(cx - 52, WALK_TOP + 13.5, z + 3.6), Color3.fromRGB(255, 80, 60), Enum.Material.Fabric))
	end
end

local function buildGuns(parent: Instance)
	local shop = folder(parent, "LeadAndCo")
	local cx, cz = Map.Shops.guns.x, Map.Shops.guns.z
	sidewalk(shop, cx, cz)
	local facing = Vector3.new(1, 0, 0)
	local w, d, h = 60, 46, 16
	local frame = shopFrame(cx, cz, facing, 18)
	building(shop, frame, w, d, h, Color3.fromRGB(110, 70, 50), Enum.Material.Brick, 12, 10)
	sign(shop, "LEAD & CO.  GUNS", Vector3.new(44, 6, 0.5), frame * CFrame.new(0, h + 4, -d / 2), Color3.fromRGB(255, 200, 80))
	counter(shop, frame, d, "guns", "Lead & Co.")
	-- Guns on the wall.
	for n = -2, 2 do
		part(shop, "Rack", Vector3.new(5, 1, 0.4), frame * CFrame.new(n * 8, 8, d / 2 - 1.3), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	end
end

local function buildMechanic(parent: Instance)
	local shop = folder(parent, "WrenchGarage")
	local cx, cz = Map.Shops.mechanic.x, Map.Shops.mechanic.z
	sidewalk(shop, cx, cz, Color3.fromRGB(100, 100, 100))
	local facing = Vector3.new(0, 0, -1)
	local w, d, h = 70, 60, 20
	local frame = shopFrame(cx, cz, facing, 12)
	building(shop, frame, w, d, h, Color3.fromRGB(70, 90, 120), Enum.Material.Metal, 34, 15)
	sign(shop, "WRENCH GARAGE  TUNING · PAINT", Vector3.new(56, 6, 0.5), frame * CFrame.new(0, h + 4, -d / 2), Color3.fromRGB(120, 200, 255))
	counter(shop, frame, d, "mechanic", "Wrench Garage")
	part(shop, "Lift", Vector3.new(10, 0.6, 18), frame * CFrame.new(-18, 0.6, 2), Color3.fromRGB(200, 170, 40), Enum.Material.DiamondPlate)
	for n = 0, 3 do
		cylinder(shop, "Tire", 1.4, 3.2, frame * CFrame.new(28, 1.6 + n * 1.5, 18) * UPRIGHT, Color3.fromRGB(25, 25, 25), Enum.Material.Rubber)
	end
	table.insert(World.RepairSpots, (frame * CFrame.new(0, 0, 0)).Position)
end

local function buildSupplies(parent: Instance)
	local shop = folder(parent, "LastStopSupplies")
	local cx, cz = Map.Shops.supplies.x, Map.Shops.supplies.z
	sidewalk(shop, cx, cz)
	local facing = Vector3.new(0, 0, 1)
	local w, d, h = 64, 44, 14
	local frame = shopFrame(cx, cz, facing, 18)
	building(shop, frame, w, d, h, Color3.fromRGB(90, 110, 80), Enum.Material.Concrete, 12, 10)
	sign(shop, "LAST STOP SUPPLIES", Vector3.new(48, 6, 0.5), frame * CFrame.new(0, h + 4, -d / 2), Color3.fromRGB(140, 255, 120))
	counter(shop, frame, d, "supplies", "Last Stop Supplies")
	for row = -1, 1, 2 do
		part(shop, "Shelf", Vector3.new(30, 6, 2), frame * CFrame.new(0, 3, row * 8 - 2), Color3.fromRGB(150, 140, 120), Enum.Material.Wood)
	end
end

-- The safe zone border: a green line on the ground and signs.
local function buildSafeZone(parent: Instance)
	local zone = folder(parent, "SafeZone")
	local half = Config.City.SafeHalf
	local green = Color3.fromRGB(80, 255, 140)
	for _, info in { { Vector3.new(half * 2, 0.06, 1.2), Vector3.new(0, 0, half) }, { Vector3.new(half * 2, 0.06, 1.2), Vector3.new(0, 0, -half) }, { Vector3.new(1.2, 0.06, half * 2), Vector3.new(half, 0, 0) }, { Vector3.new(1.2, 0.06, half * 2), Vector3.new(-half, 0, 0) } } do
		local strip = deco(part(zone, "Border", info[1], CFrame.new(info[2] + Vector3.new(0, WALK_TOP + 0.05, 0)), green, Enum.Material.Neon))
		strip.Transparency = 0.3
	end
	for _, dir in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local at = dir * (half + 3) + Vector3.new(dir.Z, 0, dir.X) * (CELL / 2 + ROAD / 2 + 4)
		part(zone, "SignPole", Vector3.new(0.5, 10, 0.5), CFrame.new(at + Vector3.new(0, WALK_TOP + 5, 0)), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
		sign(zone, "SAFE ZONE", Vector3.new(10, 3, 0.3), CFrame.lookAt(at + Vector3.new(0, WALK_TOP + 10, 0), at + Vector3.new(0, WALK_TOP + 10, 0) + dir), green)
	end
end

-- ── The employers ──────────────────────────────────────────────────────────

local buildSchool: (Instance, number, number) -> ()
local buildFrosty: (Instance, number, number) -> ()
local buildMovers: (Instance, number, number) -> ()

-- A notice board with a "Work here" prompt (server/Shops.luau opens the employer's window).
local function employerBoard(parent: Instance, employer: string, facing: Vector3)
	local spot = Map.EmployerSpots[employer]
	if not spot then
		return
	end
	local base = Vector3.new(spot.x, WALK_TOP, spot.z)
	local frame = CFrame.lookAt(base, base + facing)
	part(parent, "BoardPost", Vector3.new(0.6, 6, 0.6), frame * CFrame.new(-3, 3, 0), Color3.fromRGB(80, 60, 40), Enum.Material.Wood)
	part(parent, "BoardPost", Vector3.new(0.6, 6, 0.6), frame * CFrame.new(3, 3, 0), Color3.fromRGB(80, 60, 40), Enum.Material.Wood)
	local board = part(parent, "WorkBoard", Vector3.new(7, 4, 0.4), frame * CFrame.new(0, 5, 0), Color3.fromRGB(240, 200, 60), Enum.Material.Wood)
	sign(parent, "WORK HERE", Vector3.new(6, 1.6, 0.1), frame * CFrame.new(0, 5.6, -0.3), Color3.fromRGB(30, 30, 30), Color3.fromRGB(240, 200, 60))
	local name = employer
	for _, def in Config.Employers do
		if def.id == employer then
			name = def.name
		end
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "EmployerPrompt"
	p.ActionText = "Work here"
	p.ObjectText = name
	p.HoldDuration = 0
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p:SetAttribute("Employer", employer)
	p.Parent = board
	table.insert(World.EmployerPrompts, { prompt = p, employer = employer })
end

function buildSchool(parent: Instance, cx: number, cz: number)
	local school = folder(parent, "SunnyHillSchool")
	sidewalk(school, cx, cz)
	local facing = Vector3.new(0, 0, -1)
	local frame = shopFrame(cx, cz, facing, 10)
	building(school, frame, 80, 50, 18, Color3.fromRGB(200, 120, 80), Enum.Material.Brick, 12, 10)
	sign(school, "SUNNY HILL SCHOOL", Vector3.new(50, 6, 0.5), frame * CFrame.new(0, 22.5, -25), Color3.fromRGB(255, 230, 120))
	-- The playground behind.
	for n = -1, 1 do
		local x = cx + n * 14
		part(school, "SwingFrame", Vector3.new(0.6, 9, 0.6), CFrame.new(x - 4, WALK_TOP + 4.5, cz + 44), Color3.fromRGB(200, 60, 60), Enum.Material.Metal)
		part(school, "SwingFrame", Vector3.new(0.6, 9, 0.6), CFrame.new(x + 4, WALK_TOP + 4.5, cz + 44), Color3.fromRGB(200, 60, 60), Enum.Material.Metal)
		part(school, "SwingTop", Vector3.new(9, 0.6, 0.6), CFrame.new(x, WALK_TOP + 9, cz + 44), Color3.fromRGB(200, 60, 60), Enum.Material.Metal)
	end
	part(school, "FlagPole", Vector3.new(0.5, 22, 0.5), CFrame.new(cx + 30, WALK_TOP + 11, cz - 34), Color3.fromRGB(220, 220, 220), Enum.Material.Metal)
	employerBoard(school, "school", facing)
end

function buildFrosty(parent: Instance, cx: number, cz: number)
	local frosty = folder(parent, "FrostysIceCream")
	sidewalk(frosty, cx, cz, Color3.fromRGB(150, 150, 146))
	local facing = Vector3.new(-1, 0, 0)
	local frame = shopFrame(cx, cz, facing, 12)
	building(frosty, frame, 80, 50, 18, Color3.fromRGB(250, 230, 240), Enum.Material.SmoothPlastic, 24, 14)
	sign(frosty, "FROSTY'S ICE CREAM", Vector3.new(50, 6, 0.5), frame * CFrame.new(0, 22.5, -25), Color3.fromRGB(255, 90, 170), Color3.fromRGB(250, 250, 255))
	-- A giant cone on the roof.
	local roof = (frame * CFrame.new(0, 19, 8)).Position
	local cone = part(frosty, "Cone", Vector3.new(14, 6, 6), CFrame.new(roof + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 170, 110), Enum.Material.SmoothPlastic)
	cone.Shape = Enum.PartType.Cylinder
	local scoop = part(frosty, "Scoop", Vector3.new(9, 9, 9), CFrame.new(roof + Vector3.new(0, 16, 0)), Color3.fromRGB(255, 150, 200), Enum.Material.SmoothPlastic)
	scoop.Shape = Enum.PartType.Ball
	employerBoard(frosty, "icecream", facing)
end

function buildMovers(parent: Instance, cx: number, cz: number)
	local movers = folder(parent, "BigMoveMovers")
	sidewalk(movers, cx, cz, Color3.fromRGB(130, 130, 126))
	local facing = Vector3.new(1, 0, 0)
	local frame = shopFrame(cx, cz, facing, 12)
	building(movers, frame, 80, 50, 20, Color3.fromRGB(230, 120, 40), Enum.Material.Metal, 28, 15)
	sign(movers, "BIG MOVE MOVERS", Vector3.new(50, 6, 0.5), frame * CFrame.new(0, 24.5, -25), Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 90, 30))
	for _ = 1, 8 do
		local size = rng:NextNumber(3, 5)
		part(movers, "Box", Vector3.new(size, size, size), frame * CFrame.new(rng:NextNumber(-30, 30), size / 2 + 0.3, rng:NextNumber(0, 18)), Color3.fromRGB(190, 150, 100), Enum.Material.Cardboard)
	end
	employerBoard(movers, "movers", facing)
end

-- A big icon with the name over every shop, employer and far place, seen from afar (the way to find things).
local function buildLandmarkTags(parent: Instance)
	local tags = folder(parent, "LandmarkTags")
	local colors = { shop = Color3.fromRGB(120, 230, 110), employer = Color3.fromRGB(255, 200, 60), place = Color3.fromRGB(230, 160, 255) }
	for _, landmark in Map.Landmarks do
		local anchor = part(tags, "Tag", Vector3.new(0.2, 0.2, 0.2), CFrame.new(landmark.x, 34, landmark.z), Color3.new(0, 0, 0))
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(220, 70)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 700
		gui.LightInfluence = 0
		gui.Parent = anchor
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(1, 0, 0.6, 0)
		icon.BackgroundTransparency = 1
		icon.Text = landmark.icon
		icon.TextScaled = true
		icon.Parent = gui
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0.4, 0)
		label.Position = UDim2.fromScale(0, 0.6)
		label.BackgroundTransparency = 1
		label.Text = landmark.name
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = colors[landmark.kind] or Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
	end
end

local function buildDistrict(parent: Instance, d: Map.District)
	local district = folder(parent, d.name)
	buildDistrictRoads(district, d)
	local span = math.max(d.i1 - d.i0, d.j1 - d.j0) / 2 + 1
	for i = d.i0, d.i1 do
		for j = d.j0, d.j1 do
			local cx, cz = d.ox + i * CELL, d.oz + j * CELL
			local special = Map.special(d.id, i, j)
			if special == "school" then
				buildSchool(district, cx, cz)
				continue
			elseif special == "frosty" then
				buildFrosty(district, cx, cz)
				continue
			elseif special == "movers" then
				buildMovers(district, cx, cz)
				continue
			elseif special then
				continue
			end
			if d.style == "downtown" then
				downtownBlock(district, cx, cz, 1 - math.max(math.abs(i), math.abs(j)) / span)
			elseif d.style == "harbor" then
				harborBlock(district, cx, cz)
			else
				suburbsBlock(district, cx, cz)
			end
		end
	end
	if d.id == "downtown" then
		buildDepot(district)
		buildDealer(district)
		buildGuns(district)
		buildMechanic(district)
		buildSupplies(district)
		buildSafeZone(district)
	end
end

-- ── Connecting roads: bridges, highways ────────────────────────────────────

local function segmentFrame(s: Map.Segment, y: number): (CFrame, number)
	local a = Vector3.new(s.ax, y, s.az)
	local b = Vector3.new(s.bx, y, s.bz)
	return CFrame.lookAt((a + b) / 2, b), (b - a).Magnitude
end

local function buildBridge(parent: Instance, s: Map.Segment)
	local bridge = folder(parent, s.name or "Bridge")
	local frame, length = segmentFrame(s, ROAD_TOP)
	local rusty = s.name == "Rust Bridge"
	local steel = if rusty then Color3.fromRGB(150, 70, 40) else Color3.fromRGB(110, 100, 90)
	part(bridge, "Road", Vector3.new(s.width, 0.4, length), frame * CFrame.new(0, -0.2, 0), ASPHALT, Enum.Material.Asphalt)
	deco(part(bridge, "Line", Vector3.new(0.6, 0.05, length), frame * CFrame.new(0, 0.02, 0), LINE))
	part(bridge, "Deck", Vector3.new(s.width + 8, 4, length), frame * CFrame.new(0, -2.4, 0), Color3.fromRGB(120, 120, 116), Enum.Material.Concrete)
	for _, side in { -1, 1 } do
		part(bridge, "Railing", Vector3.new(1.2, 3, length), frame * CFrame.new(side * (s.width / 2 + 2.5), 1.5, 0), steel, Enum.Material.Metal)
	end
	-- Piers in the water.
	local x0 = math.min(s.ax, s.bx)
	for x = Map.River.x0 + 30, Map.River.x1 - 20, 50 do
		local t = (x - x0) / length
		for _, side in { -1, 1 } do
			cylinder(bridge, "Pier", 26, 5, frame * CFrame.new(side * (s.width / 2 - 2), -16, (t - 0.5) * length) * UPRIGHT, Color3.fromRGB(100, 100, 96), Enum.Material.Concrete)
		end
	end
	if not rusty then
		return
	end
	-- Rust Bridge: two pylons with cables.
	for _, x in { Map.River.x0 - 8, Map.River.x1 + 8 } do
		local t = (x - x0) / length - 0.5
		for _, side in { -1, 1 } do
			part(bridge, "Pylon", Vector3.new(3, 44, 3), frame * CFrame.new(side * (s.width / 2 + 5), 22, t * length), steel, Enum.Material.Metal)
		end
		part(bridge, "PylonBeam", Vector3.new(s.width + 14, 3, 3), frame * CFrame.new(0, 43, t * length), steel, Enum.Material.Metal)
		local top = deco(part(bridge, "Beacon", Vector3.new(1.5, 1.5, 1.5), frame * CFrame.new(0, 45.5, t * length), Color3.fromRGB(255, 40, 40), Enum.Material.Neon))
		light(top, 30, 1, Color3.fromRGB(255, 60, 60))
		for _, side in { -1, 1 } do
			for _, reach in { 20, 40, 60 } do
				for _, dir in { -1, 1 } do
					local from = (frame * CFrame.new(side * (s.width / 2 + 5), 42, t * length)).Position
					local to = (frame * CFrame.new(side * (s.width / 2 + 2.5), 3, t * length + dir * reach)).Position
					deco(part(bridge, "Cable", Vector3.new(0.3, 0.3, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), Color3.fromRGB(60, 60, 60), Enum.Material.Metal))
				end
			end
		end
	end
	sign(bridge, "RUST BRIDGE", Vector3.new(20, 3, 0.4), frame * CFrame.new(0, 38, -(length / 2 - 75)) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(255, 200, 120))
end

local function buildConnectors(parent: Instance)
	local roads = folder(parent, "Highways")
	local connectors = Map.Connectors
	for _, s in connectors do
		if s.kind == "bridge" then
			buildBridge(parent, s)
			continue
		elseif s.kind == "ice" then
			-- A road of packed ice over the frozen lake, marked with flag poles.
			local frame, length = segmentFrame(s, ROAD_TOP)
			local ice = part(roads, "IceRoad", Vector3.new(s.width, 0.4, length), frame * CFrame.new(0, -0.2, 0), Color3.fromRGB(200, 228, 240), Enum.Material.Ice)
			ice.Reflectance = 0.15
			for z = -length / 2 + 10, length / 2 - 10, 40 do
				for _, side in { -1, 1 } do
					local pole = frame * CFrame.new(side * (s.width / 2 + 1.5), 3, z)
					part(roads, "IcePole", Vector3.new(0.4, 6, 0.4), pole, Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
					deco(part(roads, "IceFlag", Vector3.new(0.1, 1.2, 1.8), pole * CFrame.new(0, 2.4, 0.9), Color3.fromRGB(230, 50, 40), Enum.Material.Fabric))
				end
			end
			continue
		end
		local frame, length = segmentFrame(s, ROAD_TOP)
		part(roads, "Road", Vector3.new(s.width, 0.4, length), frame * CFrame.new(0, -0.2, 0), ASPHALT, Enum.Material.Asphalt)
		deco(part(roads, "Line", Vector3.new(0.6, 0.05, length), frame * CFrame.new(0, 0.02, 0), LINE))
		if s.kind == "highway" then
			for _, side in { -1, 1 } do
				deco(part(roads, "EdgeLine", Vector3.new(0.5, 0.05, length), frame * CFrame.new(side * (s.width / 2 - 1.5), 0.02, 0), Color3.fromRGB(220, 220, 220)))
			end
			-- Lamps along it.
			local count = math.floor(length / 130)
			for n = 1, count do
				local side = if n % 2 == 0 then 1 else -1
				local p = (frame * CFrame.new(side * (s.width / 2 + 4), 0, (n / (count + 1) - 0.5) * length)).Position
				local tunnel = math.abs(p.X - Map.Mountain.x) < 60 and p.Z > Map.Mountain.tunnelZ0 - 20 and p.Z < Map.Mountain.tunnelZ1 + 20
				if not tunnel then
					lamp(roads, p.X, p.Z, ROAD_TOP)
				end
			end
		end
	end
	-- Fill the corners where two connector segments meet.
	for n, a in connectors do
		for m = n + 1, #connectors do
			local b = connectors[m]
			local plain = a.kind ~= "bridge" and b.kind ~= "bridge" and a.kind ~= "ice" and b.kind ~= "ice"
			if plain and a.bx == b.ax and a.bz == b.az then
				cylinder(roads, "Joint", 0.4, a.width, CFrame.new(a.bx, ROAD_TOP - 0.25, a.bz) * UPRIGHT, ASPHALT, Enum.Material.Asphalt)
			end
		end
	end
end

-- ── The mountain and the tunnel ────────────────────────────────────────────

local function buildMountain(parent: Instance)
	local m = Map.Mountain
	local terrain = workspace.Terrain
	terrain:FillBall(Vector3.new(m.x, -60, m.z), m.radius, Enum.Material.Rock)
	terrain:FillBall(Vector3.new(m.x - 150, -80, m.z + 150), 180, Enum.Material.Rock)
	terrain:FillBall(Vector3.new(m.x + 160, -80, m.z - 150), 190, Enum.Material.Rock)
	terrain:FillBall(Vector3.new(m.x - 60, 60, m.z + 80), 90, Enum.Material.Grass)
	terrain:FillBall(Vector3.new(m.x, 175, m.z), 55, Enum.Material.Snow)
	-- Carve the tunnel.
	local width = Map.HighwayWidth + 8
	local length = m.tunnelZ1 - m.tunnelZ0 + 160
	terrain:FillBlock(CFrame.new(m.x, 14, (m.tunnelZ0 + m.tunnelZ1) / 2), Vector3.new(width, 28, length), Enum.Material.Air)

	local tunnel = folder(parent, "Tunnel")
	local tunnelLength = m.tunnelZ1 - m.tunnelZ0
	local center = (m.tunnelZ0 + m.tunnelZ1) / 2
	local concrete = Color3.fromRGB(130, 128, 120)
	for _, side in { -1, 1 } do
		part(tunnel, "Wall", Vector3.new(2, 26, tunnelLength), CFrame.new(m.x + side * (width / 2 - 1), 13, center), concrete, Enum.Material.Concrete)
	end
	part(tunnel, "Ceiling", Vector3.new(width, 2, tunnelLength), CFrame.new(m.x, 25, center), concrete, Enum.Material.Concrete)
	for z = m.tunnelZ0 + 20, m.tunnelZ1 - 20, 40 do
		local strip = deco(part(tunnel, "TunnelLight", Vector3.new(1, 0.4, 8), CFrame.new(m.x, 23.8, z), Color3.fromRGB(255, 200, 120), Enum.Material.Neon))
		light(strip, 36, 1.6, Color3.fromRGB(255, 200, 140))
	end
	-- Portals.
	for _, z in { m.tunnelZ0, m.tunnelZ1 } do
		local out = if z == m.tunnelZ1 then 1 else -1
		for _, side in { -1, 1 } do
			part(tunnel, "PortalPillar", Vector3.new(5, 30, 5), CFrame.new(m.x + side * (width / 2 + 1.5), 15, z + out * 2), concrete, Enum.Material.Concrete)
		end
		part(tunnel, "PortalBeam", Vector3.new(width + 8, 6, 5), CFrame.new(m.x, 29, z + out * 2), concrete, Enum.Material.Concrete)
		sign(tunnel, "MOUNT ROT TUNNEL", Vector3.new(30, 4, 0.4), CFrame.lookAt(Vector3.new(m.x, 29, z + out * 4.8), Vector3.new(m.x, 29, z + out * 10)), Color3.fromRGB(255, 220, 120))
	end
end

-- ── The far places ─────────────────────────────────────────────────────────

local function yardFloor(parent: Instance, yard: Map.Area, color: Color3, material: Enum.Material)
	part(parent, "Yard", Vector3.new(yard.x1 - yard.x0, 0.4, yard.z1 - yard.z0), CFrame.new((yard.x0 + yard.x1) / 2, ROAD_TOP - 0.2, (yard.z0 + yard.z1) / 2), color, material)
end

local function yardOf(id: string): Map.Area
	for _, yard in Map.Yards do
		if yard.id == id then
			return yard
		end
	end
	error("no yard " .. id)
end

local function placeSign(parent: Instance, text: string, x: number, z: number, facing: Vector3, color: Color3)
	part(parent, "SignPole", Vector3.new(0.6, 14, 0.6), CFrame.new(x - 7, 7, z), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	part(parent, "SignPole", Vector3.new(0.6, 14, 0.6), CFrame.new(x + 7, 7, z), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	sign(parent, text, Vector3.new(18, 5, 0.4), CFrame.lookAt(Vector3.new(x, 13, z), Vector3.new(x, 13, z) + facing), color)
end

local function watchtower(parent: Instance, x: number, z: number)
	local wood = Color3.fromRGB(100, 80, 60)
	for _, dx in { -3, 3 } do
		for _, dz in { -3, 3 } do
			part(parent, "Leg", Vector3.new(1, 20, 1), CFrame.new(x + dx, ROAD_TOP + 10, z + dz), wood, Enum.Material.Wood)
		end
	end
	part(parent, "Platform", Vector3.new(9, 1, 9), CFrame.new(x, ROAD_TOP + 20, z), wood, Enum.Material.WoodPlanks)
	part(parent, "TowerRoof", Vector3.new(10, 1, 10), CFrame.new(x, ROAD_TOP + 27, z), Color3.fromRGB(70, 80, 60), Enum.Material.Metal)
	local lamp_ = deco(part(parent, "Searchlight", Vector3.new(1.5, 1.5, 1.5), CFrame.new(x, ROAD_TOP + 22, z), Color3.fromRGB(255, 250, 220), Enum.Material.Neon))
	light(lamp_, 50, 2, Color3.fromRGB(255, 250, 230))
end

local function buildBase(parent: Instance)
	local base = folder(parent, "MilitaryBase")
	local yard = yardOf("base")
	yardFloor(base, yard, Color3.fromRGB(80, 80, 74), Enum.Material.Asphalt)
	local wall = Color3.fromRGB(120, 118, 100)
	local w, d = yard.x1 - yard.x0, yard.z1 - yard.z0
	local cx, cz = (yard.x0 + yard.x1) / 2, (yard.z0 + yard.z1) / 2
	part(base, "Wall", Vector3.new(w, 12, 3), CFrame.new(cx, 6, yard.z0), wall, Enum.Material.Concrete)
	part(base, "Wall", Vector3.new(3, 12, d), CFrame.new(yard.x0, 6, cz), wall, Enum.Material.Concrete)
	part(base, "Wall", Vector3.new(3, 12, d), CFrame.new(yard.x1, 6, cz), wall, Enum.Material.Concrete)
	local gate = 60
	local piece = (w - gate) / 2
	part(base, "Wall", Vector3.new(piece, 12, 3), CFrame.new(yard.x0 + piece / 2, 6, yard.z1), wall, Enum.Material.Concrete)
	part(base, "Wall", Vector3.new(piece, 12, 3), CFrame.new(yard.x1 - piece / 2, 6, yard.z1), wall, Enum.Material.Concrete)
	placeSign(base, "MILITARY BASE · KEEP OUT", cx, yard.z1 + 14, Vector3.new(0, 0, 1), Color3.fromRGB(255, 80, 60))
	employerBoard(base, "army", Vector3.new(0, 0, 1))
	for _, corner in { { yard.x0 + 12, yard.z0 + 12 }, { yard.x1 - 12, yard.z0 + 12 }, { yard.x0 + 12, yard.z1 - 12 }, { yard.x1 - 12, yard.z1 - 12 } } do
		watchtower(base, corner[1], corner[2])
	end
	-- Hangar, tents, helipad, sandbags, trucks.
	part(base, "Hangar", Vector3.new(90, 28, 60), CFrame.new(cx - 140, ROAD_TOP + 14, yard.z0 + 60), Color3.fromRGB(90, 100, 80), Enum.Material.CorrodedMetal)
	cylinder(base, "HangarRoof", 90, 60, CFrame.new(cx - 140, ROAD_TOP + 28, yard.z0 + 60), Color3.fromRGB(80, 90, 70), Enum.Material.CorrodedMetal).Size = Vector3.new(90, 30, 60)
	for n = 0, 5 do
		local tx, tz = cx + 60 + (n % 3) * 30, yard.z0 + 50 + math.floor(n / 3) * 30
		local tent = CFrame.new(tx, ROAD_TOP, tz)
		gableRoof(base, tent, 14, 18, 8, Color3.fromRGB(80, 96, 60))
	end
	local pad = cylinder(base, "Helipad", 0.2, 40, CFrame.new(cx + 120, ROAD_TOP + 0.1, cz + 60) * UPRIGHT, Color3.fromRGB(60, 60, 60), Enum.Material.Concrete)
	pad.CanCollide = false
	deco(part(base, "H", Vector3.new(2, 0.05, 14), CFrame.new(cx + 116, ROAD_TOP + 0.22, cz + 60), Color3.fromRGB(240, 240, 240)))
	deco(part(base, "H", Vector3.new(2, 0.05, 14), CFrame.new(cx + 124, ROAD_TOP + 0.22, cz + 60), Color3.fromRGB(240, 240, 240)))
	deco(part(base, "H", Vector3.new(8, 0.05, 2), CFrame.new(cx + 120, ROAD_TOP + 0.22, cz + 60), Color3.fromRGB(240, 240, 240)))
	for n = 1, 10 do
		part(base, "Sandbags", Vector3.new(10, 3, 3), CFrame.new(cx + rng:NextNumber(-180, 180), ROAD_TOP + 1.5, cz + rng:NextNumber(-120, 160)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color3.fromRGB(170, 150, 110), Enum.Material.Fabric)
		if n <= 5 then
			wreck(base, CFrame.new(cx + rng:NextNumber(-180, 180), ROAD_TOP, cz + rng:NextNumber(-100, 160)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(70, 84, 56))
		end
	end
end

local function buildRadio(parent: Instance)
	local radio = folder(parent, "RadioStation")
	local yard = yardOf("radio")
	yardFloor(radio, yard, Color3.fromRGB(90, 90, 86), Enum.Material.Concrete)
	local cx, cz = (yard.x0 + yard.x1) / 2, (yard.z0 + yard.z1) / 2
	part(radio, "Station", Vector3.new(30, 12, 20), CFrame.new(cx - 50, ROAD_TOP + 6, cz - 60), Color3.fromRGB(150, 150, 140), Enum.Material.Concrete)
	-- The lattice tower.
	local tx, tz = cx + 40, cz - 50
	local height = 170
	local steel = Color3.fromRGB(190, 60, 50)
	for _, dx in { -4, 4 } do
		for _, dz in { -4, 4 } do
			part(radio, "TowerLeg", Vector3.new(0.8, height, 0.8), CFrame.new(tx + dx, ROAD_TOP + height / 2, tz + dz), steel, Enum.Material.Metal)
		end
	end
	for y = 10, height, 14 do
		part(radio, "TowerRing", Vector3.new(9, 0.6, 0.6), CFrame.new(tx, ROAD_TOP + y, tz - 4), steel, Enum.Material.Metal)
		part(radio, "TowerRing", Vector3.new(9, 0.6, 0.6), CFrame.new(tx, ROAD_TOP + y, tz + 4), steel, Enum.Material.Metal)
		part(radio, "TowerRing", Vector3.new(0.6, 0.6, 9), CFrame.new(tx - 4, ROAD_TOP + y, tz), steel, Enum.Material.Metal)
		part(radio, "TowerRing", Vector3.new(0.6, 0.6, 9), CFrame.new(tx + 4, ROAD_TOP + y, tz), steel, Enum.Material.Metal)
	end
	local beacon = deco(part(radio, "Beacon", Vector3.new(2, 2, 2), CFrame.new(tx, ROAD_TOP + height + 1, tz), Color3.fromRGB(255, 30, 30), Enum.Material.Neon))
	light(beacon, 60, 3, Color3.fromRGB(255, 40, 40))
	task.spawn(function()
		while beacon.Parent do
			beacon.Transparency = if beacon.Transparency == 0 then 0.8 else 0
			task.wait(0.8)
		end
	end)
	placeSign(radio, "RADIO STATION", cx, yard.z1 + 12, Vector3.new(0, 0, 1), Color3.fromRGB(255, 220, 120))
end

local function buildFarm(parent: Instance)
	local farm = folder(parent, "OldFarm")
	local yard = yardOf("farm")
	part(farm, "Yard", Vector3.new(yard.x1 - yard.x0, 0.4, yard.z1 - yard.z0), CFrame.new((yard.x0 + yard.x1) / 2, ROAD_TOP - 0.2, (yard.z0 + yard.z1) / 2), Color3.fromRGB(110, 96, 70), Enum.Material.Ground)
	local cx, cz = (yard.x0 + yard.x1) / 2, (yard.z0 + yard.z1) / 2
	local barn = CFrame.new(cx - 60, ROAD_TOP, cz - 80)
	part(farm, "Barn", Vector3.new(40, 18, 30), barn * CFrame.new(0, 9, 0), Color3.fromRGB(150, 40, 36), Enum.Material.WoodPlanks)
	gableRoof(farm, barn * CFrame.new(0, 18, 0), 42, 32, 10, Color3.fromRGB(70, 60, 56))
	cylinder(farm, "Silo", 36, 14, CFrame.new(cx - 20, ROAD_TOP + 18, cz - 90) * UPRIGHT, Color3.fromRGB(170, 170, 170), Enum.Material.Metal)
	local dome = part(farm, "SiloTop", Vector3.new(14, 14, 14), CFrame.new(cx - 20, ROAD_TOP + 36, cz - 90), Color3.fromRGB(150, 150, 150), Enum.Material.Metal)
	dome.Shape = Enum.PartType.Ball
	-- Fields next to the yard.
	for n = 0, 7 do
		deco(part(farm, "Crops", Vector3.new(120, 1.2, 3), CFrame.new(yard.x0 - 70, ROAD_TOP + 0.6, yard.z0 + 30 + n * 10), Color3.fromRGB(90, 120, 50), Enum.Material.Grass))
	end
	for n = 1, 8 do
		cylinder(farm, "HayBale", 4, 5, CFrame.new(cx + rng:NextNumber(-100, 100), ROAD_TOP + 2.5, cz + rng:NextNumber(0, 120)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color3.fromRGB(210, 180, 90), Enum.Material.Grass)
	end
	for _, side in { yard.z0, yard.z1 } do
		deco(part(farm, "Fence", Vector3.new(yard.x1 - yard.x0, 3, 0.5), CFrame.new(cx, ROAD_TOP + 1.5, side), Color3.fromRGB(150, 120, 80), Enum.Material.WoodPlanks)).CanCollide = true
	end
	placeSign(farm, "OLD FARM", yard.x1 + 12, cz + 40, Vector3.new(1, 0, 0), Color3.fromRGB(255, 220, 120))
	employerBoard(farm, "farm", Vector3.new(1, 0, 0))
end

local function crane(parent: Instance, x: number, z: number)
	local yellow = Color3.fromRGB(220, 170, 40)
	for _, dz in { -8, 8 } do
		part(parent, "CraneLeg", Vector3.new(2, 40, 2), CFrame.new(x, 20, z + dz), yellow, Enum.Material.Metal)
		part(parent, "CraneLeg", Vector3.new(2, 40, 2), CFrame.new(x + 14, 20, z + dz), yellow, Enum.Material.Metal)
	end
	part(parent, "CraneBoom", Vector3.new(90, 3, 3), CFrame.new(x + 30, 41, z), yellow, Enum.Material.Metal)
	part(parent, "CraneCab", Vector3.new(8, 6, 8), CFrame.new(x + 7, 45, z), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
end

local function buildDocks(parent: Instance)
	local docks = folder(parent, "HarborDocks")
	local yard = yardOf("docks")
	yardFloor(docks, yard, Color3.fromRGB(120, 120, 116), Enum.Material.Concrete)
	for z = yard.z0 + 30, yard.z1 - 30, 80 do
		part(docks, "Pier", Vector3.new(90, 1, 14), CFrame.new(yard.x1 + 45, -0.5, z), Color3.fromRGB(110, 86, 60), Enum.Material.WoodPlanks)
		for x = yard.x1 + 10, yard.x1 + 85, 25 do
			cylinder(docks, "Post", 30, 1.6, CFrame.new(x, -15, z + 7) * UPRIGHT, Color3.fromRGB(80, 64, 48), Enum.Material.Wood)
			cylinder(docks, "Post", 30, 1.6, CFrame.new(x, -15, z - 7) * UPRIGHT, Color3.fromRGB(80, 64, 48), Enum.Material.Wood)
		end
	end
	crane(docks, yard.x0 + 10, yard.z0 + 40)
	crane(docks, yard.x0 + 10, yard.z1 - 40)
	-- A rusty ship.
	part(docks, "Ship", Vector3.new(40, 14, 140), CFrame.new(yard.x1 + 140, 2, 0), Color3.fromRGB(120, 50, 40), Enum.Material.CorrodedMetal)
	part(docks, "ShipBridge", Vector3.new(30, 14, 20), CFrame.new(yard.x1 + 140, 16, 50), Color3.fromRGB(220, 220, 210), Enum.Material.Metal)
	placeSign(docks, "HARBOR DOCKS", yard.x0 + 5, yard.z1 + 10, Vector3.new(-1, 0, 0), Color3.fromRGB(120, 200, 255))
end

local function buildGas(parent: Instance)
	local gas = folder(parent, "GasStation")
	local yard = yardOf("gas")
	yardFloor(gas, yard, Color3.fromRGB(70, 70, 72), Enum.Material.Concrete)
	local cx, cz = (yard.x0 + yard.x1) / 2, (yard.z0 + yard.z1) / 2
	for _, dx in { -20, 20 } do
		for _, dz in { -18, 18 } do
			part(gas, "Pillar", Vector3.new(2, 14, 2), CFrame.new(cx - 10 + dx, ROAD_TOP + 7, cz + dz), Color3.fromRGB(220, 220, 220), Enum.Material.Metal)
		end
	end
	local canopy = part(gas, "Canopy", Vector3.new(52, 2, 48), CFrame.new(cx - 10, ROAD_TOP + 15, cz), Color3.fromRGB(200, 40, 40), Enum.Material.Metal)
	light(canopy, 40, 1.5, Color3.fromRGB(255, 240, 220))
	for _, dz in { -9, 9 } do
		part(gas, "Pump", Vector3.new(2.5, 5, 4), CFrame.new(cx - 10, ROAD_TOP + 2.5, cz + dz), Color3.fromRGB(230, 230, 230), Enum.Material.Metal)
	end
	part(gas, "Shop", Vector3.new(26, 12, 30), CFrame.new(cx + 34, ROAD_TOP + 6, cz), Color3.fromRGB(200, 190, 170), Enum.Material.Concrete)
	sign(gas, "GAS", Vector3.new(14, 6, 0.5), CFrame.lookAt(Vector3.new(cx - 10, ROAD_TOP + 19, cz + 24.5), Vector3.new(cx - 10, ROAD_TOP + 19, cz + 30)), Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 40, 40))
end

local function cabin(parent: Instance, frame: CFrame, w: number, d: number, h: number)
	part(parent, "Cabin", Vector3.new(w, h, d), frame * CFrame.new(0, h / 2, 0), Color3.fromRGB(120, 80, 50), Enum.Material.WoodPlanks)
	gableRoof(parent, frame * CFrame.new(0, h, 0), w + 3, d + 3, h * 0.6, Color3.fromRGB(240, 244, 248))
	part(parent, "Door", Vector3.new(4, 7, 0.4), frame * CFrame.new(0, 3.5, -d / 2 - 0.2), Color3.fromRGB(80, 50, 30), Enum.Material.Wood)
	for _, x in { -w / 3, w / 3 } do
		local window = deco(part(parent, "Window", Vector3.new(4, 3, 0.3), frame * CFrame.new(x, h * 0.55, -d / 2 - 0.15), Color3.fromRGB(255, 200, 110), Enum.Material.Neon))
		light(window, 18, 1, Color3.fromRGB(255, 190, 110))
	end
end

local function buildWinter(parent: Instance)
	local winter = folder(parent, "Winter")
	local b = Map.Bounds
	local snow = Color3.fromRGB(236, 240, 244)
	tiled(winter, "Snow", b.x0 - 700, Map.River.x0, b.z0 - 700, Map.WinterZ, 0, 0.2, snow, Enum.Material.Snow)
	-- The frozen lake.
	local lake = Map.Lake
	local ice = part(winter, "FrozenLake", Vector3.new(lake.x1 - lake.x0, 0.4, lake.z1 - lake.z0), CFrame.new((lake.x0 + lake.x1) / 2, 0, (lake.z0 + lake.z1) / 2), Color3.fromRGB(170, 210, 230), Enum.Material.Ice)
	ice.Reflectance = 0.25
	for _ = 1, 12 do
		deco(part(winter, "Crack", Vector3.new(rng:NextNumber(8, 30), 0.05, 0.4), CFrame.new(rng:NextNumber(lake.x0 + 20, lake.x1 - 20), 0.22, rng:NextNumber(lake.z0 + 20, lake.z1 - 20)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color3.fromRGB(110, 150, 170)))
	end
	-- The Ski Lodge.
	local yard = yardOf("lodge")
	part(winter, "Yard", Vector3.new(yard.x1 - yard.x0, 0.4, yard.z1 - yard.z0), CFrame.new((yard.x0 + yard.x1) / 2, ROAD_TOP - 0.2, (yard.z0 + yard.z1) / 2), Color3.fromRGB(215, 220, 226), Enum.Material.Snow)
	local cx, cz = (yard.x0 + yard.x1) / 2, (yard.z0 + yard.z1) / 2
	local lodge = CFrame.lookAt(Vector3.new(cx - 70, ROAD_TOP, cz), Vector3.new(cx, ROAD_TOP, cz))
	cabin(winter, lodge, 50, 34, 18)
	sign(winter, "SKI LODGE", Vector3.new(26, 5, 0.4), lodge * CFrame.new(0, 22, -18), Color3.fromRGB(255, 220, 120))
	cabin(winter, CFrame.lookAt(Vector3.new(cx + 20, ROAD_TOP, cz - 85), Vector3.new(cx + 20, ROAD_TOP, cz)), 18, 14, 10)
	cabin(winter, CFrame.lookAt(Vector3.new(cx + 20, ROAD_TOP, cz + 85), Vector3.new(cx + 20, ROAD_TOP, cz)), 18, 14, 10)
	-- A ski lift up the hill behind.
	local liftColor = Color3.fromRGB(90, 90, 96)
	for n = 0, 5 do
		local x, z = yard.x0 - 30 - n * 60, cz - 40 + n * 6
		local height = 18 + n * 14
		part(winter, "LiftPole", Vector3.new(1.4, height, 1.4), CFrame.new(x, height / 2, z), liftColor, Enum.Material.Metal)
		part(winter, "LiftArm", Vector3.new(1, 1, 8), CFrame.new(x, height, z), liftColor, Enum.Material.Metal)
	end
	workspace.Terrain:FillBall(Vector3.new(yard.x0 - 260, -120, cz - 20), 220, Enum.Material.Snow)
	placeSign(winter, "SKI LODGE · ICE ROAD", lake.x1 + 30, -2200 - 30, Vector3.new(1, 0, 0), Color3.fromRGB(140, 220, 255))
	placeSign(winter, "THIN ICE · DRIVE SLOW", 300 - 40, -2170, Vector3.new(0, 0, 1), Color3.fromRGB(255, 120, 100))
end

-- ── Scattered things ───────────────────────────────────────────────────────

local function insideDistrict(x: number, z: number, margin: number): boolean
	for _, d in Map.Districts do
		local x0, x1, z0, z1 = Map.districtEdges(d)
		if x > x0 - ROAD / 2 - margin and x < x1 + ROAD / 2 + margin and z > z0 - ROAD / 2 - margin and z < z1 + ROAD / 2 + margin then
			return true
		end
	end
	return false
end

local function buildForests(parent: Instance)
	local forest = folder(parent, "Forests")
	local b = Map.Bounds
	local m = Map.Mountain
	local placed = 0
	for _ = 1, 1400 do
		if placed >= 260 then
			break
		end
		local x = rng:NextNumber(b.x0 + 40, b.x1 - 40)
		local z = rng:NextNumber(b.z0 + 40, b.z1 - 40)
		if Map.inWater(x, z) or insideDistrict(x, z, 20) or Map.inYard(x, z) or Map.onIce(x, z) then
			continue
		end
		if (Vector3.new(x - m.x, 0, z - m.z)).Magnitude < m.radius + 60 then
			continue
		end
		local rx, rz, _, _, width = Map.nearestRoad(x, z)
		if (Vector3.new(x - rx, 0, z - rz)).Magnitude < width / 2 + 10 then
			continue
		end
		tree(forest, x, z, 0)
		placed += 1
	end
end

local function distanceToSegment(s: Map.Segment, x: number, z: number): number
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
	return math.sqrt((x - s.ax - dx * t) ^ 2 + (z - s.az - dz * t) ^ 2)
end

local function buildRoadWrecks(parent: Instance)
	local wrecks = folder(parent, "RoadWrecks")
	local segments = Map.Segments
	local placed = 0
	for _ = 1, 200 do
		if placed >= 40 then
			break
		end
		local s = segments[rng:NextInteger(1, #segments)]
		local t = rng:NextNumber(0.1, 0.9)
		local x, z = s.ax + (s.bx - s.ax) * t, s.az + (s.bz - s.az) * t
		if Map.isSafe(x, z) or s.kind == "bridge" then
			continue
		end
		local dx, dz = s.bx - s.ax, s.bz - s.az
		local length = math.sqrt(dx * dx + dz * dz)
		dx, dz = dx / length, dz / length
		-- Not on a crossing: no other road centre line close by.
		local crossing = false
		for _, o in segments do
			if o ~= s and distanceToSegment(o, x, z) < 45 then
				crossing = true
				break
			end
		end
		if crossing then
			continue
		end
		local lane = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(7, s.width / 2 - 5)
		local at = Vector3.new(x - dz * lane, ROAD_TOP, z + dx * lane)
		wreck(wrecks, CFrame.lookAt(at, at + Vector3.new(dx, 0, dz)) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0))
		placed += 1
	end
end

local function buildBoundary(parent: Instance)
	local walls = folder(parent, "Boundary")
	local b = Map.Bounds
	local black = Color3.new(0, 0, 0)
	local sides = {
		tiled(walls, "Invisible", b.x0, b.x1, b.z0 - 2, b.z0 + 2, 140, 300, black, Enum.Material.SmoothPlastic),
		tiled(walls, "Invisible", b.x0, b.x1, b.z1 - 2, b.z1 + 2, 140, 300, black, Enum.Material.SmoothPlastic),
		tiled(walls, "Invisible", b.x0 - 2, b.x0 + 2, b.z0, b.z1, 140, 300, black, Enum.Material.SmoothPlastic),
		tiled(walls, "Invisible", b.x1 - 2, b.x1 + 2, b.z0, b.z1, 140, 300, black, Enum.Material.SmoothPlastic),
	}
	for _, list in sides do
		for _, wall in list do
			wall.Transparency = 1
			wall.CanQuery = false
		end
	end
end

local function setLighting()
	Lighting.ClockTime = 18.6
	Lighting.Brightness = 1.6
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 110)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Color = Color3.fromRGB(150, 160, 140)
	atmosphere.Decay = Color3.fromRGB(90, 100, 80)
	atmosphere.Haze = 1.8
	atmosphere.Parent = Lighting
	local grade = Lighting:FindFirstChild("ZombieGrade") :: ColorCorrectionEffect? or Instance.new("ColorCorrectionEffect")
	grade.Name = "ZombieGrade"
	grade.Saturation = -0.2
	grade.Contrast = 0.1
	grade.TintColor = Color3.fromRGB(235, 245, 225)
	grade.Parent = Lighting
	local terrain = workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(40, 70, 60)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.1
end

function World.build()
	-- A fresh Baseplate place: its plate and spawn would sit inside the city.
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
	workspace.Terrain:Clear()

	folder(workspace, "Cars")
	folder(workspace, "Zombies")
	folder(workspace, "Effects")
	local world = folder(workspace, "World")

	-- Piece by piece, with a breath in between (Studio stays responsive), and a piece that fails only warns.
	local function piece(name: string, build: () -> ())
		local started = os.clock()
		local ok, err = pcall(function()
			build()
		end)
		if not ok then
			warn(`[World] {name} failed: {err}`)
		end
		print(`[World] {name} built in {math.floor((os.clock() - started) * 1000)} ms`)
		task.wait()
	end
	piece("ground", function()
		buildGround(world)
	end)
	for _, d in Map.Districts do
		piece(d.name, function()
			buildDistrict(world, d)
		end)
	end
	piece("roads and bridges", function()
		buildConnectors(world)
	end)
	piece("mountain", function()
		buildMountain(world)
	end)
	piece("military base", function()
		buildBase(world)
	end)
	piece("radio station", function()
		buildRadio(world)
	end)
	piece("farm", function()
		buildFarm(world)
	end)
	piece("docks", function()
		buildDocks(world)
	end)
	piece("gas station", function()
		buildGas(world)
	end)
	piece("winter", function()
		buildWinter(world)
	end)
	piece("forests", function()
		buildForests(world)
	end)
	piece("wrecks", function()
		buildRoadWrecks(world)
	end)
	piece("boundary", function()
		buildBoundary(world)
	end)
	piece("landmark tags", function()
		buildLandmarkTags(world)
	end)
	piece("lighting", setLighting)
end

function World.isSafe(position: Vector3): boolean
	return Map.isSafe(position.X, position.Z)
end

-- In the depot yard or inside Wrench Garage.
function World.canRepair(position: Vector3): boolean
	for _, spot in World.RepairSpots do
		if Vector3.new(position.X - spot.X, 0, position.Z - spot.Z).Magnitude < Config.City.RepairRadius then
			return true
		end
	end
	return false
end

return World
