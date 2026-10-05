--!strict
-- The minimap (always on: bottom left on a computer, top left on a touch screen) and the big map (M / MAP).
-- Both are drawn once from shared/Map.luau: land, winter, water, the mountain, blocks, roads (highways and bridges
-- stand out) and an icon for every landmark (shops, employers, far places). Live markers: you (an arrow), other
-- players, bandit cars (red !), supply crates (?), the delivery target (★), your GPS point (◆) and the car a chauffeur
-- is bringing you (🚗, MapView.setCar from client/Hud.luau; the three stick to the minimap's edge when far).
-- Like GTA, the way there is drawn along the roads (shared/Roads.luau): yellow to the job's target, purple to the
-- GPS point. A route is worked out again when the target changes or you leave it by more than ROUTE_OFF studs, and
-- the part behind you is cut off as you drive. The minimap turns with the camera (north marker on its edge) and
-- zooms out a little at speed; it moves every frame and redraws its tiles and routes MINI_HZ times a second.
-- The big map lists every landmark with what you can do there; click one to set the GPS.

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

local MapView = {}

local player = Players.LocalPlayer
local B = Map.Bounds
local WORLD_W = B.x1 - B.x0
local WORLD_H = B.z1 - B.z0

local MINI = 230
local MINI_SCALE = 0.6 -- px per stud: the minimap shows about 380 studs across
local MINI_HZ = 20
local MINI_EDGE = MINI / 2 - 13 -- markers pinned to the edge stay this far from the centre (a square)
local ZOOM_OUT = 0.72 -- the minimap's zoom at full speed
local BIG_SCALE = 0.16 -- the big map is drawn at this scale and then fitted to the screen
local LIST_W = 320
local ROUTE_OFF = 40 -- studs off the route before it is worked out again
local ROUTE_GAP = 0.5 -- seconds between two routes to the same target

local C = {
	land = Color3.fromRGB(39, 52, 43),
	snow = Color3.fromRGB(176, 186, 196),
	water = Color3.fromRGB(41, 78, 86),
	shore = Color3.fromRGB(64, 112, 140),
	ice = Color3.fromRGB(150, 196, 220),
	yard = Color3.fromRGB(82, 84, 88),
	special = Color3.fromRGB(96, 88, 62),
	roadEdge = Color3.fromRGB(22, 24, 28),
	road = Color3.fromRGB(125, 138, 121),
	highway = Color3.fromRGB(226, 230, 209),
	bridge = Color3.fromRGB(184, 128, 78),
	iceRoad = Color3.fromRGB(184, 228, 244),
	safe = Color3.fromRGB(153, 212, 125),
	job = Ui.Colors.yellow,
	gps = Ui.Gps,
	car = Ui.Colors.blue, -- the car on its way (the Hud's car call line is blue too)
	routeEdge = Color3.fromRGB(20, 18, 24),
	accent = Ui.Colors.yellow,
}
local BLOCK_COLORS = {
	downtown = Color3.fromRGB(66, 68, 74),
	harbor = Color3.fromRGB(72, 68, 62),
	suburbs = Color3.fromRGB(60, 74, 54),
}
local KIND_COLORS = {
	shop = Ui.Colors.green,
	employer = Ui.Colors.yellow,
	place = Color3.fromRGB(150, 80, 200),
}

-- A route line on one canvas: two pools of rotated frames (a dark edge under the colour), drawn from `step` on.
type Line = { edges: { any }, fills: { any }, parent: any, color: Color3, width: number, full: number, cut: number }
type Canvas = { content: any, scale: number, markers: any, job: Line, gps: Line }

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
		Font = Enum.Font.GothamBlack,
		TextColor3 = color,
		TextStrokeTransparency = 0.2,
		ZIndex = 8,
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
		BackgroundColor3 = KIND_COLORS[landmark.kind] or Color3.new(0.3, 0.3, 0.3),
		Text = if Icons.get(art) then "" else landmark.icon,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 9,
	}, parent)
	Ui.corner(icon, size)
	Ui.stroke(icon, Color3.new(1, 1, 1), 1.5)
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
		Color = ColorSequence.new(Color3.fromRGB(150, 142, 132), Color3.fromRGB(70, 66, 60)),
		Rotation = 45,
	}, hill)
	for _, yard in Map.Yards do
		rounded(rect(content, yard.x0, yard.z0, yard.x1, yard.z1, scale, C.yard, 3), math.max(2, math.floor(12 * scale)))
	end
	-- Blocks, a little lighter than the ground; the special ones warmer.
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
	-- Roads: all the dark edges first, then the fills, so the junctions are clean.
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
	local safe = rect(content, -safeHalf, -safeHalf, safeHalf, safeHalf, scale, Color3.new(0, 0, 0), 6)
	safe.BackgroundTransparency = 1
	Ui.make("UIStroke", { Color = C.safe, Thickness = if big then 2 else 1.5, Transparency = 0.25 }, safe)
	if big then
		for _, d in Map.Districts do
			local x0, x1, z0 = Map.districtEdges(d)
			caption(content, d.name:upper(), (x0 + x1) / 2, z0 - 60, scale, 14, Color3.fromRGB(255, 230, 160))
		end
		caption(content, "TUNNEL", m.x + 80, m.z, scale, 11, Color3.fromRGB(230, 230, 230))
		caption(content, "FROZEN LAKE", (lake.x0 + lake.x1) / 2, lake.z0 - 40, scale, 11, Color3.fromRGB(40, 80, 110))
		caption(content, "WINTER", 0, Map.WinterZ - 120, scale, 14, Color3.fromRGB(60, 70, 80))
		caption(content, "SAFE ZONE", 0, safeHalf + 40, scale, 11, C.safe)
	end
	-- The routes (the GPS under the job), then the markers on top.
	local routes = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7 }, content)
	local gpsLayer = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 }, routes)
	local jobLayer = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, routes)
	local width = if big then 4 else 7
	local markers = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9 }, content)
	return {
		content = content,
		scale = scale,
		markers = markers,
		job = newLine(jobLayer, C.job, width),
		gps = newLine(gpsLayer, C.gps, width),
	}
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
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 18,
	}, parent)
	Ui.corner(d, size)
	Ui.stroke(d, Color3.new(0, 0, 0), 1.5)
	return d
