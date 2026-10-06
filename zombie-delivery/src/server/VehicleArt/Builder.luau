--!strict
-- Weld the fleet's real geometry to its chassis, animated doors or tyres. Physics and progression stay in Vehicles.
local Geometry = require(script.Parent.Geometry)
local Builder = {}
type Box = { size: Vector3, offset: Vector3, kind: string }
type Leaf = { size: Vector3, center: Vector3 }
type Style = {
	width: number, length: number, wheel: number, wheelWidth: number, clearance: number, roof: number,
	boxes: { Box }, seat: Vector3, head: Vector2?, back: { leaves: { Leaf } }?, bald: boolean?,
}
type Context = {
	weld: (BasePart, BasePart) -> (), nightLight: (Instance, Color3?, Color3?, string?) -> (),
}
local SUPPORTED: { [string]: boolean } = { van = true, courier = true, highroof = true, boxtruck = true, armorvan = true, rallyvan = true, freighttruck = true, pickup = true, muscle = true }
local COLORS: { [string]: Color3 } = {
	dark = Color3.fromRGB(27, 32, 35), steel = Color3.fromRGB(151, 163, 166), glass = Color3.fromRGB(50, 72, 77),
	red = Color3.fromRGB(163, 47, 40), amber = Color3.fromRGB(206, 132, 48), white = Color3.fromRGB(217, 218, 207),
	wood = Color3.fromRGB(123, 101, 73), tyre = Color3.fromRGB(24, 26, 27), rust = Color3.fromRGB(116, 63, 36),
	primer = Color3.fromRGB(119, 125, 119), mirror = Color3.fromRGB(178, 190, 191), lamp = Color3.fromRGB(206, 202, 180),
	armor = Color3.fromRGB(67, 77, 79), tread = Color3.fromRGB(58, 60, 62),
}
local LIT_WARM, LIT_AMBER = Color3.fromRGB(255, 228, 182), Color3.fromRGB(255, 166, 52)
function Builder.supports(id: string): boolean return SUPPORTED[id] == true end
local function triple(v: Vector3): Geometry.V return { v.X, v.Y, v.Z } end
function Builder.profile(id: string, stage: number, style: Style): Geometry.Profile
	local glass: Box? = nil
	local hood: Box? = nil
	for _, b in style.boxes do
		if b.kind == "glass" and (glass == nil or b.offset.Z < (glass :: Box).offset.Z) then glass = b end
		if b.kind == "body" and b.size.X >= style.width * .7 and (hood == nil or b.offset.Z - b.size.Z / 2 < (hood :: Box).offset.Z - (hood :: Box).size.Z / 2) then hood = b end
	end
	assert(glass and hood, "Owned fleet needs its original cab and hood geometry")
	local g, h = glass :: Box, hood :: Box
	local cabBack = g.offset.Z + g.size.Z / 2
	local cabTop = g.offset.Y + g.size.Y / 2
	for _, b in style.boxes do
		if b.kind == "body" and b.size.X >= g.size.X * .8 and b.size.Z >= g.size.Z * .75 and math.abs(b.offset.Z - g.offset.Z) < g.size.Z * .5 and b.offset.Y >= cabTop - .3 then
			cabTop = math.max(cabTop, b.offset.Y + b.size.Y / 2)
		end
	end
	local cargo: Box? = nil
	for _, b in style.boxes do
		if b.kind == "body" and b.size.X >= style.width * .8 and b.offset.Z > cabBack - .5 then
			if cargo == nil or b.size.X * b.size.Y * b.size.Z > (cargo :: Box).size.X * (cargo :: Box).size.Y * (cargo :: Box).size.Z then cargo = b end
		end
	end
	local rear = if cargo then (cargo :: Box).offset.Z + (cargo :: Box).size.Z / 2 else style.length / 2
	local cargoTop = if cargo then (cargo :: Box).offset.Y + (cargo :: Box).size.Y / 2 else h.offset.Y + h.size.Y / 2
	if id == "pickup" then cargoTop = 1.6; rear = style.length / 2 - .1 end
	if id == "van" and stage >= 3 then cargoTop = 6.3 end
	-- The back's leaves: the lowest edge of the upright ones (the rear face's sill) and a lid's span (lying flat).
	local sill: number? = nil
	local lidFront: number?, lidBack: number? = nil, nil
	local leaves: { Leaf } = if style.back then style.back.leaves else {}
	for _, leaf in leaves do
		if leaf.size.Y < leaf.size.Z then
			lidFront, lidBack = leaf.center.Z - leaf.size.Z / 2, leaf.center.Z + leaf.size.Z / 2
		end
		sill = math.min(sill or math.huge, leaf.center.Y - leaf.size.Y / 2)
	end
	return {
		id = id, stage = stage, width = style.width, length = style.length, wheel = style.wheel, wheelWidth = style.wheelWidth,
		wheelY = style.wheel - style.clearance - 1.2, seatY = style.seat.Y, seatZ = style.seat.Z,
		headY = if style.head then style.head.X else 1.2, headZ = if style.head then style.head.Y else -style.length / 2 - .05, cabWidth = g.size.X, cabFront = g.offset.Z - g.size.Z / 2,
		cabBack = cabBack, cabTop = cabTop, windowTop = math.min(g.offset.Y + g.size.Y / 2, cabTop - .3), hoodTop = h.offset.Y + h.size.Y / 2,
		cargoFront = if cargo then (cargo :: Box).offset.Z - (cargo :: Box).size.Z / 2 else cabBack,
		cargoBack = rear, cargoTop = cargoTop, roof = style.roof, sill = sill, lidFront = lidFront, lidBack = lidBack,
	}
