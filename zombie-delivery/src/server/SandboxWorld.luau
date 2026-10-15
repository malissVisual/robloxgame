--!strict
-- 8.0 SANDBOX, the map (design/sandbox/KONTRAKT.md; the owner: "an easy map, everything light: one house for the
-- missions, a van, a warehouse"): builds the small test world once, in place of the city, from shared/SandboxMap.luau
-- (the fixed plots, roads, turnaround and house) and shared/SandboxScenery.luau (its dress as plain numbers). Everything
-- is anchored, in workspace.Sandbox:
--
--   Ground    the meadow's tiles (Grass, their top at GroundTop), a concrete pad on every plot (the warehouse worker's
--             building stands on it; its top flush with the meadow), the house's lawn, a few gentle mounds (big
--             buried balls: a vehicle's free-room box query passes this folder, Config.SpawnSpot.Pass, or their
--             whole boxes would fill the map)
--   Roads     the asphalt of SandboxMap.Roads and the turnaround (its top a hair under Pražská's where they overlap),
--             the gravel shoulders down to the meadow on every edge (the cars roll off and on anywhere), the markings
--             (Jinočany: the village's streets a slab each, attribute Road = its name, their shoulders as every road's;
--             no markings on them yet)
--   House     "TheOldFarmstead" (a Model, attribute SandboxHouse): shared/ChaletLooks.luau's chalet (the stand-in look)
--             on SandboxMap.House.house,
--             facing north to the road, its front door the part "FrontDoor" (attribute SandboxDoor = true, no collision:
--             server/Moving.luau puts its "Enter house" prompt there) at House.door; the path from the curb to it, the
--             garden's fence and gate (THE OLD FARMSTEAD over it), the mailbox, the flower boxes (all decoration). 8.1: the
--             chalet's parts in the Model "House_sandbox_house" (attribute Home) on the owner's Blender house's box:
--             once ZDCHouseArt is imported, server/HouseMesh.luau dresses it (the chalet's parts hidden but still
--             colliding, its gable re-cut under the model's roof; the FrontDoor where the model's door is), the garden
--             beside it in "Garden"; no import: the chalet. 8.2: Atomic (with StreamingEnabled it streams whole). 8.3
--             the big move: the FrontDoor unseen behind its two leaves (FrontLeafWest, FrontLeafEast), the back door at
--             House.back ("BackDoor": SandboxBackDoor, unseen, no collision; its leaf "BackLeaf"): door leaves that
--             swing (shared/DoorSwing.luau: DoorLeaf -1 / 1 / -1, DoorSwing 1, DoorDark); dressed, all hidden with the
--             chalet and the model's doors copied as the leaves that swing ("FrontDoorLeaf" ×2, "BackDoorLeaf"). 8.5
--             walking through: the leaves swing out of the house (DoorSwing -1: seen against the dark doorway, never
--             behind it; 8.5.1 past square: Config.Moving.Doors.Wide), and the doorways are walkable: the House box
--             (unseen when dressed, what you bumped into) no longer collides nor stops a ray; its "HouseSolid" pieces do,
--             the box less a hall behind each doorway (Config.Moving.Doors.Hall Depth deep, the opening's width and
--             height), each hall lined dark ("DoorHalls": the house is a shell behind its walls, a camera that follows
--             you in sees a dark hall)
--   Houses    Jinočany step 1 (design/jinocany/NAVRH.md §3): every other house to empty (SandboxMap.Houses after the
--             farmstead) as a stand-in until the village's own look dresses it (SandboxWorld.standIn): a Model named
--             after the house (attribute SandboxHouse = its id, Atomic), its own parts in "House_<id>" (attribute
--             Home): a plain box of walls ("House") on its box with a red gable roof over it, its name on a board over
--             the front door, and the front door walked through as the farmstead's (SandboxWorld.walkIn: "FrontDoor",
--             attribute SandboxDoor, unseen, no collision, at its door; its two leaves; the box less a dark hall
--             behind the doorway). server/Moving.luau finds each house's FrontDoor by its model's SandboxHouse.
--   Scenery   the spruces (shared/AlpineLayout.luau's two-part trees, in Atomic chunks), the wildflowers, the rail fence
--             round the edge, the street lamps along Pražská, the signpost at the crossroads
--   Auction   8.8 (only while Config.Auction.On: the auction's groundwork shows nothing before the server's step): the
--             Auction House on Depot Row, east of the crossroads (shared/AuctionHouseLayout.luau's parts, its place
--             Config.Auction.House.Spot) in the Atomic model "AuctionHouse": its sign and lot display (SurfaceGuis the
--             client paints), the consignment desk's prompt (AuctionDesk), the lot's pedestal (AuctionLotStand), two lamps
--   Boundary  the invisible walls on the Bounds
--   Far       (a Persistent model: every client always has it) outside the Bounds: the far meadow, the green hills and
--             the snowy peaks that close the view; no collision but the far meadow's, no shadows
--
--   SandboxWorld.build()      builds it once (server/Main.server.luau at the server's start, sandbox mode) and lights
--                             it; returns workspace.Sandbox (a second call returns it as it is)
--   SandboxWorld.lighting()   the fixed warm afternoon at Jinočany's latitude, 50° north (Config.SandboxLight.Sky; the
--                             Alps' 47° before the Jinočany plan; in sandbox mode the city's DayNight and Weather do not
--                             run): the clock, the sun, the ambient light, the Atmosphere's soft far haze, the sky, the
--                             clouds and the colour grade; the workspace's clock attributes for whatever reads them
--   SandboxWorld.doorLeaves(house)   8.3 walk-in doors: the house's doors' leaves that swing (house's build does it;
--                             Jinočany: any house to empty, found by the model's SandboxHouse, the farmstead's without)
--   Jinočany, the hooks for a house to empty's own look (the village's art kit replaces the stand-in with them):
--   SandboxWorld.standIn(world, house)          the stand-in of a house of SandboxMap.Houses (its Model, built and
--                                               parented, its leaves made); SandboxWorld.build stands one on each
--                                               house after the farmstead
--   SandboxWorld.walkIn(model, body, house, frame)   a house's doors walked through: `body` (its Model "House_<id>")
--                                               holds its walls' box (a part "House", on house.house's box) and its
--                                               "FrontDoor" (the doorway at house.door, `frame` the door's: its foot
--                                               on the front wall, -Z out); makes the FrontDoor the moves' door
--                                               (SandboxDoor, unseen, no collision), its two leaves (FrontLeafWest,
--                                               FrontLeafEast), the back door where the house has one (house.back:
--                                               BackDoor, SandboxBackDoor; BackLeaf) and the dark halls behind them
--                                               (the walls' box no longer solid: HouseSolid pieces, DoorHalls).
--                                               doorLeaves after it (with the model parented) makes the leaves swing

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlpineLayout = require(Shared.AlpineLayout)
local AuctionHouseLayout = require(Shared.AuctionHouseLayout) -- 8.8: the Auction House (only while Config.Auction.On)
local ChaletLooks = require(Shared.ChaletLooks)
local Config = require(Shared.Config) -- 8.5 walk-in doors: the doors' halls (Config.Moving.Doors.Hall)
local RenderBudget = require(Shared.RenderBudget)
local SandboxMap = require(Shared.SandboxMap)
local SandboxScenery = require(Shared.SandboxScenery)

local HouseMesh = require(script.Parent.HouseMesh) -- 8.1: the owner's Blender house (design/blender-house)

local SandboxWorld = {}

local S = SandboxScenery
local MAP = SandboxMap
local C = SandboxScenery.Colors
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up
local POLE = Color3.fromRGB(50, 50, 54)
local LAMP_DIM = Color3.fromRGB(196, 194, 182)
local SIGN = Color3.fromRGB(238, 196, 48) -- the signpost's boards (an alpine walking sign's yellow)
local INK = Color3.fromRGB(30, 30, 34)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function material(name: string): Enum.Material
	local ok, found = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and found then found :: Enum.Material else Enum.Material.SmoothPlastic