end

type Layer = { canvas: Canvas, players: Pool, crates: Pool, enemies: Pool }

local function layer(canvas: Canvas): Layer
	return {
		canvas = canvas,
		players = pool(canvas.markers, function(parent)
			return dot(parent, Color3.fromRGB(70, 160, 255), "", 12)
		end),
		crates = pool(canvas.markers, function(parent)
			return dot(parent, Color3.fromRGB(230, 180, 30), "?", 12)
		end),
		enemies = pool(canvas.markers, function(parent)
			return dot(parent, Color3.fromRGB(220, 40, 40), "!", 14)
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
local cameraHeading = 0
local iconHeading = math.huge
local zoom = 1

-- A screen offset from the minimap's centre (pixels, y down) turned by `degrees` clockwise.
local function turn(x: number, y: number, degrees: number): (number, number)
	local a = math.rad(degrees)
	local c, s = math.cos(a), math.sin(a)
	return x * c - y * s, x * s + y * c
end

-- An offset kept inside the minimap's square (on its edge when too far).
local function clampToEdge(x: number, y: number): (number, number, boolean)
	local far = math.max(math.abs(x), math.abs(y))
	if far > MINI_EDGE then
		return x / far * MINI_EDGE, y / far * MINI_EDGE, true
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
	marker.Position = UDim2.fromOffset(MINI / 2 + x, MINI / 2 + y)
	marker.Visible = true
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
	end
	local scale = MINI_SCALE * zoom
	pin(miniStar, position, target, scale)
	pin(miniGps, position, waypoint, scale)
	pin(miniCar, position, calledCarPosition(), scale)
	local nx, ny = clampToEdge(turn(0, -MINI, -cameraHeading))
	miniNorth.Position = UDim2.fromOffset(MINI / 2 + nx, MINI / 2 + ny)
end

local function buildMini(column: any, touch: boolean)
	mini = Ui.make("Frame", {
		Name = "Minimap",
		Size = UDim2.fromOffset(MINI, MINI),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, column)
	-- 3.2: the HUD's glass around it, a rim of dark glass with a quiet stroke (the money card's look).
	local rim = Ui.make("Frame", {
		Name = "Rim",
		Size = UDim2.new(1, 8, 1, 8),
		Position = UDim2.fromOffset(-4, -4),
		BackgroundColor3 = Ui.Colors.panel,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, mini)
	Ui.corner(rim, 20)
	Ui.stroke(rim)
	-- The map is a CanvasGroup: it clips the turning content to its rounded square.
	local group = Ui.make("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.land,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, mini)
	Ui.corner(group, 16)
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
		table.insert(miniIcons, landmarkIcon(canvas.markers, landmark, MINI_SCALE, 22, false))
	end
	miniLayer = layer(canvas)
	-- Soft shading at the top and the bottom.
	for _, side in { { 0, 90 }, { 1, -90 } } do
		local shade = Ui.make("Frame", {
			Size = UDim2.new(1, 0, 0, 46),
			Position = UDim2.fromScale(0, side[1]),
			AnchorPoint = Vector2.new(0, side[1]),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 20,
		}, group)
		Ui.make("UIGradient", {
			Rotation = side[2],
			Transparency = NumberSequence.new(0.45, 1),
		}, shade)
	end
	-- You: an arrow in the middle, pointing the way you face.
	miniMe = symbol(group, "▲", 22, Color3.new(1, 1, 1), 22)
	miniMe.Position = UDim2.fromScale(0.5, 0.5)
	miniMe.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	miniMe.Visible = true
	miniStar = symbol(group, "★", 26, C.job, 23)
	miniGps = symbol(group, "◆", 20, C.gps, 23)
	miniCar = dot(group, C.car, "🚗", 20)
	miniCar.ZIndex = 23
	miniCar.Visible = false
	-- The compass: N in a dark disc on the edge, toward the north (it goes round as the map turns).
	miniNorth = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(20, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 13),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.1,
		Text = "N",
		TextSize = 12,
		Font = Theme.DisplayFont,
		TextColor3 = Ui.Colors.red,
		ZIndex = 24,
	}, group)
	Ui.corner(miniNorth, 10)
	Ui.make("UIStroke", { Color = Ui.Colors.red, Thickness = 1, Transparency = 0.35 }, miniNorth)
	-- The key for the big map: a small dark pill at the bottom.
	local key = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.3,
		Text = if touch then "MAP  ·  BIG MAP & GPS" else "M  ·  BIG MAP & GPS",
		TextSize = 10,
		Font = Theme.HeadingFont,
		TextColor3 = Ui.Colors.dim,
		ZIndex = 25,
	}, group)
	Ui.corner(key, 8)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, key)
	-- The frame around it: a thin line on the map's edge.
	local border = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, mini)
	Ui.corner(border, 16)
	Ui.make("UIStroke", { Color = Theme.Border, Thickness = 1, Transparency = 0.2 }, border)
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
end

