--!strict
-- Builds the world in code when the server starts, from the layout in shared/Map.luau and a fixed seed (every server
-- gets the same world): the land, the river and the sea (terrain water), the three districts (Downtown, Harbor,
-- Suburbs), the bridges, the highways with the mountain tunnel (terrain), the far places (Military Base, Radio
-- Station, Old Farm, Harbor Docks, Gas Station, Silver Spur Ranch, Riverside Riding School, Harbor Fuel Depot), the
-- depot and the four shops, the First Zombie Bank and the City Clinic, street lamps, wrecks, forests and the light.
-- Every employer stands at their WORK HERE board (an R15 person from server/Npcs.luau); horses graze at the ranch and
-- the riding school (server/Animals.luau).
--
-- Zombie Delivery 2.6, the real estate (Config.Estate, laid out in Map.EstatePlots): Sunset Hills up the winding
-- Sunset Drive (terrain hills, the gate) with the Hilltop Mansion, the other mansions and the villas each in their own
-- spot (the sea cliffs with a pier, the pines, the frozen lake with a jetty, a lane in the west), the houses for sale
-- on their Suburbs lots and at the edge of town, the Harbor Lockup, the Highway Garage, Downtown Parking and the two
-- office towers (Dispatch Tower, Harbor Point) with their lobbies, office floors, roof terraces and elevator pads.
-- It registers the FOR SALE signs' prompts (World.EstatePrompts), the home spawns (World.EstateSpawns), the garages'
-- drive-out spots (World.EstateGarages) and the office computers (World.OfficePrompts) for server/Estate, CarCall and
-- Business.
--
-- The night: the street lamps, the lit windows and the night lights of the far places are registered with
-- server/DayNight.luau, which switches them with the workspace attribute "Night". Only some lamps carry a real light
-- (a SpotLight shining down); the rest only glow, so the city stays cheap at night.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Map = require(Shared.Map)

local Npcs = require(script.Parent.Npcs)
local Animals = require(script.Parent.Animals)
local DayNight = require(script.Parent.DayNight)

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
World.EmployerNpcs = {} :: { [string]: Model } -- the person at each WORK HERE board (Config.Employers id)
World.DealerSlots = {} :: { CFrame }
World.RepairSpots = { Vector3.new(0, 0, 0) } :: { Vector3 }
-- The real estate (2.6; filled by World.build, see "Real estate" below):
-- the FOR SALE signs' prompts (a ProximityPrompt "EstatePrompt", attribute Estate = the Config.Estate id; an office
-- has one in the lobby and one in the office)
World.EstatePrompts = {} :: { { prompt: ProximityPrompt, estate: string } }
-- homes: the character's spot just inside the front door, facing in (at a HumanoidRootPart's height, like
-- DepotSpawn); offices: in the office, in front of the elevators
World.EstateSpawns = {} :: { [string]: CFrame }
-- homes and garages: in front of the garage door, facing the road, at the height Vehicles.spawn builds a car at on a
-- road (the ground + 0.5)
World.EstateGarages = {} :: { [string]: CFrame }
-- the office computers (a ProximityPrompt "OfficePrompt", attribute Office = the Config.Estate id)
World.OfficePrompts = {} :: { { prompt: ProximityPrompt, office: string } }
-- the status line of every FOR SALE sign (a TextLabel "Status" on the EstatePrompt's parent; "FOR SALE\n$x" to start
-- with, server/Estate.luau may write the owners there)
World.EstateSigns = {} :: { [string]: { TextLabel } }

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
local GLASS_BLUE = Color3.fromRGB(150, 190, 210)
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

local function light(parent: Instance, range: number, brightness: number, color: Color3): PointLight
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color
	l.Shadows = false
	l.Parent = parent
	return l
end

-- A window that is dark glass (its colour now) by day and warm light at night (DayNight switches it).
local WINDOW_LIT = Color3.fromRGB(255, 210, 120)
local WINDOW_DIM = Color3.fromRGB(40, 50, 60)
local function nightWindow(p: Part, lit: Color3?)
	DayNight.nightLight(p, lit or WINDOW_LIT, p.Color, "Glass")
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

-- A street lamp: a pole, an arm reaching over the road (`reach`: the flat direction) and a head that glows at night.
-- Only the lamps with `beam` carry a real light (a SpotLight shining down: a pool of light on the road); the others
-- just glow (cheap). DayNight switches them all with the night.
local LAMP_LIT = Color3.fromRGB(255, 214, 150)
local LAMP_DIM = Color3.fromRGB(170, 170, 160)
local LAMP_POLE = Color3.fromRGB(50, 50, 54)
local function lamp(parent: Instance, x: number, z: number, base: number?, reach: Vector3?, beam: boolean?)
	local y = base or WALK_TOP
	local out = if reach and reach.Magnitude > 0.01 then Vector3.new(reach.X, 0, reach.Z).Unit else Vector3.new(-1, 0, 0)
	part(parent, "Pole", Vector3.new(0.6, 16, 0.6), CFrame.new(x, y + 8, z), LAMP_POLE, Enum.Material.Metal)
	local foot = Vector3.new(x, y + 15.8, z)
	deco(part(parent, "LampArm", Vector3.new(0.35, 0.35, 4.4), CFrame.lookAt(foot + out * 2.2, foot + out * 4.4), LAMP_POLE, Enum.Material.Metal))
	local at = foot + out * 4.2 - Vector3.new(0, 0.3, 0)
	deco(part(parent, "LampHood", Vector3.new(2, 0.3, 1.4), CFrame.lookAt(at + Vector3.new(0, 0.3, 0), at + Vector3.new(0, 0.3, 0) + out), LAMP_POLE, Enum.Material.Metal))
	local head = deco(part(parent, "Lamp", Vector3.new(1.7, 0.3, 1.1), CFrame.lookAt(at, at + out), LAMP_DIM, Enum.Material.Glass))
	if beam ~= false then
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 120
		spot.Range = 40
		spot.Brightness = 2.4
		spot.Color = Color3.fromRGB(255, 208, 150)
		spot.Shadows = false
		spot.Parent = head
	end
	DayNight.nightLight(head, LAMP_LIT, LAMP_DIM, "Glass")
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

-- Is this spot free of the places where cargo is loaded and the employers stand (keep props off them)?
local function clearOfSpots(x: number, z: number, radius: number): boolean
	local function near(px: number, pz: number): boolean
		return (x - px) ^ 2 + (z - pz) ^ 2 < radius * radius
	end
	for _, spot in Map.CargoSpots do
		if near(spot.park.x, spot.park.z) or near(spot.pile.x, spot.pile.z) then
			return false
		end
	end
	for _, spot in Map.EmployerSpots do
		if near(spot.x, spot.z) then
			return false
		end
	end
	return true
end

-- The floor height at a point: the sidewalks of the blocks are higher than the roads and the yards.
local function groundAt(x: number, z: number): number
	if Map.inYard(x, z) then
		return ROAD_TOP
	end
	return if (Map.blockAt(x, z)) ~= nil then WALK_TOP else ROAD_TOP
end

-- A wooden rail fence from a to b on the ground at `base`: a post every ~10 studs and `rails` long rails.
local function fence(parent: Instance, ax: number, az: number, bx: number, bz: number, base: number, height: number, color: Color3, rails: number)
	local a, b = Vector3.new(ax, base, az), Vector3.new(bx, base, bz)
	local length = (b - a).Magnitude
	local frame = CFrame.lookAt((a + b) / 2, b)
	local posts = math.max(1, math.floor(length / 10 + 0.5))
	for n = 0, posts do
		local p = a:Lerp(b, n / posts)
		part(parent, "FencePost", Vector3.new(0.6, height + 0.3, 0.6), CFrame.new(p + Vector3.new(0, (height + 0.3) / 2, 0)), color, Enum.Material.Wood)
	end
	for r = 1, rails do
		part(parent, "FenceRail", Vector3.new(0.22, 0.45, length), frame * CFrame.new(0, height * r / rails - 0.3, 0), color, Enum.Material.WoodPlanks)
	end
end

-- An oil drum standing at `at` (its bottom).
local function barrel(parent: Instance, at: Vector3, color: Color3)
	cylinder(parent, "Barrel", 3, 2.2, CFrame.new(at + Vector3.new(0, 1.5, 0)) * UPRIGHT, color, Enum.Material.Metal)
	deco(cylinder(parent, "BarrelRing", 0.15, 2.3, CFrame.new(at + Vector3.new(0, 2.2, 0)) * UPRIGHT, color:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal))
end

-- A pallet with a stack of boxes on it (cargo waiting around a loading spot; props, not the job's cargo).
local function palletStack(parent: Instance, frame: CFrame, box: Vector3, color: Color3, cols: number, rows: number, layers: number, material: Enum.Material?)
	local w, d = cols * (box.X + 0.2), rows * (box.Z + 0.2)
	part(parent, "Pallet", Vector3.new(w + 0.4, 0.5, d + 0.4), frame * CFrame.new(0, 0.25, 0), Color3.fromRGB(150, 116, 74), Enum.Material.WoodPlanks)
	for layer = 0, layers - 1 do
		for c = 0, cols - 1 do
			for r = 0, rows - 1 do
				local x = -w / 2 + (c + 0.5) * (box.X + 0.2)
				local z = -d / 2 + (r + 0.5) * (box.Z + 0.2)
				part(parent, "Box", box, frame * CFrame.new(x, 0.5 + box.Y / 2 + layer * box.Y, z), color, material or Enum.Material.WoodPlanks)
			end
		end
	end
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

-- The real estate's builders, used by the districts below (defined in "Real estate").
local buildEstateHouse: (Instance, number, number) -> boolean
local buildLockup: (Instance, number, number) -> ()
local buildParking: (Instance, number, number) -> ()
local buildTowerBlock: (Instance, string, number, number) -> ()

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
	-- Lamps at the crossings (on the corner, the arm over the crossing). Downtown has one at every crossing, the other
	-- districts at every other one; about half of them carry a real light, the rest only glow.
	local reach = Vector3.new(-1, 0, -1)
	for kx = d.i0 - 1, d.i1 do
		for kz = d.j0 - 1, d.j1 do
			local x = d.ox + (kx + 0.5) * CELL + ROAD / 2 + 2
			local z = d.oz + (kz + 0.5) * CELL + ROAD / 2 + 2
			if d.style == "downtown" then
				if x < x1 and z < z1 then
					lamp(parent, x, z, nil, reach, (kx + kz) % 2 == 0)
				end
			elseif x < x1 and z < z1 and (kx + kz) % 2 == 0 then
				lamp(parent, x, z, nil, reach, kx % 2 == 0)
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
			local lit = rng:NextNumber() < 0.25 -- these light up at night
			local window = deco(part(
				parent,
				"Window",
				Vector3.new(faceWidth - 4, 3, 0.3),
				CFrame.new(cx, y, cz) * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0, faceDepth / 2 + 0.1),
				Color3.fromRGB(30, 36, 44),
				Enum.Material.Glass
			))
			if lit then
				nightWindow(window)
			end
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
	local inset = 10 -- the towers end 10+ studs inside the block: room for a receiver and the pieces at an address
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
	-- A warehouse on one half, stacked containers on the other; both stay 10 studs inside the block's edge (an
	-- address's receiver and pieces stand there).
	local flip = if rng:NextNumber() < 0.5 then -1 else 1
	local w, d, h = BLOCK - 26, BLOCK / 2 - 14, rng:NextNumber(16, 24)
	local wz = cz + flip * (BLOCK / 4 - 3)
	part(parent, "Warehouse", Vector3.new(w, h, d), CFrame.new(cx, WALK_TOP + h / 2, wz), Color3.fromRGB(110 + rng:NextInteger(-20, 20), 100, 90), Enum.Material.CorrodedMetal)
	part(parent, "WarehouseRoof", Vector3.new(w + 2, 1.5, d + 2), CFrame.new(cx, WALK_TOP + h + 0.75, wz), Color3.fromRGB(70, 70, 74), Enum.Material.Metal)
	sign(parent, "WAREHOUSE " .. tostring(rng:NextInteger(1, 40)), Vector3.new(24, 4, 0.4), CFrame.new(cx, WALK_TOP + h - 3, wz - flip * (d / 2 + 0.3)) * CFrame.Angles(0, if flip > 0 then 0 else math.pi, 0), Color3.fromRGB(240, 240, 240), Color3.fromRGB(60, 60, 64))
	local sz = cz - flip * (BLOCK / 4 - 5)
	for row = -1, 1, 2 do
		for col = -2, 2 do
			if rng:NextNumber() < 0.75 then
				local stack = rng:NextInteger(1, 3)
				for level = 0, stack - 1 do
					container(parent, CFrame.new(cx + col * 9.5, WALK_TOP + 4.25 + level * 8.6, sz + row * 10.5) * CFrame.Angles(0, math.rad(rng:NextNumber(-2, 2)), 0))
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
		local window = deco(part(parent, "Window", Vector3.new(4, 3.5, 0.3), frame * CFrame.new(x, h * 0.55, -d / 2 - 0.15), Color3.fromRGB(40, 50, 60), Enum.Material.Glass))
		if lit then
			nightWindow(window)
		end
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
			-- The house faces the nearer road (north or south). A house for sale (Map.EstatePlots) has its own lot.
			local facing = if b == 0 then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1)
			local origin = Vector3.new(lx, WALK_TOP, lz - facing.Z * 4)
			local forSale = buildEstateHouse(parent, lx, lz) -- its lawn and back fence as on every lot
			if forSale then
				-- (its own house, drive and sign)
			elseif rng:NextNumber() < 0.85 then
				house(parent, CFrame.lookAt(origin, origin + facing))
			else
				wreck(parent, CFrame.new(lx, WALK_TOP, lz) * CFrame.Angles(0, rng:NextNumber(0, 6), 0))
			end
			if not forSale and rng:NextNumber() < 0.6 then
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
local buildBank: (Instance, number, number) -> ()
local buildClinic: (Instance, number, number) -> ()

-- What each employer's person wears (server/Npcs.luau roles).
local EMPLOYER_ROLES: { [string]: string } = {
	school = "clerk",
	army = "officer",
	icecream = "icecream",
	movers = "mover",
	farm = "farmer",
	ranch = "rancher",
	gas = "attendant",
	clinic = "doctor",
}

-- "Walt, the rancher" → "Walt" and "Rancher · Silver Spur Ranch"; "Captain Reyes" → itself and the place's name.
local function nameAndTitle(person: string, place: string): (string, string)
	local name, role = string.match(person, "^(.-), the (.+)$")
	if name and role then
		return name, `{string.upper(string.sub(role, 1, 1))}{string.sub(role, 2)} · {place}`
	end
	return person, place
end

