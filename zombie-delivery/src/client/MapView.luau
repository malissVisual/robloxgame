--!strict
-- The minimap (always on: bottom left on a computer, top left on a touch screen) and the big map (M / MAP).
-- Both are drawn once from shared/Map.luau: land, winter, water, the mountain, blocks, roads (highways and bridges
-- stand out) and an icon for every landmark you know (shops, employers, far places; 3.7). Live markers: you (an arrow), other
-- players, bandit cars (red !), supply crates (?), the delivery target (a red ■), your GPS point (◆) and the car a chauffeur
-- is bringing you (🚗, MapView.setCar from client/Hud.luau; the three stick to the minimap's edge when far).
-- Like GTA, the way there is drawn along the roads (shared/Roads.luau): red to the job's target, white to the
-- GPS point. A route is worked out again when the target changes or you leave it by more than ROUTE_OFF studs, and
-- the part behind you is cut off as you drive. The minimap turns with the camera (north marker on its edge) and
-- zooms out a little at speed; it moves every frame and redraws its tiles and routes MINI_HZ times a second.
-- The big map lists every landmark with what you can do there; click one to set the GPS.
-- 3.7, the map you discover (client/Discovery.luau, shared/Explore.luau): both maps are fog (charcoal, the roads hidden
-- under it) except the cells you have uncovered, and they show only the landmarks you know (on the maps and in the
-- list). The fog is drawn as one frame per run of fogged cells in a grid row (a soft rounded frame under it for the
-- edge), pooled per row; when cells are uncovered only their rows are drawn again. The job's star and route, the GPS,
-- you, your car on its way and the live markers stay over the fog: you must find your delivery.
-- 5.6: a small 🛴 marker at every ZDC RIDE rental dock (shared/RentalDocks.luau), under the fog.
-- 6.3, the bus map: on the big map the express lines (shared/BusLines.luau mapLines: a few corners a loop) in their
-- colours and their stops as white-ringed dots, under the fog like the docks; the BUS chip in the header hides them or
-- shows them again (MapView.busShown, for the session).
-- 3.8, the contract UI (design/ui-contract/): the minimap is compact and monochrome in a thin square line; inside its
-- top edge the way you face and where you are ("N · HARBOR") and EXPAND [M], a quiet text action that opens the big
-- map; under it the next turn of the route ("↰ Left onto Maple St · 120 m", the job's route, else the GPS's; with
-- neither the address you are at). The map itself is charcoal and greys (land, blocks, water, the streets lighter, the
-- highways lightest), the job's route and its star in the contract red, the GPS's route and diamond in white, you a
-- white arrow. The big map is a charcoal window with the same map.
-- 5.8 (the courier phone's look): the big map's frame wears the window header: the ZDC mark, the map glyph and MAP
-- (Ui.heading), the legend in small type after it, a thin line under it and the square ✕.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Map = require(Shared.Map)
local Roads = require(Shared.Roads)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Discovery = require(script.Parent.Discovery)

local MapView = {}

local player = Players.LocalPlayer
local B = Map.Bounds
local WORLD_W = B.x1 - B.x0
local WORLD_H = B.z1 - B.z0

local MINI_W, MINI_H = 200, 150 -- the map's window (its thin square line is drawn on its edge)
local TURN_H = 18 -- the turn line under it
local MINI_SCALE = 0.6 -- px per stud: the minimap shows about 370 studs across
local MINI_HZ = 20
local TURN_HZ = 4 -- the header and the turn line, times a second
local EDGE_X, EDGE_Y = MINI_W / 2 - 13, MINI_H / 2 - 13 -- markers pinned to the edge stay this far from the centre
local ZOOM_OUT = 0.72 -- the minimap's zoom at full speed
local BIG_SCALE = 0.16 -- the big map is drawn at this scale and then fitted to the screen
local LIST_W = 320
local ROUTE_OFF = 40 -- studs off the route before it is worked out again
local ROUTE_GAP = 0.5 -- seconds between two routes to the same target

-- 3.8: a monochrome map (design/ui-contract/): charcoal land, grey blocks and water, lighter streets on a dark edge,
-- the highways lightest; the job's route and star in the contract red, the GPS in white, both on a charcoal edge.
local K = Theme.Contract
local P = { -- (the names the drawing below reads)
	ink = K.text, -- you, the captions, the markers' text
	ink2 = K.secondary,
	paper = K.charcoal, -- the strokes and the shading under the white
	line = K.line,
	danger = K.red,
}
local C = {
	land = Color3.fromRGB(40, 44, 50),
	snow = Color3.fromRGB(60, 64, 70),
	water = Color3.fromRGB(26, 30, 37),
	shore = Color3.fromRGB(78, 84, 92),
	ice = Color3.fromRGB(52, 58, 66),
	yard = Color3.fromRGB(48, 52, 58),
	special = Color3.fromRGB(66, 70, 76),
	roadEdge = Color3.fromRGB(22, 25, 30),
	road = Color3.fromRGB(132, 138, 146),
	highway = Color3.fromRGB(176, 181, 188),
	bridge = Color3.fromRGB(112, 116, 122),
	iceRoad = Color3.fromRGB(150, 162, 174),
	safe = K.good,
	job = K.red, -- the job's route and star: the contract red (the Hud's 3D guide too)
	gps = K.text, -- the GPS: white (the Hud's GPS guide too)
	car = K.secondary, -- the car on its way
	routeEdge = K.charcoal,
	fog = Color3.fromRGB(12, 14, 17), -- 3.7: what you have not seen yet (near black under the charcoal map)
}
local FOG_CORE = 0.04 -- the fog's transparency (the roads under it all but hidden)
local FOG_SOFT = 0.55 -- its soft edge
local BLOCK_COLORS = {
	downtown = Color3.fromRGB(58, 62, 69),
	harbor = Color3.fromRGB(56, 59, 64),
	suburbs = Color3.fromRGB(54, 59, 60),
}
-- The landmarks' kinds: quiet tints for their discs' line and the list (the icons themselves are white).
local KIND_COLORS = {
	shop = Color3.fromRGB(150, 196, 146),
	employer = Color3.fromRGB(226, 184, 120),
	place = Color3.fromRGB(184, 170, 214),
	venue = Color3.fromRGB(214, 160, 150), -- 5.3, the storefronts (Map.Venues)
}

-- A route line on one canvas: two pools of rotated frames (a dark edge under the colour), drawn from `step` on.
type Line = { edges: { any }, fills: { any }, parent: any, color: Color3, width: number, full: number, cut: number }
-- 3.7: the fog on one canvas: per grid row a pool of frames (a core and its soft edge for every run of fogged cells).
type Fog = { layer: any, scale: number, feather: number, rows: { [number]: { any } } }
type Canvas = { content: any, scale: number, markers: any, job: Line, gps: Line, fog: Fog, bus: any? }

-- A route to a goal (the job's target or the GPS point).
type Route = {
	goal: Vector3?,
	points: { Roads.Point }?,
	computedAt: number,
	dirty: boolean,
	step: number, -- the step of the route you are on (the steps before it are behind you)
	cutX: number, -- where you are on that step
	cutZ: number,
	full: number, -- bumped when the steps change (redraw every frame of the line)
	cut: number, -- bumped when only the cut point moved (redraw the first frame)
}

local function newRoute(): Route
	return { goal = nil, points = nil, computedAt = -math.huge, dirty = false, step = 1, cutX = 0, cutZ = 0, full = 0, cut = 0 }
end
local jobRoute = newRoute()
local gpsRoute = newRoute()

-- Set by Hud: the GPS was set (landmark) or cleared (nil).
MapView.onWaypoint = function(_landmark: Map.Landmark?) end

local target: Vector3? = nil
local waypoint: Vector3? = nil
local calledCar: Model? = nil

-- The car on its way to you (the CarCall remote), nil = none: a marker on both maps until it is cleared.
function MapView.setCar(car: Model?)
	calledCar = car
end

local function calledCarPosition(): Vector3?
	local car = calledCar
	if not car or not car.Parent then
		return nil
	end
	return car:GetPivot().Position
end

-- A new goal for a route (Hud repeats the same target with every job update: that is not a change).
local function setGoal(route: Route, goal: Vector3?)
	local old = route.goal
	if goal and old and (Vector3.new(goal.X, 0, goal.Z) - Vector3.new(old.X, 0, old.Z)).Magnitude < 1 then
		return
	end
	route.goal = goal
	route.points = nil
	route.dirty = goal ~= nil
	route.full += 1
end

function MapView.setTarget(position: Vector3?)
	target = position
	setGoal(jobRoute, position)
end

function MapView.setWaypoint(position: Vector3?)
	waypoint = position
	setGoal(gpsRoute, position)
end

-- ── Drawing ────────────────────────────────────────────────────────────────

local function point(x: number, z: number, scale: number): UDim2
	return UDim2.fromOffset((x - B.x0) * scale, (z - B.z0) * scale)
end

local function rect(parent: any, x0: number, z0: number, x1: number, z1: number, scale: number, color: Color3, z: number): any
	return Ui.make("Frame", {
		Position = point(x0, z0, scale),
		Size = UDim2.fromOffset((x1 - x0) * scale, (z1 - z0) * scale),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
end

local function rounded(frame: any, radius: number)
	Ui.make("UICorner", { CornerRadius = UDim.new(0, radius) }, frame)
end

-- A straight band from (ax, az) to (bx, bz), `width` pixels thick, its ends extended by `extend` pixels.
local function band(frame: any, ax: number, az: number, bx: number, bz: number, scale: number, width: number, extend: number)
	local dx, dz = bx - ax, bz - az
	frame.Position = point((ax + bx) / 2, (az + bz) / 2, scale)
	frame.Size = UDim2.fromOffset(math.sqrt(dx * dx + dz * dz) * scale + extend, width)
	frame.Rotation = math.deg(math.atan2(dz, dx))
end

local function caption(parent: any, text: string, x: number, z: number, scale: number, size: number, color: Color3)
	Ui.make("TextLabel", {
		Size = UDim2.fromOffset(200, size + 4),
		Position = point(x, z, scale),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		Font = Theme.HeadingFont,
		TextColor3 = color,
		TextStrokeColor3 = P.paper,
		TextStrokeTransparency = 0.35,
		ZIndex = 7, -- (under the fog, 8)
	}, parent)
end

-- A landmark's marker: a disc in its kind's colour with the landmark's icon (shared/Icons.luau) on it, or its emoji
-- while the icon's id is empty.
local function landmarkIcon(parent: any, landmark: Map.Landmark, scale: number, size: number, clickable: boolean): any
	local art = Icons.landmark(landmark.id)
	local icon = Ui.make(if clickable then "TextButton" else "TextLabel", {
		Size = UDim2.fromOffset(size, size),
		Position = point(landmark.x, landmark.z, scale),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		Text = if Icons.get(art) then "" else landmark.icon,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = P.ink,
		ZIndex = 9,
	}, parent)
	Ui.corner(icon, size)
	Ui.stroke(icon, KIND_COLORS[landmark.kind] or P.ink2, 1)
	if Icons.get(art) then
		Ui.icon(icon, art, landmark.icon, UDim2.fromScale(0.72, 0.72), {
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 9,
		})
	end
	return icon
end

local function newLine(parent: any, color: Color3, width: number): Line
	return { edges = {}, fills = {}, parent = parent, color = color, width = width, full = -1, cut = -1 }
end

local function lineFrame(line: Line, list: { any }, index: number, edge: boolean): any
	local frame = list[index]
	if not frame then
		frame = Ui.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = if edge then C.routeEdge else line.color,
			BackgroundTransparency = if edge then 0.25 else 0,
			BorderSizePixel = 0,
			ZIndex = if edge then 1 else 2,
		}, line.parent)
		Ui.make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame) -- round ends: the steps join smoothly
		list[index] = frame
	end
	frame.Visible = true
	return frame
end

local function hideLine(line: Line, from: number)
	for n = from, #line.fills do
		line.fills[n].Visible = false
		line.edges[n].Visible = false
	end
end

-- Draws the route on one canvas (only what changed since the last time).
local function drawLine(line: Line, route: Route, scale: number)
	local points = route.points
	if not points then
		if line.full ~= route.full then
			hideLine(line, 1)
			line.full, line.cut = route.full, route.cut
		end
		return
	end
	local onlyFirst = line.full == route.full
	if onlyFirst and line.cut == route.cut then
		return
	end
	local w = line.width
	local n = 0
	for k = route.step, #points - 1 do
		local a, b = points[k], points[k + 1]
		local ax, az = if k == route.step then route.cutX else a.x, if k == route.step then route.cutZ else a.z
		if k > route.step and onlyFirst then
			break
		end
		n += 1
		band(lineFrame(line, line.edges, n, true), ax, az, b.x, b.z, scale, w + 3, w + 3)
		band(lineFrame(line, line.fills, n, false), ax, az, b.x, b.z, scale, w, w)
	end
	if not onlyFirst then
		hideLine(line, n + 1)
	end
	line.full, line.cut = route.full, route.cut
end

-- 6.3: the bus lines on the big map are shown (the BUS chip; the session remembers it).
MapView.busShown = true

-- 6.3, the bus lines' layer on a canvas: each loop's few corners joined by bands 3 px wide in its colour, every stop
-- once as a dot in a white ring (ZIndex 7: under the fog, 8, like the docks).
local function busLayer(content: any, scale: number): any
	local layer = Ui.make("Frame", { Name = "BusLines", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7, Visible = MapView.busShown }, content)
	local lines = require(Shared.BusLines).mapLines(32)
	for _, line in lines do
		local color = Color3.fromRGB(line.color[1], line.color[2], line.color[3])
		local count = #line.points
		for k = 1, count do
			local a, b = line.points[k], line.points[k % count + 1]
			local frame = Ui.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 7 }, layer)
			Ui.make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
			band(frame, a.x, a.z, b.x, b.z, scale, 3, 3)
		end
	end
	local drawn: { [number]: boolean } = {}
	for _, line in lines do
		for _, stop in line.stops do
			if not drawn[stop.id] then
				drawn[stop.id] = true
				local spot = Ui.make("Frame", {
					Name = "BusStop",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = point(stop.x, stop.z, scale),
					Size = UDim2.fromOffset(7, 7),
					BackgroundColor3 = Color3.fromRGB(line.color[1], line.color[2], line.color[3]),
					BorderSizePixel = 0,
					ZIndex = 7,
				}, layer)
				Ui.corner(spot, 7)
				Ui.stroke(spot, P.ink, 1.5)
			end
		end
	end
	return layer
