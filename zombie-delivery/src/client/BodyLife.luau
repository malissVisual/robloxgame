--!strict
-- 6.7: the life in the bodies between the stock animations (the owner: "no animations"). On every player's character
-- and every person in workspace.Npcs within Config.Body.Range of the camera (yours always; at most MaxPosed, the
-- nearest), every frame in RunService.PreSimulation, laid over the Animator's tracks through client/PoseLedger.luau (the
-- joints' Transform only, never C0: shared/Joints.luau). The maths is shared/BodyMotion.luau's, the numbers Config.Body.
--   * standing still: the breath (the chest tips back and the shoulders rise on a breath in; quicker and deeper after a
--     sprint), the weight shifting from one foot to the other every few seconds (the hips sway and tip, the free knee
--     bends, the legs keep the feet where they stand), blinks (the eyes' sphere meshes squeezed shut);
--   * the head turns to a person or a courier near and in front (your own courier also to the job's ring), the chest a
--     little with it, smoothly; the people look at the players who come up to them;
--   * walking (WalkFrom studs / s up to the sprint, where client/SprintPose.luau's run takes over and this fades out):
--     the weight read off the stock walk's own thighs: the body sinks with the legs apart, the arms swing a little more,
--     the chest turns against the hips, the head stays steady;
--   * landing from a jump or a fall: a knee dip by the fall's speed (the hips down, the legs bent with the feet
--     planted, the upper body forward);
--   * hit (health lost): a flinch, the chest jerked back, the head turned away;
--   (the bag in the hand holds its arm out itself: client/BagSway.luau, 6.7 A)
-- The arms are client/ArmPose.luau's while it has them (ArmPose.armsBusy: the aim, the carry, the phone, a swing, a
-- gesture), the waist, the head and the legs while a gesture bends the body (ArmPose.legsBusy: the pick-up). Nothing
-- moves in a seat, on a zip line or a ladder, swimming, climbing, dead or in an interaction move (client/Interact.luau):
-- the joints go back to the animation. Beyond Config.Body.Detail studs only the landing, the flinch and the walk's
-- weight are drawn. Joints and eyes are looked up once per body (again every RIG_REFRESH seconds); the bodies to pose
-- are chosen every Config.Body.Retarget seconds; no tables are made per frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Joints = require(Shared.Joints)
local BodyMotion = require(Shared.BodyMotion)
local Bodies = require(script.Parent.Bodies)
local Ledger = require(script.Parent.PoseLedger)
local ArmPose = require(script.Parent.ArmPose)
local SprintPose = require(script.Parent.SprintPose)
local Interact = require(script.Parent.Interact)
local BikeRider = require(script.Parent.BikeRider)

local BodyLife = {}

local B = Config.Body
local SPRINT_FROM = Config.Courier.Sprint.From
local RIG_REFRESH = 2 -- seconds a body's joints are kept before they are looked up again …
local RIG_RETRY = 0.5 -- … or this, while some are missing
local SWEEP = 5 -- seconds between the clean-ups of the bodies and joints that are gone
local rad = math.rad

-- The states nothing is laid over (the animation's own climb, swim, sit …).
local OFF_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

type Rig = {
	root: any, waist: any, neck: any, rs: any, ls: any,
	rh: any, rk: any, ra: any, lh: any, lk: any, la: any,
	head: BasePart?, eyes: { SpecialMesh }, thigh: number, shin: number, leg: number, expires: number,
}
type Life = {
	seed: number,
	health: number,
	flinchAt: number,
	flinchSide: number,
	fall: number, -- the fastest fall (studs / s down) since leaving the ground; 0 on it
	landAt: number,
	landDrop: number,
	exertion: number, -- 0..1: out of breath after a sprint
	breath: number, -- the breath's phase 0..1
	idle: number, -- the shares (0..1, eased): standing still, walking
	walk: number,
	yaw: number, -- the head's turn now (radians)
	pitch: number,
	target: BasePart?, -- what the head looks at (a head, the job's ring)
	lookAt: number, -- when to choose again
	shut: number, -- the eyes' shut share last drawn
	released: boolean, -- 6.8 review: given back to the animation (letGo) and not posed since: no need to again
}

local rigs: { [Model]: Rig } = {}
local lives: { [Model]: Life } = {}
local written: { [Instance]: boolean } = {}
local chosen: { Model } = {} -- the bodies posed (chosen every Retarget seconds; reused)
local near: { [Model]: number } = {} -- their distance from the camera then
local posed: { [Model]: boolean } = {} -- posed last frame (to let go of the ones that drop out)
local chosenAt = 0
local sweptAt = 0
local serial = 0

local function jointIn(character: Model, part: string, name: string): any
	return Joints.find(character:FindFirstChild(part), name)
end

local function gone(joint: any): boolean
	return joint ~= nil and joint.Parent == nil
end

local function intact(rig: Rig): boolean
	return not (gone(rig.root) or gone(rig.waist) or gone(rig.neck) or gone(rig.rs) or gone(rig.ls) or gone(rig.rh)
		or gone(rig.rk) or gone(rig.ra) or gone(rig.lh) or gone(rig.lk) or gone(rig.la))
end

local function pointIn(character: Model, part: string, name: string): Vector3?
	local p = character:FindFirstChild(part)
	local a = p and p:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else nil
end

local function span(character: Model, part: string, a: string, b: string, fallback: number): number
	local p, q = pointIn(character, part, a), pointIn(character, part, b)
	return if p and q then math.max((p - q).Magnitude, 0.2) else fallback
end

local function rigOf(character: Model): Rig
	local now = os.clock()
	local rig = rigs[character]
	if rig and now < rig.expires and intact(rig) then
		return rig
	end
	local eyes: { SpecialMesh } = if rig then rig.eyes else {}
	table.clear(eyes)
	for _, name in { "EyeL", "EyeR", "IrisL", "IrisR" } do
		local eye = character:FindFirstChild(name)
		local mesh = eye and eye:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			table.insert(eyes, mesh)
		end
	end
	local head = character:FindFirstChild("Head")
	local thigh = span(character, "RightUpperLeg", "RightHipRigAttachment", "RightKneeRigAttachment", 1.2)
	local shin = span(character, "RightLowerLeg", "RightKneeRigAttachment", "RightAnkleRigAttachment", 1.2)
	local made: Rig = {
		root = jointIn(character, "LowerTorso", "Root"),
		waist = jointIn(character, "UpperTorso", "Waist"),
		neck = jointIn(character, "Head", "Neck"),
		rs = jointIn(character, "RightUpperArm", "RightShoulder"),
		ls = jointIn(character, "LeftUpperArm", "LeftShoulder"),
		rh = jointIn(character, "RightUpperLeg", "RightHip"),
		rk = jointIn(character, "RightLowerLeg", "RightKnee"),
		ra = jointIn(character, "RightFoot", "RightAnkle"),
		lh = jointIn(character, "LeftUpperLeg", "LeftHip"),
		lk = jointIn(character, "LeftLowerLeg", "LeftKnee"),
		la = jointIn(character, "LeftFoot", "LeftAnkle"),
		head = if head and head:IsA("BasePart") then head else nil,
		eyes = eyes,
		thigh = thigh,
		shin = shin,
		leg = thigh + shin,
		expires = 0,
	}
	local complete = made.root and made.waist and made.neck and made.rs and made.ls and made.rh and made.rk and made.ra
		and made.lh and made.lk and made.la
	made.expires = now + (if complete then RIG_REFRESH else RIG_RETRY)
	rigs[character] = made
	return made
end

-- The joint over the animation (and the layers under this one) by `value`; nil gives it back.
local function layer(joint: any, value: CFrame?)
	if not joint or not joint.Parent then
		return
	end
	if not value then
		if written[joint] then
			written[joint] = nil
			Ledger.release(joint)
		end
		return
	end
	Ledger.write(joint, Ledger.now(joint) * value)
	written[joint] = true
end

local function eyesOpen(rig: Rig, life: Life)
	if life.shut ~= 0 then
		life.shut = 0
		for _, mesh in rig.eyes do
			if mesh.Parent then
				mesh.Scale = Vector3.one
			end
		end
	end
end

-- Everything given back to the animation (once: 6.8 review, a body that can't be posed (a driver, a bus rider, the
-- dead, a zip rider) is let go when it stops being posed, not again every frame, and without a table a frame).
local function letGo(character: Model)
	local rig = rigs[character]
	local life = lives[character]
	if life and life.released then
		return
	end
	if rig then
		layer(rig.root, nil)
		layer(rig.waist, nil)
		layer(rig.neck, nil)
		layer(rig.rs, nil)
		layer(rig.ls, nil)
		layer(rig.rh, nil)
		layer(rig.rk, nil)
		layer(rig.ra, nil)
		layer(rig.lh, nil)
		layer(rig.lk, nil)
		layer(rig.la, nil)
		if life then
			eyesOpen(rig, life)
		end
	end
	if life then
		life.fall, life.landAt, life.walk, life.idle = 0, -math.huge, 0, 0
		life.released = true
	end
end

local function lifeOf(character: Model, humanoid: Humanoid): Life
	local life = lives[character]
	if life then
		return life
	end
	serial += 1
	local made: Life = {
		seed = (serial * 0.61803398875) % 1,
		health = humanoid.Health,
		flinchAt = -math.huge,
		flinchSide = 1,
		fall = 0,
		landAt = -math.huge,
		landDrop = 0,
		exertion = 0,
		breath = (serial * 0.37) % 1,
		idle = 0,
		walk = 0,
		yaw = 0,
		pitch = 0,
		target = nil,
		lookAt = 0,
		shut = 0,
		released = false,
	}
	lives[character] = made
	return made
end

-- Can anything be laid on this body now?
local function able(character: Model, humanoid: Humanoid, mine: boolean): boolean
	if humanoid.Health <= 0 or humanoid.Sit or humanoid.SeatPart ~= nil or humanoid.PlatformStand then
		return false
	end
	local state = humanoid:GetState()
	if OFF_STATES[state] or (mine and state == Enum.HumanoidStateType.Physics) then
		return false
	end
	return character:GetAttribute("ZipLine") == nil and character:GetAttribute("ClimbLine") == nil
		and not Interact.posing(character) and not BikeRider.riding(character)
end

-- 6.7: what a head looks at: the nearest other body's head in front within LookRange (your own courier: the job's ring
-- within LookRing too, workspace.DeliveryGuide's Ring that client/Hud.luau moves), else nothing.
local function chooseLook(character: Model, root: BasePart, mine: boolean): BasePart?
	local best: BasePart? = nil
	local bestDistance = B.LookRange
	local here = root.Position
	local ahead = root.CFrame.LookVector
	local behind = math.cos(rad(B.LookBehind))
	for _, other in chosen do
		if other == character then
			continue
		end
		local rig = rigs[other]
		local head = rig and rig.head
		if head and head.Parent then
			local offset = head.Position - here
			local distance = offset.Magnitude
			if distance < bestDistance and distance > 0.5 and ahead:Dot(offset / distance) > behind then
				best, bestDistance = head, distance
			end
		end
	end
	if mine and not best then
		local guide = workspace:FindFirstChild("DeliveryGuide")
		local ring = guide and guide:FindFirstChild("Ring")
		if ring and ring:IsA("BasePart") and (ring.Position - here).Magnitude < B.LookRing and ring.Position.Y > here.Y - 50 then
			best = ring
		end
	end
	return best
end

-- One body this frame.
local function live(character: Model, humanoid: Humanoid, root: BasePart, dt: number, now: number, mine: boolean, detail: boolean)
	local rig = rigOf(character)
	if not rig.root or not rig.waist then
		return
	end
	local life = lifeOf(character, humanoid)
	if not able(character, humanoid, mine) then
		letGo(character) -- (6.8 review: once, then nothing while it stays so)
		life.health = humanoid.Health
		return
	end
	life.released = false
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	-- The landing: the fastest fall since the feet left the ground, dipped once they are back on it.
	if v.Y < -B.LandFrom * 0.5 then
		life.fall = math.max(life.fall, -v.Y)
	elseif life.fall > 0 and v.Y > -4 then
		local drop = BodyMotion.landDrop(life.fall)
		if drop > 0 then
			life.landAt, life.landDrop = now, drop
		end
		life.fall = 0
	end
	local grounded = life.fall == 0 and math.abs(v.Y) < 8
	-- The flinch: health lost (a regained one is not a hit).
	local health = humanoid.Health
	if health < life.health - B.FlinchMin then
		life.flinchAt = now
		life.flinchSide = if math.floor(health) % 2 == 0 then 1 else -1
	end
	life.health = health
	-- The shares, eased.
	local ease = math.min(1, dt * 3)
	life.exertion = if speed > SPRINT_FROM then math.min(1, life.exertion + dt * 2) else math.max(0, life.exertion - dt / B.Recover)
	life.idle += ((if grounded and speed < B.IdleBelow and detail then 1 else 0) - life.idle) * ease
	local walking = if grounded then math.clamp((speed - B.WalkFrom) / 3, 0, 1) * (1 - SprintPose.weight(character)) else 0
	life.walk += (walking - life.walk) * math.min(1, dt * 6)
	local armsFree = not ArmPose.armsBusy(character)
	local legsFree = not ArmPose.legsBusy(character)
	-- The breath.
	life.breath = (life.breath + dt / (B.Breath + (B.BreathRun - B.Breath) * life.exertion)) % 1
	local deep = if detail then 1 + life.exertion else 0
	local breath = BodyMotion.breath(life.breath, 1)
	local tilt = rad(B.BreathTilt) * deep * (breath - 0.5)
	local lift = B.BreathLift * deep * breath
	-- The weight on one foot (standing still).
	local k = if detail then BodyMotion.shift(now, life.seed) * life.idle else 0
	local sway, roll = k * B.ShiftSway, k * rad(B.ShiftRoll)
	-- The landing's dip and the flinch.
	local landT = now - life.landAt
	local dip = if landT < BodyMotion.landTime() then BodyMotion.land(landT) * life.landDrop else 0
	local flinch = BodyMotion.flinch(now - life.flinchAt)
	-- The walk's weight from the stock walk's own thighs.
	local bob, swing, twist = 0, 0, 0
	if life.walk > 0.01 and rig.rh and rig.lh then
		local hipR = Ledger.base(rig.rh):ToEulerAnglesXYZ()
		local hipL = Ledger.base(rig.lh):ToEulerAnglesXYZ()
		bob, swing, twist = BodyMotion.stride(hipR, hipL)
		bob, swing, twist = bob * life.walk, swing * life.walk, twist * life.walk
	end
	-- The head.
	if detail and now >= life.lookAt then
		life.lookAt = now + B.Retarget * (0.8 + 0.4 * life.seed)
		life.target = chooseLook(character, root, mine)
	end
	local yawGoal, pitchGoal = 0, 0
	local target, head = life.target, rig.head
	if detail and target and target.Parent and head then
		local offset = root.CFrame:VectorToObjectSpace(target.Position - head.Position)
		local yaw, pitch, ok = BodyMotion.look(offset.X, offset.Y, offset.Z)
		if ok then
			yawGoal, pitchGoal = yaw, pitch
		end
	end
	local follow = math.min(1, dt * B.LookSpeed)
	life.yaw += (yawGoal - life.yaw) * follow
	life.pitch += (pitchGoal - life.pitch) * follow
	local flinchTurn = life.flinchSide * rad(B.FlinchTurn) * flinch

	-- Onto the joints. The Root: the hips' sway and tip, the dip, the walk's bob.
	local lean = if life.landDrop > 0 then rad(B.LandLean) * dip / life.landDrop else 0
	if legsFree and (math.abs(sway) > 1e-4 or dip > 1e-4 or math.abs(bob) > 1e-4) then
		layer(rig.root, CFrame.new(sway, bob - dip, 0) * CFrame.Angles(0, 0, roll))
	else
		layer(rig.root, nil)
	end
	-- The waist: the breath, the chest against the hips' tip, the head's turn shared, the walk's turn, the dip's lean,
	-- the flinch.
	local waistX = tilt - lean + rad(B.FlinchBack) * flinch
	local waistY = life.yaw * B.LookChest + twist + flinchTurn * 0.3
	if legsFree and (math.abs(waistX) > 1e-4 or math.abs(waistY) > 1e-4 or math.abs(roll) > 1e-4) then
		layer(rig.waist, CFrame.Angles(waistX, waistY, -roll * 0.8))
	else
		layer(rig.waist, nil)
	end
	-- The head: the rest of the turn, steady over the walk and the breath, away from the hit.
	local neckY = life.yaw * (1 - B.LookChest) - twist + flinchTurn
	local neckX = life.pitch - tilt * 0.8 + lean * 0.5 + rad(6) * flinch
	if legsFree and (math.abs(neckX) > 1e-4 or math.abs(neckY) > 1e-4 or math.abs(roll) > 1e-4) then
		layer(rig.neck, CFrame.Angles(0, neckY, 0) * CFrame.Angles(neckX, 0, -roll * 0.2))
	else
		layer(rig.neck, nil)
	end
	-- The legs: the dip's bend (the feet planted), the sway taken out at the hips, the free knee bent.
	if legsFree and (dip > 1e-4 or math.abs(k) > 1e-3) then
		local hip, knee, ankle = BodyMotion.crouch(dip, 0, rig.thigh, rig.shin)
		local out = -roll - math.asin(math.clamp(sway / rig.leg, -0.5, 0.5))
		local bend = rad(B.ShiftKnee) * math.abs(k)
		local freeR, freeL = if k < 0 then bend else 0, if k > 0 then bend else 0
		layer(rig.rh, CFrame.Angles(hip + freeR * 0.5, 0, out))
		layer(rig.rk, CFrame.Angles(knee - freeR, 0, 0))
		layer(rig.ra, CFrame.Angles(ankle + freeR * 0.5, 0, -out - roll))
		layer(rig.lh, CFrame.Angles(hip + freeL * 0.5, 0, out))
		layer(rig.lk, CFrame.Angles(knee - freeL, 0, 0))
		layer(rig.la, CFrame.Angles(ankle + freeL * 0.5, 0, -out - roll))
	else
		layer(rig.rh, nil)
		layer(rig.rk, nil)
		layer(rig.ra, nil)
		layer(rig.lh, nil)
		layer(rig.lk, nil)
		layer(rig.la, nil)
	end
	-- The arms (while ArmPose leaves them): the shoulders rise with the breath and the flinch, the walk's extra swing,
	-- (the bag arm is client/BagSway.luau's)
	local up = lift + 0.05 * flinch
	if armsFree and (up > 1e-4 or math.abs(swing) > 1e-4) then
		layer(rig.rs, CFrame.new(0, up, 0) * CFrame.Angles(-swing, 0, 0))
		layer(rig.ls, CFrame.new(0, up, 0) * CFrame.Angles(swing, 0, 0))
	else
		layer(rig.rs, nil)
		layer(rig.ls, nil)
	end
	-- The blinks.
	if detail and #rig.eyes > 0 then
		local shut = BodyMotion.blink(now, life.seed)
		if math.abs(shut - life.shut) > 0.04 or (shut == 0 and life.shut ~= 0) then
			life.shut = shut
			local scale = Vector3.new(1, 1 - shut * (1 - B.BlinkShut), 1)
			for _, mesh in rig.eyes do
				if mesh.Parent then
					mesh.Scale = scale
				end
			end
		end
	elseif #rig.eyes > 0 then
		eyesOpen(rig, life)
	end
end

local function byDistance(a: Model, b: Model): boolean
	return (near[a] or math.huge) < (near[b] or math.huge)
end

local function consider(character: Model?, eye: Vector3, mine: boolean)
	if not character or not character:FindFirstChild("UpperTorso") then
		return
	end
	local _, root = Bodies.of(character)
	if not root then
		return
	end
	local distance = if mine then 0 else (root.Position - eye).Magnitude
	if distance <= B.Range then
		table.insert(chosen, character)
		near[character] = distance
	end
end

-- The bodies to pose: your own, the other players' and the people's within Range, at most MaxPosed, the nearest.
local function choose(eye: Vector3)
	table.clear(chosen)
	table.clear(near)
	local me = Players.LocalPlayer
	for _, player in Bodies.players() do
		consider(player.Character, eye, player == me)
	end
	local folder = workspace:FindFirstChild("Npcs")
	if folder then
		for _, person in folder:GetChildren() do
			if person:IsA("Model") then
				consider(person, eye, false)
			end
		end
	end
	if #chosen > B.MaxPosed then
		table.sort(chosen, byDistance)
		for i = #chosen, B.MaxPosed + 1, -1 do
			near[chosen[i]] = nil
			chosen[i] = nil
		end
	end
end

local function sweep(now: number)
	if now - sweptAt < SWEEP then
		return
	end
	sweptAt = now
	for character in rigs do
		if not character.Parent then
			rigs[character] = nil
			lives[character] = nil
			posed[character] = nil
		end
	end
	for joint in written do
		if not joint.Parent then
			written[joint] = nil
		end
	end
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local eye = camera.CFrame.Position
	if now - chosenAt >= B.Retarget then
		chosenAt = now
		choose(eye)
		-- the ones that dropped out go back to the animation
		for character in posed do
			if not near[character] then
				posed[character] = nil
				letGo(character)
			end
		end
	end
	local me = Players.LocalPlayer
	local mine = if me then me.Character else nil
	for _, character in chosen do
		if not character.Parent then
			continue
		end
		local humanoid, root = Bodies.of(character)
		if not humanoid or not root then
			continue
		end
		posed[character] = true
		live(character, humanoid, root, dt, now, character == mine, character == mine or (near[character] or math.huge) <= B.Detail)
	end
	sweep(now)
end

function BodyLife.start()
	RunService.PreSimulation:Connect(step)
end

return BodyLife
