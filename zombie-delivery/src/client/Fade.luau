--!strict
-- 7.0: a black fade over the whole screen, over everything (the MOVES doors: server/Moving.luau sends ("fade", "out" |
-- "in", seconds) through the Moving remote, client/MovingHud.luau calls this). Reusable by anything that moves you
-- somewhere else in a blink. Presentation only.
--   Fade.out(seconds?)    to black (0.35 s when not given)
--   Fade.into(seconds?)   back to the game
--   Fade.isDark()         black (or going there) now
-- A fade out that nothing answers lifts by itself after HOLD s: a lost message never leaves the screen black.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Fade = {}

local HOLD = 4
local DEFAULT = 0.35

local veil: Frame? = nil
local dark = false
local token = 0

local function ensure(): Frame?
	local current = veil
	if current and current.Parent then
		return current
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "Fade"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 100
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local frame = Instance.new("Frame")
	frame.Name = "Veil"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Parent = screen
	screen.Parent = playerGui
	veil = frame
	return frame
end

local function tween(frame: Frame, seconds: number, transparency: number)
	TweenService:Create(frame, TweenInfo.new(math.max(0, seconds), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = transparency }):Play()
end

function Fade.out(seconds: number?)
	local frame = ensure()
	if not frame then
		return
	end
	local time = seconds or DEFAULT
	token += 1
	local mine = token
	dark = true
	tween(frame, time, 0)
	task.delay(time + HOLD, function()
		if token == mine and dark then
			Fade.into(DEFAULT)
		end
	end)
end

function Fade.into(seconds: number?)
	local frame = ensure()
	if not frame then
		return
	end
	token += 1
	dark = false
	tween(frame, seconds or DEFAULT, 1)
end

function Fade.isDark(): boolean
	return dark
end

return Fade
