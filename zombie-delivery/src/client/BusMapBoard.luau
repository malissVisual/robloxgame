--!strict
-- 6.3, the bus map on the stops (server/BusStops.luau builds a MapBoard panel at every shelter, shared/BusLines.luau
-- has the lines): the board of the stop nearest you, within Config.Bus.MapBoardReach, gets a map drawn here. The
-- express lines in their colours (BusLines.mapLines: a few corners each), every stop a dot with a white ring, the
-- names of the stops of this stop's lines, Downtown and the Suburbs as quiet blocks, the depot, and YOU ARE HERE in
-- the contract red at this stop; over it "ZDC TRANSIT · EXPRESS", under it the lines' chips.
--
-- One board at a time: it is drawn when the nearest stop changes (a POLL, on foot or not) and taken down when you walk
-- off (the board's plain face, "BUS MAP", shows again); a board that streamed out is drawn again when it is back.
-- Nothing runs per frame.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BusLines = require(Shared:WaitForChild("BusLines"))
local Config = require(Shared:WaitForChild("Config"))
local Map = require(Shared:WaitForChild("Map"))
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local BusMapBoard = {}

local player = Players.LocalPlayer
local STOP_TAG = "BusStop" -- (server/BusStops.luau's BusStops.Tag)
local POLL = 0.5
local PPS = 50 -- the map's pixels per stud on the 3.4 × 4.6 board: 170 × 230 (a 10 px name is 0.2 studs tall)
local TITLE = 0.09 -- the title's share of the board's height
local FOOT = 0.13 -- the footer's (the stop's name and the lines' chips)
local PAD = 8 -- pixels round the map
local K = Theme.Contract
local DOT = 7 -- a stop's dot (px)
local HERE = 11 -- YOU ARE HERE's dot

local stops: { [number]: Model } = {} -- the stop models streamed in, by StopId
local shown: { id: number, board: BasePart, gui: SurfaceGui, plain: SurfaceGui? }? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- A straight band from a to b in the map's pixels, `width` thick, round ends (like client/MapView.luau's).
local function band(parent: Instance, ax: number, ay: number, bx: number, by: number, width: number, color: Color3, z: number)
	local dx, dy = bx - ax, by - ay
	local frame = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
		Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + width, width),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	Ui.make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
end

local function dot(parent: Instance, x: number, y: number, size: number, fill: Color3, ring: Color3, z: number): any
	local frame = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	Ui.make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
	Ui.make("UIStroke", { Color = ring, Thickness = 1.5 }, frame)
	return frame
end

