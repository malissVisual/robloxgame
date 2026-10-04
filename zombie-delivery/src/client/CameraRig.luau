--!strict
-- GTA-style aiming on a computer: the mouse is locked in the middle of the screen, the mouse moves the camera
-- (over the shoulder on foot, behind the car when driving), a crosshair shows where the gun hits (red over an enemy)
-- and your character faces where you aim. When a window is open (map, shop, backpack, job
-- board …) or while you hold Alt the mouse is free to click. Touch screens keep the normal Roblox camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Drive = require(script.Parent.Drive)

local CameraRig = {}

local player = Players.LocalPlayer
local enabled = false
local yaw = 0
local pitch = -0.12
local zoom = 1
local lastMouse = 0
local altHeld = false
local SENSITIVITY = 0.0032

-- Set by Main: is a window open that needs the mouse?
CameraRig.mouseNeeded = function(): boolean
	return false
end

local supported = UserInputService.KeyboardEnabled and UserInputService.MouseEnabled

local crosshair: any = nil

local function makeCrosshair()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(26, 26)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui
	local function bar(size: UDim2, position: UDim2)
		local b = Instance.new("Frame")
		b.Size = size
		b.Position = position
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		b.BorderSizePixel = 0
		b.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Parent = b
	end
	bar(UDim2.fromOffset(2, 8), UDim2.new(0.5, 0, 0, 4))
	bar(UDim2.fromOffset(2, 8), UDim2.new(0.5, 0, 1, -4))
	bar(UDim2.fromOffset(8, 2), UDim2.new(0, 4, 0.5, 0))
	bar(UDim2.fromOffset(8, 2), UDim2.new(1, -4, 0.5, 0))
	bar(UDim2.fromOffset(3, 3), UDim2.fromScale(0.5, 0.5))
	crosshair = frame
end

local function setCrosshairColor(color: Color3)
	if not crosshair then
		return
	end
	for _, b in crosshair:GetChildren() do
		if b:IsA("Frame") then
			b.BackgroundColor3 = color
		end
	end
end

-- Is the mouse captured right now (aiming), or free (a window, Alt, Roblox's menu, typing)?
function CameraRig.locked(): boolean
	return enabled and supported and not altHeld and not CameraRig.mouseNeeded() and UserInputService:GetFocusedTextBox() == nil
end

function CameraRig.setEnabled(on: boolean)
	enabled = on
	if on then
		local camera = workspace.CurrentCamera
		if camera then
			local look = camera.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
		end
	end
end

local function enemyUnderCrosshair(camera: Camera, exclude: { Instance }): boolean
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if not result then
		return false
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	while model and model.Parent and model.Parent ~= workspace and not model:GetAttribute("Zombie") and not model:GetAttribute("Bandit") do
		model = model.Parent:FindFirstAncestorOfClass("Model")
	end
	return model ~= nil and (model:GetAttribute("Zombie") ~= nil or model:GetAttribute("Bandit") ~= nil)
end

local wasActive = false

local function update()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local active = enabled and supported
	if not active then
		if wasActive then
			wasActive = false
			camera.CameraType = Enum.CameraType.Custom
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			if crosshair then
				crosshair.Visible = false
			end
		end
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		return
	end
	wasActive = true

	local locked = CameraRig.locked()
	UserInputService.MouseBehavior = if locked then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not locked
	if crosshair then
		crosshair.Visible = locked
	end

	local car, driving = Drive.seatedCar()
	local now = os.clock()
	-- Driving and not touching the mouse for a moment: the camera swings back behind the car.
	if car and driving and car.PrimaryPart and now - lastMouse > 1.2 then
		local chassis = car.PrimaryPart
		local v = chassis.AssemblyLinearVelocity
		if Vector3.new(v.X, 0, v.Z).Magnitude > 8 then
			local look = chassis.CFrame.LookVector
			local carYaw = math.atan2(-look.X, -look.Z)
			local diff = (carYaw - yaw + math.pi) % (2 * math.pi) - math.pi
			yaw += diff * math.min(1, 0.06)
			pitch += (-0.18 - pitch) * 0.05
		end
	end

	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local focus: Vector3
	local back: Vector3
	local exclude: { Instance } = { character }
	if car and car.PrimaryPart then
		local size = car:GetExtentsSize()
		focus = car.PrimaryPart.Position + Vector3.new(0, size.Y * 0.6 + 2, 0)
		back = Vector3.new(0, 2, (size.Z * 0.7 + 9) * zoom)
		table.insert(exclude, car)
	else
		focus = root.Position + Vector3.new(0, 1.8, 0)
		back = Vector3.new(2.2, 0.6, 9 * zoom) -- over the right shoulder
	end
	local effects = workspace:FindFirstChild("LocalEffects")
	if effects then
		table.insert(exclude, effects)
	end
	local guide = workspace:FindFirstChild("DeliveryGuide")
	if guide then
		table.insert(exclude, guide)
	end
	local desired = focus + rotation:VectorToWorldSpace(back)
	-- Do not go through walls.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(focus, desired - focus, params)
	local position = if hit then hit.Position + (focus - desired).Unit * 0.6 else desired
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(position, position + rotation.LookVector)

	-- On foot the character faces the aim and raises the gun.
	if not car then
		humanoid.AutoRotate = false
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	else
		humanoid.AutoRotate = true
	end

	if locked then
		setCrosshairColor(if enemyUnderCrosshair(camera, exclude) then Color3.fromRGB(255, 70, 60) else Color3.new(1, 1, 1))
	end
end

function CameraRig.start()
	if not supported then
		return
	end
	makeCrosshair()
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not enabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and CameraRig.locked() then
			yaw -= input.Delta.X * SENSITIVITY
			pitch = math.clamp(pitch - input.Delta.Y * SENSITIVITY, -1.2, 0.9)
			lastMouse = os.clock()
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			zoom = math.clamp(zoom - input.Position.Z * 0.1, 0.5, 2)
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = false
		end
	end)
	RunService:BindToRenderStep("ZombieDeliveryCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

-- The point under the crosshair (locked) for the guns and the thrown items.
function CameraRig.aimRay(): Ray?
	if not CameraRig.locked() then
		return nil
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local viewport = camera.ViewportSize
	return camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
end

return CameraRig
