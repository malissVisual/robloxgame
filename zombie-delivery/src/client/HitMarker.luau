--!strict
-- 6.16, shooting and hits: the hit marker. Every hit of yours (the Hit remote: server/Gun.luau's rounds, the melee's
-- server/CloseCombat.luau) draws a quick X around the crosshair: white on a hit, red and a little bigger on a kill, gold,
-- bigger and longer on a headshot (Config.Shots.Marker; shared/ShotFeel.luau marker), popping in and fading. A kill
-- shows a small skull over it. The dot in the middle still pulses and turns red (client/CameraRig.luau hitFeedback; the
-- 4.x headshot X that client/Shooting.luau drew is this now).
-- Where: around the crosshair while a computer's mouse is locked; otherwise (a touch screen's FIRE, the mouse freed with
-- Alt) at the spot hit, on the screen (no X when that is off the screen; the sound still plays).
-- A headshot also punches the camera in (client/ShotKick.luau; a touch screen's camera: a small CameraRig.shake).
-- A shotgun's pellets arrive together: one marker, the strongest of them. The ticks under the hit's own sound:
-- client/Sounds.luau (Marker.Ticks).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ShotFeel = require(Shared.ShotFeel)
local CameraRig = require(script.Parent.CameraRig)
local ShotKick = require(script.Parent.ShotKick)

local HitMarker = {}

local M = Config.Shots.Marker
local player = Players.LocalPlayer
local RANK: { [string]: number } = { hit = 1, kill = 2, head = 3 }
local POP_SECONDS = 0.08
local GAP = 7 -- px from the middle to a stroke's middle (the dot stays free)
local LENGTH = 8 -- px, a stroke's length (at size 1)

local holder: Frame? = nil
local scale: UIScale? = nil
local bars: { Frame } = {}
local strokes: { UIStroke } = {}
local skull: TextLabel? = nil

local shownAt = -math.huge
local shown: ShotFeel.MarkerLook = M.Hit
local shownKind = "hit"
local withSkull = false
local spot: Vector3? = nil -- the world spot hit (drawn there when the mouse is not locked)
local active = false

local DIAGONALS = { { -1, -1, -45 }, { 1, 1, -45 }, { 1, -1, 45 }, { -1, 1, 45 } } -- x, y, the stroke's rotation

local function make()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hitmarker"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(48, 48)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui
	holder = frame
	local s = Instance.new("UIScale")
	s.Parent = frame
	scale = s
	-- Four short strokes on the diagonals, leaving the dot free in the middle.
	for _, d in DIAGONALS do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Rotation = d[3]
		bar.BorderSizePixel = 0
		bar.BackgroundTransparency = 1
		bar.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Transparency = 1
		stroke.Parent = bar
		table.insert(bars, bar)
		table.insert(strokes, stroke)
	end
	local glyph = Instance.new("TextLabel")
	glyph.Size = UDim2.fromOffset(24, 24)
	glyph.AnchorPoint = Vector2.new(0.5, 1)
	glyph.Position = UDim2.new(0.5, 0, 0, -2)
	glyph.BackgroundTransparency = 1
	glyph.Text = "💀"
	glyph.TextSize = 16
	glyph.Font = Enum.Font.GothamBold
	glyph.TextTransparency = 1
	glyph.Parent = frame
	skull = glyph
end

-- Where the marker goes this frame (in pixels from the screen's top left), or nil: off the screen.
local function placeAt(): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local at = spot
	if CameraRig.locked() or not at then
		return Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	end
	local point, visible = camera:WorldToViewportPoint(at)
	return if visible then Vector2.new(point.X, point.Y) else nil
end

local function step()
	if not active then
		return
	end
	local frame, s = holder, scale
	if not frame or not s then
		return
	end
	local t = os.clock() - shownAt
	local k = t / shown.seconds
	local at = placeAt()
	if k >= 1 or not at then
		frame.Visible = false
		active = k < 1 -- (off the screen for now: it may come back on before it is done)
		return
	end
	frame.Visible = true
	frame.Position = UDim2.fromOffset(at.X, at.Y)
	local pop = math.max(0, 1 - t / POP_SECONDS)
	s.Scale = shown.size * (1 + (M.Pop - 1) * pop * pop)
	local fade = k * k -- solid at first, then gone quickly
	local gap = GAP + 3 * k
	for index, bar in bars do
		local d = DIAGONALS[index]
		bar.Position = UDim2.new(0.5, d[1] * gap, 0.5, d[2] * gap)
		bar.BackgroundTransparency = fade
		strokes[index].Transparency = 0.35 + 0.65 * fade
	end
	local glyph = skull
	if glyph then
		glyph.TextTransparency = if withSkull then fade else 1
	end
end

-- A hit of yours: kind "hit" | "kill" | "head" (a headshot counts as a kill unless `killed` is false), at `position`
-- (the spot hit, from the server).
function HitMarker.show(kind: string, killed: boolean?, position: Vector3?)
	local look, skullToo = ShotFeel.marker(kind, killed)
	local kill = kind == "kill" or (kind == "head" and killed ~= false)
	CameraRig.hitFeedback(if kill then "kill" else "hit")
	local now = os.clock()
	-- A shotgun's pellets (and a blast's) arrive together: one marker, the strongest.
	if active and now - shownAt < M.TickGap and (RANK[kind] or 1) <= (RANK[shownKind] or 1) then
		return
	end
	if kind == "head" and not (active and shownKind == "head" and now - shownAt < M.TickGap) then
		if not ShotKick.punch() then
			CameraRig.shake(M.HeadShake) -- a touch screen's camera (nothing under reduced motion)
		end
	end
	if not holder then
		make()
	end
	shownAt = now
	shown = look
	shownKind = kind
	withSkull = skullToo
	spot = position
	active = true
	local color = Color3.fromRGB(look.color[1], look.color[2], look.color[3])
	for _, bar in bars do
		bar.BackgroundColor3 = color
		bar.Size = UDim2.fromOffset(look.thick, LENGTH)
	end
	local glyph = skull
	if glyph then
		glyph.TextColor3 = color
	end
	step()
end

function HitMarker.start()
	RunService.RenderStepped:Connect(step)
end

return HitMarker
