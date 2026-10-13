--!strict
-- 7.0 prototype, the moving (design/rework/NAVRH.md): builds a house's inside (a shared/HouseLayout.luau plan) far
-- off the map, where a moving crew walks in through a fade: the floors, the walls with their doorways (wallpaper by
-- room, baseboards, door frames), the ceiling and its lights, the windows' dim daylight, the kitchen's counters, the
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

-- The rooms' looks by kind: the wallpapers (one picked per house), the floors.
local WALLPAPER: { [string]: { Color3 } } = {
	hall = { rgb(232, 220, 196), rgb(222, 212, 194), rgb(238, 228, 208) },
	living = { rgb(196, 212, 180), rgb(236, 218, 176), rgb(214, 196, 178), rgb(188, 204, 214) },
	kitchen = { rgb(240, 232, 190), rgb(204, 228, 212), rgb(246, 236, 220) },
	bedroom = { rgb(178, 196, 220), rgb(222, 198, 206), rgb(206, 214, 190) },
	kids = { rgb(250, 214, 170), rgb(190, 222, 240), rgb(214, 236, 190), rgb(236, 206, 236) },
	bath = { rgb(206, 232, 234), rgb(232, 236, 240) },
	garage = { rgb(150, 152, 150), rgb(160, 150, 140) },
}
type Floor = { color: Color3, material: Enum.Material }
local FLOORS: { [string]: { Floor } } = {
	hall = { { color = rgb(164, 120, 80), material = Enum.Material.WoodPlanks }, { color = rgb(150, 104, 66), material = Enum.Material.WoodPlanks } },
	living = { { color = rgb(176, 132, 90), material = Enum.Material.WoodPlanks }, { color = rgb(140, 96, 62), material = Enum.Material.WoodPlanks } },
	kitchen = { { color = rgb(226, 220, 204), material = Enum.Material.CeramicTiles }, { color = rgb(200, 90, 70), material = Enum.Material.CeramicTiles } },
	bedroom = { { color = rgb(170, 150, 140), material = Enum.Material.Carpet }, { color = rgb(126, 136, 156), material = Enum.Material.Carpet } },
	kids = { { color = rgb(130, 170, 200), material = Enum.Material.Carpet }, { color = rgb(196, 170, 206), material = Enum.Material.Carpet } },
	bath = { { color = rgb(214, 230, 236), material = Enum.Material.CeramicTiles } },
	garage = { { color = rgb(128, 128, 124), material = Enum.Material.Concrete } },
}
local TRIM = rgb(240, 236, 228)
local CEILING = rgb(242, 240, 234)
local DAYLIGHT = rgb(126, 156, 178) -- the windows' dim glow (Neon)
local RUGS = { rgb(170, 60, 56), rgb(52, 86, 140), rgb(196, 160, 70), rgb(90, 130, 100), rgb(150, 110, 160), rgb(220, 210, 190) }
local CABINETS = { rgb(236, 234, 226), rgb(150, 180, 160), rgb(170, 128, 86), rgb(110, 140, 170) }

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

local function counterBody(parent: Instance, at: CFrame, s: Vector3, cabinet: Color3)
	part(parent, "Cabinet", Vector3.new(s.X, 2.8, s.Z - 0.15), at * CFrame.new(0, 1.4, 0.075), cabinet, SMOOTH, true)
	part(parent, "Worktop", Vector3.new(s.X, 0.2, s.Z), at * CFrame.new(0, 2.9, 0), rgb(84, 86, 90), Enum.Material.Marble, true)
	part(parent, "Handle", Vector3.new(s.X - 0.8, 0.08, 0.06), at * CFrame.new(0, 2.4, -s.Z / 2 + 0.05), rgb(186, 190, 196), Enum.Material.Metal)
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
	part(parent, "WallCabinet", s, at * CFrame.new(0, s.Y / 2, 0), cabinetColor, SMOOTH, true)
	part(parent, "Handle", Vector3.new(s.X - 0.8, 0.08, 0.06), at * CFrame.new(0, 0.35, -s.Z / 2 - 0.03), rgb(186, 190, 196), Enum.Material.Metal)
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