end

-- The whole world into a frame at `scale` pixels per stud.
local function draw(parent: any, scale: number, big: boolean): Canvas
	local content = Ui.make("Frame", {
		Size = UDim2.fromOffset(WORLD_W * scale, WORLD_H * scale),
		BackgroundColor3 = C.land,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, parent)
	-- Ground, water, winter.
	rect(content, B.x0, B.z0, Map.River.x0, Map.WinterZ, scale, C.snow, 2)
	local river = Map.River
	rect(content, river.x0, B.z0, river.x1, B.z1, scale, C.water, 2)
	rect(content, Map.Sea.x0, B.z0, B.x1, B.z1, scale, C.water, 2)
	local shore = math.max(1, 5 * scale)
	rect(content, river.x0, B.z0, river.x0 + shore / scale, B.z1, scale, C.shore, 2)
	rect(content, river.x1 - shore / scale, B.z0, river.x1, B.z1, scale, C.shore, 2)
	rect(content, Map.Sea.x0, B.z0, Map.Sea.x0 + shore / scale, B.z1, scale, C.shore, 2)
	local lake = Map.Lake
	rounded(rect(content, lake.x0, lake.z0, lake.x1, lake.z1, scale, C.ice, 3), math.floor(40 * scale))
	local m = Map.Mountain
	-- (white: the gradient gives the colour, lit from the north-west)
	local hill = rect(content, m.x - m.radius, m.z - m.radius, m.x + m.radius, m.z + m.radius, scale, Color3.new(1, 1, 1), 3)
	Ui.make("UICorner", { CornerRadius = UDim.new(1, 0) }, hill)
	Ui.make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(84, 88, 94), Color3.fromRGB(48, 52, 58)),
		Rotation = 45,
	}, hill)
	for _, yard in Map.Yards do
		rounded(rect(content, yard.x0, yard.z0, yard.x1, yard.z1, scale, C.yard, 3), math.max(2, math.floor(12 * scale)))
	end
	-- Blocks, lavender, sand or sage on the cream ground; the special ones warmer.
	local half = Map.BlockSize / 2
	local blockRadius = math.max(2, math.floor(8 * scale))
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
				local color = if Map.special(d.id, i, j) then C.special else BLOCK_COLORS[d.style] or BLOCK_COLORS.downtown
				rounded(rect(content, cx - half, cz - half, cx + half, cz + half, scale, color, 3), blockRadius)
			end
		end
	end
	-- Roads: all the plum edges first, then the fills, so the junctions are clean.
	local border = if big then 1.5 else 3
	for pass = 1, 2 do
		for _, s in Map.Segments do
			local width = math.max(2, s.width * scale)
			local color = if pass == 1 then C.roadEdge
				elseif s.kind == "bridge" then C.bridge
				elseif s.kind == "ice" then C.iceRoad
				elseif s.kind == "highway" then C.highway
				else C.road
			local extra = if pass == 1 then border else 0
			local frame = Ui.make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = 3 + pass,
			}, content)
			band(frame, s.ax, s.az, s.bx, s.bz, scale, width + extra, s.width * scale + extra)
		end
	end
	local safeHalf = Config.City.SafeHalf
	local safe = rect(content, -safeHalf, -safeHalf, safeHalf, safeHalf, scale, P.ink, 6)
	safe.BackgroundTransparency = 1
	Ui.make("UIStroke", { Color = C.safe, Thickness = if big then 1.5 else 1, Transparency = 0.4 }, safe)
	if big then
		for _, d in Map.Districts do
			local x0, x1, z0 = Map.districtEdges(d)
			caption(content, d.name:upper(), (x0 + x1) / 2, z0 - 60, scale, 13, P.ink)
		end
		caption(content, "TUNNEL", m.x + 80, m.z, scale, 11, P.ink2)
		caption(content, "FROZEN LAKE", (lake.x0 + lake.x1) / 2, lake.z0 - 40, scale, 11, P.ink2)
		caption(content, "WINTER", 0, Map.WinterZ - 120, scale, 14, P.ink2)
		caption(content, "SAFE ZONE", 0, safeHalf + 40, scale, 11, C.safe)
	end
	-- 5.6, ZDC RIDE: a small marker at every rental dock (shared/RentalDocks.luau), under the fog: found as you uncover
	-- the map. The scooter's icon when Icons has one, else its emoji.
	local rideArt = Icons.bike(Config.Rental.CarId)
	for _, dock in require(Shared.RentalDocks).docks() do
		local size = if big then 14 else 12
		local marker = Ui.make("TextLabel", {
			Name = "RentalDock",
			Size = UDim2.fromOffset(size, size),
			Position = point(dock.x, dock.z, scale),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = K.charcoal,
			Text = if Icons.get(rideArt) then "" else "🛴",
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = P.ink,
			ZIndex = 7,
		}, content)
		Ui.corner(marker, size)
		Ui.stroke(marker, Color3.fromRGB(Config.Rental.Color[1], Config.Rental.Color[2], Config.Rental.Color[3]), 1)
		if Icons.get(rideArt) then
			Ui.icon(marker, rideArt, "🛴", UDim2.fromScale(0.8, 0.8), { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 7 })
		end
	end
	-- 6.3: the bus lines (the big map only: the minimap stays quiet).
	local bus = if big then busLayer(content, scale) else nil
	-- 3.7: the fog over the map (ZIndex 8), the routes and the markers over the fog.
	local fog: Fog = {
		layer = Ui.make("Frame", { Name = "Fog", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8 }, content),
		scale = scale,
		feather = math.max(3, math.floor(Discovery.cellSize * scale * 0.2)),
		rows = {},
	}
	-- The routes (the GPS under the job), then the markers on top.
	local routes = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9 }, content)
	local gpsLayer = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 }, routes)
	local jobLayer = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, routes)
	local width = if big then 4 else 7
	local markers = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10 }, content)
	return {
		content = content,
		scale = scale,
		markers = markers,
		job = newLine(jobLayer, C.job, width),
		gps = newLine(gpsLayer, C.gps, width),
		fog = fog,
		bus = bus,
	}
