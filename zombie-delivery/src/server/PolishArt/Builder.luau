--!strict
-- Native static/welded polish-art renderer. Geometry supplies collision, named text slots and mount points;
-- callers retain prompts, placement and gameplay, and pass DayNight.nightLight for nighttime registration.
local Builder = {}
export type Triple = { number }
export type TextSlot = { name: string, text: string, at: { number }?, size: { number }? }
export type Piece = {
	name: string, size: Triple, at: Triple, color: Triple, rotation: Triple?, material: string?,
	shape: string?, solid: boolean?, query: boolean?, night: boolean?, shadow: boolean?, transparency: number?,
	lineColor: boolean?, slots: { TextSlot }?, light: number?,
}
export type Mount = { name: string, attach: string, at: Triple }
export type Spec = { id: string, pieces: { Piece }, attachments: { Mount }? }
export type Options = { weldTo: BasePart?, lineColor: Color3?, nightLight: ((Instance, Color3?, Color3?, string?) -> ())? }

function Builder.build(parent: Instance, frame: CFrame, spec: Spec, options: Options?): Model
	local opt = options or {}
	local model = Instance.new("Model")
	model.Name = spec.id
	local parts: { [string]: BasePart } = {}
	for _, d in spec.pieces do
		local p: BasePart = if d.shape == "Wedge" then Instance.new("WedgePart") elseif d.shape == "Truss" then Instance.new("TrussPart") else Instance.new("Part")
		p.Name = d.name
		p.Size = Vector3.new(d.size[1], d.size[2], d.size[3])
		local r = d.rotation or { 0, 0, 0 }
		p.CFrame = frame * CFrame.new(d.at[1], d.at[2], d.at[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		p.Color = if d.lineColor and opt.lineColor then opt.lineColor else Color3.fromRGB(d.color[1], d.color[2], d.color[3])
		p.Material = (Enum.Material :: any)[d.material or "Metal"]
		p.Anchored = opt.weldTo == nil
		p.Massless = true
		p.CanCollide = opt.weldTo == nil and d.solid == true
		p.CanQuery = opt.weldTo == nil and d.query == true
		p.CanTouch = false
		p.CastShadow = d.shadow == true
		p.Transparency = d.transparency or 0
		if p:IsA("Part") then
			if d.shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder elseif d.shape == "Ball" then p.Shape = Enum.PartType.Ball end
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		end
		p.Parent = model
		parts[d.name] = p
		if opt.weldTo then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "PolishWeld"
			weld.Part0, weld.Part1 = opt.weldTo, p
			weld.Parent = p
		end
		if d.slots then
			local gui = Instance.new("SurfaceGui")
			gui.Name = "PolishLabel"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 50
			gui.LightInfluence = 0.15
			gui.Parent = p
			for _, slot in d.slots do
				local label = Instance.new("TextLabel")
				label.Name = slot.name
				local at, size = slot.at or { 0, 0 }, slot.size or { 1, 1 }
				label.Position = UDim2.fromScale(at[1], at[2])
				label.Size = UDim2.fromScale(size[1], size[2])
				label.BackgroundTransparency = 1
				label.Text = slot.text
				label.TextColor3 = Color3.fromRGB(231, 232, 224)
				label.TextScaled = true
				label.Font = Enum.Font.GothamMedium
				label.Parent = gui
			end
		end
		if d.light then
			local light = Instance.new("PointLight")
			light.Range, light.Brightness = d.light, 0.8
			light.Color = Color3.fromRGB(255, 225, 187)
			light.Shadows = false
			light.Parent = p
			if opt.nightLight then opt.nightLight(light) end
		end
		if d.night and opt.nightLight then
			opt.nightLight(p, Color3.fromRGB(255, 225, 187), p.Color, d.material or "Metal")
		end
	end
	for _, mount in spec.attachments or {} do
		local target = assert(parts[mount.attach], "Missing polish mount target")
		local attachment = Instance.new("Attachment")
		attachment.Name = mount.name
		attachment.CFrame = target.CFrame:ToObjectSpace(frame * CFrame.new(mount.at[1], mount.at[2], mount.at[3]))
		attachment.Parent = target
	end
	model.Parent = parent
	return model
end

return Builder
