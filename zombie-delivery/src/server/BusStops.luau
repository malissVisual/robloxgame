--!strict
-- 5.5, the city buses' stops (shared/BusLines.luau): a shelter at every stop's kerb, built once by server/World.luau
-- (its build list: "bus stops"). Native parts, at most 25 a stop (23): a concrete pad, a glass back and sides on four
-- posts under a roof with a fascia in the line's colour and a lamp that glows at night, a bench, the arrivals board
-- on the back wall (a SurfaceGui whose "Arrivals" label every client fills from the timetable: client/BusRide.luau),
-- a pole sign at the front end facing along the street (BUS, the lines' coloured number chips, the stop's name) and
-- the road's yellow kerb line and BUS lettering where the bus stands.
--
-- Where: the shelter stands on the sidewalk from the curb to 3 studs in (the people's walk line, 4.5 in, stays clear:
-- shared/TrafficLanes.luau), centred on the bus's front-right door; nothing of it collides above the pad but the
-- posts, the glass, the bench and the pole. Each shelter is a Model tagged "BusStop" with StopId and StopName.
--
-- 6.3, the bus map at every stop: a MapBoard panel on two posts past the shelter's back end (in line with its back
-- glass, facing the road, 3.4 × 4.6), its face "ZDC TRANSIT · EXPRESS · BUS MAP" from afar; the client of a player near
-- the stop draws the lines on it with YOU ARE HERE (client/BusMapBoard.luau). 4 parts more (23 a stop).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BusLines = require(Shared.BusLines)
local Map = require(Shared.Map)
local DayNight = require(script.Parent.DayNight)

local BusStops = {}

BusStops.Tag = "BusStop"