local function setGps(landmark: Map.Landmark?)
	MapView.setWaypoint(if landmark then Vector3.new(landmark.x, Map.RoadTop, landmark.z) else nil)
	MapView.onWaypoint(landmark)
end

local function buildList(parent: any)
	local list = Ui.make("ScrollingFrame", {
		Size = UDim2.new(0, LIST_W, 1, -56),
		Position = UDim2.new(1, -LIST_W - 8, 0, 48),
		BackgroundColor3 = Ui.Colors.panelLight,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Ui.Colors.dim,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 41,
	}, parent)
	Ui.corner(list, 8)
	Ui.padding(list, 6)
	Ui.list(list, true, 6)
	local order = 0
	local function title(text: string, color: Color3)
		order += 1
		Ui.caps(list, text, UDim2.new(1, -8, 0, 20), { LayoutOrder = order, TextColor3 = color, TextSize = 12, ZIndex = 42 })
	end
	local function entry(landmark: Map.Landmark)
		order += 1
		local button = Ui.make("TextButton", {
			Size = UDim2.new(1, -8, 0, 52),
			BackgroundColor3 = Ui.Colors.panel,
			BackgroundTransparency = 0.2,
			Text = "",
			AutoButtonColor = true,
			LayoutOrder = order,
			ZIndex = 42,
		}, list)
		Ui.corner(button, 10)
		Ui.stroke(button)
		Ui.icon(button, Icons.landmark(landmark.id), landmark.icon, UDim2.fromOffset(40, 40), {
			Position = UDim2.fromOffset(4, 6),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 43,
			ImageColor3 = KIND_COLORS[landmark.kind] or Color3.new(1, 1, 1),
		})
		Ui.label(button, landmark.name, UDim2.new(1, -54, 0, 20), { Position = UDim2.fromOffset(50, 4), TextSize = 14, Font = Theme.DisplayFont, ZIndex = 43, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		Ui.label(button, landmark.description, UDim2.new(1, -54, 0, 26), {
			Position = UDim2.fromOffset(50, 24),
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			TextColor3 = Ui.Colors.dim,
			ZIndex = 43,
		})
		button.Activated:Connect(function()
			setGps(landmark)
			big.Visible = false
		end)
	end
	title("Click a place to set the GPS", Ui.Colors.text)
	local clear = Ui.ghostButton(list, "◆  CLEAR GPS", UDim2.new(1, -8, 0, 32), C.gps, function()
		setGps(nil)
	end)
	order += 1
	clear.LayoutOrder = order
	clear.ZIndex = 42
	type Group = { kind: string, title: string, color: Color3 }
	local groups: { Group } = {
		{ kind = "shop", title = "SHOPS  (in the safe zone)", color = KIND_COLORS.shop },
		{ kind = "employer", title = "WORK  (earn their vehicle)", color = KIND_COLORS.employer },
		{ kind = "place", title = "FAR PLACES", color = KIND_COLORS.place },
	}
	for _, group in groups do
		title(group.title, group.color)
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
		BackgroundColor3 = Ui.Colors.panel,
		BackgroundTransparency = Theme.WindowTransparency,
		Visible = false,
		ZIndex = 40,
	}, gui)
	bigScale = Ui.make("UIScale", {}, big)
	Ui.corner(big, Theme.PanelRadius)
	Ui.stroke(big, Ui.Colors.panelLight:Lerp(Ui.Colors.text, 0.2), 1).Transparency = 0.3
	Ui.make("TextLabel", {
		Size = UDim2.new(1, -60, 0, 36),
		Position = UDim2.fromOffset(12, 6),
		BackgroundTransparency = 1,
		RichText = true,
		Text = `MAP   ▲ you   <font color="{hex(C.job)}">★ delivery ━</font>   <font color="{hex(C.gps)}">◆ GPS ━</font>   <font color="#FF5050">!</font> bandit car   ? crate`,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 17,
		Font = Theme.DisplayFont,
		TextColor3 = Ui.Colors.text,
		ZIndex = 41,
	}, big)
	local close = Ui.closeButton(big, function()
		big.Visible = false
	end)
	close.Position = UDim2.new(1, -8, 0, 6)
	close.ZIndex = 42
	local holder = Ui.make("Frame", {
		Size = UDim2.fromOffset(mapW, mapH),
		Position = UDim2.fromOffset(8, 48),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 40,
	}, big)
	local canvas = draw(holder, BIG_SCALE, true)
	bigCanvas = canvas
	for _, landmark in Map.Landmarks do
		local icon = landmarkIcon(canvas.markers, landmark, BIG_SCALE, 24, true)
		icon.Activated:Connect(function()
			setGps(landmark)
			big.Visible = false
		end)
	end
	bigLayer = layer(canvas)
	bigMe = symbol(canvas.markers, "▲", 24, Color3.new(1, 1, 1), 20)
	bigStar = symbol(canvas.markers, "★", 28, C.job, 21)
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
