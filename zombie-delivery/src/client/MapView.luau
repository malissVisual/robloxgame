--!strict
-- The minimap (always on: bottom left on a computer, top left on a touch screen) and the big map (M / MAP).
-- Both are drawn once from shared/Map.luau: land, winter, water, the mountain, roads, blocks and an icon for every
-- landmark (shops, employers, far places). Live markers: you (an arrow), other players, bandit cars (red !),
-- supply crates (?), the delivery target (★) and your GPS point (◆; both stick to the minimap's edge when far).
-- The big map lists every landmark with what you can do there; click one to set the GPS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local Ui = require(script.Parent.Ui)

local MapView = {}

local player = Players.LocalPlayer
local B = Map.Bounds
local WORLD_W = B.x1 - B.x0
local WORLD_H = B.z1 - B.z0

local MINI = 230
local MINI_SCALE = 0.6 -- px per stud: the minimap shows about 380 studs across
local BIG_SCALE = 0.16 -- the big map is drawn at this scale and then fitted to the screen
local LIST_W = 320

local BLOCK_COLORS = {
	downtown = Color3.fromRGB(86, 86, 92),
	harbor = Color3.fromRGB(96, 88, 78),
	suburbs = Color3.fromRGB(78, 98, 64),
}
local KIND_COLORS = {
	shop = Color3.fromRGB(70, 170, 90),
	employer = Color3.fromRGB(210, 150, 30),
	place = Color3.fromRGB(150, 80, 200),
}

type Canvas = { content: any, scale: number, markers: any }

-- Set by Hud: the GPS was set (landmark) or cleared (nil).
MapView.onWaypoint = function(_landmark: Map.Landmark?) end

local target: Vector3? = nil
local waypoint: Vector3? = nil

function MapView.setTarget(position: Vector3?)
	target = position
end

function MapView.setWaypoint(position: Vector3?)
	waypoint = position
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
		ZIndex = 7,
	}, parent)
end

local function landmarkIcon(parent: any, landmark: Map.Landmark, scale: number, size: number, clickable: boolean): any
	local icon = Ui.make(if clickable then "TextButton" else "TextLabel", {
		Size = UDim2.fromOffset(size, size),
		Position = point(landmark.x, landmark.z, scale),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = KIND_COLORS[landmark.kind] or Color3.new(0.3, 0.3, 0.3),
		Text = landmark.icon,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 9,
	}, parent)
	Ui.corner(icon, size)
	Ui.stroke(icon, Color3.new(1, 1, 1), 1.5)
	return icon
end

-- The whole world into a frame at `scale` pixels per stud.
local function draw(parent: any, scale: number, big: boolean): Canvas
	local content = Ui.make("Frame", {
		Size = UDim2.fromOffset(WORLD_W * scale, WORLD_H * scale),
		BackgroundColor3 = Color3.fromRGB(64, 70, 52),
		BorderSizePixel = 0,
		ZIndex = 1,
	}, parent)
	rect(content, B.x0, B.z0, Map.River.x0, Map.WinterZ, scale, Color3.fromRGB(196, 202, 208), 2)
	local water = Color3.fromRGB(44, 86, 112)
	rect(content, Map.River.x0, B.z0, Map.River.x1, B.z1, scale, water, 2)
	rect(content, Map.Sea.x0, B.z0, B.x1, B.z1, scale, water, 2)
	local lake = Map.Lake
	rect(content, lake.x0, lake.z0, lake.x1, lake.z1, scale, Color3.fromRGB(150, 200, 225), 3)
	local m = Map.Mountain
	local hill = rect(content, m.x - m.radius, m.z - m.radius, m.x + m.radius, m.z + m.radius, scale, Color3.fromRGB(110, 102, 92), 3)
	Ui.make("UICorner", { CornerRadius = UDim.new(1, 0) }, hill)
	for _, yard in Map.Yards do
		rect(content, yard.x0, yard.z0, yard.x1, yard.z1, scale, Color3.fromRGB(100, 100, 100), 3)
	end
	local half = Map.BlockSize / 2
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
				local special = Map.special(d.id, i, j)
				local color = if special then Color3.fromRGB(120, 110, 70) else BLOCK_COLORS[d.style] or BLOCK_COLORS.downtown
				rect(content, cx - half, cz - half, cx + half, cz + half, scale, color, 3)
			end
		end
	end
	for _, s in Map.Segments do
		local dx, dz = s.bx - s.ax, s.bz - s.az
		local length = math.sqrt(dx * dx + dz * dz)
		local color = if s.kind == "bridge" then Color3.fromRGB(150, 90, 50)
			elseif s.kind == "ice" then Color3.fromRGB(120, 170, 200)
			elseif s.kind == "highway" then Color3.fromRGB(58, 58, 64)
			else Color3.fromRGB(36, 36, 40)
		Ui.make("Frame", {
			Size = UDim2.fromOffset((length + s.width) * scale, math.max(2, s.width * scale)),
			Position = point((s.ax + s.bx) / 2, (s.az + s.bz) / 2, scale),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = math.deg(math.atan2(dz, dx)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, content)
	end
	local safeHalf = Config.City.SafeHalf
	local safe = rect(content, -safeHalf, -safeHalf, safeHalf, safeHalf, scale, Color3.new(0, 0, 0), 5)
	safe.BackgroundTransparency = 1
	Ui.make("UIStroke", { Color = Color3.fromRGB(80, 255, 140), Thickness = 2 }, safe)
	if big then
		for _, d in Map.Districts do
			local x0, x1, z0 = Map.districtEdges(d)
			caption(content, d.name:upper(), (x0 + x1) / 2, z0 - 60, scale, 14, Color3.fromRGB(255, 230, 160))
		end
		caption(content, "TUNNEL", m.x + 80, m.z, scale, 11, Color3.fromRGB(230, 230, 230))
		caption(content, "FROZEN LAKE", (lake.x0 + lake.x1) / 2, lake.z0 - 40, scale, 11, Color3.fromRGB(40, 80, 110))
		caption(content, "WINTER", 0, Map.WinterZ - 120, scale, 14, Color3.fromRGB(60, 70, 80))
		caption(content, "SAFE ZONE", 0, safeHalf + 40, scale, 11, Color3.fromRGB(80, 255, 140))
	end
	local markers = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8 }, content)
	return { content = content, scale = scale, markers = markers }
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

