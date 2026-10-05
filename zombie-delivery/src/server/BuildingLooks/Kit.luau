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
		local material = Enum.Material[detail.material or "Metal"] :: Enum.Material
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
	return model
end

return Kit
