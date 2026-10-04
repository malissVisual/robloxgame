--!strict
-- The gun arms. Aiming on foot, every character's arms come up and point the gun where it aims (up or down too):
-- the right arm straight forward, the left hand under the gun. The pose goes into the shoulder, elbow and wrist
-- joints' Transform every frame in RunService.PreSimulation, after the Animator wrote the walk animation and before
-- the engine applies it, blended smoothly in and out. The joints can be Motor6Ds or, since Roblox's Avatar Joint
-- Upgrade, AnimationConstraints (shared/Joints.luau); C0 is never touched (read-only on the new joints).
-- Your own character follows your camera directly; the others follow the Aiming / AimPitch attributes the server
-- sets on their characters. The bandits (client/ZombieAnimator.luau) hold their guns up with the same pose.
-- Cargo: every character with the Carrying attribute (server/Cargo.luau; players and the people in workspace.Npcs)
-- holds it: both upper arms forward-down, the forearms forward under the box at chest height (the gun in the hand
-- is hidden meanwhile); "horse" is a lead: the right hand a little forward on the rope. Blended in and out too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Joints = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Joints"))
local CameraRig = require(script.Parent.CameraRig)

local ArmPose = {}

local RAISE_TIME = 0.2 -- seconds for the arms to come up
local LOWER_TIME = 0.3
local CARRY_IN = 0.25 -- seconds to take the cargo into the arms
local CARRY_OUT = 0.3
local NPC_RANGE = 180 -- people farther from the camera than this are not posed
local blends: { [Model]: number } = {}
-- The carry pose per character: how far in (0..1) and what is held (kept while it blends out).
type Carry = { t: number, kind: string }
local carries: { [Model]: Carry } = {}
local hiddenGuns: { [Model]: Instance } = {}
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

-- The joint goes from the animation toward `aim` (by aimT) and then toward `carry` (by carryT); either may be nil.
-- Both 0 gives the joint back to the animation.
local function lay(joint: any, aim: CFrame?, aimT: number, carry: CFrame?, carryT: number)
	if not joint or not joint.Parent then
		return
	end
	local base = baseOf(joint)
	local out = base
	if aim and aimT > 0 then
		out = out:Lerp(aim, aimT)
	end
	if carry and carryT > 0 then
		out = out:Lerp(carry, carryT)
	end
	if out == base then
		joint.Transform = base
		written[joint] = nil
		animated[joint] = nil
		return
	end
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

-- The carry poses (R15). Per kind: how far the upper arms come forward, the elbow bend that brings the forearms
-- level under the load, and how far the arms turn in toward it (big things are held wider).
type CarryShape = { shoulder: number, elbow: number, inward: number }
local CARRY_SHAPES: { [string]: CarryShape } = {
	crate = { shoulder = 32, elbow = 62, inward = 12 },
	ammo = { shoulder = 30, elbow = 64, inward = 14 },
	sack = { shoulder = 28, elbow = 70, inward = 16 },
	barrel = { shoulder = 36, elbow = 56, inward = 8 },
	icebox = { shoulder = 34, elbow = 60, inward = 9 },
	furniture = { shoulder = 40, elbow = 52, inward = 4 },
	soup = { shoulder = 26, elbow = 68, inward = 18 },
}
local DEFAULT_SHAPE = CARRY_SHAPES.crate

type ArmGoals = { rs: CFrame?, re: CFrame?, rw: CFrame?, ls: CFrame?, le: CFrame?, lw: CFrame? }

local function carryGoals(kind: string?): ArmGoals
	if kind == nil then
		return {} :: ArmGoals
	end
	if kind == "horse" then
		-- Leading on a rope: the right hand a little forward and out, the elbow soft; the left arm swings free.
		return {
			rs = CFrame.Angles(0, math.rad(-6), 0) * CFrame.Angles(math.rad(24), 0, math.rad(4)),
			re = CFrame.Angles(math.rad(26), 0, 0),
			rw = CFrame.Angles(math.rad(-10), 0, 0),
		}
	end
	local shape = CARRY_SHAPES[kind] or DEFAULT_SHAPE
	local inward = math.rad(shape.inward)
	return {
		rs = CFrame.Angles(0, inward, 0) * CFrame.Angles(math.rad(shape.shoulder), 0, 0),
		re = CFrame.Angles(math.rad(shape.elbow), 0, 0),
		rw = CFrame.Angles(0, math.rad(-10), 0),
		ls = CFrame.Angles(0, -inward, 0) * CFrame.Angles(math.rad(shape.shoulder), 0, 0),
		le = CFrame.Angles(math.rad(shape.elbow), 0, 0),
		lw = CFrame.Angles(0, math.rad(10), 0),
	}
end

