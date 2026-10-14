--!strict
-- 6.24: the gait (the owner: "better animations, how he walks and moves"), on this client, for every courier's
-- character and every person in workspace.Npcs within Config.Gait.Range of the camera (yours always; at most MaxPosed,
-- the nearest). shared/Gait.luau is the maths (the planted walk, the run and the tired sprint, any way while aiming,
-- the leans, the jump and the landing, the idle's fidgets and holds); here each body's look goes in every frame (its
-- velocity in its own frame, its turn, in the air or not, the slope under it, the breath, what its hands hold) and the
-- pose comes out into the R15 joints' Transform: the first stage of client/PoseLedger.luau (before client/ArmPose's aim,
-- carry and gestures, client/BodyLife's breath, look and flinch, client/BagSway's bag arm: they lay their poses over
-- it), never C0 (shared/Joints.luau). It replaces 6.0's client/SprintPose.luau (its run is the gait's from RunFrom).
--   * The stock tracks (server/CharacterArt/Animate.client.luau: idle, walk, run, jump, fall) keep playing underneath:
--     a body farther than Range, or one the gait lets go, shows them alone. Each joint is laid over them by the pose's
--     own weight (standing still most go back to the stock idle).
--   * Nothing is posed in a seat, on a bike, a zip line or a ladder, climbing, swimming, dead or in a move of
--     client/Interact.luau: the joints go back to the animation (once).
--   * Within Config.Gait.Detail (yours always) the whole gait each frame, a ray down for the slope every SlopeEvery;
--     farther the pose is worked out FarHz times a second and the same pose written every frame (the Animator writes
--     over the joints each frame), no ray, no fidget. A phone poses fewer bodies, nearer (client/DeviceBudget.luau).
--   * Your breath is client/Stamina.luau's; another courier's is guessed from their sprint (Gait). Reduced Motion
--     (client/PhoneMotion.luau): no fidgets, no flail, half the lean into a turn.
-- Joints and measures (shared/Gait.luau Body: from the rig attachments) are looked up once per body (again every
-- RIG_REFRESH seconds, RIG_RETRY while some are missing, at once when one left the body); each body keeps its own
-- state, input and pose tables and its CFrames: no tables are made per frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Joints = require(Shared.Joints)
local Gait = require(Shared.Gait)
local Gestures = require(Shared.Gestures)
local Bodies = require(script.Parent.Bodies)
local DeviceBudget = require(script.Parent.DeviceBudget)
local CameraRig = require(script.Parent.CameraRig)
local Holster = require(script.Parent.Holster)
local Interact = require(script.Parent.Interact)
local BikeRider = require(script.Parent.BikeRider)
local Stamina = require(script.Parent.Stamina)
local PhoneMotion = require(script.Parent.PhoneMotion)
local Ledger = require(script.Parent.PoseLedger)

local GaitPose = {}

local G = Config.Gait
local RIG_REFRESH = 2 -- seconds a body's joints are kept before they are looked up again …
local RIG_RETRY = 0.5 -- … or this, while some are missing
local SWEEP = 5 -- seconds between the clean-ups of the bodies that are gone
local LOOK = 0.1 -- seconds between the looks at what a body's hands hold
local CALM_LOOK = 1 -- seconds between the looks at Reduced Motion
local COUNT = Gait.Count

-- The states nothing is posed in (the animation's own climb, swim, sit …; a jump and a fall are the gait's).
local OFF_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Flying] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

type Rig = { joints: { any }, body: Gait.Body, expires: number, complete: boolean }
type Walker = {
	state: Gait.State,
	input: Gait.Input,
	pose: Gait.Pose,
	frames: { CFrame }, -- the pose as CFrames (rebuilt when it is worked out again)
	wrote: { boolean }, -- the joints this module holds
	posed: boolean, -- anything held (letGo gives them back once)
	facing: number, -- the root's heading last frame (its turn)
	turn: number, -- smoothed turn rate
	since: number, -- seconds gathered for a far body's next pose
	rayAt: number,
	params: RaycastParams?,
	lookAt: number, -- when to look at the hands again
	hands: string,
	heavy: number,
	aiming: boolean,
}

local rigs: { [Model]: Rig } = {}
local walkers: { [Model]: Walker } = {}
local chosen: { Model } = {} -- the bodies walked (chosen every Retarget seconds; reused)
local near: { [Model]: number } = {} -- their distance from the camera then
local posed: { [Model]: boolean } = {} -- walked since the last choice (the ones that drop out go back)
local chosenAt = -math.huge
local sweptAt = 0
local serial = 0
local calm = false
local calmAt = -math.huge

