--!strict
-- 6.16, speed lines (the owner: "speed lines when you floor it"): thin white streaks that fly out toward the screen's
-- edges while you drive near your top speed (shared/DriveFeel.luau streaks: from SpeedLines.From of it, a scooter's or
-- a bike's from TwoFrom; a nitro past it shows them all), subtle (SpeedLines.Opacity at the most) and only in the outer
-- ring of the screen, so the road ahead stays clear. A ScreenGui under the HUD (DisplayOrder -5) of SpeedLines.Count
-- thin Frames (a phone: Lite of them), moved every frame only while they show (the gui is off otherwise). None with
-- reduced motion (the player's Roblox setting) and none for a passenger. Numbers in Config.DriveFeel.SpeedLines.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DriveFeel = require(Shared:WaitForChild("DriveFeel"))

local DeviceBudget = require(script.Parent.DeviceBudget)
local Drive = require(script.Parent.Drive)

local SpeedLines = {}

local Lines = Config.DriveFeel.SpeedLines
local FADE_IN = 4 -- 1/s: how quickly they come and go with the speed
local THICK = 2 -- px (a phone's screen: 3)

type Streak = { frame: Frame, angle: number, radius: number, speed: number, life: number, age: number, length: number }

local streaks: { Streak } = {}
local gui: ScreenGui? = nil
local strength = 0
local motion = { checkedAt = 0, reduced = false }

local function reducedMotion(): boolean
	local now = os.clock()
	if now - motion.checkedAt > 2 then
		motion.checkedAt = now
		local ok, on = pcall(function(): any
			return (GuiService :: any).ReducedMotionEnabled
		end)
		motion.reduced = ok and on == true
	end
	return motion.reduced
end

-- Somewhere new in the outer ring of the screen (first: part-way through its life, so they do not start together).
local function respawn(s: Streak, first: boolean)
	s.angle = math.random() * 2 * math.pi
	s.radius = 0.6 + math.random() * 0.28 -- of half the screen, out from the middle
	s.speed = 0.9 + math.random() * 0.9 -- of half the screen a second, outward
	s.life = 0.22 + math.random() * 0.22
	s.age = if first then math.random() * s.life else 0
	s.length = 50 + math.random() * 110
end

local function build(parent: Instance)
	local screen = Instance.new("ScreenGui")
	screen.Name = "SpeedLines"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = -5
	screen.Enabled = false
	local count = if DeviceBudget.lite then math.max(4, math.floor(Lines.Count * Lines.Lite)) else Lines.Count
	for _ = 1, count do
		local frame = Instance.new("Frame")
		frame.Name = "Streak"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BackgroundTransparency = 1
		local gradient = Instance.new("UIGradient") -- a thin tail toward the middle, the head toward the edge
		gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.7, 0.1), NumberSequenceKeypoint.new(1, 0.5) })
		gradient.Parent = frame
		frame.Parent = screen
		local s: Streak = { frame = frame, angle = 0, radius = 0, speed = 0, life = 1, age = 0, length = 0 }
		respawn(s, true)
		table.insert(streaks, s)
	end
	screen.Parent = parent
	gui = screen
end

-- How strong they should be now (0 … 1): your speed's share of your top speed while you drive.
local function wanted(): number
	if reducedMotion() then
		return 0
	end
	local car, driving = Drive.seatedCar()
	local chassis = car and car.PrimaryPart
	if not car or not driving or not chassis then
		return 0
	end
	local top = (car:GetAttribute("MaxSpeed") or 60) :: number * ((car:GetAttribute("SpeedMult") or 1) :: number)
	local v = chassis.AssemblyLinearVelocity
	local share = Vector3.new(v.X, 0, v.Z).Magnitude / math.max(top, 1)
	return DriveFeel.streaks(share, car:GetAttribute("Bike") == true)
end

local function step(dt: number)
	local screen = gui
	local camera = workspace.CurrentCamera
	if not screen or not camera then
		return
	end
	strength += (wanted() - strength) * math.min(1, dt * FADE_IN)
	if strength < 0.02 then
		if screen.Enabled then
			screen.Enabled = false
		end
		return
	end
	screen.Enabled = true
	local size = camera.ViewportSize
	local cx, cy = size.X / 2, size.Y / 2
	local thick = if DeviceBudget.lite then THICK + 1 else THICK
	local shown = Lines.Opacity * strength
	for _, s in streaks do
		s.age += dt
		if s.age >= s.life then
			respawn(s, false)
		end
		local t = s.age / s.life
		local r = s.radius + s.speed * s.age
		local dx, dy = math.cos(s.angle) * cx, math.sin(s.angle) * cy
		local frame = s.frame
		frame.Position = UDim2.fromOffset(cx + dx * r, cy + dy * r)
		frame.Rotation = math.deg(math.atan2(dy, dx))
		frame.Size = UDim2.fromOffset(s.length * (0.5 + 0.5 * strength), thick)
		frame.BackgroundTransparency = 1 - shown * math.sin(math.pi * t)
	end
end

function SpeedLines.start()
	task.spawn(function()
		build(Players.LocalPlayer:WaitForChild("PlayerGui"))
	end)
	RunService.RenderStepped:Connect(step)
end

return SpeedLines