-- Both poses on a character: aim (t 0..1, pitch in radians, + is up) and carry (t 0..1, the kind held).
local function pose(character: Model, aimT: number, pitch: number, carryT: number, kind: string?)
	local kick = kicks[character] or 0
	local up = math.rad(90) + pitch + kick * 0.11
	local c: ArmGoals = carryGoals(if carryT > 0 then kind else nil)
	if character:FindFirstChild("UpperTorso") then
		-- R15: an arm hangs down (-Y); turning about X lifts it forward (-Z), about Y swings it in or out.
		lay(jointIn(character, "RightUpperArm", "RightShoulder"), CFrame.Angles(0, math.rad(8), 0) * CFrame.Angles(up, 0, 0), aimT, c.rs, carryT)
		lay(jointIn(character, "RightLowerArm", "RightElbow"), CFrame.Angles(kick * 0.08, 0, 0), aimT, c.re, carryT)
		lay(jointIn(character, "RightHand", "RightWrist"), CFrame.identity, aimT, c.rw, carryT)
		lay(jointIn(character, "LeftUpperArm", "LeftShoulder"), CFrame.Angles(0, math.rad(-38), 0) * CFrame.Angles(up - math.rad(8), 0, 0), aimT, c.ls, carryT)
		lay(jointIn(character, "LeftLowerArm", "LeftElbow"), CFrame.Angles(math.rad(12), 0, 0), aimT, c.le, carryT)
		lay(jointIn(character, "LeftHand", "LeftWrist"), CFrame.identity, aimT, c.lw, carryT)
		return
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		-- R6: the shoulders swing about their Z axis (mirrored on the left); no elbows, so the arms come well forward.
		local lead = kind == "horse"
		local rightCarry = if carryT > 0 then CFrame.Angles(0, 0, math.rad(if lead then 25 else 75)) else nil
		local leftCarry = if carryT > 0 and not lead then CFrame.Angles(0, 0, -math.rad(75)) else nil
		lay(Joints.find(torso, "Right Shoulder"), CFrame.Angles(0, 0, up), aimT, rightCarry, carryT)
		lay(Joints.find(torso, "Left Shoulder"), CFrame.Angles(0, 0, -(up - math.rad(10))), aimT, leftCarry, carryT)
	end
end

-- The aim pose on a character: t = 0 (the animation alone) .. 1 (the gun up), pitch in radians (+ is up).
function ArmPose.apply(character: Model, t: number, pitch: number)
	pose(character, t, pitch, 0, nil)
end

-- What a character holds (the server's Carrying attribute), or nil.
local function carryingOf(character: Model): string?
	local value = character:GetAttribute("Carrying")
	return if type(value) == "string" and value ~= "" then value else nil
end

-- The gun in the hand is hidden (on this client) while the hands hold cargo, and comes back after.
local function showGun(character: Model, visible: boolean)
	local gun = character:FindFirstChild("HandGun")
	local hidden = hiddenGuns[character]
	if visible then
		if hidden then
			hiddenGuns[character] = nil
			if hidden.Parent then
				for _, part in hidden:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = 0
					end
				end
			end
		end
		return
	end
	if gun and gun ~= hidden then
		hiddenGuns[character] = gun
		local parts = gun:GetDescendants()
		table.insert(parts, gun)
		for _, part in parts do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
			end
		end
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

local function ease(blend: number): number
	-- Quick at the start, settling at the end.
	return 1 - (1 - blend) * (1 - blend)
end

-- One character this frame: the aim and the carry pose blend in or out and go onto the joints.
local function poseCharacter(character: Model, humanoid: Humanoid?, aiming: boolean, pitch: number, raise: number, dt: number)
	local alive = humanoid ~= nil and humanoid.Health > 0 and not humanoid.Sit
	local kind = if alive then carryingOf(character) else nil
	-- Hands full: no gun.
	if kind or not alive then
		aiming = false
	end
	if kind then
		showGun(character, false)
	elseif hiddenGuns[character] then
		showGun(character, true)
	end
	local blend = blends[character] or 0
	blend = if aiming then math.min(1, blend + dt / raise) else math.max(0, blend - dt / LOWER_TIME)
	local carry = carries[character]
	local carryBlend = if carry then carry.t else 0
	carryBlend = if kind then math.min(1, carryBlend + dt / CARRY_IN) else math.max(0, carryBlend - dt / CARRY_OUT)
	if blend <= 0 and carryBlend <= 0 then
		if blends[character] or carry then
			pose(character, 0, 0, 0, nil) -- back to the animation alone
			blends[character] = nil
			carries[character] = nil
		end
		return
	end
	if blend > 0 then
		blends[character] = blend
	else
		blends[character] = nil
	end
	local held: string? = nil
	if carryBlend > 0 then
		-- While it blends out the arms keep the shape of what they held.
		held = kind or (if carry then carry.kind else nil) or "crate"
		if carry then
			carry.t = carryBlend
			carry.kind = held :: string
		else
			carries[character] = { t = carryBlend, kind = held :: string }
		end
	else
		carries[character] = nil
	end
	pose(character, ease(blend), math.clamp(pitch, -1.1, 1.1), ease(carryBlend), held)
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
		if aiming and player == me and humanoid and humanoid.Health > 0 and not humanoid.Sit then
			report(character)
		end
		if character:FindFirstChild("UpperTorso") then
			leanBody(character, humanoid, dt)
		end
		-- Yours come up slower out of a sprint (CameraRig decides); the others' at the normal pace.
		local raise = if player == me then math.max(0.1, CameraRig.raiseTime() - 0.05) else RAISE_TIME
		poseCharacter(character, humanoid, aiming, pitch, raise, dt)
	end
	-- The people of the world (givers, receivers) carry too.
	local npcs = workspace:FindFirstChild("Npcs")
	local camera = workspace.CurrentCamera
	if npcs and camera then
		local eye = camera.CFrame.Position
		for _, model in npcs:GetChildren() do
			if not model:IsA("Model") or (not carries[model] and not carryingOf(model)) then
				continue
			end
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - eye).Magnitude <= NPC_RANGE then
				poseCharacter(model, model:FindFirstChildOfClass("Humanoid"), false, 0, RAISE_TIME, dt)
			end
		end
	end
	for character in carries do
		if not character.Parent then
			carries[character] = nil
		end
	end
	for character in hiddenGuns do
		if not character.Parent then
			hiddenGuns[character] = nil
		end
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