end

-- ── The parts ──────────────────────────────────────────────────────────────

-- A shadow only from a part big enough to throw one you notice (SandboxScenery.Shadow, then RenderBudget's rule).
local function shadowFor(size: Vector3, cframe: CFrame): boolean
	local long = math.max(size.X, size.Y, size.Z)
	local short = math.min(size.X, size.Y, size.Z)
	local middle = size.X + size.Y + size.Z - long - short
	return long >= S.Shadow.Long and middle >= S.Shadow.Wide and RenderBudget.shadowFor(size, cframe)
end

local function dress(p: BasePart, parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, look: Enum.Material?)
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = look or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.CastShadow = shadowFor(size, cframe)
	p.Parent = parent
end

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, look: Enum.Material?): Part
	local p = Instance.new("Part")
	dress(p, parent, name, size, cframe, color, look)
	return p
end

local function wedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, look: Enum.Material?): WedgePart
	local p = Instance.new("WedgePart")
	dress(p, parent, name, size, cframe, color, look)
	return p
end

local function cornerWedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, look: Enum.Material?): CornerWedgePart
	local p = Instance.new("CornerWedgePart")
	dress(p, parent, name, size, cframe, color, look)
	return p
end

-- Decoration: nothing collides with it, no ray finds it.
local function deco<T>(p: T): T
	local part = p :: any
	part.CanCollide = false
	part.CanQuery = false
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A flat slab over a rect with its top at `top`, `depth` thick.
local function slab(parent: Instance, name: string, r: { x0: number, x1: number, z0: number, z1: number }, top: number, depth: number, color: Color3, look: Enum.Material): Part
	local p = block(parent, name, Vector3.new(r.x1 - r.x0, depth, r.z1 - r.z0), CFrame.new((r.x0 + r.x1) / 2, top - depth / 2, (r.z0 + r.z1) / 2), color, look)
	p.CastShadow = false
	return p
end

-- A board's text on one face (readable from that side).
local function label(board: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.4
	gui.MaxDistance = 320
	gui.Parent = board
	local text_ = Instance.new("TextLabel")
	text_.Name = "Label"
	text_.BackgroundTransparency = 1
	text_.Position = UDim2.fromScale(0.04, 0.12)
	text_.Size = UDim2.fromScale(0.92, 0.76)
	text_.Text = text
	text_.TextScaled = true
	text_.Font = Enum.Font.GothamBlack
	text_.TextColor3 = color
	text_.Parent = gui
end

-- A rail fence along segments: a post every `step` studs (one where two meet), `rails` long rails.
local function fenceRun(parent: Instance, segments: { SandboxScenery.Segment }, step: number, height: number, rails: number, color: Color3, solid: boolean)
	local seen: { [string]: boolean } = {}
	local y = MAP.GroundTop
	for _, s in segments do
		local a, b = Vector3.new(s.ax, y, s.az), Vector3.new(s.bx, y, s.bz)
		local length = (b - a).Magnitude
		local posts = math.max(1, math.floor(length / step + 0.5))
		for n = 0, posts do
			local p = a:Lerp(b, n / posts)
			local key = `{math.floor(p.X * 10 + 0.5)}_{math.floor(p.Z * 10 + 0.5)}`
			if not seen[key] then
				seen[key] = true
				local post = block(parent, "FencePost", Vector3.new(0.6, height + 0.3, 0.6), CFrame.new(p + Vector3.new(0, (height + 0.3) / 2, 0)), color, Enum.Material.Wood)
				if not solid then
					deco(post)
				end
			end
		end
		local frame = CFrame.lookAt((a + b) / 2, b)
		for r = 1, rails do
			local rail = block(parent, "FenceRail", Vector3.new(0.22, 0.42, length), frame * CFrame.new(0, height * r / rails - 0.3, 0), color, Enum.Material.WoodPlanks)
			if not solid then
				deco(rail)
			end
		end
	end
end

-- A square pyramid of four corner wedges (each one's apex over its (+X, -Z) corner, put at the pyramid's middle):
-- server/Alpine.luau's far peaks.
local function pyramid(parent: Instance, name: string, x: number, z: number, y: number, half: number, height: number, yaw: number, color: Color3, look: Enum.Material)
	for q = 0, 3 do
		local p = cornerWedge(parent, name, Vector3.new(half, height, half), CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, yaw + q * math.pi / 2, 0) * CFrame.new(-half / 2, 0, half / 2), color, look)
		deco(p)
		p.CastShadow = false
	end
end

-- ── The ground ─────────────────────────────────────────────────────────────

local function ground(world: Instance)
	local holder = folder(world, "Ground")
	local top = MAP.GroundTop
	local tiles = S.meadow()
	for _, t in tiles do
		slab(holder, "Meadow", t, top, 2, rgb(C.Meadow), Enum.Material.Grass)
	end
	for _, plot in MAP.Plots do
		local pad = slab(holder, "Pad", plot.rect, top, 2, rgb(C.Pad), Enum.Material.Concrete)
		pad:SetAttribute("Plot", plot.id)
	end
	slab(holder, "Lawn", MAP.House.lot, top, 2, rgb(C.Lawn), Enum.Material.Grass)
	for _, m in S.mounds() do
		local ball = block(holder, "Mound", Vector3.new(2 * m.radius, 2 * m.radius, 2 * m.radius), CFrame.new(m.x, top + m.height - m.radius, m.z), rgb(m.color), Enum.Material.Grass)
		ball.Shape = Enum.PartType.Ball
		ball.CastShadow = false
	end
