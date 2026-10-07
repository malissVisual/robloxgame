--!strict
-- 6.0: the courier's sprint and the bag that flies behind it, on every player's character within
-- Config.Courier.Sprint.Range of the camera (yours always), every frame in RunService.PreSimulation (after the Animator,
-- before the engine applies the joints; the Transform only, never C0: shared/Joints.luau).
--   * 6.0.1, the sprint is a real run cycle (shared/RunCycle.luau): faster than Sprint.From studs / s on foot (not
--     seated, climbing, swimming, in the air, on a zip line or a ladder, in a move of client/Interact.luau) the legs,
--     the arms, the waist, the neck and the body's bob on the Root joint are set ABSOLUTE (the rest pose times the
--     cycle's rotations, as client/BikeRider.luau's standing rider), blended in from the animation and back out over
--     Sprint.BlendTime; it lets go under Sprint.Off. The cycle's phase moves with the distance run (Sprint.Stride studs
--     a cycle), so the cadence follows the speed; the swing and the lean grow from From to Full. The walk and the
--     stock run under From are the animation's alone.
--   * The arms are left alone (blended back to the animation) while client/ArmPose.luau has them: aiming, carrying,
--     the phone, a gesture, a swing, a door's handle (their attributes, or yours from CameraRig / Holster) and 0.35 s
--     after; the legs, the waist, the head and the bob go on. ArmPose's own sprint lean steps aside meanwhile
--     (SprintPose.weight).
--   * The plastic bag (server/KitWear.luau: KitBagPivot in the character, hung from the left hand by the Motor6D
--     BagSwing): it hangs straight down at rest and swings back by the speed (Config.Courier.Bag: MaxTilt at
--     FullSpeed, a spring that overshoots a little), flutters and sways when fast and jolts with every step of the
--     cycle (Bag.Bounce). Its Transform turns it from where the hand holds it to that.
-- Joints are looked up once per character (again every RIG_REFRESH seconds, RIG_RETRY while some are missing, at once
-- when one left the body). The blend starts from the animation's own value of a joint (a joint that still holds what
-- we wrote was not written by the Animator this frame: its last animation value is the base, as in ArmPose). Let go
-- (slowing down, out of range, gone), a joint that still holds our value goes back to the rest pose (the identity; the
-- Animator writes over it where it animates; 5.9.1's lesson: a bob must never stay on the Root).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Joints = require(Shared.Joints)
local RunCycle = require(Shared.RunCycle)
local Bodies = require(script.Parent.Bodies)
local CameraRig = require(script.Parent.CameraRig)
local Holster = require(script.Parent.Holster)
local Interact = require(script.Parent.Interact)

local SprintPose = {}

local S = Config.Courier.Sprint
local B = Config.Courier.Bag
local RIG_REFRESH = 2 -- seconds a character's joints are kept before they are looked up again …
local RIG_RETRY = 0.5 -- … or this, while some are missing
local BUSY_FOR = 1.5 -- seconds after a gesture, a swing or a door's handle the arms stay ArmPose's
local ARMS_HOLD = 0.35 -- 6.0 review: and this long after ArmPose lets go (it lowers the arms for ~0.3 s)
local SWEEP = 5 -- seconds between the clean-ups of the characters and joints that are gone
local TAU = 2 * math.pi

-- The states the sprint is off in (the animation's own jump, fall, climb, swim, sit …).
local OFF_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Flying] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

type Rig = {
	lh: any, rh: any, lk: any, rk: any, ls: any, rs: any, le: any, re: any,
	waist: any, neck: any, root: any, bag: any, pivot: BasePart?, expires: number,
}
type Body = {
	weight: number, -- the cycle's share (0 = the animation alone)
	arms: number, -- the arms' share of it (0 while ArmPose has them)
	on: boolean, -- sprinting (From in, Off out)
	phase: number,
	effort: number,
	busyUntil: number,
	tilt: number, spin: number, flutter: number, swung: boolean, -- the bag
}

local rigs: { [Model]: Rig } = {}
local bodies: { [Model]: Body } = {}
-- Per joint: the Transform written last frame, and the animation's own value under it (as in client/ArmPose.luau).
local written: { [Instance]: CFrame } = {}
local animated: { [Instance]: CFrame } = {}
local pose = RunCycle.blank() -- (one table, filled per character)
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

-- `value` (absolute: the rest pose times the cycle) blended over the animation by `w`.
local function put(joint: any, value: CFrame, w: number)
	if not joint or not joint.Parent then
		return
	end
	local out = if w >= 0.999 then value else baseOf(joint):Lerp(value, w)
	joint.Transform = out
	written[joint] = out
end

-- The joint let go (once): back to the rest pose if it still holds what we wrote; a value the Animator (or ArmPose)
-- wrote this frame stays.
local function release(joint: any)
	if not joint then
		return
	end
	local mine = written[joint]
	if not mine then
		return
	end
	if joint.Parent and Joints.same(joint.Transform, mine) then
		joint.Transform = CFrame.identity
	end
	written[joint] = nil
	animated[joint] = nil
end

local function gone(joint: any): boolean
	return joint ~= nil and joint.Parent == nil
end

local function jointIn(character: Model, part: string, name: string): any
	return Joints.find(character:FindFirstChild(part), name)
end

local function intact(rig: Rig): boolean
	return not (gone(rig.lh) or gone(rig.rh) or gone(rig.lk) or gone(rig.rk) or gone(rig.ls) or gone(rig.rs)
		or gone(rig.le) or gone(rig.re) or gone(rig.waist) or gone(rig.neck) or gone(rig.root) or gone(rig.bag))
end

local function rigOf(character: Model): Rig
	local now = os.clock()
	local rig = rigs[character]
	if rig and now < rig.expires and intact(rig) then
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
		waist = if r15 then jointIn(character, "UpperTorso", "Waist") else nil,
		neck = if r15 then jointIn(character, "Head", "Neck") else nil,
		root = if r15 then jointIn(character, "LowerTorso", "Root") else nil,
		bag = Joints.find(pivot, "BagSwing"),
		pivot = pivot,
		expires = 0,
	}
	local complete = r15 and made.lh and made.rh and made.lk and made.rk and made.ls and made.rs and made.le and made.re
		and made.waist and made.neck and made.root
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
	release(rig.ls)
	release(rig.rs)
	release(rig.le)
	release(rig.re)