end

-- ── Fog (3.7) ──────────────────────────────────────────────────────────────

-- The n-th run's frames in a row's pool: its core and its soft edge (made the first time).
local function fogFrames(fog: Fog, list: { any }, n: number): (any, any)
	local core, soft = list[n * 2 - 1], list[n * 2]
	if not core then
		soft = Ui.make("Frame", { BackgroundColor3 = C.fog, BackgroundTransparency = FOG_SOFT, BorderSizePixel = 0, ZIndex = 1 }, fog.layer)
		Ui.make("UICorner", { CornerRadius = UDim.new(0, fog.feather) }, soft)
		core = Ui.make("Frame", { BackgroundColor3 = C.fog, BackgroundTransparency = FOG_CORE, BorderSizePixel = 0, ZIndex = 2 }, fog.layer)
		list[n * 2 - 1], list[n * 2] = core, soft
	end
	core.Visible = true
	soft.Visible = true
	return core, soft
end

-- One grid row of fog: a frame for every run of fogged cells (a full row of fog is one frame), the rest hidden.
local function drawFogRow(fog: Fog, cz: number)
	local G = Discovery.grid
	local list = fog.rows[cz]
	if not list then
		list = {}
		fog.rows[cz] = list
	end
	local scale, f = fog.scale, fog.feather
	local cellPx = G.Size * scale
	local z0 = G.Z0 + cz * G.Size
	local n = 0
	local cx = 0
	while cx < G.Cols do
		if Discovery.uncoveredCell(cx, cz) then
			cx += 1
			continue
		end
		local from = cx
		while cx < G.Cols and not Discovery.uncoveredCell(cx, cz) do
			cx += 1
		end
		n += 1
		local core, soft = fogFrames(fog, list, n)
		local at = point(G.X0 + from * G.Size, z0, scale)
		local w = (cx - from) * cellPx
		core.Position = at
		core.Size = UDim2.fromOffset(w, cellPx + 1) -- (1 px over the next row: no seam between the rows)
		soft.Position = at - UDim2.fromOffset(f, f)
		soft.Size = UDim2.fromOffset(w + 2 * f, cellPx + 2 * f)
	end
	for k = n * 2 + 1, #list do
		list[k].Visible = false
	end
