--!strict
-- 7.0, the moving rework's world (design/rework/NAVRH.md): builds shared/MoveSiteLooks.luau's set pieces as anchored
-- parts (Config.MoveSites), once, when server/Moving.luau starts. Only the pieces the looks mark solid collide and stop
-- bullets (the Wall's footings and panels, the posts, the booth, sandbags, jersey barriers, the army truck's hull, the
-- kiosk); the rest is decoration (CanCollide and CanQuery off). CanTouch off everywhere, no loops, no meshes: the lamps'
-- glass and their few PointLights go on at night through DayNight. Text is SurfaceGuis drawn within
-- MoveSiteLooks.textRange. Nothing stands in the truck's lane into the drop-off's bay, on a house's path from its door
-- to the truck's kerb or on the people's walk line round a block (tests/movesites_test.luau on the looks,
-- tools/move-sites/check.py on what this builds on the recorder; tools/move-sites/render.py draws it).
--
--   MoveSites.board(parent)           the "MovingBoard" kiosk at Config.Moving.Board (Persistent, by the spawn): returns
--                                     the model and its corkboard ("Board"), the part Moving hangs its prompt on
--   MoveSites.dropOff(parent)         the "MovingDropOff" model (Persistent): the Wall's checkpoint round the drop-off
--                                     (Config.Moving.DropOff; its bay the same 22 × 18 as before, Config.MoveSites.Bay)
--   MoveSites.house(model, title, home)  a contract's house dressed for moving day ("MovingDay" in its site's model: the
--                                     ZDC MOVING yard sign, boxes by the door, MOVING DAY over it, cones at the truck's
--                                     kerb, the EVACUATED realtor's sign); returns the yard sign
--   MoveSites.farm(model, title, placeId)   7.x farm move: Walt's farm at its place (Map.Places, turned with it: the
--                                     frame MoveSiteLooks.sitePlace): the farmhouse and the moving-day dress
--                                     ("MovingDay" in its site's model); returns the yard sign
--   MoveSites.dressing(parent)        the "MoveDressing" folder: the depot's ZDC MOVING & EVACUATION banner (Persistent)
--                                     and the city's evacuation spots (Atomic each)
--   MoveSites.build(parent, place, pieces, name, mode?)   one set as a Model (the others' builder)
--   8.0 SANDBOX (design/sandbox/KONTRAKT.md): no Wall, no dressing, no city house (no moving-day dress on the sandbox's
--   houses either: the countryside's six stand on the map as server/SandboxWorld.luau builds them, server/Moving.luau's SB.site
--   their doors and curbs); a kiosk on every player's plot:
--   MoveSites.plotBoard(parent, plot)    the "MovingBoard<id>" kiosk (Persistent) at the plot's board spot
--                                     (shared/SandboxMap.luau plot.board: by the warehouse's roller door, on its wall's
--                                     outside, facing out), half a stud farther out (its plinth against the wall), its
--                                     corkboard the sandbox's (MoveSiteLooks.board(true): the places to empty,
--                                     no Wall; each card shows its player's own house, server/Moving.luau SB.contractFor);
--                                     returns the model and its corkboard ("Board", the part Moving hangs its prompt
--                                     on; its attribute Plot = the plot's id)
--   MoveSites.plotBoardPlace(plot)    where that kiosk's foot stands (tools/move-sites/check.py checks it there)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared.MoveSiteLooks)
local Map = require(Shared.Map)
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

-- (Persistent by the spawn, like the depot's own counters: always on every client.)
function MoveSites.board(parent: Instance): (Model, BasePart)
	local model = MoveSites.build(parent, Looks.boardPlace(), Looks.board(), "MovingBoard", Enum.ModelStreamingMode.Persistent)
	local board = named(model, "Board")
	model.PrimaryPart = board
	return model, board
end

-- 8.0 SANDBOX: the kiosk's foot at a plot's board spot, moved PLOT_OUT studs out along the way it looks (its plinth's
-- back, 1.5 behind its foot, then rests against the warehouse's wall instead of in it).
local PLOT_OUT = 0.5
function MoveSites.plotBoardPlace(plot: SandboxMap.Plot): Looks.Place
	local spot = plot.board
	local yaw = math.rad(spot.yaw)
	return { x = spot.x - math.sin(yaw) * PLOT_OUT, y = spot.y, z = spot.z - math.cos(yaw) * PLOT_OUT, yaw = spot.yaw }
end

function MoveSites.plotBoard(parent: Instance, plot: SandboxMap.Plot): (Model, BasePart)
	local model = MoveSites.build(parent, MoveSites.plotBoardPlace(plot), Looks.board(true), `MovingBoard{plot.id}`, Enum.ModelStreamingMode.Persistent)
	local board = named(model, "Board")
	board:SetAttribute("Plot", plot.id)
	model.PrimaryPart = board
	return model, board
end

function MoveSites.dropOff(parent: Instance): Model
	local model = MoveSites.build(parent, Looks.checkpointPlace(), Looks.checkpoint(), "MovingDropOff", Enum.ModelStreamingMode.Persistent)
	model.PrimaryPart = named(model, "CheckpointSign")
	return model
end

function MoveSites.house(model: Model, title: string, home: Map.Home): BasePart
	local dressed = MoveSites.build(model, Looks.doorPlace(home), Looks.house(title, Looks.parkDepth(home)), "MovingDay")
	return named(dressed, "YardSign")
end

-- 7.x farm move: the farm's set, nil when its place is not on the map.
function MoveSites.farm(model: Model, title: string, placeId: string): BasePart?
	local place = Looks.sitePlace(placeId)
	if not place then
		return nil
	end
	local dressed = MoveSites.build(model, place, Looks.farm(title), "MovingDay")
	return named(dressed, "YardSign")
end

-- The banner Persistent like the depot it hangs on; each spot Atomic (it streams in whole, never half a pile).
function MoveSites.dressing(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "MoveDressing"
	MoveSites.build(folder, Looks.bannerPlace(), Looks.banner(), "DepotBanner", Enum.ModelStreamingMode.Persistent)
	for _, place in Looks.spotPlaces() do
		MoveSites.build(folder, place, Looks.spot(place.seed or 1), `EvacuationSpot{place.seed}`, Enum.ModelStreamingMode.Atomic)
	end
	folder.Parent = parent
	return folder
end

return MoveSites