end

local function bodyBack(rig: Rig)
	release(rig.lh)
	release(rig.rh)
	release(rig.lk)
	release(rig.rk)
	release(rig.waist)
	release(rig.neck)
	release(rig.root)
end

-- A character out of range (or gone): everything back to the rest pose, the bag hanging from the hand as it is held.
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
	bodyBack(rig)
	local bag = rig.bag
	if bag and bag.Parent and body.swung then
		bag.Transform = CFrame.identity
	end
end

-- Can this body sprint now (on its feet, nothing else moving it)?
local function onFoot(character: Model, humanoid: Humanoid, mine: boolean): boolean
	if humanoid.Health <= 0 or humanoid.Sit or humanoid.SeatPart ~= nil or humanoid.PlatformStand then
		return false
	end
	local state = humanoid:GetState()
	if OFF_STATES[state] or (mine and state == Enum.HumanoidStateType.Physics) then
		return false
	end
	return character:GetAttribute("ZipLine") == nil and character:GetAttribute("ClimbLine") == nil
		and not Interact.posing(character)
end

-- The run cycle into the joints: the legs, the waist, the neck and the Root by `w`, the arms by `wa`.
local function run(rig: Rig, w: number, wa: number, phase: number, effort: number)
	local p = RunCycle.pose(phase, effort, pose)
	put(rig.rh, CFrame.Angles(p.rightHip, 0, 0), w)
	put(rig.lh, CFrame.Angles(p.leftHip, 0, 0), w)
	put(rig.rk, CFrame.Angles(p.rightKnee, 0, 0), w)
	put(rig.lk, CFrame.Angles(p.leftKnee, 0, 0), w)
	put(rig.waist, CFrame.Angles(p.lean, 0, 0) * CFrame.Angles(0, p.twist, 0), w)
	put(rig.neck, CFrame.Angles(0, p.neckTurn, 0) * CFrame.Angles(p.neckPitch, 0, 0), w)
	put(rig.root, CFrame.new(0, p.bob, 0) * CFrame.Angles(0, p.hipTurn, 0), w)
	if wa > 0.001 then
		put(rig.rs, CFrame.Angles(0, p.inward, 0) * CFrame.Angles(p.rightShoulder, 0, 0), wa)
		put(rig.ls, CFrame.Angles(0, -p.inward, 0) * CFrame.Angles(p.leftShoulder, 0, 0), wa)
		put(rig.re, CFrame.Angles(p.rightElbow, 0, 0), wa)
		put(rig.le, CFrame.Angles(p.leftElbow, 0, 0), wa)
	elseif written[rig.rs] or written[rig.ls] or written[rig.re] or written[rig.le] then
		armsBack(rig)
	end
