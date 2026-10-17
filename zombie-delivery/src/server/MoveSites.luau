--!strict
-- The ZDC dispatch kiosk (9.7 runs: the lobby's dispatch, server/LobbyWorld.luau): builds shared/MoveSiteLooks.luau's
-- pieces as anchored parts (Config.MoveSites). Only the pieces the looks mark solid collide and stop bullets; the rest
-- is decoration (CanCollide and CanQuery off). CanTouch off everywhere, no loops, no meshes: the lamp's glass and its
-- PointLight take their day look through DayNight. Text is SurfaceGuis drawn within MoveSiteLooks.textRange
-- (tests/movesites_test.luau on the looks, tools/move-sites/check.py on what this builds on the recorder). 10.5: the
-- city's moving world (the depot's board, the Wall's drop-off, the houses' moving-day dress, Walt's farm, the depot's
-- banner and the evacuation spots) went with the city.
--
--   MoveSites.kiosk(parent, spot, name)   the kiosk (Persistent) at `spot`, named `name`: returns the model and its
--                                     corkboard ("Board", its PrimaryPart: the part server/Runs.luau hangs its prompt on)
--   MoveSites.build(parent, place, pieces, name, mode?)   one set as a Model (the kiosk's builder)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared.MoveSiteLooks)
local SandboxMap = require(Shared.SandboxMap)
local DayNight = require(script.Parent.DayNight)

local MoveSites = {}

local FONTS: { [string]: Enum.Font } = { Black = Enum.Font.GothamBlack, Bold = Enum.Font.GothamBold, Medium = Enum.Font.GothamMedium }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Text on one face of a part: the lines one under the other, centred (on a coloured panel when `back`).
local function words(part: BasePart, w: Looks.Words, size: { number })
	local width, height = Looks.faceSize(w.face, size)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Words" .. w.face
	gui.Face = (Enum.NormalId :: any)[w.face]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Looks.pixels(width, height)
	gui.LightInfluence = if w.lit then 0 else 0.2
	gui.MaxDistance = Looks.textRange(height)
	gui.Parent = part
	local holder: Instance = gui
	local back = w.back
	if back then
		local inset = w.inset or 0
		local panel = Instance.new("Frame")
		panel.Name = "Back"
		panel.BackgroundColor3 = rgb(back)
		panel.BorderSizePixel = 0
		panel.Position = UDim2.fromScale(inset, inset)
		panel.Size = UDim2.fromScale(1 - 2 * inset, 1 - 2 * inset)
		panel.Parent = gui
		holder = panel
	end
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.02, 0)
	list.Parent = holder
	for index, line in w.lines do
		local label = Instance.new("TextLabel")
		label.Name = `Line{index}`
		label.LayoutOrder = index
		label.Size = UDim2.fromScale(0.94, line.size)
		label.BackgroundTransparency = 1
		label.Font = FONTS[line.font or "Medium"] or Enum.Font.GothamMedium
		label.TextScaled = true
		label.Text = line.text
		label.TextColor3 = rgb(line.color)
		label.Parent = holder
	end
end

-- One set as a Model under `parent`: its pieces in its place's frame (MoveSiteLooks' rules for every flag), streamed
-- the `mode` way (nil: the default).
function MoveSites.build(parent: Instance, place: Looks.Place, pieces: { Looks.Piece }, name: string, mode: Enum.ModelStreamingMode?): Model
	local model = Instance.new("Model")
	model.Name = name
	if mode then
		model.ModelStreamingMode = mode
	end
	local frame = CFrame.new(place.x, place.y, place.z) * CFrame.Angles(0, math.rad(place.yaw), 0)
	for _, d in pieces do
		local p: BasePart = if d.shape == "Wedge" then Instance.new("WedgePart") else Instance.new("Part")
		p.Name = d.name
		p.Size = Vector3.new(d.size[1], d.size[2], d.size[3])
		local r = d.rotation or { 0, 0, 0 }
		p.CFrame = frame
			* CFrame.new(d.at[1], d.at[2], d.at[3])
			* CFrame.Angles(0, math.rad(d.yaw or 0), 0)
			* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		p.Color = rgb(d.color)
		p.Material = (Enum.Material :: any)[d.material]
		p.Anchored = true
		p.CanCollide = d.solid == true
		p.CanQuery = d.solid == true
		p.CanTouch = false
		p.CastShadow = Looks.shadow(d, place.y)
		p.Transparency = d.transparency or 0
		if p:IsA("Part") then
			if d.shape == "Cylinder" then
				p.Shape = Enum.PartType.Cylinder
			end
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
		end
		p.Parent = model
		local faces = d.words
		if faces then
			for _, w in faces do
				words(p, w, d.size)
			end
		end
		local glow = d.glow
		if d.light then
			local light = Instance.new("PointLight")
			light.Range = d.light
			light.Brightness = 1.2
			light.Color = rgb(glow or { 255, 224, 168 })
			light.Shadows = false
			light.Parent = p
			DayNight.nightLight(light)
		end
		if glow then
			DayNight.nightLight(p, rgb(glow), p.Color, d.material)
		end
	end
	model.Parent = parent
	return model
end

-- The first part of a model with this name (a set's own: MoveSiteLooks names are unique in a set).
local function named(model: Model, name: string): BasePart
	local found = model:FindFirstChild(name)
	assert(found and found:IsA("BasePart"), `MoveSites: no {name} in {model.Name}`)
	return found
end

-- 9.7 RUNS: the kiosk at any spot (the lobby's ZDC dispatch: SandboxMap.Lobby.dispatch), named `name` (Persistent:
-- always on every client); returns it and its corkboard ("Board").
function MoveSites.kiosk(parent: Instance, spot: SandboxMap.Spot, name: string): (Model, BasePart)
	local model = MoveSites.build(parent, { x = spot.x, y = spot.y, z = spot.z, yaw = spot.yaw }, Looks.board(), name, Enum.ModelStreamingMode.Persistent)
	local board = named(model, "Board")
	model.PrimaryPart = board
	return model, board
end

return MoveSites