local function gone(joint: any): boolean
	return joint ~= nil and joint ~= false and joint.Parent == nil
end

local function pointIn(part: Instance?, name: string): Vector3?
	local a = if part then part:FindFirstChild(name) else nil
	return if a and a:IsA("Attachment") then a.Position else nil
end

-- A body's measures from its rig attachments (shared/Gait.luau Body), or nil when a piece is missing.
local function measure(character: Model): Gait.Body?
	local thighPart, shinPart, foot, pelvis = character:FindFirstChild("RightUpperLeg"), character:FindFirstChild("RightLowerLeg"),
		character:FindFirstChild("RightFoot"), character:FindFirstChild("LowerTorso")
	local hip, knee = pointIn(thighPart, "RightHipRigAttachment"), pointIn(thighPart, "RightKneeRigAttachment")
	local knee2, ankle = pointIn(shinPart, "RightKneeRigAttachment"), pointIn(shinPart, "RightAnkleRigAttachment")
	local ankle2 = pointIn(foot, "RightAnkleRigAttachment")
	local rootAt, hipAt = pointIn(pelvis, "RootRigAttachment"), pointIn(pelvis, "RightHipRigAttachment")
	if not (hip and knee and knee2 and ankle and ankle2 and rootAt and hipAt and foot and foot:IsA("BasePart")) then
		return nil
	end
	local thigh, shin = knee - hip, ankle - knee2
	local size = (foot :: BasePart).Size
	return Gait.body(thigh.Magnitude, shin.Magnitude, ankle2.Y + size.Y / 2, size.Z / 2 - ankle2.Z, size.Z / 2 + ankle2.Z,
		hipAt.X - rootAt.X, rootAt.Y - hipAt.Y, math.atan2(-thigh.Z, -thigh.Y), math.atan2(-shin.Z, -shin.Y))
end

local function rigOf(character: Model): Rig
	local now = os.clock()
	local rig = rigs[character]
	if rig and now < rig.expires then
		local intact = true
		for _, joint in rig.joints do
			if gone(joint) then
				intact = false
				break
			end
		end
		if intact then
			return rig
		end
	end
	local joints: { any } = if rig then rig.joints else table.create(COUNT, false)
	local complete = character:FindFirstChild("UpperTorso") ~= nil
	for j = 1, COUNT do
		local joint = Joints.find(character:FindFirstChild(Gait.Parts[j]), Gait.Names[j])
		joints[j] = joint or false
		if not joint then
			complete = false
		end
	end
	local body = if complete then measure(character) else nil
	local made: Rig = {
		joints = joints,
		body = body or Gait.Classic,
		expires = now + (if complete and body then RIG_REFRESH else RIG_RETRY),
		complete = complete and body ~= nil,
	}
	rigs[character] = made
	return made
end

local function walkerOf(character: Model): Walker
	local w = walkers[character]
	if w then
		return w
	end
	serial += 1
	local made: Walker = {
		state = Gait.new((serial * 0.61803398875) % 1),
		input = Gait.input(),
		pose = Gait.pose(),
		frames = table.create(COUNT, CFrame.identity),
		wrote = table.create(COUNT, false),
		posed = false,
		facing = 0,
		turn = 0,
		since = math.huge,
		rayAt = 0,
		params = nil,
		lookAt = 0,
		hands = "free",
		heavy = 0,
		aiming = false,
	}
	walkers[character] = made
	return made
end

-- Every joint this module holds back to the animation (once), the body's gait started again.
local function letGo(character: Model)
	local w = walkers[character]
	if not w or not w.posed then
		return
	end
	w.posed = false
	local rig = rigs[character]
	for j = 1, COUNT do
		if w.wrote[j] then
			w.wrote[j] = false
			local joint = if rig then rig.joints[j] else nil
			if joint and joint.Parent then
				Ledger.release(joint)
			end
		end
	end
	local seed = w.state.seed
	w.state = Gait.new(seed)
	w.since = math.huge
end

