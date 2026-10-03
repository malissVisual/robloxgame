--!strict
-- The minimap (top left, always on) and the big map (M). Both are drawn once from shared/Map.luau (land, water,
-- the mountain, roads, blocks, the shops and the far places) and carry live markers: you (an arrow), the other
-- players, the delivery target (a star; on the minimap it sticks to the edge when it is out of view) and the supply
-- crates near you.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local Ui = require(script.Parent.Ui)

local MapView = {}

local player = Players.LocalPlayer
local B = Map.Bounds
local WORLD_W = B.x1 - B.x0
local WORLD_H = B.z1 - B.z0

type ShopIcon = { text: string, color: Color3 }
local SHOP_ICONS: { [string]: ShopIcon } = {
	depot = { text = "📦", color = Color3.fromRGB(255, 190, 60) },
	dealer = { text = "🚗", color = Color3.fromRGB(255, 90, 70) },
	guns = { text = "🔫", color = Color3.fromRGB(255, 150, 60) },
	mechanic = { text = "🔧", color = Color3.fromRGB(110, 180, 255) },
	supplies = { text = "🛒", color = Color3.fromRGB(120, 230, 110) },
}
local SHOP_COLORS = {
	depot = Color3.fromRGB(150, 110, 40),
	dealer = Color3.fromRGB(140, 50, 44),
	guns = Color3.fromRGB(140, 80, 40),
	mechanic = Color3.fromRGB(50, 90, 140),
	supplies = Color3.fromRGB(60, 120, 60),
}
local DISTRICT_COLORS = {
	downtown = Color3.fromRGB(86, 86, 92),
	harbor = Color3.fromRGB(96, 88, 78),
	suburbs = Color3.fromRGB(78, 98, 64),
}

type Canvas = {
	content: any,
	scale: number,
	markers: any, -- the layer of the live markers inside the content
}

local function rect(parent: any, x0: number, z0: number, x1: number, z1: number, scale: number, color: Color3, z: number): any
	return Ui.make("Frame", {
		Position = UDim2.fromOffset((x0 - B.x0) * scale, (z0 - B.z0) * scale),
		Size = UDim2.fromOffset((x1 - x0) * scale, (z1 - z0) * scale),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
end

local function point(x: number, z: number, scale: number): UDim2
	return UDim2.fromOffset((x - B.x0) * scale, (z - B.z0) * scale)
end

local function icon(parent: any, text: string, color: Color3, size: number, z: number): any
	local label = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = z,
	}, parent)
	Ui.corner(label, size)
	Ui.stroke(label, Color3.new(0, 0, 0), 1.5)
	return label
end

local function caption(parent: any, text: string, x: number, z: number, scale: number, size: number, color: Color3, zIndex: number)
	Ui.make("TextLabel", {
		Size = UDim2.fromOffset(160, size + 4),
		Position = point(x, z, scale),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		Font = Enum.Font.GothamBlack,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		ZIndex = zIndex,
	}, parent)
end

-- Draws the whole world into a frame at `scale` pixels per stud.
local function draw(parent: any, scale: number, labels: boolean): Canvas
	local content = Ui.make("Frame", {
		Size = UDim2.fromOffset(WORLD_W * scale, WORLD_H * scale),
		BackgroundColor3 = Color3.fromRGB(64, 70, 52),
		BorderSizePixel = 0,
		ZIndex = 1,
	}, parent)
	rect(content, B.x0, B.z0, Map.River.x0, Map.WinterZ, scale, Color3.fromRGB(196, 202, 208), 2) -- winter
	local lake = Map.Lake
	rect(content, lake.x0, lake.z0, lake.x1, lake.z1, scale, Color3.fromRGB(150, 200, 225), 3)
	local water = Color3.fromRGB(44, 86, 112)
	rect(content, Map.River.x0, B.z0, Map.River.x1, B.z1, scale, water, 2)
	rect(content, Map.Sea.x0, B.z0, B.x1, B.z1, scale, water, 2)
	-- The mountain.
	local m = Map.Mountain
	local hill = rect(content, m.x - m.radius, m.z - m.radius, m.x + m.radius, m.z + m.radius, scale, Color3.fromRGB(104, 98, 88), 3)
	Ui.make("UICorner", { CornerRadius = UDim.new(1, 0) }, hill)
	-- Yards.
	for _, yard in Map.Yards do
		rect(content, yard.x0, yard.z0, yard.x1, yard.z1, scale, Color3.fromRGB(96, 96, 96), 3)
	end
	-- Blocks.
	local half = Map.BlockSize / 2
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
				local special = if d.id == "downtown" then Map.SpecialBlocks[`{i},{j}`] else nil
				local color = if special then SHOP_COLORS[special] else DISTRICT_COLORS[d.style]
				rect(content, cx - half, cz - half, cx + half, cz + half, scale, color or DISTRICT_COLORS.downtown, 3)
			end
		end
	end
	-- Roads.
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
	-- The safe zone.
	local safeHalf = Config.City.SafeHalf
	local safe = rect(content, -safeHalf, -safeHalf, safeHalf, safeHalf, scale, Color3.new(0, 0, 0), 5)
	safe.BackgroundTransparency = 1
	Ui.make("UIStroke", { Color = Color3.fromRGB(80, 255, 140), Thickness = 2 }, safe)
	-- Shops and places.
	local iconSize = math.clamp(scale * 70, 14, 26)
	for id, shop in Map.Shops do
		local info = SHOP_ICONS[id]
		if info then
			icon(content, info.text, info.color, iconSize, 6).Position = point(shop.x, shop.z, scale)
		end
	end
	for _, place in Map.Places do
		icon(content, "📍", Color3.fromRGB(200, 60, 200), iconSize, 6).Position = point(place.x, place.z, scale)
		if labels then
			caption(content, place.name, place.x, place.z + 34 / scale * 0.6, scale, 13, Color3.fromRGB(255, 200, 255), 7)
		end
	end
	if labels then
		for _, d in Map.Districts do
			local x0, x1, z0 = Map.districtEdges(d)
			caption(content, d.name:upper(), (x0 + x1) / 2, z0 - 40, scale, 16, Color3.fromRGB(255, 230, 160), 7)
		end
		for _, s in Map.Connectors do
			if s.name and s.kind == "bridge" then
				caption(content, s.name, (s.ax + s.bx) / 2, s.az - 40, scale, 12, Color3.fromRGB(230, 200, 160), 7)
			end
		end
		caption(content, "TUNNEL", m.x + 70, m.z, scale, 13, Color3.fromRGB(230, 230, 230), 7)
		caption(content, "FROZEN LAKE", (lake.x0 + lake.x1) / 2, lake.z0 - 30, scale, 13, Color3.fromRGB(40, 80, 110), 7)
		caption(content, "WINTER", 0, Map.WinterZ - 60, scale, 16, Color3.fromRGB(60, 70, 80), 7)
	end
	local markers = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8 }, content)
	return { content = content, scale = scale, markers = markers }
