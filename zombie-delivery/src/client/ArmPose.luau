--!strict
-- The gun arms. Aiming on foot, every character's arms come up and point the gun where it aims (up or down too):
-- the right arm straight forward, the left hand under the gun. The pose goes into the shoulder, elbow and wrist
-- joints' Transform every frame in RunService.PreSimulation, after the Animator wrote the walk animation and before
-- the engine applies it, blended smoothly in and out. The joints can be Motor6Ds or, since Roblox's Avatar Joint
-- Upgrade, AnimationConstraints (shared/Joints.luau); C0 is never touched (read-only on the new joints).
-- Your own character follows your camera directly; the others follow the Aiming / AimPitch attributes the server
-- sets on their characters. The bandits (client/ZombieAnimator.luau) hold their guns up with the same pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Joints = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Joints"))
local CameraRig = require(script.Parent.CameraRig)

local ArmPose = {}

local RAISE_TIME = 0.2 -- seconds for the arms to come up
local LOWER_TIME = 0.3
local blends: { [Model]: number } = {}
-- Per joint: the Transform written last frame, and the animation's own value under it. A joint that still holds
-- our value was not written by the Animator this frame (throttled, or no track moves it): the last animation
-- value is the base then, so the pose never piles up on itself and an arm never stays stuck up.
-- (Plain tables, cleaned up when a joint goes away: Roblox may collect an Instance's Lua handle from a weak table
-- while the Instance still exists.)
local written: { [Instance]: CFrame } = {}
local animated: { [Instance]: CFrame } = {}
local reported = false
-- Recoil: every shot kicks the arms up a little, then they settle back on the aim.
local kicks: { [Model]: number } = {}
local KICK: { [string]: number } = { pistol = 1, smg = 0.45, shotgun = 1.9, rifle = 1.5, minigun = 0.3, launcher = 2 }

function ArmPose.kick(character: Model)
	local gun = character:FindFirstChild("HandGun")
	local weapon = gun and gun:GetAttribute("Weapon")
	local strength = KICK[if type(weapon) == "string" then weapon else "pistol"] or 1
	kicks[character] = math.min(2.5, (kicks[character] or 0) + strength)
end
-- The animation's own value of a joint this frame (see `written` above).
local function baseOf(joint: any): CFrame
	local live: CFrame = joint.Transform
	local mine = written[joint]
	if mine and Joints.same(live, mine) then
		return animated[joint] or CFrame.identity
	end
	animated[joint] = live
	return live
end

local function lay(joint: any, goal: CFrame, t: number)
	if not joint or not joint.Parent then
		return
	end
	local base = baseOf(joint)
	if t <= 0 then
		joint.Transform = base
		written[joint] = nil
		animated[joint] = nil
		return
	end
	local out = base:Lerp(goal, t)
	joint.Transform = out
	written[joint] = out
end

-- Laid ON TOP of the animation (the walk keeps going under it); `rotation` = nil gives the joint back.
local function layer(joint: any, rotation: CFrame?)
	if not joint or not joint.Parent then
		return
	end
	local base = baseOf(joint)
	if not rotation then
		joint.Transform = base
		written[joint] = nil
		animated[joint] = nil
		return
	end
	local out = base * rotation
	joint.Transform = out
	written[joint] = out
end

local function jointIn(character: Model, partName: string, jointName: string): any
	return Joints.find(character:FindFirstChild(partName), jointName)
end

-- The aim pose on a character: t = 0 (the animation alone) .. 1 (the gun up), pitch in radians (+ is up).
function ArmPose.apply(character: Model, t: number, pitch: number)
	local kick = kicks[character] or 0
	local up = math.rad(90) + pitch + kick * 0.11
	if character:FindFirstChild("UpperTorso") then
		-- R15: an arm hangs down (-Y); turning about X lifts it forward (-Z), about Y swings it in or out.
		lay(jointIn(character, "RightUpperArm", "RightShoulder"), CFrame.Angles(0, math.rad(8), 0) * CFrame.Angles(up, 0, 0), t)
		lay(jointIn(character, "RightLowerArm", "RightElbow"), CFrame.Angles(kick * 0.08, 0, 0), t)
		lay(jointIn(character, "RightHand", "RightWrist"), CFrame.identity, t)
		lay(jointIn(character, "LeftUpperArm", "LeftShoulder"), CFrame.Angles(0, math.rad(-38), 0) * CFrame.Angles(up - math.rad(8), 0, 0), t)
		lay(jointIn(character, "LeftLowerArm", "LeftElbow"), CFrame.Angles(math.rad(12), 0, 0), t)
		lay(jointIn(character, "LeftHand", "LeftWrist"), CFrame.identity, t)
		return
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		-- R6: the shoulders swing about their Z axis (mirrored on the left).
		lay(Joints.find(torso, "Right Shoulder"), CFrame.Angles(0, 0, up), t)
		lay(Joints.find(torso, "Left Shoulder"), CFrame.Angles(0, 0, -(up - math.rad(10))), t)
	end