end

-- The bag flies behind by the speed: a spring toward the tilt, a flutter and a sway when fast, a jolt every step.
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
	body.flutter += dt * B.FlutterHz * TAU * math.max(0.25, fast)
	-- (6.0.1: with each footfall of the cycle, phase 0.1 / 0.6, it drops forward, and flies back up between)
	local jolt = math.rad(B.Bounce) * body.weight * -math.cos(2 * TAU * (body.phase - 0.1))
	local tilt = body.tilt + math.rad(B.Flutter) * fast * math.sin(body.flutter) + jolt
	local sway = math.rad(B.Sway) * math.sin(body.flutter * 0.5) * (0.3 + fast)
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
	local rate = dt / math.max(S.BlendTime, 0.01)
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
			body = { weight = 0, arms = 0, on = false, phase = 0, effort = 0, busyUntil = 0, tilt = 0, spin = 0, flutter = 0, swung = false }
			bodies[character] = body
		end
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local can = rig.lh ~= nil and rig.root ~= nil and rig.waist ~= nil and onFoot(character, humanoid, mine)
		body.on = can and speed > (if body.on then S.Off else S.From)
		local was = body.weight
		local w = math.clamp(was + math.clamp((if body.on then 1 else 0) - was, -rate, rate), 0, 1)
		body.weight = w
		body.phase = RunCycle.advance(body.phase, speed * dt, S.Stride)
		body.effort += (RunCycle.effort(speed, S.From, S.Full) - body.effort) * math.min(1, dt * 6)
		if w > 0.001 then
			local free = armsFree(character, mine)
			local now = os.clock()
			if not free then
				body.busyUntil = now + ARMS_HOLD
			elseif now < body.busyUntil then
				free = false
			end
			-- (a sprint starting takes the free arms along with the rest: they blend in with `w`)
			body.arms = if was <= 0.001 then (if free then 1 else 0)
				else math.clamp(body.arms + math.clamp((if free then 1 else 0) - body.arms, -rate, rate), 0, 1)
			run(rig, w, w * body.arms, body.phase, body.effort)
		elseif written[rig.root] or written[rig.lh] or written[rig.rs] or written[rig.ls] then
			armsBack(rig)
			bodyBack(rig)
			body.arms = 0
		end
		swingBag(rig, body, root, dt)
	end
	sweep(os.clock())
end

-- The sprint cycle's share on this character now (0..1; client/ArmPose.luau leaves the waist's sprint lean to it).
function SprintPose.weight(character: Model): number
	local body = bodies[character]
	return if body then body.weight else 0
end

function SprintPose.start()
	RunService.PreSimulation:Connect(step)
end

return SprintPose
