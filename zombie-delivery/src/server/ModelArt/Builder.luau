--!strict
-- Build native decorative skins on caller-owned attachment parts. No gameplay, physics controllers or rig joints.
local Builder = {}
export type Triple = { number }
export type Piece = {
	name: string, size: Triple, at: Triple, attach: string, finish: string,
	turn: Triple?, shape: string?, shadow: boolean?, text: string?, textSlot: string?, night: boolean?,
}
export type Point = { name: string, at: Triple, attach: string, turn: Triple? }
export type Spec = { id: string, pieces: { Piece }, attachments: { Point }? }
export type Built = { model: Model, parts: { BasePart }, points: { Attachment } }
local FINISH: { [string]: { color: Triple, material: Enum.Material } } = {
	charcoal = { color = { 35, 40, 43 }, material = Enum.Material.Metal },
	cloth = { color = { 44, 49, 48 }, material = Enum.Material.Fabric },
	red = { color = { 153, 49, 43 }, material = Enum.Material.SmoothPlastic },
	steel = { color = { 166, 176, 174 }, material = Enum.Material.Metal },
	worn = { color = { 110, 118, 110 }, material = Enum.Material.Metal },
	rust = { color = { 110, 64, 41 }, material = Enum.Material.CorrodedMetal },
	white = { color = { 216, 219, 205 }, material = Enum.Material.SmoothPlastic },
	glass = { color = { 43, 64, 70 }, material = Enum.Material.Glass },
	sole = { color = { 23, 27, 29 }, material = Enum.Material.Rubber },
	foam = { color = { 111, 119, 119 }, material = Enum.Material.SmoothPlastic },
	parcel = { color = { 147, 120, 84 }, material = Enum.Material.SmoothPlastic },
	paper = { color = { 218, 210, 184 }, material = Enum.Material.SmoothPlastic },
	screen = { color = { 96, 141, 143 }, material = Enum.Material.Neon },
	reflector = { color = { 188, 200, 192 }, material = Enum.Material.SmoothPlastic },
	wall = { color = { 80, 88, 86 }, material = Enum.Material.Concrete },
	concrete = { color = { 112, 117, 112 }, material = Enum.Material.Concrete },
	floor = { color = { 59, 65, 66 }, material = Enum.Material.Concrete },
}
local function pose(at: Triple, turn: Triple?): CFrame
	local r = turn or { 0, 0, 0 }
	return CFrame.new(at[1], at[2], at[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
end
function Builder.build(parent: Instance, spec: Spec, targets: { [string]: BasePart }): Built
	-- Validate target coverage before creating anything. Caller supplies rig bones or separate moving assembly roots.
	for _, p in spec.pieces do assert(targets[p.attach] and FINISH[p.finish], "Missing art target or finish: " .. p.name) end
	for _, p in spec.attachments or {} do assert(targets[p.attach], "Missing attachment target: " .. p.name) end
	local model = Instance.new("Model")
	model.Name = spec.id .. "Art"
	local built: Built = { model = model, parts = {}, points = {} }
	for _, d in spec.pieces do
		local target = targets[d.attach]
		local p = Instance.new(if d.shape == "Wedge" then "WedgePart" else "Part") :: BasePart
		local finish = FINISH[d.finish]
		p.Name, p.Size = d.name, Vector3.new(d.size[1], d.size[2], d.size[3])
		p.CFrame = target.CFrame * pose(d.at, d.turn)
		p.Color, p.Material = Color3.fromRGB(finish.color[1], finish.color[2], finish.color[3]), finish.material
		-- The weld follows an anchored display root too. Never anchor a skin part: it would freeze the caller's rig.
		p.Anchored, p.Massless, p.CanCollide, p.CanQuery, p.CanTouch = false, true, false, false, false
		p.CastShadow = d.shadow == true -- explicitly enable only large pieces; strips, spokes and fasteners stay off
		if d.shape == "Cylinder" then (p :: Part).Shape = Enum.PartType.Cylinder end
		p:SetAttribute("ArtAttach", d.attach)
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Name, weld.Part0, weld.Part1, weld.Parent = "ArtWeld", target, p, p
		if d.text or d.textSlot then
			local gui = Instance.new("SurfaceGui")
			gui.Name, gui.Face, gui.SizingMode, gui.PixelsPerStud = "ArtLabel", Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 80
			gui.LightInfluence, gui.Parent = .15, p
			local text = Instance.new("TextLabel")
			text.Name, text.Text = d.textSlot or "Label", d.text or ""
			text.Size, text.BackgroundTransparency, text.TextScaled = UDim2.fromScale(1, 1), 1, true
			text.Font, text.TextColor3 = Enum.Font.GothamMedium, Color3.fromRGB(216, 219, 205)
			text.Parent = gui
		end
		p:SetAttribute("NightLamp", d.night == true) -- Claude registers these with DayNight; no scheduler here
		table.insert(built.parts, p)
	end
	for _, d in spec.attachments or {} do
		local point = Instance.new("Attachment")
		point.Name, point.CFrame, point.Parent = d.name, pose(d.at, d.turn), targets[d.attach]
		table.insert(built.points, point)
	end
	model.Parent = parent
	return built
end
function Builder.destroy(built: Built)
	for _, point in built.points do point:Destroy() end
	built.model:Destroy()
end
return Builder