end

-- The fog again: every row (cells nil) or only the rows of these cells.
local function drawFog(fog: Fog, cells: { number }?)
	local G = Discovery.grid
	if not cells then
		for cz = 0, G.Rows - 1 do
			drawFogRow(fog, cz)
		end
		return
	end
	local rows: { [number]: boolean } = {}
	for _, index in cells do
		local cz = index // G.Cols
		if not rows[cz] then
			rows[cz] = true
			drawFogRow(fog, cz)
		end
	end
end

-- ── Routes ─────────────────────────────────────────────────────────────────

-- Works the route out (when needed) and cuts off the part behind you.
local function updateRoute(route: Route, position: Vector3, now: number)
	local goal = route.goal
	if not goal then
		return
	end
	local points = route.points
	if points and not route.dirty then
		local k, x, z, off = Roads.closest(points, position.X, position.Z, route.step)
		if off <= ROUTE_OFF or now - route.computedAt < ROUTE_GAP then
			if k ~= route.step then
				route.step, route.cutX, route.cutZ = k, x, z
				route.full += 1
			elseif (x - route.cutX) ^ 2 + (z - route.cutZ) ^ 2 > 4 then
				route.cutX, route.cutZ = x, z
				route.cut += 1
			end
			return
		end
	end
	-- A new target, or you left the route: the way from here.
	points = Roads.route(position.X, position.Z, goal.X, goal.Z)
	route.points = points
	route.computedAt = now
	route.dirty = false
	route.step = 1
	route.cutX, route.cutZ = position.X, position.Z
	route.full += 1
end

-- ── Live markers ───────────────────────────────────────────────────────────

local function symbol(parent: any, text: string, size: number, color: Color3, zIndex: number): any
	return Ui.make("TextLabel", {
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = color,
		TextStrokeColor3 = P.paper,
		TextStrokeTransparency = 0,
		Visible = false,
		ZIndex = zIndex,
	}, parent)
end

type Pool = { items: { any }, make: () -> any }
local function pool(parent: any, make: (any) -> any): Pool
	return {
		items = {},
		make = function()
			return make(parent)
		end,
	}
end
local function take(p: Pool, index: number): any
	local item = p.items[index]
	if not item then
		item = p.make()
		p.items[index] = item
	end
	item.Visible = true
	return item
end
local function hideFrom(p: Pool, index: number)
	for n = index, #p.items do
		p.items[n].Visible = false
	end
end

local function dot(parent: any, color: Color3, text: string, size: number): any
	local d = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Theme.textOn(color),
		ZIndex = 18,
	}, parent)
	Ui.corner(d, size)
	Ui.stroke(d, P.paper, 1.5)
	return d
end

type Layer = { canvas: Canvas, players: Pool, crates: Pool, enemies: Pool }

local function layer(canvas: Canvas): Layer
	return {
		canvas = canvas,
		players = pool(canvas.markers, function(parent)
			return dot(parent, K.secondary, "", 10)
		end),
		crates = pool(canvas.markers, function(parent)
			return dot(parent, K.warn, "?", 12)
		end),
		enemies = pool(canvas.markers, function(parent)
			return dot(parent, K.red, "!", 14)
		end),
	}
end

-- rotation: the markers' own rotation (on the turning minimap they turn back to stay upright).
local function updateLayer(l: Layer, rotation: number)
	local scale = l.canvas.scale
	local n = 0
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if other ~= player and root then
			n += 1
			take(l.players, n).Position = point(root.Position.X, root.Position.Z, scale)
		end
	end
	hideFrom(l.players, n + 1)
	n = 0
	local loot = workspace:FindFirstChild("Loot")
	if loot then
		for _, crate in loot:GetChildren() do
			if crate:IsA("BasePart") then
				n += 1
				local marker = take(l.crates, n)
				marker.Position = point(crate.Position.X, crate.Position.Z, scale)
				marker.Rotation = rotation
			end
		end
	end
	hideFrom(l.crates, n + 1)
	n = 0
	local bandits = workspace:FindFirstChild("BanditCars")
	if bandits then
		for _, car in bandits:GetChildren() do
			local chassis = if car:IsA("Model") then car.PrimaryPart else nil
			if chassis and ((car:GetAttribute("Health") or 0) :: number) > 0 then
				n += 1
				local marker = take(l.enemies, n)
				marker.Position = point(chassis.Position.X, chassis.Position.Z, scale)
				marker.Rotation = rotation
			end
		end
	end
	hideFrom(l.enemies, n + 1)
