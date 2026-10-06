--!strict
-- Static, non-blocking architectural details. Blueprints are pure data; World keeps gameplay geometry and prompts.
local Kit = {}

export type Triple = { number }
export type Detail = {
	name: string,
	position: Triple,
	size: Triple,
	color: Triple,
	material: string?,
	rotation: Triple?,
	transparency: number?,
	shape: string?,
	label: string?,
	textColor: Triple?,
	night: boolean?,
	beam: number?,
}
export type Blueprint = {
	id: string,
	width: number,
	depth: number,
	height: number,
	details: { Detail },
	-- The front openings that must stay clear (tools/check-building-looks.py): { center x, width, clear height } each.
	entries: { { number } }?,
	-- 4.3: an open hall you look into (the depot, bays, docks, garages): warm ceiling panels with light that are on day
	-- and night, so the inside reads instead of a black box. The panels are not details (no part budget).
	interior: boolean?,
}
export type Context = {
	part: (Instance, string, Vector3, CFrame, Color3, Enum.Material?) -> Part,
	deco: (Part) -> Part,
	nightLight: (Instance, Color3?, Color3?, string?) -> (),
}

-- 5.3, the storefronts of Map.Venues (server/World.luau buildVenue): every one is a 30 x 24 x 12 shop (Map.VenueSize)
-- with a 9-wide, 8-tall door in the middle of its front (World's building() makes the shell, the name board stands on
-- the parapet above the awning). The shared front: two shop windows that glow at night (framed, a sill, a head), the door
-- jambs and header, corner piers, a sloping awning in the kind's colours with its valance and a light under it, the
-- counter and the menu board inside, a plate on the right window, a roof unit and the doorstep. A kind adds its own
-- `extras` (a chimney, a giant burger, lanterns, a mailbox ...). Pure data: a blueprint like the others.
export type Storefront = {
	id: string,
	awning: Triple,
	stripe: Triple, -- the awning's stripes and valance
	trim: Triple, -- the window and door frames
	counter: Triple,
	menu: string, -- the board behind the counter
	poster: string, -- the glowing plate on the right window
	extras: { Detail },
}
Kit.StoreWidth, Kit.StoreDepth, Kit.StoreHeight, Kit.StoreDoor, Kit.StoreDoorHeight = 30, 24, 12, 9, 8

function Kit.storefront(spec: Storefront): Blueprint
	local front = -Kit.StoreDepth / 2 -- the front wall's outer face (z)
	local details: { Detail } = {}
	local function add(detail: Detail)
		table.insert(details, detail)
	end
	local dark, glass = { 34, 44, 52 }, { 40, 52, 60 }
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		add({ name = "ShopWindow" .. tag, position = { side * 9.6, 4.6, front - 0.11 }, size = { 8, 5.4, 0.2 }, color = glass, material = "Glass", night = true })
		add({ name = "WindowSill" .. tag, position = { side * 9.6, 1.75, front - 0.3 }, size = { 8.6, 0.3, 0.6 }, color = spec.trim, material = "Concrete" })
		add({ name = "WindowHead" .. tag, position = { side * 9.6, 7.45, front - 0.25 }, size = { 8.6, 0.3, 0.5 }, color = spec.trim, material = "Metal" })
		add({ name = "DoorJamb" .. tag, position = { side * 4.8, 4, front - 0.25 }, size = { 0.5, 8, 0.5 }, color = spec.trim, material = "Metal" })
		add({ name = "CornerPier" .. tag, position = { side * 14.55, 6, front - 0.3 }, size = { 0.9, 12, 0.6 }, color = spec.trim, material = "Concrete" })
	end
	add({ name = "DoorHeader", position = { 0, 8.25, front - 0.25 }, size = { 10.1, 0.5, 0.5 }, color = spec.trim, material = "Metal" })
	-- The awning slopes down to the street (its lowest edge 8.7 over the walk), the valance hangs from its front edge.
	add({ name = "Awning", position = { 0, 9.4, front - 1.9 }, size = { 30, 0.3, 4 }, color = spec.awning, material = "SmoothPlastic", rotation = { -15, 0, 0 } })
	for n, x in { -7.5, 7.5 } do
		add({ name = "AwningStripe" .. n, position = { x, 9.4, front - 1.9 }, size = { 3.4, 0.34, 4 }, color = spec.stripe, material = "SmoothPlastic", rotation = { -15, 0, 0 } })
	end
	add({ name = "Valance", position = { 0, 8.5, front - 3.75 }, size = { 30, 0.7, 0.1 }, color = spec.stripe, material = "SmoothPlastic" })
	add({ name = "AwningLight", position = { 0, 8.75, front - 0.6 }, size = { 6, 0.15, 0.5 }, color = { 184, 172, 146 }, material = "Glass", night = true, beam = 18 })
	add({ name = "WindowPlate", position = { 9.6, 6.55, front - 0.25 }, size = { 4, 0.9, 0.08 }, color = dark, material = "Glass", night = true, label = spec.poster, textColor = { 255, 214, 120 } })
	add({ name = "Doorstep", position = { 0, 0.1, front - 0.9 }, size = { 10, 0.2, 1.6 }, color = { 120, 120, 118 }, material = "Concrete" })
	-- Inside: the counter across the back, the menu board on the back wall, a shelf on the left wall.
	add({ name = "Counter", position = { -2, 1.9, 4 }, size = { 14, 3.8, 2.6 }, color = spec.counter, material = "Wood" })
	add({ name = "CounterTop", position = { -2, 3.9, 4 }, size = { 14.6, 0.2, 3 }, color = { 200, 200, 196 }, material = "SmoothPlastic" })
	add({ name = "MenuBoard", position = { 0, 7.4, 10.9 }, size = { 12, 2.6, 0.15 }, color = dark, material = "Metal", label = spec.menu })
	add({ name = "Shelf", position = { -13.9, 5, 2 }, size = { 1.2, 0.25, 10 }, color = spec.counter, material = "Wood" })
	add({ name = "RoofUnit", position = { 9, 13, 7 }, size = { 4, 2, 3 }, color = { 120, 122, 124 }, material = "Metal" })
	for _, extra in spec.extras do
		add(extra)
	end
	return {
		id = spec.id,
		width = Kit.StoreWidth,
		depth = Kit.StoreDepth,
		height = Kit.StoreHeight,
		details = details,
		entries = { { 0, Kit.StoreDoor, Kit.StoreDoorHeight } },
	}