end

-- ── Live markers ───────────────────────────────────────────────────────────

local function arrow(parent: any, size: number, color: Color3): any
	return Ui.make("TextLabel", {
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = "▲",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = color,
		TextStrokeTransparency = 0,
		ZIndex = 20,
	}, parent)
end

local function star(parent: any, size: number): any
	return Ui.make("TextLabel", {
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = "★",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 220, 40),
		TextStrokeTransparency = 0,
		Visible = false,
		ZIndex = 21,
	}, parent)
end

local target: Vector3? = nil

function MapView.setTarget(position: Vector3?)
	target = position
end

-- Where am I and which way do I face.
local function myPose(): (Vector3?, Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
	if root then
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		local facing = if seat then seat.CFrame.LookVector else root.CFrame.LookVector
		return root.Position, facing
	end
	return nil, look
end

local function heading(facing: Vector3): number
	return math.deg(math.atan2(facing.X, -facing.Z))
end

-- A pool of small dots for the other players and the crates.
type Pool = { parent: any, items: { any }, make: () -> any }
local function pool(parent: any, make: (any) -> any): Pool
	return { parent = parent, items = {}, make = function()
		return make(parent)
	end }
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

local function playerDot(parent: any): any
	local dot = Ui.make("Frame", {
		Size = UDim2.fromOffset(10, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(80, 170, 255),
		ZIndex = 19,
	}, parent)
	Ui.corner(dot, 5)
	Ui.stroke(dot, Color3.new(1, 1, 1), 1.5)
	Ui.make("TextLabel", {
		Name = "Label",
		Size = UDim2.fromOffset(120, 14),
		Position = UDim2.new(0.5, 0, 0, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(180, 220, 255),
		TextStrokeTransparency = 0.3,
		ZIndex = 19,
	}, dot)
	return dot
end

local function crateDot(parent: any): any
	local dot = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 200, 40),
		Text = "?",
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.new(0, 0, 0),
		ZIndex = 18,
	}, parent)
	Ui.corner(dot, 3)
	return dot
end

local function updateMarkers(canvas: Canvas, players: Pool, crates: Pool)
	local n = 0
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			n += 1
			local dot = take(players, n)
			dot.Position = point(root.Position.X, root.Position.Z, canvas.scale)
			local label = dot:FindFirstChild("Label")
			if label then
				label.Text = other.DisplayName
			end
		end
	end
	hideFrom(players, n + 1)
	local c = 0
	local loot = workspace:FindFirstChild("Loot")
	if loot then
		for _, crate in loot:GetChildren() do
			if crate:IsA("BasePart") then
				c += 1
				take(crates, c).Position = point(crate.Position.X, crate.Position.Z, canvas.scale)
			end
		end
	end
	hideFrom(crates, c + 1)
end

-- ── The minimap ────────────────────────────────────────────────────────────

local MINI = 210
local MINI_SCALE = 0.42

local mini: any = nil
local miniCanvas: Canvas? = nil
local miniMe: any = nil
local miniStar: any = nil
local miniPlayers: Pool? = nil
local miniCrates: Pool? = nil

-- ── The big map ────────────────────────────────────────────────────────────

