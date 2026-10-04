--!strict
-- The gun arm. Aiming on foot, every character's arms come up and point the gun where it aims (up or down too):
-- the right arm straight forward, the left hand under the gun. Every frame the shoulder joints turn (Motor6D.C0,
-- which no animation touches) and the walk animation's swing of the arms fades out (Motor6D.Transform, after the
-- animations ran), smoothly up and down. Works for R15 and R6 characters.
-- Your own character follows your camera directly; the others follow the Aiming / AimPitch attributes the server
-- sets on their characters.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraRig = require(script.Parent.CameraRig)

local ArmPose = {}

local RAISE_TIME = 0.2 -- seconds for the arm to come up
local LOWER_TIME = 0.3
local blends: { [Model]: number } = {}
-- Each joint's own C0 before any posing (the pose turns it, and gives it back exactly).
local rest: { [Motor6D]: CFrame } = {}

local function joint(parent: Instance?, name: string): Motor6D?
	local found = parent and parent:FindFirstChild(name)
	return if found and found:IsA("Motor6D") then found else nil
end

local function lay(motor: Motor6D?, goal: CFrame, t: number)
	if not motor then
		return
	end
	local base = rest[motor]
	if not base then
		base = motor.C0
		rest[motor] = base
	end
	motor.C0 = base * CFrame.identity:Lerp(goal, t)
	-- The animation's own swing of this joint fades out while the gun is up.
	motor.Transform = motor.Transform:Lerp(CFrame.identity, t)
end

local function pose(character: Model, t: number, pitch: number)
	local up = math.rad(90) + pitch
	local upperTorso = character:FindFirstChild("UpperTorso")
	if upperTorso then
		-- R15: the arm hangs down (-Y); turning about X lifts it forward (-Z).
		lay(joint(character:FindFirstChild("RightUpperArm"), "RightShoulder"), CFrame.Angles(0, math.rad(8), 0) * CFrame.Angles(up, 0, 0), t)
		lay(joint(character:FindFirstChild("RightLowerArm"), "RightElbow"), CFrame.identity, t)
		lay(joint(character:FindFirstChild("RightHand"), "RightWrist"), CFrame.identity, t)
		lay(joint(character:FindFirstChild("LeftUpperArm"), "LeftShoulder"), CFrame.Angles(0, math.rad(-38), 0) * CFrame.Angles(up - math.rad(8), 0, 0), t)
		lay(joint(character:FindFirstChild("LeftLowerArm"), "LeftElbow"), CFrame.Angles(math.rad(12), 0, 0), t)
		lay(joint(character:FindFirstChild("LeftHand"), "LeftWrist"), CFrame.identity, t)
		return
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		-- R6: the shoulders swing about their Z axis (mirrored on the left).
		lay(joint(torso, "Right Shoulder"), CFrame.Angles(0, 0, up), t)
		lay(joint(torso, "Left Shoulder"), CFrame.Angles(0, 0, -(up - math.rad(10))), t)
	end
end

local function step(dt: number)
	local me = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local aiming: boolean, pitch: number
		if player == me then
			aiming, pitch = CameraRig.aimPose()
		else
			aiming = character:GetAttribute("Aiming") == true
			local p = character:GetAttribute("AimPitch")
			pitch = if type(p) == "number" then p else 0
		end
		if not humanoid or humanoid.Health <= 0 or humanoid.Sit then
			aiming = false
		end
		local blend = blends[character] or 0
		blend = if aiming then math.min(1, blend + dt / RAISE_TIME) else math.max(0, blend - dt / LOWER_TIME)
		if blend <= 0 then
			if blends[character] then
				pose(character, 0, 0) -- back to the animation (or the rest pose)
				blends[character] = nil
			end
			continue
		end
		blends[character] = blend
		-- Eased: quick at the start, settling at the top.
		local t = 1 - (1 - blend) * (1 - blend)
		pose(character, t, math.clamp(pitch, -1.1, 1.1))
	end
	for character in blends do
		if not character.Parent then
			blends[character] = nil
		end
	end
	for motor in rest do
		if not motor.Parent then
			rest[motor] = nil
		end
	end
end

function ArmPose.start()
	-- PreSimulation runs after the animations: what is set here is what everybody sees this frame.
	RunService.PreSimulation:Connect(step)
end

return ArmPose