-- the flat things: rugs (a border and a field), the round one, the runner, mats, the oil stain
local function rug(parent: Instance, at: CFrame, s: Vector3, roll: (number) -> number, round: boolean)
	local a, b = RUGS[roll(#RUGS)], RUGS[roll(#RUGS)]
	if round then
		local d = math.min(s.X, s.Z)
		cylinder(part(parent, "Rug", Vector3.new(0.06, d, d), at * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.pi / 2), a, Enum.Material.Fabric))
		cylinder(part(parent, "RugField", Vector3.new(0.07, d - 1, d - 1), at * CFrame.new(0, 0.035, 0) * CFrame.Angles(0, 0, math.pi / 2), b, Enum.Material.Fabric))
		return
	end
	part(parent, "Rug", Vector3.new(s.X, 0.06, s.Z), at * CFrame.new(0, 0.03, 0), a, Enum.Material.Fabric)
	part(parent, "RugField", Vector3.new(math.max(0.4, s.X - 0.9), 0.07, math.max(0.4, s.Z - 0.9)), at * CFrame.new(0, 0.035, 0), b, Enum.Material.Fabric)
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
	local wallpaper: { [string]: Color3 } = {}
	local floors: { [string]: Floor } = {}
	for kind, list in WALLPAPER do
		wallpaper[kind] = list[roll(#list)]
	end
	for kind, list in FLOORS do
		floors[kind] = list[roll(#list)]
	end
	local kindOf: { [string]: string } = {}
	for _, room in plan.rooms do
		kindOf[room.id] = room.kind
	end
	local half = plan.wall / 2
	local ceiling = plan.ceiling

	-- the safety ground, the floors (each room's to its walls' middles), the ceiling
	local mid = (plan.min + plan.max) / 2
	local g = T.Ground
	local ground = part(shell, "Ground", Vector3.new(plan.size.X + 2 * g.Margin, g.Depth, plan.size.Z + 2 * g.Margin), at(mid.X, -0.2 - g.Depth / 2, mid.Z), rgb(96, 92, 86), Enum.Material.Concrete, true)
	ground.CastShadow = false
	for _, room in plan.rooms do
		local floor = floors[room.kind] or floors.hall
		local w, d = room.max.X - room.min.X + plan.wall, room.max.Z - room.min.Z + plan.wall
		part(shell, "Floor", Vector3.new(w, 0.2, d), at((room.min.X + room.max.X) / 2, -0.1, (room.min.Z + room.max.Z) / 2), floor.color, floor.material, true)
	end
	part(shell, "Ceiling", Vector3.new(plan.size.X, 1, plan.size.Z), at(mid.X, ceiling + 0.5, mid.Z), CEILING, SMOOTH, true)

	-- the walls: a slab per room side in its wallpaper, a baseboard along its foot, the bathroom tiled to the sill
	for _, face in plan.faces do
		local kind = kindOf[face.room] or "hall"
		local size = face.max - face.min
		local centre = (face.min + face.max) / 2
		local material = if kind == "garage" then Enum.Material.Concrete else Enum.Material.Plaster
		part(shell, if face.header then "Header" else "Wall", size, at(centre.X, centre.Y, centre.Z), wallpaper[kind] or TRIM, material, true)
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
		if along <= 1.6 or kind == "garage" then
			continue -- (nothing on a stub beside a doorway)
		elseif kind == "bath" then
			strip("Tiles", 4.5, 0.06, rgb(236, 242, 244), Enum.Material.CeramicTiles)
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
		local frameColor = if door.front then rgb(110, 76, 50) else TRIM
		local depth = plan.wall + 0.3
		local function piece(name: string, dx: number, y: number, sAlong: number, sY: number)
			local size = if door.axis == "X" then Vector3.new(sAlong, sY, depth) else Vector3.new(depth, sY, sAlong)
			local x = if door.axis == "X" then door.at.X + dx else door.at.X
			local z = if door.axis == "X" then door.at.Z else door.at.Z + dx
			part(decor, name, size, at(x, y, z), frameColor, SMOOTH)
		end
		for _, s in { -1, 1 } do
			piece("Jamb", s * (w + 0.2), plan.doorHeight / 2, 0.4, plan.doorHeight)
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
		part(shell, "Porch", Vector3.new(2 * w, 0.2, porch), at(x, -0.1, z - porch / 2), rgb(150, 146, 140), Enum.Material.Concrete, true)
		for _, s in { -1, 1 } do
			part(shell, "PorchWall", Vector3.new(0.5, ceiling, porch), at(x + s * (w + 0.25), ceiling / 2, z - porch / 2), rgb(214, 220, 214), Enum.Material.WoodPlanks, true)
		end
		part(shell, "PorchRoof", Vector3.new(2 * w + 1, 0.5, porch), at(x, plan.doorHeight + 1.25, z - porch / 2), rgb(214, 220, 214), Enum.Material.WoodPlanks, true)
		local glow = part(shell, "Daylight", Vector3.new(2 * w, plan.doorHeight + 1.5, 0.4), at(x, (plan.doorHeight + 1.5) / 2, z - porch - 0.2), rgb(236, 240, 228), Enum.Material.Neon, true)
		glow.CastShadow = false
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Back -- (+Z: into the house)
		light.Brightness = T.DoorLight.Brightness
		light.Range = T.DoorLight.Range
		light.Angle = 70
		light.Color = color(T.DoorLight.Color)
		light.Parent = glow
		local mat = part(decor, "WelcomeMat", Vector3.new(4, 0.06, 2.2), at(x, 0.03, z - 1.6), rgb(150, 110, 70), Enum.Material.Fabric)
		sign(mat, "WELCOME", Enum.NormalId.Top, rgb(60, 40, 24))
		local exit = part(decor, "ExitSign", Vector3.new(2.6, 0.9, 0.3), at(x, plan.doorHeight + 1.05, front.at.Z + half + 0.15), rgb(250, 250, 248), SMOOTH)
		sign(exit, "EXIT", Enum.NormalId.Back, rgb(255, 255, 255), rgb(30, 160, 80))
	end

	-- the windows: a frame, the glowing pane and a sill (a small one no sill); curtains in the living room
	for _, w in plan.windows do
		local kind = kindOf[w.room] or "hall"
		local frame = origin * CFrame.lookAt(w.at, w.at + w.normal) -- -Z into the room
		local small = w.width <= 3
		part(decor, "WindowFrame", Vector3.new(w.width + 0.5, w.height + 0.5, 0.16), frame * CFrame.new(0, 0, -0.08), TRIM, SMOOTH)
		local pane = part(decor, "Window", Vector3.new(w.width, w.height, 0.06), frame * CFrame.new(0, 0, -0.19), if kind == "bath" then rgb(170, 190, 200) else DAYLIGHT, Enum.Material.Neon)
		pane:SetAttribute("InteriorWindow", true)
		if not small then
			part(decor, "Sill", Vector3.new(w.width + 1, 0.2, 0.6), frame * CFrame.new(0, -w.height / 2 - 0.1, -0.3), TRIM, SMOOTH)
		end
		if kind == "living" then
			local curtain = ({ rgb(176, 64, 60), rgb(90, 120, 150), rgb(214, 190, 130), rgb(120, 140, 100) })[roll(4)]
			for _, s in { -1, 1 } do
				part(decor, "Curtain", Vector3.new(1.0, w.height + 1.8, 0.2), frame * CFrame.new(s * (w.width / 2 + 0.6), 0.4, -0.35), curtain, Enum.Material.Fabric)
			end
		end
	end

	-- the ceiling lights: one in the middle of every room, two in a long one; a tube in the garage
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
				lamp = cylinder(part(decor, "Lamp", Vector3.new(0.3, 2.6, 2.6), at(s[1], ceiling - 0.15, s[2]) * CFrame.Angles(0, 0, math.pi / 2), rgb(255, 238, 210), Enum.Material.Neon))
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
