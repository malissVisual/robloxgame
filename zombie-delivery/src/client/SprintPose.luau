--!strict
-- 6.0: the courier's sprint and the bag that flies behind it, on every player's character within
-- Config.Courier.Sprint.Range of the camera (yours always), every frame in RunService.PreSimulation (after the Animator,
-- before the engine applies the joints; the Transform only, never C0: shared/Joints.luau).
--   * The sprint: from Sprint.From studs / s on foot (all on at Full; the run animation keeps going under it) the hips
--     swing Stride farther than the animation's own swing, the knees bend Knee more, the shoulders pump Arms farther
--     and the elbows bend Elbow degrees more. The forward lean is client/ArmPose.luau's (the waist), as before. The
--     arms are left alone while ArmPose has them: aiming, carrying, the phone, a gesture, a swing, a door's handle
--     (their attributes, or yours from CameraRig / Holster), and nothing is laid on a zip line or a ladder.
--   * The plastic bag (server/KitWear.luau: KitBagPivot in the character, hung from the left hand by the Motor6D
--     BagSwing): it hangs straight down at rest and swings back by the speed (Config.Courier.Bag: MaxTilt at
--     FullSpeed, a spring that overshoots a little), flutters and sways when fast. Its Transform turns it from where
--     the hand holds it to that.
-- Joints are looked up once per character (again every RIG_REFRESH seconds, RIG_RETRY while some are missing, at once
-- when one left the body), the far ones (and the ones going out of range) are given back to the animation once. Like
-- ArmPose: a joint that still holds what we wrote was not written by the Animator this frame, so its last animation
-- value is the base (the pose never piles up on itself).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Joints = require(Shared.Joints)
local Bodies = require(script.Parent.Bodies)
local CameraRig = require(script.Parent.CameraRig)
local Holster = require(script.Parent.Holster)

local SprintPose = {}

local S = Config.Courier.Sprint
local B = Config.Courier.Bag
local RIG_REFRESH = 2 -- seconds a character's joints are kept before they are looked up again …
local RIG_RETRY = 0.5 -- … or this, while some are missing
local BUSY_FOR = 1.5 -- seconds after a gesture, a swing or a door's handle the arms stay ArmPose's
local SWEEP = 5 -- seconds between the clean-ups of the characters and joints that are gone

type Rig = { lh: any, rh: any, lk: any, rk: any, ls: any, rs: any, le: any, re: any, bag: any, pivot: BasePart?, expires: number }
type Body = { weight: number, arms: boolean, tilt: number, spin: number, phase: number, swung: boolean }

local rigs: { [Model]: Rig } = {}
local bodies: { [Model]: Body } = {}
-- Per joint: the Transform written last frame, and the animation's own value under it (as in client/ArmPose.luau).
local written: { [Instance]: CFrame } = {}
local animated: { [Instance]: CFrame } = {}
local sweptAt = 0

local function baseOf(joint: any): CFrame
	local live: CFrame = joint.Transform
	local mine = written[joint]
	if mine and Joints.same(live, mine) then
		return animated[joint] or CFrame.identity
	end
	animated[joint] = live
	return live
end

-- The joint back to the animation alone (once).
local function giveBack(joint: any)
	if not joint or not written[joint] then
		return
	end
	if joint.Parent then
		joint.Transform = baseOf(joint)
	end
	written[joint] = nil
	animated[joint] = nil
end

-- The animation's own swing about X, `k` times more on top of it, and `extra` radians more (a bend).
local function lay(joint: any, k: number, extra: number)
	if not joint or not joint.Parent then
		return
	end
	if k <= 0.001 and math.abs(extra) <= 0.001 then
		giveBack(joint)
		return
	end
	local base = baseOf(joint)
	local rx = base:ToEulerAnglesXYZ()
	local out = base * CFrame.Angles(rx * k + extra, 0, 0)
	joint.Transform = out
	written[joint] = out