end

function Kit.build(parent: Instance, frame: CFrame, blueprint: Blueprint, context: Context): Folder
	-- Builders call once. No Heartbeat, scans, asset downloads or changes to existing instances.
	local model = Instance.new("Folder")
	model.Name = "Architecture"
	model:SetAttribute("Building", blueprint.id)
	model:SetAttribute("DetailCount", #blueprint.details)
	model.Parent = parent
	for _, detail in blueprint.details do
		local p, s, c = detail.position, detail.size, detail.color
		local rotation = detail.rotation or { 0, 0, 0 }
		local pose = frame * CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(math.rad(rotation[1]), math.rad(rotation[2]), math.rad(rotation[3]))
		local material = (Enum.Material :: any)[detail.material or "Metal"] :: Enum.Material
		local item = context.deco(context.part(model, detail.name, Vector3.new(s[1], s[2], s[3]), pose, Color3.fromRGB(c[1], c[2], c[3]), material))
		item.CanTouch = false
		item.CastShadow = detail.transparency == nil and detail.label == nil
		item.Transparency = detail.transparency or 0
		if detail.shape == "Cylinder" then
			item.Shape = Enum.PartType.Cylinder
		end
		if detail.label then
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Wayfinding"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.LightInfluence = 0.15
			gui.Parent = item
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Text = detail.label
			text.TextScaled = true
			text.Font = Enum.Font.GothamMedium
			local ink = detail.textColor or { 232, 234, 232 }
			text.TextColor3 = Color3.fromRGB(ink[1], ink[2], ink[3])
			text.Parent = gui
		end
		if detail.night then
			local warm = Color3.fromRGB(255, 228, 187)
			if detail.beam then
				local lamp = Instance.new("PointLight")
				lamp.Range = detail.beam
				lamp.Brightness = 0.8
				lamp.Color = warm
				lamp.Shadows = false
				lamp.Parent = item
			end
			context.nightLight(item, warm, item.Color, "Glass")
		end
	end
	if blueprint.interior then
		-- One panel (two in a wide hall) under the ceiling, a little in from the front; a SurfaceLight shines down
		-- only, so nothing spills onto the roof or through it.
		local count = if blueprint.width >= 48 then 2 else 1
		local span = blueprint.width / count
		local y = blueprint.height - 1.1
		for n = 1, count do
			local x = -blueprint.width / 2 + span * (n - 0.5)
			local pose = frame * CFrame.new(x, y, -blueprint.depth * 0.1)
			local panel = context.deco(context.part(model, `InteriorLight{n}`, Vector3.new(math.min(span * 0.5, 14), 0.2, 1.4), pose, Color3.fromRGB(255, 236, 205), Enum.Material.Neon))
			panel.CanTouch = false
			panel.CastShadow = false
			local glow = Instance.new("SurfaceLight")
			glow.Face = Enum.NormalId.Bottom
			glow.Angle = 150
			glow.Range = math.clamp(blueprint.height + 12, 20, 40)
			glow.Brightness = 2
			glow.Color = Color3.fromRGB(255, 228, 187)
			glow.Shadows = false
			glow.Parent = panel
		end
	end
	return model
end

return Kit
