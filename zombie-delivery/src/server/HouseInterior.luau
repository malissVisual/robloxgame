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
--   HouseInterior.slot(index)           the origin of interior number `index` (0, 1, 2 ...): far off the map
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
-- 7.x the farm: a plan of kind "farm" (shared/Layouts/Farm.luau) builds its farmhouse like a house and its barn and
-- yard in the farm block below (farmShell and the farm's fixtures' looks): two roofs, the yard open to the sky, the
-- barn doors a second way out with their own daylight. The farmhouse is a chalet inside like a house (its planks,
-- panelling, beams, lace, the front door's leaves); the barn and the yard keep their own (no chalet beams there), and a
-- fixture kind both have (the Stube's kachelofen) takes the farm's own look (FARM_LOOKS).
-- 8.3 the lodge: a plan of kind "lodge" (shared/HouseLayout.luau: a house's plan made bigger, its guest room a bedroom's
-- kind, its study a living room's) builds as a house, and its terrace door (a second doorway to the outside, in a side
-- wall) gets a porch of daylight like the front door's (sidePorch).
-- The owner's Blender furniture (design/blender-furniture/): once ZDCFurnitureArt is imported, server/FurnitureMesh.luau
-- dresses each piece in its models (the Root, its welds and its labels stay; without the import FurnitureLooks' look).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FurnitureLooks = require(Shared.FurnitureLooks)
local FurnitureMesh = require(script.Parent.FurnitureMesh)
local HouseLayout = require(Shared.HouseLayout)

local T = Config.Furniture
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
	hall = { rgb(242, 236, 222), rgb(236, 230, 214) },
	living = { rgb(244, 238, 226), rgb(240, 230, 212) },
	kitchen = { rgb(244, 240, 228), rgb(238, 234, 220) },
	bedroom = { rgb(240, 234, 226), rgb(234, 228, 234) },
	kids = { rgb(242, 236, 212), rgb(228, 238, 228) },
	bath = { rgb(226, 238, 240), rgb(236, 240, 242) },
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
local TRIM = rgb(240, 236, 228)
local WOODWORK = rgb(132, 88, 54) -- the door frames, the window frames and sills
local CEILING = rgb(222, 194, 152) -- pine boards
local BEAM = rgb(108, 72, 44)
local LACE = rgb(250, 248, 242)
local LAMP = rgb(255, 222, 176) -- a warm glow
local DAYLIGHT = rgb(126, 156, 178) -- the windows' dim glow (Neon)
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

-- ── 7.x the farm ──────────────────────────────────────────────────────────────
-- Walt's farm (shared/Layouts/Farm.luau, a plan of kind "farm"). Its farmhouse's rooms are a house's kinds (hall,
-- living: the Stube, kitchen, bedroom; the pantry looks like a hall) and are built above like a house's. Its barn's rooms
-- (stable, barn: the threshing floor, workshop) and the yard are FARM_OWN: the build leaves their floors, walls and
-- lights to farmShell (called where a house gets its ceiling), which builds the two roofs (the yard is open to the
-- sky), the barn in weathered timber, the yard's whitewashed farmhouse wall with its stone plinth and its windows'
-- outsides (shutters, geraniums), the fences with an invisible wall over them, the cobbled path, the barn's door frames
-- and the ranch's name over its yard door. The fixtures' looks below draw the stoves, the larder, the stalls, the hay
-- loft, the beams and their lanterns (the barn's lights), the forge, the trough, the woodpile and the barn doors (the
-- second exit: the doors swung open onto an apron, the daylight beyond, EXIT over them).
local FARM_OWN: { [string]: boolean } = { stable = true, barn = true, workshop = true, yard = true }
local FARM = Config.Furniture.Farm
local TIMBERS = { rgb(122, 86, 58), rgb(106, 76, 54), rgb(138, 98, 64) } -- the barn's boards (weathered larch)
local FARM_TILES = { rgb(70, 120, 90), rgb(206, 196, 170), rgb(160, 76, 56), rgb(84, 112, 150) } -- the stoves' tiles
local WHITEWASH = rgb(242, 238, 228)
local FENCE = rgb(150, 112, 74)
local STONE = rgb(128, 124, 118)
local DARKWOOD = rgb(84, 58, 40)
local FARM_FLOORS: { [string]: Floor } = {
	barn = { color = rgb(152, 114, 76), material = Enum.Material.WoodPlanks },
	stable = { color = rgb(132, 126, 114), material = Enum.Material.Cobblestone },
	workshop = { color = rgb(118, 94, 70), material = Enum.Material.WoodPlanks },
	yard = { color = rgb(126, 118, 96), material = Enum.Material.Pebble },
}
local HORSES = { "THUNDER", "DUSTY", "PEPPER", "BISCUIT" } -- the stalls' name boards, in order (Thunder's first)
local stalls = 0
local FARM_LOOKS: { [string]: FixtureLook } = {} -- the farm's own looks of a house's fixture kinds

-- a kitchen range clad in tiles, its iron hob, the oven door, a brass rail, the flue up to the ceiling
LOOKS.tiled_stove = function(parent, at, s, roll)
	part(parent, "Range", Vector3.new(s.X, s.Y - 0.2, s.Z), at * CFrame.new(0, (s.Y - 0.2) / 2, 0), FARM_TILES[roll(#FARM_TILES)], Enum.Material.CeramicTiles, true)
	part(parent, "Hob", Vector3.new(s.X + 0.1, 0.2, s.Z + 0.1), at * CFrame.new(0, s.Y - 0.1, 0), rgb(40, 40, 44), Enum.Material.Metal, true)
	part(parent, "OvenDoor", Vector3.new(1.3, 1.1, 0.08), at * CFrame.new(-0.6, 1.3, -s.Z / 2 - 0.04), rgb(30, 30, 34), Enum.Material.Metal)
	part(parent, "Rail", Vector3.new(s.X, 0.1, 0.1), at * CFrame.new(0, s.Y - 0.45, -s.Z / 2 - 0.15), rgb(204, 164, 72), Enum.Material.Metal)
	local flue = T.Ceiling - s.Y
	cylinder(part(parent, "Flue", Vector3.new(flue, 0.6, 0.6), at * CFrame.new(0.9, s.Y + flue / 2, s.Z / 2 - 0.5) * CFrame.Angles(0, 0, math.pi / 2), rgb(50, 50, 54), Enum.Material.Metal))
end

-- the Stube's tiled stove (a Kachelofen): a stone base, the tiled body and its crown, a cornice, the bench in front of
-- it (the farm's own look of the fixture kind a chalet's living room has too: FARM_LOOKS goes before LOOKS in a farm)
FARM_LOOKS.kachelofen = function(parent, at, s, roll)
	local tile = FARM_TILES[roll(#FARM_TILES)]
	local body = s.Z - 1.2
	local back = s.Z / 2 - body / 2
	part(parent, "Base", Vector3.new(s.X, 0.5, body), at * CFrame.new(0, 0.25, back), STONE, Enum.Material.Slate, true)
	part(parent, "Stove", Vector3.new(s.X - 0.4, 3.8, body - 0.2), at * CFrame.new(0, 2.4, back + 0.1), tile, Enum.Material.CeramicTiles, true)
	part(parent, "Cornice", Vector3.new(s.X, 0.25, body), at * CFrame.new(0, 4.42, back), DARKWOOD, Enum.Material.Wood, true)
	part(parent, "Crown", Vector3.new(s.X - 0.9, 1.3, body - 0.6), at * CFrame.new(0, 5.2, back + 0.3), tile:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.CeramicTiles, true)
	part(parent, "Bench", Vector3.new(s.X, 0.25, 1.2), at * CFrame.new(0, 1.6, -s.Z / 2 + 0.6), rgb(170, 128, 82), Enum.Material.Wood, true)
	part(parent, "BenchFront", Vector3.new(s.X, 1.5, 0.15), at * CFrame.new(0, 0.75, -s.Z / 2 + 0.1), rgb(150, 110, 70), Enum.Material.Wood, true)
end

-- the pantry's larder: wooden shelves, rows of preserving jars, a ham hung from the top
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

-- a stall: its straw and the horse's name board on the back wall (the first stall is Thunder's)
LOOKS.stall = function(parent, at, s)
	stalls += 1
	part(parent, "Straw", Vector3.new(s.X - 0.6, 0.1, s.Z - 0.4), at * CFrame.new(0, 0.05, 0), rgb(214, 186, 106), Enum.Material.Grass)
	local board = part(parent, "NameBoard", Vector3.new(2.4, 0.7, 0.12), at * CFrame.new(0, 6.4, s.Z / 2 - 0.06), DARKWOOD, Enum.Material.Wood)
	sign(board, HORSES[(stalls - 1) % #HORSES + 1], Enum.NormalId.Front, rgb(240, 226, 190))
end

-- a partition between two stalls: the boards, a rail on top, the post at its front
LOOKS.stall_wall = function(parent, at, s)
	local wood = rgb(130, 94, 62)
	part(parent, "Boards", Vector3.new(0.4, s.Y - 1.2, s.Z), at * CFrame.new(0, (s.Y - 1.2) / 2, 0), wood, Enum.Material.WoodPlanks, true)
	part(parent, "Rail", Vector3.new(0.5, 0.3, s.Z), at * CFrame.new(0, s.Y - 0.15, 0), DARKWOOD, Enum.Material.Wood, true)
	part(parent, "Post", Vector3.new(0.5, s.Y, 0.5), at * CFrame.new(0, s.Y / 2, -s.Z / 2 + 0.25), DARKWOOD, Enum.Material.Wood, true)
end

-- a manger: a wooden trough on its front board, hay in it
LOOKS.manger = function(parent, at, s)
	part(parent, "Front", Vector3.new(s.X, 1.75, 0.2), at * CFrame.new(0, 0.875, -s.Z / 2 + 0.1), rgb(130, 94, 62), Enum.Material.WoodPlanks, true)
	part(parent, "Trough", Vector3.new(s.X, 0.9, s.Z), at * CFrame.new(0, 2.2, 0), rgb(120, 86, 56), Enum.Material.Wood, true)
	part(parent, "Hay", Vector3.new(s.X - 0.3, 0.5, s.Z - 0.3), at * CFrame.new(0, 2.75, 0), rgb(214, 186, 106), Enum.Material.Grass)
end

-- the hay loft over the stalls: its boards (`at` is their floor), the beam along its edge, the hay piled on it and a
-- fringe of hay hanging over the edge
LOOKS.hay_loft = function(parent, at, s)
	local straw = rgb(214, 186, 106)
	part(parent, "Loft", Vector3.new(s.X, 0.4, s.Z), at * CFrame.new(0, 0.2, 0), rgb(130, 96, 64), Enum.Material.WoodPlanks, true)
	part(parent, "LoftBeam", Vector3.new(s.X, 0.7, 0.7), at * CFrame.new(0, -0.15, -s.Z / 2 + 0.35), DARKWOOD, Enum.Material.Wood)
	part(parent, "HayPile", Vector3.new(s.X * 0.7, 2.6, s.Z * 0.55), at * CFrame.new(-s.X * 0.1, 1.7, s.Z * 0.15), straw, Enum.Material.Grass)
	part(parent, "HayPile", Vector3.new(s.X * 0.35, 1.6, s.Z * 0.3), at * CFrame.new(s.X * 0.25, 1.2, -s.Z * 0.2), straw:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Grass)
	part(parent, "HayFringe", Vector3.new(s.X - 3, 0.9, 0.4), at * CFrame.new(0, -0.6, -s.Z / 2 - 0.1), straw, Enum.Material.Grass)
end

-- a tie beam across a barn room (`at` its underside)
LOOKS.beam = function(parent, at, s)
	part(parent, "Beam", s, at * CFrame.new(0, s.Y / 2, 0), DARKWOOD, Enum.Material.Wood)
end

-- a lantern hung from a beam (`at` its bottom, size.Y up to the beam): the chain, the cap, the glow and its light
LOOKS.lantern = function(parent, at, s)
	local metal = rgb(44, 42, 40)
	part(parent, "Chain", Vector3.new(0.08, s.Y - 1.2, 0.08), at * CFrame.new(0, 1.2 + (s.Y - 1.2) / 2, 0), metal, Enum.Material.Metal)
	part(parent, "LanternCap", Vector3.new(s.X, 0.25, s.Z), at * CFrame.new(0, 1.075, 0), metal, Enum.Material.Metal)
	local glow = part(parent, "Lantern", Vector3.new(s.X - 0.3, 0.95, s.Z - 0.3), at * CFrame.new(0, 0.475, 0), color(FARM.Lantern.Color), Enum.Material.Neon)
	glow.CastShadow = false
	local light = Instance.new("PointLight")
	light.Brightness = FARM.Lantern.Brightness
	light.Range = FARM.Lantern.Range
	light.Color = color(FARM.Lantern.Color)
	light.Shadows = false
	light.Parent = glow
end

-- the smith's forge: a stone hearth, its embers, the iron hood and the flue up to the roof
LOOKS.forge = function(parent, at, s)
	part(parent, "Hearth", Vector3.new(s.X, 2.4, s.Z), at * CFrame.new(0, 1.2, 0), STONE, Enum.Material.Brick, true)
	part(parent, "Embers", Vector3.new(s.X - 1.2, 0.2, s.Z - 1.2), at * CFrame.new(0, 2.5, 0), rgb(255, 110, 40), Enum.Material.Neon)
	part(parent, "Hood", Vector3.new(s.X, 1.4, s.Z - 0.4), at * CFrame.new(0, 5.5, 0.2), rgb(54, 54, 58), Enum.Material.Metal)
	local flue = FARM.BarnCeiling - 6.2
	part(parent, "Flue", Vector3.new(1.2, flue, 1.2), at * CFrame.new(0, 6.2 + flue / 2, s.Z / 2 - 0.7), rgb(54, 54, 58), Enum.Material.Metal)
end

-- the yard's stone water trough and its pump
LOOKS.trough = function(parent, at, s)
	part(parent, "Trough", Vector3.new(s.X, 1.8, s.Z), at * CFrame.new(0, 0.9, 0), STONE, Enum.Material.Slate, true)
	local water = part(parent, "Water", Vector3.new(s.X - 0.5, 0.06, s.Z - 0.5), at * CFrame.new(0, 1.75, 0), rgb(110, 160, 190), Enum.Material.Glass)
	water.Transparency = 0.3
	part(parent, "Pump", Vector3.new(0.45, s.Y + 1.2, 0.45), at * CFrame.new(s.X / 2 - 0.5, (s.Y + 1.2) / 2, s.Z / 2 - 0.3), rgb(60, 92, 70), Enum.Material.Metal, true)
end

-- firewood stacked along the farmhouse's wall under a little roof
LOOKS.woodpile = function(parent, at, s)
	part(parent, "Woodpile", Vector3.new(s.X, s.Y - 0.8, s.Z - 0.2), at * CFrame.new(0, (s.Y - 0.8) / 2, 0.1), rgb(176, 136, 92), Enum.Material.Wood, true)
	part(parent, "WoodRoof", Vector3.new(s.X + 0.6, 0.2, s.Z + 0.4), at * CFrame.new(0, s.Y - 0.3, 0) * CFrame.Angles(-0.15, 0, 0), DARKWOOD, Enum.Material.WoodPlanks)
end

-- the barn doors (`at` the doorway's middle on the wall's line, its front into the barn, +Z outside): the posts and
-- the lintel, the two doors swung wide open against the apron's sides (they keep you on it), the apron, the daylight
-- beyond it (dark at night) and the EXIT sign over them inside
LOOKS.barn_doors = function(parent, at, s)
	local w, h, wall = s.X, s.Y, s.Z
	local apron = FARM.Apron
	for _, x in { -1, 1 } do
		part(parent, "Jamb", Vector3.new(0.8, h + 0.6, wall + 0.4), at * CFrame.new(x * (w / 2 + 0.4), (h + 0.6) / 2, 0), DARKWOOD, Enum.Material.Wood)
		part(parent, "BarnDoor", Vector3.new(0.35, h - 0.6, apron), at * CFrame.new(x * (w / 2 + 0.3), (h - 0.6) / 2 + 0.1, wall / 2 + apron / 2), rgb(150, 56, 44), Enum.Material.WoodPlanks, true)
		local brace = math.sqrt(apron * apron + (h - 1.6) * (h - 1.6))
		part(parent, "Brace", Vector3.new(0.4, brace, 0.4), at * CFrame.new(x * (w / 2 + 0.05), h / 2, wall / 2 + apron / 2) * CFrame.Angles(math.atan2(apron, h - 1.6), 0, 0), rgb(236, 230, 214), Enum.Material.Wood)
	end
	part(parent, "Lintel", Vector3.new(w + 2.4, 0.8, wall + 0.4), at * CFrame.new(0, h + 0.4, 0), DARKWOOD, Enum.Material.Wood)
	part(parent, "Apron", Vector3.new(w + 1, 0.2, apron), at * CFrame.new(0, -0.1, wall / 2 + apron / 2), rgb(118, 108, 90), Enum.Material.Ground, true)
	local glow = part(parent, "BarnDaylight", Vector3.new(w + 1, h + 1, 0.4), at * CFrame.new(0, (h + 1) / 2, wall / 2 + apron + 0.2), rgb(236, 240, 228), Enum.Material.Neon, true)
	glow.CastShadow = false
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front -- (-Z: into the barn)
	light.Brightness = FARM.BarnLight.Brightness
	light.Range = FARM.BarnLight.Range
	light.Angle = 70
	light.Color = color(FARM.BarnLight.Color)
	light.Parent = glow
	daylight(glow, NIGHT.porch, light)
	local exit = part(parent, "ExitSign", Vector3.new(2.6, 0.9, 0.3), at * CFrame.new(0, h + 1.35, -wall / 2 - 0.15), rgb(250, 250, 248), SMOOTH)
	sign(exit, "EXIT", Enum.NormalId.Front, rgb(255, 255, 255), rgb(30, 160, 80))
end

-- 8.3 the lodge: a door's leaf, shut in its doorway (a part of its own, apart from the wall, no collision): its name, its
-- door ("front", "terrace": the attribute DoorLeaf) and the side of the doorway it hangs on (Hinge: "west", "east",
-- "south", "north", the interior's axes as the map's). The doors' swing is the client's (it reads these).
local function doorLeaf(parent: Instance, name: string, size: Vector3, cf: CFrame, c: Color3, door: string, hinge: string): Part
	local p = part(parent, name, size, cf, c, Enum.Material.Wood)
	p:SetAttribute("DoorLeaf", door)
	p:SetAttribute("Hinge", hinge)
	-- (Danny's paths go through it, whatever its swing does with it: a door, not a wall)
	local through = Instance.new("PathfindingModifier")
	through.PassThrough = true
	through.Parent = p
	return p
end

-- 8.3 the lodge's numbers (Config.Furniture.Lodge: the owner found a house's inside "a flashbang"): its lights modest,
-- warm, read from there; no glowing lamps, panes or porch walls; its plaster a warm off-white.
local LODGE = (T :: any).Lodge

-- The daylight through a doorway to the outside: the porch's outer wall glows, a SurfaceLight on it shines into the house
-- (+Z, its Back), dark at night (7.0 review). 8.3 the lodge: the wall soft (not glowing, LODGE.Porch), its light the
-- modest LODGE.DoorLight, never the daylight's.
local function porchLight(glow: BasePart, lodge: boolean)
	local tune = if lodge then LODGE.DoorLight else T.DoorLight
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Back -- (+Z: into the house)
	light.Brightness = tune.Brightness
	light.Range = tune.Range
	light.Angle = 70
	light.Color = color(tune.Color)
	light.Parent = glow
	if lodge then
		glow.Material = SMOOTH
		glow.Color = color(LODGE.Porch)
	else
		daylight(glow, NIGHT.porch, light) -- 7.0 review: dark at night
	end
end

-- 8.3 the lodge: its rooms' plaster mixed toward the warm off-white (not the bathroom's tiles nor the garage's concrete).
local function lodgeWalls(plaster: { [string]: Color3 })
	for kind, c in plaster do
		if kind ~= "bath" and kind ~= "garage" then
			plaster[kind] = c:Lerp(color(LODGE.Walls), LODGE.WallsMix)
		end
	end
end

-- 8.3 the lodge: a way out that is not the front door (the terrace door in a side wall: HouseLayout's kind "lodge") gets
-- a porch as the front door's (its floor, larch sides and roof, the outer wall that stops a walk out with its light into
-- the house: porchLight's, the lodge's soft), the door's lintel and the EXIT sign over it inside. The frame: the
-- doorway's middle on its wall's centre line, -Z out of the house.
local function sidePorch(shell: Instance, decor: Instance, plan: HouseLayout.Plan, origin: CFrame, door: HouseLayout.Door)
	local half = plan.wall / 2
	local mid = (plan.min + plan.max) / 2
	local out = if door.axis == "Z" then Vector3.new(if door.at.X > mid.X then 1 else -1, 0, 0) else Vector3.new(0, 0, if door.at.Z > mid.Z then 1 else -1)
	local frame = origin * CFrame.lookAt(door.at, door.at + out)
	local w, porch, h = door.width / 2 + 1, 6, plan.doorHeight
	local larch = rgb(156, 112, 72)
	part(shell, "TerracePorch", Vector3.new(2 * w, 0.2, porch), frame * CFrame.new(0, -0.1, -(half + porch / 2)), rgb(150, 146, 140), Enum.Material.WoodPlanks, true)
	for _, s in { -1, 1 } do
		part(shell, "TerraceWall", Vector3.new(0.5, plan.ceiling, porch), frame * CFrame.new(s * (w + 0.25), plan.ceiling / 2, -(half + porch / 2)), larch, Enum.Material.WoodPlanks, true)
	end
	part(shell, "TerraceRoof", Vector3.new(2 * w + 1, 0.5, porch), frame * CFrame.new(0, h + 1.25, -(half + porch / 2)), larch, Enum.Material.WoodPlanks, true)
	part(decor, "Lintel", Vector3.new(door.width + 0.8, 0.4, plan.wall + 0.3), frame * CFrame.new(0, h + 0.2, 0), rgb(110, 76, 50), Enum.Material.Wood)
	-- its leaf, shut in the doorway, hinged at the frame's +X jamb (the lodge's east door: its south side)
	local right = Vector3.new(-out.Z, 0, out.X) -- (the frame's +X: its RightVector)
	local hinge = if math.abs(right.X) > math.abs(right.Z) then (if right.X > 0 then "east" else "west") else (if right.Z > 0 then "south" else "north")
	doorLeaf(decor, "TerraceLeaf", Vector3.new(door.width - 0.06, h - 0.15, 0.24), frame * CFrame.new(0, (h - 0.15) / 2, 0), rgb(96, 64, 40), "terrace", hinge)
	local glow = part(shell, "TerraceDaylight", Vector3.new(2 * w, h + 1.5, 0.4), frame * CFrame.new(0, (h + 1.5) / 2, -(half + porch + 0.2)), rgb(236, 240, 228), Enum.Material.Neon, true)
	glow.CastShadow = false
	porchLight(glow, plan.kind == "lodge") -- (the lodge's: soft, Config.Furniture.Lodge.DoorLight)
	local exit = part(decor, "ExitSign", Vector3.new(2.6, 0.9, 0.3), frame * CFrame.new(0, h + 1.05, half + 0.15), rgb(250, 250, 248), SMOOTH)
	sign(exit, "EXIT", Enum.NormalId.Back, rgb(255, 255, 255), rgb(30, 160, 80))
end

-- The farm's own shell (see the block's header): the roofs, the barn's and the yard's floors and walls, the yard's
-- dressing.
local function farmShell(shell: Instance, decor: Instance, plan: HouseLayout.Plan, origin: CFrame, roll: (number) -> number)
	stalls = 0
	local half = plan.wall / 2
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	local timber = TIMBERS[roll(#TIMBERS)]
	local shutters = ({ rgb(60, 110, 70), rgb(150, 50, 40), rgb(70, 96, 140) })[roll(3)]
	local kindOf: { [string]: string } = {}
	-- the two buildings' boxes (to their walls' outer faces) and their tops; the yard
	type Box = { x0: number, z0: number, x1: number, z1: number, top: number }
	local house: Box? = nil
	local barn: Box? = nil
	local yard: HouseLayout.Room? = nil
	for _, room in plan.rooms do
		kindOf[room.id] = room.kind
		if room.kind == "yard" then
			yard = room
			continue
		end
		local b: Box = { x0 = room.min.X - half, z0 = room.min.Z - half, x1 = room.max.X + half, z1 = room.max.Z + half, top = room.max.Y }
		local into = if FARM_OWN[room.kind] then barn else house
		if into then
			b = { x0 = math.min(b.x0, into.x0), z0 = math.min(b.z0, into.z0), x1 = math.max(b.x1, into.x1), z1 = math.max(b.z1, into.z1), top = math.max(b.top, into.top) }
		end
		if FARM_OWN[room.kind] then
			barn = b
		else
			house = b
		end
	end
	-- the roofs: the farmhouse's ceiling (a house's), the barn's dark boards
	local function roof(b: Box, name: string, c: Color3, material: Enum.Material)
		part(shell, name, Vector3.new(b.x1 - b.x0, 1, b.z1 - b.z0), at((b.x0 + b.x1) / 2, b.top + 0.5, (b.z0 + b.z1) / 2), c, material, true)
	end
	if house then
		roof(house, "Ceiling", CEILING, Enum.Material.WoodPlanks) -- (a chalet's pine ceiling, as a house's)
	end
	if barn then
		roof(barn, "BarnRoof", timber:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.WoodPlanks)
	end
	-- the barn's and the yard's floors (to their walls' middles)
	for _, room in plan.rooms do
		local look = FARM_FLOORS[room.kind]
		if look then
			local w, d = room.max.X - room.min.X + plan.wall, room.max.Z - room.min.Z + plan.wall
			part(shell, "Floor", Vector3.new(w, 0.2, d), at((room.min.X + room.max.X) / 2, -0.1, (room.min.Z + room.max.Z) / 2), look.color, look.material, true)
		end
	end
	-- their walls: the barn's timber, the yard's whitewashed farmhouse wall (a stone plinth at its foot), the barn's
	-- front, the fences (an invisible wall over them up to Farm.Barrier)
	for _, face in plan.faces do
		local kind = kindOf[face.room]
		if not kind or not FARM_OWN[kind] then
			continue
		end
		local size = face.max - face.min
		local centre = (face.min + face.max) / 2
		local c, material = timber, Enum.Material.WoodPlanks
		local houseSide = kind == "yard" and not face.outer and face.normal.Z > 0.5
		if kind == "yard" and face.outer then
			c = FENCE
		elseif houseSide then
			c, material = WHITEWASH, Enum.Material.Plaster
		elseif face.outer then
			c = timber:Lerp(Color3.new(0, 0, 0), 0.08)
		end
		part(shell, if face.header then "Header" else "Wall", size, at(centre.X, centre.Y, centre.Z), c, material, true)
		if face.header then
			continue
		end
		if kind == "yard" and face.outer then
			local high = FARM.Barrier - size.Y
			local barrier = part(shell, "Barrier", Vector3.new(size.X, high, size.Z), at(centre.X, face.max.Y + high / 2, centre.Z), FENCE, SMOOTH, true)
			barrier.Transparency = 1
			barrier.CastShadow = false
		elseif houseSide then
			part(decor, "Plinth", Vector3.new(size.X, 1.4, 0.2), at(centre.X, 0.7, face.max.Z + 0.1), STONE, Enum.Material.Slate)
		end
	end
	if not yard then
		return
	end
	local y = yard :: HouseLayout.Room
	-- the eaves over the yard: the farmhouse's and the barn's
	local width = y.max.X - y.min.X + plan.wall
	local cx = (y.min.X + y.max.X) / 2
	if house then
		part(decor, "Eave", Vector3.new(width + 2, 0.4, 2.6), at(cx, house.top + 0.8, y.min.Z + 1.3), DARKWOOD, Enum.Material.WoodPlanks)
	end
	if barn then
		part(decor, "Eave", Vector3.new(width + 2, 0.4, 2.6), at(cx, barn.top + 0.8, y.max.Z - 1.3), DARKWOOD, Enum.Material.WoodPlanks)
	end
	-- the windows' outsides on the farmhouse's yard wall: a frame, the dark pane, shutters, a box of geraniums
	for _, w in plan.windows do
		local kind = kindOf[w.room]
		if kind and not FARM_OWN[kind] and w.normal.Z < -0.5 and math.abs(w.at.Z + plan.wall - y.min.Z) < 0.01 then
			local z = y.min.Z
			part(decor, "WindowFrame", Vector3.new(w.width + 0.5, w.height + 0.5, 0.16), at(w.at.X, w.at.Y, z + 0.08), DARKWOOD, SMOOTH)
			local pane = part(decor, "Pane", Vector3.new(w.width, w.height, 0.06), at(w.at.X, w.at.Y, z + 0.19), rgb(40, 52, 62), Enum.Material.Glass)
			pane.Reflectance = 0.2
			for _, s in { -1, 1 } do
				part(decor, "Shutter", Vector3.new(w.width / 2, w.height + 0.3, 0.12), at(w.at.X + s * (w.width * 0.75 + 0.35), w.at.Y, z + 0.1), shutters, Enum.Material.WoodPlanks)
			end
			local sill = w.at.Y - w.height / 2
			part(decor, "FlowerBox", Vector3.new(w.width + 0.6, 0.6, 0.7), at(w.at.X, sill - 0.3, z + 0.35), DARKWOOD, Enum.Material.Wood)
			part(decor, "Geraniums", Vector3.new(w.width + 0.3, 0.6, 0.55), at(w.at.X, sill + 0.25, z + 0.35), rgb(214, 40, 52), Enum.Material.Fabric)
		end
	end
	-- the frame of the barn's door from the yard (a house's skips doorways this wide); the cobbled path from the back
	-- door to it; the ranch's name over it
	local back: HouseLayout.Door? = nil
	local barnDoor: HouseLayout.Door? = nil
	for _, d in plan.doors do
		local a, b = kindOf[d.rooms[1]], kindOf[d.rooms[2]]
		if d.rooms[1] == "mudroom" and d.rooms[2] == y.id then
			back = d
		end
		if not (a and FARM_OWN[a] and b and FARM_OWN[b]) then
			continue
		end
		if d.rooms[1] == y.id or d.rooms[2] == y.id then
			barnDoor = d
		else
			continue -- (the openings inside the barn go without)
		end
		for _, s in { -1, 1 } do
			local dx = s * (d.width / 2 + 0.3)
			local size = if d.axis == "X" then Vector3.new(0.6, plan.doorHeight, plan.wall + 0.3) else Vector3.new(plan.wall + 0.3, plan.doorHeight, 0.6)
			part(decor, "Jamb", size, at(d.at.X + (if d.axis == "X" then dx else 0), plan.doorHeight / 2, d.at.Z + (if d.axis == "X" then 0 else dx)), DARKWOOD, Enum.Material.Wood)
		end
	end
	if back and barnDoor then
		local a = Vector3.new(back.at.X, 0.03, back.at.Z + half)
		local b = Vector3.new(barnDoor.at.X, 0.03, barnDoor.at.Z - half)
		part(decor, "Path", Vector3.new(4.5, 0.06, (b - a).Magnitude), origin * CFrame.lookAt((a + b) / 2, b), rgb(150, 146, 138), Enum.Material.Cobblestone)
	end
	if barnDoor then
		local board = part(decor, "RanchSign", Vector3.new(9, 1.6, 0.3), at(barnDoor.at.X, plan.doorHeight + 2.2, barnDoor.at.Z - half - 0.15), DARKWOOD, Enum.Material.Wood)
		sign(board, "SILVER SPUR RANCH", Enum.NormalId.Front, rgb(240, 226, 190))
	end
end

-- ── The interior ─────────────────────────────────────────────────────────────

function HouseInterior.build(plan: HouseLayout.Plan, origin: CFrame): (Model, { [number]: Model })
	local roll = dice(plan.seed)
	local model = Instance.new("Model")
	model.Name = "HouseInterior"
	model:SetAttribute("Seed", plan.seed)
	model:SetAttribute("Kind", plan.kind)
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
	plaster.pantry, panelling.pantry = plaster.hall, panelling.hall -- (7.x the farm's pantry looks like its hall)
	local lodge = plan.kind == "lodge" -- 8.3: warm off-white walls, modest lights (Config.Furniture.Lodge)
	if lodge then
		lodgeWalls(plaster)
	end
	local planks = PLANKS[roll(#PLANKS)]
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
		if FARM_OWN[room.kind] then
			continue -- 7.x the farm's barn and yard: farmShell
		end
		local floor = FLOOR_OF[room.kind]
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
	if plan.kind == "farm" then
		farmShell(shell, decor, plan, origin, roll) -- 7.x the farm: its two roofs, the barn and the yard
	else
		part(shell, "Ceiling", Vector3.new(plan.size.X, 1, plan.size.Z), at(mid.X, ceiling + 0.5, mid.Z), CEILING, Enum.Material.WoodPlanks, true)
	end

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
			if room.kind == "bath" or room.kind == "garage" or FARM_OWN[room.kind] or room.max.Z - room.min.Z < 10 then
				continue -- (7.x the farm: none in its barn, it has its own tie beams, nor over the open yard)
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
				part(decor, "Beam", Vector3.new(x1 - x0, beam, beam), at((x0 + x1) / 2, ceiling - beam / 2, z), BEAM, Enum.Material.Wood)
			end
		end
	end

	-- the walls: a slab per room side in its plaster, the wood panelling along its foot (the bathroom tiled to the
	-- ceiling, the garage bare concrete)
	for _, face in plan.faces do
		local kind = kindOf[face.room] or "hall"
		if FARM_OWN[kind] then
			continue -- 7.x the farm's barn and yard: farmShell
		end
		local size = face.max - face.min
		local centre = (face.min + face.max) / 2
		local material = if kind == "garage" then Enum.Material.Concrete elseif kind == "bath" then Enum.Material.CeramicTiles else Enum.Material.Plaster
		part(shell, if face.header then "Header" else "Wall", size, at(centre.X, centre.Y, centre.Z), plaster[kind] or TRIM, material, true)
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
		local panel = panelling[kind]
		if along <= 1.6 or kind == "garage" or kind == "bath" then
			continue -- (nothing on a stub beside a doorway; the bathroom's walls are tiles all the way up)
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
		-- 7.x alpine: the front door's two leaves opened out against the porch's sides, a painted flower on each (on the
		-- side toward the porch's middle): its bloom over a pair of green leaves
		local leaf = front.width / 2
		local paint = DOORS[roll(#DOORS)]
		local bloom = BLOOMS[roll(#BLOOMS)]
		for _, s in (if lodge then {} else { -1, 1 }) :: { number } do -- (8.3 the lodge: its leaves shut, below)
			local lx = x + s * (leaf + 0.12)
			local lz = z - 0.15 - leaf / 2
			local tall = plan.doorHeight - 0.15
			part(decor, "DoorLeaf", Vector3.new(0.24, tall, leaf), at(lx, tall / 2, lz), paint, Enum.Material.Wood)
			local face = lx - s * 0.14
			cylinder(part(decor, "Bloom", Vector3.new(0.04, 1.1, 1.1), at(face, tall * 0.68, lz), bloom, SMOOTH))
			part(decor, "Leaves", Vector3.new(0.04, 0.9, 0.9), at(face, tall * 0.5, lz) * CFrame.Angles(math.pi / 4, 0, 0), LEAF, SMOOTH)
		end
		local glow = part(shell, "Daylight", Vector3.new(2 * w, plan.doorHeight + 1.5, 0.4), at(x, (plan.doorHeight + 1.5) / 2, z - porch - 0.2), rgb(236, 240, 228), Enum.Material.Neon, true)
		glow.CastShadow = false
		porchLight(glow, lodge) -- (its light into the house; 8.3 the lodge's soft, Config.Furniture.Lodge.DoorLight)
		if lodge then
			-- 8.3 the lodge: the front door's two leaves shut in the doorway, each hinged at its jamb (west, east): a door
			-- that opens as you walk through it (the doors' swing is the client's; nothing collides)
			for _, s in { -1, 1 } do
				doorLeaf(decor, if s < 0 then "FrontLeafWest" else "FrontLeafEast", Vector3.new(leaf - 0.06, plan.doorHeight - 0.15, 0.24), at(x + s * leaf / 2, (plan.doorHeight - 0.15) / 2, front.at.Z), paint, "front", if s < 0 then "west" else "east")
			end
		end
		local mat = part(decor, "WelcomeMat", Vector3.new(4, 0.06, 2.2), at(x, 0.03, z - 1.6), rgb(150, 110, 70), Enum.Material.Fabric)
		sign(mat, "WELCOME", Enum.NormalId.Top, rgb(60, 40, 24))
		local exit = part(decor, "ExitSign", Vector3.new(2.6, 0.9, 0.3), at(x, plan.doorHeight + 1.05, front.at.Z + half + 0.15), rgb(250, 250, 248), SMOOTH)
		sign(exit, "EXIT", Enum.NormalId.Back, rgb(255, 255, 255), rgb(30, 160, 80))
	end
	-- 8.3 the lodge: its other way out (the terrace door) gets its own porch of daylight (a farm's barn doors have theirs)
	if plan.kind ~= "farm" then
		for index, door in plan.doors do
			if index > 1 and door.rooms[2] == "outside" then
				sidePorch(shell, decor, plan, origin, door)
			end
		end
	end

	-- the windows: a wooden frame, the glowing pane and a deep sill (a small one no sill); a lace curtain over the lower
	-- half of every big one but the bathroom's (7.x alpine)
	for _, w in plan.windows do
		local kind = kindOf[w.room] or "hall"
		local frame = origin * CFrame.lookAt(w.at, w.at + w.normal) -- -Z into the room
		local small = w.width <= 3
		part(decor, "WindowFrame", Vector3.new(w.width + 0.5, w.height + 0.5, 0.16), frame * CFrame.new(0, 0, -0.08), WOODWORK, Enum.Material.Wood)
		local pane = part(decor, "Window", Vector3.new(w.width, w.height, 0.06), frame * CFrame.new(0, 0, -0.19), if kind == "bath" then rgb(170, 190, 200) else DAYLIGHT, Enum.Material.Neon)
		pane:SetAttribute("InteriorWindow", true)
		if lodge then
			pane.Material, pane.Color = SMOOTH, color(LODGE.Pane) -- (8.3 the lodge: a soft pane, no glow)
		else
			daylight(pane, if kind == "bath" then NIGHT.bath else NIGHT.pane) -- 7.0 review: a night sky at night
		end
		if not small then
			part(decor, "Sill", Vector3.new(w.width + 1, 0.2, 0.6), frame * CFrame.new(0, -w.height / 2 - 0.1, -0.3), WOODWORK, Enum.Material.Wood)
		end
		if not small and kind ~= "bath" and kind ~= "garage" then
			local lace = part(decor, "Lace", Vector3.new(w.width + 0.1, w.height * 0.55, 0.05), frame * CFrame.new(0, -w.height * 0.225, -0.3), LACE, Enum.Material.Fabric)
			lace.Transparency = 0.3
		end
	end

	-- the ceiling lights: one in the middle of every room, two in a long one, a warm glow (7.x alpine); a tube in the
	-- garage. 8.3 the lodge: one modest warm light a room (Config.Furniture.Lodge.Light), its lamp not glowing.
	local tune = if lodge then LODGE.Light else T.Light
	for _, room in plan.rooms do
		if FARM_OWN[room.kind] then
			continue -- 7.x the farm's barn: its lanterns are fixtures; the yard is open to the sky
		end
		local lx, lz = room.max.X - room.min.X, room.max.Z - room.min.Z
		local cx, cz = (room.min.X + room.max.X) / 2, (room.min.Z + room.max.Z) / 2
		local spots: { { number } } = { { cx, cz } }
		if math.max(lx, lz) > T.Light.LongRoom and not lodge then
			spots = if lx > lz then { { room.min.X + lx / 4, cz }, { room.max.X - lx / 4, cz } } else { { cx, room.min.Z + lz / 4 }, { cx, room.max.Z - lz / 4 } }
		end
		for _, s in spots do
			local lamp
			if room.kind == "garage" then
				lamp = part(decor, "Tube", Vector3.new(4, 0.3, 0.6), at(s[1], ceiling - 0.15, s[2]), rgb(236, 244, 255), if lodge then SMOOTH else Enum.Material.Neon)
			else
				lamp = cylinder(part(decor, "Lamp", Vector3.new(0.3, 2.6, 2.6), at(s[1], ceiling - 0.15, s[2]) * CFrame.Angles(0, 0, math.pi / 2), LAMP, if lodge then SMOOTH else Enum.Material.Neon))
			end
			lamp.CastShadow = false
			local light = Instance.new("PointLight")
			light.Brightness = tune.Brightness
			light.Range = tune.Range
			light.Color = if room.kind == "garage" and not lodge then rgb(226, 236, 255) else color(tune.Color)
			light.Shadows = false
			light.Parent = lamp
		end
	end

	-- the fixtures (a farm's own looks first: 7.x the farm)
	local farm = plan.kind == "farm"
	for _, f in plan.fixtures do
		local look = (farm and FARM_LOOKS[f.kind]) or LOOKS[f.kind]
		if look then
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

-- The origin of interior number `index`: far off the map (past Map.Bounds), a slot apart, at the same height.
function HouseInterior.slot(index: number): CFrame
	local o = T.Slot.Origin
	return CFrame.new(o[1] + index * T.Slot.Spacing, o[2], o[3])
end

function HouseInterior.destroy(model: Model)
	model:Destroy()
end

return HouseInterior