end

local function gone(joint: any): boolean
	return joint ~= nil and joint.Parent == nil
end

local function jointIn(character: Model, part: string, name: string): any
	return Joints.find(character:FindFirstChild(part), name)
end

local function rigOf(character: Model): Rig
	local now = os.clock()
	local rig = rigs[character]
	if rig and now < rig.expires and not (gone(rig.lh) or gone(rig.rh) or gone(rig.lk) or gone(rig.rk) or gone(rig.ls) or gone(rig.rs) or gone(rig.le) or gone(rig.re) or gone(rig.bag)) then
		return rig
	end
	local r15 = character:FindFirstChild("UpperTorso") ~= nil
	local found = character:FindFirstChild("KitBagPivot")
	local pivot = if found and found:IsA("BasePart") then found else nil
	local made: Rig = {
		lh = if r15 then jointIn(character, "LeftUpperLeg", "LeftHip") else nil,
		rh = if r15 then jointIn(character, "RightUpperLeg", "RightHip") else nil,
		lk = if r15 then jointIn(character, "LeftLowerLeg", "LeftKnee") else nil,
		rk = if r15 then jointIn(character, "RightLowerLeg", "RightKnee") else nil,
		ls = if r15 then jointIn(character, "LeftUpperArm", "LeftShoulder") else nil,
		rs = if r15 then jointIn(character, "RightUpperArm", "RightShoulder") else nil,
		le = if r15 then jointIn(character, "LeftLowerArm", "LeftElbow") else nil,
		re = if r15 then jointIn(character, "RightLowerArm", "RightElbow") else nil,
		bag = Joints.find(pivot, "BagSwing"),
		pivot = pivot,
		expires = 0,
	}
	local complete = r15 and made.lh and made.rh and made.lk and made.rk and made.ls and made.rs and made.le and made.re
	made.expires = now + (if complete then RIG_REFRESH else RIG_RETRY)
	rigs[character] = made
	return made
end

local function recent(character: Model, name: string): boolean
	local at = character:GetAttribute(name)
	return type(at) == "number" and workspace:GetServerTimeNow() - at < BUSY_FOR
end