end

-- ── The roads ──────────────────────────────────────────────────────────────

local function roads(world: Instance)
	local holder = folder(world, "Roads")
	local main, depot = MAP.Roads[1], MAP.Roads[2]
	local asphalt = rgb(C.Asphalt)
	local depth = S.RoadDepth
	local row = slab(holder, "Road", depot :: any, MAP.RoadTop, depth, asphalt, Enum.Material.Asphalt)
	row:SetAttribute("Road", depot.name)
	-- (Pražská from Depot Row's south edge: the junction is Depot Row's asphalt)
	local street = slab(holder, "Road", { x0 = main.x0, x1 = main.x1, z0 = depot.z1, z1 = main.z1 }, MAP.RoadTop, depth, asphalt, Enum.Material.Asphalt)
	street:SetAttribute("Road", main.name)
	for index, road in MAP.Roads do -- (Jinočany: the village's streets; they only touch each other: no flicker)
		if index > 2 then
			slab(holder, "Road", road :: any, MAP.RoadTop, depth, asphalt, Enum.Material.Asphalt):SetAttribute("Road", road.name)
		end
	end
	local T = MAP.Turnaround
	local disc = block(holder, "Turnaround", Vector3.new(depth, 2 * T.r, 2 * T.r), CFrame.new(T.x, S.TurnaroundTop - depth / 2, T.z) * UPRIGHT, asphalt, Enum.Material.Asphalt)
	disc.Shape = Enum.PartType.Cylinder
	disc.CastShadow = false
	local gravel = rgb(C.Shoulder)
	for _, r in S.ramps() do
		local frame = CFrame.fromMatrix(Vector3.new(r.x, r.y, r.z), Vector3.new(r.rx, 0, r.rz), Vector3.yAxis)
		local size = Vector3.new(r.sx, r.sy, r.sz)
		local p: BasePart = if r.kind == "corner"
			then cornerWedge(holder, "Shoulder", size, frame, gravel, Enum.Material.Pebble)
			else wedge(holder, "Shoulder", size, frame, gravel, Enum.Material.Pebble)
		p.CastShadow = false
	end
	local white = rgb(C.Line)
	for _, m in S.markings() do
		local at = Vector3.new(m.x, m.top + 0.025, m.z)
		local line = deco(block(holder, m.name, Vector3.new(m.width, 0.05, m.length), CFrame.lookAt(at, at + Vector3.new(m.dx, 0, m.dz)), white, Enum.Material.SmoothPlastic))
		line.CastShadow = false
	end
end

-- ── The house ──────────────────────────────────────────────────────────────

-- 8.1: dressed in the owner's Blender house (its roof's ridge across the house, from side to side), the chalet's gable
-- (its ridge from the front to the back) would stand out of that roof over the front and back walls, unseen but solid:
-- its two wedges, still solid and unseen, become a gable across the house, S.Chalet.Pitch steep, under the model's roof.
local function underMeshRoof(body: Model, frame: CFrame)
	local box = MAP.House.house
	local half = box.sz / 2
	local rise = half * math.tan(math.rad(S.Chalet.Pitch))
	local n = 0
	for _, p in body:GetChildren() do
		if p.Name == "Roof" and p:IsA("BasePart") then
			-- (a wedge's slope looks to its -Z: the front half's to the street, the back half's turned round)
			p.Size = Vector3.new(box.sx, rise, half)
			p.CFrame = frame * CFrame.new(0, box.sy + rise / 2, half / 2 + n * half) * CFrame.Angles(0, n * math.pi, 0)
			n += 1
		end
	end
end

-- 8.3 walk-in doors: the house's doors' leaves (shared/DoorSwing.luau's attributes; client/WalkDoors.luau swings them,
-- server/Moving.luau says when), the front door's two and the back door's one, each hinged at its opening's side
-- (DoorLeaf ±1), a dark doorway where it stood (DoorDark: the house's body behind it). 8.5: swinging out of the house
-- (DoorSwing -1, was 1: swung in, a leaf went behind its dark doorway at once and its swing was never seen; out it
-- swings in front of it, as the interior's swing out onto their porches). Dressed in the owner's Blender house (its
-- doors part of the model: still): leaves made like them just in front
-- of them (SandboxScenery.frontLeaves, backLeaves; models "FrontDoorLeaf", "BackDoorLeaf" in the model's own finishes,
-- HouseMesh.Looks), the chalet's own leaves hidden with it, swinging no more; else the chalet's own leaves (house's
-- build: FrontLeafWest, FrontLeafEast, BackLeaf). Never colliding, never in a ray's way. 8.5.1 (the owner: "the doors
-- just disappear"): they open Config.Moving.Doors.Wide degrees (DoorAngle), past square: square to the wall they were
-- edge-on to a camera walking up, two slivers by a black doorway. Returns the leaves. Jinočany: any house to empty
-- (its model's SandboxHouse: SandboxMap.Houses' id; none: the farmstead), its back door's only where it has one.
function SandboxWorld.doorLeaves(house: Model): { Instance }
	local H = MAP.house(house:GetAttribute("SandboxHouse")) or MAP.House
	local body = house:FindFirstChild("House_" .. H.id)
	local made: { Instance } = {}
	if not body then
		return made
	end
	if body:GetAttribute("MeshArt") == true then
		local doors: { { spot: SandboxMap.Spot, name: string, leaves: { SandboxScenery.FrontLeaf } } } = { { spot = H.door, name = "FrontDoorLeaf", leaves = S.frontLeaves() } }
		local back = H.back
		if back then
			table.insert(doors, { spot = back, name = "BackDoorLeaf", leaves = S.backLeaves() })
		end
		for _, door in doors do
			local d = door.spot
			local frame = CFrame.new(d.x, d.y, d.z) * CFrame.Angles(0, math.rad(d.yaw), 0)
			for _, leaf in door.leaves do
				local model = Instance.new("Model")
				model.Name = door.name
				for n, spec in leaf.parts do
					local look = HouseMesh.Looks[spec.finish]
					local turn = if spec.cylinder then CFrame.Angles(0, math.pi / 2, 0) else CFrame.new()
					local p = deco(block(model, spec.name, Vector3.new(spec.size[1], spec.size[2], spec.size[3]), frame * CFrame.new(spec.at[1], spec.at[2], spec.at[3]) * turn, look.color, look.material))
					p.Reflectance = look.reflectance or 0
					if spec.cylinder then
						p.Shape = Enum.PartType.Cylinder
					end
					if n == 1 then
						model.PrimaryPart = p
					end
				end
				model:SetAttribute("DoorLeaf", leaf.hinge)
				model:SetAttribute("DoorSwing", -1) -- (8.5: out of the house)
				model:SetAttribute("DoorAngle", Config.Moving.Doors.Wide) -- (8.5.1: their faces stay in sight)
				model:SetAttribute("DoorDark", true)
				model.Parent = house
				table.insert(made, model)
			end
		end
		return made
	end
	for _, name in { "FrontLeafWest", "FrontLeafEast", "BackLeaf" } do
		local leaf = body:FindFirstChild(name)
		if leaf then
			leaf:SetAttribute("DoorLeaf", if name == "FrontLeafWest" then -1 elseif name == "FrontLeafEast" then 1 else S.BackDoor.Hinge)
			leaf:SetAttribute("DoorSwing", -1) -- (8.5: out of the house)
			leaf:SetAttribute("DoorAngle", Config.Moving.Doors.Wide) -- (8.5.1)
			leaf:SetAttribute("DoorDark", true)
			table.insert(made, leaf)
		end
	end
	return made
end

-- 8.5 walk-in doors (the owner: "so it doesn't feel like I bumped into the door, but I keep walking smoothly"): the
-- doorways walkable. The House box (the chalet's body; unseen under the owner's Blender house, still what stopped you at
-- its door) no longer collides nor stops a ray; "HouseSolid" pieces of the house's own (unseen) do instead: the box less
-- a hall behind each doorway (the front door's, the back door's: Config.Moving.Doors.Hall Depth studs into the house,
-- the opening's width, the door's height), so you walk on through the open door while the trip's fade starts
-- (server/Moving.luau's WalkIn), the walls either side as solid as ever. Each hall lined dark in "DoorHalls" (its back,
-- sides, ceiling and floor, from just behind the model's own door: the house is a shell behind its walls, and a camera
-- that follows you in sees a dark hall, never the hollow model); decoration, never colliding. `frame`: the front door's
-- (its foot on the front wall, -Z out); `top`: the doorways' height. Jinočany: house `H` (SandboxMap.Houses'), its front
-- door looking any way (its box's width across the door, its depth back from it), a back door's hall only where it has
-- one (else the solid behind the front hall reaches the back wall).
local function doorHalls(model: Model, body: Model, H: SandboxMap.House, frame: CFrame, top: number)
	local box = H.house
	local hall = Config.Moving.Doors.Hall
	local house = body:FindFirstChild("House")
	if not (house and house:IsA("BasePart")) then
		return
	end
	local turned = H.door.yaw % 180 ~= 0 -- (its front to the west or the east: its width along Z)
	local w, h, d = if turned then box.sz else box.sx, box.sy, if turned then box.sx else box.sz
	local depth = math.min(hall.Depth, d / 2 - 1)
	local back = H.back
	-- the solid pieces, each a box x0 … x1, y0 … y1, z0 … z1 in the front door's frame (the house from z 0 back to d)
	local function solid(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
		local p = block(body, "HouseSolid", Vector3.new(x1 - x0, y1 - y0, z1 - z0), frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), house.Color, house.Material)
		p.Transparency = 1
		p.CastShadow = false
	end
	local ways: { { x: number, half: number, z0: number } } = { { x = 0, half = S.FrontDoor.Width / 2, z0 = 0 } }
	local linings: { { frame: CFrame, width: number } } = { { frame = frame, width = S.FrontDoor.Width } }
	if back then
		local backFrame = CFrame.new(back.x, back.y, back.z) * CFrame.Angles(0, math.rad(back.yaw), 0)
		local bx = frame:PointToObjectSpace(backFrame.Position).X -- (the back door's middle across the house, the front's frame)
		solid(-w / 2, w / 2, 0, h, depth, d - depth) -- (between the two halls)
		table.insert(ways, { x = bx, half = S.BackDoor.Width / 2, z0 = d - depth })
		table.insert(linings, { frame = backFrame, width = S.BackDoor.Width })
	else
		solid(-w / 2, w / 2, 0, h, depth, d) -- (behind the front door's hall: the rest of the house)
	end
	for _, way in ways do
		solid(-w / 2, way.x - way.half, 0, h, way.z0, way.z0 + depth)
		solid(way.x + way.half, w / 2, 0, h, way.z0, way.z0 + depth)
		solid(way.x - way.half, way.x + way.half, top, h, way.z0, way.z0 + depth) -- (over the doorway)
	end
	house.CanCollide = false
	house.CanQuery = false
	-- the halls' dark lining, each in its own door's frame (its foot on its wall, -Z out, the hall from z `from` to depth)
	local holder = folder(model, "DoorHalls")
	local dark = rgb(hall.Color)
	local from, t = 0.35, 0.1 -- (from just behind the model's own door, 0.34 deep in its pocket)
	local long = depth - from
	for _, way in linings do
		local half = way.width / 2
		local function line(size: Vector3, at: Vector3)
			deco(block(holder, "DoorHall", size, way.frame * CFrame.new(at), dark, Enum.Material.SmoothPlastic)).CastShadow = false
		end
		line(Vector3.new(way.width, top, t), Vector3.new(0, top / 2, depth - t / 2)) -- (its back)
		for _, side in { -1, 1 } do
			line(Vector3.new(t, top, long), Vector3.new(side * (half - t / 2), top / 2, from + long / 2))
		end
		line(Vector3.new(way.width, t, long), Vector3.new(0, top - t / 2, from + long / 2)) -- (its ceiling)
		line(Vector3.new(way.width, 0.04, long), Vector3.new(0, 0.02, from + long / 2)) -- (its floor, on the lawn)
	end
end

-- 8.3 the big move, 8.5 walk-in doors (the farmstead's build did it; Jinočany: every house to empty's): the house's
-- doors walked through. Its FrontDoor (in `body`, at H.door: `frame`) is the doorway, the moves' front door, unseen
-- (SandboxDoor, no collision: server/Moving.luau puts its "Enter house" prompt there), behind its two leaves (each
-- half of it, a part of their own, each its doorway's side: SandboxWorld.doorLeaves makes them door leaves, the doors'
-- swing is the client's); the back door at H.back where the house has one (the owner's model's, in the middle of its
-- back wall): its doorway "BackDoor" (attribute SandboxBackDoor, unseen, no collision: server/Moving.luau's second
-- way in) as the FrontDoor is to the front, S.BackDoor.Width wide, and its leaf; then the dark halls behind them
-- (doorHalls: the walls' box "House" no longer solid). All of them the house's own parts: the farmstead dressed in the
-- owner's model hides them with the chalet (copies of the model's doors swing instead: doorLeaves).
function SandboxWorld.walkIn(model: Model, body: Model, H: SandboxMap.House, frame: CFrame)
	local front = body:FindFirstChild("FrontDoor")
	if not (front and front:IsA("BasePart")) then
		return
	end
	front:SetAttribute("SandboxDoor", true)
	front.CanCollide = false
	local size = front.Size
	front.Transparency = 1
	front.CastShadow = false
	for _, side in { -1, 1 } do
		deco(block(body, if side < 0 then "FrontLeafWest" else "FrontLeafEast", Vector3.new(size.X / 2, size.Y, size.Z + 0.04),
			front.CFrame * CFrame.new(side * size.X / 4, 0, 0), front.Color, front.Material))
	end
	local back = H.back
	if back then
		local width = S.BackDoor.Width
		local backFrame = CFrame.new(back.x, back.y, back.z) * CFrame.Angles(0, math.rad(back.yaw), 0) * frame:ToObjectSpace(front.CFrame)
		local doorway = deco(block(body, "BackDoor", Vector3.new(width, size.Y, size.Z), backFrame, front.Color, front.Material))
		doorway:SetAttribute("SandboxBackDoor", true)
		doorway.Transparency = 1
		doorway.CastShadow = false
		deco(block(body, "BackLeaf", Vector3.new(width, size.Y, size.Z + 0.04), backFrame, front.Color, front.Material))
	end
	doorHalls(model, body, H, frame, size.Y) -- 8.5 walk-in doors: the doorways walkable, a dark hall behind each
end

-- Jinočany step 1: a house to empty of the village (SandboxMap.Houses after the farmstead) until the village's own look
-- dresses it: in the Model named after it (attribute SandboxHouse = its id; Atomic: it streams in whole, its door's
-- prompt with it), its own parts in "House_<id>" (attribute Home): its walls' box "House" on house.house (the village's
-- render), a red gable roof over it (its ridge along the front, decoration), the front door (ChaletLooks' door's size,
-- just outside the front wall at house.door) walked through as the farmstead's (SandboxWorld.walkIn), its name on a
-- board over the door (their numbers SandboxScenery.StandIn's). Returns the model (parented to `world`, its leaves door
-- leaves).
function SandboxWorld.standIn(world: Instance, H: SandboxMap.House): Model
	local look = S.StandIn
	local model = Instance.new("Model")
	model.Name = (string.gsub(H.name, "[^%w]", ""))
	model:SetAttribute("SandboxHouse", H.id)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local body = Instance.new("Model")
	body.Name = "House_" .. H.id
	body:SetAttribute("Home", H.id)
	body.Parent = model
	local box, door = H.house, H.door
	local frame = CFrame.new(door.x, door.y, door.z) * CFrame.Angles(0, math.rad(door.yaw), 0)
	local turned = door.yaw % 180 ~= 0
	local w, h, d = if turned then box.sz else box.sx, box.sy, if turned then box.sx else box.sz
	local walls = block(body, "House", Vector3.new(w, h, d), frame * CFrame.new(0, h / 2, d / 2), rgb(look.Render), Enum.Material.Plaster)
	body.PrimaryPart = walls
	model.PrimaryPart = walls
	-- (a wedge's slope looks to its -Z: the front half's to the street, the back half's turned round)
	local half = d / 2 + look.Eaves
	local rise = half * math.tan(math.rad(look.Pitch))
	for n = 0, 1 do
		deco(wedge(body, "Roof", Vector3.new(w + 2 * look.Eaves, rise, half), frame * CFrame.new(0, h + rise / 2, d / 2 + (n - 0.5) * half) * CFrame.Angles(0, n * math.pi, 0), rgb(look.Roof), Enum.Material.Slate))
	end
	local door3 = look.DoorSize -- (ChaletLooks' door's: just outside the front wall)
	block(body, "FrontDoor", Vector3.new(door3[1], door3[2], door3[3]), frame * CFrame.new(0, door3[2] / 2, -door3[3] / 2), rgb(look.Door), Enum.Material.Wood)
	local sign = look.Board
	local board = deco(block(body, "NameBoard", Vector3.new(math.min(w - 2, sign[1]), sign[2], 0.2), frame * CFrame.new(0, sign[3], -0.12), rgb(look.Sign), Enum.Material.WoodPlanks))
	board.CastShadow = false
	label(board, Enum.NormalId.Front, string.upper(H.name), Color3.fromRGB(250, 244, 228))
	SandboxWorld.walkIn(model, body, H, frame)
	model.Parent = world
	SandboxWorld.doorLeaves(model)
	return model
end

local function house(world: Instance): Model
	local H = MAP.House
	local model = Instance.new("Model")
	model.Name = "TheOldFarmstead"
	model:SetAttribute("SandboxHouse", H.id)
	-- 8.2 perf (design/performance/REPORT.md, section 9): with StreamingEnabled it streams in and out whole (its door's
	-- prompt, the garden and the owner's Blender house with it), never a house half there
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- 8.1: the house's own parts in a Model "House_<id>" (attribute Home), as World's buildHouse makes Marge's: the one
	-- server/HouseMesh.luau dresses (the garden stays out of it)
	local body = Instance.new("Model")
	body.Name = "House_" .. H.id
	body:SetAttribute("Home", H.id)
	body.Parent = model
	local door = H.door
	-- the front door's frame: its middle on the ground at the front wall, -Z out of the door (north, to the road)
	local frame = CFrame.new(door.x, door.y, door.z) * CFrame.Angles(0, math.rad(door.yaw), 0)
	local lot = H.lot
	local spec: ChaletLooks.Spec = {
		w = H.house.sx,
		d = H.house.sz,
		h = H.house.sy,
		lot = lot.x1 - lot.x0,
		front = (lot.x1 - lot.x0) / 2 - (door.z - lot.z0), -- (its own front fence is left out: the garden has one)
		seed = S.Chalet.Seed,
		render = S.Chalet.Render,
		shade = S.Chalet.Shade,
	}
	for _, piece in ChaletLooks.house(spec) do
		if piece.name == "Fence" then
			continue
		end
		local turn = piece.turn or { 0, 0, 0 }
		local at, size = piece.at, piece.size
		local cframe = frame * CFrame.new(at[1], at[2], at[3]) * CFrame.Angles(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
		local p = block(body, piece.name, Vector3.new(size[1], size[2], size[3]), cframe, rgb(piece.color), material(piece.material))
		if piece.shape == "Wedge" then
			p.Shape = Enum.PartType.Wedge
		elseif piece.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		if piece.name == "Door" then
			-- the moves' "Enter house" prompt goes here; nothing to bump into
			p.Name = "FrontDoor"
			p:SetAttribute("SandboxDoor", true)
			p.CanCollide = false
		elseif piece.name == "House" then
			body.PrimaryPart = p
			model.PrimaryPart = p
		elseif not piece.solid then
			deco(p)
		end
	end
	-- 8.3 the big move: the doors' leaves (shut, each a part of its own, each its doorway's side: SandboxWorld.doorLeaves
	-- makes them door leaves, the doors' swing is the client's) and the back door. The front door's two leaves in the
	-- FrontDoor's place, each half of it (it stays the doorway, the moves' front door, unseen: the leaves show the door);
	-- the back door at House.back (the owner's model's, in the middle of its back wall): its doorway "BackDoor" (attribute
	-- SandboxBackDoor, unseen, no collision: server/Moving.luau's second way in) as the FrontDoor is to the front,
	-- S.BackDoor.Width wide, and its leaf. All of them the house's own parts: dressed in the owner's model they are hidden
	-- with the chalet (copies of the model's doors swing instead: doorLeaves).
	SandboxWorld.walkIn(model, body, H, frame) -- (Jinočany: every house to empty's, the stand-ins' too)
	-- the owner's Blender house over it once imported (the chalet's parts hidden, the FrontDoor too: still the prompt's
	-- part, where the model's door is); else the chalet as it is
	if HouseMesh.dress(body, H.id) then
		underMeshRoof(body, frame)
	end

	-- The garden: the path from the curb's shoulder to the door, the fence round the lot with its gate, the board over
	-- the gate, the mailbox, the flower boxes. Decoration all: nothing stops a mover with a sofa.
	local garden = folder(model, "Garden")
	local path = S.Path
	local G = S.Garden
	local from = G.Front - 2.5 -- (the turnaround's shoulder reaches to about here)
	local to = door.z - 0.4 -- (the door's front)
	deco(block(garden, "Path", Vector3.new(path.x1 - path.x0, 0.1, to - from), CFrame.new((path.x0 + path.x1) / 2, MAP.GroundTop + 0.03, (from + to) / 2), rgb(C.Path), Enum.Material.Pebble)).CastShadow = false
	fenceRun(garden, S.garden(), G.Post, G.Height, 2, rgb(C.Fence), false)
	local wood, dark = rgb(C.Fence), Color3.fromRGB(70, 48, 32)
	local gx, gz = door.x, G.Front
	for _, side in { -1, 1 } do
		-- (over the fence's end posts)
		deco(block(garden, "GatePost", Vector3.new(0.9, 11, 0.9), CFrame.new(gx + side * G.Gate, 5.5, gz), wood, Enum.Material.Wood))
	end
	deco(block(garden, "GateBeam", Vector3.new(2 * G.Gate + 1.6, 0.8, 1), CFrame.new(gx, 11.2, gz), dark, Enum.Material.Wood))
	local name = deco(block(garden, "GateBoard", Vector3.new(9, 1.6, 0.25), CFrame.new(gx, 9.6, gz), Color3.fromRGB(150, 108, 66), Enum.Material.WoodPlanks))
	label(name, Enum.NormalId.Front, string.upper(H.name), Color3.fromRGB(250, 244, 228))
	label(name, Enum.NormalId.Back, string.upper(H.name), Color3.fromRGB(250, 244, 228))
	-- the mailbox outside the fence, left of the gate, its name board to the road
	local mx, mz = gx - G.Gate - 3.5, gz - 1.4
	deco(block(garden, "MailboxPost", Vector3.new(0.35, 3.4, 0.35), CFrame.new(mx, 1.7, mz), dark, Enum.Material.Wood))
	deco(block(garden, "Mailbox", Vector3.new(1.5, 1.1, 1.9), CFrame.new(mx, 3.95, mz), Color3.fromRGB(46, 84, 58), Enum.Material.Metal))
	local plate = deco(block(garden, "MailboxName", Vector3.new(3.2, 0.7, 0.12), CFrame.new(mx, 2.6, mz - 0.25), Color3.fromRGB(242, 236, 220), Enum.Material.Wood))
	label(plate, Enum.NormalId.Front, string.upper(H.name), INK)
	-- the flower boxes: by the gate inside the fence, either side of the door
	local blooms = { Color3.fromRGB(210, 38, 46), Color3.fromRGB(246, 196, 52), Color3.fromRGB(226, 96, 150), Color3.fromRGB(150, 92, 200) }
	for n, spot in { { gx - 10.5, gz + 2.2 }, { gx + 10.5, gz + 2.2 }, { gx - 5.8, door.z - 2.4 }, { gx + 5.8, door.z - 2.4 } } do
		deco(block(garden, "FlowerBox", Vector3.new(2.8, 1, 1.2), CFrame.new(spot[1], 0.5, spot[2]), Color3.fromRGB(132, 92, 58), Enum.Material.WoodPlanks))
		deco(block(garden, "Flowers", Vector3.new(2.5, 0.8, 0.95), CFrame.new(spot[1], 1.4, spot[2]), blooms[n], Enum.Material.Grass)).CastShadow = false
	end
	model.Parent = world
	SandboxWorld.doorLeaves(model) -- 8.3 walk-in doors: its doors' leaves swing (the model's doors copied when dressed)
	return model
end

-- ── 8.8 The Auction House ──────────────────────────────────────────────────

-- shared/AuctionHouseLayout.luau's parts (only while Config.Auction.On) in the Atomic model "AuctionHouse", dressed by
-- their tags: the sign's and the lot display's words (client/AuctionUi.luau paints them from the auction's view), the
-- desk's "Consign a piece" prompt (attribute AuctionDesk: the client opens the window), the lot's pedestal (attribute
-- AuctionLotStand: where the server's step shows the piece), the lamps' light.
local function auctionHouse(world: Instance): Model
	local H = Config.Auction.House
	local model = Instance.new("Model")
	model.Name = "AuctionHouse"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("AuctionHouse", true)
	local cream, gold = Color3.fromRGB(250, 242, 222), Color3.fromRGB(255, 206, 92)
	local function surface(part: BasePart, face: Enum.NormalId, names: { string }, boxes: { { number } }, texts: { string }, colors: { Color3 })
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Words"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.3
		gui.MaxDistance = H.Range
		for n, name in names do
			local b = boxes[n]
			local line = Instance.new("TextLabel")
			line.Name = name
			line.BackgroundTransparency = 1
			line.Position = UDim2.fromScale(b[1], b[2])
			line.Size = UDim2.fromScale(b[3], b[4])
			line.Text = texts[n] or ""
			line.TextScaled = true
			line.Font = if n == 1 or b[4] >= 0.2 then Enum.Font.GothamBlack else Enum.Font.GothamBold
			line.TextColor3 = colors[n] or cream
			line.TextXAlignment = if b[5] == 1 then Enum.TextXAlignment.Left elseif b[5] == 2 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
			line.Parent = gui
		end
		gui.Parent = part
	end
	for _, spec in AuctionHouseLayout.parts() do
		local size = Vector3.new(spec.sx, spec.sy, spec.sz)
		local frame = CFrame.new(spec.x, spec.y, spec.z) * CFrame.Angles(0, math.rad(spec.yaw), 0)
		local p: BasePart = if spec.shape == "wedge"
			then wedge(model, spec.name, size, frame, rgb(spec.color), material(spec.material))
			else block(model, spec.name, size, frame, rgb(spec.color), material(spec.material))
		if not spec.solid then
			deco(p)
		end
		p.Transparency = spec.alpha or 0
		if spec.tag == "sign" then -- (its words: Title, and Next: the client's "Next auction in 12:34")
			surface(p, Enum.NormalId.Front, AuctionHouseLayout.SignLabels, { { 0.03, 0.06, 0.94, 0.58 }, { 0.03, 0.66, 0.94, 0.28 } }, { "AUCTION HOUSE", "" }, { gold, cream })
		elseif spec.tag == "screen" then -- (the lot on the podium: the client writes it; built empty but for the title)
			surface(p, Enum.NormalId.Front, AuctionHouseLayout.ScreenLabels,
				{ { 0.04, 0.05, 0.92, 0.11 }, { 0.04, 0.19, 0.92, 0.2 }, { 0.04, 0.41, 0.92, 0.1 }, { 0.04, 0.53, 0.92, 0.24 }, { 0.04, 0.8, 0.6, 0.13, 1 }, { 0.66, 0.8, 0.3, 0.13, 2 } },
				{ "AUCTION HOUSE", "No lot on the podium", "", "", "", "" }, { gold, cream, cream, gold, cream, cream })
		elseif spec.tag == "notice" then -- (faces the hall: the part's -X)
			surface(p, Enum.NormalId.Left, { "Title", "Line" }, { { 0.05, 0.08, 0.9, 0.5 }, { 0.05, 0.62, 0.9, 0.28 } }, { "CONSIGN HERE", "rare · epic · legendary" }, { gold, cream })
		elseif spec.tag == "desk" then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "AuctionDeskPrompt"
			prompt.ActionText = "Consign a piece"
			prompt.ObjectText = "Auction desk"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt:SetAttribute("AuctionDesk", true)
			prompt.Parent = p
		elseif spec.tag == "stand" then
			p:SetAttribute("AuctionLotStand", true)
		elseif spec.tag == "lamp" then
			local light = Instance.new("PointLight")
			light.Brightness = H.Lamp.Brightness
			light.Range = H.Lamp.Range
			light.Color = rgb(H.Lamp.Color)
			light.Shadows = false
			light.Parent = p
		end
	end
	model.Parent = world
	return model
end

-- ── The scenery ────────────────────────────────────────────────────────────

-- A tree's or a flower's part from AlpineLayout's numbers (a trunk cylinder standing up, a needle spire ellipsoid).
local function treePart(parent: Instance, spec: AlpineLayout.PartSpec): Part
	local frame = CFrame.new(spec.x, spec.y, spec.z) * CFrame.Angles(0, spec.yaw, 0)
	local p: Part
	if spec.shape == "cylinder" then
		p = block(parent, spec.name, Vector3.new(spec.sy, spec.sx, spec.sz), frame * UPRIGHT, rgb(spec.color), material(spec.material))
		p.Shape = Enum.PartType.Cylinder
	else
		p = block(parent, spec.name, Vector3.new(spec.sx, spec.sy, spec.sz), frame, rgb(spec.color), material(spec.material))
		if spec.shape == "ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
	end
	if not spec.collide then
		deco(p)
	end
	return p
end

local function scenery(world: Instance)
	local holder = folder(world, "Scenery")
	-- the trees, one Atomic model a chunk (streamed together)
	local trees = folder(holder, "Trees")
	local chunks: { [string]: Model } = {}
	for _, t in S.trees() do
		local model = chunks[t.chunk]
		if not model then
			local made = Instance.new("Model")
			made.Name = `Trees_{t.chunk}`
			made.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			chunks[t.chunk] = made
			model = made
		end
		for _, spec in AlpineLayout.treeParts(t) do
			treePart(model, spec)
		end
	end
	for _, model in chunks do
		model.Parent = trees
	end
	-- the wildflowers
	local meadow = folder(holder, "Wildflowers")
	for _, f in S.flowers() do
		local bloom = deco(block(meadow, "Flower", Vector3.new(f.size, f.size, f.size), CFrame.new(f.x, f.y, f.z), rgb(f.color), Enum.Material.SmoothPlastic))
		bloom.Shape = Enum.PartType.Ball
		bloom.CastShadow = false
	end
	-- the rail fence round the world
	fenceRun(folder(holder, "Fence"), S.fence(), S.FencePost, 3.6, 2, rgb(C.Fence), true)
	-- the street lamps (a fixed afternoon: their heads stay dim, no lights)
	local lamps = folder(holder, "Lamps")
	local up = Vector3.new(0, 0.3, 0)
	for _, l in S.lamps() do
		local y = MAP.GroundTop
		local out = Vector3.new(l.rx, 0, l.rz)
		block(lamps, "LampPole", Vector3.new(0.6, 16, 0.6), CFrame.new(l.x, y + 8, l.z), POLE, Enum.Material.Metal)
		local foot = Vector3.new(l.x, y + 15.8, l.z)
		deco(block(lamps, "LampArm", Vector3.new(0.35, 0.35, 4.4), CFrame.lookAt(foot + out * 2.2, foot + out * 4.4), POLE, Enum.Material.Metal))
		local at = foot + out * 4.2 - up
		deco(block(lamps, "LampHood", Vector3.new(2, 0.3, 1.4), CFrame.lookAt(at + up, at + up + out), POLE, Enum.Material.Metal))
		deco(block(lamps, "Lamp", Vector3.new(1.7, 0.3, 1.1), CFrame.lookAt(at, at + out), LAMP_DIM, Enum.Material.Glass))
	end
	-- the signpost at the crossroads: a post, three yellow boards (to the warehouses either way, to the farmstead)
	local sign = folder(holder, "Signpost")
	local s = S.Signpost
	block(sign, "SignPost", Vector3.new(0.7, 12, 0.7), CFrame.new(s.x, 6, s.z), Color3.fromRGB(96, 70, 48), Enum.Material.Wood)
	deco(block(sign, "SignCap", Vector3.new(1.1, 0.4, 1.1), CFrame.new(s.x, 12.2, s.z), POLE, Enum.Material.Metal))
	for _, b in S.signpost() do
		local reach = 4.4
		local at = Vector3.new(s.x + b.dx * reach, b.y, s.z + b.dz * reach)
		local face = if b.dz == 0 then Vector3.new(0, 0, -1) else Vector3.new(-1, 0, 0) -- (its front to the north, or the west)
		local board = deco(block(sign, "SignBoard", Vector3.new(8, 1.5, 0.25), CFrame.lookAt(at, at + face), SIGN, Enum.Material.SmoothPlastic))
		label(board, Enum.NormalId.Front, b.text, INK)
		label(board, Enum.NormalId.Back, b.back, INK)
	end
end

-- ── The edge and far away ──────────────────────────────────────────────────

local function boundary(world: Instance)
	local holder = folder(world, "Boundary")
	local b, h, t = MAP.Bounds, S.WallHeight, 2
	local black = Color3.new(0, 0, 0)
	for _, r in {
		{ x0 = b.x0, x1 = b.x1, z0 = b.z0, z1 = b.z0 + t },
		{ x0 = b.x0, x1 = b.x1, z0 = b.z1 - t, z1 = b.z1 },
		{ x0 = b.x0, x1 = b.x0 + t, z0 = b.z0, z1 = b.z1 },
		{ x0 = b.x1 - t, x1 = b.x1, z0 = b.z0, z1 = b.z1 },
	} do
		local wall = slab(holder, "InvisibleWall", r, MAP.GroundTop + h - 10, h, black, Enum.Material.SmoothPlastic)
		wall.Transparency = 1
		wall.CanQuery = false
	end
end

local function far(world: Instance)
	local model = Instance.new("Model")
	model.Name = "Far"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	for _, r in S.farGround() do
		slab(model, "FarMeadow", r, MAP.GroundTop, 2, rgb(C.Far), Enum.Material.Grass).CanQuery = false
	end
	for _, h in S.hills() do
		local ball = deco(block(model, "Hill", Vector3.new(2 * h.radius, 2 * h.radius, 2 * h.radius), CFrame.new(h.x, MAP.GroundTop + h.height - h.radius, h.z), rgb(h.color), Enum.Material.Grass))
		ball.Shape = Enum.PartType.Ball
		ball.CastShadow = false
	end
	local rock, snow = rgb(C.Rock), rgb(C.Snow)
	for _, p in S.peaks() do
		pyramid(model, "Peak", p.x, p.z, p.base, p.half, p.height, p.yaw, rock, Enum.Material.Slate)
		pyramid(model, "PeakSnow", p.x, p.z, p.capY, p.capHalf, p.capHeight, p.yaw, snow, Enum.Material.Snow)
	end
	model.Parent = world
end

-- ── The light ──────────────────────────────────────────────────────────────

function SandboxWorld.lighting()
	local L = S.Light
	Lighting.ClockTime = L.Clock
	Lighting.GeographicLatitude = L.Latitude
	Lighting.Brightness = L.Brightness
	Lighting.ExposureCompensation = L.Exposure
	Lighting.Ambient = rgb(L.Ambient)
	Lighting.OutdoorAmbient = rgb(L.Outdoor)
	Lighting.ColorShift_Top = rgb(L.ShiftTop)
	Lighting.ColorShift_Bottom = rgb(L.ShiftBottom)
	Lighting.EnvironmentDiffuseScale = L.Diffuse
	Lighting.EnvironmentSpecularScale = L.Specular
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = L.Softness
	Lighting.FogColor = rgb(L.Air)
	Lighting.FogStart = L.Fog[1]
	Lighting.FogEnd = L.Fog[2]
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.SunAngularSize = L.Sun
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting
	local air = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	air.Density = L.Density
	air.Offset = L.Offset
	air.Color = rgb(L.Air)
	air.Decay = rgb(L.Decay)
	air.Glare = L.Glare
	air.Haze = L.Haze
	air.Parent = Lighting
	local grade = Lighting:FindFirstChild("SandboxGrade") :: ColorCorrectionEffect? or Instance.new("ColorCorrectionEffect")
	grade.Name = "SandboxGrade"
	grade.TintColor = rgb(L.Tint)
	grade.Saturation = L.Saturation
	grade.Contrast = L.Contrast
	grade.Brightness = L.Lift
	grade.Enabled = true
	grade.Parent = Lighting
	local terrain = workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = L.Clouds.Cover
	clouds.Density = L.Clouds.Density
	clouds.Color = rgb(L.Clouds.Color)
	clouds.Enabled = true
	clouds.Parent = terrain
	-- (what the city's clock would have said: anything that still reads it sees a clear, still afternoon)
	workspace:SetAttribute("ClockHour", L.Clock)
	workspace:SetAttribute("ClockRate", 0)
	workspace:SetAttribute("Night", false)
	workspace:SetAttribute("Weather", "clear")
end

-- ── The build ──────────────────────────────────────────────────────────────

function SandboxWorld.build(): Folder
	local found = workspace:FindFirstChild("Sandbox")
	if found and found:IsA("Folder") then
		return found
	end
	local started = os.clock()
	local world = Instance.new("Folder")
	world.Name = "Sandbox"
	ground(world)
	roads(world)
	house(world)
	for index, h in MAP.Houses do -- (Jinočany: the village's houses to empty, each a stand-in for now)
		if index > 1 then
			SandboxWorld.standIn(world, h)
		end
	end
	scenery(world)
	if Config.Auction.On then -- 8.8: the Auction House, only once the auction is on (nothing of it shows before)
		auctionHouse(world)
	end
	boundary(world)
	far(world)
	world.Parent = workspace -- (in one go)
	SandboxWorld.lighting()
	local parts = 0
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[SandboxWorld] the sandbox world: %d parts, %d trees, in %.2f s", parts, #S.trees(), os.clock() - started))
	return world
end

return SandboxWorld