local function label(parent: Instance, text: string, x: number, y: number, size: number, color: Color3, right: boolean, z: number)
	Ui.make("TextLabel", {
		AnchorPoint = Vector2.new(if right then 1 else 0, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(120, size + 2),
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		Font = Theme.HeadingFont,
		TextColor3 = color,
		TextStrokeColor3 = K.charcoal,
		TextStrokeTransparency = 0.2,
		TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
		ZIndex = z,
	}, parent)
end

-- The whole map on a board for stop `stopId`.
local function draw(board: BasePart, stopId: number): SurfaceGui
	local gui = Ui.make("SurfaceGui", {
		Name = "BusMapGui",
		Face = Enum.NormalId.Back, -- (toward the road, like the board's plain face)
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PPS,
		LightInfluence = 0,
	}, nil) :: SurfaceGui
	local w, h = board.Size.X * PPS, board.Size.Y * PPS
	local back = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.charcoal, BorderSizePixel = 0 }, gui)
	Ui.make("TextLabel", {
		Size = UDim2.new(1, -12, TITLE, -6),
		Position = UDim2.fromOffset(6, 4),
		BackgroundTransparency = 1,
		Text = "ZDC TRANSIT · EXPRESS",
		TextScaled = true,
		Font = Theme.HeadingFont,
		TextColor3 = K.text,
		ZIndex = 2,
	}, back)
	Ui.make("Frame", { Size = UDim2.new(1, -12, 0, 1), Position = UDim2.new(0, 6, TITLE, 0), BackgroundColor3 = K.rule, BorderSizePixel = 0, ZIndex = 2 }, back)
	local mapTop, mapH = h * TITLE + 2, h * (1 - TITLE - FOOT) - 4
	local area = Ui.make("Frame", {
		Size = UDim2.fromOffset(w, mapH),
		Position = UDim2.fromOffset(0, mapTop),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
	}, back)

	-- The projection: every line's corners in the area, north up, the same scale both ways.
	local lines = BusLines.mapLines(32)
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	for _, line in lines do
		for _, p in line.points do
			x0, x1 = math.min(x0, p.x), math.max(x1, p.x)
			z0, z1 = math.min(z0, p.z), math.max(z1, p.z)
		end
	end
	local scale = math.min((w - 2 * PAD) / math.max(1, x1 - x0), (mapH - 2 * PAD) / math.max(1, z1 - z0))
	local ox = (w - (x1 - x0) * scale) / 2
	local oy = (mapH - (z1 - z0) * scale) / 2
	local function project(x: number, z: number): (number, number)
		return ox + (x - x0) * scale, oy + (z - z0) * scale
	end

	-- Downtown and the Suburbs as quiet blocks, the depot's block (where the safe zone is) lighter.
	for _, d in Map.Districts do
		local ex0, ex1, ez0, ez1 = Map.districtEdges(d)
		local ax, ay = project(ex0, ez0)
		local bx, by = project(ex1, ez1)
		Ui.make("Frame", { Position = UDim2.fromOffset(ax, ay), Size = UDim2.fromOffset(bx - ax, by - ay), BackgroundColor3 = K.row, BorderSizePixel = 0, ZIndex = 2 }, area)
	end
	local depot = Map.Shops.depot
	local half = Map.BlockSize / 2
	local dx0, dy0 = project(depot.x - half, depot.z - half)
	local dx1, dy1 = project(depot.x + half, depot.z + half)
	Ui.make("Frame", { Position = UDim2.fromOffset(dx0, dy0), Size = UDim2.fromOffset(dx1 - dx0, dy1 - dy0), BackgroundColor3 = K.track, BorderSizePixel = 0, ZIndex = 3 }, area)
	local cx, cy = project(depot.x, depot.z)
	label(area, "DEPOT", cx + (dx1 - dx0) / 2 + 2, cy, 9, K.secondary, false, 3)

	-- The lines, then the stops over them.
	local here: BusLines.Stop? = BusLines.allStops()[stopId]
	local mine: { [number]: boolean } = {}
	if here then
		for _, id in here.lines do
			mine[id] = true
		end
	end
	for _, line in lines do
		local color = rgb(line.color)
		local count = #line.points
		for k = 1, count do
			local a, b = line.points[k], line.points[k % count + 1]
			local ax, ay = project(a.x, a.z)
			local bx, by = project(b.x, b.z)
			band(area, ax, ay, bx, by, if mine[line.line] then 5 else 3, color, 4)
		end
	end
	local drawn: { [number]: boolean } = {}
	for _, line in lines do
		for _, stop in line.stops do
			if drawn[stop.id] then
				continue
			end
			drawn[stop.id] = true
			local sx, sy = project(stop.x, stop.z)
			dot(area, sx, sy, DOT, rgb(line.color), K.text, 5)
			-- The names of the stops of this stop's lines (left of the dot on the map's right half).
			local full = BusLines.allStops()[stop.id]
			local named = false
			if full then
				for _, id in full.lines do
					named = named or mine[id] == true
				end
			end
			if named and stop.id ~= stopId then
				local right = sx > w / 2
				label(area, stop.name, sx + (if right then -6 else 6), sy, 10, K.text, right, 6)
			end
		end
	end
	if here then
		local hx, hy = project(here.x, here.z)
		dot(area, hx, hy, HERE, K.red, K.text, 7)
		local right = hx > w / 2
		label(area, "YOU ARE HERE", hx + (if right then -8 else 8), hy - 6, 11, K.red, right, 7)
		label(area, here.name, hx + (if right then -8 else 8), hy + 6, 10, K.text, right, 7)
	end

	-- The footer: this stop, the lines' chips.
	local foot = Ui.make("Frame", {
		Size = UDim2.new(1, -12, FOOT, -6),
		Position = UDim2.new(0, 6, 1 - FOOT, 2),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, back)
	Ui.make("TextLabel", {
		Size = UDim2.fromScale(1, 0.45),
		BackgroundTransparency = 1,
		Text = if here then string.upper(here.name) else "",
		TextScaled = true,
		Font = Theme.HeadingFont,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	}, foot)
	local row = Ui.make("Frame", { Size = UDim2.fromScale(1, 0.48), Position = UDim2.fromScale(0, 0.52), BackgroundTransparency = 1, ZIndex = 2 }, foot)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for n, line in lines do
		local chip = Ui.make("TextLabel", {
			Size = UDim2.new(1 / #lines, -4, 1, 0),
			LayoutOrder = n,
			BackgroundColor3 = rgb(line.color),
			BorderSizePixel = 0,
			Text = `{line.line} {line.short}`,
			TextScaled = true,
			Font = Theme.HeadingFont,
			TextColor3 = K.text,
			ZIndex = 3,
		}, row)
		Ui.make("UICorner", { CornerRadius = UDim.new(0, 3) }, chip)
	end
	gui.Parent = board
	return gui
end

-- Takes the drawn board down (its plain face shows again).
local function clear()
	local current = shown
	if not current then
		return
	end
	shown = nil
	current.gui:Destroy()
	if current.plain and current.plain.Parent then
		current.plain.Enabled = true
	end
end

-- The nearest stop's board, drawn when it changes.
local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local id: number? = nil
	if root and root:IsA("BasePart") then
		local near = BusLines.stopsNear(root.Position.X, root.Position.Z, Config.Bus.MapBoardReach)
		if #near > 0 then
			id = near[1].stop.id
		end
	end
	local current = shown
	if current and (current.id ~= id or not current.board.Parent or not current.gui.Parent) then
		clear()
	end
	if not id or shown then
		return
	end
	local model = stops[id]
	local board = if model and model.Parent then model:FindFirstChild("MapBoard") else nil
	if not board or not board:IsA("BasePart") then
		return -- (not streamed in yet: the next poll)
	end
	local plain = board:FindFirstChild("MapBoardGui")
	local gui = draw(board, id)
	if plain and plain:IsA("SurfaceGui") then
		plain.Enabled = false
		shown = { id = id, board = board, gui = gui, plain = plain }
	else
		shown = { id = id, board = board, gui = gui, plain = nil }
	end
end

local function addStop(item: Instance)
	local id = item:GetAttribute("StopId")
	if item:IsA("Model") and type(id) == "number" then
		stops[id] = item
	end
end

function BusMapBoard.start()
	for _, item in CollectionService:GetTagged(STOP_TAG) do
		addStop(item)
	end
	CollectionService:GetInstanceAddedSignal(STOP_TAG):Connect(addStop)
	CollectionService:GetInstanceRemovedSignal(STOP_TAG):Connect(function(item: Instance)
		local id = item:GetAttribute("StopId")
		if type(id) == "number" and stops[id] == item then
			stops[id] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(POLL)
			local ok, err = pcall(function()
				update()
			end)
			if not ok then
				warn(`[BusMapBoard] {err}`)
			end
		end
	end)
end

return BusMapBoard