-- A notice board with the employer standing next to it. Talking to them (the prompt on the person, or on the
-- board when no person could be made) opens the employer's window (server/Shops.luau).
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
	local def: Config.EmployerDef? = nil
	for _, d in Config.Employers do
		if d.id == employer then
			def = d
		end
	end
	local name = if def then def.name else employer
	local person = if def then def.person else name

	local npc: Model? = nil
	local ok, err = pcall(function()
		local who, title = nameAndTitle(person, name)
		local at = (frame * CFrame.new(4.4, 0, -1.4)).Position
		local feet = Vector3.new(at.X, groundAt(at.X, at.Z), at.Z)
		npc = Npcs.spawn(Npcs.look(EMPLOYER_ROLES[employer] or "townsperson", who, title), CFrame.lookAt(feet, feet + facing))
	end)
	if not ok then
		warn(`[World] no person at the {name} board: {err}`)
	end
	local holder: BasePart = board
	local npcRoot = if npc then npc.PrimaryPart else nil
	if npc and npcRoot then
		World.EmployerNpcs[employer] = npc
		holder = npcRoot
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "EmployerPrompt"
	p.ActionText = if holder == board then "Work here" else `Work for {name}`
	p.ObjectText = if holder == board then name else person
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p:SetAttribute("Employer", employer)
	p.Parent = holder
	table.insert(World.EmployerPrompts, { prompt = p, employer = employer })
	local talking = npc
	if talking and def then
		local pitch = def.pitch
		p.Triggered:Connect(function(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				Npcs.glance(talking, root.Position)
			end
			Npcs.say(talking, pitch, 6)
		end)
	end
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

-- A person who only stands there (a guard, a nurse): an R15 NPC from server/Npcs.luau, or nothing if none can be made.
local function bystander(role: string, person: string, place: string, at: CFrame)
	local ok, err = pcall(function()
		local who, title = nameAndTitle(person, place)
		local feet = at.Position
		Npcs.spawn(Npcs.look(role, who, title), CFrame.lookAt(feet, feet + at.LookVector))
	end)
	if not ok then
		warn(`[World] no {person} at {place}: {err}`)
	end
end

-- ── First Zombie Bank ──────────────────────────────────────────────────────
-- Downtown, just north of the safe zone, its front on the avenue to the North Highway: a marble hall with a portico
-- of columns, steps down to the curb where the armored truck loads the cash (Map.CargoSpots.bank), the vault door
-- inside, a guard at the door.

local MARBLE = Color3.fromRGB(214, 208, 192)
local GOLD = Color3.fromRGB(226, 182, 64)

function buildBank(parent: Instance, cx: number, cz: number)
	local bank = folder(parent, "FirstZombieBank")
	sidewalk(bank, cx, cz, Color3.fromRGB(168, 162, 150))
	local facing = Vector3.new(-1, 0, 0)
	local w, d, h = 72, 56, 24
	local frame = shopFrame(cx, cz, facing, 14)
	building(bank, frame, w, d, h, MARBLE, Enum.Material.Marble, 12, 14)
	local front = -d / 2
	-- The portico: a platform with a step, six columns, the beam with the name and the pediment over it.
	part(bank, "Portico", Vector3.new(48, 1.2, 10), frame * CFrame.new(0, 0.6, front - 5), MARBLE, Enum.Material.Marble)
	part(bank, "Step", Vector3.new(48, 0.6, 3), frame * CFrame.new(0, 0.3, front - 11.5), MARBLE:Lerp(Color3.new(0, 0, 0), 0.08), Enum.Material.Marble)
	for _, x in { -21, -15, -9, 9, 15, 21 } do
		cylinder(bank, "Column", 18.6, 2.4, frame * CFrame.new(x, 1.2 + 9.3, front - 7.5) * UPRIGHT, MARBLE, Enum.Material.Marble)
		part(bank, "ColumnBase", Vector3.new(3.2, 0.6, 3.2), frame * CFrame.new(x, 1.5, front - 7.5), MARBLE, Enum.Material.Marble)
		part(bank, "ColumnCap", Vector3.new(3.2, 0.6, 3.2), frame * CFrame.new(x, 19.5, front - 7.5), MARBLE, Enum.Material.Marble)
	end
	part(bank, "Beam", Vector3.new(50, 2.6, 10), frame * CFrame.new(0, 21.1, front - 5), MARBLE, Enum.Material.Marble)
	gableRoof(bank, frame * CFrame.new(0, 22.4, front - 5) * CFrame.Angles(0, math.pi / 2, 0), 10, 50, 6.5, MARBLE)
	sign(bank, "FIRST ZOMBIE BANK", Vector3.new(40, 2.2, 0.3), frame * CFrame.new(0, 21.1, front - 10.16), GOLD, Color3.fromRGB(34, 52, 44))
	local coin = deco(part(bank, "Coin", Vector3.new(0.3, 3.6, 3.6), frame * CFrame.new(0, 24.6, front - 10.1) * CFrame.Angles(0, math.pi / 2, 0), GOLD, Enum.Material.Metal))
	coin.Shape = Enum.PartType.Cylinder
	-- A copper dome on the roof.
	part(bank, "DomeBase", Vector3.new(22, 1.2, 22), frame * CFrame.new(0, h + 1.6, 6), MARBLE, Enum.Material.Marble)
	cylinder(bank, "DomeDrum", 7, 16, frame * CFrame.new(0, h + 5.2, 6) * UPRIGHT, MARBLE, Enum.Material.Marble)
	local dome = part(bank, "Dome", Vector3.new(16, 16, 16), frame * CFrame.new(0, h + 8.7, 6), Color3.fromRGB(96, 140, 118), Enum.Material.Metal)
	dome.Shape = Enum.PartType.Ball
	-- Tall windows beside the door: they glow at night; lanterns at the door, a light under the portico.
	for _, x in { -27, -17, 17, 27 } do
		nightWindow(deco(part(bank, "Window", Vector3.new(5, 12, 0.2), frame * CFrame.new(x, 9, front - 0.6), WINDOW_DIM, Enum.Material.Glass)), Color3.fromRGB(255, 226, 160))
	end
	for _, x in { -7.6, 7.6 } do
		local lantern = deco(part(bank, "Lantern", Vector3.new(1, 1.8, 1), frame * CFrame.new(x, 9, front - 0.9), Color3.fromRGB(150, 140, 110), Enum.Material.Glass))
		DayNight.nightLight(lantern, Color3.fromRGB(255, 220, 140), Color3.fromRGB(150, 140, 110), "Glass")
	end
	local porch = deco(part(bank, "PorticoLight", Vector3.new(3, 0.3, 3), frame * CFrame.new(0, 19.6, front - 5), Color3.fromRGB(150, 140, 110), Enum.Material.Glass))
	light(porch, 34, 1.6, Color3.fromRGB(255, 222, 170))
	DayNight.nightLight(porch, Color3.fromRGB(255, 230, 170), Color3.fromRGB(150, 140, 110), "Glass")
	-- Inside: the tellers' counter behind glass, the round vault door in the back wall, gold bars on a cart.
	part(bank, "TellerCounter", Vector3.new(40, 4, 3), frame * CFrame.new(0, 2, 4), Color3.fromRGB(96, 66, 44), Enum.Material.Wood)
	local screen = part(bank, "TellerGlass", Vector3.new(40, 4, 0.2), frame * CFrame.new(0, 6, 4), GLASS_BLUE, Enum.Material.Glass)
	screen.Transparency = 0.6
	local vault = frame * CFrame.new(0, 7.5, d / 2 - 1.6) * CFrame.Angles(0, math.pi / 2, 0)
	cylinder(bank, "VaultDoor", 1.2, 13, vault, Color3.fromRGB(150, 150, 156), Enum.Material.DiamondPlate)
	cylinder(bank, "VaultHub", 1.8, 3, vault * CFrame.new(0.6, 0, 0), GOLD, Enum.Material.Metal)
	for n = 0, 2 do
		deco(part(bank, "VaultSpoke", Vector3.new(0.4, 0.5, 8), vault * CFrame.new(1, 0, 0) * CFrame.Angles(n * math.pi / 3, 0, 0), GOLD, Enum.Material.Metal))
	end
	part(bank, "Cart", Vector3.new(5, 0.4, 3), frame * CFrame.new(-14, 2, 18), Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
	for n = 0, 5 do
		local bar = part(bank, "GoldBar", Vector3.new(1.4, 0.6, 0.8), frame * CFrame.new(-15.6 + (n % 3) * 1.6, 2.5 + math.floor(n / 3) * 0.6, 18), GOLD, Enum.Material.Metal)
		bar.Reflectance = 0.2
	end
	-- Flags at the corners of the forecourt, a sign at the curb for the armored trucks.
	for _, x in { -33, 33 } do
		part(bank, "FlagPole", Vector3.new(0.5, 18, 0.5), frame * CFrame.new(x, 9, front - 14), Color3.fromRGB(210, 210, 210), Enum.Material.Metal)
		deco(part(bank, "Flag", Vector3.new(6, 3.6, 0.2), frame * CFrame.new(x + (if x > 0 then -3.2 else 3.2), 15.8, front - 14), Color3.fromRGB(40, 110, 70), Enum.Material.Fabric))
	end
	local spot = Map.CargoSpots.bank
	local post = Vector3.new(spot.pile.x - 2, WALK_TOP, spot.pile.z - 15)
	part(bank, "SignPost", Vector3.new(0.4, 7, 0.4), CFrame.new(post + Vector3.new(0, 3.5, 0)), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	sign(bank, "ARMORED TRUCKS ONLY", Vector3.new(7, 2, 0.2), CFrame.lookAt(post + Vector3.new(0, 6.4, 0), post + Vector3.new(0, 6.4, 0) + facing), Color3.fromRGB(255, 255, 255), Color3.fromRGB(34, 52, 44))
	-- The guard by the door (on a cash run the manager brings the sacks out to the curb).
	bystander("guard", "Sam, the bank guard", "First Zombie Bank", frame * CFrame.new(12, 1.2, front - 9.6))
end

-- ── City Clinic ────────────────────────────────────────────────────────────
-- Downtown, south-west of the depot: a white two-storey clinic with blue windows, the emergency canopy over the
-- sidewalk where the ambulance unloads (Map.CargoSpots.clinic), a helipad on the roof, beds inside. Dr. Novak hires
-- ambulance drivers at the WORK HERE board beside the front; a nurse waits under the canopy.

local CLINIC_WHITE = Color3.fromRGB(238, 240, 236)
local CLINIC_RED = Color3.fromRGB(214, 36, 40)

-- A red cross (two bars) on a plane: frame at its centre, facing -Z.
local function redCross(parent: Instance, frame: CFrame, size: number)
	deco(part(parent, "Cross", Vector3.new(size, size / 3, 0.3), frame, CLINIC_RED, Enum.Material.Neon))
	deco(part(parent, "Cross", Vector3.new(size / 3, size, 0.3), frame, CLINIC_RED, Enum.Material.Neon))
end

function buildClinic(parent: Instance, cx: number, cz: number)
	local clinic = folder(parent, "CityClinic")
	sidewalk(clinic, cx, cz, Color3.fromRGB(176, 178, 176))
	local facing = Vector3.new(1, 0, 0)
	local spot = Map.CargoSpots.clinic
	-- The building is centred on the emergency entrance (in line with the cargo spot), set back 10 in the block.
	local origin = Vector3.new(cx - 10, WALK_TOP, spot.pile.z)
	local frame = CFrame.lookAt(origin, origin + facing)
	local w, d, h = 84, 56, 26
	building(clinic, frame, w, d, h, CLINIC_WHITE, Enum.Material.Concrete, 14, 11)
	local front = -d / 2
	sign(clinic, "CITY CLINIC", Vector3.new(44, 5, 0.5), frame * CFrame.new(0, h + 4, front), CLINIC_RED, Color3.fromRGB(250, 250, 250))
	-- Window bands on both floors (they glow cold white at night), a red cross on the front.
	local paneDim, paneLit = Color3.fromRGB(110, 150, 180), Color3.fromRGB(226, 240, 255)
	for _, x in { -26, 26 } do
		for _, y in { 6.5, 17.5 } do
			local pane = deco(part(clinic, "Window", Vector3.new(26, 4, 0.2), frame * CFrame.new(x, y, front - 0.6), paneDim, Enum.Material.Glass))
			DayNight.nightLight(pane, paneLit, paneDim, "Glass")
		end
	end
	local over = deco(part(clinic, "Window", Vector3.new(12, 4, 0.2), frame * CFrame.new(0, 19, front - 0.6), paneDim, Enum.Material.Glass))
	DayNight.nightLight(over, paneLit, paneDim, "Glass")
	deco(part(clinic, "CrossPanel", Vector3.new(7, 6.6, 0.3), frame * CFrame.new(-36, 12, front - 0.65), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic))
	redCross(clinic, frame * CFrame.new(-36, 12, front - 0.85), 5.4)
	-- The emergency canopy from the door out to the curb: the ambulance unloads under it.
	local toCurb = (origin.X + d / 2) - (cx + BLOCK / 2) -- negative: the curb is in front of the wall
	local length = -toCurb - 2
	local mid = front - length / 2
	part(clinic, "Canopy", Vector3.new(26, 0.8, length), frame * CFrame.new(0, 13.4, mid), CLINIC_WHITE, Enum.Material.Metal)
	deco(part(clinic, "CanopyTrim", Vector3.new(26.4, 0.5, length + 0.4), frame * CFrame.new(0, 12.9, mid), CLINIC_RED, Enum.Material.SmoothPlastic))
	for _, x in { -12, 12 } do
		part(clinic, "CanopyPost", Vector3.new(0.8, 13, 0.8), frame * CFrame.new(x, 6.5, front - length + 1), Color3.fromRGB(200, 200, 204), Enum.Material.Metal)
	end
	sign(clinic, "EMERGENCY", Vector3.new(18, 2.6, 0.3), frame * CFrame.new(0, 14.6, front - length - 0.2), Color3.fromRGB(255, 255, 255), CLINIC_RED)
	local panel = deco(part(clinic, "CanopyLight", Vector3.new(8, 0.2, 2), frame * CFrame.new(0, 12.6, mid), Color3.fromRGB(190, 196, 200), Enum.Material.Glass))
	light(panel, 30, 1.8, Color3.fromRGB(235, 245, 255))
	DayNight.nightLight(panel, Color3.fromRGB(240, 248, 255), Color3.fromRGB(190, 196, 200), "Glass")
	-- A sign at the curb, a bench by the door.
	local post = Vector3.new(spot.pile.x + 1, WALK_TOP, spot.pile.z + 19)
	part(clinic, "SignPost", Vector3.new(0.4, 7, 0.4), CFrame.new(post + Vector3.new(0, 3.5, 0)), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	sign(clinic, "AMBULANCES ONLY", Vector3.new(7, 2, 0.2), CFrame.lookAt(post + Vector3.new(0, 6.4, 0), post + Vector3.new(0, 6.4, 0) + facing), Color3.fromRGB(255, 255, 255), CLINIC_RED)
	local bench = frame * CFrame.new(24, 0, front - 4)
	part(clinic, "Bench", Vector3.new(8, 0.5, 2), bench * CFrame.new(0, 1.8, 0), Color3.fromRGB(110, 80, 56), Enum.Material.WoodPlanks)
	part(clinic, "BenchBack", Vector3.new(8, 2, 0.4), bench * CFrame.new(0, 3, 0.9), Color3.fromRGB(110, 80, 56), Enum.Material.WoodPlanks)
	for _, x in { -3.4, 3.4 } do
		part(clinic, "BenchLeg", Vector3.new(0.4, 1.6, 1.8), bench * CFrame.new(x, 0.8, 0), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	end
	-- On the roof: the helipad with its H and lights, a big red cross seen from the road.
	cylinder(clinic, "Helipad", 0.3, 26, frame * CFrame.new(10, h + 1.15, 6) * UPRIGHT, Color3.fromRGB(70, 74, 78), Enum.Material.Concrete)
	for _, piece in { { 1.6, 10, -3 }, { 1.6, 10, 3 }, { 6, 1.6, 0 } } do
		deco(part(clinic, "H", Vector3.new(piece[1], 0.05, piece[2]), frame * CFrame.new(10 + piece[3], h + 1.32, 6), Color3.fromRGB(240, 240, 240)))
	end
	for n = 0, 5 do
		local angle = n * math.pi / 3
		local beacon = deco(part(clinic, "PadLight", Vector3.new(0.6, 0.4, 0.6), frame * CFrame.new(10 + math.cos(angle) * 12, h + 1.4, 6 + math.sin(angle) * 12), Color3.fromRGB(120, 140, 110), Enum.Material.Glass))
		DayNight.nightLight(beacon, Color3.fromRGB(120, 255, 120), Color3.fromRGB(120, 140, 110), "Glass")
	end
	part(clinic, "CrossPost", Vector3.new(0.6, 6, 0.6), frame * CFrame.new(-28, h + 3.5, front + 4.6), Color3.fromRGB(90, 90, 94), Enum.Material.Metal)
	deco(part(clinic, "CrossSign", Vector3.new(11, 11, 0.4), frame * CFrame.new(-28, h + 9, front + 4), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic))
	redCross(clinic, frame * CFrame.new(-28, h + 9, front + 3.7), 9)
	-- Inside: the reception desk, beds with curtains along the back wall.
	part(clinic, "Reception", Vector3.new(14, 4, 3), frame * CFrame.new(-16, 2, -8), Color3.fromRGB(220, 222, 226), Enum.Material.SmoothPlastic)
	for _, x in { -32, -22, 22, 32 } do
		local bed = frame * CFrame.new(x, 0, d / 2 - 7)
		part(clinic, "BedFrame", Vector3.new(4, 1.6, 8), bed * CFrame.new(0, 0.8, 0), Color3.fromRGB(150, 156, 160), Enum.Material.Metal)
		part(clinic, "Mattress", Vector3.new(3.8, 0.8, 7.6), bed * CFrame.new(0, 2, 0), Color3.fromRGB(245, 245, 248), Enum.Material.Fabric)
		part(clinic, "Pillow", Vector3.new(3, 0.6, 1.6), bed * CFrame.new(0, 2.7, 2.8), Color3.fromRGB(250, 250, 252), Enum.Material.Fabric)
		local curtain = deco(part(clinic, "Curtain", Vector3.new(0.2, 7, 9), bed * CFrame.new(-2.6, 4.2, 0), Color3.fromRGB(150, 200, 200), Enum.Material.Fabric))
		curtain.Transparency = 0.2
	end
	employerBoard(clinic, "clinic", facing)
	bystander("nurse", "Nurse Kim", "City Clinic", frame * CFrame.new(-8, 0, front - 6))
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
		-- The landmark's icon (shared/Icons.luau) in its kind's colour, or its emoji while the icon's id is empty.
		local art = Icons.get(Icons.landmark(landmark.id))
		if art then
			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(1, 0, 0.6, 0)
			icon.BackgroundTransparency = 1
			icon.Image = art
			icon.ScaleType = Enum.ScaleType.Fit
			icon.ImageColor3 = colors[landmark.kind] or Color3.new(1, 1, 1)
			icon.Parent = gui
		else
			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(1, 0, 0.6, 0)
			icon.BackgroundTransparency = 1
			icon.Text = landmark.icon
			icon.TextScaled = true
			icon.Parent = gui
		end
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
			elseif special == "bank" then
				buildBank(district, cx, cz)
				continue
			elseif special == "clinic" then
				buildClinic(district, cx, cz)
				continue
			elseif special == "dispatchtower" or special == "harborpoint" then
				buildTowerBlock(district, special, cx, cz)
				continue
			elseif special == "parking" then
				buildParking(district, cx, cz)
				continue
			elseif special == "lockup" then
				buildLockup(district, cx, cz)
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

-- A road that starts in the middle of another road (a T-junction): how far its centre line stays off that road.
local function junctionTrim(s: Map.Segment, x: number, z: number): number
	for _, o in Map.Segments do
		if o == s or (o.ax == x and o.az == z) or (o.bx == x and o.bz == z) then
			continue
		end
		local dx, dz = o.bx - o.ax, o.bz - o.az
		local length2 = dx * dx + dz * dz
		local t = if length2 > 0 then math.clamp(((x - o.ax) * dx + (z - o.az) * dz) / length2, 0, 1) else 0
		if (x - o.ax - dx * t) ^ 2 + (z - o.az - dz * t) ^ 2 < 0.01 then
			return o.width / 2 + 1
		end
	end
	return 0
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
		local trimA, trimB = junctionTrim(s, s.ax, s.az), junctionTrim(s, s.bx, s.bz)
		deco(part(roads, "Line", Vector3.new(0.6, 0.05, length - trimA - trimB), frame * CFrame.new(0, 0.02, (trimB - trimA) / 2), LINE))
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
					lamp(roads, p.X, p.Z, ROAD_TOP, frame.RightVector * -side, true)
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
	local lamp_ = deco(part(parent, "Searchlight", Vector3.new(1.5, 1.5, 1.5), CFrame.new(x, ROAD_TOP + 22, z), Color3.fromRGB(150, 150, 140), Enum.Material.Glass))
	light(lamp_, 50, 2, Color3.fromRGB(255, 250, 230))
	DayNight.nightLight(lamp_, Color3.fromRGB(255, 250, 220), Color3.fromRGB(150, 150, 140), "Glass")
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
		local sx, sz = cx + rng:NextNumber(-180, 180), cz + rng:NextNumber(-120, 160)
		local angle = rng:NextNumber(0, 3)
		if clearOfSpots(sx, sz, 22) then
			part(base, "Sandbags", Vector3.new(10, 3, 3), CFrame.new(sx, ROAD_TOP + 1.5, sz) * CFrame.Angles(0, angle, 0), Color3.fromRGB(170, 150, 110), Enum.Material.Fabric)
		end
		if n <= 5 then
			local wx, wz = cx + rng:NextNumber(-180, 180), cz + rng:NextNumber(-100, 160)
			local turn = rng:NextNumber(0, 6)
			if clearOfSpots(wx, wz, 26) then
				wreck(base, CFrame.new(wx, ROAD_TOP, wz) * CFrame.Angles(0, turn, 0), Color3.fromRGB(70, 84, 56))
			end
		end
	end
	-- The ammo bunker by the gate: Sergeant Hayes takes the crates here (Map.CargoSpots.base).
	local spot = Map.CargoSpots.base
	local px, pz = spot.pile.x, spot.pile.z
	local sand = Color3.fromRGB(170, 150, 110)
	part(base, "Sandbags", Vector3.new(3, 3.4, 16), CFrame.new(px - 9, ROAD_TOP + 1.7, pz - 2), sand, Enum.Material.Fabric)
	part(base, "Sandbags", Vector3.new(14, 3.4, 3), CFrame.new(px - 3, ROAD_TOP + 1.7, pz - 9), sand, Enum.Material.Fabric)
	local bunker = CFrame.lookAt(Vector3.new(px - 16, ROAD_TOP, pz - 14), Vector3.new(px, ROAD_TOP, pz))
	part(base, "Bunker", Vector3.new(12, 7, 10), bunker * CFrame.new(0, 3.5, 0), Color3.fromRGB(110, 112, 96), Enum.Material.Concrete)
	part(base, "BunkerDoor", Vector3.new(3.6, 5.4, 0.3), bunker * CFrame.new(0, 2.7, -5.1), Color3.fromRGB(60, 66, 50), Enum.Material.Metal)
	sign(base, "AMMO", Vector3.new(5, 1.4, 0.2), bunker * CFrame.new(0, 6, -5.2), Color3.fromRGB(255, 220, 90), Color3.fromRGB(50, 56, 40))
	palletStack(base, CFrame.new(px - 5, ROAD_TOP, pz + 9) * CFrame.Angles(0, 0.2, 0), Vector3.new(2.6, 1.4, 1.6), Color3.fromRGB(80, 92, 58), 2, 2, 2, Enum.Material.Metal)
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
	for _ = 1, 8 do
		local hx, hz, angle = cx + rng:NextNumber(-100, 100), cz + rng:NextNumber(0, 120), rng:NextNumber(0, 3)
		if clearOfSpots(hx, hz, 16) then
			cylinder(farm, "HayBale", 4, 5, CFrame.new(hx, ROAD_TOP + 2.5, hz) * CFrame.Angles(0, angle, 0), Color3.fromRGB(210, 180, 90), Enum.Material.Grass)
		end
	end
	-- The produce stand by the barn (Map.CargoSpots.farm): crates of vegetables waiting for the markets.
	local spot = Map.CargoSpots.farm
	local stand = CFrame.lookAt(Vector3.new(spot.pile.x - 9, ROAD_TOP, spot.pile.z - 7), Vector3.new(spot.park.x, ROAD_TOP, spot.park.z))
	part(farm, "StandTable", Vector3.new(10, 0.4, 4), stand * CFrame.new(0, 3, 0), Color3.fromRGB(140, 104, 66), Enum.Material.WoodPlanks)
	for _, x in { -4.6, 4.6 } do
		for _, z in { -1.6, 1.6 } do
			part(farm, "StandLeg", Vector3.new(0.4, 3, 0.4), stand * CFrame.new(x, 1.5, z), Color3.fromRGB(110, 80, 50), Enum.Material.Wood)
		end
	end
	for n, color in { Color3.fromRGB(190, 40, 36), Color3.fromRGB(110, 170, 70), Color3.fromRGB(230, 130, 30) } do
		local crate = stand * CFrame.new(-3.4 + (n - 1) * 3.4, 3.8, 0)
		part(farm, "Crate", Vector3.new(3, 1.2, 2.6), crate, Color3.fromRGB(170, 130, 84), Enum.Material.WoodPlanks)
		deco(part(farm, "Produce", Vector3.new(2.6, 0.5, 2.2), crate * CFrame.new(0, 0.7, 0), color, Enum.Material.Pebble))
	end
	sign(farm, "FRESH FOOD", Vector3.new(8, 1.6, 0.2), stand * CFrame.new(0, 6, 1.9), Color3.fromRGB(60, 40, 20), Color3.fromRGB(240, 220, 170))
	part(farm, "SignPost", Vector3.new(0.4, 5, 0.4), stand * CFrame.new(-3.6, 3.5, 2), Color3.fromRGB(110, 80, 50), Enum.Material.Wood)
	part(farm, "SignPost", Vector3.new(0.4, 5, 0.4), stand * CFrame.new(3.6, 3.5, 2), Color3.fromRGB(110, 80, 50), Enum.Material.Wood)
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
	-- Army ammo waiting on pallets by the loading spot (Map.CargoSpots.docks), Rocco's forklift next to it.
	local spot = Map.CargoSpots.docks
	local olive = Color3.fromRGB(80, 92, 58)
	palletStack(docks, CFrame.new(spot.pile.x + 9, ROAD_TOP, spot.pile.z + 12), Vector3.new(2.6, 1.4, 1.6), olive, 2, 3, 2, Enum.Material.Metal)
	palletStack(docks, CFrame.new(spot.pile.x + 10, ROAD_TOP, spot.pile.z - 10), Vector3.new(2.6, 1.4, 1.6), olive, 2, 3, 3, Enum.Material.Metal)
	local lift = CFrame.lookAt(Vector3.new(spot.pile.x + 6, ROAD_TOP, spot.pile.z + 26), Vector3.new(spot.pile.x + 6, ROAD_TOP, spot.pile.z))
	part(docks, "Forklift", Vector3.new(4, 3, 6), lift * CFrame.new(0, 2, 0), Color3.fromRGB(230, 170, 30), Enum.Material.Metal)
	part(docks, "ForkliftCage", Vector3.new(3.6, 3.4, 3.4), lift * CFrame.new(0, 5.2, 0.8), Color3.fromRGB(40, 40, 44), Enum.Material.Metal).Transparency = 0.5
	part(docks, "ForkliftMast", Vector3.new(3.6, 7, 0.5), lift * CFrame.new(0, 3.5, -3.2), Color3.fromRGB(50, 50, 54), Enum.Material.Metal)
	for _, x in { -1, 1 } do
		part(docks, "Fork", Vector3.new(0.4, 0.2, 3.4), lift * CFrame.new(x, 0.5, -5), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	end
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
	DayNight.nightLight(light(canopy, 40, 1.5, Color3.fromRGB(255, 240, 220)))
	for _, dz in { -9, 9 } do
		part(gas, "Pump", Vector3.new(2.5, 5, 4), CFrame.new(cx - 10, ROAD_TOP + 2.5, cz + dz), Color3.fromRGB(230, 230, 230), Enum.Material.Metal)
	end
	part(gas, "Shop", Vector3.new(26, 12, 30), CFrame.new(cx + 34, ROAD_TOP + 6, cz), Color3.fromRGB(200, 190, 170), Enum.Material.Concrete)
	sign(gas, "GAS", Vector3.new(14, 6, 0.5), CFrame.lookAt(Vector3.new(cx - 10, ROAD_TOP + 19, cz + 24.5), Vector3.new(cx - 10, ROAD_TOP + 19, cz + 30)), Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 40, 40))
	-- The underground tank's filler caps by the shop: the fuel barrels are emptied here (Map.CargoSpots.gas).
	local spot = Map.CargoSpots.gas
	for n = 0, 1 do
		local at = Vector3.new(spot.pile.x + 3 + n * 3, ROAD_TOP, spot.pile.z + 5)
		cylinder(gas, "FillerCap", 0.5, 1.6, CFrame.new(at + Vector3.new(0, 0.25, 0)) * UPRIGHT, Color3.fromRGB(230, 200, 40), Enum.Material.Metal)
	end
	part(gas, "FillerSignPost", Vector3.new(0.4, 5, 0.4), CFrame.new(spot.pile.x + 9, ROAD_TOP + 2.5, spot.pile.z + 6), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	sign(gas, "FUEL DELIVERY", Vector3.new(6, 1.4, 0.2), CFrame.lookAt(Vector3.new(spot.pile.x + 9, ROAD_TOP + 5, spot.pile.z + 5.8), Vector3.new(spot.pile.x + 9, ROAD_TOP + 5, spot.pile.z)), Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 40, 40))
	for n = 0, 2 do
		barrel(gas, Vector3.new(yard.x1 - 6, ROAD_TOP, yard.z0 + 6 + n * 2.6), Color3.fromRGB(70, 90, 130))
	end
	employerBoard(gas, "gas", Vector3.new(-1, 0, 0))
end

-- ── Silver Spur Ranch ──────────────────────────────────────────────────────
-- Off the West Highway down the Ranch Road: a gate with the ranch's name, the ranch house, the big red barn, the
-- stable with its stalls (the horses for the riding school are led out of here), the paddock with grazing horses.

local WOOD = Color3.fromRGB(116, 84, 56)
local WHITE_WOOD = Color3.fromRGB(228, 224, 212)

-- A stable: a row of stalls under a lean-to roof, open at the front (frame: floor centre, -Z = the open front).
local function stableRow(parent: Instance, frame: CFrame, stalls: number, stall: number, depth: number, color: Color3, trim: Color3): { CFrame }
	local w = stalls * stall
	local h = 11
	-- The roof slopes down to the front: h at the back wall, low at the front posts.
	local drop = 2.5
	local front = h - drop * depth / (depth + 4) -- the roof's underside over the front posts
	local slope = math.atan2(drop, depth + 4)
	part(parent, "StableFloor", Vector3.new(w, 0.2, depth), frame * CFrame.new(0, 0.1, 0), Color3.fromRGB(196, 170, 104), Enum.Material.Fabric)
	part(parent, "StableBack", Vector3.new(w, h, 1), frame * CFrame.new(0, h / 2, depth / 2 - 0.5), color, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		part(parent, "StableEnd", Vector3.new(1, front, depth), frame * CFrame.new(side * (w / 2 - 0.5), front / 2, 0), color, Enum.Material.WoodPlanks)
		part(parent, "StableGable", Vector3.new(1, h - front, depth), frame * CFrame.new(side * (w / 2 - 0.5), front + (h - front) / 2, 0), color, Enum.Material.WoodPlanks).Shape = Enum.PartType.Wedge
	end
	local roofZ = -1.5 -- 1 stud over the back wall, 4 over the front
	local roofY = h - drop * (depth / 2 - roofZ) / (depth + 4) + 0.3
	part(parent, "StableRoof", Vector3.new(w + 2, 0.6, depth + 5), frame * CFrame.new(0, roofY, roofZ) * CFrame.Angles(-slope, 0, 0), Color3.fromRGB(80, 70, 66), Enum.Material.CorrodedMetal)
	local spots: { CFrame } = {}
	for n = 0, stalls - 1 do
		local x = -w / 2 + (n + 0.5) * stall
		if n > 0 then
			part(parent, "StallWall", Vector3.new(0.5, 6, depth - 1), frame * CFrame.new(-w / 2 + n * stall, 3, -0.5), color:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.WoodPlanks)
		end
		part(parent, "Post", Vector3.new(0.8, front, 0.8), frame * CFrame.new(-w / 2 + n * stall, front / 2, -depth / 2), trim, Enum.Material.Wood)
		-- A half door (the middle stall stands open), a hay rack at the back.
		if n ~= math.floor(stalls / 2) then
			part(parent, "StallDoor", Vector3.new(stall - 1.2, 4.2, 0.4), frame * CFrame.new(x, 2.1, -depth / 2), color, Enum.Material.WoodPlanks)
			deco(part(parent, "DoorBrace", Vector3.new(0.3, 5.4, 0.1), frame * CFrame.new(x, 2.1, -depth / 2 - 0.25) * CFrame.Angles(0, 0, math.rad(48)), trim))
		end
		part(parent, "HayRack", Vector3.new(stall - 4, 1.6, 1.2), frame * CFrame.new(x, 4.6, depth / 2 - 1.6), Color3.fromRGB(214, 186, 100), Enum.Material.Grass)
		table.insert(spots, frame * CFrame.new(x, 0.2, 0))
	end
	part(parent, "Post", Vector3.new(0.8, front, 0.8), frame * CFrame.new(w / 2, front / 2, -depth / 2), trim, Enum.Material.Wood)
	part(parent, "Header", Vector3.new(w + 0.8, 0.8, 0.8), frame * CFrame.new(0, front - 0.4, -depth / 2), trim, Enum.Material.Wood)
	return spots
end

-- A water trough on its legs.
local function trough(parent: Instance, frame: CFrame)
	part(parent, "Trough", Vector3.new(8, 0.4, 3), frame * CFrame.new(0, 0.6, 0), Color3.fromRGB(120, 124, 128), Enum.Material.Metal)
	for _, side in { -1, 1 } do
		part(parent, "TroughSide", Vector3.new(8, 2, 0.3), frame * CFrame.new(0, 1.6, side * 1.35), Color3.fromRGB(120, 124, 128), Enum.Material.Metal)
		part(parent, "TroughEnd", Vector3.new(0.3, 2, 3), frame * CFrame.new(side * 3.85, 1.6, 0), Color3.fromRGB(120, 124, 128), Enum.Material.Metal)
	end
	local water = deco(part(parent, "Water", Vector3.new(7.4, 0.2, 2.4), frame * CFrame.new(0, 2.2, 0), Color3.fromRGB(70, 110, 130), Enum.Material.Glass))
	water.Transparency = 0.3
end

-- A gateway over a road: two log posts, a beam and the name hanging from it (facing: the way the sign looks).
local function gateway(parent: Instance, x: number, z: number, along: Vector3, facing: Vector3, text: string, color: Color3, background: Color3, span: number)
	local base = Vector3.new(x, ROAD_TOP, z)
	for _, side in { -1, 1 } do
		cylinder(parent, "GatePost", 20, 1.6, CFrame.new(base + along * side * span / 2 + Vector3.new(0, 10, 0)) * UPRIGHT, WOOD, Enum.Material.Wood)
	end
	local top = base + Vector3.new(0, 19.5, 0)
	part(parent, "GateBeam", Vector3.new(1.4, 1.4, span + 4), CFrame.lookAt(top, top + along), WOOD, Enum.Material.Wood)
	local board = top + Vector3.new(0, -3.4, 0)
	for _, side in { -1, 1 } do
		deco(part(parent, "Chain", Vector3.new(0.15, 2.4, 0.15), CFrame.new(board + along * side * 9 + Vector3.new(0, 1.9, 0)), Color3.fromRGB(60, 60, 60), Enum.Material.Metal))
	end
	sign(parent, text, Vector3.new(22, 3.6, 0.4), CFrame.lookAt(board + facing * 0.2, board + facing), color, background)
	sign(parent, text, Vector3.new(22, 3.6, 0.4), CFrame.lookAt(board - facing * 0.2, board - facing), color, background)
end

local function buildRanch(parent: Instance)
	local ranch = folder(parent, "SilverSpurRanch")
	local yard = yardOf("ranch")
	yardFloor(ranch, yard, Color3.fromRGB(128, 104, 74), Enum.Material.Ground)
	local cx = (yard.x0 + yard.x1) / 2

	-- The gate at the end of the Ranch Road, white fences along its last stretch.
	gateway(ranch, cx, yard.z0 - 12, Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), "SILVER SPUR RANCH", Color3.fromRGB(255, 226, 150), Color3.fromRGB(70, 46, 30), 46)
	for _, side in { -1, 1 } do
		fence(ranch, cx + side * 24, yard.z0 - 150, cx + side * 24, yard.z0 - 4, 0, 4, WHITE_WOOD, 2)
	end

	-- The ranch house with its porch, by the gate.
	local house = CFrame.lookAt(Vector3.new(yard.x0 + 34, ROAD_TOP, yard.z0 + 40), Vector3.new(yard.x0 + 60, ROAD_TOP, yard.z0 + 40))
	local hw, hd, hh = 28, 20, 11
	part(ranch, "House", Vector3.new(hw, hh, hd), house * CFrame.new(0, hh / 2, 0), WHITE_WOOD, Enum.Material.WoodPlanks)
	gableRoof(ranch, house * CFrame.new(0, hh, 0), hw + 3, hd + 3, 6, Color3.fromRGB(90, 60, 50))
	part(ranch, "Door", Vector3.new(4, 7, 0.4), house * CFrame.new(0, 3.5, -hd / 2 - 0.2), Color3.fromRGB(110, 60, 40), Enum.Material.Wood)
	for _, x in { -8, 8 } do
		nightWindow(deco(part(ranch, "Window", Vector3.new(4, 3.5, 0.3), house * CFrame.new(x, 6, -hd / 2 - 0.15), WINDOW_DIM, Enum.Material.Glass)), Color3.fromRGB(255, 210, 130))
	end
	part(ranch, "Porch", Vector3.new(hw - 4, 0.6, 6), house * CFrame.new(0, 0.3, -hd / 2 - 3), Color3.fromRGB(140, 104, 70), Enum.Material.WoodPlanks)
	part(ranch, "PorchRoof", Vector3.new(hw - 2, 0.5, 7), house * CFrame.new(0, 8.6, -hd / 2 - 3.2) * CFrame.Angles(math.rad(-8), 0, 0), Color3.fromRGB(90, 60, 50), Enum.Material.Slate)
	for _, x in { -(hw / 2 - 3), hw / 2 - 3 } do
		part(ranch, "PorchPost", Vector3.new(0.6, 8.4, 0.6), house * CFrame.new(x, 4.2, -hd / 2 - 6), WHITE_WOOD, Enum.Material.Wood)
	end
	part(ranch, "Chimney", Vector3.new(2.4, 7, 2.4), house * CFrame.new(hw / 2 - 4, hh + 4, 3), Color3.fromRGB(130, 80, 66), Enum.Material.Brick)
	lamp(ranch, yard.x0 + 60, yard.z0 + 14, ROAD_TOP)

	-- The big red barn on the west side, doors to the yard.
	local barn = CFrame.lookAt(Vector3.new(yard.x0 + 36, ROAD_TOP, yard.z0 + 122), Vector3.new(yard.x0 + 80, ROAD_TOP, yard.z0 + 122))
	local bw, bd, bh = 40, 30, 16
	local red = Color3.fromRGB(150, 40, 34)
	part(ranch, "Barn", Vector3.new(bw, bh, bd), barn * CFrame.new(0, bh / 2, 0), red, Enum.Material.WoodPlanks)
	-- The ridge runs front to back: the doors are under the gable.
	gableRoof(ranch, barn * CFrame.new(0, bh, 0) * CFrame.Angles(0, math.pi / 2, 0), bd + 3, bw + 3, 10, Color3.fromRGB(70, 64, 62))
	local front = -bd / 2 - 0.2
	part(ranch, "BarnDoor", Vector3.new(14, 12, 0.4), barn * CFrame.new(0, 6, front), red:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		deco(part(ranch, "DoorBrace", Vector3.new(0.6, 17.5, 0.2), barn * CFrame.new(side * 3.5, 6, front - 0.25) * CFrame.Angles(0, 0, side * math.rad(28)), WHITE_WOOD))
		deco(part(ranch, "DoorTrim", Vector3.new(0.8, 12, 0.2), barn * CFrame.new(side * 7, 6, front - 0.25), WHITE_WOOD))
	end
	deco(part(ranch, "DoorTrim", Vector3.new(14.8, 0.8, 0.2), barn * CFrame.new(0, 12, front - 0.25), WHITE_WOOD))
	part(ranch, "LoftDoor", Vector3.new(5, 4, 0.4), barn * CFrame.new(0, bh + 3, -(bd + 3) / 2 - 0.2), WHITE_WOOD, Enum.Material.WoodPlanks)
	-- Square hay bales stacked by the barn.
	for n = 0, 5 do
		local col, layer = n % 3, math.floor(n / 3)
		part(ranch, "HayBale", Vector3.new(4.2, 2.4, 2.6), barn * CFrame.new(bw / 2 + 4, 1.2 + layer * 2.4, -6 + col * 2.8) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(216, 186, 100), Enum.Material.Grass)
	end

	-- The stable on the east side: the job's horses come out here (Map.CargoSpots.ranch), two more look out.
	local stable = CFrame.lookAt(Vector3.new(yard.x1 - 20, ROAD_TOP, 800), Vector3.new(yard.x1 - 40, ROAD_TOP, 800))
	local stalls = stableRow(ranch, stable, 5, 12, 20, Color3.fromRGB(140, 96, 60), WHITE_WOOD)
	sign(ranch, "STABLE", Vector3.new(12, 2.4, 0.3), stable * CFrame.new(0, 10.6, -10.6), Color3.fromRGB(255, 226, 150), Color3.fromRGB(70, 46, 30))
	trough(ranch, CFrame.new(yard.x1 - 26, ROAD_TOP, 846) * CFrame.Angles(0, math.pi / 2, 0))
	for _, n in { 1, 5 } do
		local at = stalls[n] * CFrame.new(0, 0, -3.6)
		pcall(function()
			Animals.horse(CFrame.lookAt(at.Position, at.Position + stable.LookVector))
		end)
	end
	-- A saddle on a rail and a wheelbarrow by the stable.
	part(ranch, "Rail", Vector3.new(0.4, 0.4, 8), CFrame.new(yard.x1 - 32, ROAD_TOP + 3.4, 762), WOOD, Enum.Material.Wood)
	for _, z in { 759, 765 } do
		part(ranch, "RailLeg", Vector3.new(0.4, 3.4, 0.4), CFrame.new(yard.x1 - 32, ROAD_TOP + 1.7, z), WOOD, Enum.Material.Wood)
	end
	part(ranch, "Saddle", Vector3.new(2.2, 1, 2.6), CFrame.new(yard.x1 - 32, ROAD_TOP + 4, 762), Color3.fromRGB(110, 60, 30), Enum.Material.Leather)

	-- The paddock behind the yard: a three-rail fence, grass, a trough, a hay feeder and grazing horses.
	local paddock = Map.Clearings[1]
	deco(part(ranch, "Pasture", Vector3.new(paddock.x1 - paddock.x0, 0.1, paddock.z1 - paddock.z0), CFrame.new((paddock.x0 + paddock.x1) / 2, 0.05, (paddock.z0 + paddock.z1) / 2), Color3.fromRGB(86, 104, 58), Enum.Material.Grass))
	local px0, px1, pz0, pz1 = paddock.x0 + 2, paddock.x1 - 2, paddock.z0 + 2, paddock.z1 - 2
	fence(ranch, px0, pz0, cx - 12, pz0, 0, 4, WOOD, 3)
	fence(ranch, cx + 12, pz0, px1, pz0, 0, 4, WOOD, 3)
	fence(ranch, px0, pz0, px0, pz1, 0, 4, WOOD, 3)
	fence(ranch, px1, pz0, px1, pz1, 0, 4, WOOD, 3)
	fence(ranch, px0, pz1, px1, pz1, 0, 4, WOOD, 3)
	-- The closed paddock gate.
	part(ranch, "Gate", Vector3.new(24, 0.4, 0.3), CFrame.new(cx, 1.6, pz0), Color3.fromRGB(150, 150, 150), Enum.Material.Metal)
	part(ranch, "Gate", Vector3.new(24, 0.4, 0.3), CFrame.new(cx, 3.4, pz0), Color3.fromRGB(150, 150, 150), Enum.Material.Metal)
	trough(ranch, CFrame.new(px0 + 14, 0, pz0 + 16))
	cylinder(ranch, "HayFeeder", 3.6, 6, CFrame.new(cx + 40, 1.8, pz0 + 60) * UPRIGHT, Color3.fromRGB(210, 180, 96), Enum.Material.Grass)
	cylinder(ranch, "FeederRing", 0.6, 6.6, CFrame.new(cx + 40, 3.4, pz0 + 60) * UPRIGHT, Color3.fromRGB(70, 70, 74), Enum.Material.Metal)
	for n = 1, 3 do
		local hx, hz = rng:NextNumber(px0 + 20, px1 - 20), rng:NextNumber(pz0 + 20, pz1 - 20)
		local turn = rng:NextNumber(0, math.pi * 2)
		pcall(function()
			local horse = Animals.horse(CFrame.new(hx, 0, hz) * CFrame.Angles(0, turn, 0))
			if n > 1 then
				Animals.roam(horse, px0 + 8, pz0 + 8, px1 - 8, pz1 - 8)
			else
				horse:SetAttribute("Grazing", true)
			end
		end)
	end
	employerBoard(ranch, "ranch", Vector3.new(0, 0, -1))
end

-- ── Riverside Riding School ────────────────────────────────────────────────
-- Down Riding School Lane from the Suburbs, by the river: a clubhouse, a stable and the fenced sand arena.

local function buildStables(parent: Instance)
	local school = folder(parent, "RiversideRidingSchool")
	local yard = yardOf("stables")
	yardFloor(school, yard, Color3.fromRGB(150, 132, 100), Enum.Material.Ground)
	local laneZ = (yard.z0 + yard.z1) / 2
	for _, s in Map.Connectors do
		if s.name == "Riding School Lane" then
			laneZ = s.bz
		end
	end
	gateway(school, yard.x0 - 6, laneZ, Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), "RIVERSIDE RIDING SCHOOL", Color3.fromRGB(255, 255, 255), Color3.fromRGB(40, 90, 60), 42)

	-- The clubhouse in the north-west corner.
	local club = CFrame.lookAt(Vector3.new(yard.x0 + 22, ROAD_TOP, yard.z0 + 16), Vector3.new(yard.x0 + 22, ROAD_TOP, yard.z0 + 40))
	part(school, "Clubhouse", Vector3.new(28, 10, 18), club * CFrame.new(0, 5, 0), Color3.fromRGB(236, 232, 220), Enum.Material.WoodPlanks)
	gableRoof(school, club * CFrame.new(0, 10, 0), 31, 21, 5, Color3.fromRGB(50, 96, 64))
	part(school, "Door", Vector3.new(4, 7, 0.4), club * CFrame.new(0, 3.5, -9.2), Color3.fromRGB(50, 96, 64), Enum.Material.Wood)
	for _, x in { -8, 8 } do
		nightWindow(deco(part(school, "Window", Vector3.new(4.5, 3, 0.3), club * CFrame.new(x, 5.5, -9.15), WINDOW_DIM, Enum.Material.Glass)), Color3.fromRGB(255, 214, 140))
	end
	sign(school, "RIDING SCHOOL", Vector3.new(14, 2.2, 0.3), club * CFrame.new(0, 8.6, -9.4), Color3.fromRGB(255, 255, 255), Color3.fromRGB(40, 90, 60))

	-- The stable along the north side, open to the south: Emma takes the horses in here (Map.CargoSpots.stables).
	local stable = CFrame.lookAt(Vector3.new(yard.x0 + 110, ROAD_TOP, yard.z0 + 12), Vector3.new(yard.x0 + 110, ROAD_TOP, yard.z0 + 40))
	local stalls = stableRow(school, stable, 5, 13, 20, Color3.fromRGB(110, 76, 50), Color3.fromRGB(236, 232, 220))
	pcall(function()
		local at = stalls[2] * CFrame.new(0, 0, -3.6)
		Animals.horse(CFrame.lookAt(at.Position, at.Position + stable.LookVector))
	end)
	trough(school, CFrame.new(yard.x1 - 14, ROAD_TOP, yard.z0 + 44) * CFrame.Angles(0, math.pi / 2, 0))
	lamp(school, yard.x0 + 50, yard.z0 + 44, ROAD_TOP)
	lamp(school, yard.x1 - 10, yard.z1 - 10, ROAD_TOP)

	-- The arena south of the yard: sand, a white two-rail fence with a gap to the yard, two show jumps.
	local arena = Map.Clearings[2]
	local ax0, ax1, az0, az1 = arena.x0 + 5, arena.x1 - 8, arena.z0 + 8, arena.z1 - 6
	part(school, "ArenaSand", Vector3.new(ax1 - ax0, 0.2, az1 - az0), CFrame.new((ax0 + ax1) / 2, 0.1, (az0 + az1) / 2), Color3.fromRGB(214, 194, 150), Enum.Material.Sand)
	local gapX = (ax0 + ax1) / 2
	fence(school, ax0, az0, gapX - 8, az0, 0, 4, WHITE_WOOD, 2)
	fence(school, gapX + 8, az0, ax1, az0, 0, 4, WHITE_WOOD, 2)
	fence(school, ax0, az0, ax0, az1, 0, 4, WHITE_WOOD, 2)
	fence(school, ax1, az0, ax1, az1, 0, 4, WHITE_WOOD, 2)
	fence(school, ax0, az1, ax1, az1, 0, 4, WHITE_WOOD, 2)
	for _, jump in { { ax0 + 30, (az0 + az1) / 2 }, { ax1 - 30, az0 + 40 } } do
		local frame = CFrame.new(jump[1], 0.2, jump[2])
		for _, side in { -1, 1 } do
			part(school, "JumpStand", Vector3.new(0.6, 4.4, 1.2), frame * CFrame.new(side * 5, 2.2, 0), WHITE_WOOD, Enum.Material.Wood)
		end
		for n, y in { 1.6, 3.2 } do
			part(school, "JumpPole", Vector3.new(10, 0.35, 0.35), frame * CFrame.new(0, y, 0), if n == 1 then Color3.fromRGB(200, 40, 40) else Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic)
		end
	end
	pcall(function()
		local horse = Animals.horse(CFrame.new(ax0 + 30, 0.2, az1 - 30))
		Animals.roam(horse, ax0 + 8, az0 + 8, ax1 - 8, az1 - 8)
	end)
	-- Willows along the river bank.
	for z = yard.z0 + 10, arena.z1, 34 do
		tree(school, Map.River.x0 - 9, z, 0)
	end
end

-- ── Harbor Fuel Depot ──────────────────────────────────────────────────────
-- South of the Harbor warehouses: the storage tanks in their bund wall, pipes to the loading shed where the fuel
-- barrels wait (Map.CargoSpots.fueldepot), the office and a fence along the water.

local function buildFuelDepot(parent: Instance)
	local depot = folder(parent, "HarborFuelDepot")
	local yard = yardOf("fueldepot")
	yardFloor(depot, yard, Color3.fromRGB(112, 112, 108), Enum.Material.Concrete)
	local tankColor = Color3.fromRGB(214, 214, 208)
	local red = Color3.fromRGB(190, 44, 36)
	local steel = Color3.fromRGB(150, 150, 154)

	-- The tanks in their bund wall; every tank's outlet runs to the manifold in front of the wall.
	local tankZ = yard.z1 - 48
	local bx0, bx1, bz0, bz1 = yard.x0 + 14, yard.x0 + 252, tankZ - 26, yard.z1 - 6
	local manifoldZ = bz0 - 3
	local tanks = { { x = yard.x0 + 42, d = 40, h = 30, label = "DIESEL" }, { x = yard.x0 + 106, d = 40, h = 30, label = "GASOLINE" }, { x = yard.x0 + 170, d = 40, h = 30, label = "DIESEL" }, { x = yard.x0 + 230, d = 26, h = 22, label = "KEROSENE" } }
	for _, t in tanks do
		local base = Vector3.new(t.x, ROAD_TOP, tankZ)
		cylinder(depot, "Tank", t.h, t.d, CFrame.new(base + Vector3.new(0, t.h / 2, 0)) * UPRIGHT, tankColor, Enum.Material.Metal)
		cylinder(depot, "TankStripe", 2, t.d + 0.3, CFrame.new(base + Vector3.new(0, t.h * 0.72, 0)) * UPRIGHT, red, Enum.Material.Metal)
		local roof = part(depot, "TankRoof", Vector3.new(t.d + 0.6, 4, t.d + 0.6), CFrame.new(base + Vector3.new(0, t.h, 0)), tankColor, Enum.Material.Metal)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = roof
		local label = base + Vector3.new(0, t.h * 0.45, -t.d / 2 - 0.3)
		sign(depot, t.label, Vector3.new(t.d * 0.45, t.d * 0.12, 0.2), CFrame.lookAt(label, label + Vector3.new(0, 0, -1)), red, tankColor)
		-- A ladder up the side.
		local lx = t.x + t.d / 2 + 0.6
		for _, dz in { -0.8, 0.8 } do
			part(depot, "LadderRail", Vector3.new(0.2, t.h, 0.2), CFrame.new(lx, ROAD_TOP + t.h / 2, tankZ + dz), steel, Enum.Material.Metal)
		end
		for y = 2, t.h - 1, 3 do
			deco(part(depot, "Rung", Vector3.new(0.2, 0.2, 1.6), CFrame.new(lx, ROAD_TOP + y, tankZ), steel, Enum.Material.Metal))
		end
		local face = tankZ - t.d / 2
		cylinder(depot, "Pipe", face - manifoldZ + 0.6, 1.2, CFrame.new(t.x, ROAD_TOP + 2, (face + manifoldZ) / 2) * CFrame.Angles(0, math.pi / 2, 0), steel, Enum.Material.Metal)
	end
	local concrete = Color3.fromRGB(150, 148, 140)
	part(depot, "BundWall", Vector3.new(bx1 - bx0, 3, 1), CFrame.new((bx0 + bx1) / 2, ROAD_TOP + 1.5, bz0), concrete, Enum.Material.Concrete)
	part(depot, "BundWall", Vector3.new(bx1 - bx0, 3, 1), CFrame.new((bx0 + bx1) / 2, ROAD_TOP + 1.5, bz1), concrete, Enum.Material.Concrete)
	part(depot, "BundWall", Vector3.new(1, 3, bz1 - bz0), CFrame.new(bx0, ROAD_TOP + 1.5, (bz0 + bz1) / 2), concrete, Enum.Material.Concrete)
	part(depot, "BundWall", Vector3.new(1, 3, bz1 - bz0), CFrame.new(bx1, ROAD_TOP + 1.5, (bz0 + bz1) / 2), concrete, Enum.Material.Concrete)

	-- The manifold along the wall and the line to the loading shed, on little supports.
	local spot = Map.CargoSpots.fueldepot
	-- The shed's posts stand well away from the park circle (the pile is just inside its west edge).
	local shedX, shedZ = spot.pile.x + 8, spot.pile.z + 4
	local lineX = shedX + 14
	local mx0, mx1 = tanks[1].x, math.max(tanks[#tanks].x, lineX)
	cylinder(depot, "Manifold", mx1 - mx0, 1.4, CFrame.new((mx0 + mx1) / 2, ROAD_TOP + 2, manifoldZ), steel, Enum.Material.Metal)
	for x = mx0, mx1, 20 do
		part(depot, "PipeSupport", Vector3.new(0.6, 1.4, 1.6), CFrame.new(x, ROAD_TOP + 0.7, manifoldZ), Color3.fromRGB(90, 90, 94), Enum.Material.Metal)
	end
	cylinder(depot, "Pipe", manifoldZ - shedZ - 12, 1.2, CFrame.new(lineX, ROAD_TOP + 2, (manifoldZ + shedZ + 12) / 2) * CFrame.Angles(0, math.pi / 2, 0), steel, Enum.Material.Metal)
	cylinder(depot, "Riser", 12, 1.2, CFrame.new(lineX, ROAD_TOP + 8, shedZ + 12) * UPRIGHT, steel, Enum.Material.Metal)
	for _, z in { manifoldZ - 1, (manifoldZ + shedZ) / 2 + 6 } do
		local valve = cylinder(depot, "Valve", 0.4, 2.4, CFrame.new(lineX, ROAD_TOP + 3.4, z) * UPRIGHT, red, Enum.Material.Metal)
		valve.CanCollide = false
	end

	-- The loading shed over the barrel spot.
	local shed = CFrame.new(shedX, ROAD_TOP, shedZ)
	for _, x in { -12, 12 } do
		for _, z in { -11, 11 } do
			part(depot, "ShedPost", Vector3.new(0.8, 12, 0.8), shed * CFrame.new(x, 6, z), Color3.fromRGB(230, 180, 40), Enum.Material.Metal)
		end
	end
	local roof = part(depot, "ShedRoof", Vector3.new(27, 0.8, 26), shed * CFrame.new(0, 12.4, 0), Color3.fromRGB(70, 74, 80), Enum.Material.CorrodedMetal)
	DayNight.nightLight(light(roof, 34, 1.4, Color3.fromRGB(255, 236, 200)))
	sign(depot, "BARREL LOADING", Vector3.new(14, 2, 0.3), shed * CFrame.new(0, 11, -13.2) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(30, 30, 30), Color3.fromRGB(240, 200, 50))
	-- Full barrels on pallets at the back of the shed, empty ones by the wall.
	local colors = { Color3.fromRGB(190, 44, 36), Color3.fromRGB(40, 80, 150), Color3.fromRGB(220, 170, 40) }
	for n, offset in { Vector3.new(8, 0, 8), Vector3.new(-2, 0, 9), Vector3.new(9, 0, -2) } do
		local base = Vector3.new(shedX, ROAD_TOP, shedZ) + offset
		part(depot, "Pallet", Vector3.new(5.4, 0.5, 5.4), CFrame.new(base + Vector3.new(0, 0.25, 0)), Color3.fromRGB(150, 116, 74), Enum.Material.WoodPlanks)
		for _, dx in { -1.3, 1.3 } do
			for _, dz in { -1.3, 1.3 } do
				barrel(depot, base + Vector3.new(dx, 0.5, dz), colors[n])
			end
		end
	end

	-- The office by the entrance, a sign on the road, a fence along the water and the back.
	local office = CFrame.lookAt(Vector3.new(yard.x0 + 22, ROAD_TOP, yard.z0 + 26), Vector3.new(yard.x0 + 22, ROAD_TOP, yard.z0))
	part(depot, "Office", Vector3.new(24, 9, 14), office * CFrame.new(0, 4.5, 0), Color3.fromRGB(220, 220, 214), Enum.Material.Metal)
	part(depot, "OfficeRoof", Vector3.new(25, 0.6, 15), office * CFrame.new(0, 9.3, 0), Color3.fromRGB(90, 94, 100), Enum.Material.Metal)
	part(depot, "Door", Vector3.new(3.6, 7, 0.3), office * CFrame.new(-6, 3.5, -7.1), Color3.fromRGB(70, 90, 120), Enum.Material.Metal)
	nightWindow(deco(part(depot, "Window", Vector3.new(8, 3, 0.3), office * CFrame.new(4, 5, -7.1), WINDOW_DIM, Enum.Material.Glass)), Color3.fromRGB(255, 220, 150))
	placeSign(depot, "HARBOR FUEL DEPOT", yard.x0 + 70, yard.z0 + 6, Vector3.new(0, 0, -1), Color3.fromRGB(255, 210, 80))
	sign(depot, "NO SMOKING", Vector3.new(6, 2, 0.2), CFrame.lookAt(Vector3.new((bx0 + bx1) / 2, ROAD_TOP + 4.6, bz0 - 0.6), Vector3.new((bx0 + bx1) / 2, ROAD_TOP + 4.6, bz0 - 10)), Color3.fromRGB(255, 255, 255), red)
	local wire = Color3.fromRGB(110, 114, 118)
	for _, run in { { yard.x0, yard.z1, yard.x1, yard.z1 }, { yard.x1, yard.z0 + 30, yard.x1, yard.z1 }, { yard.x0, yard.z0 + 50, yard.x0, yard.z1 } } do
		local a, b = Vector3.new(run[1], ROAD_TOP, run[2]), Vector3.new(run[3], ROAD_TOP, run[4])
		local length = (b - a).Magnitude
		local mesh = part(depot, "ChainLink", Vector3.new(0.2, 7, length), CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, 3.5, 0), wire, Enum.Material.Metal)
		mesh.Transparency = 0.65
		local posts = math.floor(length / 16)
		for n = 0, posts do
			local p = a:Lerp(b, n / posts)
			part(depot, "FencePost", Vector3.new(0.4, 7.6, 0.4), CFrame.new(p + Vector3.new(0, 3.8, 0)), wire, Enum.Material.Metal)
		end
	end
	lamp(depot, yard.x0 + 60, yard.z0 + 40, ROAD_TOP)
	lamp(depot, yard.x1 - 30, yard.z0 + 40, ROAD_TOP)
end

local function cabin(parent: Instance, frame: CFrame, w: number, d: number, h: number)
	part(parent, "Cabin", Vector3.new(w, h, d), frame * CFrame.new(0, h / 2, 0), Color3.fromRGB(120, 80, 50), Enum.Material.WoodPlanks)
	gableRoof(parent, frame * CFrame.new(0, h, 0), w + 3, d + 3, h * 0.6, Color3.fromRGB(240, 244, 248))
	part(parent, "Door", Vector3.new(4, 7, 0.4), frame * CFrame.new(0, 3.5, -d / 2 - 0.2), Color3.fromRGB(80, 50, 30), Enum.Material.Wood)
	for _, x in { -w / 3, w / 3 } do
		local window = deco(part(parent, "Window", Vector3.new(4, 3, 0.3), frame * CFrame.new(x, h * 0.55, -d / 2 - 0.15), WINDOW_DIM, Enum.Material.Glass))
		light(window, 18, 1, Color3.fromRGB(255, 190, 110))
		nightWindow(window, Color3.fromRGB(255, 200, 110))
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

-- ── Real estate (Zombie Delivery 2.6) ──────────────────────────────────────
-- The properties of Config.Estate where Map.EstatePlots puts them, spread over the map: the Hilltop Mansion in Sunset
-- Hills above the city, Ocean View on the sea cliffs north of the Harbor, Pinecrest in the western pines, the Lakeside
-- Villa by the frozen lake (in the snow), the Sunset Villa down its quiet lane in the west, the houses on their
-- Suburbs lots and Birch Cottage at the edge of town, the three garages, the offices in Dispatch Tower and Harbor
-- Point. Every building has a simple walkable inside (rooms with doorways, furniture, lights; a staircase in the
-- mansions), a garage for its cars, a FOR SALE sign with an "EstatePrompt" (World.EstatePrompts), the spawn inside the
-- front door (World.EstateSpawns) and the spot in front of the garage where a car comes out (World.EstateGarages).
-- The towers' floors are joined by elevator pads (step on one: you ride to the floor written over it); every office
-- has its computer with an "OfficePrompt" (World.OfficePrompts) and its spawn in front of the elevators.
--
-- The buildings are drawn in a local frame (CFrame.lookAt from the plot's centre on the ground toward its front):
-- +X is the right of somebody looking out of the front door, -Z the front, +Z the back (Map.plotPoint's frame).
--
-- The builders live in their own function (defineRealEstate, run right after it): the main chunk of this file has
-- many locals already and Luau allows 200 per function.

local buildSunsetHills: (Instance) -> ()
local buildEstate: (Instance) -> ()
local nearAnyLot: (number, number, number) -> boolean

local function defineRealEstate()
	local ESTATE: { [string]: Config.EstateDef } = {}
	for _, def in Config.Estate.Properties do
		ESTATE[def.id] = def
	end
	local estateRng = Random.new(Config.City.Seed + 26) -- the estate's own dice (the rest of the world keeps its own)
	local GARAGE_APRON = Map.GarageApron
	local PAD_TOP = ROAD_TOP + 0.05 -- the lots outside the blocks: a grass pad just over the road

	-- "$6,000,000"
	local function dollars(amount: number): string
		local digits = tostring(math.floor(amount))
		local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
		if string.sub(grouped, 1, 1) == "," then
			grouped = string.sub(grouped, 2)
		end
		return "$" .. grouped
	end

	-- Builds one property and only warns if it fails (the rest of the world goes on).
	local function attempt(what: string, build: () -> ())
		local ok, err = pcall(function()
			build()
		end)
		if not ok then
			warn(`[World] {what} failed: {err}`)
		end
	end

	local function plotFrame(plot: Map.EstatePlot, y: number): CFrame
		local origin = Vector3.new(plot.x, y, plot.z)
		return CFrame.lookAt(origin, origin + Vector3.new(plot.facing.x, 0, plot.facing.z))
	end

	-- How far the road is in front of the front wall (a plot faces its road): the driveway's length.
	local function frontReach(plot: Map.EstatePlot): number
		for k = 0, 60 do
			local x, z = Map.plotPoint(plot, 0, -plot.front - k)
			if Map.onRoad(x, z) then
				return k
			end
		end
		return 12
	end

	-- A box in a local frame f, between two corners.
	local function box(parent: Instance, name: string, f: CFrame, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, color: Color3, material: Enum.Material?): Part
		return part(parent, name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), f * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material)
	end

	type Opening = { at: number, width: number, bottom: number, top: number, glass: boolean? }

	local GLASS = Color3.fromRGB(160, 200, 220)

	-- A straight wall in f: along X (at z = `at`, from a0 to a1) or along Z (at x = `at`), from y0 to y1, `thick` thick,
	-- with openings (doorways; windows get a pane of glass). The openings' bottom and top are above y0.
	local function wall(parent: Instance, f: CFrame, alongX: boolean, a0: number, a1: number, at: number, y0: number, y1: number, openings: { Opening }?, color: Color3, material: Enum.Material?, thick: number?, lit: boolean?)
		local t = thick or 1
		local function piece(name: string, s0: number, s1: number, b: number, top: number, depth: number): Part?
			if s1 - s0 < 0.05 or top - b < 0.05 then
				return nil
			end
			if alongX then
				return box(parent, name, f, s0, b, at - depth / 2, s1, top, at + depth / 2, color, material)
			end
			return box(parent, name, f, at - depth / 2, b, s0, at + depth / 2, top, s1, color, material)
		end
		local list = table.clone(openings or {})
		table.sort(list, function(p: Opening, q: Opening)
			return p.at < q.at
		end)
		local cursor = a0
		for _, o in list do
			local s0, s1 = o.at - o.width / 2, o.at + o.width / 2
			piece("Wall", cursor, s0, y0, y1, t)
			piece("Wall", s0, s1, y0, y0 + o.bottom, t)
			piece("Wall", s0, s1, y0 + o.top, y1, t)
			if o.glass then
				local pane = piece("Window", s0, s1, y0 + o.bottom, y0 + o.top, 0.3)
				if pane then
					pane.Color = GLASS
					pane.Material = Enum.Material.Glass
					pane.Transparency = 0.5
					if lit then
						DayNight.nightLight(pane, Color3.fromRGB(255, 214, 140), GLASS, "Glass")
					end
				end
			end
			cursor = s1
		end
		piece("Wall", cursor, a1, y0, y1, t)
	end

	-- A floor slab (top at `top`, `thick` thick) over a rectangle, with a hole cut out (a stairwell).
	local function slabWithHole(parent: Instance, f: CFrame, x0: number, z0: number, x1: number, z1: number, top: number, thick: number, hx0: number, hz0: number, hx1: number, hz1: number, color: Color3, material: Enum.Material)
		local y0 = top - thick
		box(parent, "Floor", f, x0, y0, z0, hx0, top, z1, color, material)
		box(parent, "Floor", f, hx1, y0, z0, x1, top, z1, color, material)
		box(parent, "Floor", f, hx0, y0, z0, hx1, top, hz0, color, material)
		box(parent, "Floor", f, hx0, y0, hz1, hx1, top, z1, color, material)
	end

	-- Steps along +Z from z0, from floor y0 up to y1 (1 stud or less each), `width` wide around x.
	local function stairs(parent: Instance, f: CFrame, x: number, z0: number, y0: number, y1: number, width: number, run: number, color: Color3)
		local count = math.ceil((y1 - y0) / 0.95)
		local rise = (y1 - y0) / count
		for k = 1, count do
			box(parent, "Step", f, x - width / 2, y0, z0 + (k - 1) * run, x + width / 2, y0 + k * rise, z0 + k * run, color, Enum.Material.WoodPlanks)
		end
	end

	-- A light panel in the ceiling (always on, like the shops').
	local function ceilingLight(parent: Instance, f: CFrame, x: number, y: number, z: number, range: number)
		local panel = deco(part(parent, "CeilingLight", Vector3.new(3, 0.2, 3), f * CFrame.new(x, y - 0.1, z), Color3.fromRGB(255, 244, 220), Enum.Material.Neon))
		light(panel, range, 0.9, Color3.fromRGB(255, 236, 205))
	end

	-- ── Furniture: `cf` stands on the floor, the piece's front looks along cf.LookVector ────────────────────────────

	local function sofa(parent: Instance, cf: CFrame, color: Color3, length: number?)
		local w = length or 8
		part(parent, "Sofa", Vector3.new(w, 1.8, 3.2), cf * CFrame.new(0, 0.9, 0), color, Enum.Material.Fabric)
		part(parent, "SofaBack", Vector3.new(w, 2.4, 0.8), cf * CFrame.new(0, 2.4, 1.2), color, Enum.Material.Fabric)
		for _, side in { -1, 1 } do
			part(parent, "SofaArm", Vector3.new(0.8, 2.6, 3.2), cf * CFrame.new(side * (w / 2 - 0.4), 1.3, 0), color:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Fabric)
		end
	end

	local function bed(parent: Instance, cf: CFrame, blanket: Color3)
		-- the head at the back (+Z), you get in from the front
		part(parent, "BedFrame", Vector3.new(6, 1.4, 9), cf * CFrame.new(0, 0.7, 0), Color3.fromRGB(110, 80, 56), Enum.Material.Wood)
		part(parent, "Mattress", Vector3.new(5.6, 0.8, 8.4), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(236, 234, 228), Enum.Material.Fabric)
		deco(part(parent, "Blanket", Vector3.new(5.8, 0.2, 5), cf * CFrame.new(0, 2.25, -1.6), blanket, Enum.Material.Fabric))
		deco(part(parent, "Pillow", Vector3.new(4, 0.5, 1.4), cf * CFrame.new(0, 2.45, 3.2), Color3.fromRGB(250, 250, 248), Enum.Material.Fabric))
		part(parent, "Headboard", Vector3.new(6.4, 4.4, 0.6), cf * CFrame.new(0, 2.2, 4.7), Color3.fromRGB(90, 64, 46), Enum.Material.Wood)
	end

	local function diningSet(parent: Instance, cf: CFrame, length: number, wood: Color3)
		part(parent, "Table", Vector3.new(length, 0.4, 4), cf * CFrame.new(0, 3, 0), wood, Enum.Material.Wood)
		part(parent, "TableLeg", Vector3.new(length - 2, 2.8, 1), cf * CFrame.new(0, 1.4, 0), wood:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Wood)
		local seats = math.max(1, math.floor(length / 4))
		for n = 1, seats do
			local x = (n - (seats + 1) / 2) * 3.6
			for _, side in { -1, 1 } do
				local chair = cf * CFrame.new(x, 0, side * 3.2)
				part(parent, "Chair", Vector3.new(2, 0.4, 2), chair * CFrame.new(0, 1.9, 0), wood, Enum.Material.Wood)
				part(parent, "ChairBack", Vector3.new(2, 2.4, 0.3), chair * CFrame.new(0, 3.1, side * 0.9), wood, Enum.Material.Wood)
			end
		end
	end

	local function kitchen(parent: Instance, cf: CFrame, length: number, top: Color3)
		-- a counter row (the cook stands in front), the fridge at its right end
		part(parent, "Counter", Vector3.new(length, 3.6, 2.6), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(236, 236, 232), Enum.Material.SmoothPlastic)
		part(parent, "Worktop", Vector3.new(length + 0.2, 0.3, 2.8), cf * CFrame.new(0, 3.75, 0), top, Enum.Material.Marble)
		deco(part(parent, "Hob", Vector3.new(2.4, 0.08, 1.8), cf * CFrame.new(-length / 4, 3.94, 0), Color3.fromRGB(24, 24, 26), Enum.Material.Glass))
		deco(part(parent, "Sink", Vector3.new(2.2, 0.08, 1.6), cf * CFrame.new(length / 4, 3.94, 0), Color3.fromRGB(170, 176, 182), Enum.Material.Metal))
		part(parent, "Fridge", Vector3.new(3, 7, 2.6), cf * CFrame.new(length / 2 + 1.6, 3.5, 0), Color3.fromRGB(210, 214, 218), Enum.Material.Metal)
	end

	local function tv(parent: Instance, cf: CFrame)
		part(parent, "TvStand", Vector3.new(6, 1.8, 1.6), cf * CFrame.new(0, 0.9, 0), Color3.fromRGB(50, 44, 40), Enum.Material.Wood)
		local screen = part(parent, "Tv", Vector3.new(5.4, 3.2, 0.3), cf * CFrame.new(0, 3.6, 0.3), Color3.fromRGB(16, 18, 22), Enum.Material.Glass)
		screen.Reflectance = 0.1
	end

	local function plant(parent: Instance, cf: CFrame, size: number?)
		local s = size or 1
		cylinder(parent, "Pot", 1.6 * s, 1.6 * s, cf * CFrame.new(0, 0.8 * s, 0) * UPRIGHT, Color3.fromRGB(170, 110, 80), Enum.Material.Slate)
		local leaves = deco(part(parent, "Leaves", Vector3.new(2.8, 3.2, 2.8) * s, cf * CFrame.new(0, 3 * s, 0), Color3.fromRGB(64, 120, 58), Enum.Material.Grass))
		leaves.Shape = Enum.PartType.Ball
	end

	local function bookshelf(parent: Instance, cf: CFrame)
		part(parent, "Bookshelf", Vector3.new(5, 7, 1.4), cf * CFrame.new(0, 3.5, 0.2), Color3.fromRGB(120, 86, 58), Enum.Material.Wood)
		for row = 0, 2 do
			deco(part(parent, "Books", Vector3.new(4.4, 1.3, 0.2), cf * CFrame.new(0, 1.4 + row * 2, -0.55), Color3.fromHSV(estateRng:NextNumber(), 0.45, 0.6), Enum.Material.SmoothPlastic))
		end
	end

	local function rug(parent: Instance, cf: CFrame, w: number, d: number, color: Color3)
		deco(part(parent, "Rug", Vector3.new(w, 0.06, d), cf * CFrame.new(0, 0.03, 0), color, Enum.Material.Fabric))
	end

	local function coffeeTable(parent: Instance, cf: CFrame)
		part(parent, "CoffeeTable", Vector3.new(4, 0.3, 2.4), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(90, 66, 48), Enum.Material.Wood)
		part(parent, "CoffeeTableBase", Vector3.new(3, 1.35, 1.6), cf * CFrame.new(0, 0.68, 0), Color3.fromRGB(70, 52, 38), Enum.Material.Wood)
	end

	local function bathroom(parent: Instance, tub: CFrame, toilet: CFrame, sink: CFrame)
		local white = Color3.fromRGB(240, 242, 244)
		part(parent, "Bathtub", Vector3.new(3.6, 2.2, 6.4), tub * CFrame.new(0, 1.1, 0), white, Enum.Material.SmoothPlastic)
		deco(part(parent, "BathWater", Vector3.new(2.8, 0.1, 5.6), tub * CFrame.new(0, 2, 0), Color3.fromRGB(150, 200, 230), Enum.Material.Glass)).Transparency = 0.3
		part(parent, "Toilet", Vector3.new(1.6, 1.6, 2.2), toilet * CFrame.new(0, 0.8, 0), white, Enum.Material.SmoothPlastic)
		part(parent, "ToiletTank", Vector3.new(1.8, 2, 0.8), toilet * CFrame.new(0, 2, 1.2), white, Enum.Material.SmoothPlastic)
		part(parent, "Washbasin", Vector3.new(2.6, 3, 1.8), sink * CFrame.new(0, 1.5, 0), white, Enum.Material.Marble)
		deco(part(parent, "Mirror", Vector3.new(2.4, 2.4, 0.1), sink * CFrame.new(0, 5, 0.95), Color3.fromRGB(200, 220, 230), Enum.Material.Glass)).Reflectance = 0.4
	end

	local function lounger(parent: Instance, cf: CFrame)
		part(parent, "Lounger", Vector3.new(2.4, 0.6, 6), cf * CFrame.new(0, 0.9, 0), Color3.fromRGB(240, 240, 236), Enum.Material.Fabric)
		part(parent, "LoungerBack", Vector3.new(2.4, 0.4, 2.4), cf * CFrame.new(0, 1.6, 2.2) * CFrame.Angles(math.rad(35), 0, 0), Color3.fromRGB(240, 240, 236), Enum.Material.Fabric)
		part(parent, "LoungerBase", Vector3.new(2, 0.6, 5), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(150, 120, 90), Enum.Material.Wood)
	end

	local function parasol(parent: Instance, cf: CFrame, color: Color3)
		part(parent, "ParasolPole", Vector3.new(0.3, 8, 0.3), cf * CFrame.new(0, 4, 0), Color3.fromRGB(220, 220, 220), Enum.Material.Metal)
		deco(cylinder(parent, "Parasol", 0.4, 8, cf * CFrame.new(0, 8, 0) * UPRIGHT, color, Enum.Material.Fabric))
	end

	-- A palm tree (Sunset Hills, by the pools and the sea).
	local function palm(parent: Instance, x: number, z: number, y: number)
		local height = estateRng:NextNumber(14, 20)
		local lean = estateRng:NextNumber(-0.15, 0.15)
		local top = Vector3.new(x + lean * height, y + height, z + lean * height * 0.5)
		local foot = Vector3.new(x, y, z)
		part(parent, "PalmTrunk", Vector3.new(1.2, 1.2, height), CFrame.lookAt((foot + top) / 2, top), Color3.fromRGB(130, 104, 74), Enum.Material.Wood)
		for n = 0, 5 do
			local angle = n * math.pi / 3 + estateRng:NextNumber(-0.2, 0.2)
			local dir = Vector3.new(math.cos(angle), -0.35, math.sin(angle))
			deco(part(parent, "PalmLeaf", Vector3.new(2.4, 0.2, 8), CFrame.lookAt(top + dir * 3.6, top + dir * 8), Color3.fromRGB(70, 130, 60), Enum.Material.Grass))
		end
	end

	-- A pine (no snow): Pinecrest's pines and the hills'.
	local function pine(parent: Instance, x: number, z: number, y: number)
		local height = estateRng:NextNumber(14, 22)
		cylinder(parent, "Trunk", height, 1.3, CFrame.new(x, y + height / 2, z) * UPRIGHT, Color3.fromRGB(78, 58, 42), Enum.Material.Wood)
		for n = 0, 2 do
			local size = 11 - n * 3
			local ball = deco(part(parent, "Needles", Vector3.new(size, size * 0.9, size), CFrame.new(x, y + height * 0.42 + n * 4, z), Color3.fromRGB(38, 70, 44), Enum.Material.Grass))
			ball.Shape = Enum.PartType.Ball
		end
	end

	local function hedge(parent: Instance, f: CFrame, x0: number, z0: number, x1: number, z1: number, height: number)
		box(parent, "Hedge", f, x0, 0, z0, x1, height, z1, Color3.fromRGB(60, 104, 52), Enum.Material.Grass)
	end

	-- ── Signs and prompts ──────────────────────────────────────────────────────

	-- A FOR SALE sign on two posts: the property's name on top, the board under it (the EstatePrompt's parent) says
	-- "FOR SALE · $price" (server/Estate.luau writes the owners there). `cf` stands on the ground, the text looks along
	-- cf.LookVector (toward the road).
	local SIGN_RED = Color3.fromRGB(196, 40, 36)
	local function forSaleSign(parent: Instance, id: string, cf: CFrame, small: boolean?): Part?
		local def = ESTATE[id]
		if not def then
			return nil
		end
		local k = if small then 0.7 else 1
		local height = 7 * k
		for _, side in { -1, 1 } do
			part(parent, "SignPost", Vector3.new(0.45, height, 0.45), cf * CFrame.new(side * 3.4 * k, height / 2, 0.3), Color3.fromRGB(235, 235, 235), Enum.Material.Wood)
		end
		sign(parent, string.upper(def.name), Vector3.new(7.6 * k, 1.4 * k, 0.25), cf * CFrame.new(0, height - 0.2 * k, 0), Color3.fromRGB(255, 220, 120), Color3.fromRGB(34, 34, 40))
		local board = part(parent, "EstateSign", Vector3.new(7.6 * k, 3.4 * k, 0.35), cf * CFrame.new(0, height - 2.9 * k, 0), Color3.fromRGB(250, 250, 248), Enum.Material.SmoothPlastic)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Plate"
		gui.Face = Enum.NormalId.Front
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Status"
		label.Size = UDim2.new(1, -12, 1, -8)
		label.Position = UDim2.fromOffset(6, 4)
		label.BackgroundTransparency = 1
		label.Text = `FOR SALE\n{dollars(def.price)}`
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = SIGN_RED
		label.Parent = gui
		local signs = World.EstateSigns[id] or {}
		table.insert(signs, label)
		World.EstateSigns[id] = signs

		local p = Instance.new("ProximityPrompt")
		p.Name = "EstatePrompt"
		p.ActionText = "View listing"
		p.ObjectText = def.name
		p.HoldDuration = 0
		p.MaxActivationDistance = 12
		p.RequiresLineOfSight = false
		p:SetAttribute("Estate", id)
		p.Parent = board
		table.insert(World.EstatePrompts, { prompt = p, estate = id })
		return board
	end

	-- The garage of a home or a garage building: `doors` doors of 10 studs (2 stud pillars between) in the front wall,
	-- `depth` deep. `cf` is the middle of the front wall on the floor, looking out. Returns the spot in front of it where
	-- a car comes out (World.EstateGarages): in front of a door, facing out, at a car's height over the ground.
	local function garageBlock(parent: Instance, cf: CFrame, doors: number, depth: number, height: number, color: Color3, material: Enum.Material): CFrame
		local gw = doors * 12 + 2
		local half = gw / 2
		local concrete = Color3.fromRGB(128, 128, 126)
		box(parent, "GarageFloor", cf, -half, -0.3, 0, half, 0, depth, concrete, Enum.Material.Concrete)
		box(parent, "GarageWall", cf, -half, 0, depth - 1, half, height, depth, color, material)
		box(parent, "GarageWall", cf, -half, 0, 0, -half + 1, height, depth - 1, color, material)
		box(parent, "GarageWall", cf, half - 1, 0, 0, half, height, depth - 1, color, material)
		for n = 0, doors do
			local x = -half + 1 + n * 12
			box(parent, "GaragePillar", cf, x - 1, 0, 0, x + 1, height, 1, color, material)
			if n > 0 and n < doors then
				-- the line between two bays
				deco(box(parent, "BayLine", cf, x - 0.15, 0, 2, x + 0.15, 0.05, depth - 2, Color3.fromRGB(230, 230, 230)))
			end
		end
		box(parent, "GarageLintel", cf, -half, 9, 0, half, height, 1, color, material)
		for n = 1, doors do
			local x = -half + n * 12 - 4
			deco(cylinder(parent, "GarageDoorRoll", 10, 1.3, cf * CFrame.new(x, 9.6, 1.6), Color3.fromRGB(200, 200, 196), Enum.Material.DiamondPlate))
		end
		box(parent, "GarageRoof", cf, -half - 0.5, height, -0.5, half + 0.5, height + 0.8, depth + 0.5, color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Metal)
		ceilingLight(parent, cf, 0, height, depth / 2, math.max(gw, depth))
		local x = if doors % 2 == 0 then 6 else 0
		return cf * CFrame.new(x, 0.58, -GARAGE_APRON) -- over the driveway (0.08), like a car on a road
	end

	-- A lot outside the city blocks: a grass pad over the plot's lot and its front yard down to the road.
	local function lotPad(parent: Instance, f: CFrame, plot: Map.EstatePlot, reach: number, color: Color3?, material: Enum.Material?)
		-- f stands on the pad's top (PAD_TOP)
		box(parent, "Lot", f, -plot.w / 2, -PAD_TOP, -plot.front - reach + 0.3, plot.w / 2, 0, plot.back, color or Color3.fromRGB(86, 116, 60), material or Enum.Material.Grass)
	end

	local function driveway(parent: Instance, f: CFrame, x0: number, x1: number, z0: number, z1: number, color: Color3?)
		box(parent, "Driveway", f, x0, 0, z0, x1, 0.08, z1, color or Color3.fromRGB(150, 146, 138), Enum.Material.Pavement)
	end

	local function registerHome(id: string, f: CFrame, doorX: number, doorZ: number, floorY: number)
		-- just inside the front door, facing in
		World.EstateSpawns[id] = f * CFrame.new(doorX, floorY + 3, doorZ + 5) * CFrame.Angles(0, math.pi, 0)
	end

	-- ── Homes ──────────────────────────────────────────────────────────────────

	type HomeStyle = {
		wall: Color3,
		wallMaterial: Enum.Material,
		inner: Color3,
		floor: Color3,
		floorMaterial: Enum.Material,
		roof: Color3,
		accent: Color3, -- sofas, blankets, the parasols
		gable: boolean, -- a pitched roof (else flat with a parapet)
		glassy: boolean, -- big windows
		doors: number, -- garage doors
	}

	local HOME_STYLES: { [string]: HomeStyle } = {
		hilltop = { wall = Color3.fromRGB(242, 240, 234), wallMaterial = Enum.Material.SmoothPlastic, inner = Color3.fromRGB(236, 232, 224), floor = Color3.fromRGB(214, 206, 192), floorMaterial = Enum.Material.Marble, roof = Color3.fromRGB(60, 62, 68), accent = Color3.fromRGB(40, 96, 150), gable = false, glassy = true, doors = 4 },
		oceanview = { wall = Color3.fromRGB(214, 226, 232), wallMaterial = Enum.Material.SmoothPlastic, inner = Color3.fromRGB(240, 242, 244), floor = Color3.fromRGB(196, 176, 150), floorMaterial = Enum.Material.WoodPlanks, roof = Color3.fromRGB(70, 80, 92), accent = Color3.fromRGB(30, 140, 160), gable = false, glassy = true, doors = 4 },
		pinecrest = { wall = Color3.fromRGB(150, 146, 136), wallMaterial = Enum.Material.Slate, inner = Color3.fromRGB(226, 216, 196), floor = Color3.fromRGB(140, 100, 68), floorMaterial = Enum.Material.WoodPlanks, roof = Color3.fromRGB(70, 56, 48), accent = Color3.fromRGB(150, 60, 50), gable = true, glassy = false, doors = 3 },
		lakeside = { wall = Color3.fromRGB(70, 74, 82), wallMaterial = Enum.Material.SmoothPlastic, inner = Color3.fromRGB(236, 234, 228), floor = Color3.fromRGB(180, 160, 130), floorMaterial = Enum.Material.WoodPlanks, roof = Color3.fromRGB(40, 42, 46), accent = Color3.fromRGB(220, 160, 60), gable = false, glassy = true, doors = 2 },
		sunset = { wall = Color3.fromRGB(246, 244, 238), wallMaterial = Enum.Material.Plaster, inner = Color3.fromRGB(244, 236, 222), floor = Color3.fromRGB(200, 150, 110), floorMaterial = Enum.Material.Slate, roof = Color3.fromRGB(176, 90, 60), accent = Color3.fromRGB(230, 120, 70), gable = false, glassy = false, doors = 2 },
		maple = { wall = Color3.fromRGB(200, 214, 226), wallMaterial = Enum.Material.WoodPlanks, inner = Color3.fromRGB(240, 236, 226), floor = Color3.fromRGB(160, 120, 84), floorMaterial = Enum.Material.WoodPlanks, roof = Color3.fromRGB(70, 74, 86), accent = Color3.fromRGB(80, 120, 170), gable = true, glassy = false, doors = 1 },
		oak = { wall = Color3.fromRGB(150, 80, 62), wallMaterial = Enum.Material.Brick, inner = Color3.fromRGB(236, 226, 206), floor = Color3.fromRGB(150, 110, 76), floorMaterial = Enum.Material.WoodPlanks, roof = Color3.fromRGB(64, 58, 54), accent = Color3.fromRGB(90, 130, 80), gable = true, glassy = false, doors = 1 },
		birch = { wall = Color3.fromRGB(236, 220, 180), wallMaterial = Enum.Material.WoodPlanks, inner = Color3.fromRGB(246, 238, 220), floor = Color3.fromRGB(170, 130, 90), floorMaterial = Enum.Material.WoodPlanks, roof = Color3.fromRGB(120, 60, 46), accent = Color3.fromRGB(200, 90, 80), gable = true, glassy = false, doors = 1 },
		elm = { wall = Color3.fromRGB(196, 206, 176), wallMaterial = Enum.Material.WoodPlanks, inner = Color3.fromRGB(240, 238, 228), floor = Color3.fromRGB(150, 116, 86), floorMaterial = Enum.Material.WoodPlanks, roof = Color3.fromRGB(90, 70, 60), accent = Color3.fromRGB(120, 100, 160), gable = true, glassy = false, doors = 1 },
	}

	-- A flat roof with a low parapet (or a pitched one) over a box x0..x1, z0..z1 at height `top`.
	local function homeRoof(parent: Instance, f: CFrame, x0: number, z0: number, x1: number, z1: number, top: number, style: HomeStyle)
		if style.gable then
			box(parent, "Ceiling", f, x0, top - 0.6, z0, x1, top, z1, style.inner, Enum.Material.SmoothPlastic)
			gableRoof(parent, f * CFrame.new((x0 + x1) / 2, top, (z0 + z1) / 2), x1 - x0 + 3, z1 - z0 + 3, math.min(9, (z1 - z0) * 0.3), style.roof)
			return
		end
		box(parent, "Roof", f, x0 - 1.5, top - 0.6, z0 - 1.5, x1 + 1.5, top + 0.6, z1 + 1.5, style.roof, Enum.Material.Concrete)
		for _, edge in { { x0 - 1.5, z0 - 1.5, x1 + 1.5, z0 - 0.5 }, { x0 - 1.5, z1 + 0.5, x1 + 1.5, z1 + 1.5 }, { x0 - 1.5, z0 - 0.5, x0 - 0.5, z1 + 0.5 }, { x1 + 0.5, z0 - 0.5, x1 + 1.5, z1 + 0.5 } } do
			box(parent, "Parapet", f, edge[1], top + 0.6, edge[2], edge[3], top + 1.6, edge[4], style.wall, style.wallMaterial)
		end
	end

	-- A pool on a terrace: the rim, the water (you wade in it) and its tiled floor. x0..x1, z0..z1 is the water.
	local function pool(parent: Instance, f: CFrame, x0: number, z0: number, x1: number, z1: number, y: number)
		local rim = Color3.fromRGB(226, 222, 212)
		box(parent, "PoolRim", f, x0 - 1.2, y, z0 - 1.2, x1 + 1.2, y + 0.8, z0, rim, Enum.Material.Limestone)
		box(parent, "PoolRim", f, x0 - 1.2, y, z1, x1 + 1.2, y + 0.8, z1 + 1.2, rim, Enum.Material.Limestone)
		box(parent, "PoolRim", f, x0 - 1.2, y, z0, x0, y + 0.8, z1, rim, Enum.Material.Limestone)
		box(parent, "PoolRim", f, x1, y, z0, x1 + 1.2, y + 0.8, z1, rim, Enum.Material.Limestone)
		deco(box(parent, "PoolTiles", f, x0, y, z0, x1, y + 0.05, z1, Color3.fromRGB(70, 160, 200), Enum.Material.SmoothPlastic))
		local water = deco(box(parent, "PoolWater", f, x0, y + 0.1, z0, x1, y + 0.6, z1, Color3.fromRGB(80, 190, 230), Enum.Material.Glass))
		water.Transparency = 0.35
		local glow = Instance.new("SurfaceLight")
		glow.Face = Enum.NormalId.Top
		glow.Range = 10
		glow.Brightness = 1.2
		glow.Color = Color3.fromRGB(120, 220, 255)
		glow.Parent = water
		DayNight.nightLight(glow)
	end

	-- A wooden pier from the garden out over the water (the lakeside villa's on the river, Ocean View's on the sea).
	local function pier(parent: Instance, from: Vector3, to: Vector3)
		local frame = CFrame.lookAt((from + to) / 2, to)
		local length = (to - from).Magnitude
		part(parent, "Pier", Vector3.new(6, 0.6, length), frame, Color3.fromRGB(150, 116, 80), Enum.Material.WoodPlanks)
		for z = -length / 2 + 4, length / 2 - 2, 10 do
			for _, side in { -1, 1 } do
				cylinder(parent, "PierPost", 12, 0.9, frame * CFrame.new(side * 2.6, -5.5, z) * UPRIGHT, Color3.fromRGB(110, 86, 60), Enum.Material.Wood)
			end
		end
		local post = deco(part(parent, "PierLamp", Vector3.new(0.8, 0.8, 0.8), frame * CFrame.new(2.6, 3.4, length / 2 - 1), Color3.fromRGB(150, 140, 110), Enum.Material.Glass))
		part(parent, "PierLampPost", Vector3.new(0.3, 3, 0.3), frame * CFrame.new(2.6, 1.6, length / 2 - 1), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
		light(post, 20, 1.2, Color3.fromRGB(255, 214, 150))
		DayNight.nightLight(post, Color3.fromRGB(255, 220, 150), Color3.fromRGB(150, 140, 110), "Glass")
	end

	-- A mansion: two floors (a living room, the hall with the stairs, the kitchen and the dining room downstairs; two
	-- bedrooms and a bathroom upstairs), the garage wing for `doors` x 2 cars, a terrace with the pool behind.
	local function mansion(parent: Instance, id: string, plot: Map.EstatePlot, style: HomeStyle)
		local home = folder(parent, ESTATE[id].name)
		local f = plotFrame(plot, PAD_TOP)
		local reach = frontReach(plot)
		lotPad(home, f, plot, reach)
		local W = plot.w
		local X0, X1 = -W / 2, -W / 2 + 58 -- the house
		local Z0, Z1 = -23, 23
		local L1, L2, TOP = 0.3, 13.6, 26
		local wallC, wallM, inner = style.wall, style.wallMaterial, style.inner
		local doorX = (X0 + X1) / 2
		local glassW = if style.glassy then 14 else 9
		-- Floors.
		box(home, "Floor", f, X0, 0, Z0, X1, L1, Z1, style.floor, style.floorMaterial)
		local holeX0, holeX1, holeZ0, holeZ1 = X0 + 23, X0 + 29, -3, 19
		slabWithHole(home, f, X0 + 1, Z0 + 1, X1 - 1, Z1 - 1, L2, 0.6, holeX0, holeZ0, holeX1, holeZ1, style.floor, style.floorMaterial)
		stairs(home, f, (holeX0 + holeX1) / 2, -2, L1, L2, 6, 1.45, style.floor:Lerp(Color3.new(0, 0, 0), 0.15))
		-- Outer walls, both floors.
		for storey = 1, 2 do
			local y0 = if storey == 1 then L1 else L2
			local y1 = if storey == 1 then L2 - 0.6 else TOP
			local front: { Opening } = {
				{ at = X0 + 10, width = glassW, bottom = 2.5, top = 10, glass = true },
				{ at = X1 - 11, width = glassW, bottom = 2.5, top = 10, glass = true },
			}
			if storey == 1 then
				table.insert(front, { at = doorX, width = 6, bottom = 0, top = 9 })
			else
				table.insert(front, { at = doorX, width = 8, bottom = 2.5, top = 10, glass = true })
			end
			wall(home, f, true, X0, X1, Z0 + 0.5, y0, y1, front, wallC, wallM, 1, storey == 1)
			local back: { Opening } = {
				{ at = X0 + 10, width = glassW + 2, bottom = if storey == 1 then 1 else 2.5, top = 10.5, glass = true },
				{ at = X1 - 11, width = 10, bottom = 5, top = 10, glass = true },
			}
			if storey == 1 then
				table.insert(back, { at = doorX, width = 6, bottom = 0, top = 9 }) -- out to the terrace
			end
			wall(home, f, true, X0, X1, Z1 - 0.5, y0, y1, back, wallC, wallM, 1, storey == 2)
			wall(home, f, false, Z0 + 1, Z1 - 1, X0 + 0.5, y0, y1, {
				{ at = -12, width = 8, bottom = 2.5, top = 10, glass = true },
				{ at = 12, width = 8, bottom = 2.5, top = 10, glass = true },
			}, wallC, wallM)
			wall(home, f, false, Z0 + 1, Z1 - 1, X1 - 0.5, y0, y1, nil, wallC, wallM)
		end
		-- Inner walls: downstairs living | hall | kitchen; upstairs bedroom | landing | bedroom and bathroom.
		local A, B = X0 + 21, X0 + 37
		wall(home, f, false, Z0 + 1, Z1 - 1, A, L1, L2 - 0.6, { { at = 0, width = 8, bottom = 0, top = 9.5 } }, inner, Enum.Material.SmoothPlastic, 0.6)
		wall(home, f, false, Z0 + 1, Z1 - 1, B, L1, L2 - 0.6, { { at = 0, width = 8, bottom = 0, top = 9.5 } }, inner, Enum.Material.SmoothPlastic, 0.6)
		-- The west bedroom door opens onto the full landing south of the stairwell (not the narrow ledge beside it).
		wall(home, f, false, Z0 + 1, Z1 - 1, A, L2, TOP, { { at = -8, width = 5, bottom = 0, top = 8.5 } }, inner, Enum.Material.SmoothPlastic, 0.6)
		wall(home, f, false, Z0 + 1, Z1 - 1, B, L2, TOP, { { at = -6, width = 5, bottom = 0, top = 8.5 } }, inner, Enum.Material.SmoothPlastic, 0.6)
		wall(home, f, true, B + 0.3, X1 - 1, 6, L2, TOP, { { at = B + 6, width = 4, bottom = 0, top = 8.5 } }, inner, Enum.Material.SmoothPlastic, 0.6)
		homeRoof(home, f, X0, Z0, X1, Z1, TOP + 0.6, style)
		-- Lights.
		for _, spot in { { (X0 + A) / 2, -8 }, { (X0 + A) / 2, 10 }, { (A + B) / 2, -14 }, { (B + X1) / 2, -6 }, { (B + X1) / 2, 12 } } do
			ceilingLight(home, f, spot[1], L2 - 0.6, spot[2], 26)
		end
		for _, spot in { { (X0 + A) / 2, 0 }, { (A + B) / 2, 4 }, { (B + X1) / 2, -8 }, { (B + X1) / 2, 14 } } do
			ceilingLight(home, f, spot[1], TOP, spot[2], 22)
		end
		-- Downstairs.
		local livingX = (X0 + A) / 2
		rug(home, f * CFrame.new(livingX, L1, 0), 14, 18, style.accent:Lerp(Color3.new(1, 1, 1), 0.5))
		tv(home, f * CFrame.new(X0 + 2, L1, 0) * CFrame.Angles(0, -math.pi / 2, 0))
		sofa(home, f * CFrame.new(A - 4.5, L1, 0) * CFrame.Angles(0, math.pi / 2, 0), style.accent, 10)
		coffeeTable(home, f * CFrame.new(livingX + 1, L1, 0))
		bookshelf(home, f * CFrame.new(A - 1.3, L1, -15) * CFrame.Angles(0, math.pi / 2, 0))
		plant(home, f * CFrame.new(X0 + 3, L1, Z0 + 3))
		plant(home, f * CFrame.new(X0 + 3, L1, Z1 - 3))
		rug(home, f * CFrame.new(doorX, L1, Z0 + 6), 6, 8, Color3.fromRGB(150, 60, 50))
		plant(home, f * CFrame.new(B - 3, L1, Z0 + 3), 1.2)
		local kitchenX = (B + X1) / 2
		kitchen(home, f * CFrame.new(kitchenX - 3, L1, Z1 - 2.6), 12, Color3.fromRGB(230, 226, 220))
		diningSet(home, f * CFrame.new(kitchenX, L1, -7), 9, Color3.fromRGB(120, 86, 60))
		plant(home, f * CFrame.new(X1 - 3, L1, Z0 + 3))
		-- Upstairs.
		bed(home, f * CFrame.new(livingX, L2, Z1 - 7), style.accent)
		rug(home, f * CFrame.new(livingX, L2, 4), 10, 8, style.accent:Lerp(Color3.new(1, 1, 1), 0.6))
		bookshelf(home, f * CFrame.new(A - 1.3, L2, -14) * CFrame.Angles(0, math.pi / 2, 0))
		plant(home, f * CFrame.new(X0 + 3, L2, Z0 + 3))
		bed(home, f * CFrame.new(kitchenX + 2, L2, 0.7), style.accent:Lerp(Color3.new(1, 1, 1), 0.3))
		plant(home, f * CFrame.new(X1 - 3, L2, Z0 + 3))
		bathroom(home, f * CFrame.new(kitchenX + 2, L2, Z1 - 4.5) * CFrame.Angles(0, math.pi / 2, 0), f * CFrame.new(B + 3, L2, Z1 - 3), f * CFrame.new(X1 - 2.4, L2, 14) * CFrame.Angles(0, math.pi / 2, 0))
		-- The garage wing at the right, its doors on the front.
		local gw = style.doors * 12 + 2
		local gx = W / 2 - gw / 2
		World.EstateGarages[id] = garageBlock(home, f * CFrame.new(gx, 0, Z0), style.doors, 30, 12.5, wallC, wallM)
		driveway(home, f, gx - gw / 2 + 2, gx + gw / 2 - 2, Z0 - reach, Z0)
		driveway(home, f, doorX - 3, doorX + 3, Z0 - reach, Z0, Color3.fromRGB(196, 188, 172))
		-- The terrace and the pool.
		local deck = Color3.fromRGB(196, 176, 150)
		box(home, "Terrace", f, X0, 0, Z1, X1, 0.5, Z1 + 22, deck, Enum.Material.WoodPlanks)
		pool(home, f, X0 + 6, Z1 + 6, X0 + 40, Z1 + 18, 0.5)
		lounger(home, f * CFrame.new(X1 - 13, 0.5, Z1 + 12))
		lounger(home, f * CFrame.new(X1 - 8, 0.5, Z1 + 12))
		parasol(home, f * CFrame.new(X1 - 3, 0.5, Z1 + 12), style.accent)
		-- The garden: hedges round the back, palms or pines, a lantern at the door.
		hedge(home, f, -W / 2, plot.back - 2, W / 2, plot.back, 4)
		hedge(home, f, -W / 2, Z1 + 22, -W / 2 + 2, plot.back - 2, 4)
		hedge(home, f, W / 2 - 2, Z1 + 22, W / 2, plot.back - 2, 4)
		for _, spot in { { -W / 2 + 5, Z1 + 30 }, { W / 2 - 6, Z1 + 32 }, { X0 + 20, Z1 + 34 }, { -W / 2 + 6, Z0 - 6 } } do
			local p = (f * CFrame.new(spot[1], 0, spot[2])).Position
			if style.gable then
				pine(home, p.X, p.Z, p.Y)
			else
				palm(home, p.X, p.Z, p.Y)
			end
		end
		for _, side in { -1, 1 } do
			local lantern = deco(part(home, "Lantern", Vector3.new(0.9, 1.6, 0.9), f * CFrame.new(doorX + side * 4.5, L1 + 7, Z0 - 0.6), Color3.fromRGB(150, 140, 110), Enum.Material.Glass))
			DayNight.nightLight(lantern, Color3.fromRGB(255, 220, 150), Color3.fromRGB(150, 140, 110), "Glass")
		end
		sign(home, string.upper(ESTATE[id].name), Vector3.new(20, 2, 0.3), f * CFrame.new(doorX, L2 - 1.4, Z0 - 0.2), style.accent:Lerp(Color3.new(1, 1, 1), 0.4), style.roof)
		registerHome(id, f, doorX, Z0, L1)
		forSaleSign(home, id, f * CFrame.new(-W / 2 + 8, 0, Z0 - reach + 3))
	end

	-- A villa: one floor (a living room with the kitchen, a bedroom, a bathroom), a garage for `doors` x 2 cars, a
	-- terrace with a small pool behind.
	local function villa(parent: Instance, id: string, plot: Map.EstatePlot, style: HomeStyle): CFrame
		local home = folder(parent, ESTATE[id].name)
		local f = plotFrame(plot, PAD_TOP)
		local reach = frontReach(plot)
		local winter = Map.isWinter(plot.x, plot.z)
		if winter then
			lotPad(home, f, plot, reach, Color3.fromRGB(232, 236, 240), Enum.Material.Snow)
		else
			lotPad(home, f, plot, reach)
		end
		local W = plot.w
		local X0, X1 = -W / 2, -W / 2 + 48
		local Z0, Z1 = -17, 17
		local L1, TOP = 0.3, 12
		local wallC, wallM, inner = style.wall, style.wallMaterial, style.inner
		local doorX = X0 + 24
		local P = X1 - 15 -- the wall between the living room and the bedroom side
		box(home, "Floor", f, X0, 0, Z0, X1, L1, Z1, style.floor, style.floorMaterial)
		wall(home, f, true, X0, X1, Z0 + 0.5, L1, TOP, {
			{ at = doorX, width = 6, bottom = 0, top = 9 },
			{ at = X0 + 9, width = if style.glassy then 14 else 10, bottom = 2, top = 10, glass = true },
			{ at = X1 - 5, width = 6, bottom = 5, top = 9, glass = true },
		}, wallC, wallM, 1, true)
		wall(home, f, true, X0, X1, Z1 - 0.5, L1, TOP, {
			{ at = X0 + 16, width = 20, bottom = 0.5, top = 10.5, glass = true },
			{ at = X1 - 7, width = 8, bottom = 2.5, top = 10, glass = true },
		}, wallC, wallM)
		wall(home, f, false, Z0 + 1, Z1 - 1, X0 + 0.5, L1, TOP, { { at = 8, width = 10, bottom = 2.5, top = 10, glass = true } }, wallC, wallM)
		wall(home, f, false, Z0 + 1, Z1 - 1, X1 - 0.5, L1, TOP, nil, wallC, wallM)
		wall(home, f, false, Z0 + 1, Z1 - 1, P, L1, TOP, { { at = 6, width = 4.5, bottom = 0, top = 8.5 }, { at = -10, width = 4.5, bottom = 0, top = 8.5 } }, inner, Enum.Material.SmoothPlastic, 0.6)
		wall(home, f, true, P + 0.3, X1 - 1, -3, L1, TOP, nil, inner, Enum.Material.SmoothPlastic, 0.6)
		homeRoof(home, f, X0, Z0, X1, Z1, TOP + 0.6, style)
		ceilingLight(home, f, X0 + 10, TOP, 0, 26)
		ceilingLight(home, f, X0 + 24, TOP, 0, 26)
		ceilingLight(home, f, (P + X1) / 2, TOP, 8, 18)
		ceilingLight(home, f, (P + X1) / 2, TOP, -10, 16)
		-- The living room and the kitchen.
		kitchen(home, f * CFrame.new(X0 + 2.4, L1, -10) * CFrame.Angles(0, -math.pi / 2, 0), 9, Color3.fromRGB(40, 40, 44))
		diningSet(home, f * CFrame.new(X0 + 13, L1, -7), 6, Color3.fromRGB(140, 104, 72))
		rug(home, f * CFrame.new(P - 9, L1, 5), 10, 8, style.accent:Lerp(Color3.new(1, 1, 1), 0.5))
		tv(home, f * CFrame.new(P - 1.2, L1, 5) * CFrame.Angles(0, math.pi / 2, 0))
		sofa(home, f * CFrame.new(P - 14, L1, 5) * CFrame.Angles(0, -math.pi / 2, 0), style.accent)
		coffeeTable(home, f * CFrame.new(P - 8.5, L1, 5) * CFrame.Angles(0, math.pi / 2, 0))
		plant(home, f * CFrame.new(X0 + 3, L1, Z1 - 3))
		plant(home, f * CFrame.new(P - 3, L1, Z0 + 3), 1.2)
		-- The bedroom and the bathroom.
		bed(home, f * CFrame.new(X1 - 6, L1, 8) * CFrame.Angles(0, math.pi / 2, 0), style.accent)
		bathroom(home, f * CFrame.new(X1 - 4.5, L1, -11) * CFrame.Angles(0, math.pi / 2, 0), f * CFrame.new(P + 2.5, L1, -14), f * CFrame.new(X1 - 2.4, L1, -5.5) * CFrame.Angles(0, math.pi / 2, 0))
		-- The garage.
		local gw = style.doors * 12 + 2
		local gx = W / 2 - gw / 2
		World.EstateGarages[id] = garageBlock(home, f * CFrame.new(gx, 0, Z0), style.doors, 28, 11, wallC, wallM)
		driveway(home, f, gx - gw / 2 + 2, gx + gw / 2 - 2, Z0 - reach, Z0)
		driveway(home, f, doorX - 3, doorX + 3, Z0 - reach, Z0, Color3.fromRGB(196, 188, 172))
		-- The terrace and the pool.
		box(home, "Terrace", f, X0, 0, Z1, X1, 0.5, Z1 + 11, Color3.fromRGB(206, 196, 180), Enum.Material.Limestone)
		pool(home, f, X0 + 4, Z1 + 3, X0 + 22, Z1 + 9, 0.5)
		lounger(home, f * CFrame.new(X0 + 28, 0.5, Z1 + 5.5))
		parasol(home, f * CFrame.new(X0 + 32, 0.5, Z1 + 6), style.accent)
		hedge(home, f, -W / 2, plot.back - 2, W / 2, plot.back, 3.5)
		for _, spot in { { -W / 2 + 4, Z0 - 6 }, { W / 2 - 4, plot.back - 6 }, { -W / 2 + 4, plot.back - 6 } } do
			local p = (f * CFrame.new(spot[1], 0, spot[2])).Position
			if winter then
				tree(home, p.X, p.Z, p.Y) -- a snowy pine
			else
				palm(home, p.X, p.Z, p.Y)
			end
		end
		local lantern = deco(part(home, "Lantern", Vector3.new(0.9, 1.6, 0.9), f * CFrame.new(doorX + 4.5, L1 + 7, Z0 - 0.6), Color3.fromRGB(150, 140, 110), Enum.Material.Glass))
		DayNight.nightLight(lantern, Color3.fromRGB(255, 220, 150), Color3.fromRGB(150, 140, 110), "Glass")
		registerHome(id, f, doorX, Z0, L1)
		forSaleSign(home, id, f * CFrame.new(X0 + 8, 0, Z0 - reach + 3))
		return f
	end

	-- A house on its Suburbs lot: a living room with the kitchen, a bedroom, a bathroom, a one-door garage, a pitched
	-- roof. Maple Street's is two storeys high outside (the upstairs is not furnished), Oak Lane's has a porch, Birch
	-- Cottage a chimney.
	local function estateHouse(parent: Instance, id: string, plot: Map.EstatePlot, style: HomeStyle)
		local home = folder(parent, ESTATE[id].name)
		local onBlock = Map.blockAt(plot.x, plot.z) ~= nil -- a Suburbs lot (else its own lot at the edge of town)
		local base = if onBlock then WALK_TOP else PAD_TOP
		local f = plotFrame(plot, base)
		local reach = if onBlock then 0 else frontReach(plot)
		if not onBlock then
			lotPad(home, f, plot, reach)
			hedge(home, f, -plot.w / 2, plot.back - 1.5, plot.w / 2, plot.back, 3)
			for _, spot in { { -plot.w / 2 - 6, 0 }, { plot.w / 2 + 6, 12 }, { -plot.w / 2 + 4, plot.back + 6 } } do
				local p = (f * CFrame.new(spot[1], 0, spot[2])).Position
				tree(home, p.X, p.Z, p.Y)
			end
		end
		local X0, X1 = -22, 8
		local Z0, Z1 = -10, 10
		local L1 = 0.3
		local TOP = if id == "maple" then 19 else 11
		local wallC, wallM, inner = style.wall, style.wallMaterial, style.inner
		local doorX = X0 + 8
		local P = X0 + 14 -- living room | bedroom and bathroom
		box(home, "Floor", f, X0, 0, Z0, X1, L1, Z1, style.floor, style.floorMaterial)
		local frontWindows: { Opening } = {
			{ at = doorX, width = 5, bottom = 0, top = 8 },
			{ at = X0 + 3.5, width = 4, bottom = 3, top = 8, glass = true },
			{ at = P + 6, width = 5, bottom = 4, top = 8, glass = true },
		}
		wall(home, f, true, X0, X1, Z0 + 0.5, L1, 11, frontWindows, wallC, wallM, 1, true)
		wall(home, f, true, X0, X1, Z1 - 0.5, L1, 11, { { at = X0 + 6, width = 6, bottom = 4.4, top = 8, glass = true }, { at = P + 7, width = 6, bottom = 3, top = 8, glass = true } }, wallC, wallM)
		wall(home, f, false, Z0 + 1, Z1 - 1, X0 + 0.5, L1, 11, { { at = 0, width = 6, bottom = 3, top = 8, glass = true } }, wallC, wallM)
		wall(home, f, false, Z0 + 1, Z1 - 1, X1 - 0.5, L1, 11, nil, wallC, wallM)
		wall(home, f, false, Z0 + 1, Z1 - 1, P, L1, 11, { { at = 4.5, width = 4, bottom = 0, top = 8 }, { at = -5, width = 4, bottom = 0, top = 8 } }, inner, Enum.Material.SmoothPlastic, 0.5)
		wall(home, f, true, P + 0.25, X1 - 1, 0, L1, 11, nil, inner, Enum.Material.SmoothPlastic, 0.5)
		if TOP > 11 then
			-- the upper storey (outside only): its walls, windows that light up at night
			box(home, "Ceiling", f, X0 + 1, 10.6, Z0 + 1, X1 - 1, 11.2, Z1 - 1, inner, Enum.Material.SmoothPlastic)
			wall(home, f, true, X0, X1, Z0 + 0.5, 11, TOP, { { at = X0 + 6, width = 5, bottom = 2, top = 6, glass = true }, { at = X1 - 8, width = 5, bottom = 2, top = 6, glass = true } }, wallC, wallM, 1, true)
			wall(home, f, true, X0, X1, Z1 - 0.5, 11, TOP, nil, wallC, wallM)
			wall(home, f, false, Z0 + 1, Z1 - 1, X0 + 0.5, 11, TOP, nil, wallC, wallM)
			wall(home, f, false, Z0 + 1, Z1 - 1, X1 - 0.5, 11, TOP, nil, wallC, wallM)
		end
		homeRoof(home, f, X0, Z0, X1, Z1, TOP, style)
		ceilingLight(home, f, X0 + 7, 10.4, 0, 18)
		ceilingLight(home, f, (P + X1) / 2, 10.4, 5, 12)
		-- Inside.
		kitchen(home, f * CFrame.new(X0 + 5, L1, Z1 - 2.4), 6, Color3.fromRGB(200, 196, 190))
		diningSet(home, f * CFrame.new(X0 + 10, L1, 1.5), 4, Color3.fromRGB(140, 104, 72))
		sofa(home, f * CFrame.new(X0 + 3, L1, -6) * CFrame.Angles(0, -math.pi / 2, 0), style.accent, 6)
		plant(home, f * CFrame.new(P - 2, L1, Z0 + 2), 0.8)
		bed(home, f * CFrame.new(X1 - 6, L1, 5) * CFrame.Angles(0, math.pi / 2, 0), style.accent)
		local white = Color3.fromRGB(240, 242, 244)
		part(home, "Shower", Vector3.new(3.4, 0.3, 3.4), f * CFrame.new(X1 - 2.8, L1 + 0.15, -6.5), white, Enum.Material.SmoothPlastic)
		deco(part(home, "ShowerGlass", Vector3.new(0.2, 7, 3.4), f * CFrame.new(X1 - 4.6, L1 + 3.5, -6.5), GLASS, Enum.Material.Glass)).Transparency = 0.5
		part(home, "Toilet", Vector3.new(1.6, 1.6, 2.2), f * CFrame.new(P + 2, L1 + 0.8, -7.8), white, Enum.Material.SmoothPlastic)
		part(home, "Washbasin", Vector3.new(2.4, 3, 1.6), f * CFrame.new(P + 5.5, L1 + 1.5, -1.3), white, Enum.Material.Marble)
		-- The garage, the drive, the path.
		local gx = X1 + 7
		World.EstateGarages[id] = garageBlock(home, f * CFrame.new(gx, 0, Z0), 1, 20, 10, wallC, wallM)
		-- the block's edge (the house stands 5 forward of its lot's middle), or the road in front of its own lot
		local lotFront = if onBlock then -(Map.SuburbLot / 2 - 5) - Map.SuburbInset else -plot.front - reach + 0.3
		driveway(home, f, gx - 5, gx + 5, lotFront, Z0)
		driveway(home, f, doorX - 2, doorX + 2, lotFront, Z0, Color3.fromRGB(200, 192, 176))
		if id == "oak" then
			box(home, "Porch", f, doorX - 6, 0, Z0 - 5, doorX + 6, 0.4, Z0, Color3.fromRGB(150, 110, 76), Enum.Material.WoodPlanks)
			for _, side in { -1, 1 } do
				part(home, "PorchPost", Vector3.new(0.6, 8.6, 0.6), f * CFrame.new(doorX + side * 5.4, 4.7, Z0 - 4.4), Color3.fromRGB(240, 240, 236), Enum.Material.Wood)
			end
			box(home, "PorchRoof", f, doorX - 6.5, 9, Z0 - 5.5, doorX + 6.5, 9.6, Z0, style.roof, Enum.Material.Slate)
		elseif id == "birch" then
			box(home, "Chimney", f, X0 + 3, TOP - 2, 2, X0 + 6, TOP + 7, 5, Color3.fromRGB(140, 80, 62), Enum.Material.Brick)
		end
		local lantern = deco(part(home, "Lantern", Vector3.new(0.8, 1.4, 0.8), f * CFrame.new(doorX + 3.4, L1 + 6.5, Z0 - 0.6), Color3.fromRGB(150, 140, 110), Enum.Material.Glass))
		DayNight.nightLight(lantern, Color3.fromRGB(255, 220, 150), Color3.fromRGB(150, 140, 110), "Glass")
		registerHome(id, f, doorX, Z0, L1)
		forSaleSign(home, id, f * CFrame.new(-3, 0, lotFront + 3), true)
	end

	-- The houses for sale on the Suburbs lots (suburbsBlock asks while it lays out the lots).
	local HOUSE_PLOTS: { { id: string, plot: Map.EstatePlot } } = {}
	for _, def in Config.Estate.Properties do
		local plot = Map.EstatePlots[def.id]
		if plot and def.kind == "house" and Map.blockAt(plot.x, plot.z) ~= nil then
			table.insert(HOUSE_PLOTS, { id = def.id, plot = plot })
		end
	end

	-- The house for sale on the Suburbs lot centred here, if any.
	local function houseOnLot(lx: number, lz: number): (string?, Map.EstatePlot?)
		for _, entry in HOUSE_PLOTS do
			if math.abs(entry.plot.x - lx) < 2 and math.abs(entry.plot.z - lz) < Map.SuburbLot / 2 then
				return entry.id, entry.plot
			end
		end
		return nil, nil
	end

	buildEstateHouse = function(parent: Instance, lx: number, lz: number): boolean
		local id, plot = houseOnLot(lx, lz)
		if not id or not plot then
			return false
		end
		local style = HOME_STYLES[id] or HOME_STYLES.elm
		attempt(`house {id}`, function()
			estateHouse(parent, id, plot, style)
		end)
		return true
	end

	-- ── Garages ────────────────────────────────────────────────────────────────

	-- The Harbor Lockup: a rusty row of four lock-ups on a Harbor block, containers stacked behind.
	buildLockup = function(parent: Instance, cx: number, cz: number)
		local lockup = folder(parent, "HarborLockup")
		sidewalk(lockup, cx, cz, Color3.fromRGB(120, 120, 116))
		local plot = Map.EstatePlots.garage_harbor
		if not plot then
			return
		end
		local f = plotFrame(plot, WALK_TOP)
		local color = Color3.fromRGB(176, 104, 54)
		World.EstateGarages.garage_harbor = garageBlock(lockup, f * CFrame.new(0, 0, -plot.front), 4, plot.front + plot.back, 11, color, Enum.Material.CorrodedMetal)
		sign(lockup, "HARBOR LOCKUP", Vector3.new(30, 3, 0.4), f * CFrame.new(0, 13.6, -plot.front - 0.3), Color3.fromRGB(255, 220, 120), Color3.fromRGB(50, 50, 54))
		-- containers on the rest of the block, behind the lock-ups
		for row = 0, 1 do
			for col = -2, 2 do
				if estateRng:NextNumber() < 0.8 then
					local stack = estateRng:NextInteger(1, 3)
					for level = 0, stack - 1 do
						container(lockup, f * CFrame.new(col * 10, 4.25 + level * 8.6, plot.back + 18 + row * 22) * CFrame.Angles(0, math.rad(estateRng:NextNumber(-2, 2)), 0))
					end
				end
			end
		end
		forSaleSign(lockup, "garage_harbor", f * CFrame.new(20, 0, -plot.front - 9))
	end

	-- Downtown Parking: an open parking deck in the safe zone, six bays under a roof deck.
	buildParking = function(parent: Instance, cx: number, cz: number)
		local parking = folder(parent, "DowntownParking")
		sidewalk(parking, cx, cz, Color3.fromRGB(110, 110, 112))
		local plot = Map.EstatePlots.garage_downtown
		if not plot then
			return
		end
		local f = plotFrame(plot, WALK_TOP)
		local half, front, back = plot.w / 2, plot.front, plot.back
		local concrete = Color3.fromRGB(150, 150, 146)
		local H = 11
		box(parking, "Deck", f, -half, 0, -front, half, 0.25, back, Color3.fromRGB(60, 60, 64), Enum.Material.Asphalt)
		wall(parking, f, true, -half, half, back - 0.5, 0, H + 1.2, nil, concrete, Enum.Material.Concrete)
		for _, side in { -1, 1 } do
			wall(parking, f, false, -front, back - 1, side * (half - 0.5), 0, H + 1.2, { { at = 0, width = 44, bottom = 3.5, top = 9 } }, concrete, Enum.Material.Concrete)
		end
		for n = 0, 6 do
			local x = -half + 1 + n * (plot.w - 2) / 6
			box(parking, "Pillar", f, x - 1, 0, -front, x + 1, H, -front + 2, concrete, Enum.Material.Concrete)
			if n > 0 and n < 6 then
				deco(box(parking, "BayLine", f, x - 0.15, 0.25, -front + 3, x + 0.15, 0.3, back - 22, Color3.fromRGB(240, 240, 240)))
			end
		end
		box(parking, "Lintel", f, -half, 9.5, -front, half, H, -front + 2, Color3.fromRGB(46, 90, 170), Enum.Material.SmoothPlastic)
		box(parking, "RoofDeck", f, -half, H, -front, half, H + 1, back, concrete, Enum.Material.Concrete)
		for _, edge in { { -half, -front, half, -front + 1 }, { -half, -front + 1, -half + 1, back - 1 }, { half - 1, -front + 1, half, back - 1 } } do
			box(parking, "Parapet", f, edge[1], H + 1, edge[2], edge[3], H + 2.4, edge[4], concrete, Enum.Material.Concrete)
		end
		sign(parking, "DOWNTOWN PARKING", Vector3.new(40, 1.4, 0.3), f * CFrame.new(0, 10.25, -front - 0.2), Color3.fromRGB(255, 255, 255), Color3.fromRGB(46, 90, 170))
		-- a tall P on a post at the corner
		part(parking, "SignPost", Vector3.new(1, 22, 1), f * CFrame.new(-half + 3, 11, -front - 6), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
		local pSign = part(parking, "ParkingSign", Vector3.new(6, 6, 0.6), f * CFrame.new(-half + 3, 21, -front - 6), Color3.fromRGB(46, 90, 170), Enum.Material.SmoothPlastic)
		sign(parking, "P", Vector3.new(5, 5, 0.1), pSign.CFrame * CFrame.new(0, 0, -0.36), Color3.fromRGB(255, 255, 255), Color3.fromRGB(46, 90, 170))
		for _, x in { -half / 2, half / 2 } do
			ceilingLight(parking, f, x, H, -4, 40)
		end
		World.EstateGarages.garage_downtown = f * CFrame.new((plot.w - 2) / 12, 0.5, -front - GARAGE_APRON)
		forSaleSign(parking, "garage_downtown", f * CFrame.new(half - 6, 0, -front - 14))
	end

	-- The Highway Garage by the North Highway: four bays and an apron down to the road.
	local function buildHighwayGarage(parent: Instance)
		local plot = Map.EstatePlots.garage_north
		if not plot then
			return
		end
		local garage = folder(parent, "HighwayGarage")
		local f = plotFrame(plot, PAD_TOP)
		local reach = frontReach(plot)
		lotPad(garage, f, plot, reach, Color3.fromRGB(120, 120, 116), Enum.Material.Concrete)
		local color = Color3.fromRGB(70, 100, 130)
		World.EstateGarages.garage_north = garageBlock(garage, f * CFrame.new(0, 0, -plot.front), 4, plot.front + plot.back, 12, color, Enum.Material.Metal)
		sign(garage, "HIGHWAY GARAGE", Vector3.new(30, 3, 0.4), f * CFrame.new(0, 14.6, -plot.front - 0.3), Color3.fromRGB(120, 200, 255), Color3.fromRGB(34, 36, 40))
		for n = 0, 4 do
			cylinder(garage, "Tire", 1.4, 3.2, f * CFrame.new(-plot.w / 2 - 3, 0.7 + n * 1.45, plot.back - 4) * UPRIGHT, Color3.fromRGB(25, 25, 25), Enum.Material.Rubber)
		end
		barrel(garage, (f * CFrame.new(plot.w / 2 + 3, 0, plot.back - 3)).Position, Color3.fromRGB(170, 50, 40))
		barrel(garage, (f * CFrame.new(plot.w / 2 + 3, 0, plot.back - 6.5)).Position, Color3.fromRGB(60, 90, 150))
		forSaleSign(garage, "garage_north", f * CFrame.new(plot.w / 2 - 4, 0, -plot.front - reach + 3))
	end

	-- ── The towers ─────────────────────────────────────────────────────────────
	-- A tower is a hollow shell with real rooms only where you can go: the lobby, the office floors and the roof. Every
	-- room floor has a row of elevator doors on its back wall (the roof: on the lift's kiosk), one per other stop, a
	-- glowing pad in front of each: step on it and you ride to the floor written over the door. You arrive in front of
	-- the doors of that floor (World.EstateSpawns for an office floor).

	type TowerLook = { body: Color3, material: Enum.Material, trim: Color3, glass: Color3 }
	local TOWER_LOOKS: { [string]: TowerLook } = {
		dispatchtower = { body = Color3.fromRGB(64, 70, 84), material = Enum.Material.Concrete, trim = Color3.fromRGB(255, 186, 60), glass = Color3.fromRGB(110, 160, 196) },
		harborpoint = { body = Color3.fromRGB(176, 182, 186), material = Enum.Material.Concrete, trim = Color3.fromRGB(70, 200, 220), glass = Color3.fromRGB(120, 190, 210) },
	}

	local lastRide: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		lastRide[player] = nil
	end)

	-- A pad that takes whoever steps on it to `target` (a character's root frame). Not from a seat, not twice a second.
	local function ridePad(pad: BasePart, target: CFrame)
		pad.CanTouch = true
		pad.Touched:Connect(function(hit)
			local character = hit.Parent
			if not character or not character:IsA("Model") then
				return
			end
			local player = Players:GetPlayerFromCharacter(character)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not player or not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
				return
			end
			local now = os.clock()
			if now - (lastRide[player] or 0) < 1.5 then
				return
			end
			lastRide[player] = now
			character:PivotTo(target)
		end)
	end

	type Stop = { floor: number, label: string, y: number, backZ: number }

	-- The elevator doors and pads of one stop: one per other stop, along the wall at backZ (facing -Z).
	local function elevatorBank(parent: Instance, f: CFrame, here: number, stops: { Stop }, arrivals: { CFrame }, look: TowerLook)
		local stop = stops[here]
		local count = #stops - 1
		local k = 0
		for index, other in stops do
			if index == here then
				continue
			end
			k += 1
			local x = (k - (count + 1) / 2) * 12
			local y, z = stop.y, stop.backZ
			box(parent, "ElevatorFrame", f, x - 5, y, z - 0.3, x + 5, y + 10.2, z, look.body:Lerp(Color3.new(0, 0, 0), 0.4), Enum.Material.Metal)
			for _, side in { -1, 1 } do
				box(parent, "ElevatorDoor", f, x + side * 0.05, y, z - 0.6, x + side * 4, y + 9, z - 0.3, Color3.fromRGB(190, 194, 198), Enum.Material.Metal)
			end
			sign(parent, other.label, Vector3.new(9, 1.1, 0.1), f * CFrame.new(x, y + 9.6, z - 0.4), look.trim, Color3.fromRGB(24, 26, 30))
			local pad = box(parent, "ElevatorPad", f, x - 4, y, z - 6, x + 4, y + 0.15, z - 0.8, look.trim, Enum.Material.Neon)
			pad.CanCollide = false
			pad.Transparency = 0.25
			pad:SetAttribute("ElevatorTo", other.label)
			ridePad(pad, arrivals[index])
		end
	end

	-- An office floor: a desk with the company computer (the OfficePrompt), a meeting table, a lounge, the FOR SALE sign.
	local function officeRoom(parent: Instance, f: CFrame, y: number, half: number, id: string, look: TowerLook)
		local def = ESTATE[id]
		deco(box(parent, "Carpet", f, -half + 1, y, -half + 1, half - 1, y + 0.05, half - 1, Color3.fromRGB(70, 74, 86), Enum.Material.Fabric))
		-- the boss's desk by the front windows; the computer looks at the chair
		local desk = f * CFrame.new(-half + 16, y, -half + 14)
		part(parent, "Desk", Vector3.new(9, 0.4, 3.8), desk * CFrame.new(0, 3.2, 0), Color3.fromRGB(56, 44, 36), Enum.Material.Wood)
		for _, side in { -1, 1 } do
			part(parent, "DeskSide", Vector3.new(0.4, 3, 3.6), desk * CFrame.new(side * 4.2, 1.5, 0), Color3.fromRGB(40, 32, 26), Enum.Material.Wood)
		end
		local front = part(parent, "DeskFront", Vector3.new(8, 2.4, 0.3), desk * CFrame.new(0, 1.8, 1.7), Color3.fromRGB(40, 32, 26), Enum.Material.Wood)
		front.CanCollide = false
		part(parent, "MonitorStand", Vector3.new(0.4, 1, 0.4), desk * CFrame.new(0, 3.9, 0.6), Color3.fromRGB(30, 30, 32), Enum.Material.Metal)
		local computer = part(parent, "Computer", Vector3.new(4, 2.4, 0.3), desk * CFrame.new(0, 5.4, 0.6), Color3.fromRGB(20, 22, 26), Enum.Material.SmoothPlastic)
		local screen = Instance.new("SurfaceGui")
		screen.Face = Enum.NormalId.Front
		screen.PixelsPerStud = 40
		screen.LightInfluence = 0
		screen.Parent = computer
		local text = Instance.new("TextLabel")
		text.Size = UDim2.new(1, -8, 1, -8)
		text.Position = UDim2.fromOffset(4, 4)
		text.BackgroundColor3 = Color3.fromRGB(10, 26, 18)
		text.Text = "DISPATCH\nyour couriers · your safe"
		text.TextScaled = true
		text.Font = Enum.Font.Code
		text.TextColor3 = Color3.fromRGB(110, 255, 150)
		text.Parent = screen
		deco(part(parent, "Keyboard", Vector3.new(2.6, 0.1, 0.9), desk * CFrame.new(0, 3.45, -0.6), Color3.fromRGB(40, 40, 44), Enum.Material.SmoothPlastic))
		local chair = desk * CFrame.new(0, 0, -3)
		part(parent, "OfficeChair", Vector3.new(2.4, 0.6, 2.4), chair * CFrame.new(0, 2, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric)
		part(parent, "OfficeChairBack", Vector3.new(2.4, 3, 0.4), chair * CFrame.new(0, 3.8, -1.1), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric)
		part(parent, "OfficeChairFoot", Vector3.new(0.4, 1.7, 0.4), chair * CFrame.new(0, 0.85, 0), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
		local p = Instance.new("ProximityPrompt")
		p.Name = "OfficePrompt"
		p.ActionText = "Run your company"
		p.ObjectText = if def then def.name else "Office"
		p.HoldDuration = 0
		p.MaxActivationDistance = 10
		p.RequiresLineOfSight = false
		p:SetAttribute("Office", id)
		p.Parent = computer
		table.insert(World.OfficePrompts, { prompt = p, office = id })
		-- the meeting table, the lounge, shelves and plants
		diningSet(parent, f * CFrame.new(-half + 16, y, 6) * CFrame.Angles(0, math.pi / 2, 0), 10, Color3.fromRGB(230, 230, 226))
		sofa(parent, f * CFrame.new(half - 6, y, -half + 14) * CFrame.Angles(0, math.pi / 2, 0), look.trim:Lerp(Color3.new(0, 0, 0), 0.35), 10)
		coffeeTable(parent, f * CFrame.new(half - 12, y, -half + 14) * CFrame.Angles(0, math.pi / 2, 0))
		rug(parent, f * CFrame.new(half - 11, y + 0.05, -half + 14), 12, 14, Color3.fromRGB(196, 186, 170))
		for _, side in { -1, 1 } do
			bookshelf(parent, f * CFrame.new(side * (half - 5), y, half - 2.2))
			plant(parent, f * CFrame.new(side * (half - 3), y, -half + 3), 1.3)
		end
		sign(parent, if def then string.upper(def.name) else "OFFICE", Vector3.new(16, 2, 0.2), f * CFrame.new(0, y + 9, -half + 1.2) * CFrame.Angles(0, math.pi, 0), look.trim, Color3.fromRGB(24, 26, 30))
		-- the FOR SALE sign, facing the elevators
		forSaleSign(parent, id, f * CFrame.new(10, y, half - 24) * CFrame.Angles(0, math.pi, 0), true)
		ceilingLight(parent, f, -half / 2, y + 11, 0, 34)
		ceilingLight(parent, f, half / 2, y + 11, 0, 34)
	end

	local function buildTower(parent: Instance, tower: Map.Tower)
		local look = TOWER_LOOKS[tower.id] or TOWER_LOOKS.dispatchtower
		local model = folder(parent, tower.name)
		local f = plotFrame({ x = tower.x, z = tower.z, facing = tower.facing, district = tower.district, w = tower.w, front = tower.w / 2, back = tower.w / 2 }, WALK_TOP)
		local W, H = tower.w, tower.floorHeight
		local half = W / 2
		-- The offices on this tower's floors.
		local offices: { [number]: string } = {}
		for _, def in Config.Estate.Properties do
			local plot = Map.EstatePlots[def.id]
			if plot and plot.tower == tower.id and plot.floor then
				offices[plot.floor] = def.id
			end
		end
		local stops: { Stop } = { { floor = 1, label = "LOBBY", y = 0.4, backZ = half - 1 } }
		for floor = 2, tower.floors do
			local id = offices[floor]
			if id then
				local label = if floor == tower.floors then `{floor}F · PENTHOUSE` else `{floor}F · OFFICE`
				table.insert(stops, { floor = floor, label = label, y = Map.floorHeight(tower, floor) + 0.4, backZ = half - 1 })
			end
		end
		local roofY = tower.floors * H + 0.4
		table.insert(stops, { floor = tower.floors + 1, label = "ROOF", y = roofY, backZ = half - 13 })
		local arrivals: { CFrame } = {}
		for index, stop in stops do
			arrivals[index] = f * CFrame.new(0, stop.y + 3, stop.backZ - 14)
		end
		local room: { [number]: boolean } = { [1] = true }
		for floor in offices do
			room[floor] = true
		end

		-- The shell: real walls with windows on the room floors, plain bands with window strips in between.
		local body, material = look.body, look.material
		local floor = 1
		while floor <= tower.floors do
			local y0 = Map.floorHeight(tower, floor)
			if room[floor] then
				local y1 = y0 + H
				local glassOpening: { Opening } = { { at = 0, width = W - 10, bottom = 1.4, top = 10.4, glass = true } }
				if floor == 1 then
					wall(model, f, true, -half, half, -half + 0.5, y0, y1, {
						{ at = 0, width = 10, bottom = 0, top = 9.5 },
						{ at = -(half / 2 + 3), width = half - 12, bottom = 0.4, top = 9.5, glass = true },
						{ at = half / 2 + 3, width = half - 12, bottom = 0.4, top = 9.5, glass = true },
					}, body, material)
				else
					wall(model, f, true, -half, half, -half + 0.5, y0, y1, glassOpening, body, material)
				end
				wall(model, f, true, -half, half, half - 0.5, y0, y1, nil, body, material)
				for _, side in { -1, 1 } do
					wall(model, f, false, -half + 1, half - 1, side * (half - 0.5), y0, y1, glassOpening, body, material)
				end
				-- its floor; its ceiling unless the floor above is a room too (that one lays its own floor)
				box(model, "Floor", f, -half + 1, y0 - 0.6, -half + 1, half - 1, y0 + 0.4, half - 1, Color3.fromRGB(176, 172, 166), Enum.Material.Marble)
				if floor < tower.floors and not room[floor + 1] then
					box(model, "Ceiling", f, -half + 1, y1 - 0.6, -half + 1, half - 1, y1 + 0.4, half - 1, Color3.fromRGB(226, 226, 222), Enum.Material.SmoothPlastic)
				end
				floor += 1
			else
				local last = floor
				while last + 1 <= tower.floors and not room[last + 1] do
					last += 1
				end
				local y1 = Map.floorHeight(tower, last) + H
				wall(model, f, true, -half, half, -half + 0.5, y0, y1, nil, body, material)
				wall(model, f, true, -half, half, half - 0.5, y0, y1, nil, body, material)
				for _, side in { -1, 1 } do
					wall(model, f, false, -half + 1, half - 1, side * (half - 0.5), y0, y1, nil, body, material)
				end
				for level = floor, last do
					local y = Map.floorHeight(tower, level) + 6
					for side = 0, 3 do
						local window = deco(part(model, "Window", Vector3.new(W - 6, 5, 0.3), f * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, y, -half - 0.1), Color3.fromRGB(30, 38, 48), Enum.Material.Glass))
						if estateRng:NextNumber() < 0.3 then
							nightWindow(window)
						end
					end
				end
				floor = last + 1
			end
		end
		-- Corner trims up the whole height.
		local height = tower.floors * H
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				box(model, "Trim", f, sx * half - 1.2, 0, sz * half - 1.2, sx * half + 1.2, height + 1.5, sz * half + 1.2, body:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Metal)
			end
		end
		-- The roof: the slab, a glass railing, the lift's kiosk, a helipad, an antenna with a beacon, the name.
		box(model, "Roof", f, -half, height - 0.6, -half, half, height + 0.4, half, Color3.fromRGB(120, 120, 118), Enum.Material.Concrete)
		for _, edge in { { -half, -half, half, -half + 0.6 }, { -half, half - 0.6, half, half }, { -half, -half + 0.6, -half + 0.6, half - 0.6 }, { half - 0.6, -half + 0.6, half, half - 0.6 } } do
			local rail = box(model, "Railing", f, edge[1], height + 0.4, edge[2], edge[3], height + 4, edge[4], GLASS, Enum.Material.Glass)
			rail.Transparency = 0.5
		end
		local roofStop = stops[#stops]
		local kioskHalf = (#stops - 1) * 6 + 2
		box(model, "LiftKiosk", f, -kioskHalf, height + 0.4, roofStop.backZ, kioskHalf, height + 12, half - 3, body, material)
		box(model, "LiftKioskRoof", f, -kioskHalf - 1, height + 12, roofStop.backZ - 1, kioskHalf + 1, height + 12.8, half - 2, look.trim, Enum.Material.Metal)
		local helipad = cylinder(model, "Helipad", 0.2, 22, f * CFrame.new(0, height + 0.5, -half + 15) * UPRIGHT, Color3.fromRGB(60, 62, 66), Enum.Material.Concrete)
		helipad.CanCollide = false
		sign(model, "H", Vector3.new(8, 8, 0.05), f * CFrame.new(0, height + 0.62, -half + 15) * CFrame.Angles(-math.pi / 2, 0, 0), Color3.fromRGB(255, 255, 255), Color3.fromRGB(60, 62, 66))
		part(model, "Antenna", Vector3.new(0.8, 26, 0.8), f * CFrame.new(-half + 6, height + 13, half - 6), Color3.fromRGB(180, 180, 184), Enum.Material.Metal)
		local beacon = deco(part(model, "Beacon", Vector3.new(1.6, 1.6, 1.6), f * CFrame.new(-half + 6, height + 26.6, half - 6), Color3.fromRGB(140, 30, 30), Enum.Material.Glass))
		light(beacon, 40, 2, Color3.fromRGB(255, 50, 50))
		DayNight.nightLight(beacon, Color3.fromRGB(255, 40, 40), Color3.fromRGB(140, 30, 30), "Glass")
		-- the name on top, lit at night (front and back)
		for _, back in { false, true } do
			local turn = if back then CFrame.Angles(0, math.pi, 0) else CFrame.new()
			local at = f * turn * CFrame.new(0, height + 8, -half + 2)
			for _, side in { -1, 1 } do
				part(model, "SignPost", Vector3.new(0.6, 8, 0.6), at * CFrame.new(side * (half - 8), -4, 0.4), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
			end
			sign(model, string.upper(tower.name), Vector3.new(W - 12, 5, 0.4), at, look.trim, Color3.fromRGB(20, 22, 26))
		end
		local crown = deco(box(model, "Crown", f, -half - 1.3, height + 0.4, -half - 1.3, half + 1.3, height + 1.2, half + 1.3, look.trim:Lerp(Color3.new(0, 0, 0), 0.5), Enum.Material.Metal))
		DayNight.nightLight(crown, look.trim, crown.Color, "Metal")
		-- The entrance: a canopy with the name, lanterns, a plaza.
		box(model, "Canopy", f, -9, 10.2, -half - 6, 9, 10.8, -half, look.trim:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal)
		sign(model, string.upper(tower.name), Vector3.new(24, 2.2, 0.3), f * CFrame.new(0, 11.2, -half - 0.3), look.trim, Color3.fromRGB(20, 22, 26))
		local canopyLight = deco(box(model, "CanopyLight", f, -6, 10, -half - 4, 6, 10.2, -half - 2, Color3.fromRGB(150, 140, 110), Enum.Material.Glass))
		light(canopyLight, 26, 1.4, Color3.fromRGB(255, 226, 170))
		DayNight.nightLight(canopyLight, Color3.fromRGB(255, 230, 170), Color3.fromRGB(150, 140, 110), "Glass")
		deco(box(model, "Plaza", f, -half, 0, -half - 14, half, 0.06, -half, Color3.fromRGB(176, 170, 160), Enum.Material.Slate))
		for _, side in { -1, 1 } do
			box(model, "Planter", f, side * (half - 8) - 4, 0, -half - 12, side * (half - 8) + 4, 1.6, -half - 4, Color3.fromRGB(110, 106, 100), Enum.Material.Concrete)
			local p = (f * CFrame.new(side * (half - 8), 1.6, -half - 8)).Position
			tree(model, p.X, p.Z, p.Y)
		end

		-- The lobby: the reception, a waiting corner, plants, the office directory (the offices' listings).
		local lobbyY = stops[1].y
		deco(box(model, "LobbyRug", f, -6, lobbyY, -half + 1, 6, lobbyY + 0.05, half - 8, Color3.fromRGB(150, 40, 40), Enum.Material.Fabric))
		local reception = f * CFrame.new(-half + 14, lobbyY, -6)
		part(model, "Reception", Vector3.new(14, 4, 3), reception * CFrame.new(0, 2, 0), Color3.fromRGB(60, 50, 44), Enum.Material.Wood)
		part(model, "ReceptionTop", Vector3.new(14.4, 0.3, 3.4), reception * CFrame.new(0, 4.15, 0), Color3.fromRGB(226, 222, 214), Enum.Material.Marble)
		sign(model, string.upper(tower.name), Vector3.new(12, 1.6, 0.1), reception * CFrame.new(0, 2.4, -1.56), look.trim, Color3.fromRGB(24, 26, 30))
		bystander("clerk", "Mia, the receptionist", tower.name, reception * CFrame.new(0, 0, 3.4))
		sofa(model, f * CFrame.new(half - 6, lobbyY, -8) * CFrame.Angles(0, math.pi / 2, 0), look.trim:Lerp(Color3.new(0, 0, 0), 0.3), 10)
		coffeeTable(model, f * CFrame.new(half - 12, lobbyY, -8) * CFrame.Angles(0, math.pi / 2, 0))
		for _, spot in { { -half + 3, -half + 3 }, { half - 3, -half + 3 }, { half - 3, 6 } } do
			plant(model, f * CFrame.new(spot[1], lobbyY, spot[2]), 1.4)
		end
		local listing = 0
		for floorNo = 2, tower.floors do
			local id = offices[floorNo]
			if id then
				forSaleSign(model, id, f * CFrame.new(-half + 1.5, lobbyY, 4 + listing * 10) * CFrame.Angles(0, -math.pi / 2, 0), true)
				listing += 1
			end
		end
		ceilingLight(model, f, -half / 2, H - 0.6, 0, 36)
		ceilingLight(model, f, half / 2, H - 0.6, 0, 36)

		-- The offices.
		for floorNo, id in offices do
			officeRoom(model, f, Map.floorHeight(tower, floorNo) + 0.4, half, id, look)
		end
		-- The elevators: every stop's doors and pads, the arrival spots.
		for index, stop in stops do
			elevatorBank(model, f, index, stops, arrivals, look)
			local id = offices[stop.floor]
			if id then
				World.EstateSpawns[id] = arrivals[index]
			end
		end
	end

	-- The tower's block: a plaza sidewalk; the tower itself.
	buildTowerBlock = function(parent: Instance, towerId: string, cx: number, cz: number)
		local tower = Map.Towers[towerId]
		local block = folder(parent, if tower then tower.name else towerId)
		sidewalk(block, cx, cz, Color3.fromRGB(160, 156, 150))
		if tower then
			attempt(tower.name, function()
				buildTower(block, tower)
			end)
		end
	end

	-- ── Sunset Hills and the homes ─────────────────────────────────────────────
	-- Sunset Hills above the city (north-east of Downtown): the hills (terrain, cut away under the lot and the road), the
	-- gate on Sunset Drive, its lamps and turning circle, pines on the slopes. The mansions and the villas stand each in
	-- their own spot (buildHomes): the Hilltop Mansion up here, Ocean View on the coast with rocks, palms and a pier on
	-- the sea, Pinecrest among the pines, the Lakeside Villa with a jetty onto the frozen lake, the Sunset Villa.

	type Hill = { x: number, z: number, radius: number, depth: number }
	local HILLS: { Hill } = {
		{ x = 410, z = -900, radius = 120, depth = 85 },
		{ x = 420, z = -1080, radius = 110, depth = 78 },
		{ x = 670, z = -770, radius = 100, depth = 76 },
		{ x = 610, z = -1310, radius = 130, depth = 90 },
		{ x = 690, z = -1080, radius = 90, depth = 72 },
	}

	local function inLot(plot: Map.EstatePlot, x: number, z: number, margin: number): boolean
		local ax, az = Map.plotPoint(plot, -plot.w / 2 - margin, -plot.front - margin - 20)
		local bx, bz = Map.plotPoint(plot, plot.w / 2 + margin, plot.back + margin)
		return x > math.min(ax, bx) and x < math.max(ax, bx) and z > math.min(az, bz) and z < math.max(az, bz)
	end

	nearAnyLot = function(x: number, z: number, margin: number): boolean
		for _, plot in Map.EstatePlots do
			if inLot(plot, x, z, margin) then
				return true
			end
		end
		return false
	end

	buildSunsetHills = function(world: Instance)
		local hills = folder(world, "SunsetHills")
		local terrain = workspace.Terrain
		local drive: { Map.Segment } = {}
		for _, s in Map.Connectors do
			if s.name == "Sunset Drive" then
				table.insert(drive, s)
			end
		end
		local function nearDrive(x: number, z: number, margin: number): boolean
			for _, s in drive do
				local dx, dz = s.bx - s.ax, s.bz - s.az
				local t = math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / (dx * dx + dz * dz), 0, 1)
				if math.sqrt((x - s.ax - dx * t) ^ 2 + (z - s.az - dz * t) ^ 2) < s.width / 2 + margin then
					return true
				end
			end
			return false
		end
		-- The hills, then the lots and the road cut out of them; pines on the slopes.
		for _, hill in HILLS do
			terrain:FillBall(Vector3.new(hill.x, -hill.depth, hill.z), hill.radius, Enum.Material.Grass)
		end
		for _, plot in Map.EstatePlots do
			if plot.district == "sunsethills" then
				local ax, az = Map.plotPoint(plot, -plot.w / 2 - 6, -plot.front - 40)
				local bx, bz = Map.plotPoint(plot, plot.w / 2 + 6, plot.back + 6)
				local x0, x1 = math.min(ax, bx), math.max(ax, bx)
				local z0, z1 = math.min(az, bz), math.max(az, bz)
				terrain:FillBlock(CFrame.new((x0 + x1) / 2, 40.5, (z0 + z1) / 2), Vector3.new(x1 - x0, 80, z1 - z0), Enum.Material.Air)
			end
		end
		for _, s in drive do
			local frame, length = segmentFrame(s, 40.5)
			terrain:FillBlock(frame, Vector3.new(s.width + 16, 80, length + 16), Enum.Material.Air)
		end
		for _, hill in HILLS do
			local ground = math.sqrt(hill.radius ^ 2 - hill.depth ^ 2)
			for _ = 1, 9 do
				local angle = estateRng:NextNumber(0, math.pi * 2)
				local d = estateRng:NextNumber(0, ground * 0.8)
				local x, z = hill.x + math.cos(angle) * d, hill.z + math.sin(angle) * d
				if Map.inWater(x, z) or nearAnyLot(x, z, 8) or nearDrive(x, z, 10) then
					continue
				end
				pine(hills, x, z, -hill.depth + math.sqrt(hill.radius ^ 2 - d * d) - 1)
			end
		end
		-- The gate where the drive leaves Downtown: stone pillars, an arch with the name both ways, lanterns.
		local start, second = Map.SunsetDrive[1], Map.SunsetDrive[2]
		local a, b = Vector3.new(start[1], 0, start[2]), Vector3.new(second[1], 0, second[2])
		local gate = CFrame.lookAt(a + (b - a).Unit * 70, b) -- looking up the drive
		local stone = Color3.fromRGB(196, 170, 140)
		for _, side in { -1, 1 } do
			local pillar = gate * CFrame.new(side * (ROAD / 2 + 4), 0, 0)
			part(hills, "GatePillar", Vector3.new(5, 22, 5), pillar * CFrame.new(0, 11, 0), stone, Enum.Material.Sandstone)
			part(hills, "GatePillarCap", Vector3.new(6, 1.2, 6), pillar * CFrame.new(0, 22.6, 0), stone:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Sandstone)
			local lantern = deco(part(hills, "Lantern", Vector3.new(1.4, 2.2, 1.4), pillar * CFrame.new(0, 24.4, 0), Color3.fromRGB(150, 140, 110), Enum.Material.Glass))
			light(lantern, 30, 1.4, Color3.fromRGB(255, 200, 140))
			DayNight.nightLight(lantern, Color3.fromRGB(255, 210, 140), Color3.fromRGB(150, 140, 110), "Glass")
			for k = 1, 3 do
				local p = (pillar * CFrame.new(side * (6 + k * 7), 0, estateRng:NextNumber(-3, 3))).Position
				pine(hills, p.X, p.Z, 0)
			end
		end
		part(hills, "GateArch", Vector3.new(ROAD + 14, 3, 4), gate * CFrame.new(0, 21, 0), stone, Enum.Material.Sandstone)
		for _, way in { 1, -1 } do
			sign(hills, "SUNSET HILLS", Vector3.new(ROAD + 6, 3.4, 0.3), gate * CFrame.Angles(0, if way == 1 then math.pi else 0, 0) * CFrame.new(0, 21, -2.2), Color3.fromRGB(255, 170, 90), Color3.fromRGB(60, 34, 30))
		end
		-- Lamps along the drive (not on a driveway), the turning circle at its end.
		for n, s in drive do
			local frame, length = segmentFrame(s, ROAD_TOP)
			local count = math.max(1, math.floor(length / 70))
			for k = 1, count do
				local side = if (n + k) % 2 == 0 then 1 else -1
				local p = (frame * CFrame.new(side * (s.width / 2 + 3), 0, (k / (count + 1) - 0.5) * length)).Position
				if Map.inYard(p.X, p.Z) or nearAnyLot(p.X, p.Z, 2) then
					continue
				end
				lamp(hills, p.X, p.Z, 0, frame.RightVector * -side, k % 2 == 0)
			end
		end
		local last = Map.SunsetDrive[#Map.SunsetDrive]
		cylinder(hills, "TurningCircle", 0.4, ROAD * 1.6, CFrame.new(last[1], ROAD_TOP - 0.25, last[2]) * UPRIGHT, ASPHALT, Enum.Material.Asphalt)
	end

	-- Every mansion and villa where Map.EstatePlots puts it, with what its spot calls for.
	local function buildHomes(world: Instance)
		local homes = folder(world, "Homes")
		for _, def in Config.Estate.Properties do
			local plot = Map.EstatePlots[def.id]
			local style = HOME_STYLES[def.id]
			if not plot or not style or (def.kind ~= "mansion" and def.kind ~= "villa") then
				continue
			end
			attempt(def.name, function()
				if def.kind == "mansion" then
					mansion(homes, def.id, plot, style)
				else
					villa(homes, def.id, plot, style)
				end
			end)
		end
		-- Ocean View: a pier on the sea behind the garden, palms and rocks along the cliff edge.
		local oceanview = Map.EstatePlots.oceanview
		if oceanview then
			attempt("Ocean View's coast", function()
				local bx, bz = Map.plotPoint(oceanview, -10, oceanview.back)
				pier(homes, Vector3.new(bx, 0.6, bz), Vector3.new(Map.Sea.x0 + 70, 0.6, bz))
				for _, dz in { -44, -22, 18, 40 } do
					palm(homes, Map.Sea.x0 - 14, bz + dz, 0)
				end
				for k = 1, 9 do
					local z = bz - 100 + k * 20
					if math.abs(z - bz) < 10 then
						continue -- the pier
					end
					local rock = part(homes, "Rock", Vector3.new(estateRng:NextNumber(6, 12), estateRng:NextNumber(4, 9), estateRng:NextNumber(6, 12)), CFrame.new(Map.Sea.x0 - 4, 1, z) * CFrame.Angles(estateRng:NextNumber(-0.3, 0.3), estateRng:NextNumber(0, 3), estateRng:NextNumber(-0.3, 0.3)), Color3.fromRGB(120, 112, 104), Enum.Material.Rock)
					rock.CanCollide = true
				end
			end)
		end
		-- The Lakeside Villa: a jetty from its side garden out onto the frozen lake.
		local lakeside = Map.EstatePlots.lakeside
		if lakeside then
			attempt("the Lakeside jetty", function()
				local sx, sz = Map.plotPoint(lakeside, -lakeside.w / 2, 12)
				pier(homes, Vector3.new(sx, 0.6, sz), Vector3.new(Map.Lake.x1 - 40, 0.6, sz))
			end)
		end
		-- Pinecrest: a pine wood all around the lot.
		local pinecrest = Map.EstatePlots.pinecrest
		if pinecrest then
			for _ = 1, 26 do
				local right = estateRng:NextNumber(-pinecrest.w / 2 - 50, pinecrest.w / 2 + 50)
				local back = estateRng:NextNumber(-pinecrest.front - 10, pinecrest.back + 50)
				local x, z = Map.plotPoint(pinecrest, right, back)
				local rx, rz = Map.nearestRoad(x, z)
				if inLot(pinecrest, x, z, 6) or math.sqrt((x - rx) ^ 2 + (z - rz) ^ 2) < ROAD / 2 + 8 then
					continue
				end
				pine(homes, x, z, 0)
			end
		end
	end

	-- The real estate outside the blocks: the mansions and the villas, the houses on their own lots (Birch Cottage) and
	-- the Highway Garage. (The houses on the Suburbs lots, the lockup, the parking house and the towers are built with
	-- their districts, Sunset Hills' drive and hills by buildSunsetHills.)
	buildEstate = function(world: Instance)
		local estate = folder(world, "Estate")
		buildHomes(estate)
		for _, def in Config.Estate.Properties do
			local plot = Map.EstatePlots[def.id]
			if plot and def.kind == "house" and Map.blockAt(plot.x, plot.z) == nil then
				attempt(`house {def.id}`, function()
					estateHouse(estate, def.id, plot, HOME_STYLES[def.id] or HOME_STYLES.elm)
				end)
			end
		end
		attempt("Highway Garage", function()
			buildHighwayGarage(estate)
		end)
		-- Every property got its spots? (A failed build leaves a fallback in front of the plot, so nothing breaks.)
		for _, def in Config.Estate.Properties do
			local plot = Map.EstatePlots[def.id]
			if not plot then
				continue
			end
			local ground = groundAt(plot.x, plot.z)
			local fx, fz = Map.plotPoint(plot, 0, -plot.front - GARAGE_APRON)
			local out = Vector3.new(plot.facing.x, 0, plot.facing.z)
			if def.kind ~= "office" and not World.EstateGarages[def.id] then
				warn(`[World] {def.id}: no garage spot, using the front of the plot`)
				World.EstateGarages[def.id] = CFrame.lookAt(Vector3.new(fx, ground + 0.5, fz), Vector3.new(fx, ground + 0.5, fz) + out)
			end
			if (def.kind ~= "garage") and not World.EstateSpawns[def.id] then
				warn(`[World] {def.id}: no spawn, using the front of the plot`)
				World.EstateSpawns[def.id] = CFrame.lookAt(Vector3.new(fx, ground + 3, fz), Vector3.new(fx, ground + 3, fz) - out)
			end
		end
	end
end
defineRealEstate()

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

-- Inside one of these areas or within `margin` of it.
local function nearArea(areas: { Map.Area }, x: number, z: number, margin: number): boolean
	for _, a in areas do
		if x > a.x0 - margin and x < a.x1 + margin and z > a.z0 - margin and z < a.z1 + margin then
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
		if Map.inWater(x, z) or insideDistrict(x, z, 20) or nearArea(Map.Yards, x, z, 30) or nearArea(Map.Clearings, x, z, 14) or Map.onIce(x, z)
			or nearArea({ Map.SunsetHills }, x, z, 10) or nearAnyLot(x, z, 12) then
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
		if Map.isSafe(x, z) or s.kind == "bridge" or s.name == "Ranch Road" or s.name == "Riding School Lane" or table.find(Map.EstateRoads, s.name or "") ~= nil or nearAnyLot(x, z, 30) or not clearOfSpots(x, z, 40) then
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

-- The day look (the clock and the night are server/DayNight.luau's; every client blends the night look over this,
-- client/Weather.luau). A sky with stars and a big moon for the night.
local function setLighting()
	Lighting.Brightness = 1.6
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(100, 100, 110)
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.StarCount = 3000
	sky.MoonAngularSize = 14
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting
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
	piece("Sunset Hills", function()
		buildSunsetHills(world)
	end)
	piece("estate", function()
		buildEstate(world)
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
	piece("ranch", function()
		buildRanch(world)
	end)
	piece("riding school", function()
		buildStables(world)
	end)
	piece("fuel depot", function()
		buildFuelDepot(world)
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