local big: any = nil
local bigCanvas: Canvas? = nil
local bigMe: any = nil
local bigStar: any = nil
local bigPlayers: Pool? = nil
local bigCrates: Pool? = nil

function MapView.isOpen(): boolean
	return big ~= nil and big.Visible
end

function MapView.toggle()
	if big then
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

local function updateMini(position: Vector3, facing: Vector3)
	local canvas = miniCanvas
	if not canvas or not mini.Visible then
		return
	end
	local px, py = (position.X - B.x0) * canvas.scale, (position.Z - B.z0) * canvas.scale
	canvas.content.Position = UDim2.fromOffset(MINI / 2 - px, MINI / 2 - py)
	miniMe.Rotation = heading(facing)
	if miniPlayers and miniCrates then
		updateMarkers(canvas, miniPlayers, miniCrates)
	end
	-- The target: inside the view, or pinned to the edge.
	if target then
		local dx = (target.X - position.X) * canvas.scale
		local dy = (target.Z - position.Z) * canvas.scale
		local limit = MINI / 2 - 10
		local distance = math.sqrt(dx * dx + dy * dy)
		if distance > limit then
			dx, dy = dx / distance * limit, dy / distance * limit
		end
		miniStar.Position = UDim2.fromOffset(MINI / 2 + dx, MINI / 2 + dy)
		miniStar.Visible = true
	else
		miniStar.Visible = false
	end
end

local function updateBig(position: Vector3, facing: Vector3)
	local canvas = bigCanvas
	if not canvas or not big.Visible then
		return
	end
	bigMe.Position = point(position.X, position.Z, canvas.scale)
	bigMe.Rotation = heading(facing)
	if bigPlayers and bigCrates then
		updateMarkers(canvas, bigPlayers, bigCrates)
	end
	if target then
		bigStar.Position = point(target.X, target.Z, canvas.scale)
		bigStar.Visible = true
	else
		bigStar.Visible = false
	end
end

function MapView.start(gui: any, scaleOf: (any) -> any)
	-- Minimap: a round-cornered window that clips the drawn world.
	mini = Ui.make("CanvasGroup", {
		Name = "Minimap",
		Size = UDim2.fromOffset(MINI, MINI),
		Position = UDim2.fromOffset(16, 92),
		BackgroundColor3 = Color3.fromRGB(20, 22, 26),
		BorderSizePixel = 0,
	}, gui)
	Ui.corner(mini, 14)
	scaleOf(mini)
	local canvas = draw(mini, MINI_SCALE, false)
	miniCanvas = canvas
	miniPlayers = pool(canvas.markers, playerDot)
	miniCrates = pool(canvas.markers, crateDot)
	miniMe = arrow(mini, 22, Color3.fromRGB(255, 255, 255))
	miniMe.Position = UDim2.fromScale(0.5, 0.5)
	miniStar = star(mini, 24)
	local border = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30 }, mini)
	Ui.corner(border, 14)
	Ui.make("UIStroke", { Color = Color3.fromRGB(255, 196, 50), Thickness = 2 }, border)
	Ui.make("TextLabel", {
		Size = UDim2.fromOffset(MINI, 16),
		Position = UDim2.new(0, 0, 1, -18),
		BackgroundTransparency = 1,
		Text = "M = big map",
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(230, 230, 230),
		TextStrokeTransparency = 0.3,
		ZIndex = 31,
	}, mini)

	-- Big map: fits the screen.
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local scale = math.min((viewport.X * 0.8) / WORLD_W, (viewport.Y * 0.8) / WORLD_H)
	big = Ui.make("Frame", {
		Name = "BigMap",
		Size = UDim2.fromOffset(WORLD_W * scale + 16, WORLD_H * scale + 52),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 22, 26),
		Visible = false,
		ZIndex = 40,
	}, gui)
	Ui.corner(big, 12)
	Ui.stroke(big, Color3.fromRGB(255, 196, 50), 2)
	Ui.make("TextLabel", {
		Size = UDim2.new(1, -60, 0, 36),
		Position = UDim2.fromOffset(12, 4),
		BackgroundTransparency = 1,
		Text = "MAP   ▲ you   ★ delivery   ? supply crate   📍 far places",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 196, 50),
	}, big)
	local close = Ui.button(big, "X", UDim2.fromOffset(34, 34), Color3.fromRGB(230, 70, 60), function()
		big.Visible = false
	end)
	close.Position = UDim2.new(1, -42, 0, 6)
	local holder = Ui.make("Frame", {
		Size = UDim2.fromOffset(WORLD_W * scale, WORLD_H * scale),
		Position = UDim2.fromOffset(8, 44),
		BackgroundTransparency = 1,
	}, big)
	local bc = draw(holder, scale, true)
	bigCanvas = bc
	bigPlayers = pool(bc.markers, playerDot)
	bigCrates = pool(bc.markers, crateDot)
	bigMe = arrow(bc.markers, 22, Color3.fromRGB(255, 255, 255))
	bigStar = star(bc.markers, 28)

	RunService.RenderStepped:Connect(function()
		local position, facing = myPose()
		if not position then
			return
		end
		updateMini(position, facing)
		updateBig(position, facing)
	end)
end

return MapView