end

-- Where am I, which way do I face and how fast am I going.
local function myPose(): (Vector3?, Vector3, number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil, Vector3.new(0, 0, -1), 0
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	return root.Position, if seat then seat.CFrame.LookVector else root.CFrame.LookVector, speed
end

local function heading(facing: Vector3): number
	return math.deg(math.atan2(facing.X, -facing.Z))
end

-- ── The minimap ────────────────────────────────────────────────────────────

-- The minimap's whole size (the map in its thin line, the turn line): client/Hud.luau stacks it under the cash.
MapView.MiniSize = Vector2.new(MINI_W, MINI_H + 4 + TURN_H)

local mini: any = nil -- the holder (what setVisible hides)
local miniCanvas: Canvas? = nil
local miniLayer: Layer? = nil
local miniZoom: any = nil -- UIScale of the zoom frame
local miniRotor: any = nil -- turns the map with the camera
local miniIcons: { any } = {}
local miniMe: any = nil
local miniStar: any = nil
local miniGps: any = nil
local miniCar: any = nil
local miniNorth: any = nil
local miniWhere: any = nil -- the header: "N · HARBOR"
local miniTurn: any = nil -- the line under the map: the next turn
local turnAt = 0
local cameraHeading = 0
local iconHeading = math.huge
local zoom = 1

-- 3.7: everything that shows a landmark (its icon on either map, its row in the big map's list) and the list's group
-- titles: shown only once the landmark is known (client/Discovery.luau).
local landmarkViews: { { id: string, view: any } } = {}
local groupViews: { { kind: string, view: any } } = {}
local discoveredLabel: any = nil

local function refreshKnown()
	for _, entry in landmarkViews do
		local visible = Discovery.knows(entry.id)
		if entry.view.Visible ~= visible then
			entry.view.Visible = visible
		end
	end
	for _, group in groupViews do
		local any = false
		for _, landmark in Map.Landmarks do
			if landmark.kind == group.kind and Discovery.knows(landmark.id) then
				any = true
				break
			end
		end
		group.view.Visible = any
	end
	if discoveredLabel then
		local n, total = Discovery.knownCount()
		discoveredLabel.Text = `{n} / {total} places discovered`
	end
end

-- A screen offset from the minimap's centre (pixels, y down) turned by `degrees` clockwise.
local function turn(x: number, y: number, degrees: number): (number, number)
	local a = math.rad(degrees)
	local c, s = math.cos(a), math.sin(a)
	return x * c - y * s, x * s + y * c
end

-- An offset kept inside the minimap's window (on its edge when too far). At the top it stays under the header (the
-- place, EXPAND), which draws over the map: the compass and the pinned markers would hide under it.
local function clampToEdge(x: number, y: number): (number, number, boolean)
	local far = math.max(math.abs(x) / EDGE_X, if y < 0 then -y / (MINI_H / 2 - 30) else y / EDGE_Y)
	if far > 1 then
		return x / far, y / far, true
	end
	return x, y, false
end

-- A marker over the turning map, or pinned to its edge when the point is out of view.
local function pin(marker: any, from: Vector3, at: Vector3?, scale: number)
	if not at then
		marker.Visible = false
		return
	end
	local x, y = turn((at.X - from.X) * scale, (at.Z - from.Z) * scale, -cameraHeading)
	x, y = clampToEdge(x, y)
	marker.Position = UDim2.fromOffset(MINI_W / 2 + x, MINI_H / 2 + y)
	marker.Visible = true
end

-- ── The header and the turn line ──────────────────────────────────────────

-- The road at (x, z) going along (dx, dz): a named one (a bridge, a highway, a country road), else the district's
-- street (along X) or avenue (along Z), named like the addresses (shared/Map.luau Map.addresses).
local function roadName(x: number, z: number, dx: number, dz: number): string?
	local way = math.sqrt(dx * dx + dz * dz)
	if way <= 0 then
		return nil
	end
	for _, s in Map.Segments do
		local name = s.name
		if not name then
			continue
		end
		local sx, sz = s.bx - s.ax, s.bz - s.az
		local length2 = sx * sx + sz * sz
		if length2 <= 0 then
			continue
		end
		local t = math.clamp(((x - s.ax) * sx + (z - s.az) * sz) / length2, 0, 1)
		local px, pz = s.ax + sx * t, s.az + sz * t
		if (x - px) ^ 2 + (z - pz) ^ 2 < s.width ^ 2 and math.abs(sx * dx + sz * dz) / (math.sqrt(length2) * way) > 0.7 then
			return name
		end
	end
	for _, d in Map.Districts do
		local x0, x1, z0, z1 = Map.districtEdges(d)
		if x >= x0 - 12 and x <= x1 + 12 and z >= z0 - 12 and z <= z1 + 12 then
			if math.abs(dx) >= math.abs(dz) then
				local k = math.floor((z - d.oz) / Map.Cell)
				return d.streets[(k - d.j0 + 1) % #d.streets + 1]
			end
			local k = math.floor((x - d.ox) / Map.Cell)
			return d.avenues[(k - d.i0 + 1) % #d.avenues + 1]
		end
	end
	return nil
end

-- The next turn of a route from where you are on it: "↰ Left onto Maple St · 120 m" (nil without a route).
local function nextTurn(route: Route): string?
	local points = route.points
	if not points or #points < 2 then
		return nil
	end
	local step = math.clamp(route.step, 1, #points - 1)
	local dx, dz = points[step + 1].x - route.cutX, points[step + 1].z - route.cutZ
	local ahead = math.sqrt(dx * dx + dz * dz)
	for k = step + 1, #points - 1 do
		local nx, nz = points[k + 1].x - points[k].x, points[k + 1].z - points[k].z
		local length = math.sqrt(nx * nx + nz * nz)
		local before = math.sqrt(dx * dx + dz * dz)
		if length >= 1 and before >= 0.5 then
			-- (a, b) → the sine of the angle between them: > 0 turns right (x east, z south).
			local side = (dx * nz - dz * nx) / (before * length)
			if math.abs(side) > 0.5 then
				local name = roadName(points[k].x + nx / length * 12, points[k].z + nz / length * 12, nx, nz)
				local metres = math.floor(ahead / 5 + 0.5) * 5
				local way = if side > 0 then "↱ Right" else "↰ Left"
				return `{way} {if name then `onto {name}` else "at the junction"} · {metres} m`
			end
		end
		if length >= 1 then
			dx, dz = nx, nz
		end
		ahead += length
	end
	if ahead < 25 then
		return "◎ Arriving"
	end
	return `↑ Straight on · {math.floor(ahead / 5 + 0.5) * 5} m`
end

-- Where a point is, in a word or two: a district, a place out of town, the winter, else the open road.
local function placeName(x: number, z: number): string
	for _, d in Map.Districts do
		local x0, x1, z0, z1 = Map.districtEdges(d)
		if x >= x0 and x <= x1 and z >= z0 and z <= z1 then
			return d.name
		end
	end
	for _, place in Map.Places do
		if (place.x - x) ^ 2 + (place.z - z) ^ 2 < 200 ^ 2 then
			return place.name
		end
	end
	return if Map.isWinter(x, z) then "Winter" else "Open road"
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- The header and the turn line (TURN_HZ times a second): the way you face and where you are; the job's route's next
-- turn, else the GPS route's, else the nearest address.
local function updateTurn(position: Vector3)
	local face = COMPASS[math.floor(((cameraHeading % 360) + 22.5) / 45) % 8 + 1]
	local where = `{face} · {string.upper(placeName(position.X, position.Z))}`
	if miniWhere.Text ~= where then
		miniWhere.Text = where
	end
	local line = nextTurn(jobRoute) or nextTurn(gpsRoute)
	if not line then
		local best, bestD = nil :: Map.Address?, 160 ^ 2
		for _, address in Map.addresses() do
			local d2 = (address.x - position.X) ^ 2 + (address.z - position.Z) ^ 2
			if d2 < bestD then
				best, bestD = address, d2
			end
		end
		line = if best then `⌂ Near {best.name}` else `⌂ {placeName(position.X, position.Z)}`
	end
	if miniTurn.Text ~= line then
		miniTurn.Text = line
	end
end

-- Every frame: the turn, the position and the pins; `heavy` (MINI_HZ) also redraws the tiles and the routes.
local function updateMini(position: Vector3, facing: Vector3, speed: number, heavy: boolean, dt: number)
	local canvas = miniCanvas
	if not canvas or not miniLayer then
		return
	end
	-- Turn with the camera (keep the last heading while it looks straight down).
	local camera = workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		if Vector3.new(look.X, 0, look.Z).Magnitude > 0.15 then
			cameraHeading = heading(look)
		end
	end
	miniRotor.Rotation = -cameraHeading
	-- Zoom out a little at speed.
	local wanted = 1 - (1 - ZOOM_OUT) * math.clamp((speed - 30) / 80, 0, 1)
	zoom += (wanted - zoom) * (1 - 0.88 ^ (dt * MINI_HZ))
	if math.abs(miniZoom.Scale - zoom) > 0.002 then
		miniZoom.Scale = zoom
	end
	local px, py = (position.X - B.x0) * MINI_SCALE, (position.Z - B.z0) * MINI_SCALE
	canvas.content.Position = UDim2.fromOffset(-px, -py)
	miniMe.Rotation = heading(facing) - cameraHeading
	-- The icons on the map stay upright.
	if math.abs(cameraHeading - iconHeading) > 0.5 then
		iconHeading = cameraHeading
		for _, icon in miniIcons do
			icon.Rotation = cameraHeading
		end
	end
	if heavy then
		updateLayer(miniLayer, cameraHeading)
		drawLine(canvas.gps, gpsRoute, MINI_SCALE)
		drawLine(canvas.job, jobRoute, MINI_SCALE)
		local now = os.clock()
		if now >= turnAt then
			turnAt = now + 1 / TURN_HZ
			updateTurn(position)
		end
	end
	local scale = MINI_SCALE * zoom
	pin(miniStar, position, target, scale)
	pin(miniGps, position, waypoint, scale)
	pin(miniCar, position, calledCarPosition(), scale)
	local nx, ny = clampToEdge(turn(0, -MINI_H, -cameraHeading))
	miniNorth.Position = UDim2.fromOffset(MINI_W / 2 + nx, MINI_H / 2 + ny)
end

local function buildMini(column: any, touch: boolean)
	local size = MapView.MiniSize
	mini = Ui.make("Frame", {
		Name = "Minimap",
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, column)
	-- 3.8: the map in a thin square line (no frame, no shadow), the turn line under it.
	local group = Ui.make("CanvasGroup", {
		Size = UDim2.fromOffset(MINI_W, MINI_H),
		BackgroundColor3 = C.land,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, mini)
	-- (the line on a frame of its own over the map, not on the CanvasGroup that clips the turning map)
	local frame = Ui.make("Frame", { Name = "Line", Size = UDim2.fromOffset(MINI_W, MINI_H), BackgroundTransparency = 1, ZIndex = 3 }, mini)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.ink, Thickness = 1, Transparency = 0.25 }, frame)
	local zoomFrame = Ui.make("Frame", {
		Size = UDim2.fromOffset(0, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, group)
	miniZoom = Ui.make("UIScale", { Scale = 1 }, zoomFrame)
	miniRotor = Ui.make("Frame", {
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, zoomFrame)
	local canvas = draw(miniRotor, MINI_SCALE, false)
	miniCanvas = canvas
	for _, landmark in Map.Landmarks do
		local icon = landmarkIcon(canvas.markers, landmark, MINI_SCALE, 22, false)
		icon.Visible = false -- (until it is known: refreshKnown)
		table.insert(miniIcons, icon)
		table.insert(landmarkViews, { id = landmark.id, view = icon })
	end
	miniLayer = layer(canvas)
	-- Soft charcoal shading at the top (under the header) and the bottom.
	for _, side in { { 0, 90 }, { 1, -90 } } do
		local shade = Ui.make("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromScale(0, side[1]),
			AnchorPoint = Vector2.new(0, side[1]),
			BackgroundColor3 = P.paper,
			BorderSizePixel = 0,
			ZIndex = 20,
		}, group)
		Ui.make("UIGradient", {
			Rotation = side[2],
			Transparency = NumberSequence.new(0.3, 1),
		}, shade)
	end
	-- You: an arrow in the middle, pointing the way you face.
	miniMe = symbol(group, "▲", 20, P.ink, 22)
	miniMe.Position = UDim2.fromScale(0.5, 0.5)
	miniMe.Visible = true
	miniStar = symbol(group, "■", 14, C.job, 23)
	miniGps = symbol(group, "◆", 16, C.gps, 23)
	miniCar = dot(group, C.car, "🚗", 20)
	miniCar.ZIndex = 23
	miniCar.Visible = false
	-- The compass: a small N in a charcoal square on the edge, toward the north (it goes round as the map turns).
	miniNorth = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 13),
		BackgroundColor3 = P.paper,
		BackgroundTransparency = 0.2,
		Text = "N",
		TextSize = 11,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink,
		ZIndex = 24,
	}, group)
	-- The header inside the map's top edge: where you are in small caps, EXPAND [M] a quiet text action (the big map).
	miniWhere = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(7, 4),
		BackgroundTransparency = 1,
		Text = "N",
		TextSize = 11,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink,
		TextStrokeColor3 = P.paper,
		TextStrokeTransparency = 0.4,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	}, mini)
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(112, 20) }, miniWhere)
	local expand = Ui.make("TextButton", {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 0),
		BackgroundTransparency = 1,
		Text = if touch then "EXPAND" else "EXPAND  [M]",
		TextSize = 11,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink2,
		TextStrokeColor3 = P.paper,
		TextStrokeTransparency = 0.4,
		AutoButtonColor = false,
		ZIndex = 4,
	}, mini)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, expand)
	-- Hover: brighter, a thin red line under it (the contract's text action).
	local underline = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -5), BackgroundColor3 = P.danger, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, expand)
	expand.MouseEnter:Connect(function()
		expand.TextColor3 = P.ink
		underline.BackgroundTransparency = 0
	end)
	expand.MouseLeave:Connect(function()
		expand.TextColor3 = P.ink2
		underline.BackgroundTransparency = 1
	end)
	expand.Activated:Connect(function()
		MapView.toggle()
	end)
	-- The turn line under the map: small caps on a faint charcoal stroke.
	local strip = Ui.make("Frame", {
		Size = UDim2.fromOffset(MINI_W, TURN_H),
		Position = UDim2.fromOffset(0, MINI_H + 4),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, mini)
	miniTurn = Ui.make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 12,
		TextScaled = true,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink2,
		TextStrokeColor3 = P.paper,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, strip)
	-- A long street name shrinks a little before it would be cut.
	Ui.make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 10 }, miniTurn)