end

-- Once, the first time you aim: which joint moves your arm (or a warning that none was found), for the Output.
local function report(character: Model)
	if reported then
		return
	end
	reported = true
	local joint = if character:FindFirstChild("UpperTorso")
		then jointIn(character, "RightUpperArm", "RightShoulder")
		else Joints.find(character:FindFirstChild("Torso"), "Right Shoulder")
	if joint then
		print(`[ArmPose] aiming: the gun arm moves through a {joint.ClassName}`)
	else
		warn("[ArmPose] no shoulder joint found on your character: the arms cannot come up")
	end
end

-- The body's weight: leaning into a sprint, leaning back when braking hard (out of a sprint into aiming).
type Lean = { amount: number, speed: number }
local leans: { [Model]: Lean } = {}
local LEAN_SPRINT = math.rad(9) -- forward at a full sprint
local LEAN_BRAKE = math.rad(7) -- back while braking hard

local function leanBody(character: Model, humanoid: Humanoid?, dt: number)
	local waist = jointIn(character, "UpperTorso", "Waist")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not waist or not root or not root:IsA("BasePart") then
		return
	end
	local state = leans[character]
	if not state then
		state = { amount = 0, speed = 0 }
		leans[character] = state
	end
	local velocity = root.AssemblyLinearVelocity
	local now = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local braking = math.max(0, state.speed - now) / math.max(dt, 1 / 240)
	state.speed = now
	local onFoot = humanoid ~= nil and humanoid.Health > 0 and not humanoid.Sit
	local goal = if onFoot
		then LEAN_SPRINT * math.clamp((now - 12) / 9, 0, 1) - LEAN_BRAKE * math.clamp((braking - 15) / 40, 0, 1)
		else 0
	state.amount += (goal - state.amount) * math.min(1, dt * 8)
	if math.abs(state.amount) < 0.002 and math.abs(goal) < 0.002 then
		if written[waist] then
			layer(waist, nil)
		end
		state.amount = 0
		return
	end
	-- About X: negative tips the upper body forward.
	layer(waist, CFrame.Angles(-state.amount, 0, 0))
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
		if aiming and player == me then
			report(character)
		end
		if character:FindFirstChild("UpperTorso") then
			leanBody(character, humanoid, dt)
		end
		-- Yours come up slower out of a sprint (CameraRig decides); the others' at the normal pace.
		local raise = if player == me then math.max(0.1, CameraRig.raiseTime() - 0.05) else RAISE_TIME
		local blend = blends[character] or 0
		blend = if aiming then math.min(1, blend + dt / raise) else math.max(0, blend - dt / LOWER_TIME)
		if blend <= 0 then
			if blends[character] then
				ArmPose.apply(character, 0, 0) -- back to the animation alone
				blends[character] = nil
			end
			continue
		end
		blends[character] = blend
		-- Eased: quick at the start, settling at the top.
		local t = 1 - (1 - blend) * (1 - blend)
		ArmPose.apply(character, t, math.clamp(pitch, -1.1, 1.1))
	end
	for character in blends do
		if not character.Parent then
			blends[character] = nil
		end
	end
	for character, kick in kicks do
		local left = kick * math.exp(-dt * 14)
		if left > 0.01 and character.Parent then
			kicks[character] = left
		else
			kicks[character] = nil
		end
	end
	for character in leans do
		if not character.Parent then
			leans[character] = nil
		end
	end
	for joint in written do
		if not joint.Parent then
			written[joint] = nil
			animated[joint] = nil
		end
	end
end

function ArmPose.start()
	-- PreSimulation runs after the Animator and before the engine applies the joints: what is written here is what
	-- this client shows (a write in RenderStepped or Heartbeat would be overwritten by the next animation step).
	RunService.PreSimulation:Connect(step)
end

return ArmPose