-- Can the gait pose this body now (on its feet or in the air, nothing else moving it)? `air`: a jump or a fall counts
-- (client/ArmPose.luau's lean asks with it).
local function onFoot(character: Model, humanoid: Humanoid, mine: boolean, air: boolean?): boolean
	if humanoid.Health <= 0 or humanoid.Sit or humanoid.SeatPart ~= nil or humanoid.PlatformStand then
		return false
	end
	local state = humanoid:GetState()
	if OFF_STATES[state] or (mine and state == Enum.HumanoidStateType.Physics) then
		return false
	end
	if air == false and (state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall) then
		return false
	end
	return character:GetAttribute("ZipLine") == nil and character:GetAttribute("ClimbLine") == nil
		and not Interact.posing(character) and not BikeRider.riding(character)
end
GaitPose.onFoot = onFoot

-- What the hands hold (shared/Gait.luau Input.hands), looked at every LOOK seconds.
local function look(character: Model, w: Walker, mine: boolean, now: number)
	if now < w.lookAt then
		return
	end
	w.lookAt = now + LOOK
	local carrying = character:GetAttribute("Carrying")
	local speed = character:GetAttribute("CarrySpeed")
	w.heavy = if type(speed) == "number" then 1 else 0
	w.aiming = if mine then false else character:GetAttribute("Aiming") == true
	if type(carrying) == "string" and carrying ~= "" then
		w.hands = "carry"
		return
	end
	local gestureAt, gesture = character:GetAttribute("GestureAt"), character:GetAttribute("Gesture")
	local gesturing = type(gestureAt) == "number" and type(gesture) == "string"
		and workspace:GetServerTimeNow() - gestureAt < (Gestures.seconds(gesture) or 0)
	if character:GetAttribute("PhoneHeld") == true or character:GetAttribute("ClipboardHeld") == true or gesturing then -- (8.5: Danny's clipboard)
		w.hands = "busy"
		return
	end
	local holstered = if mine then Holster.holstered() else character:GetAttribute("Holstered") == true
	if character:GetAttribute("Hand") == "gun" and not holstered and character:FindFirstChild("HandGun") then
		w.hands = "gun"
	elseif character:GetAttribute("BagWorn") == "hand" then
		w.hands = "bag"
	else
		w.hands = "free"
	end
end

-- The ground's rise a stud forward and a stud right under the body (its frame), from a ray down.
local function slope(character: Model, root: BasePart, humanoid: Humanoid, w: Walker): (number, number)
	local params = w.params
	if not params then
		local made = RaycastParams.new()
		made.FilterType = Enum.RaycastFilterType.Exclude
		made.FilterDescendantsInstances = { character }
		made.IgnoreWater = true
		w.params = made
		params = made
	end
	local reach = root.Size.Y / 2 + humanoid.HipHeight + 2
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params)
	if not hit or hit.Normal.Y < 0.6 then
		return 0, 0
	end
	local n = root.CFrame:VectorToObjectSpace(hit.Normal)
	return n.Z / n.Y, -n.X / n.Y
end

local function wrapPi(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- The pose (shared/Gait.luau's numbers) as CFrames.
local function build(w: Walker)
	local m, frames = w.pose.m, w.frames
	for j = 1, COUNT do
		local o = (j - 1) * 12
		frames[j] = CFrame.new(m[o + 1], m[o + 2], m[o + 3], m[o + 4], m[o + 5], m[o + 6], m[o + 7], m[o + 8], m[o + 9], m[o + 10], m[o + 11], m[o + 12])
	end
end

-- The pose into the joints, each by its own weight over the animation (and nothing under this stage).
local function write(rig: Rig, w: Walker)
	local weights, frames, wrote = w.pose.w, w.frames, w.wrote
	for j = 1, COUNT do
		local joint = rig.joints[j]
		if joint and joint.Parent then
			local weight = weights[j]
			if weight > 0.001 then
				local value = frames[j]
				Ledger.write(joint, if weight >= 0.999 then value else Ledger.now(joint):Lerp(value, weight))
				wrote[j] = true
				w.posed = true
			elseif wrote[j] then
				wrote[j] = false
				Ledger.release(joint)
			end
		end
	end
end

-- One body this frame.
local function walk(character: Model, humanoid: Humanoid, root: BasePart, dt: number, now: number, mine: boolean, detail: boolean)
	local rig = rigOf(character)
	if not rig.complete or not onFoot(character, humanoid, mine) then
		letGo(character)
		return
	end
	local w = walkerOf(character)
	local frame = root.CFrame
	local lookV = frame.LookVector
	local facing = math.atan2(-lookV.X, -lookV.Z)
	local turnNow = if dt > 0 and w.since ~= math.huge then wrapPi(facing - w.facing) / dt else 0
	w.facing = facing
	w.turn += (math.clamp(turnNow, -12, 12) - w.turn) * math.min(1, dt * 10)
	-- (a far body: worked out FarHz times a second, the same pose written in between)
	w.since = if w.since == math.huge then 1 else w.since + dt
	if not detail and w.since < 1 / G.FarHz then
		write(rig, w)
		return
	end
	local step = math.min(w.since, 0.1)
	w.since = 0
	look(character, w, mine, now)
	local i = w.input
	local v = root.AssemblyLinearVelocity
	local lv = frame:VectorToObjectSpace(v)
	i.dt = step
	i.vx, i.vz, i.vy = lv.X, lv.Z, v.Y
	i.y = frame.Y
	i.yawRate = w.turn
	local state = humanoid:GetState()
	i.air = state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
	if detail and now >= w.rayAt then
		w.rayAt = now + G.SlopeEvery
		i.slopeF, i.slopeR = slope(character, root, humanoid, w)
	elseif not detail then
		i.slopeF, i.slopeR = 0, 0
	end
	i.breath = if mine then Stamina.breath() else -1
	local aiming = w.aiming
	if mine then
		aiming = (CameraRig.aimPose())
	end
	i.aiming = aiming
	i.hands = if aiming and w.hands ~= "carry" then "busy" else w.hands
	i.heavy = w.heavy
	i.detail = detail
	i.calm = calm
	Gait.step(w.state, i, rig.body, w.pose)
	build(w)
	write(rig, w)
end

local function byDistance(a: Model, b: Model): boolean
	return (near[a] or math.huge) < (near[b] or math.huge)
end

local function consider(character: Model?, eye: Vector3, mine: boolean, range: number)
	if not character or not character:FindFirstChild("UpperTorso") then
		return
	end
	local _, root = Bodies.of(character)
	if not root then
		return
	end
	local distance = if mine then 0 else (root.Position - eye).Magnitude
	if distance <= range then
		table.insert(chosen, character)
		near[character] = distance
	end
end

-- The bodies to walk: yours, the other couriers' and the people's within Range, at most MaxPosed, the nearest.
local function choose(eye: Vector3)
	table.clear(chosen)
	table.clear(near)
	local me = Players.LocalPlayer
	local range = DeviceBudget.range(G.Range)
	for _, player in Bodies.players() do
		consider(player.Character, eye, player == me, range)
	end
	local folder = workspace:FindFirstChild("Npcs")
	if folder then
		for _, person in folder:GetChildren() do
			if person:IsA("Model") then
				consider(person, eye, false, range)
			end
		end
	end
	local most = DeviceBudget.count(G.MaxPosed)
	if #chosen > most then
		table.sort(chosen, byDistance)
		for k = #chosen, most + 1, -1 do
			near[chosen[k]] = nil
			chosen[k] = nil
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
			walkers[character] = nil
			posed[character] = nil
		end
	end
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	if now - calmAt >= CALM_LOOK then
		calmAt = now
		calm = PhoneMotion.reducedMotion()
	end
	local eye = camera.CFrame.Position
	if now - chosenAt >= G.Retarget then
		chosenAt = now
		choose(eye)
		for character in posed do
			if not near[character] then
				posed[character] = nil
				letGo(character)
			end
		end
	end
	local me = Players.LocalPlayer
	local mine = if me then me.Character else nil
	local detail = DeviceBudget.range(G.Detail)
	for _, character in chosen do
		if not character.Parent then
			continue
		end
		local humanoid, root = Bodies.of(character)
		if not humanoid or not root then
			continue
		end
		posed[character] = true
		local isMine = character == mine
		walk(character, humanoid, root, dt, now, isMine, isMine or (near[character] or math.huge) <= detail)
	end
	sweep(now)
end

-- How far the gait holds this body's legs and hips now (0 … 1; 0 when it does not pose it).
function GaitPose.legs(character: Model): number
	local w = walkers[character]
	return if w and w.posed then w.pose.w[Gait.ROOT] else 0
end

-- The walk's own move on this body (0 standing … 1 walking or running): client/ArmPose.luau's lean steps aside.
function GaitPose.moving(character: Model): number
	local w = walkers[character]
	return if w and w.posed then Gait.moving(w.state) else 0
end

-- The sprint's run cycle's share on this body (0 … 1): client/BagSway.luau leaves the waist and the head to it.
function GaitPose.sprint(character: Model): number
	local w = walkers[character]
	return if w and w.posed then Gait.running(w.state) else 0
end

-- How far the gait holds an arm (the left: `left`): client/BagSway.luau's bag arm takes the rest.
function GaitPose.arm(character: Model, left: boolean): number
	local w = walkers[character]
	return if w and w.posed then w.pose.w[if left then Gait.LS else Gait.RS] else 0
end

function GaitPose.start()
	Ledger.stage(10, "GaitPose", step)
end

return GaitPose
