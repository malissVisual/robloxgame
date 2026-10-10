--!strict
-- 6.16, shooting and hits: the aiming camera's kick. Every shot of yours kicks the camera up (and a little to a random
-- side), a critically damped spring brings it back on the aim by itself (shared/ShotFeel.luau spring); a shotgun or a
-- rifle kicks hard, a pistol less, an SMG or a minigun only a little (Config.Shots.Guns, the car guns too; a gun out of a
-- car window WindowShare of it). A headshot closes the field of view for a blink (Marker.HeadPunch).
-- Only the computer's aiming camera (client/CameraRig.luau calls ShotKick.apply once a frame, after it placed the
-- camera; the turn is never kept, so nothing piles up in the aim): a touch screen's Roblox camera is never turned (it
-- would keep the turn), there the arms' kick (client/ArmPose.luau) and a small CameraRig.shake on a headshot are it.
-- Reduced motion (the player's Roblox setting): ReducedMotion of the kick, no punch.
-- The shot already went where the crosshair was: the kick comes after it.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ShotFeel = require(Shared.ShotFeel)

local ShotKick = {}

local S = Config.Shots
local RATE = S.KickRate
local pitch, pitchV = 0, 0 -- degrees, degrees/s
local yaw, yawV = 0, 0
local punch, punchV = 0, 0 -- degrees of field of view taken off
local appliedAt = -math.huge -- the last frame CameraRig placed the camera (it is ours while it does)
local rng = Random.new()

local function reducedMotion(): boolean
	local ok, on = pcall(function(): any
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

-- Is the camera CameraRig's now (a computer's)? On a touch screen apply never runs: nothing to kick.
local function ours(): boolean
	return os.clock() - appliedAt < 0.25
end

-- A shot of the gun `id` (a weapon's or a car gun's) fired: kick. share: 1 (the hand gun, the roof gun), less from a window.
function ShotKick.shot(id: string?, share: number?)
	if not ours() then
		return
	end
	local def = ShotFeel.kick(id)
	local k = (share or 1) * (if reducedMotion() then S.ReducedMotion else 1)
	local most = ShotFeel.impulse(S.KickMax, RATE)
	pitchV = math.min(most, pitchV + ShotFeel.impulse(def.pitch * k, RATE))
	yawV = math.clamp(yawV + ShotFeel.impulse(def.yaw * k * rng:NextNumber(-1, 1), RATE), -most, most)
end

-- A headshot of yours: the picture punches in a little. false: the camera is not this module's (a touch screen).
function ShotKick.punch(): boolean
	if not ours() then
		return false
	end
	if not reducedMotion() then
		punchV = math.min(ShotFeel.impulse(S.Marker.HeadPunch * 1.5, RATE), punchV + ShotFeel.impulse(S.Marker.HeadPunch, RATE))
	end
	return true
end

-- CameraRig, every frame after it placed the camera: this frame's kick on top (turned, never kept).
function ShotKick.apply(camera: Camera, dt: number)
	appliedAt = os.clock()
	pitch, pitchV = ShotFeel.spring(pitch, pitchV, RATE, dt)
	yaw, yawV = ShotFeel.spring(yaw, yawV, RATE, dt)
	punch, punchV = ShotFeel.spring(punch, punchV, RATE, dt)
	if pitch > S.KickMax then -- (held down: it never piles up past KickMax)
		pitch, pitchV = S.KickMax, math.min(pitchV, 0)
	end
	if math.abs(pitch) + math.abs(yaw) > 0.001 then
		camera.CFrame *= CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
	end
	if math.abs(punch) > 0.001 then
		camera.FieldOfView = math.max(20, camera.FieldOfView - punch)
	end
end

return ShotKick
