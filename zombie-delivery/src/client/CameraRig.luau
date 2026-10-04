--!strict
-- GTA-style aiming on a computer: the mouse is locked in the middle of the screen, the mouse moves the camera
-- (behind you on foot, behind the car when driving), a crosshair shows where the gun hits (red over an enemy).
-- On foot it plays like GTA: walking and running the character turns where it goes; aiming (right mouse) or
-- shooting (left mouse) it turns to the crosshair, the camera moves in over the shoulder and the gun arm goes up. When a window is open (map, shop, backpack, job
-- board …) or while you hold Alt the mouse is free to click. Touch screens keep the normal Roblox camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Drive = require(script.Parent.Drive)

local CameraRig = {}

local player = Players.LocalPlayer
local enabled = false
local yaw = 0
local pitch = -0.12
local zoom = 1
local lastMouse = 0
local altHeld = false
local rmbHeld = false -- aiming
local lmbHeld = false -- shooting
local lastFire = 0
local aimBlend = 0 -- 0 = walking camera, 1 = over the shoulder
local aimingSent = false
local smoothFocus: Vector3? = nil -- the camera's focus follows smoothly (no shaking with every bump of the car)
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

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Tell the server (the gun arm goes up / down for everybody).
local function sendAiming(aiming: boolean)
	if aiming ~= aimingSent then
		aimingSent = aiming
		Net.get("Aiming"):FireServer(aiming)
	end
end

-- Shooting module: a shot was fired (the character turns to the aim for a moment).
function CameraRig.noteFire()
	lastFire = os.clock()
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local active = enabled and supported
	if not active then
		if wasActive then
			wasActive = false
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			sendAiming(false)
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
	-- Aiming from a car (drive-by): right mouse held, any seat.
	local carAim = locked and car ~= nil and rmbHeld and humanoid.Health > 0

	-- Driving and not touching the mouse for a moment: the camera swings back behind the car.
	if car and driving and car.PrimaryPart and now - lastMouse > 1.2 and not carAim then
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

	-- Aiming: right mouse held, shooting, or a shot a moment ago (on foot only).
	local wantAim = locked and not car and (rmbHeld or lmbHeld or now - lastFire < 0.7) and humanoid.Health > 0
	aimBlend = lerp(aimBlend, if wantAim or carAim then 1 else 0, math.min(1, dt * 10))
	sendAiming(wantAim)

	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local focus: Vector3
	local back: Vector3
	local exclude: { Instance } = { character }
	if car and car.PrimaryPart then
		local size = car:GetExtentsSize()
		focus = car.PrimaryPart.Position + Vector3.new(0, size.Y * 0.6 + 2, 0)
		-- Behind the car; aiming: closer, over the right side of the roof.
		back = Vector3.new(lerp(0, 3, aimBlend), lerp(2, 0.8, aimBlend), lerp(size.Z * 0.7 + 9, size.Z * 0.3 + 4, aimBlend) * zoom)
		table.insert(exclude, car)
	else
		focus = root.Position + Vector3.new(0, lerp(2.2, 1.8, aimBlend), 0)
		-- Walking: behind, a little to the side. Aiming: close over the right shoulder.
		back = Vector3.new(lerp(0.8, 2.3, aimBlend), lerp(1.2, 0.5, aimBlend), lerp(11, 6.5, aimBlend) * zoom)
	end
	-- Only the world stops the camera, not things that move around.
	for _, name in { "LocalEffects", "DeliveryGuide", "Zombies", "Cars", "BanditCars", "Loot", "Effects" } do
		local thing = workspace:FindFirstChild(name)
		if thing then
			table.insert(exclude, thing)
		end
	end
	-- Smooth follow: sideways tight, up and down soft (the car's bumps do not shake the picture).
	local last = smoothFocus
	local previous: Vector3 = if last and (last - focus).Magnitude <= 40 then last else focus
	local side = math.min(1, dt * 25)
	local vertical = math.min(1, dt * 7)
	focus = Vector3.new(lerp(previous.X, focus.X, side), lerp(previous.Y, focus.Y, vertical), lerp(previous.Z, focus.Z, side))
	smoothFocus = focus
	local desired = focus + rotation:VectorToWorldSpace(back)
	-- Do not go through walls.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(focus, desired - focus, params)
	local position = if hit then hit.Position + (focus - desired).Unit * 0.6 else desired
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(position, position + rotation.LookVector)
	camera.FieldOfView = lerp(70, 55, aimBlend)

	-- On foot: the character turns where it walks (the Humanoid does it), or toward the aim while aiming.
	if wantAim then
		humanoid.AutoRotate = false
		local look = root.CFrame.LookVector
		local current = math.atan2(-look.X, -look.Z)
		local diff = (yaw - current + math.pi) % (2 * math.pi) - math.pi
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, current + diff * math.min(1, dt * 18), 0)
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
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = true
		elseif processed then
			return
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbHeld = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			lmbHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			lmbHeld = false
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
