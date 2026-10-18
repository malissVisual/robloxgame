--!strict
-- 7.0 prototype, the moving (design/rework/NAVRH.md): builds a house's inside (a shared/HouseLayout.luau plan) far
-- off the map, where a moving crew walks in through a fade: the floors, the walls with their doorways (plaster and
-- panelling by room, door frames), the ceiling and its lights, the windows' dim daylight, the kitchen's counters, the
-- bathroom, the garage, rugs, the front door with its EXIT sign and a porch of daylight outside it, and every piece of
-- furniture at its spot (shared/FurnitureLooks.luau). Nothing here runs per frame; the moving job
-- (server/Moving.luau) parents, uses and destroys what it builds.
--
--   HouseInterior.build(plan, origin)   the interior as a Model (unparented; its pivot `origin`, the plan's house origin:
--                                       the floor at the front door's middle, +Z into the house) and spot id → piece.
--                                       Everything is anchored; a piece's Root is anchored and holds its looks by welds
--                                       (unanchor the Root to carry it). A piece's model has the attributes Spot (its
--                                       spot id) and Star (★), under the folder "Items". The safety ground under the
--                                       house (Config.Furniture.Ground) and the walls and ceiling round it keep
--                                       everyone in; the porch's daylight wall stops a walk out of the front door.
--                                       10.x the map: the model's attribute MapPlan is the plan in one short string
--                                       (shared/SandboxMapRules.luau encode: its rooms, doorways, fixtures, windows
--                                       and the origin), the clients' big map and minimap draw a run's floor plan from it
--   HouseInterior.slot(index)          the origin of interior number `index` (0, 1, 2 ...): far off the map
--                                       (Config.Furniture.Slot, past Map.Bounds), Spacing apart, never overlapping
--   HouseInterior.destroy(model)        takes an interior down (pieces carried out of it are not in it any more)
--
-- StreamingEnabled: ask the client to stream the place in (player:RequestStreamAroundAsync(origin.Position)) before
-- a player is moved there.
-- 7.0 review: the windows' panes and the porch's daylight wall are the hour's: their daylight glow by day, a dark night
-- sky (no glow, the porch's light dim and moon blue) while the server's workspace attribute Night is on (read at the
-- build, then one listener for every interior standing: a few dozen parts, only when it turns).
-- 7.x alpine (the map is an Austrian alpine valley, its houses chalets): the house inside is a cosy chalet's. White
-- plaster over wood panelling (the wainscot), one plank floor of warm pine, a pine ceiling on dark beams, the Kachelofen
-- in the living room, the kitchen's corner bench under the Herrgottswinkel's shelf, rag rugs, lace in the windows,
-- antlers and alpine pictures on the walls, the front door's leaves painted with flowers, warm lamps; the bathroom and
-- the garage stay practical (tiles, concrete). Config.Furniture.Alpine has its numbers.
-- 8.3 the big house: a plan of kind "big" (shared/HouseLayout.luau: the sandbox's big house, a house's plan made
-- bigger, its guest room a bedroom's kind, its study a living room's) builds as a house, its lights and Neon as every
-- house's (Config.SandboxLight.House), its front door's two leaves as every house's (frontLeaves), and its back door (a
-- second doorway to the outside, in a side wall) gets a porch of daylight like the front door's and a leaf (sidePorch).
-- The owner's Blender furniture (design/blender-furniture/): once ZDCFurnitureArt is imported, server/FurnitureMesh.luau
-- dresses each piece in its models (the Root, its welds and its labels stay; without the import FurnitureLooks' look).
-- 8.3 walk-in doors (the sandbox, Config.Moving.Doors Swing): the front door's two leaves stand shut across the doorway,
-- door leaves of shared/DoorSwing.luau (the models "FrontDoorLeaf": DoorLeaf ±1 at the doorway's sides, DoorSwing -1
-- out onto the porch, DoorAngle 90), swung open by every client as you walk up to them (frontLeaves); the big house's
-- back door's leaf too (the part "BackLeaf": DoorLeaf 1, its +X jamb; sidePorch). Each a PathfindingModifier
-- PassThrough on its part: Danny's paths through it (swingOut).
-- 8.9.1 the house's fixtures in the owner's Blender model (design/blender-fixtures/KONTRAKT.md): each fixture of
-- FixtureMesh.Kinds (the kitchen's, the bathroom's, the Kachelofen, the garage's) is built in its own Model
-- "Fixture_<kind>" (attribute Fixture) in Decor, and once ZDCFixtureArt is imported server/FixtureMesh.luau dresses it
-- (its solid parts stay, hidden; without the import, or a fixture of another size, its parts as before). The rugs,
-- mats, stains, antlers and pictures stay loose in Decor.
-- 9.5 the countryside's spots: a plan of kind "cabin", "lodge", "mill" or "cottage" (shared/Layouts/Countryside.luau)
-- builds as a house in its own style (SPOTS: the walls, the wainscot, the floors, the ceiling and its beams, the lace;
-- its dice after a house's, so a house looks as it did): the Pond Cabin's dark stained boards, the Forest Lodge's
-- plaster over a high wainscot of logs, the Old Mill's stone workroom and whitewashed miller's room, the Orchard
-- Cottage's whitewash, its painted band and the kitchen's clay tiles. Their own fixtures' looks: the wood stove (its
-- pipe up to the ceiling), the net and the lifebuoy on the cabin's walls, the millstones under their hopper, the pit
-- wheel on the water wheel's shaft, the sack hoist and the hanging lanterns (no light of their own).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DoorSwing = require(Shared.DoorSwing) -- 8.3 walk-in doors: the front door's leaves swing
local FurnitureLooks = require(Shared.FurnitureLooks)
local FixtureMesh = require(script.Parent.FixtureMesh) -- 8.9.1: the fixtures in the owner's Blender model
local FurnitureMesh = require(script.Parent.FurnitureMesh)
local HouseLayout = require(Shared.HouseLayout)
local LightRules = require(Shared.SandboxLightRules) -- 8.5.2: the rooms' ceiling lamps
local MapRules = require(Shared.SandboxMapRules) -- 10.x the map: the floor plan published on the model (MapPlan)

local T = Config.Furniture
local LIT = Config.SandboxLight.House -- 8.3: the lights' numbers and the Neon's colours (Config.SandboxLight)
local HouseInterior = {}

local SMOOTH = Enum.Material.SmoothPlastic

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local function color(list: { number }): Color3
	return Color3.fromRGB(list[1], list[2], list[3])
end

-- The rooms' looks by kind (7.x alpine: a chalet's), one of each list picked per house by its dice: the plaster over
-- the panelling, the panelling (the wainscot: pine, a kids' room's painted; none in the bathroom, its tiles, nor the
-- garage), the floor (the planks one look under the whole house; the bathroom's tiles and the garage's concrete laid
-- over them).
local KINDS = { "hall", "living", "kitchen", "bedroom", "kids", "bath", "garage" } -- (the lists' order: the dice's)
local PLASTER: { [string]: { Color3 } } = {
	hall = { rgb(226, 216, 198), rgb(220, 210, 192) }, -- (8.3: a warm off-white, never a white: Config.SandboxLight.Caps.WallLuma)
	living = { rgb(228, 218, 200), rgb(224, 212, 192) },
	kitchen = { rgb(226, 218, 202), rgb(220, 212, 196) },
	bedroom = { rgb(224, 214, 204), rgb(218, 210, 214) },
	kids = { rgb(226, 216, 190), rgb(210, 222, 208) },
	bath = { rgb(206, 218, 220), rgb(214, 220, 218) },
	garage = { rgb(150, 152, 150), rgb(160, 150, 140) },
}
local PINE = { rgb(186, 134, 82), rgb(166, 114, 70), rgb(200, 150, 96) }
local PANELLING: { [string]: { Color3 } } = {
	hall = PINE,
	living = PINE,
	kitchen = PINE,
	bedroom = PINE,
	kids = { rgb(122, 160, 150), rgb(148, 178, 204), rgb(212, 160, 118) },
}
type Floor = { color: Color3, material: Enum.Material }
local PLANKS: { Floor } = {
	{ color = rgb(184, 132, 82), material = Enum.Material.WoodPlanks },
	{ color = rgb(198, 150, 96), material = Enum.Material.WoodPlanks },
	{ color = rgb(164, 114, 70), material = Enum.Material.WoodPlanks },
}
local FLOOR_OF: { [string]: Floor } = {
	bath = { color = rgb(214, 230, 236), material = Enum.Material.CeramicTiles },
	garage = { color = rgb(128, 128, 124), material = Enum.Material.Concrete },
}
local TRIM = rgb(222, 214, 200)
local WOODWORK = rgb(132, 88, 54) -- the door frames, the window frames and sills
local CEILING = rgb(204, 174, 132) -- pine boards (8.3: a shade darker round the lamps)
local BEAM = rgb(108, 72, 44)
local LACE = rgb(234, 228, 216)
local LAMP = color(LIT.Glow) -- a warm glow
local DAYLIGHT = color(LIT.Window) -- the windows' dim glow (Neon)
-- 7.0 review: the same at night (no glow): the panes, the bathroom's, the porch's wall; the porch light's share and hue
local NIGHT = { pane = rgb(28, 36, 58), bath = rgb(36, 44, 62), porch = rgb(24, 30, 48), light = 0.25, lightColor = rgb(150, 170, 220) }
type Daylit = { day: Color3, night: Color3, light: SurfaceLight?, brightness: number, color: Color3 }
local daylit: { [BasePart]: Daylit } = setmetatable({}, { __mode = "k" }) :: any
local watchingNight = false

-- Is it night now (the server's Night attribute: server/DayNight.luau)? Off the game (a recorder): day.
local function nightNow(): boolean
	local ok, night = pcall(function(): boolean
		return workspace:GetAttribute("Night") == true
	end)
	return ok and night == true
end

local function shade(p: BasePart, d: Daylit, night: boolean)
	p.Color = if night then d.night else d.day
	p.Material = if night then Enum.Material.SmoothPlastic else Enum.Material.Neon
	local light = d.light
	if light then
		light.Brightness = d.brightness * (if night then NIGHT.light else 1)
		light.Color = if night then NIGHT.lightColor else d.color
	end
end

-- A part that shows the daylight (and its light): shaded for the hour now, and again whenever the night turns.
local function daylight(p: BasePart, night: Color3, light: SurfaceLight?)
	local d: Daylit = { day = p.Color, night = night, light = light, brightness = if light then light.Brightness else 0, color = if light then light.Color else p.Color }
	daylit[p] = d
	shade(p, d, nightNow())
	if watchingNight then
		return
	end
	watchingNight = true
	pcall(function()
		workspace:GetAttributeChangedSignal("Night"):Connect(function()
			local night = nightNow()
			for part, info in daylit do
				if part.Parent then
					shade(part, info, night)
				else
					daylit[part] = nil
				end
			end
		end)
	end)
end
-- the rag rugs' colours; the kitchen's cabinets (pine, painted sage, painted blue, cream); the Kachelofen's tiles;
-- the bench's cushion; the front door's paint; the painted flowers; the pictures' skies
local RUGS = { rgb(170, 64, 56), rgb(64, 96, 140), rgb(200, 166, 80), rgb(96, 132, 98), rgb(150, 110, 150), rgb(228, 218, 196) }
local CABINETS = { rgb(198, 152, 100), rgb(132, 154, 122), rgb(104, 132, 150), rgb(232, 222, 196) }
local TILES = { rgb(64, 110, 84), rgb(198, 150, 70), rgb(232, 224, 204), rgb(110, 132, 150) }
local CUSHIONS = { rgb(176, 52, 48), rgb(64, 96, 140), rgb(96, 132, 98) }
local DOORS = { rgb(70, 104, 84), rgb(126, 56, 46), rgb(150, 104, 62) }
local BLOOMS = { rgb(206, 56, 52), rgb(244, 240, 228), rgb(236, 178, 60) }
local LEAF = rgb(70, 118, 66)
local SKIES = { rgb(130, 176, 222), rgb(236, 180, 150), rgb(170, 200, 226) }

-- The house's dice for its looks (the plan's seed: the same house looks the same).
local function dice(seed: number): (number) -> number
	local state = math.floor(math.abs(seed)) % 2147483646 + 7
	return function(n: number): number
		state = (state * 48271) % 2147483647
		return state % n + 1
	end
end

-- An anchored part; `solid` ones collide and are queried (walls, floors, counters), the rest are decoration.
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, c: Color3, material: Enum.Material?, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = c
	p.Material = material or SMOOTH
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.CastShadow = solid == true
	p.Parent = parent
	return p
end

local function cylinder(p: Part): Part
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function sign(p: BasePart, text: string, face: Enum.NormalId, fg: Color3, bg: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.MaxDistance = Config.Performance.SignRange -- 8.2 perf: small text, drawn only near
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	if bg then
		label.BackgroundColor3 = bg
	end
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = fg
	label.Parent = gui
	gui.Parent = p
end

-- ── The fixtures' looks ────────────────────────────────────────────────────────
-- Each in its own frame: `at` the bottom middle, the front -Z, size (along the wall, height, depth).
type FixtureLook = (Instance, CFrame, Vector3, (number) -> number) -> ()

-- (7.x alpine: wooden fronts, no metal handle bars; a scrubbed wooden worktop)
local function counterBody(parent: Instance, at: CFrame, s: Vector3, cabinet: Color3)
	part(parent, "Cabinet", Vector3.new(s.X, 2.8, s.Z - 0.15), at * CFrame.new(0, 1.4, 0.075), cabinet, Enum.Material.WoodPlanks, true)
	part(parent, "Worktop", Vector3.new(s.X, 0.2, s.Z), at * CFrame.new(0, 2.9, 0), rgb(150, 112, 74), Enum.Material.WoodPlanks, true)
end

local LOOKS: { [string]: FixtureLook } = {}
local cabinetColor = CABINETS[1]

LOOKS.counter = function(parent, at, s)
	counterBody(parent, at, s, cabinetColor)
end

LOOKS.sink = function(parent, at, s)
	counterBody(parent, at, s, cabinetColor)
	part(parent, "Basin", Vector3.new(1.8, 0.06, 1.3), at * CFrame.new(0, 3.01, -0.1), rgb(196, 200, 206), Enum.Material.Metal)
	part(parent, "Tap", Vector3.new(0.15, 0.8, 0.15), at * CFrame.new(0, 3.4, 0.75), rgb(196, 200, 206), Enum.Material.Metal)
	part(parent, "Spout", Vector3.new(0.12, 0.12, 0.6), at * CFrame.new(0, 3.75, 0.5), rgb(196, 200, 206), Enum.Material.Metal)
end

LOOKS.stove = function(parent, at, s)
	part(parent, "Stove", Vector3.new(s.X, 2.9, s.Z), at * CFrame.new(0, 1.45, 0), rgb(232, 232, 228), SMOOTH, true)
	part(parent, "Hob", Vector3.new(s.X - 0.2, 0.1, s.Z - 0.3), at * CFrame.new(0, 2.95, 0.05), rgb(24, 24, 26), Enum.Material.Glass)
	for _, x in { -0.65, 0.65 } do
		cylinder(part(parent, "Burner", Vector3.new(0.04, 0.75, 0.75), at * CFrame.new(x, 3.02, 0.05) * CFrame.Angles(0, 0, math.pi / 2), rgb(60, 60, 64), Enum.Material.Metal))
	end
	part(parent, "Oven", Vector3.new(s.X - 0.5, 1.5, 0.08), at * CFrame.new(0, 1.3, -s.Z / 2 - 0.02), rgb(40, 40, 44), Enum.Material.Glass)
	part(parent, "OvenHandle", Vector3.new(s.X - 0.8, 0.1, 0.1), at * CFrame.new(0, 2.2, -s.Z / 2 - 0.1), rgb(186, 190, 196), Enum.Material.Metal)
end

LOOKS.cabinets = function(parent, at, s)
	part(parent, "WallCabinet", s, at * CFrame.new(0, s.Y / 2, 0), cabinetColor, Enum.Material.WoodPlanks, true)
end

LOOKS.hood = function(parent, at, s)
	part(parent, "Hood", Vector3.new(s.X, 0.6, s.Z), at * CFrame.new(0, 0.3, 0), rgb(176, 180, 186), Enum.Material.Metal, true)
	part(parent, "Flue", Vector3.new(s.X * 0.45, s.Y - 0.6, s.Z * 0.55), at * CFrame.new(0, 0.6 + (s.Y - 0.6) / 2, s.Z * 0.2), rgb(176, 180, 186), Enum.Material.Metal)
end

LOOKS.tub = function(parent, at, s)
	part(parent, "Tub", s, at * CFrame.new(0, s.Y / 2, 0), rgb(246, 246, 244), SMOOTH, true)
	local water = part(parent, "Water", Vector3.new(s.X - 0.6, 0.06, s.Z - 0.6), at * CFrame.new(0, s.Y + 0.01, 0), rgb(150, 200, 226), Enum.Material.Glass)
	water.Transparency = 0.3
	part(parent, "Tap", Vector3.new(0.3, 0.6, 0.3), at * CFrame.new(s.X / 2 - 0.6, s.Y + 0.3, s.Z / 2 - 0.4), rgb(196, 200, 206), Enum.Material.Metal)
end

LOOKS.toilet = function(parent, at, s)
	local white = rgb(246, 246, 244)
	part(parent, "Base", Vector3.new(1.0, 1.2, 1.4), at * CFrame.new(0, 0.6, 0.2), white, SMOOTH, true)
	part(parent, "Bowl", Vector3.new(1.5, 0.45, 1.9), at * CFrame.new(0, 1.42, -0.15), white, SMOOTH, true)
	part(parent, "Seat", Vector3.new(1.5, 0.1, 1.7), at * CFrame.new(0, 1.7, -0.2), rgb(236, 236, 232), SMOOTH)
	part(parent, "Tank", Vector3.new(1.6, 1.4, 0.7), at * CFrame.new(0, 2.4, s.Z / 2 - 0.35), white, SMOOTH, true)
end

LOOKS.basin = function(parent, at, s)
	local white = rgb(246, 246, 244)
	part(parent, "Pedestal", Vector3.new(0.6, 2.5, 0.6), at * CFrame.new(0, 1.25, 0.2), white, SMOOTH, true)
	part(parent, "Basin", Vector3.new(s.X, 0.6, s.Z), at * CFrame.new(0, 2.8, 0), white, SMOOTH, true)
	part(parent, "Tap", Vector3.new(0.15, 0.5, 0.15), at * CFrame.new(0, 3.35, s.Z / 2 - 0.3), rgb(196, 200, 206), Enum.Material.Metal)
	part(parent, "MirrorFrame", Vector3.new(2.4, 3.0, 0.1), at * CFrame.new(0, 5.4, s.Z / 2 - 0.05), rgb(200, 196, 186), SMOOTH)
	local mirror = part(parent, "Mirror", Vector3.new(2.1, 2.7, 0.05), at * CFrame.new(0, 5.4, s.Z / 2 - 0.12), rgb(196, 214, 224), Enum.Material.Glass)
	mirror.Reflectance = 0.5
end

LOOKS.workbench = function(parent, at, s)
	local wood = rgb(170, 128, 82)
	part(parent, "Bench", Vector3.new(s.X, 0.3, s.Z), at * CFrame.new(0, s.Y - 0.15, 0), wood, Enum.Material.WoodPlanks, true)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(parent, "Leg", Vector3.new(0.3, s.Y - 0.3, 0.3), at * CFrame.new(x * (s.X / 2 - 0.3), (s.Y - 0.3) / 2, z * (s.Z / 2 - 0.3)), wood:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Wood, true)
		end
	end
	part(parent, "Shelf", Vector3.new(s.X - 0.6, 0.2, s.Z - 0.6), at * CFrame.new(0, 0.8, 0), wood, Enum.Material.WoodPlanks)
	part(parent, "Pegboard", Vector3.new(s.X, 3.4, 0.12), at * CFrame.new(0, s.Y + 2.1, s.Z / 2 - 0.06), rgb(190, 160, 120), Enum.Material.Cardboard)
	part(parent, "Vise", Vector3.new(0.7, 0.5, 0.6), at * CFrame.new(s.X / 2 - 0.6, s.Y + 0.25, -s.Z / 2 + 0.4), rgb(60, 90, 140), Enum.Material.Metal)
end

LOOKS.shelves = function(parent, at, s, roll)
	local metal = rgb(120, 126, 132)
	for _, x in { -1, 1 } do
		part(parent, "Upright", Vector3.new(0.2, s.Y, s.Z), at * CFrame.new(x * (s.X / 2 - 0.1), s.Y / 2, 0), metal, Enum.Material.Metal, true)
	end
	for n, y in { 0.4, 2.3, 4.2, 6.1 } do
		part(parent, "Shelf", Vector3.new(s.X - 0.4, 0.15, s.Z), at * CFrame.new(0, y, 0), metal, Enum.Material.Metal, true)
		if n <= 3 then
			local boxColor = ({ rgb(196, 158, 108), rgb(60, 110, 170), rgb(200, 70, 50), rgb(90, 150, 80) })[roll(4)]
			part(parent, "Bin", Vector3.new(1.6, 1.2, s.Z - 0.3), at * CFrame.new(-1.0 + (n - 1) * 0.9, y + 0.68, 0), boxColor, Enum.Material.Cardboard)
		end
	end
end

LOOKS.garage_door = function(parent, at, s)
	local metal = rgb(200, 204, 206)
	part(parent, "GarageDoor", s, at * CFrame.new(0, s.Y / 2, 0), metal, Enum.Material.Metal, true)
	for n = 1, 2 do
		part(parent, "Groove", Vector3.new(s.X, 0.12, 0.06), at * CFrame.new(0, n * s.Y / 3, -s.Z / 2 - 0.03), rgb(150, 154, 158), Enum.Material.Metal)
	end
end

LOOKS.fireplace = function(parent, at, s)
	local brick = rgb(160, 84, 64)
	part(parent, "Surround", s, at * CFrame.new(0, s.Y / 2, 0), brick, Enum.Material.Brick, true)
	part(parent, "Firebox", Vector3.new(2.8, 2.4, 0.6), at * CFrame.new(0, 1.4, -s.Z / 2 + 0.28), rgb(24, 20, 18), SMOOTH)
	part(parent, "Mantel", Vector3.new(s.X + 0.4, 0.35, s.Z + 0.4), at * CFrame.new(0, s.Y - 0.4, 0), rgb(110, 76, 50), Enum.Material.Wood, true)
	part(parent, "Hearth", Vector3.new(s.X + 0.6, 0.2, s.Z + 1.0), at * CFrame.new(0, 0.1, -0.3), rgb(110, 108, 104), Enum.Material.Slate, true)
	part(parent, "Chimney", Vector3.new(s.X * 0.7, T.Ceiling - s.Y, s.Z * 0.7), at * CFrame.new(0, s.Y + (T.Ceiling - s.Y) / 2, s.Z * 0.15), brick, Enum.Material.Brick, true)
	cylinder(part(parent, "Log", Vector3.new(2.0, 0.45, 0.45), at * CFrame.new(0, 0.55, -s.Z / 2 + 0.4), rgb(100, 66, 40), Enum.Material.Wood))
	part(parent, "Embers", Vector3.new(1.6, 0.2, 0.4), at * CFrame.new(0, 0.32, -s.Z / 2 + 0.45), rgb(255, 120, 40), Enum.Material.Neon)
end

-- 7.x alpine: the Kachelofen, a chalet's tiled stove: the tiled stove in two tiers under its cornice, the iron fire
-- door with the fire's glow through its slot, the wooden bench along its front (no light of its own: the lights are the
-- fuse box's)
LOOKS.kachelofen = function(parent, at, s, roll)
	local tile = TILES[roll(#TILES)]
	local back = s.Z / 2 -- (the wall)
	local deep = s.Z - 1.1 -- the stove's depth behind its bench
	local z = back - deep / 2
	part(parent, "Stove", Vector3.new(s.X - 0.8, 3.7, deep - 0.2), at * CFrame.new(0, 1.85, z + 0.1), tile, Enum.Material.CeramicTiles, true)
	part(parent, "Upper", Vector3.new(s.X - 2, 2.4, deep - 0.7), at * CFrame.new(0, 4.9, z + 0.35), tile:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.CeramicTiles, true)
	part(parent, "Cornice", Vector3.new(s.X - 1.6, s.Y - 6.1, deep - 0.4), at * CFrame.new(0, (6.1 + s.Y) / 2, z + 0.2), tile:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.CeramicTiles, true)
	local front = z + 0.1 - (deep - 0.2) / 2
	part(parent, "FireDoor", Vector3.new(1.3, 1.1, 0.1), at * CFrame.new(0, 2.4, front - 0.05), rgb(46, 42, 40), Enum.Material.Metal)
	part(parent, "Glow", Vector3.new(0.9, 0.14, 0.05), at * CFrame.new(0, 2.15, front - 0.12), rgb(255, 130, 50), Enum.Material.Neon)
	part(parent, "StoveBench", Vector3.new(s.X, 1.5, s.Z - deep), at * CFrame.new(0, 0.75, -s.Z / 2 + (s.Z - deep) / 2), PINE[roll(#PINE)], Enum.Material.WoodPlanks, true)
end

-- the kitchen's corner bench: its long leg (a seat on its plank base, the back against the wall, a cushion) and its
-- short leg (the same without the cushion)
local function bench(parent: Instance, at: CFrame, s: Vector3, roll: (number) -> number, cushion: boolean)
	local wood = PINE[roll(#PINE)]
	part(parent, "Seat", Vector3.new(s.X, 1.5, s.Z - 0.3), at * CFrame.new(0, 0.75, -0.15), wood, Enum.Material.WoodPlanks, true)
	part(parent, "Backrest", Vector3.new(s.X, s.Y - 1.5, 0.3), at * CFrame.new(0, (1.5 + s.Y) / 2, s.Z / 2 - 0.15), wood:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Wood, true)
	if cushion then
		part(parent, "Cushion", Vector3.new(s.X - 0.3, 0.16, s.Z - 0.6), at * CFrame.new(0, 1.58, -0.25), CUSHIONS[roll(#CUSHIONS)], Enum.Material.Fabric)
	end
end
LOOKS.corner_bench = function(parent, at, s, roll)
	bench(parent, at, s, roll, true)
end
LOOKS.bench = function(parent, at, s, roll)
	bench(parent, at, s, roll, false)
end

-- the Herrgottswinkel's corner shelf: a three-cornered board in its +X, +Z corner, a candle and a bunch of dried
-- flowers on it
LOOKS.corner_shelf = function(parent, at, s)
	local board = Instance.new("WedgePart")
	board.Name = "CornerShelf"
	board.Size = Vector3.new(0.15, s.X, s.Z) -- (turned: its triangle flat, the right angle in the corner)
	board.CFrame = at * CFrame.new(0, 0.075, 0) * CFrame.Angles(0, 0, math.pi / 2)
	board.Color = WOODWORK
	board.Material = Enum.Material.Wood
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.CastShadow = false
	board.Parent = parent
	cylinder(part(parent, "Candle", Vector3.new(0.7, 0.3, 0.3), at * CFrame.new(s.X / 2 - 0.45, 0.5, s.Z / 2 - 0.45) * CFrame.Angles(0, 0, math.pi / 2), rgb(244, 236, 214)))
	local flowers = part(parent, "DriedFlowers", Vector3.new(0.7, 0.7, 0.7), at * CFrame.new(s.X / 2 - 0.5, 0.5, s.Z / 2 - 1.05), rgb(196, 112, 74), Enum.Material.Fabric)
	flowers.Shape = Enum.PartType.Ball
end

-- the antlers on their shield (the beams spread up and out, a tine on each)
LOOKS.antlers = function(parent, at, s)
	local bone = rgb(226, 210, 176)
	local wall = s.Z / 2
	part(parent, "Plaque", Vector3.new(0.9, 1.2, 0.14), at * CFrame.new(0, 0.6, wall - 0.07), rgb(96, 62, 38), Enum.Material.Wood)
	for _, side in { -1, 1 } do
		part(parent, "Antler", Vector3.new(0.14, 1.35, 0.14), at * CFrame.new(side * 0.42, 1.2, wall - 0.25) * CFrame.Angles(0, 0, -side * 0.55), bone, SMOOTH)
		part(parent, "Tine", Vector3.new(0.1, 0.6, 0.1), at * CFrame.new(side * 0.5, 1.62, wall - 0.25) * CFrame.Angles(0, 0, side * 0.15), bone, SMOOTH)
	end
end

-- a framed alpine picture: a snowy peak over a meadow under the sky
LOOKS.picture = function(parent, at, s, roll)
	local wall = s.Z / 2
	part(parent, "PictureFrame", Vector3.new(s.X, s.Y, 0.12), at * CFrame.new(0, s.Y / 2, wall - 0.06), WOODWORK, Enum.Material.Wood)
	local foot = 0.18 -- (the frame's border)
	local w, h = s.X - 2 * foot, s.Y - 2 * foot
	part(parent, "Sky", Vector3.new(w, h, 0.03), at * CFrame.new(0, s.Y / 2, wall - 0.135), SKIES[roll(#SKIES)], SMOOTH)
	-- the peak: a square turned on its corner, its lower half behind the meadow
	local meadow = 0.55
	local peak = math.min(0.55, (h - meadow) * 0.75, w / 2 - 0.4)
	local px = ({ -0.35, 0, 0.35 })[roll(3)]
	part(parent, "Peak", Vector3.new(peak * math.sqrt(2), peak * math.sqrt(2), 0.03), at * CFrame.new(px, foot + meadow, wall - 0.16) * CFrame.Angles(0, 0, math.pi / 4), rgb(232, 236, 242), SMOOTH)
	part(parent, "Meadow", Vector3.new(w, meadow, 0.035), at * CFrame.new(0, foot + meadow / 2, wall - 0.18), rgb(96, 146, 76), SMOOTH)
end

-- the flat things: rag rugs (7.x alpine: a ground and a woven band across it), the round braided one, the runner,
-- mats, the oil stain
local function rug(parent: Instance, at: CFrame, s: Vector3, roll: (number) -> number, round: boolean)
	local a, b = RUGS[roll(#RUGS)], RUGS[roll(#RUGS)]
	if round then
		local d = math.min(s.X, s.Z)
		cylinder(part(parent, "Rug", Vector3.new(0.06, d, d), at * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.pi / 2), a, Enum.Material.Fabric))
		cylinder(part(parent, "RugField", Vector3.new(0.07, d - 1, d - 1), at * CFrame.new(0, 0.035, 0) * CFrame.Angles(0, 0, math.pi / 2), b, Enum.Material.Fabric))
		return
	end
	part(parent, "Rug", Vector3.new(s.X, 0.06, s.Z), at * CFrame.new(0, 0.03, 0), a, Enum.Material.Fabric)
	part(parent, "Stripe", Vector3.new(s.X, 0.07, math.min(1.6, s.Z * 0.22)), at * CFrame.new(0, 0.035, 0), b, Enum.Material.Fabric)
end
LOOKS.rug = function(parent, at, s, roll)
	rug(parent, at, s, roll, false)
end
LOOKS.runner = LOOKS.rug
LOOKS.round_rug = function(parent, at, s, roll)
	rug(parent, at, s, roll, true)
end
LOOKS.mat = function(parent, at, s, roll)
	part(parent, "Mat", Vector3.new(s.X, 0.06, s.Z), at * CFrame.new(0, 0.03, 0), RUGS[roll(#RUGS)], Enum.Material.Fabric)
end
LOOKS.stain = function(parent, at, s)
	local stain = cylinder(part(parent, "OilStain", Vector3.new(0.02, s.X, s.Z), at * CFrame.new(0, 0.01, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(40, 38, 36), SMOOTH))
	stain.Transparency = 0.35
end

-- ── 9.5 the countryside's spots ────────────────────────────────────────────────
-- (their plans: shared/Layouts/Countryside.luau; each fixture in its own frame as the others)

-- a cast iron wood stove on its legs, the fire door and its glow, the stovepipe up to the ceiling (s.Y)
LOOKS.wood_stove = function(parent, at, s)
	local iron = rgb(46, 44, 42)
	local front = -(s.Z - 0.8) / 2 + 0.1
	part(parent, "StoveLegs", Vector3.new(s.X - 0.4, 0.5, s.Z - 0.6), at * CFrame.new(0, 0.25, 0.1), rgb(36, 34, 32), Enum.Material.Metal, true)
	part(parent, "Stove", Vector3.new(s.X - 0.6, 2.4, s.Z - 0.8), at * CFrame.new(0, 1.7, 0.1), iron, Enum.Material.Metal, true)
	part(parent, "StoveTop", Vector3.new(s.X - 0.4, 0.2, s.Z - 0.6), at * CFrame.new(0, 3.0, 0.1), rgb(30, 30, 30), Enum.Material.Metal, true)
	part(parent, "FireDoor", Vector3.new(1.2, 1.0, 0.1), at * CFrame.new(0, 1.6, front - 0.06), rgb(30, 28, 26), Enum.Material.Metal)
	part(parent, "Glow", Vector3.new(0.8, 0.12, 0.05), at * CFrame.new(0, 1.35, front - 0.12), rgb(255, 130, 50), Enum.Material.Neon)
	local pipe = s.Y - 3.1
	cylinder(part(parent, "Pipe", Vector3.new(pipe, 0.6, 0.6), at * CFrame.new(0, 3.1 + pipe / 2, 0.6) * CFrame.Angles(0, 0, math.pi / 2), iron, Enum.Material.Metal))
	part(parent, "Hearthstone", Vector3.new(s.X + 0.4, 0.1, 1.2), at * CFrame.new(0, 0.05, -s.Z / 2 - 0.4), rgb(84, 84, 88), Enum.Material.Slate)
end

-- a fishing net hung on the wall (its bottom `at`), its floats along the top
LOOKS.net = function(parent, at, s)
	local wall = s.Z / 2
	local net = part(parent, "Net", Vector3.new(s.X, s.Y, 0.05), at * CFrame.new(0, s.Y / 2, wall - 0.1), rgb(70, 92, 72), Enum.Material.Fabric)
	net.Transparency = 0.35
	for n, x in { -1.4, -0.45, 0.5, 1.45 } do
		local float = part(parent, "Float", Vector3.new(0.4, 0.4, 0.4), at * CFrame.new(x * s.X / 4, s.Y - 0.25, wall - 0.25), if n % 2 == 0 then rgb(240, 236, 226) else rgb(232, 120, 40), SMOOTH)
		float.Shape = Enum.PartType.Ball
	end
end

-- a lifebuoy on the wall: its ring in eight pieces, red and white
LOOKS.lifebuoy = function(parent, at, s)
	local wall = s.Z / 2
	local r = s.X / 2 - 0.25
	for n = 0, 7 do
		local a = n * math.pi / 4
		part(parent, "Lifebuoy", Vector3.new(0.75, 0.42, 0.3), at * CFrame.new(math.cos(a) * r, s.Y / 2 + math.sin(a) * r, wall - 0.2) * CFrame.Angles(0, 0, a + math.pi / 2),
			if n % 2 == 0 then rgb(214, 50, 40) else rgb(240, 236, 226), SMOOTH)
	end
end

-- the millstones: the stone floor (a wooden platform, its step), the vat round the stones and its lid, the horse and
-- the hopper over them with grain in it, the shoe feeding the stones, the meal spout and its bin, the stone crane
LOOKS.millstones = function(parent, at, s)
	local wood = rgb(120, 86, 56)
	local up = 1.2
	part(parent, "StoneFloor", Vector3.new(s.X, up, s.Z), at * CFrame.new(0, up / 2, 0), wood, Enum.Material.WoodPlanks, true)
	part(parent, "Step", Vector3.new(2.4, 0.6, 0.8), at * CFrame.new(0, 0.3, -s.Z / 2 + 0.4), wood, Enum.Material.WoodPlanks, true)
	cylinder(part(parent, "Vat", Vector3.new(1.8, 6.2, 6.2), at * CFrame.new(0, up + 0.9, 0.4) * CFrame.Angles(0, 0, math.pi / 2), rgb(150, 110, 70), Enum.Material.Wood, true))
	cylinder(part(parent, "VatLid", Vector3.new(0.2, 6.4, 6.4), at * CFrame.new(0, up + 1.9, 0.4) * CFrame.Angles(0, 0, math.pi / 2), rgb(130, 94, 60), Enum.Material.Wood, true))
	for _, x in { -1.5, 1.5 } do
		part(parent, "Horse", Vector3.new(0.35, 2.8, 0.35), at * CFrame.new(x, up + 3.4, 0.4), rgb(100, 70, 46), Enum.Material.Wood, true)
	end
	part(parent, "Hopper", Vector3.new(2.8, 1.8, 2.8), at * CFrame.new(0, up + 5.7, 0.4), wood, Enum.Material.WoodPlanks, true)
	part(parent, "Grain", Vector3.new(2.5, 0.1, 2.5), at * CFrame.new(0, up + 6.65, 0.4), rgb(214, 180, 100), SMOOTH)
	part(parent, "Shoe", Vector3.new(0.5, 0.3, 1.6), at * CFrame.new(0, up + 4.4, -0.2) * CFrame.Angles(0.3, 0, 0), wood, Enum.Material.Wood)
	part(parent, "Spout", Vector3.new(0.5, 0.5, 1.0), at * CFrame.new(0, up + 0.8, -2.9), rgb(110, 78, 50), Enum.Material.Wood)
	part(parent, "MealBin", Vector3.new(2.0, 1.0, 1.0), at * CFrame.new(1.4, up + 0.5, -3.3), wood, Enum.Material.WoodPlanks, true)
	part(parent, "Flour", Vector3.new(1.8, 0.08, 0.8), at * CFrame.new(1.4, up + 1.02, -3.3), rgb(246, 244, 236), SMOOTH)
	part(parent, "CranePost", Vector3.new(0.45, s.Y - up, 0.45), at * CFrame.new(s.X / 2 - 0.4, up + (s.Y - up) / 2, s.Z / 2 - 0.4), rgb(90, 64, 42), Enum.Material.Wood, true)
	part(parent, "CraneArm", Vector3.new(3.4, 0.4, 0.4), at * CFrame.new(s.X / 2 - 2.0, s.Y - 0.6, s.Z / 2 - 0.4), rgb(90, 64, 42), Enum.Material.Wood)
end

-- the pit wheel on the water wheel's shaft through the wall: the wheel and its spokes in its pit (fenced, so nobody
-- falls in), the shaft, the stone bearing at the wall
LOOKS.pit_wheel = function(parent, at, s)
	local wood = rgb(110, 78, 50)
	local back = s.Z / 2
	part(parent, "PitFence", Vector3.new(s.X, 3.2, 0.3), at * CFrame.new(0, 1.6, -s.Z / 2 + 0.15), wood, Enum.Material.WoodPlanks, true)
	for _, x in { -1, 1 } do
		part(parent, "PitFence", Vector3.new(0.3, 3.2, s.Z - 0.3), at * CFrame.new(x * (s.X / 2 - 0.15), 1.6, 0.15), wood, Enum.Material.WoodPlanks, true)
	end
	part(parent, "Pit", Vector3.new(s.X - 0.6, 0.06, s.Z - 0.6), at * CFrame.new(0, 0.03, 0.15), rgb(40, 34, 28), SMOOTH)
	local hub = s.Y - 4.9
	cylinder(part(parent, "PitWheel", Vector3.new(0.7, 7.6, 7.6), at * CFrame.new(0, hub, 0.2) * CFrame.Angles(0, math.pi / 2, 0), rgb(124, 88, 56), Enum.Material.Wood, true))
	for n = 0, 1 do
		part(parent, "Spoke", Vector3.new(7.2, 0.5, 0.2), at * CFrame.new(0, hub, -0.2) * CFrame.Angles(0, 0, math.pi / 4 + n * math.pi / 2), rgb(96, 68, 44), Enum.Material.Wood)
	end
	cylinder(part(parent, "Shaft", Vector3.new(s.Z, 1.0, 1.0), at * CFrame.new(0, hub, 0) * CFrame.Angles(0, math.pi / 2, 0), rgb(90, 64, 42), Enum.Material.Wood))
	part(parent, "Bearing", Vector3.new(1.6, hub - 0.5, 1.0), at * CFrame.new(0, (hub - 0.5) / 2, back - 0.5), rgb(130, 126, 118), Enum.Material.Slate, true)
end

-- the sack hoist: its trap in the ceiling (at the top), the chain down from it, the hook and a sack on it
LOOKS.sack_hoist = function(parent, at, s)
	part(parent, "Trap", Vector3.new(s.X, 0.1, s.Z), at * CFrame.new(0, s.Y - 0.05, 0), rgb(40, 32, 26), Enum.Material.WoodPlanks)
	part(parent, "Chain", Vector3.new(0.12, s.Y - 1.8, 0.12), at * CFrame.new(0, 1.8 + (s.Y - 1.8) / 2, 0), rgb(60, 60, 62), Enum.Material.Metal)
	part(parent, "Hook", Vector3.new(0.4, 0.4, 0.12), at * CFrame.new(0, 1.7, 0), rgb(60, 60, 62), Enum.Material.Metal)
	part(parent, "Sack", Vector3.new(1.2, 1.5, 0.9), at * CFrame.new(0, 0.75, 0), rgb(196, 168, 116), Enum.Material.Fabric)
end

-- a lantern hung from the ceiling (`at` its bottom, size.Y up to the ceiling): the chain, the cap, its warm glass (the
-- room's lamps light it: no light of its own)
LOOKS.hanging_lantern = function(parent, at, s)
	local metal = rgb(44, 42, 40)
	part(parent, "Chain", Vector3.new(0.08, s.Y - 1.2, 0.08), at * CFrame.new(0, 1.2 + (s.Y - 1.2) / 2, 0), metal, Enum.Material.Metal)
	part(parent, "LanternCap", Vector3.new(s.X, 0.25, s.Z), at * CFrame.new(0, 1.075, 0), metal, Enum.Material.Metal)
	local glow = part(parent, "Lantern", Vector3.new(s.X - 0.3, 0.95, s.Z - 0.3), at * CFrame.new(0, 0.475, 0), LAMP, Enum.Material.Neon)
	glow.CastShadow = false
end

-- Each spot's own inside (a plan of its kind): the walls' colours and material and the wainscot's (by room kind, `any`
-- the rest; a kind with no wainscot gets neither it nor a baseboard: the cabin's boards), the floor under it all (`any`)
-- and a room kind's own over it, the ceiling's boards and beams, the room kinds whose windows have lace.
type SpotStyle = {
	walls: { [string]: { Color3 } },
	material: { [string]: Enum.Material },
	panels: { [string]: { Color3 } },
	panelHeight: number,
	panelMaterial: Enum.Material,
	floors: { [string]: Floor },
	ceiling: Color3,
	beam: Color3,
	lace: { [string]: boolean },
}
local SPOTS: { [string]: SpotStyle } = {
	cabin = {
		walls = { any = { rgb(96, 70, 50), rgb(84, 62, 46), rgb(106, 78, 56) } },
		material = { any = Enum.Material.WoodPlanks },
		panels = {},
		panelHeight = 3.8,
		panelMaterial = Enum.Material.WoodPlanks,
		floors = { any = { color = rgb(122, 92, 64), material = Enum.Material.WoodPlanks }, store = { color = rgb(112, 108, 100), material = Enum.Material.Concrete } },
		ceiling = rgb(112, 84, 60),
		beam = rgb(66, 48, 36),
		lace = {},
	},
	lodge = {
		walls = { any = { rgb(222, 208, 182), rgb(214, 200, 176) } },
		material = { any = Enum.Material.Plaster },
		panels = { any = { rgb(120, 82, 52), rgb(134, 94, 60) }, kitchen = { rgb(166, 118, 74), rgb(150, 104, 64) } },
		panelHeight = 5.2,
		panelMaterial = Enum.Material.Wood,
		floors = { any = { color = rgb(132, 94, 62), material = Enum.Material.WoodPlanks } },
		ceiling = rgb(156, 114, 74),
		beam = rgb(74, 50, 34),
		lace = { bedroom = true },
	},
	mill = {
		walls = { any = { rgb(150, 144, 132), rgb(140, 136, 128) }, living = { rgb(216, 210, 196), rgb(212, 206, 194) } },
		material = { any = Enum.Material.Cobblestone, living = Enum.Material.Plaster },
		panels = { living = { rgb(110, 80, 56), rgb(96, 70, 50) } },
		panelHeight = 3.8,
		panelMaterial = Enum.Material.WoodPlanks,
		floors = { any = { color = rgb(152, 124, 90), material = Enum.Material.WoodPlanks } },
		ceiling = rgb(132, 100, 70),
		beam = rgb(82, 58, 40),
		lace = { living = true },
	},
	cottage = {
		walls = { any = { rgb(220, 214, 202), rgb(216, 212, 204) }, bedroom = { rgb(208, 214, 216), rgb(218, 208, 200) } },
		material = { any = Enum.Material.Plaster },
		panels = { kitchen = { rgb(96, 128, 158), rgb(116, 146, 116) }, bedroom = { rgb(150, 120, 160), rgb(120, 150, 170) } },
		panelHeight = 3,
		panelMaterial = Enum.Material.SmoothPlastic,
		floors = {
			any = { color = rgb(170, 128, 86), material = Enum.Material.WoodPlanks },
			kitchen = { color = rgb(170, 98, 70), material = Enum.Material.CeramicTiles },
			store = { color = rgb(150, 140, 126), material = Enum.Material.Brick },
		},
		ceiling = rgb(206, 196, 176),
		beam = rgb(112, 80, 54),
		lace = { kitchen = true, bedroom = true },
	},
}

-- ── The stoves and the larder (the countryside's spots': shared/Layouts/Countryside.luau) ─────────────────────────────
local STOVE_TILES = { rgb(70, 120, 90), rgb(206, 196, 170), rgb(160, 76, 56), rgb(84, 112, 150) } -- the stoves' tiles

-- a kitchen range clad in tiles, its iron hob, the oven door, a brass rail, the flue up to the ceiling
LOOKS.tiled_stove = function(parent, at, s, roll)
	part(parent, "Range", Vector3.new(s.X, s.Y - 0.2, s.Z), at * CFrame.new(0, (s.Y - 0.2) / 2, 0), STOVE_TILES[roll(#STOVE_TILES)], Enum.Material.CeramicTiles, true)
	part(parent, "Hob", Vector3.new(s.X + 0.1, 0.2, s.Z + 0.1), at * CFrame.new(0, s.Y - 0.1, 0), rgb(40, 40, 44), Enum.Material.Metal, true)
	part(parent, "OvenDoor", Vector3.new(1.3, 1.1, 0.08), at * CFrame.new(-0.6, 1.3, -s.Z / 2 - 0.04), rgb(30, 30, 34), Enum.Material.Metal)
	part(parent, "Rail", Vector3.new(s.X, 0.1, 0.1), at * CFrame.new(0, s.Y - 0.45, -s.Z / 2 - 0.15), rgb(204, 164, 72), Enum.Material.Metal)
	local flue = T.Ceiling - s.Y
	cylinder(part(parent, "Flue", Vector3.new(flue, 0.6, 0.6), at * CFrame.new(0.9, s.Y + flue / 2, s.Z / 2 - 0.5) * CFrame.Angles(0, 0, math.pi / 2), rgb(50, 50, 54), Enum.Material.Metal))
end

-- a larder: wooden shelves, rows of preserving jars, a ham hung from the top
LOOKS.larder = function(parent, at, s)
	local wood = rgb(160, 118, 76)
	for _, x in { -1, 1 } do
		part(parent, "Upright", Vector3.new(0.25, s.Y, s.Z), at * CFrame.new(x * (s.X / 2 - 0.125), s.Y / 2, 0), wood, Enum.Material.Wood, true)
	end
	for n, y in { 0.5, 2.6, 4.7 } do
		part(parent, "Shelf", Vector3.new(s.X - 0.5, 0.15, s.Z), at * CFrame.new(0, y, 0), wood, Enum.Material.WoodPlanks, true)
		if n <= 2 then
			local jars = part(parent, "Jars", Vector3.new(s.X - 1.2, 0.8, 0.6), at * CFrame.new(0, y + 0.475, 0.2), if n == 1 then rgb(200, 90, 50) else rgb(220, 170, 60), Enum.Material.Glass)
			jars.Transparency = 0.15
		end
	end
	part(parent, "Ham", Vector3.new(0.7, 1.1, 0.6), at * CFrame.new(s.X / 4, 6.0, -0.1), rgb(150, 70, 56), Enum.Material.SmoothPlastic)
end

-- 8.3 walk-in doors: a door's leaf (`leaf`: its part `body`, or the model that part is the PrimaryPart of; no
-- collision), shut in its doorway, hinged at its end `hinge` (±1 along its width), opening out onto the porch (-Z) a
-- right angle, flat along it: a door leaf of shared/DoorSwing.luau (DoorLeaf, DoorSwing -1, DoorAngle 90:
-- server/Moving.luau says when, every client swings it as you walk up to it); with Config.Moving.Doors.Swing off it
-- stands open so (10.6: the city's way, Config.Sandbox.On false, is gone). Danny's paths go through it whatever its swing does (a PathfindingModifier PassThrough on its
-- part: a door, not a wall).
local function swingOut(leaf: PVInstance, body: BasePart, hinge: number)
	local through = Instance.new("PathfindingModifier")
	through.PassThrough = true
	through.Parent = body
	if Config.Moving.Doors.Swing then
		leaf:SetAttribute("DoorLeaf", hinge)
		leaf:SetAttribute("DoorSwing", -1) -- (out, onto the porch: -Z)
		leaf:SetAttribute("DoorAngle", 90) -- (flat along the porch)
		return
	end
	local swing = DoorSwing.pieces(body.Size.X, body.Size.Z, hinge, -1, 90)[1]
	local open = body.CFrame * CFrame.new(swing.hx, 0, swing.hz) * CFrame.Angles(0, swing.yaw, 0) * CFrame.new(-swing.hx, 0, -swing.hz)
	if leaf == body then
		body.CFrame = open
	else
		leaf:PivotTo(open)
	end
end

-- The daylight through a doorway to the outside: the porch's outer wall (Neon, LIT.Daylight) and a SurfaceLight on it
-- shining into the house (+Z, its Back: LIT.Porch), dark at night (7.0 review).
local function porchLight(glow: BasePart)
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Back -- (+Z: into the house)
	light.Brightness = LIT.Porch.Brightness
	light.Range = LIT.Porch.Range
	light.Angle = 70
	light.Color = color(LIT.Porch.Color)
	light.Parent = glow
	daylight(glow, NIGHT.porch, light) -- 7.0 review: dark at night
end

-- 8.3 the big house: a way out that is not the front door (the back door, in the corridor's east wall: HouseLayout's
-- kind "big") gets a porch as the front door's (its floor, larch sides and roof, the outer wall of daylight that stops a
-- walk out, porchLight's), the door's lintel, its leaf and the EXIT sign over it inside. The frame: the doorway's middle
-- on its wall's centre line, -Z out of the house.
local function sidePorch(shell: Instance, decor: Instance, plan: HouseLayout.Plan, origin: CFrame, door: HouseLayout.Door)
	local half = plan.wall / 2
	local mid = (plan.min + plan.max) / 2
	local out = if door.axis == "Z" then Vector3.new(if door.at.X > mid.X then 1 else -1, 0, 0) else Vector3.new(0, 0, if door.at.Z > mid.Z then 1 else -1)
	local frame = origin * CFrame.lookAt(door.at, door.at + out)
	local w, porch, h = door.width / 2 + 1, 6, plan.doorHeight
	local larch = rgb(156, 112, 72)
	part(shell, "BackPorch", Vector3.new(2 * w, 0.2, porch), frame * CFrame.new(0, -0.1, -(half + porch / 2)), rgb(150, 146, 140), Enum.Material.WoodPlanks, true)
	for _, s in { -1, 1 } do
		part(shell, "BackPorchWall", Vector3.new(0.5, plan.ceiling, porch), frame * CFrame.new(s * (w + 0.25), plan.ceiling / 2, -(half + porch / 2)), larch, Enum.Material.WoodPlanks, true)
	end
	part(shell, "BackPorchRoof", Vector3.new(2 * w + 1, 0.5, porch), frame * CFrame.new(0, h + 1.25, -(half + porch / 2)), larch, Enum.Material.WoodPlanks, true)
	part(decor, "Lintel", Vector3.new(door.width + 0.8, 0.4, plan.wall + 0.3), frame * CFrame.new(0, h + 0.2, 0), rgb(110, 76, 50), Enum.Material.Wood)
	-- its leaf, shut in the doorway, hinged at the frame's +X jamb (the east wall's door: its south side), opening out
	-- onto the porch (8.3 walk-in doors: swingOut)
	local leaf = part(decor, "BackLeaf", Vector3.new(door.width - 0.06, h - 0.15, 0.24), frame * CFrame.new(0, (h - 0.15) / 2, 0), rgb(96, 64, 40), Enum.Material.Wood)
	swingOut(leaf, leaf, 1)
	local glow = part(shell, "BackDaylight", Vector3.new(2 * w, h + 1.5, 0.4), frame * CFrame.new(0, (h + 1.5) / 2, -(half + porch + 0.2)), color(LIT.Daylight), Enum.Material.Neon, true)
	glow.CastShadow = false
	porchLight(glow)
	local exit = part(decor, "ExitSign", Vector3.new(2.6, 0.9, 0.3), frame * CFrame.new(0, h + 1.05, half + 0.15), rgb(250, 250, 248), SMOOTH)
	sign(exit, "EXIT", Enum.NormalId.Back, rgb(255, 255, 255), rgb(30, 160, 80))
end

-- The front door's two leaves (7.x alpine: painted, a flower on each) in the doorway, its middle at `x`, the wall's
-- outer face at `z` (the house's frame: `at`), each `leaf` wide and `tall` high, on the porch's side of the wall. 8.3
-- walk-in doors (Config.Moving.Doors Swing; shared/DoorSwing.luau's attributes): in the sandbox each a model
-- "FrontDoorLeaf" (its part "DoorLeaf", its flower) shut across the doorway, hinged at the doorway's side, swinging out
-- onto the porch as you walk up to it (server/Moving.luau says when, client/WalkDoors.luau swings it, its flower
-- turned to the porch's middle once open); elsewhere (the city's client swings none) it stands open as it always did
-- (swingOut).
local function frontLeaves(decor: Instance, at: (number, number, number) -> CFrame, x: number, z: number, leaf: number, tall: number, paint: Color3, bloom: Color3)
	for _, s in { -1, 1 } do
		local leafModel = Instance.new("Model")
		leafModel.Name = "FrontDoorLeaf"
		local lx, lz = x + s * leaf / 2, z - 0.27
		local p = part(leafModel, "DoorLeaf", Vector3.new(leaf, tall, 0.24), at(lx, tall / 2, lz), paint, Enum.Material.Wood)
		local face = lz + 0.14 -- (its side to the house)
		cylinder(part(leafModel, "Bloom", Vector3.new(0.04, 1.1, 1.1), at(lx, tall * 0.68, face) * CFrame.Angles(0, math.pi / 2, 0), bloom, SMOOTH))
		part(leafModel, "Leaves", Vector3.new(0.9, 0.9, 0.04), at(lx, tall * 0.5, face) * CFrame.Angles(0, 0, math.pi / 4), LEAF, SMOOTH)
		leafModel.PrimaryPart = p
		swingOut(leafModel, p, s) -- (hinged at the doorway's side: its end s)
		leafModel.Parent = decor
	end
end

-- ── The interior ─────────────────────────────────────────────────────────────

function HouseInterior.build(plan: HouseLayout.Plan, origin: CFrame): (Model, { [number]: Model })
	local roll = dice(plan.seed)
	local model = Instance.new("Model")
	model.Name = "HouseInterior"
	model:SetAttribute("Seed", plan.seed)
	model:SetAttribute("Kind", plan.kind)
	-- 10.x the map: the floor plan in one short string (shared/SandboxMapRules.luau encode; the clients' big map and
	-- minimap draw it), written once with the interior. (A recorder's frame has no LookVector: no turn.)
	local facing = (origin :: any).LookVector
	local yaw = if facing then math.deg(math.atan2(-facing.X, -facing.Z)) else 0
	model:SetAttribute("MapPlan", MapRules.encode(plan, { x = origin.Position.X, y = origin.Position.Y, z = origin.Position.Z, yaw = yaw }))
	local shell = folder(model, "Shell")
	local decor = folder(model, "Decor")
	local items = folder(model, "Items")
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	cabinetColor = CABINETS[roll(#CABINETS)]
	local plaster: { [string]: Color3 } = {}
	local panelling: { [string]: Color3 } = {}
	for _, kind in KINDS do
		plaster[kind] = PLASTER[kind][roll(#PLASTER[kind])]
		local panels = PANELLING[kind]
		if panels then
			panelling[kind] = panels[roll(#panels)]
		end
	end
	local planks = PLANKS[roll(#PLANKS)]
	-- 9.5 the countryside's spots: their own walls, wainscot and floor (SPOTS; the dice after a house's)
	local style = SPOTS[plan.kind]
	local spotWall: { [string]: Color3 } = {}
	local spotPanel: { [string]: Color3 } = {}
	if style then
		local styled: { [string]: boolean } = {}
		for _, room in plan.rooms do
			local k = room.kind
			if not styled[k] then
				styled[k] = true
				local walls = style.walls[k] or style.walls.any
				spotWall[k] = walls[roll(#walls)]
				local panels = style.panels[k] or style.panels.any
				if panels then
					spotPanel[k] = panels[roll(#panels)]
				end
			end
		end
		planks = style.floors.any
	end
	local kindOf: { [string]: string } = {}
	for _, room in plan.rooms do
		kindOf[room.id] = room.kind
	end
	local half = plan.wall / 2
	local ceiling = plan.ceiling

	-- the safety ground; the floor: the planks under every room in one part, the bathroom's tiles and the garage's
	-- concrete laid over them a hair higher (each to its walls' middles); the pine ceiling
	local mid = (plan.min + plan.max) / 2
	local g = T.Ground
	local ground = part(shell, "Ground", Vector3.new(plan.size.X + 2 * g.Margin, g.Depth, plan.size.Z + 2 * g.Margin), at(mid.X, -0.2 - g.Depth / 2, mid.Z), rgb(96, 92, 86), Enum.Material.Concrete, true)
	ground.CastShadow = false
	local lo, hi = Vector3.new(math.huge, 0, math.huge), Vector3.new(-math.huge, 0, -math.huge)
	for _, room in plan.rooms do
		local floor = (if style then style.floors[room.kind] else nil) or FLOOR_OF[room.kind]
		local w, d = room.max.X - room.min.X + plan.wall, room.max.Z - room.min.Z + plan.wall
		local cx, cz = (room.min.X + room.max.X) / 2, (room.min.Z + room.max.Z) / 2
		if floor then
			part(shell, "Floor", Vector3.new(w, 0.06, d), at(cx, -0.01, cz), floor.color, floor.material, true)
		else
			lo = Vector3.new(math.min(lo.X, cx - w / 2), 0, math.min(lo.Z, cz - d / 2))
			hi = Vector3.new(math.max(hi.X, cx + w / 2), 0, math.max(hi.Z, cz + d / 2))
		end
	end
	if hi.X > lo.X then
		part(shell, "Floor", Vector3.new(hi.X - lo.X, 0.2, hi.Z - lo.Z), at((lo.X + hi.X) / 2, -0.1, (lo.Z + hi.Z) / 2), planks.color, planks.material, true)
	end
	part(shell, "Ceiling", Vector3.new(plan.size.X, 1, plan.size.Z), at(mid.X, ceiling + 0.5, mid.Z), if style then style.ceiling else CEILING, Enum.Material.WoodPlanks, true)

	-- the beams under the ceiling: BeamRows across every row of rooms (rooms side by side, the same depth), a beam
	-- through the walls of the rooms next to each other, none over the bathroom, the garage or a narrow row (the
	-- corridor: its lamps hang in its middle)
	do
		local beam = T.Alpine.Beam
		local rows: { { Vector3 } } = {} -- { min, max } runs of rooms
		local sorted = table.clone(plan.rooms)
		table.sort(sorted, function(a: HouseLayout.Room, b: HouseLayout.Room): boolean
			if math.abs(a.min.Z - b.min.Z) > 1e-6 then
				return a.min.Z < b.min.Z
			end
			return a.min.X < b.min.X
		end)
		for _, room in sorted do
			if room.kind == "bath" or room.kind == "garage" or room.max.Z - room.min.Z < 10 then
				continue
			end
			local last = rows[#rows]
			if last and math.abs(last[1].Z - room.min.Z) < 1e-6 and math.abs(last[2].Z - room.max.Z) < 1e-6 and room.min.X - last[2].X <= plan.wall + 1e-3 then
				last[2] = room.max
			else
				table.insert(rows, { room.min, room.max })
			end
		end
		for _, run in rows do
			local x0, x1 = run[1].X - half, run[2].X + half
			for k = 1, T.Alpine.BeamRows do
				local z = run[1].Z + (run[2].Z - run[1].Z) * k / (T.Alpine.BeamRows + 1)
				part(decor, "Beam", Vector3.new(x1 - x0, beam, beam), at((x0 + x1) / 2, ceiling - beam / 2, z), if style then style.beam else BEAM, Enum.Material.Wood)
			end
		end
	end

	-- the walls: a slab per room side in its plaster, the wood panelling along its foot (the bathroom tiled to the
	-- ceiling, the garage bare concrete)
	for _, face in plan.faces do
		local kind = kindOf[face.room] or "hall"
		local size = face.max - face.min
		local centre = (face.min + face.max) / 2
		local material = if style then style.material[kind] or style.material.any
			elseif kind == "garage" then Enum.Material.Concrete
			elseif kind == "bath" then Enum.Material.CeramicTiles
			else Enum.Material.Plaster
		part(shell, if face.header then "Header" else "Wall", size, at(centre.X, centre.Y, centre.Z), (if style then spotWall[kind] else plaster[kind]) or TRIM, material, true)
		if face.header then
			continue
		end
		local n = face.normal
		-- the face you see: the slab's side toward the room
		local sx = if n.X > 0.5 then face.max.X elseif n.X < -0.5 then face.min.X else centre.X
		local sz = if n.Z > 0.5 then face.max.Z elseif n.Z < -0.5 then face.min.Z else centre.Z
		local along = if math.abs(n.X) > 0.5 then size.Z else size.X
		local function strip(name: string, height: number, depth: number, c: Color3, material2: Enum.Material)
			local s = if math.abs(n.X) > 0.5 then Vector3.new(depth, height, along) else Vector3.new(along, height, depth)
			part(shell, name, s, at(sx + n.X * depth / 2, height / 2, sz + n.Z * depth / 2), c, material2)
		end
		local panel = if style then spotPanel[kind] else panelling[kind]
		if along <= 1.6 or kind == "garage" or kind == "bath" or (style and not panel) then
			continue -- (nothing on a stub beside a doorway; the bathroom's walls are tiles all the way up; 9.5 the cabin's boards)
		elseif style and panel then
			strip("Wainscot", style.panelHeight, 0.12, panel, style.panelMaterial)
		elseif panel then
			strip("Wainscot", T.Alpine.Wainscot, 0.12, panel, Enum.Material.WoodPlanks)
		else
			strip("Baseboard", 0.5, 0.15, TRIM, SMOOTH)
		end
	end

	-- the doorways' frames (not the hall's wide arch); the front door's the porch with daylight beyond it and the EXIT
	-- sign over it
	for _, door in plan.doors do
		if door.width >= T.HallOpening then
			continue
		end
		local w = door.width / 2
		local frameColor = if door.front then rgb(110, 76, 50) else WOODWORK
		local depth = plan.wall + 0.3
		local function piece(name: string, dx: number, y: number, sAlong: number, sY: number)
			local size = if door.axis == "X" then Vector3.new(sAlong, sY, depth) else Vector3.new(depth, sY, sAlong)
			local x = if door.axis == "X" then door.at.X + dx else door.at.X
			local z = if door.axis == "X" then door.at.Z else door.at.Z + dx
			part(decor, name, size, at(x, y, z), frameColor, Enum.Material.Wood)
		end
		for _, s in { -1, 1 } do
			piece("Jamb", s * (w + 0.18), plan.doorHeight / 2, 0.4, plan.doorHeight) -- (a hair into the opening: no face shared with the wall's end)
		end
		if door.front then
			piece("Lintel", 0, plan.doorHeight + 0.2, door.width + 0.8, 0.4)
		end
	end
	do
		local front = plan.doors[1]
		local w = front.width / 2 + 1
		local x, z = front.at.X, front.at.Z - half
		local porch = 6
		local larch = rgb(156, 112, 72) -- (7.x alpine: the chalet's weathered larch boards)
		part(shell, "Porch", Vector3.new(2 * w, 0.2, porch), at(x, -0.1, z - porch / 2), rgb(150, 146, 140), Enum.Material.Concrete, true)
		for _, s in { -1, 1 } do
			part(shell, "PorchWall", Vector3.new(0.5, ceiling, porch), at(x + s * (w + 0.25), ceiling / 2, z - porch / 2), larch, Enum.Material.WoodPlanks, true)
		end
		part(shell, "PorchRoof", Vector3.new(2 * w + 1, 0.5, porch), at(x, plan.doorHeight + 1.25, z - porch / 2), larch, Enum.Material.WoodPlanks, true)
		-- 7.x alpine: the front door's two leaves, a painted flower on each: its bloom over a pair of green leaves (8.3:
		-- shut across the doorway, swinging out onto the porch as you walk up to it: frontLeaves)
		local paint = DOORS[roll(#DOORS)]
		local bloom = BLOOMS[roll(#BLOOMS)]
		frontLeaves(decor, at, x, z, front.width / 2, plan.doorHeight - 0.15, paint, bloom)
		local glow = part(shell, "Daylight", Vector3.new(2 * w, plan.doorHeight + 1.5, 0.4), at(x, (plan.doorHeight + 1.5) / 2, z - porch - 0.2), color(LIT.Daylight), Enum.Material.Neon, true)
		glow.CastShadow = false
		porchLight(glow) -- (its light into the house: Config.SandboxLight.House.Porch, dark at night)
		local mat = part(decor, "WelcomeMat", Vector3.new(4, 0.06, 2.2), at(x, 0.03, z - 1.6), rgb(150, 110, 70), Enum.Material.Fabric)
		sign(mat, "WELCOME", Enum.NormalId.Top, rgb(60, 40, 24))
		local exit = part(decor, "ExitSign", Vector3.new(2.6, 0.9, 0.3), at(x, plan.doorHeight + 1.05, front.at.Z + half + 0.15), rgb(250, 250, 248), SMOOTH)
		sign(exit, "EXIT", Enum.NormalId.Back, rgb(255, 255, 255), rgb(30, 160, 80))
	end
	-- 8.3 the big house: its other way out (the back door) gets its own porch of daylight
	for index, door in plan.doors do
		if index > 1 and door.rooms[2] == "outside" then
			sidePorch(shell, decor, plan, origin, door)
		end
	end

	-- the windows: a wooden frame, the glowing pane and a deep sill (a small one no sill); a lace curtain over the lower
	-- half of every big one but the bathroom's (7.x alpine)
	for _, w in plan.windows do
		local kind = kindOf[w.room] or "hall"
		local frame = origin * CFrame.lookAt(w.at, w.at + w.normal) -- -Z into the room
		local small = w.width <= 3
		part(decor, "WindowFrame", Vector3.new(w.width + 0.5, w.height + 0.5, 0.16), frame * CFrame.new(0, 0, -0.08), WOODWORK, Enum.Material.Wood)
		local pane = part(decor, "Window", Vector3.new(w.width, w.height, 0.06), frame * CFrame.new(0, 0, -0.19), if kind == "bath" then color(LIT.BathWindow) else DAYLIGHT, Enum.Material.Neon)
		pane:SetAttribute("InteriorWindow", true)
		daylight(pane, if kind == "bath" then NIGHT.bath else NIGHT.pane) -- 7.0 review: a night sky at night
		if not small then
			part(decor, "Sill", Vector3.new(w.width + 1, 0.2, 0.6), frame * CFrame.new(0, -w.height / 2 - 0.1, -0.3), WOODWORK, Enum.Material.Wood)
		end
		if not small and kind ~= "bath" and kind ~= "garage" and (style == nil or style.lace[kind] == true) then
			local lace = part(decor, "Lace", Vector3.new(w.width + 0.1, w.height * 0.55, 0.05), frame * CFrame.new(0, -w.height * 0.225, -0.3), LACE, Enum.Material.Fabric)
			lace.Transparency = 0.3
		end
	end

	-- the ceiling lights: one in the middle of every room, two in a long one, a warm glow (7.x alpine); a tube in the
	-- garage
	for _, room in plan.rooms do
		-- (8.5.2: a lamp over each cell of the room's floor, the cells at most Lamp.Long on a side: one in a room, two
		-- along a long one, a row down a long corridor, a grid in a big room; shared/SandboxLightRules.luau lamps)
		local spots = LightRules.lamps(room.min.X, room.max.X, room.min.Z, room.max.Z)
		for _, s in spots do
			local lamp
			if room.kind == "garage" then
				lamp = part(decor, "Tube", Vector3.new(4, 0.3, 0.6), at(s[1], ceiling - 0.15, s[2]), color(LIT.Tube), Enum.Material.Neon)
			else
				lamp = cylinder(part(decor, "Lamp", Vector3.new(0.3, 2.6, 2.6), at(s[1], ceiling - 0.15, s[2]) * CFrame.Angles(0, 0, math.pi / 2), LAMP, Enum.Material.Neon))
			end
			lamp.CastShadow = false
			local light = Instance.new("PointLight")
			light.Brightness = LIT.Lamp.Brightness
			light.Range = LIT.Lamp.Range
			light.Color = if room.kind == "garage" then rgb(226, 236, 255) else color(LIT.Lamp.Color)
			light.Shadows = false
			light.Parent = lamp
		end
	end

	-- the fixtures; 8.9.1: one of the owner's Blender model's kinds in its own Model, dressed by server/FixtureMesh.luau
	-- once the model is imported
	for _, f in plan.fixtures do
		local look = LOOKS[f.kind]
		if look and FixtureMesh.Kinds[f.kind] then
			local fixture = Instance.new("Model")
			fixture.Name = "Fixture_" .. f.kind
			fixture:SetAttribute("Fixture", f.kind)
			look(fixture, origin * f.at, f.size, roll)
			fixture.Parent = decor
			FixtureMesh.dress(fixture, f.kind, origin * f.at, f.size)
		elseif look then
			look(decor, origin * f.at, f.size, roll)
		end
	end

	-- the pieces, anchored at their spots
	local pieces: { [number]: Model } = {}
	for _, spot in plan.spots do
		local piece = FurnitureLooks.build(spot.item, spot.variant)
		FurnitureMesh.dress(piece, spot.item, spot.variant) -- (the owner's Blender models, once imported)
		piece:PivotTo(origin * spot.at)
		local root = piece.PrimaryPart
		if root then
			root.Anchored = true
		end
		piece:SetAttribute("Spot", spot.id)
		piece:SetAttribute("Star", spot.star)
		piece.Parent = items
		pieces[spot.id] = piece
	end
	model.WorldPivot = origin
	return model, pieces
end

-- The origin of interior number `index`: far off the map (past SandboxMap.Bounds), a slot apart, at the same height.
function HouseInterior.slot(index: number): CFrame
	local o = T.Slot.Origin
	return CFrame.new(o[1] + index * T.Slot.Spacing, o[2], o[3])
end

function HouseInterior.destroy(model: Model)
	model:Destroy()
end

return HouseInterior