end
local function emit(parent: Instance, to: BasePart, frame: CFrame, pieces: { Geometry.Piece }, paint: Color3, paintParts: { BasePart }, context: Context)
	for _, piece in pieces do
		local p = Instance.new(if piece.shape == "Wedge" then "WedgePart" else "Part") :: BasePart
		local s, v, r = piece.size, piece.at, piece.turn or { 0, 0, 0 }
		p.Name = piece.name
		p.Size = Vector3.new(s[1], s[2], s[3])
		p.CFrame = frame * CFrame.new(v[1], v[2], v[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		p.Color = if piece.finish == "paint" then paint else COLORS[piece.finish] or COLORS.dark
		p.Material = if piece.finish == "glass" or piece.finish == "lamp" or piece.finish == "amber" then Enum.Material.Glass elseif piece.finish == "tyre" or piece.finish == "tread" then Enum.Material.Rubber elseif piece.finish == "rust" then Enum.Material.CorrodedMetal elseif piece.finish == "wood" then Enum.Material.WoodPlanks elseif piece.finish == "paint" or piece.finish == "primer" then Enum.Material.SmoothPlastic else Enum.Material.Metal
		p.Transparency = if piece.finish == "glass" then .28 else 0
		p.Reflectance = if piece.finish == "mirror" then .35 elseif piece.finish == "steel" then .08 else 0
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.CollisionGroup = "Car"
		-- Glass, strips, rods and small trim cast no shadow (two sides under 0.6): the panels carry the car's shadow.
		local a, b, c = s[1], s[2], s[3]
		p.CastShadow = piece.finish ~= "glass" and (a >= .6 and b >= .6 or a >= .6 and c >= .6 or b >= .6 and c >= .6)
		if piece.shape == "Cylinder" then (p :: Part).Shape = Enum.PartType.Cylinder end
		p:SetAttribute("FleetFinish", piece.finish)
		p.Parent = parent
		context.weld(to, p)
		if piece.finish == "paint" then table.insert(paintParts, p) end
		if piece.finish == "lamp" or piece.finish == "amber" then context.nightLight(p, if piece.finish == "amber" then LIT_AMBER else LIT_WARM, p.Color, "Glass") end
		if piece.text then
			local gui = Instance.new("SurfaceGui")
			gui.Name, gui.Face, gui.SizingMode, gui.PixelsPerStud = "FleetLabel", Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 60
			gui.LightInfluence = .2
			gui.Parent = p
			local text = Instance.new("TextLabel")
			text.Size, text.BackgroundTransparency = UDim2.fromScale(1, 1), 1
			text.Font, text.TextScaled, text.Text, text.TextColor3 = Enum.Font.GothamMedium, true, piece.text, COLORS.white
			text.Parent = gui
		end
	end
end
-- doors: the cab doors' z spans (the waist line and the mirrors keep clear of them).
function Builder.body(model: Model, chassis: BasePart, top: CFrame, style: Style, color: Color3, paintParts: { BasePart }, context: Context, doors: { Geometry.DoorSpan }?)
	local folder = Instance.new("Folder"); folder.Name = "FleetBody"; folder.Parent = model
	local profile = Builder.profile(model:GetAttribute("FleetStyle") :: string, model:GetAttribute("FleetStage") :: number, style)
	profile.doors = doors
	emit(folder, chassis, top, Geometry.body(profile), color, paintParts, context)
end
function Builder.door(model: Model, panel: BasePart, style: Style, side: number, color: Color3, paintParts: { BasePart }, context: Context)
	local profile = Builder.profile(model:GetAttribute("FleetStyle") :: string, model:GetAttribute("FleetStage") :: number, style)
	local top = (model.PrimaryPart :: BasePart).CFrame * CFrame.new(0, .6, 0)
	local panelTop = top:PointToObjectSpace(panel.Position).Y + panel.Size.Y / 2
	emit(panel, panel, panel.CFrame, Geometry.door(triple(panel.Size), side, profile.windowTop, panelTop, math.max(0, math.abs(top:PointToObjectSpace(panel.Position).X) - profile.cabWidth / 2)), color, paintParts, context)
end
function Builder.rear(panel: BasePart, color: Color3, paintParts: { BasePart }, context: Context)
	emit(panel, panel, panel.CFrame, Geometry.rear(triple(panel.Size)), color, paintParts, context)
end
-- The look a Tyres & Suspension level gives: 0 the stock steel wheel, 1 new tyres (tread rings), 3 alloy rims too.
local function tyreTier(handling: number): number
	return if handling >= 3 then 3 elseif handling >= 1 then 1 else 0
end
-- Dresses one tyre (in its folder FleetWheel). The tyre's attributes FleetSide (-1 left, 1 right: its outer face) and
-- FleetInner (a twin tyre inside another: no rim) come from Vehicles; FleetTyres keeps the tier it was dressed for.
function Builder.wheel(tyre: BasePart, handling: number, context: Context)
	local tier = tyreTier(handling)
	local old = tyre:FindFirstChild("FleetWheel"); if old then old:Destroy() end
	local folder = Instance.new("Folder"); folder.Name = "FleetWheel"; folder.Parent = tyre
	local side = if tyre:GetAttribute("FleetSide") == -1 then -1 else 1
	emit(folder, tyre, tyre.CFrame, Geometry.wheel(tyre.Size.X, tyre.Size.Y / 2, tier >= 3, side, tyre:GetAttribute("FleetInner") ~= true, tier >= 1), COLORS.steel, {}, context)
	-- The rim and tread lie inside the tyre's own shadow.
	for _, p in folder:GetChildren() do if p:IsA("BasePart") then p.CastShadow = false end end
	if tier >= 1 then tyre.Color = COLORS.tyre end
	tyre:SetAttribute("FleetTyres", tier)
end
-- A kit change dresses again only the tyres whose look changes (the wheels are built once with the car).
function Builder.fitTyres(model: Model, handling: number, context: Context)
	local tier = tyreTier(handling)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name == "Tyre" and p:GetAttribute("FleetTyres") ~= tier then Builder.wheel(p, handling, context) end
	end
end
function Builder.upgrades(model: Model, chassis: BasePart, style: Style, folder: Instance, plow: number, armor: number, engine: number, context: Context)
	local profile = Builder.profile(model:GetAttribute("FleetStyle") :: string, model:GetAttribute("FleetStage") :: number, style)
	emit(folder, chassis, chassis.CFrame * CFrame.new(0, .6, 0), Geometry.upgrades(profile, plow, armor, engine), COLORS.steel, {}, context)
end
return Builder