local function updateLayer(l: Layer)
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
				take(l.crates, n).Position = point(crate.Position.X, crate.Position.Z, scale)
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
				take(l.enemies, n).Position = point(chassis.Position.X, chassis.Position.Z, scale)
			end
		end
	end
	hideFrom(l.enemies, n + 1)
end

-- Where am I and which way do I face.
local function myPose(): (Vector3?, Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil, Vector3.new(0, 0, -1)
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return root.Position, if seat then seat.CFrame.LookVector else root.CFrame.LookVector
end

local function heading(facing: Vector3): number
	return math.deg(math.atan2(facing.X, -facing.Z))
end

-- ── The minimap ────────────────────────────────────────────────────────────

local mini: any = nil
local miniLayer: Layer? = nil
local miniMe: any = nil
local miniStar: any = nil
local miniGps: any = nil

-- A marker inside the minimap, or pinned to its edge when the point is out of view.
local function pin(marker: any, from: Vector3, at: Vector3?, scale: number)
	if not at then
		marker.Visible = false
		return
	end
	local dx = (at.X - from.X) * scale
	local dy = (at.Z - from.Z) * scale
	local limit = MINI / 2 - 12
	local distance = math.sqrt(dx * dx + dy * dy)
	if distance > limit then
		dx, dy = dx / distance * limit, dy / distance * limit
	end
	marker.Position = UDim2.fromOffset(MINI / 2 + dx, MINI / 2 + dy)
	marker.Visible = true
end

-- ── The big map ────────────────────────────────────────────────────────────

local big: any = nil
local bigScale: any = nil
local bigLayer: Layer? = nil
local bigMe: any = nil
local bigStar: any = nil
local bigGps: any = nil

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

function MapView.isOpen(): boolean
	return big ~= nil and big.Visible
end

function MapView.toggle()
	if big then
		fitBig()
		big.Visible = not big.Visible
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
	waypoint = if landmark then Vector3.new(landmark.x, Map.RoadTop, landmark.z) else nil
	MapView.onWaypoint(landmark)
end

local function buildList(parent: any)
	local list = Ui.make("ScrollingFrame", {
		Size = UDim2.new(0, LIST_W, 1, -56),
		Position = UDim2.new(1, -LIST_W - 8, 0, 48),
		BackgroundColor3 = Color3.fromRGB(30, 32, 38),
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
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
		Ui.label(list, text, UDim2.new(1, -8, 0, 22), { LayoutOrder = order, TextColor3 = color, TextSize = 16, Font = Enum.Font.GothamBlack, ZIndex = 42 })
	end
	local function entry(landmark: Map.Landmark)
		order += 1
		local button = Ui.make("TextButton", {
			Size = UDim2.new(1, -8, 0, 52),
			BackgroundColor3 = Color3.fromRGB(46, 50, 58),
			Text = "",
			AutoButtonColor = true,
			LayoutOrder = order,
			ZIndex = 42,
		}, list)
		Ui.corner(button, 8)
		Ui.label(button, landmark.icon, UDim2.fromOffset(40, 40), { Position = UDim2.fromOffset(4, 6), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 43 })
		Ui.label(button, landmark.name, UDim2.new(1, -54, 0, 20), { Position = UDim2.fromOffset(50, 4), TextSize = 15, Font = Enum.Font.GothamBlack, ZIndex = 43 })
		Ui.label(button, landmark.description, UDim2.new(1, -54, 0, 26), {
			Position = UDim2.fromOffset(50, 24),
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			TextColor3 = Color3.fromRGB(190, 195, 200),
			ZIndex = 43,
		})
		button.Activated:Connect(function()
			setGps(landmark)
			big.Visible = false
		end)
	end
	title("Click a place to set the GPS", Color3.fromRGB(255, 255, 255))
	local clear = Ui.button(list, "CLEAR GPS", UDim2.new(1, -8, 0, 32), Color3.fromRGB(90, 96, 104), function()
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

function MapView.start(gui: any, scaleOf: (any) -> any)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	-- Minimap.
	mini = Ui.make("CanvasGroup", {
		Name = "Minimap",
		Size = UDim2.fromOffset(MINI, MINI),
		Position = if touch then UDim2.fromOffset(16, 92) else UDim2.new(0, 16, 1, -16),
		AnchorPoint = if touch then Vector2.zero else Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(20, 22, 26),
		BorderSizePixel = 0,
	}, gui)
	Ui.corner(mini, 14)
	scaleOf(mini)
	local canvas = draw(mini, MINI_SCALE, false)
	for _, landmark in Map.Landmarks do
		landmarkIcon(canvas.markers, landmark, MINI_SCALE, 22, false)
	end
	miniLayer = layer(canvas)
	miniMe = symbol(mini, "▲", 24, Color3.new(1, 1, 1), 20)
	miniMe.Position = UDim2.fromScale(0.5, 0.5)
	miniMe.Visible = true
	miniStar = symbol(mini, "★", 26, Color3.fromRGB(255, 220, 40), 21)
	miniGps = symbol(mini, "◆", 22, Color3.fromRGB(90, 200, 255), 21)
	local frame = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30 }, mini)
	Ui.corner(frame, 14)
	Ui.make("UIStroke", { Color = Color3.fromRGB(255, 196, 50), Thickness = 2 }, frame)
	Ui.make("TextLabel", {
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(0.5, -10, 0, 2),
		BackgroundTransparency = 1,
		Text = "N",
		TextSize = 16,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
		ZIndex = 31,
	}, mini)
	Ui.make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -18),
		BackgroundTransparency = 1,
		Text = if touch then "MAP button = big map" else "M = big map & GPS",
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(230, 230, 230),
		TextStrokeTransparency = 0.3,
		ZIndex = 31,
	}, mini)

	-- Big map: drawn at a fixed scale, fitted to the screen with a UIScale when it opens.
	local mapW, mapH = WORLD_W * BIG_SCALE, WORLD_H * BIG_SCALE
	big = Ui.make("Frame", {
		Name = "BigMap",
		Size = UDim2.fromOffset(mapW + LIST_W + 30, mapH + 56),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 22, 26),
		Visible = false,
		ZIndex = 40,
	}, gui)
	bigScale = Ui.make("UIScale", {}, big)
	Ui.corner(big, 12)
	Ui.stroke(big, Color3.fromRGB(255, 196, 50), 2)
	Ui.make("TextLabel", {
		Size = UDim2.new(1, -60, 0, 36),
		Position = UDim2.fromOffset(12, 6),
		BackgroundTransparency = 1,
		Text = "MAP   ▲ you   ★ delivery   ◆ GPS   ! bandit car   ? crate",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 196, 50),
		ZIndex = 41,
	}, big)
	local close = Ui.button(big, "X", UDim2.fromOffset(34, 34), Color3.fromRGB(230, 70, 60), function()
		big.Visible = false
	end)
	close.Position = UDim2.new(1, -42, 0, 6)
	close.ZIndex = 42
	local holder = Ui.make("Frame", {
		Size = UDim2.fromOffset(mapW, mapH),
		Position = UDim2.fromOffset(8, 48),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 40,
	}, big)
	local bc = draw(holder, BIG_SCALE, true)
	for _, landmark in Map.Landmarks do
		local icon = landmarkIcon(bc.markers, landmark, BIG_SCALE, 24, true)
		icon.Activated:Connect(function()
			setGps(landmark)
			big.Visible = false
		end)
	end
	bigLayer = layer(bc)
	bigMe = symbol(bc.markers, "▲", 24, Color3.new(1, 1, 1), 20)
	bigStar = symbol(bc.markers, "★", 28, Color3.fromRGB(255, 220, 40), 21)
	bigGps = symbol(bc.markers, "◆", 24, Color3.fromRGB(90, 200, 255), 21)
	buildList(big)

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitBig)
	end

	RunService.RenderStepped:Connect(function()
		local position, facing = myPose()
		if not position then
			return
		end
		if mini.Visible and miniLayer then
			local px, py = (position.X - B.x0) * MINI_SCALE, (position.Z - B.z0) * MINI_SCALE
			miniLayer.canvas.content.Position = UDim2.fromOffset(MINI / 2 - px, MINI / 2 - py)
			miniMe.Rotation = heading(facing)
			updateLayer(miniLayer)
			pin(miniStar, position, target, MINI_SCALE)
			pin(miniGps, position, waypoint, MINI_SCALE)
		end
		if big.Visible and bigLayer then
			bigMe.Visible = true
			bigMe.Position = point(position.X, position.Z, BIG_SCALE)
			bigMe.Rotation = heading(facing)
			updateLayer(bigLayer)
			bigStar.Visible = target ~= nil
			if target then
				bigStar.Position = point(target.X, target.Z, BIG_SCALE)
			end
			bigGps.Visible = waypoint ~= nil
			if waypoint then
				bigGps.Position = point(waypoint.X, waypoint.Z, BIG_SCALE)
			end
		end
	end)
end

return MapView
