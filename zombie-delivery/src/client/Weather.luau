--!strict
-- Winter north of the mountain: snow falls around the camera and the air turns cold and white. Also hides the
-- big landmark icons up close. Only on this client.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Map = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Map"))

local Weather = {}

function Weather.start()
	local cloud = Instance.new("Part")
	cloud.Name = "SnowCloud"
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.Transparency = 1
	cloud.Size = Vector3.new(160, 1, 160)
	cloud.Parent = workspace
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.LightEmission = 0.3
	snow.Size = NumberSequence.new(0.35)
	snow.Lifetime = NumberRange.new(5, 7)
	snow.Speed = NumberRange.new(8, 12)
	snow.SpreadAngle = Vector2.new(15, 15)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Acceleration = Vector3.new(2, 0, 1)
	snow.Rate = 0
	snow.Parent = cloud

	local wasWinter = false
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local normalColor = if atmosphere then atmosphere.Color else Color3.new(1, 1, 1)
	local normalDensity = if atmosphere then atmosphere.Density else 0.3

	local tagCheck = 0
	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local position = camera.CFrame.Position
		cloud.CFrame = CFrame.new(position + Vector3.new(0, 40, 0))
		-- The big icons over the landmarks: only from afar (up close the buildings' own signs say it).
		tagCheck += dt
		if tagCheck > 0.25 then
			tagCheck = 0
			local world = workspace:FindFirstChild("World")
			local tags = world and world:FindFirstChild("LandmarkTags")
			if tags then
				for _, tag in tags:GetChildren() do
					local gui = tag:FindFirstChildOfClass("BillboardGui")
					if gui and tag:IsA("BasePart") then
						gui.Enabled = Vector3.new(tag.Position.X - position.X, 0, tag.Position.Z - position.Z).Magnitude > 110
					end
				end
			end
		end
		local winter = Map.isWinter(position.X, position.Z)
		if winter == wasWinter then
			return
		end
		wasWinter = winter
		snow.Rate = if winter then 400 else 0
		atmosphere = atmosphere or Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			if winter then
				normalColor, normalDensity = atmosphere.Color, atmosphere.Density
			end
			TweenService:Create(atmosphere, TweenInfo.new(2), {
				Color = if winter then Color3.fromRGB(220, 230, 240) else normalColor,
				Density = if winter then 0.42 else normalDensity,
			}):Play()
		end
	end)
end

return Weather