local PAD_TOP = Map.WalkTop + 0.1
local METAL = Color3.fromRGB(46, 48, 52)
local GLASS = Color3.fromRGB(170, 200, 214)
local CONCRETE = Color3.fromRGB(150, 148, 142)
local WOOD = Color3.fromRGB(122, 86, 56)
local PAINT = Color3.fromRGB(226, 186, 40)
local LAMP_LIT = Color3.fromRGB(255, 232, 190)
local LAMP_DIM = Color3.fromRGB(120, 120, 116)

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

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function surface(p: BasePart, face: Enum.NormalId, pps: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0
	gui.Parent = p
	return gui
end

local function text(parent: Instance, value: string, size: UDim2, position: UDim2, color: Color3, props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = value
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	if props then
		for key, v in props do
			(label :: any)[key] = v
		end
	end
	label.Parent = parent
	return label
end

-- The pole sign's face: BUS, a chip per line, the stop's name.
local function signFace(board: BasePart, face: Enum.NormalId, stop: BusLines.Stop)
	local gui = surface(board, face, 60)
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
	back.BorderSizePixel = 0
	back.Parent = gui
	text(back, "BUS", UDim2.new(1, -16, 0.3, 0), UDim2.fromOffset(8, 4), Color3.new(1, 1, 1))
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -16, 0.26, 0)
	row.Position = UDim2.new(0, 8, 0.33, 0)
	row.BackgroundTransparency = 1
	row.Parent = back
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	for _, id in stop.lines do
		local line = BusLines.line(id)
		if line then
			local chip = text(row, tostring(id), UDim2.new(0.28, 0, 1, 0), UDim2.new(), Color3.new(1, 1, 1), {
				BackgroundTransparency = 0,
				BackgroundColor3 = rgb(line.color),
				BorderSizePixel = 0,
			})
			Instance.new("UIAspectRatioConstraint").Parent = chip
		end
	end
	text(back, string.upper(stop.name), UDim2.new(1, -16, 0.34, 0), UDim2.new(0, 8, 0.62, 0), Color3.fromRGB(230, 230, 222), {
		TextWrapped = true,
		Font = Enum.Font.GothamMedium,
	})
end

local function shelter(parent: Instance, stop: BusLines.Stop)
	local model = Instance.new("Model")
	model.Name = `Bus Stop · {stop.name}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- (the arrivals board streams in with its shelter)
	model:SetAttribute("StopId", stop.id)
	model:SetAttribute("StopName", stop.name)
	-- The frame: on the curb by the door, -Z into the sidewalk; `along` toward the bus's front, `depth` in from the curb.
	local curb = Vector3.new(stop.kx - stop.nx * 1.5, 0, stop.kz - stop.nz * 1.5)
	local frame = CFrame.lookAt(curb, curb + Vector3.new(stop.nx, 0, stop.nz))
	local function at(along: number, depth: number, y: number): CFrame
		return frame * CFrame.new(-along, y, -depth)
	end
	local first = BusLines.line(stop.lines[1])
	local lineColor = if first then rgb(first.color) else PAINT

	part(model, "Pad", Vector3.new(11, PAD_TOP, 3.4), at(0, 1.7, PAD_TOP / 2), CONCRETE, Enum.Material.Concrete)
	local height = 7.2
	for _, along in { -4.7, 4.7 } do
		for _, depth in { 0.45, 2.75 } do
			part(model, "Post", Vector3.new(0.3, height, 0.3), at(along, depth, PAD_TOP + height / 2), METAL, Enum.Material.Metal)
		end
		local side = part(model, "Glass", Vector3.new(0.15, 5.2, 2.0), at(along, 1.6, PAD_TOP + 0.5 + 2.6), GLASS, Enum.Material.Glass)
		side.Transparency = 0.55
	end
	local back = part(model, "Glass", Vector3.new(9.1, 5.2, 0.15), at(0, 2.8, PAD_TOP + 0.5 + 2.6), GLASS, Enum.Material.Glass)
	back.Transparency = 0.55
	part(model, "Roof", Vector3.new(10.6, 0.35, 3.9), at(0, 1.65, PAD_TOP + height + 0.17), METAL, Enum.Material.Metal)
	deco(part(model, "Fascia", Vector3.new(10.6, 0.55, 0.15), at(0, -0.35, PAD_TOP + height + 0.1), lineColor, Enum.Material.SmoothPlastic))
	local lamp = deco(part(model, "Lamp", Vector3.new(8, 0.12, 0.6), at(0, 1.6, PAD_TOP + height - 0.08), LAMP_DIM, Enum.Material.SmoothPlastic))
	DayNight.nightLight(lamp, LAMP_LIT, LAMP_DIM, "SmoothPlastic")
	-- The bench against the back.
	part(model, "Bench", Vector3.new(6, 0.3, 1.0), at(0, 2.2, PAD_TOP + 1.6), WOOD, Enum.Material.Wood)
	for _, along in { -2.6, 2.6 } do
		part(model, "BenchLeg", Vector3.new(0.3, 1.45, 0.8), at(along, 2.2, PAD_TOP + 0.73), METAL, Enum.Material.Metal)
	end
	-- The arrivals board on the back wall, facing the road (client/BusRide.luau writes it).
	local board = deco(part(model, "ArrivalsBoard", Vector3.new(4.4, 1.9, 0.1), at(0, 2.68, PAD_TOP + 5.0), Color3.fromRGB(18, 20, 24), Enum.Material.SmoothPlastic))
	local gui = surface(board, Enum.NormalId.Back, 50)
	gui.Name = "ArrivalsGui"
	text(gui, string.upper(stop.name), UDim2.new(1, -12, 0.26, 0), UDim2.fromOffset(6, 3), Color3.fromRGB(230, 230, 222), {
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	text(gui, "", UDim2.new(1, -12, 0.66, 0), UDim2.new(0, 6, 0.3, 0), Color3.fromRGB(255, 196, 70), {
		Name = "Arrivals",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Code,
	})
	-- The pole sign at the front end, its two faces along the street.
	part(model, "SignPole", Vector3.new(0.35, 10, 0.35), at(6.2, 0.7, PAD_TOP + 5), METAL, Enum.Material.Metal)
	local sign = deco(part(model, "Sign", Vector3.new(2.4, 2.8, 0.15), at(6.2, 0.7, PAD_TOP + 8.6) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(22, 24, 28), Enum.Material.Metal))
	signFace(sign, Enum.NormalId.Front, stop)
	signFace(sign, Enum.NormalId.Back, stop)
	-- 6.3: the map board past the back end (the bus's side of the shelter; the pole sign is at the front end), its face
	-- toward the road like the arrivals board's. Its plain face; a near client covers it with the map.
	local mapAlong, mapDepth = -8.4, 2.7
	for _, along in { mapAlong - 1.85, mapAlong + 1.85 } do
		part(model, "MapPost", Vector3.new(0.3, 6.4, 0.3), at(along, mapDepth, PAD_TOP + 3.1), METAL, Enum.Material.Metal)
	end
	deco(part(model, "MapFrame", Vector3.new(3.7, 0.3, 0.3), at(mapAlong, mapDepth, PAD_TOP + 6.3), lineColor, Enum.Material.SmoothPlastic))
	local mapBoard = deco(part(model, "MapBoard", Vector3.new(3.4, 4.6, 0.12), at(mapAlong, mapDepth, PAD_TOP + 3.85), Color3.fromRGB(18, 20, 24), Enum.Material.SmoothPlastic))
	local plain = surface(mapBoard, Enum.NormalId.Back, 40)
	plain.Name = "MapBoardGui"
	text(plain, "ZDC TRANSIT · EXPRESS", UDim2.new(1, -12, 0.08, 0), UDim2.fromOffset(6, 6), Color3.fromRGB(230, 230, 222))
	text(plain, "BUS MAP", UDim2.new(1, -24, 0.12, 0), UDim2.new(0, 12, 0.44, 0), Color3.fromRGB(255, 196, 70))
	-- On the road: the yellow kerb line where the bus stands, and BUS.
	local stand = BusLines.DoorAhead -- (the bus's middle is this far behind the door)
	deco(part(model, "BusBay", Vector3.new(26, 0.05, 0.45), at(-stand, -0.4, Map.RoadTop + 0.03), PAINT))
	local letters = deco(part(model, "BusLetters", Vector3.new(7, 0.05, 2.6), at(-stand, -3.8, Map.RoadTop + 0.03), PAINT))
	letters.Transparency = 1
	local paint = surface(letters, Enum.NormalId.Top, 40)
	text(paint, "BUS", UDim2.fromScale(1, 1), UDim2.new(), PAINT)
	CollectionService:AddTag(model, BusStops.Tag)
	model.Parent = parent
end

-- Every stop's shelter (server/World.luau's build list).
function BusStops.build(world: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "BusStops"
	folder.Parent = world
	for _, stop in BusLines.allStops() do
		local ok, err = pcall(function()
			shelter(folder, stop)
		end)
		if not ok then
			warn(`[BusStops] {stop.name}: {err}`)
		end
	end
end

return BusStops
