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
