--!strict
-- 7.0: a black fade over the whole screen, over everything (the MOVES doors: server/Moving.luau sends ("fade", "out" |
-- "in", seconds) through the Moving remote, client/MovingHud.luau calls this). Reusable by anything that moves you
-- somewhere else in a blink. Presentation only.
--   Fade.out(seconds?)             to black (0.35 s when not given)
--   Fade.into(seconds?, arrival?)  back to the game; 8.3 with an arrival (a door's trip: Fade.arrival of the message's
--                                  own): the black held until your body is there (within `near` studs of `at`: it may
--                                  have walked a step since; or `wait` s), the hook onArrive
--                                  (client/WalkDoors.luau: the camera behind you, the way you face there), `dark` s more,
--                                  then back to the game: the move happened while it was black, nothing seen popping
--   Fade.arrival(raw) -> Arrival?  a trip's arrival from the server's message (checked; nil: none, a plain fade in)
--   Fade.onArrive                  8.3: fn(look) when you are there, still black (set by client/WalkDoors.luau)
--   Fade.isDark()                  black (or going there) now
-- A fade out that nothing answers lifts by itself after HOLD s: a lost message never leaves the screen black. Both ways
-- ease in and out (Sine): no hard edge at either end.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Fade = {}

export type Arrival = { at: Vector3, look: Vector3, dark: number, wait: number, near: number }

local HOLD = 4
local DEFAULT = 0.35
local STEP = "ZombieDeliveryFadeArrive"

local veil: Frame? = nil
local dark = false
local token = 0

Fade.onArrive = nil :: ((look: Vector3) -> ())?

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
	TweenService:Create(frame, TweenInfo.new(math.max(0, seconds), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = transparency }):Play()
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

function Fade.arrival(raw: any): Arrival?
	if type(raw) ~= "table" or typeof(raw.at) ~= "Vector3" or typeof(raw.look) ~= "Vector3" then
		return nil
	end
	local function seconds(x: any, most: number): number
		return if type(x) == "number" and x == x then math.clamp(x, 0, most) else 0
	end
	local near = if type(raw.near) == "number" and raw.near == raw.near then math.clamp(raw.near, 1, 20) else 6
	return { at = raw.at, look = raw.look, dark = seconds(raw.dark, 1), wait = seconds(raw.wait, 3), near = near }
end

-- Your body's root now (nil: no body).
local function rootNow(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

function Fade.into(seconds: number?, arrival: Arrival?)
	local frame = ensure()
	if not frame then
		return
	end
	token += 1
	local mine = token
	pcall(function()
		RunService:UnbindFromRenderStep(STEP)
	end)
	if not arrival then
		dark = false
		tween(frame, seconds or DEFAULT, 1)
		return
	end
	-- 8.3 a door's trip: still black until the body is there (looked at every frame, before the camera's step: the camera
	-- turned in the same frame), then `dark` s, then the fade in
	local started = os.clock()
	local function lift()
		task.delay(arrival.dark, function()
			if token == mine then
				dark = false
				tween(frame, seconds or DEFAULT, 1)
			end
		end)
	end
	local ok = pcall(function()
		RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value - 1, function()
			if token ~= mine then
				RunService:UnbindFromRenderStep(STEP)
				return
			end
			local root = rootNow()
			local there = root ~= nil and (root.Position - arrival.at).Magnitude <= arrival.near
			if not there and os.clock() - started < arrival.wait then
				return
			end
			RunService:UnbindFromRenderStep(STEP)
			local hook = Fade.onArrive
			if there and hook then
				pcall(hook, arrival.look)
			end
			lift()
		end)
	end)
	if not ok then
		lift() -- (no render step here: as before, after the dark)
	end
end

function Fade.isDark(): boolean
	return dark
end

return Fade