end

-- ── The big map ────────────────────────────────────────────────────────────

local big: any = nil
local bigScale: any = nil
local bigCanvas: Canvas? = nil
local bigLayer: Layer? = nil
local bigMe: any = nil
local bigStar: any = nil
local bigGps: any = nil
local bigCar: any = nil

local function fitBig()
	local camera = workspace.CurrentCamera
	if not camera or not big then
		return
	end
	local viewport = camera.ViewportSize
	local w = WORLD_W * BIG_SCALE + LIST_W + 30
	local h = WORLD_H * BIG_SCALE + 56
	bigScale.Scale = math.clamp(math.min(viewport.X * 0.96 / w, viewport.Y * 0.9 / h), 0.3, 1.6)
end

local function updateBig(position: Vector3, facing: Vector3)
	local canvas = bigCanvas
	if not canvas or not bigLayer then
		return
	end
	bigMe.Visible = true
	bigMe.Position = point(position.X, position.Z, BIG_SCALE)
	bigMe.Rotation = heading(facing)
	updateLayer(bigLayer, 0)
	drawLine(canvas.gps, gpsRoute, BIG_SCALE)
	drawLine(canvas.job, jobRoute, BIG_SCALE)
	bigStar.Visible = target ~= nil
	if target then
		bigStar.Position = point(target.X, target.Z, BIG_SCALE)
	end
	bigGps.Visible = waypoint ~= nil
	if waypoint then
		bigGps.Position = point(waypoint.X, waypoint.Z, BIG_SCALE)
	end
	local car = calledCarPosition()
	bigCar.Visible = car ~= nil
	if car then
		bigCar.Position = point(car.X, car.Z, BIG_SCALE)
	end
