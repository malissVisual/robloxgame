--!strict
-- The vans. 10.6 (only the sandbox is the game): a player's one vehicle is the Deliveros Sprinter (Config.Sandbox.Van,
-- its numbers Config.Sprinter, its look and walk-in bay shared/SprinterLooks.luau), at most one in the world for each
-- player, built in code. Nobody drives (the 10.4 ride is the clients' animation, client/RideUi.luau): a van is parked
-- where it is put and anchored there; it has no seats, no movers and no health. The city's cars, bikes and scooters,
-- their driving, stages, upgrades, gear, roof guns, rentals, repairs and chauffeurs are gone with it.
--
-- Where vans stand: server/Runs.luau parks a run's van at its house's curb and each player's own van at a round's house
-- (Moving.parkVan: server/SandboxBoot.luau's parkVan → Vehicles.placeAt); server/Moving.luau's "Call the van to the
-- door" moves it (Vehicles.standUp); a van goes again with Vehicles.remove (the run's end, the player leaving).
-- 6.26, never into something: the room its hull needs is checked before it comes out and a free spot found near
-- (findRoom: shared/SpawnSpot.luau, Config.SpawnSpot): on the ground's plane under its four wheels.
--
-- The model (its PrimaryPart the "Chassis": its top is the bay's floor, 2.4 over the ground):
--   * the hull: hidden boxes that collide (SprinterLooks.hull: the cab, the nose, the bulkhead, the bay's walls and roof
--     round the hollow walk-in bay), the chassis and a hidden wheel collider at each wheel;
--   * its look (SprinterBuild.body: SprinterLooks' skin, the cab doors' skins, the back doors' and the sliding door's),
--     only looks (no mass, no collisions, not hit by rays), each with the attribute SprinterVisual: server/SprinterMesh
--     .luau hides them when it dresses the van in the owner's Blender model; the painted panels are Car.paintParts
--     (server/VanPaint.luau paints them through the hook Vehicles.onStyle, shared/VanLook.luau);
--   * the tyres on Motor6Ds "WheelMotor" (SprinterMesh puts its wheels on them);
--   * the back (3.2): two doors, each on a Motor6D "BackHinge" (C0 the hinge line, closed with no Transform; the
--     attributes Axis and Angle the open turn); the model's attribute BackOpen says where they are and every client
--     swings them there (client/CarVisuals.luau). The "BackPrompt" in the Attachment "CargoDoor" at the back opening's
--     middle opens and closes them (toggleBack): on foot, a hand free (empty hands, or one light piece: the character
--     attribute CarryHands = 1), the owner or whom the hook Vehicles.backAllowed lets (server/Moving.luau: the run's
--     party). The Load prompts sit in CargoDoor too (server/Moving.luau, server/Runs.luau);
--   * 8.0, the walk-in bay (SprinterBuild.wire): shut, the back doors' block keeps the bay closed; open, the rear step
--     folds out behind the bumper. The sliding door (its "SidePrompt": anybody on foot, so nobody is ever shut in; the
--     attribute SlideOpen) rolls back along the side on its Motor6D "SlideMotor" (the server tweens its C0: every client
--     sees it), its block goes and the side step comes out (both back once it has shut). The bay's light is on while
--     either stands open;
--   * the load: the pieces loaded ride welded to the chassis (Vehicles.cargoHolder) in its cargo slots
--     (Vehicles.cargoSlots, as many as Config.Cars' capacity: tests/run_tests.py counts them);
--   * the attributes OwnerId, OwnerName, CarId, Sprinter (the clients and SprinterMesh find a van by them).
--
--   Vehicles.placeAt(player, spot)      the player's van parked at `spot` (its middle there, facing its look; the old
--                                       one goes), on free ground near it: the Car (nil while the save loads)
--   Vehicles.spawnAt(player, ground)    the same at `ground` as it is given (on the ground, Drop over it)
--   Vehicles.get(player) / remove(player)
--   Vehicles.standUp(car, heading)      the van stood where it is on free ground, facing `heading` (the van called to
--                                       a door)
--   Vehicles.groundY(x, z, refY?)       the top of the ground there (a ray from above: no van, body or zombie)
--   Vehicles.cargoDoor / cargoSlots / cargoHolder, Vehicles.backPrompt / hasBack / backOpen / backVerb / setBack
--   Vehicles.carDef(id)                 a Config.Cars entry by its id (the van's name on the prompts)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local DayNight = require(script.Parent.DayNight) -- (only the lamps' day look: the game's day never turns)
local SpawnSpot = require(Shared.SpawnSpot) -- 6.26: a van never comes out into something (findRoom)
local RenderBudget = require(Shared.RenderBudget) -- 6.13.1: only the pieces big enough throw a shadow
local Sprinter = require(Shared.SprinterLooks)

-- 10.5 (the city's server/World.luau and shared/Map.luau went): the old road level (the ground's fallback where a ray
-- finds nothing) and the water's level (a ground ray looks 6 below it).
local ROAD_TOP = 0.4
local WATER_LEVEL = -3
local CHASSIS_HEIGHT = 1.2

export type Car = {
	owner: Player,
	id: string, -- its Config.Cars id (Config.Sandbox.Van)
	model: Model,
	chassis: Part, -- the PrimaryPart, anchored; its top is the bay's floor
	paintParts: { BasePart }, -- the painted panels (server/VanPaint.luau)
	size: Vector3, -- the hull: its width, its height over the chassis' bottom, its length
	wrecked: boolean, -- taken away (Vehicles.remove): out of the world (the name of old: a van is never wrecked now)
	ground: CFrame, -- where it was put down (the spot asked for, or the free one near it: findRoom)
}

local Vehicles = {}

local cars: { [Player]: Car } = {}

-- 6.12, set by server/VanPaint.luau: a van was built: its paint goes on. Never changes its collisions.
Vehicles.onStyle = function(_car: Car) end

-- Set by server/Moving.luau: may this player (not the owner) open and close the back of this van (the run's party)?
Vehicles.backAllowed = function(_player: Player, _car: Car): boolean
	return false
end

local DARK = Color3.fromRGB(34, 34, 38)

-- A box of the van, relative to the chassis' top centre (offset = its middle); kind: "glass" the cab, "body" the rest.
type Box = { size: Vector3, offset: Vector3, kind: string }

-- 3.2: one back door, relative to the chassis' top centre, closed.
type Leaf = {
	size: Vector3,
	center: Vector3,
	hinge: Vector3, -- a point on the hinge line
	axis: string, -- "Y": it swings out sideways
	angle: number, -- degrees of the open turn about the axis
}

-- A point of SprinterLooks (the van's frame: from the ground under its middle) in the chassis' top's frame.
local function point(at: { number }): Vector3
	return Vector3.new(at[1], at[2] - Sprinter.Top, at[3])
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The van's measures in the chassis' top's frame (front -Z): its hull boxes, its wheels, its back doors, its cargo.
local STYLE = (function()
	local boxes: { Box } = {}
	for _, b in Sprinter.hull() do
		table.insert(boxes, { size = Vector3.new(b.size[1], b.size[2], b.size[3]), offset = point(b.at), kind = b.kind })
	end
	local leaves: { Leaf } = {}
	for _, leaf in Sprinter.leaves() do
		table.insert(leaves, {
			size = Vector3.new(leaf.size[1], leaf.size[2], leaf.size[3]),
			center = point(leaf.center),
			hinge = point(leaf.hinge),
			axis = "Y",
			angle = leaf.angle,
		})
	end
	return {
		width = Sprinter.Width,
		length = Sprinter.Length,
		wheel = Config.Sprinter.Wheel, -- radius
		wheelWidth = 1,
		clearance = Config.Sprinter.Clearance, -- the chassis' bottom over the ground
		wheelAt = Vector2.new(Sprinter.Track, Sprinter.Axle), -- the wheels' x and z (±)
		boxes = boxes,
		leaves = leaves,
		door = point(Sprinter.CargoDoor), -- where you load at the back
		-- the cargo slots: the bottom middles of the pieces, facing the front (Config.Cars capacity of them)
		slots = {
			Vector3.new(-1.6, 0, -1.2),
			Vector3.new(1.6, 0, -1.2),
			Vector3.new(-1.6, 0, 2.2),
			Vector3.new(1.6, 0, 2.2),
			Vector3.new(-1.6, 0, 5.6),
			Vector3.new(1.6, 0, 5.6),
			Vector3.new(-1.6, 0, 9.0),
			Vector3.new(1.6, 0, 9.0),
		},
	}
end)()

-- A Config.Cars entry by its id (nil: none such).
function Vehicles.carDef(id: string): Config.CarDef?
	for _, def in Config.Cars do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- The van's own entry (Config.Sandbox.Van in Config.Cars).
local function vanDef(): Config.CarDef
	return Vehicles.carDef(Config.Sandbox.Van) or Config.Cars[1]
end

local function newPart(model: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "Car"
	p.CastShadow = RenderBudget.casts(size.X, size.Y, size.Z)
	p.Parent = model
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- ── The look (shared/SprinterLooks.luau) ───────────────────────────────────
-- One table: the module's top level stays small.
local SprinterBuild = {}

-- Pieces of the van's look (SprinterLooks, the van's frame) as parts under `parent`: no mass, no collisions, not hit by
-- rays, welded to `to` (nil: not welded). A "paint" piece is the van's colour (it joins paintParts); a lamp shows its
-- day look (server/DayNight.luau; the bay's own lamps follow its light, SprinterBuild.wire); a label on its front
-- face. FleetFinish as of old (tools/vehicle-preview reads it); SprinterVisual: only looks (server/SprinterMesh.luau
-- hides these when the owner's Blender model dresses the van).
function SprinterBuild.emit(parent: Instance, to: BasePart?, top: CFrame, pieces: { Sprinter.Piece }, color: Color3, paintParts: { BasePart }): { BasePart }
	local made: { BasePart } = {}
	for _, piece in pieces do
		local finish = Sprinter.Finish[piece.finish] or Sprinter.Finish.trim
		local s, a, r = piece.size, piece.at, piece.turn or { 0, 0, 0 }
		local p = Instance.new(if piece.shape == "Wedge" then "WedgePart" else "Part") :: BasePart
		p.Name = piece.name
		p.Size = Vector3.new(s[1], s[2], s[3])
		p.CFrame = top * CFrame.new(a[1], a[2] - Sprinter.Top, a[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		local own = finish.color
		p.Color = if own then rgb(own) else color
		p.Material = (Enum.Material :: any)[finish.material] :: Enum.Material
		p.Transparency = if piece.clear then 1 else finish.transparency or 0
		p.Reflectance = finish.reflectance or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.CollisionGroup = "Car"
		-- (the panels carry the van's shadow: no glass, no label plate, nothing thin on two sides)
		p.CastShadow = not piece.clear and finish.material ~= "Glass" and ((s[1] >= 0.6 and s[2] >= 0.6) or (s[1] >= 0.6 and s[3] >= 0.6) or (s[2] >= 0.6 and s[3] >= 0.6))
		if piece.shape == "Cylinder" then
			(p :: Part).Shape = Enum.PartType.Cylinder
		end
		p:SetAttribute("FleetFinish", if own then piece.finish else "paint")
		p:SetAttribute("SprinterVisual", true) -- (only looks: server/SprinterMesh.luau hides it under the Blender model)
		if own == nil then
			table.insert(paintParts, p)
		end
		local lit = finish.lit
		if lit and piece.name ~= Sprinter.Lamps then
			DayNight.nightLight(p, rgb(lit), p.Color, finish.material)
		end
		local text = piece.text
		if text then
			local gui = Instance.new("SurfaceGui")
			gui.Name = "FleetLabel"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 50
			gui.LightInfluence = 1
			-- 8.2 perf: drawn only near (Config.Performance's small text: a phone draws every SurfaceGui on its own)
			gui.MaxDistance = math.max(Config.Performance.SignRange, Config.Performance.SignPerStud * s[2])
			gui.Parent = p
			local textLabel = Instance.new("TextLabel")
			textLabel.Size = UDim2.fromScale(1, 1)
			textLabel.BackgroundTransparency = 1
			textLabel.Font = (Enum.Font :: any)[piece.font or "GothamBold"] :: Enum.Font
			textLabel.TextScaled = true
			textLabel.Text = text
			local ink = Sprinter.Finish[piece.ink or "trim"].color or { 32, 35, 38 }
			textLabel.TextColor3 = rgb(ink)
			textLabel.Parent = gui
		end
		p.Parent = parent
		if to then
			weld(to, p)
		end
		table.insert(made, p)
	end
	return made
end

-- The van's body: its skin and its cab doors' (shut for good: nobody gets in) on the chassis; the colliders its doors
-- switch (SprinterLooks.Switched: the shut doors' blocks, the fold-out steps; a new van shut); the sliding door
-- ("SideDoor") on the Motor6D "SlideMotor" (C0 shut; the server moves it: SprinterBuild.wire) with its "SidePrompt" and
-- the bay's ceiling light (working: a player's van; else the door welded shut, no prompt, no light).
function SprinterBuild.body(model: Model, chassis: Part, top: CFrame, color: Color3, paintParts: { BasePart }, working: boolean)
	local folder = Instance.new("Folder")
	folder.Name = "SprinterBody"
	folder:SetAttribute("SprinterVisual", true)
	folder.Parent = model
	SprinterBuild.emit(folder, chassis, top, Sprinter.body(), color, paintParts)
	for _, side in { -1, 1 } do
		SprinterBuild.emit(folder, chassis, top, Sprinter.door(side), color, paintParts)
	end
	for _, s in Sprinter.Switched do
		local finish = if s.finish then Sprinter.Finish[s.finish] else nil
		local own = finish and finish.color
		local p = newPart(model, s.name, Vector3.new(s.size[1], s.size[2], s.size[3]), top * CFrame.new(point(s.at)), if own then rgb(own) else color,
			if finish then (Enum.Material :: any)[finish.material] :: Enum.Material else Enum.Material.SmoothPlastic)
		p.Massless = true
		p.CanCollide = s.solid == "closed"
		p.Transparency = if finish and p.CanCollide then 0 else 1
		p:SetAttribute("SprinterDoor", s.door)
		p:SetAttribute("SprinterSolid", s.solid)
		p:SetAttribute("SprinterShown", finish ~= nil)
		weld(chassis, p)
	end
	local pieces = Sprinter.slider()
	local slide = SprinterBuild.emit(folder, nil, top, { pieces[1] }, color, paintParts)[1]
	slide:SetAttribute("FleetFinish", nil) -- (on its Motor6D, not welded: the fleet's audit asks a weld of a FleetFinish)
	SprinterBuild.emit(slide, slide, top, table.move(pieces, 2, #pieces, 1, {}), color, paintParts)
	if not working then
		weld(chassis, slide)
		return
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "SlideMotor"
	motor.Part0 = chassis
	motor.Part1 = slide
	motor.C0 = chassis.CFrame:ToObjectSpace(slide.CFrame)
	motor.Parent = chassis
	local at = Instance.new("Attachment")
	at.Name = "SlidePoint" -- (not "SideDoor": that is the door, SprinterMesh's door group)
	at.Position = Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + point(Sprinter.SidePrompt)
	at.Parent = chassis
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SidePrompt"
	prompt.ActionText = "Open side door"
	prompt.ObjectText = model.Name
	prompt.HoldDuration = Config.Cargo.HoldDuration
	prompt.MaxActivationDistance = Config.Sprinter.Slider.Reach
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = at
	model:SetAttribute("SlideOpen", false)
	local spot = Instance.new("Attachment")
	spot.Name = "BayLight"
	spot.Position = Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + point(Sprinter.Light)
	spot.Parent = chassis
	local tune = Config.SandboxLight.Van.Bay -- (8.3: the game's light, Config.SandboxLight)
	local light = Instance.new("PointLight")
	light.Name = "BayLight"
	light.Range = tune.Range
	light.Brightness = tune.Brightness
	light.Color = rgb(tune.Color)
	light.Shadows = true -- (the bay's walls keep it in; on only while a door stands open)
	light.Enabled = false
	light.Parent = spot
end

-- 3.2: the back doors (STYLE.leaves) with their skins (SprinterLooks.leaves' pieces). working (a player's van): each
-- hangs on a Motor6D "BackHinge" that the clients turn (client/CarVisuals.luau), else it is welded shut. The leaves
-- join paintParts.
function SprinterBuild.back(model: Model, chassis: Part, top: CFrame, working: boolean, color: Color3, paintParts: { BasePart })
	local specs = Sprinter.leaves()
	for index, leaf in STYLE.leaves do
		local p = newPart(model, "BackDoor", leaf.size, top * CFrame.new(leaf.center), color, Enum.Material.SmoothPlastic)
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p:SetAttribute("SprinterVisual", true) -- (the leaf is its door's panel: only looks)
		table.insert(paintParts, p)
		local spec = specs[index]
		if spec then
			SprinterBuild.emit(p, p, top, spec.pieces, color, paintParts)
		end
		if not working then
			weld(chassis, p)
			continue
		end
		-- Hinged, not welded: Part1 = chassis * C0 * Transform * C1:Inverse(), closed with no Transform.
		local hinge = Instance.new("Motor6D")
		hinge.Name = "BackHinge"
		hinge.Part0 = chassis
		hinge.Part1 = p
		hinge.C0 = CFrame.new(Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + leaf.hinge)
		hinge.C1 = CFrame.new(leaf.hinge - leaf.center)
		hinge:SetAttribute("Axis", leaf.axis)
		hinge:SetAttribute("Angle", leaf.angle)
		hinge.Parent = chassis
	end
end

type Built = { model: Model, chassis: Part, paintParts: { BasePart }, size: Vector3 }

-- Builds the van standing on `ground` (the ground under its middle, facing its LookVector), anchored. display: a
-- showroom model (the tools' previews: no prompts, no hinges, the doors welded shut).
local function build(def: Config.CarDef, color: Color3, ground: CFrame, display: boolean?): Built
	local style = STYLE
	local working = display ~= true
	local model = Instance.new("Model")
	model.Name = def.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("SprinterArt", true)
	model:SetAttribute("Sprinter", true) -- (server/SprinterMesh.luau: a sprinter to dress)

	local chassisY = style.clearance + CHASSIS_HEIGHT / 2
	local chassisCF = ground * CFrame.new(0, chassisY, 0)
	local chassis = newPart(model, "Chassis", Vector3.new(style.width - 0.4, CHASSIS_HEIGHT, style.length), chassisCF, DARK, Enum.Material.Metal)
	chassis.Anchored = true
	chassis:SetAttribute("SprinterVisual", true) -- (only looks under the Blender model's body)
	model.PrimaryPart = chassis
	local paintParts: { BasePart } = {}
	local top = chassisCF * CFrame.new(0, CHASSIS_HEIGHT / 2, 0)

	-- The hull: hidden, colliding (the walk-in bay's walls round its hollow bay; its floor the chassis' top).
	local height = CHASSIS_HEIGHT
	for _, b in style.boxes do
		local p = newPart(model, if b.kind == "glass" then "Cabin" else "Body", b.size, top * CFrame.new(b.offset), DARK, Enum.Material.SmoothPlastic)
		p.Massless = true
		p.Transparency = 1
		weld(chassis, p)
		height = math.max(height, CHASSIS_HEIGHT + b.offset.Y + b.size.Y / 2)
	end
	SprinterBuild.body(model, chassis, top, color, paintParts, working)
	SprinterBuild.back(model, chassis, top, working, color, paintParts)

	-- The wheels: a hidden collider (the van's solid there) and a tyre on a Motor6D "WheelMotor" (SprinterMesh's wheels go
	-- on it) with its hub and a spoke.
	local wheelY = style.wheel - chassisY
	local wx, wz = style.wheelAt.X, style.wheelAt.Y
	for _, offset in { Vector3.new(-wx, wheelY, -wz), Vector3.new(wx, wheelY, -wz), Vector3.new(-wx, wheelY, wz), Vector3.new(wx, wheelY, wz) } do
		local size = Vector3.new(style.wheelWidth, style.wheel * 2, style.wheel * 2)
		local collider = newPart(model, "WheelCollider", size, chassisCF * CFrame.new(offset), DARK, Enum.Material.Rubber)
		collider.Shape = Enum.PartType.Cylinder
		collider.Transparency = 1
		weld(chassis, collider)
		local tyre = newPart(model, "Tyre", size, chassisCF * CFrame.new(offset), Color3.fromRGB(24, 24, 24), Enum.Material.Rubber)
		tyre.Shape = Enum.PartType.Cylinder
		tyre.CanCollide = false
		tyre.CanQuery = false
		tyre.Massless = true
		local motor = Instance.new("Motor6D")
		motor.Name = "WheelMotor"
		motor.Part0 = chassis
		motor.Part1 = tyre
		motor.C0 = CFrame.new(offset)
		motor:SetAttribute("Front", offset.Z < 0)
		motor:SetAttribute("Radius", style.wheel)
		motor.Parent = chassis
		local hub = newPart(model, "Hub", Vector3.new(style.wheelWidth + 0.1, style.wheel, style.wheel), tyre.CFrame, Color3.fromRGB(170, 170, 170), Enum.Material.Metal)
		hub.Shape = Enum.PartType.Cylinder
		hub.CanCollide = false
		hub.CanQuery = false
		hub.Massless = true
		weld(tyre, hub)
		local spoke = newPart(model, "Spoke", Vector3.new(style.wheelWidth + 0.15, style.wheel * 1.6, 0.35), tyre.CFrame, Color3.fromRGB(90, 90, 90), Enum.Material.Metal)
		spoke.CanCollide = false
		spoke.CanQuery = false
		spoke.Massless = true
		weld(tyre, spoke)
	end

	local built: Built = { model = model, chassis = chassis, paintParts = paintParts, size = Vector3.new(style.width, height, style.length) }
	if not working then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CollisionGroup = "Default"
			end
		end
		return built
	end

	-- The cargo: the back opening (the Load prompts and the BackPrompt sit there).
	local door = Instance.new("Attachment")
	door.Name = "CargoDoor"
	door.Position = Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + style.door
	door.Parent = chassis
	local backPrompt = Instance.new("ProximityPrompt")
	backPrompt.Name = "BackPrompt"
	backPrompt.ActionText = "Open doors"
	backPrompt.ObjectText = def.name
	backPrompt.HoldDuration = Config.Cargo.HoldDuration
	backPrompt.MaxActivationDistance = 9
	backPrompt.RequiresLineOfSight = false
	backPrompt.KeyboardKeyCode = Enum.KeyCode.E
	backPrompt.Parent = door
	model:SetAttribute("BackOpen", false)
	return built
end

-- ── Cargo (server/Moving.luau) ──────────────────────────────────────────────

-- Where the loaded pieces ride, relative to the chassis: the bottom centre of a piece, facing the front.
function Vehicles.cargoSlots(_car: Car): { CFrame }
	local list = {}
	for _, slot in STYLE.slots do
		table.insert(list, CFrame.new(Vector3.new(0, CHASSIS_HEIGHT / 2, 0) + slot))
	end
	return list
end

-- The part a loaded piece is welded to: the chassis (the slots are relative to it).
function Vehicles.cargoHolder(car: Car): BasePart
	return car.chassis
end

-- The back of the van, where the Load prompts and the BackPrompt sit.
function Vehicles.cargoDoor(car: Car): Attachment?
	local door = car.chassis:FindFirstChild("CargoDoor")
	return if door and door:IsA("Attachment") then door else nil
end

-- ── The back that opens (3.2) ──────────────────────────────────────────────

-- The prompt that opens and closes the back; nil: gone with the van.
function Vehicles.backPrompt(car: Car): ProximityPrompt?
	local door = Vehicles.cargoDoor(car)
	local prompt = door and door:FindFirstChild("BackPrompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- Has this van a back that opens (it is in the world)?
function Vehicles.hasBack(car: Car): boolean
	return not car.wrecked and Vehicles.backPrompt(car) ~= nil
end

function Vehicles.backOpen(car: Car): boolean
	return car.model:GetAttribute("BackOpen") == true
end

-- "open the back doors" / "close the back doors" (opening: the way it goes now).
function Vehicles.backVerb(_car: Car, opening: boolean): string
	return `{if opening then "open" else "close"} the back doors`
end

-- Opens or closes the back (the clients swing it, client/CarVisuals.luau). Nothing happens without a back.
function Vehicles.setBack(car: Car, open: boolean)
	if not Vehicles.hasBack(car) or Vehicles.backOpen(car) == open then
		return
	end
	car.model:SetAttribute("BackOpen", open)
	local prompt = Vehicles.backPrompt(car)
	if prompt then
		prompt.ActionText = if open then "Close doors" else "Open doors"
	end
end

-- What the character holds in its hands (server/Moving.luau sets it), or nil.
local function carrying(character: Instance?): string?
	local value = character and character:GetAttribute("Carrying")
	return if type(value) == "string" then value else nil
end

-- The BackPrompt pressed: open or close it. On foot, a hand free (empty hands, or one light piece in them: the
-- character attribute CarryHands = 1), the owner or the run's party.
local function toggleBack(car: Car, player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if car.wrecked or not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local notice = Net.get("Notice")
	if player ~= car.owner and not Vehicles.backAllowed(player, car) then
		notice:FireClient(player, "This is not your van.")
		return
	end
	local open = Vehicles.backOpen(car)
	if carrying(character) and character:GetAttribute("CarryHands") ~= 1 then
		local verb = Vehicles.backVerb(car, not open)
		local count = character:GetAttribute("CarryCount")
		if type(count) == "number" and count >= 2 then
			notice:FireClient(player, `Hands full: put a piece down with G, then {verb} (E). Or a crew mate opens it for you.`)
		else
			notice:FireClient(player, `Your hands are full. Put it down (G), then {verb} (E).`)
		end
		return
	end
	Vehicles.setBack(car, not open)
end

-- 8.0, the walk-in bay: a player's van's doors (BackOpen, SlideOpen), steps and light. The back (its BackPrompt,
-- setBack): shut, the BackBlock keeps the bay closed; open, the rear step folds out (solid and shown) behind the bumper.
-- The sliding door (its SidePrompt: anybody on foot, so nobody is ever shut in; the attribute SlideOpen): it rolls
-- back along the side (the server moves its SlideMotor's C0: every client sees it), its block goes and the side step
-- comes out (both back once it has shut). The bay's light is on while either stands open.
function SprinterBuild.wire(car: Car)
	local model, chassis = car.model, car.chassis
	local switched: { BasePart } = {}
	local lamps: { BasePart } = {}
	local folded: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SprinterDoor") ~= nil then
			table.insert(switched, d)
		elseif d:IsA("BasePart") and d.Name == Sprinter.Lamps then
			table.insert(lamps, d)
		elseif d:IsA("BasePart") and d.Name == Sprinter.StepFolded then
			folded = d
		end
	end
	local spot = chassis:FindFirstChild("BayLight")
	local light = spot and spot:FindFirstChildOfClass("PointLight")
	local lampLit = rgb(Config.SandboxLight.Van.Bay.Color)
	local lampDim = if lamps[1] then lamps[1].Color else lampLit
	local slideShut = true -- (the side door is shut, not only on its way shut)
	local function sync()
		local back = model:GetAttribute("BackOpen") == true
		for _, p in switched do
			local open = if p:GetAttribute("SprinterDoor") == "back" then back else not slideShut
			local solid = (p:GetAttribute("SprinterSolid") == "open") == open
			p.CanCollide = solid
			if p:GetAttribute("SprinterShown") == true then
				p.Transparency = if solid then 0 else 1
			end
		end
		if folded and model:GetAttribute("SprinterMesh") == nil then -- (the Blender model hid it: left so)
			folded.Transparency = if back then 1 else 0
		end
		local lit = (back or not slideShut) and not car.wrecked
		if light and light.Parent then
			light.Enabled = lit
		end
		for _, lamp in lamps do
			lamp.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			lamp.Color = if lit then lampLit else lampDim
		end
	end
	model:GetAttributeChangedSignal("BackOpen"):Connect(sync)
	local motor = chassis:FindFirstChild("SlideMotor")
	local at = chassis:FindFirstChild("SlidePoint")
	local prompt = at and at:FindFirstChildOfClass("ProximityPrompt")
	if motor and motor:IsA("Motor6D") and prompt then
		local TweenService = game:GetService("TweenService")
		local _, move = Sprinter.slider()
		local shut = motor.C0
		local open = CFrame.new(move[1], 0, move[2]) * shut
		local seconds = Config.Sprinter.Slider.Seconds
		local turn = 0
		model:GetAttributeChangedSignal("SlideOpen"):Connect(function()
			local opening = model:GetAttribute("SlideOpen") == true
			prompt.ActionText = if opening then "Close side door" else "Open side door"
			TweenService:Create(motor, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = if opening then open else shut }):Play()
			turn += 1
			local mine = turn
			if opening then
				slideShut = false
				sync()
			else
				task.delay(seconds, function()
					if turn == mine and model.Parent then
						slideShut = true
						sync()
					end
				end)
			end
		end)
		prompt.Triggered:Connect(function(player: Player)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if car.wrecked or not character or not humanoid or humanoid.Health <= 0 then
				return
			end
			local opening = model:GetAttribute("SlideOpen") ~= true
			if carrying(character) and character:GetAttribute("CarryHands") ~= 1 then
				Net.get("Notice"):FireClient(player, `Your hands are full. Put it down (G), then {if opening then "open" else "close"} the side door (E).`)
			else
				model:SetAttribute("SlideOpen", opening)
			end
		end)
	end
	sync()
end

-- ── Placing a van ──────────────────────────────────────────────────────────

-- What a ray looking for the ground must not see: the vans, the people, the zombies.
local function groundIgnore(): { Instance }
	local list: { Instance } = {}
	for _, name in { "Cars", "Npcs", "Zombies", "Loot" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

-- The top of the ground at (x, z): a road, a yard, a floor (looking down from well above refY). Where nothing is
-- found: the old road level.
function Vehicles.groundY(x: number, z: number, refY: number?): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = groundIgnore()
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local top = math.max(refY or ROAD_TOP, ROAD_TOP) + 90
	local origin = Vector3.new(x, top, z)
	-- Look past what nothing stands on: a sign board, a beam, a steep face (a few tries down through them).
	for _ = 1, 5 do
		local hit = workspace:Raycast(origin, Vector3.new(0, WATER_LEVEL - 6 - origin.Y, 0), params)
		if not hit then
			break
		end
		local part = hit.Instance
		local broad = not part:IsA("BasePart") or part:IsA("Terrain") or math.min(part.Size.X, part.Size.Z) >= 3
		if hit.Normal.Y > 0.6 and broad then
			return if hit.Position.Y > WATER_LEVEL - 2 then hit.Position.Y else ROAD_TOP
		end
		origin = hit.Position - Vector3.new(0, 0.05, 0)
	end
	return ROAD_TOP
end

-- The van's four wheels where they touch the ground, in its own space (front left, front right, back left, back right).
local function wheelsOf(): { SpawnSpot.Wheel }
	local x, z = STYLE.wheelAt.X, STYLE.wheelAt.Y
	return { { x = -x, z = -z }, { x = x, z = -z }, { x = -x, z = z }, { x = x, z = z } }
end

-- 6.26, a van never comes out into something (Config.SpawnSpot, shared/SpawnSpot.luau): `ground` (on the ground under
-- its middle, Drop over it, facing its look) is tried first, then the spots near it in a small spiral. A spot is free
-- when the ground under its four wheels is one plane no steeper than Slope (rays; SpawnSpot.plane), nothing stands in
-- the way from the spot asked for at its hull's middle height (a ray: no van through a wall or a fence), and the room
-- its hull needs over that plane (from Lift up, Pad wider) holds nothing it would collide with (a box query in the
-- collision group "Car": the props, the walls, the other vans, a player's body; never a zombie or a corpse, which do
-- not collide with a car). `ignore`: the van itself. Returns the spot (Drop over its wheels' ground, tilted to its
-- plane, facing as asked) and whether it is free; none free: the spot asked for (on its plane when it has one; a
-- warning in Studio).
local function findRoom(ground: CFrame, ignore: { Instance }, what: string): (CFrame, boolean)
	local cfg = Config.SpawnSpot
	local style = STYLE
	local flat = Vector3.new(ground.LookVector.X, 0, ground.LookVector.Z)
	local look = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude
	local skip = groundIgnore()
	for _, item in ignore do
		table.insert(skip, item)
	end
	rays.FilterDescendantsInstances = skip
	rays.IgnoreWater = true
	rays.RespectCanCollide = true
	local path = RaycastParams.new() -- (the way there: only what stands, not the people and the vans)
	path.FilterType = Enum.RaycastFilterType.Exclude
	path.FilterDescendantsInstances = skip
	path.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local pass = table.clone(ignore)
	for _, where in cfg.Pass do -- (the loot: pushed along like the zombies; 8.0.1: the game's ground)
		local folder: Instance? = workspace
		for name in string.gmatch(where, "[^%.]+") do
			folder = if folder then folder:FindFirstChild(name) else nil
		end
		if folder and folder ~= workspace then
			table.insert(pass, folder)
		end
	end
	overlap.FilterDescendantsInstances = pass
	overlap.RespectCanCollide = true
	overlap.MaxParts = 1
	pcall(function()
		overlap.CollisionGroup = "Car" -- (what a van's hull collides with)
		path.CollisionGroup = "Car"
	end)
	local top = CHASSIS_HEIGHT
	for _, b in style.boxes do
		top = math.max(top, CHASSIS_HEIGHT + b.offset.Y + b.size.Y / 2)
	end
	top += style.clearance -- (the hull's top over its wheels' ground)
	local sx, sy, sz, cy = SpawnSpot.box(style.width, style.length, top, cfg.Lift, cfg.Pad)
	local along, across = SpawnSpot.steps(style.width, style.length, cfg.Gap)
	local why = "no ground under a wheel"
	local asked: CFrame? = nil -- the spot asked for on its ground's plane
	local from = ground.Position + Vector3.new(0, cy - cfg.Drop, 0) -- (the hull's middle there)
	for n, step in SpawnSpot.candidates(cfg.Tries, along, across, cfg.Across) do
		local at = ground.Position + look * step.along + right * step.across
		local frame = CFrame.lookAt(at, at + look)
		local points: { { number } } = {}
		for _, w in wheelsOf() do
			local spot = frame * Vector3.new(w.x, 0, w.z)
			local hit = workspace:Raycast(spot + Vector3.new(0, cfg.Probe / 2, 0), Vector3.new(0, -cfg.Probe, 0), rays)
			if not hit then
				break
			end
			table.insert(points, { hit.Position.X, hit.Position.Y, hit.Position.Z })
		end
		local even, whyNot, up, middle = SpawnSpot.plane(points, cfg.Spread, cfg.Slope)
		if not up or not middle then
			why = if n == 1 then whyNot else why
			continue
		end
		local lookOn, rightOn, upOn = SpawnSpot.frame(up, look.X, look.Z, true)
		local origin = Vector3.new(at.X, SpawnSpot.heightAt(up, middle, at.X, at.Z), at.Z)
		local onPlane = CFrame.fromMatrix(origin, Vector3.new(rightOn[1], rightOn[2], rightOn[3]), Vector3.new(upOn[1], upOn[2], upOn[3]),
			-Vector3.new(lookOn[1], lookOn[2], lookOn[3]))
		if n == 1 and up[2] >= math.cos(math.rad(cfg.Steepest)) then
			asked = onPlane -- (too steep or taken: it stands there on its wheels when nothing is free)
			from = (onPlane * CFrame.new(0, cy, 0)).Position
		end
		if not even then
			why = if n == 1 then whyNot else why
			continue
		elseif n > 1 then
			local to = (onPlane * CFrame.new(0, cy, 0)).Position
			local wall = workspace:Raycast(from, to - from, path)
			if wall then
				continue -- (a wall, a fence between: not through it)
			end
		end
		local hit = workspace:GetPartBoundsInBox(onPlane * CFrame.new(0, cy, 0), Vector3.new(sx, sy, sz), overlap)
		if #hit > 0 then
			why = if n == 1 then `{hit[1]:GetFullName()} in the way` else why
			continue
		end
		if n > 1 and RunService:IsStudio() then
			print(string.format("[Vehicles] %s: %s at the spot asked for; put %.0f studs along the way it faces, %.0f to its right (try %d)", what, why, step.along, step.across, n))
		end
		return onPlane * CFrame.new(0, cfg.Drop, 0), true
	end
	if RunService:IsStudio() then
		warn(`[Vehicles] {what}: no free spot in {cfg.Tries} tries ({why} at the spot asked for): put there anyway`)
	end
	return if asked then asked * CFrame.new(0, cfg.Drop, 0) else ground, false
end

function Vehicles.get(player: Player): Car?
	local car = cars[player]
	if car and not car.wrecked then
		return car
	end
	return nil
end

-- The player's van leaves the world (a run's end, a new van, leaving the game).
function Vehicles.remove(player: Player)
	local car = cars[player]
	if car then
		cars[player] = nil
		car.wrecked = true
		car.model:Destroy()
	end
end

-- Builds the player's van standing at `ground` (its position on the ground, Drop over it, facing its LookVector: on
-- free ground near it, findRoom) and makes it theirs; the old one goes. Anchored with its wheels on the ground. Returns
-- nil while the save is not loaded.
function Vehicles.spawnAt(player: Player, ground: CFrame): Car?
	if not PlayerData.get(player) then
		return nil
	end
	local def = vanDef()
	Vehicles.remove(player)
	local spot = findRoom(ground, {}, `{player.Name}'s {def.name}`)
	local stands = spot * CFrame.new(0, -Config.SpawnSpot.Drop, 0) -- (anchored: on its wheels, not dropped onto them)
	local built = build(def, rgb(def.color), stands)
	local car: Car = {
		owner = player,
		id = def.id,
		model = built.model,
		chassis = built.chassis,
		paintParts = built.paintParts,
		size = built.size,
		wrecked = false,
		ground = stands,
	}
	car.model.Name = `{player.DisplayName}'s {def.name}`
	car.model:SetAttribute("OwnerId", player.UserId)
	car.model:SetAttribute("OwnerName", player.DisplayName)
	car.model:SetAttribute("CarId", def.id)
	Vehicles.onStyle(car) -- 8.3: its paint (server/VanPaint.luau)
	local backPrompt = Vehicles.backPrompt(car)
	if backPrompt then
		backPrompt.Triggered:Connect(function(by: Player)
			toggleBack(car, by)
		end)
	end
	SprinterBuild.wire(car) -- 8.0: the walk-in bay's doors, steps and light
	car.model.Parent = workspace:FindFirstChild("Cars") or workspace
	cars[player] = car
	return car
end

-- The player's van parked at `spot` (its middle on the ground there, facing the spot's look; the old one goes).
-- Returns the van, or nil while the save loads.
function Vehicles.placeAt(player: Player, spot: CFrame): Car?
	local look = Vector3.new(spot.LookVector.X, 0, spot.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, 1)
	Vehicles.remove(player) -- (the old van is not in the way)
	local at = spot.Position
	local position = Vector3.new(at.X, Vehicles.groundY(at.X, at.Z, at.Y) + Config.SpawnSpot.Drop, at.Z)
	return Vehicles.spawnAt(player, CFrame.lookAt(position, position + look))
end

-- 6.26: the van stood where it is (the ground right under it: not a bridge or a roof over it), facing `heading` (flat),
-- tilted to the plane of the ground under its four wheels, nudged to free room when something is where it stands
-- (findRoom). server/Moving.luau's "Call the van to the door" moves it so.
function Vehicles.standUp(car: Car, heading: Vector3)
	if car.wrecked or not car.chassis.Parent then
		return
	end
	local at = car.chassis.Position
	local flat = Vector3.new(heading.X, 0, heading.Z)
	local look = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local drop = Config.SpawnSpot.Drop
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip = groundIgnore()
	table.insert(skip, car.model)
	params.FilterDescendantsInstances = skip
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local under = workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -30, 0), params)
	local asked = Vector3.new(at.X, (if under then under.Position.Y else Vehicles.groundY(at.X, at.Z, at.Y)) + drop, at.Z)
	local spot = findRoom(CFrame.lookAt(asked, asked + look), { car.model }, car.model.Name)
	car.ground = spot * CFrame.new(0, -drop, 0)
	car.model:PivotTo(car.ground * CFrame.new(0, STYLE.clearance + CHASSIS_HEIGHT / 2, 0))
end

function Vehicles.start()
	Players.PlayerRemoving:Connect(function(player)
		Vehicles.remove(player)
	end)
end

-- (tests/run_tests.py and the tools' previews stage this module with its build, STYLE and wheelsOf exported.)
return Vehicles