-- Are the arms free for the sprint (not ArmPose's right now)?
local function armsFree(character: Model, mine: boolean): boolean
	if character:GetAttribute("Carrying") ~= nil or character:GetAttribute("PhoneHeld") == true then
		return false
	end
	if mine then
		local aiming = CameraRig.aimPose()
		local swingAt = Holster.localSwing()
		if aiming or (swingAt ~= nil and os.clock() - swingAt < BUSY_FOR) then
			return false
		end
	elseif character:GetAttribute("Aiming") == true or recent(character, "MeleeAt") then
		return false
	end
	return not (recent(character, "GestureAt") or recent(character, "BoardAt") or recent(character, "AlightAt"))
end

local function armsBack(rig: Rig)
	giveBack(rig.ls)
	giveBack(rig.rs)
	giveBack(rig.le)
	giveBack(rig.re)
end

-- A character out of range (or gone): everything given back, the bag hanging from the hand as it is held.
local function letGo(character: Model)
	local body = bodies[character]
	if not body then
		return
	end
	bodies[character] = nil
	local rig = rigs[character]
	if not rig then
		return
	end
	armsBack(rig)
	for _, joint in { rig.lh, rig.rh, rig.lk, rig.rk } do
		giveBack(joint)
	end
	local bag = rig.bag
	if bag and bag.Parent and body.swung then
		bag.Transform = CFrame.identity
	end
end

-- The bag flies behind by the speed: a spring toward the tilt, a flutter and a sway when fast.
local function swingBag(rig: Rig, body: Body, root: BasePart, dt: number)
	local joint, pivot = rig.bag, rig.pivot
	if not joint or not pivot or not joint.Parent or not pivot.Parent then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local fast = math.clamp(flat.Magnitude / B.FullSpeed, 0, 1)
	local goal = math.rad(B.MaxTilt) * fast
	body.spin += (B.Spring * (goal - body.tilt) - B.Damp * body.spin) * dt
	body.tilt += body.spin * dt
	body.phase += dt * B.FlutterHz * 2 * math.pi * math.max(0.25, fast)
	local tilt = body.tilt + math.rad(B.Flutter) * fast * math.sin(body.phase)
	local sway = math.rad(B.Sway) * math.sin(body.phase * 0.5) * (0.3 + fast)
	local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local ahead = if flat.Magnitude > 1 then flat.Unit elseif facing.Magnitude > 0.01 then facing.Unit else Vector3.new(0, 0, -1)
	local side = ahead:Cross(Vector3.yAxis)
	-- The bag hangs down from the grip: its up leans forward as the bag goes back, and sways to the sides.
	local up = (Vector3.yAxis * math.cos(tilt) + ahead * math.sin(tilt)) * math.cos(sway) + side * math.sin(sway)
	local right = side - up * side:Dot(up)
	if right.Magnitude < 1e-3 then
		return
	end
	local want = CFrame.fromMatrix(pivot.Position, right.Unit, up.Unit)
	-- (pivot = hand · C0 · Transform: the new Transform turns the pivot from where it is to `want`)
	joint.Transform = (joint.Transform * pivot.CFrame:Inverse() * want).Rotation
	body.swung = true
end

local function sweep(now: number)
	if now - sweptAt < SWEEP then
		return
	end
	sweptAt = now
	for character in rigs do
		if not character.Parent then
			rigs[character] = nil
			bodies[character] = nil
		end
	end
	for joint in written do
		if not joint.Parent then
			written[joint] = nil
			animated[joint] = nil
		end
	end
end

local function step(dt: number)
	local me = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	for _, player in Bodies.players() do
		local character = player.Character
		if not character then
			continue
		end
		local mine = player == me
		local humanoid, root = Bodies.of(character)
		if not humanoid or not root or (not mine and eye and (root.Position - eye).Magnitude > S.Range) then
			letGo(character)
			continue
		end
		local rig = rigOf(character)
		local body = bodies[character]
		if not body then
			body = { weight = 0, arms = false, tilt = 0, spin = 0, phase = 0, swung = false }
			bodies[character] = body
		end
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local onFoot = humanoid.Health > 0 and not humanoid.Sit and humanoid.SeatPart == nil
			and character:GetAttribute("ZipLine") == nil and character:GetAttribute("ClimbLine") == nil
		local goal = if onFoot and rig.lh then math.clamp((speed - S.From) / math.max(0.1, S.Full - S.From), 0, 1) else 0
		local w = body.weight + math.clamp(goal - body.weight, -S.Blend * dt, S.Blend * dt)
		body.weight = w
		if w > 0.001 then
			lay(rig.lh, S.Stride * w, 0)
			lay(rig.rh, S.Stride * w, 0)
			lay(rig.lk, S.Knee * w, 0)
			lay(rig.rk, S.Knee * w, 0)
			local arms = armsFree(character, mine)
			if arms then
				lay(rig.ls, S.Arms * w, 0)
				lay(rig.rs, S.Arms * w, 0)
				lay(rig.le, 0, math.rad(S.Elbow) * w)
				lay(rig.re, 0, math.rad(S.Elbow) * w)
			elseif body.arms then
				armsBack(rig)
			end
			body.arms = arms
		elseif body.arms or written[rig.lh] then
			for _, joint in { rig.lh, rig.rh, rig.lk, rig.rk } do
				giveBack(joint)
			end
			armsBack(rig)
			body.arms = false
		end
		swingBag(rig, body, root, dt)
	end
	sweep(os.clock())
end

function SprintPose.start()
	RunService.PreSimulation:Connect(step)
end

return SprintPose
