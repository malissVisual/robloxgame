--!strict
-- Cached true model previews for the garage: live owned car with its kit, otherwise the purchased stage geometry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Data = require(Shared.VehiclePreviewData)
local Economy = require(Shared.Economy)
local Preview = {}
local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic, Plastic = Enum.Material.Plastic, Metal = Enum.Material.Metal,
	Glass = Enum.Material.Glass, Rubber = Enum.Material.Rubber, CorrodedMetal = Enum.Material.CorrodedMetal,
	WoodPlanks = Enum.Material.WoodPlanks, DiamondPlate = Enum.Material.DiamondPlate,
}
local function liveCar(id: string): Model?
	local cars = workspace:FindFirstChild("Cars")
	if not cars then return nil end
	for _, child in cars:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OwnerId") == Players.LocalPlayer.UserId and child:GetAttribute("CarId") == id then return child end
	end
	return nil
end
local function snapshot(rows: any, colors: any, paintId: string?): Model
	local model = Instance.new("Model")
	local paint = if paintId then Economy.findPaint(paintId) else nil
	for _, row in rows do
		local p = Instance.new(if row[1] == 2 then "WedgePart" else "Part") :: BasePart
		p.Name = "PreviewPanel"
		p.Size = Vector3.new(row[5], row[6], row[7])
		p.CFrame = CFrame.new(row[2], row[3], row[4], row[8], row[9], row[10], row[11], row[12], row[13], row[14], row[15], row[16])
		local color = colors[row[17]]
		p.Color = Color3.new(color[1], color[2], color[3])
		p.Material = MATERIALS[row[18]] or Enum.Material.SmoothPlastic
		p.Transparency = 1 - row[19]
		if row[20] and paint and paint.color then
			local c = paint.color
			p.Color = Color3.fromRGB(c[1], c[2], c[3])
			if paint.material then
				local material = (Enum.Material :: any)[paint.material]
				if typeof(material) == "EnumItem" then p.Material = material :: Enum.Material end
			end
			if p.Material == Enum.Material.Neon then p.Color = p.Color:Lerp(Color3.new(0, 0, 0), .35) end
			p.Reflectance = if p.Material == Enum.Material.Glass then .25 elseif p.Material == Enum.Material.Foil then .1 else 0
		end
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		if row[1] == 1 then (p :: Part).Shape = Enum.PartType.Cylinder end
		p.Parent = model
		if row[21] then
			local gui = Instance.new("SurfaceGui")
			gui.Face, gui.SizingMode, gui.PixelsPerStud = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 60
			gui.Parent = p
			local label = Instance.new("TextLabel")
			label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
			label.Font, label.TextScaled, label.Text = Enum.Font.GothamMedium, true, row[21]
			label.TextColor3 = Color3.fromRGB(217, 218, 207)
			label.Parent = gui
		end
	end
	return model
end
function Preview.show(holder: Instance, car: any): boolean
	local id, stage = tostring(car.id), math.max(0, math.floor(tonumber(car.stage) or 0))
	local rows, colors = Data.get(id, stage)
	if not rows then return false end -- company vehicles retain their existing drawing
	local source = if car.out then liveCar(id) else nil
	local key = id .. ":" .. tostring(stage) .. ":" .. tostring(car.paint) .. ":" .. tostring(car.upgrades) .. ":" .. tostring(car.out)
	local old = holder:FindFirstChild("VehicleModelPreview")
	if old and old:IsA("ViewportFrame") and old:GetAttribute("PreviewKey") == key then
		local ref = old:FindFirstChild("LiveSource")
		if ref and ref:IsA("ObjectValue") and ref.Value == source then return true end
	end
	for _, child in holder:GetChildren() do child:Destroy() end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name, viewport.Size, viewport.BackgroundTransparency = "VehicleModelPreview", UDim2.fromScale(1, 1), 1
	viewport.Ambient, viewport.LightColor, viewport.LightDirection = Color3.fromRGB(160, 173, 180), Color3.fromRGB(255, 239, 219), Vector3.new(-1, -1, -.5)
	viewport:SetAttribute("PreviewKey", key)
	viewport.Parent = holder
	local ref = Instance.new("ObjectValue"); ref.Name, ref.Value, ref.Parent = "LiveSource", source, viewport
	local model = if source and source.Archivable then source:Clone() else snapshot(rows, colors, if type(car.paint) == "string" then car.paint else nil)
	-- A local static copy: no live movers, particles, sounds, prompts, joints or code inside the ViewportFrame.
	for _, obj in model:GetDescendants() do
		if obj:IsA("BasePart") then obj.Anchored = true; obj.CanCollide = false; obj.CanTouch = false; obj.CanQuery = false
		elseif obj:IsA("JointInstance") or obj:IsA("WeldConstraint") or obj:IsA("Constraint") or obj:IsA("LuaSourceContainer") or obj:IsA("ProximityPrompt") or obj:IsA("ParticleEmitter") or obj:IsA("Sound") or obj:IsA("Light") then obj:Destroy() end
	end
	if source then model:PivotTo(CFrame.new()) end
	local world = Instance.new("WorldModel"); world.Parent = viewport; model.Parent = world
	local cf, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	local direction = Vector3.new(-.9, .6, -1.5).Unit
	local right = (-direction):Cross(Vector3.yAxis).Unit
	local up = right:Cross(-direction).Unit
	local half = size / 2
	local function extent(axis: Vector3): number
		return math.abs(axis.X) * half.X + math.abs(axis.Y) * half.Y + math.abs(axis.Z) * half.Z
	end
	local aspect = 2 -- the garage drawing slot is 300 x 150
	if holder:IsA("GuiObject") then
		local pixels = (holder :: GuiObject).AbsoluteSize
		if pixels.Y > 0 then aspect = math.max(.5, pixels.X / pixels.Y) end
	end
	local tangent = math.tan(math.rad(camera.FieldOfView / 2))
	local distance = 1.08 * (math.max(extent(up) / tangent, extent(right) / (tangent * aspect)) + extent(direction))
	camera.CFrame = CFrame.lookAt(cf.Position + direction * distance, cf.Position)
	camera.Parent, viewport.CurrentCamera = viewport, camera
	return true
end
-- The window closed: drop the viewport and its local model copy (show builds it again on the next open).
function Preview.clear(holder: Instance)
	local old = holder:FindFirstChild("VehicleModelPreview")
	if old then old:Destroy() end
end
return Preview