end

local function refresh(heavy: boolean, dt: number)
	local position, facing, speed = myPose()
	if not position then
		return
	end
	if heavy then
		local now = os.clock()
		updateRoute(jobRoute, position, now)
		updateRoute(gpsRoute, position, now)
	end
	if mini.Visible then
		updateMini(position, facing, speed, heavy, dt)
	end
	if heavy and big.Visible then
		updateBig(position, facing)
	end
end

function MapView.isOpen(): boolean
	return big ~= nil and big.Visible
end

function MapView.toggle()
	if big then
		fitBig()
		big.Visible = not big.Visible
		if big.Visible then
			refresh(true, 0)
		end
	end
end

function MapView.setVisible(visible: boolean)
	if mini then
		mini.Visible = visible
	end
	if big and not visible then
		big.Visible = false
	end
	Discovery.setShown(visible) -- 3.7: the "new location" banners wait while the HUD is hidden
end

local function setGps(landmark: Map.Landmark?)
	MapView.setWaypoint(if landmark then Vector3.new(landmark.x, Map.RoadTop, landmark.z) else nil)
	MapView.onWaypoint(landmark)
end

local function buildList(parent: any)
	local list = Ui.make("ScrollingFrame", {
		Size = UDim2.new(0, LIST_W, 1, -56),
		Position = UDim2.new(1, -LIST_W - 8, 0, 48),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = P.line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 41,
	}, parent)
	Ui.padding(list, 6)
	Ui.list(list, true, 6)
	local order = 0
	local function title(text: string, color: Color3)
		order += 1
		-- 3.8: small caps on the charcoal; the kind's tint in a small square before it.
		local row = Ui.make("Frame", { Size = UDim2.new(1, -8, 0, 20), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 42 }, list)
		Ui.make("Frame", { Size = UDim2.fromOffset(7, 7), Position = UDim2.new(0, 2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 42 }, row)
		local label = Ui.caps(row, text, UDim2.new(1, -16, 1, 0), { Position = UDim2.fromOffset(16, 0), TextColor3 = P.ink2, TextSize = 11, ZIndex = 42 })
		return row, label
	end
	local function entry(landmark: Map.Landmark)
		order += 1
		local button = Ui.make("TextButton", {
			Size = UDim2.new(1, -8, 0, 52),
			BackgroundColor3 = K.charcoal,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
			ZIndex = 42,
		}, list)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 0.75 }, button)
		-- Hover: a raised row and a narrow red rule.
		local rule = Ui.make("Frame", { Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = P.danger, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 44 }, button)
		button.MouseEnter:Connect(function()
			button.BackgroundColor3 = K.raised
			rule.BackgroundTransparency = 0
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = K.charcoal
			rule.BackgroundTransparency = 1
		end)
		Ui.icon(button, Icons.landmark(landmark.id), landmark.icon, UDim2.fromOffset(40, 40), {
			Position = UDim2.fromOffset(4, 6),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 43,
			ImageColor3 = KIND_COLORS[landmark.kind] or P.ink2,
		})
		Ui.label(button, landmark.name, UDim2.new(1, -54, 0, 20), { Position = UDim2.fromOffset(50, 4), TextSize = 14, Font = Theme.HeadingFont, TextColor3 = P.ink, ZIndex = 43, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		Ui.label(button, landmark.description, UDim2.new(1, -54, 0, 26), {
			Position = UDim2.fromOffset(50, 24),
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			TextColor3 = P.ink2,
			ZIndex = 43,
		})
		button.Activated:Connect(function()
			setGps(landmark)
			big.Visible = false
		end)
		button.Visible = false -- (until it is known: refreshKnown)
		table.insert(landmarkViews, { id = landmark.id, view = button })
	end
	title("Click a place to set the GPS", C.gps)
	-- 3.7: how much of the map's places you know (the rest you find by driving around).
	local _, counter = title("", C.fog)
	discoveredLabel = counter
	local clear = Ui.ghostButton(list, "◆  CLEAR GPS", UDim2.new(1, -8, 0, 32), C.gps, function()
		setGps(nil)
	end)
	order += 1
	clear.LayoutOrder = order
	clear.ZIndex = 42
	type Group = { kind: string, title: string, color: Color3 }
	local groups: { Group } = {
		{ kind = "shop", title = "SHOPS AND REPAIRS", color = KIND_COLORS.shop },
		{ kind = "employer", title = "WORK  (earn their vehicle)", color = KIND_COLORS.employer },
		{ kind = "venue", title = "STORES AND FOOD", color = KIND_COLORS.venue }, -- 5.3
		{ kind = "place", title = "FAR PLACES", color = KIND_COLORS.place },
	}
	for _, group in groups do
		local row = title(group.title, group.color)
		table.insert(groupViews, { kind = group.kind, view = row })
		for _, landmark in Map.Landmarks do
			if landmark.kind == group.kind then
				entry(landmark)
			end
		end
	end
end

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function buildBig(gui: any)
	-- Drawn at a fixed scale, fitted to the screen with a UIScale when it opens.
	local mapW, mapH = WORLD_W * BIG_SCALE, WORLD_H * BIG_SCALE
	big = Ui.make("Frame", {
		Name = "BigMap",
		Size = UDim2.fromOffset(mapW + LIST_W + 30, mapH + 56),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 40,
	}, gui)
	bigScale = Ui.make("UIScale", {}, big)
	-- 3.8: a charcoal window (square, a thin line). 5.8: the window header: [■ ZDC] | [map glyph] MAP, the legend in
	-- small type with the markers' colours, a thin line under it, the square ✕.
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 0.45 }, big)
	local heading = Ui.heading(big, "Map", { glyph = "map", textSize = 18, height = 36 })
	heading.frame.Size = UDim2.fromOffset(170, 36)
	heading.frame.Position = UDim2.fromOffset(12, 5)
	for _, part in heading.frame:GetDescendants() do
		if part:IsA("GuiObject") then
			part.ZIndex = 41
		end
	end
	heading.frame.ZIndex = 41
	Ui.make("TextLabel", {
		Name = "Legend",
		Size = UDim2.new(1, -(190 + 60 + 84), 0, 36),
		Position = UDim2.fromOffset(190, 5),
		BackgroundTransparency = 1,
		RichText = true,
		Text = `▲ YOU   <font color="{hex(C.job)}">■━</font> DELIVERY   <font color="{hex(C.gps)}">◆━</font> GPS   <font color="{hex(P.danger)}">!</font> BANDIT CAR   ? CRATE   🚌━ BUS LINES   <font color="{hex(C.fog)}">■</font> UNEXPLORED`,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = 12,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink2,
		ZIndex = 41,
	}, big)
	Ui.make("Frame", { Name = "HeaderLine", Size = UDim2.new(1, -16, 0, 1), Position = UDim2.fromOffset(8, 45), BackgroundColor3 = K.rule, BorderSizePixel = 0, ZIndex = 41 }, big)
	local close = Ui.closeButton(big, function()
		big.Visible = false
	end)
	close.Position = UDim2.new(1, -8, 0, 3)
	close.ZIndex = 42
	-- 6.3: the BUS chip left of the ✕: the bus lines on the map on or off (for the session).
	local busChip = Ui.make("TextButton", {
		Name = "BusChip",
		Size = UDim2.fromOffset(76, 24),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -56, 0, 11),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		TextSize = 12,
		Font = Theme.HeadingFont,
		ZIndex = 42,
	}, big)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 0.45 }, busChip)
	local function showBus()
		busChip.Text = if MapView.busShown then "🚌 BUS ON" else "🚌 BUS OFF"
		busChip.TextColor3 = if MapView.busShown then P.ink else P.ink2
		busChip.BackgroundColor3 = if MapView.busShown then K.raised else K.recessed
		local canvas = bigCanvas
		if canvas and canvas.bus then
			canvas.bus.Visible = MapView.busShown
		end
	end
	busChip.Activated:Connect(function()
		MapView.busShown = not MapView.busShown
		showBus()
	end)
	local holder = Ui.make("Frame", {
		Size = UDim2.fromOffset(mapW, mapH),
		Position = UDim2.fromOffset(8, 48),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 40,
	}, big)
	local canvas = draw(holder, BIG_SCALE, true)
	bigCanvas = canvas
	showBus()
	for _, landmark in Map.Landmarks do
		local icon = landmarkIcon(canvas.markers, landmark, BIG_SCALE, 24, true)
		icon.Activated:Connect(function()
			setGps(landmark)
			big.Visible = false
		end)
		icon.Visible = false -- (until it is known: refreshKnown)
		table.insert(landmarkViews, { id = landmark.id, view = icon })
	end
	bigLayer = layer(canvas)
	bigMe = symbol(canvas.markers, "▲", 24, P.ink, 20)
	bigStar = symbol(canvas.markers, "■", 16, C.job, 21)
	bigGps = symbol(canvas.markers, "◆", 24, C.gps, 21)
	bigCar = dot(canvas.markers, C.car, "🚗", 22)
	bigCar.ZIndex = 21
	bigCar.Visible = false
	buildList(big)
end

-- column: the frame the minimap goes into (under the money panel, laid out by Hud).
function MapView.start(gui: any, column: any)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	buildMini(column, touch)
	buildBig(gui)

	-- 3.7: the fog and the known landmarks, now (all fog until the server's state comes) and whenever cells are
	-- uncovered (only their rows are drawn again).
	local function onDiscovery(cells: { number }?)
		if miniCanvas then
			drawFog(miniCanvas.fog, cells)
		end
		if bigCanvas then
			drawFog(bigCanvas.fog, cells)
		end
		refreshKnown()
	end
	Discovery.changed:Connect(onDiscovery)
	onDiscovery(nil)

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitBig)
	end

	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local heavy = elapsed >= 1 / MINI_HZ
		if heavy then
			elapsed = math.min(elapsed - 1 / MINI_HZ, 1 / MINI_HZ)
		end
		if mini.Visible or big.Visible then
			refresh(heavy, dt)
		end
	end)
end

return MapView
