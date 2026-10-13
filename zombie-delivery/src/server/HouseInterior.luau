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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FurnitureLooks = require(Shared.FurnitureLooks)
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
	part(shell, "Ceiling", Vector3.new(plan.size.X, 1, plan.size.Z), at(mid.X, ceiling + 0.5, mid.Z), CEILING, Enum.Material.WoodPlanks, true)

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
				part(decor, "Beam", Vector3.new(x1 - x0, beam, beam), at((x0 + x1) / 2, ceiling - beam / 2, z), BEAM, Enum.Material.Wood)
			end
		end
	end

	-- the walls: a slab per room side in its plaster, the wood panelling along its foot (the bathroom tiled to the
	-- ceiling, the garage bare concrete)
	for _, face in plan.faces do
		local kind = kindOf[face.room] or "hall"
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
		for _, s in { -1, 1 } do
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
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Back -- (+Z: into the house)
		light.Brightness = T.DoorLight.Brightness
		light.Range = T.DoorLight.Range
		light.Angle = 70
		light.Color = color(T.DoorLight.Color)
		light.Parent = glow
		daylight(glow, NIGHT.porch, light) -- 7.0 review: dark at night
		local mat = part(decor, "WelcomeMat", Vector3.new(4, 0.06, 2.2), at(x, 0.03, z - 1.6), rgb(150, 110, 70), Enum.Material.Fabric)
		sign(mat, "WELCOME", Enum.NormalId.Top, rgb(60, 40, 24))
		local exit = part(decor, "ExitSign", Vector3.new(2.6, 0.9, 0.3), at(x, plan.doorHeight + 1.05, front.at.Z + half + 0.15), rgb(250, 250, 248), SMOOTH)
		sign(exit, "EXIT", Enum.NormalId.Back, rgb(255, 255, 255), rgb(30, 160, 80))
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
		daylight(pane, if kind == "bath" then NIGHT.bath else NIGHT.pane) -- 7.0 review: a night sky at night
		if not small then
			part(decor, "Sill", Vector3.new(w.width + 1, 0.2, 0.6), frame * CFrame.new(0, -w.height / 2 - 0.1, -0.3), WOODWORK, Enum.Material.Wood)
		end
		if not small and kind ~= "bath" and kind ~= "garage" then
			local lace = part(decor, "Lace", Vector3.new(w.width + 0.1, w.height * 0.55, 0.05), frame * CFrame.new(0, -w.height * 0.225, -0.3), LACE, Enum.Material.Fabric)
			lace.Transparency = 0.3
		end
	end

	-- the ceiling lights: one in the middle of every room, two in a long one, a warm glow (7.x alpine); a tube in the
	-- garage
	for _, room in plan.rooms do
		local lx, lz = room.max.X - room.min.X, room.max.Z - room.min.Z
		local cx, cz = (room.min.X + room.max.X) / 2, (room.min.Z + room.max.Z) / 2
		local spots: { { number } } = { { cx, cz } }
		if math.max(lx, lz) > T.Light.LongRoom then
			spots = if lx > lz then { { room.min.X + lx / 4, cz }, { room.max.X - lx / 4, cz } } else { { cx, room.min.Z + lz / 4 }, { cx, room.max.Z - lz / 4 } }
		end
		for _, s in spots do
			local lamp
			if room.kind == "garage" then
				lamp = part(decor, "Tube", Vector3.new(4, 0.3, 0.6), at(s[1], ceiling - 0.15, s[2]), rgb(236, 244, 255), Enum.Material.Neon)
			else
				lamp = cylinder(part(decor, "Lamp", Vector3.new(0.3, 2.6, 2.6), at(s[1], ceiling - 0.15, s[2]) * CFrame.Angles(0, 0, math.pi / 2), LAMP, Enum.Material.Neon))
			end
			lamp.CastShadow = false
			local light = Instance.new("PointLight")
			light.Brightness = T.Light.Brightness
			light.Range = T.Light.Range
			light.Color = if room.kind == "garage" then rgb(226, 236, 255) else color(T.Light.Color)
			light.Shadows = false
			light.Parent = lamp
		end
	end

	-- the fixtures
	for _, f in plan.fixtures do
		local look = LOOKS[f.kind]
		if look then
			look(decor, origin * f.at, f.size, roll)
		end
	end

	-- the pieces, anchored at their spots
	local pieces: { [number]: Model } = {}
	for _, spot in plan.spots do
		local piece = FurnitureLooks.build(spot.item, spot.variant)
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
