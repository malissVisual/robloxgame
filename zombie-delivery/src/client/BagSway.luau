--!strict
-- 6.1: the plastic bag in a courier's hand swings behind them (the owner's wish: "the bag just flutters behind you"), on
-- every player's character within Config.Courier.Bag.Range of the camera (yours always), every frame in
-- RunService.PreSimulation. The only writer of the BagSwing joint's Transform (server/KitWear.luau hangs KitBagPivot from
-- the left hand by that Motor6D; client/SprintPose.luau no longer touches it).
--
-- shared/BagSwing.luau is the pendulum: a damped spring driven by the grip's real acceleration (it trails when you start,
-- swings forward when you stop, out on a turn) and the speed's air (it leans back at a run), a flutter and a twist at
-- speed. Here its tilt becomes a world orientation: the bag's broad sides along your facing (its +X to your right, as it
-- hangs), its up axis leaning away from where its bottom has gone, turned about the handles by the twist; the Transform
-- is that orientation seen from the grip (the hand · C0), straight from the hand's frame each frame. (6.0 built it from
-- the pivot's last solved CFrame and its old Transform: any frame the pivot was not solved again compounded the
-- error; with the step jolt at 8 Hz and the flutter on top, the bag jittered and blinked.)
-- A character's joint is looked up once (again when it leaves the body, every LOOK seconds while it has none); out of
-- range or gone, the joint goes back to the identity once and its swing is forgotten.
-- 6.4: each bag swings with its own tuning (the pivot's Bag attribute, Config.Courier.Bags): a tote a little slower,
-- the thermal and the padded bag heavy and boxy, the duffel slow with hardly any flutter. Each way of wearing it (the
-- pivot's Worn attribute, server/KitWear.luau: "hand" | "shoulder" | "hip" | "back") its own motion: in the hand the
-- pendulum, on the shoulder or the hip a stiff little swing (Config.Courier.Wear) and a bounce with the steps
-- (BagSwing.bob, Bounce), on the back a soft bob (BackBob). When the bag moves between the front and the back (the
-- character's BagSwitchAt, the server time: the new pivot replaces the old one) it starts where it was, relative to
-- the body, and moves to its new place over Config.Courier.Switch seconds while the sling / unsling gesture plays
-- (client/ArmPose.luau). Still the joint's only writer.
-- 6.4.1: the joint may hang from an R6 body's "Left Arm" or "Torso" (server/KitWear.luau, KitFit.R6): it is found by
-- its pivot, whatever its Part0. The Transform stays a rotation about the grip in the hand (and a few hundredths of a
-- stud of bounce elsewhere), so the bag never leaves its place. And once per spawn, Config.Courier.BagCheck.After
-- seconds after your bag shows (the character's BagWorn attribute), a look whether it really is on you; when not, the
-- Output says why, for the owner to paste: no parts, all see-through, or farther than BagCheck.Far studs from your hand
-- or from its place, e.g. "[BagSway] your bag is 37.2 studs from your hand (style hand, joint LeftHand → KitBagPivot,
-- C0 (0.00, -0.27, 0.00), Transform (0.00, 0.00, 0.00))".
-- 6.7, the body under the bag (the owner: "no animations … I want better animations"), in the same pass on every
-- player's R15 body near the camera (Config.Courier.BagArm), each laid on top of the animation and let go to the
-- identity when it does not apply: while the bag hangs in the left hand (BagWorn "hand") its arm is a little straighter
-- and out, swinging less, only while client/ArmPose.luau and client/SprintPose.luau leave that arm (no aim, no cargo
-- in the hands, no phone, gesture, swing or car door, no sprint; BagArm.Hold seconds after); a loaded bag (the
-- player's BagCount) leans the torso the other way, and a gesture's torso and head (shared/Gestures.luau body: the
-- throw's turn back and through, the look down into the bag) go on the Waist and the Neck, the waist only standing or
-- slower than BagArm.Calm (ArmPose leans it when you move faster) and never in the sprint (SprintPose's).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BagSwing = require(Shared.BagSwing)
local Joints = require(Shared.Joints) -- 6.7: the bag arm, the lean, the gestures' torso and head
local Gestures = require(Shared.Gestures)
local Bodies = require(script.Parent.Bodies)
local DeviceBudget = require(script.Parent.DeviceBudget) -- 6.13.1: a phone poses only the nearer bodies
local CameraRig = require(script.Parent.CameraRig) -- 6.7: who has the arm now (as client/SprintPose.luau asks)
local Holster = require(script.Parent.Holster)
local SprintPose = require(script.Parent.SprintPose)
local Interact = require(script.Parent.Interact)
local Ledger = require(script.Parent.PoseLedger) -- 6.7 B: the joints shared with ArmPose, SprintPose and BodyLife

local BagSway = {}

local B = Config.Courier.Bag
local C = Config.Courier -- 6.4: Bounce, BackBob, Step, Switch, Wear
local SWITCH = math.max(0.05, C.Switch)
local WEAR = BagSwing.tuning(B :: any, C.Wear) -- 6.4: a bag on the shoulder or the hip: a stiff little swing
local LOOK = 0.4 -- seconds between the looks for a bag on a character that has none
local CHECK = Config.Courier.BagCheck -- 6.4.1: the look whether your bag is really on you
local SWEEP = 5 -- seconds between the clean-ups of the characters that are gone

-- 6.4: every bag's own swing (Config.Courier.Bags over Bag: the bigger, the heavier), made once per bag id. The pivot's
-- Bag attribute (server/KitWear.luau) names the bag in that hand.
local tunings: { [string]: BagSwing.Tuning } = {}
local function tuningOf(pivot: Instance?): BagSwing.Tuning
	local id = if pivot then pivot:GetAttribute("Bag") else nil
	local key = if type(id) == "string" then id else Config.Courier.BagKit
	local made = tunings[key]
	if not made then
		made = BagSwing.tuning(B :: any, Config.Courier.Bags[key])
		tunings[key] = made
	end
	return made
end

type Rec = {
	joint: Motor6D?,
	hand: BasePart?,
	state: BagSwing.State,
	nextLook: number,
	written: boolean, -- a Transform of ours is on the joint
	tuning: BagSwing.Tuning, -- 6.4: this bag's swing
	worn: string, -- 6.4: "hand" | "shoulder" | "hip" | "back" (the pivot's Worn attribute)
	walked: number, -- 6.4: studs walked (the steps' bounce)
	rel: CFrame?, -- 6.4: the bag's last pose relative to the body (a move to the back or the front starts there) …
	from: CFrame?, -- … the pose the running move started from, and the move's start (the server time)
	fromAt: number,
	relBag: string?, -- (the bag that pose was of)
}

local recs: { [Model]: Rec } = {}
local checks: { [Model]: number | boolean } = {} -- 6.4.1: your body → when its bag showed (os.clock), true: looked
local missingSince: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- 6.5.1: Hand "bag", no BagWorn since
local missingTold: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local sweptAt = 0
local handVec = { 0, 0, 0 } -- (reused every frame)
local bodyVec = { 0, 0, 0 }

-- The bag's joint on this character (nil without a bag: in a seat, stowed, another hand).
local function find(character: Model): (Motor6D?, BasePart?)
	local pivot = character:FindFirstChild("KitBagPivot")
	local joint = if pivot then pivot:FindFirstChild("BagSwing") else nil
	if joint and joint:IsA("Motor6D") then
		local hand = joint.Part0
		if hand and hand:IsA("BasePart") then
			return joint, hand
		end
	end
	return nil, nil
end

-- 6.4.1: "(x, y, z)" to two decimals, for the Output.
local function v3(v: Vector3): string
	return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end

-- 6.4.1: is your bag really on you? Once, a while after it showed; says in the Output what is wrong (nothing when all
-- is well). `worn` the BagWorn attribute.
local function diagnose(character: Model, worn: string)
	local pivot = character:FindFirstChild("KitBagPivot")
	local art = character:FindFirstChild("KitBagArt")
	local parts: { BasePart } = {}
	if art then
		for _, child in art:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
		end
	end
	if not pivot or not pivot:IsA("BasePart") or #parts == 0 then
		warn(`[BagSway] your bag ({worn}) has no parts on your character (pivot {if pivot then "yes" else "no"}, art parts {#parts}): the server built none, look for a [KitWear] line in the server Output`)
		return
	end
	local joint = pivot:FindFirstChild("BagSwing")
	if not joint or not joint:IsA("Motor6D") or not joint.Part0 then
		warn(`[BagSway] your bag's joint is {if joint then joint.ClassName else "missing"}: it cannot hang from your hand (style {worn})`)
		return
	end
	local hand = joint.Part0 :: BasePart
	local about = `style {worn}, joint {hand.Name} → {pivot.Name}, C0 {v3(joint.C0.Position)}, Transform {v3(joint.Transform.Position)}`
	local place = (hand.CFrame * joint.C0).Position
	local off = (pivot.Position - place).Magnitude
	if off > CHECK.Far then
		warn(string.format("[BagSway] your bag sits %.1f studs from its place (%s)", off, about))
	end
	local far, clear = 0, 0
	for _, part in parts do
		far = math.max(far, (part.Position - hand.Position).Magnitude)
		if part.Transparency < 0.95 and part.LocalTransparencyModifier < 0.95 then
			clear += 1
		end
	end
	if far > CHECK.Far then
		warn(string.format("[BagSway] your bag is %.1f studs from your hand (%s)", far, about))
	end
	local camera = workspace.CurrentCamera
	local head = character:FindFirstChild("Head")
	local firstPerson = camera ~= nil and head ~= nil and head:IsA("BasePart") and (camera.CFrame.Position - head.Position).Magnitude < 1
	if clear == 0 and not firstPerson then
		local part = parts[1]
		warn(string.format("[BagSway] your bag's %d parts are all see-through (Transparency %.2f, LocalTransparencyModifier %.2f; %s)", #parts, part.Transparency, part.LocalTransparencyModifier, about))
	end
	-- 6.5.1: and always one line of what it found (the owner still sees no bag: this tells us where it is)
	print(string.format("[BagSway] your bag: %d parts (%d visible), %.1f studs from your %s, %.1f from its place (%s)", #parts, clear, far, hand.Name, off, about))
end

-- Our Transform off the joint (it hangs as the hand holds it), the swing forgotten.
local function release(rec: Rec)
	local joint = rec.joint
	if joint and rec.written and joint.Parent then
		joint.Transform = CFrame.identity
	end
	rec.written = false
	rec.joint, rec.hand = nil, nil
	rec.state = BagSwing.new()
end

local function forget(character: Model)
	local rec = recs[character]
	if rec then
		release(rec)
		recs[character] = nil
	end
end

-- ── 6.7: the bag arm, the counter-lean, the gestures' torso and head ─────────────────────────────────────────────────
-- Laid on top of the animation (Transform only, never C0; let go back to the animation: 6.7 B, client/PoseLedger.luau), each
-- joint only while nobody else writes it: the left arm while ArmPose / SprintPose leave it (and A.Hold after), the
-- waist only standing or slow (A.Calm) and not sprinting, the neck while not sprinting. As in client/ArmPose.luau, a
-- joint that still holds what we wrote was not written by the Animator this frame: its last animation value is the base.

local A = Config.Courier.BagArm
local BUSY_FOR = 1.5 -- seconds after a swing or a car door's handle the arms stay ArmPose's (as client/SprintPose.luau)
local CALM_FOR = 0.6 -- seconds slower than A.Calm before the waist is ours (ArmPose's own lean has died away by then)
local RIG_REFRESH = 2 -- seconds a body's joints are kept before they are looked up again

type Body = {
	ls: any,
	le: any,
	waist: any,
	neck: any,
	expires: number,
	arm: number, -- the bag arm's share (0..1)
	lean: number, -- the counter-lean now (radians)
	calmSince: number?, -- since when (os.clock) slower than A.Calm on foot
	busyUntil: number, -- the left arm stays the others' until then
	gestureAt: number?, -- the last GestureAt seen …
	gestureStart: number, -- … and when it began here (os.clock)
}
local bodies: { [Model]: Body } = {}
-- 6.7 B: the joints these layers wrote; their values go through client/PoseLedger.luau (shared with ArmPose,
-- SprintPose and BodyLife, so the waist's and the arm's layers add up instead of piling up on a frame the Animator
-- skips).
local written: { [Instance]: boolean } = {}

-- The animation's own value of a joint this frame (client/PoseLedger.luau).
local function baseOf(joint: any): CFrame
	return Ledger.base(joint)
end

-- `rotation` on top of the animation (and the layers under this one); nil lets the joint go (back to the animation).
local function lay(joint: any, rotation: CFrame?)
	if not joint then
		return
	end
	if rotation and joint.Parent then
		local out = Ledger.now(joint) * rotation
		if out == out then -- (never a NaN on a joint)
			Ledger.write(joint, out)
			written[joint] = true
		end
		return
	end
	if written[joint] then
		written[joint] = nil
		Ledger.release(joint)
	end
end

-- Degrees { x, y, z } (Gestures' order: CFrame.Angles(0, y, 0) * CFrame.Angles(x, 0, z)) by a share.
local function turned(a: { number }, w: number): CFrame
	return CFrame.Angles(0, math.rad(a[2]) * w, 0) * CFrame.Angles(math.rad(a[1]) * w, 0, math.rad(a[3]) * w)
end

local function letGoBody(character: Model)
	local body = bodies[character]
	if body then
		lay(body.ls, nil)
		lay(body.le, nil)
		lay(body.waist, nil)
		lay(body.neck, nil)
		bodies[character] = nil
	end
end

local function recent(character: Model, name: string): boolean
	local at = character:GetAttribute(name)
	return type(at) == "number" and workspace:GetServerTimeNow() - at < BUSY_FOR
end

-- Has something else the left arm now (client/ArmPose.luau: aiming, carrying, the phone, a gesture, a swing, a car
-- door; client/SprintPose.luau: the sprint)?
local function armTaken(character: Model, mine: boolean, gesturing: boolean): boolean
	if gesturing or character:GetAttribute("Carrying") ~= nil or character:GetAttribute("PhoneHeld") == true or SprintPose.weight(character) > 0.001 then
		return true
	end
	if mine then
		local aiming = CameraRig.aimPose()
		local swingAt = Holster.localSwing()
		if aiming or (swingAt ~= nil and os.clock() - swingAt < BUSY_FOR) then
			return true
		end
	elseif character:GetAttribute("Aiming") == true or recent(character, "MeleeAt") then
		return true
	end
	return recent(character, "BoardAt") or recent(character, "AlightAt")
end

-- The gesture the body is in (its Gesture / GestureAt attributes, played from when it arrived here, as ArmPose plays
-- it; an old one, from before it came into view, does not play): its kind and the seconds into it, or nil.
local function gestureOf(character: Model, body: Body): (string?, number)
	local value = character:GetAttribute("GestureAt")
	local kind = character:GetAttribute("Gesture")
	if type(value) ~= "number" or type(kind) ~= "string" then
		return nil, 0
	end
	if body.gestureAt ~= value then
		body.gestureAt = value
		body.gestureStart = if workspace:GetServerTimeNow() - value < 1 then os.clock() else -math.huge
	end
	local t = os.clock() - body.gestureStart
	local total = Gestures.seconds(kind)
	if not total or t >= total then
		return nil, 0
	end
	return kind, t
end

local function bodyStep(player: Player, character: Model, humanoid: Humanoid, root: BasePart, dt: number, mine: boolean, now: number)
	if not character:FindFirstChild("UpperTorso") then
		return -- (R15 only)
	end
	local body = bodies[character]
	if not body then
		body = { ls = nil, le = nil, waist = nil, neck = nil, expires = 0, arm = 0, lean = 0, calmSince = nil, busyUntil = 0, gestureAt = nil, gestureStart = 0 }
		bodies[character] = body
	end
	local b = body :: Body
	local gone = (b.ls and not b.ls.Parent) or (b.waist and not b.waist.Parent) or (b.neck and not b.neck.Parent)
	if now >= b.expires or gone then
		b.ls = Joints.find(character:FindFirstChild("LeftUpperArm"), "LeftShoulder")
		b.le = Joints.find(character:FindFirstChild("LeftLowerArm"), "LeftElbow")
		b.waist = Joints.find(character:FindFirstChild("UpperTorso"), "Waist")
		b.neck = Joints.find(character:FindFirstChild("Head"), "Neck")
		b.expires = now + RIG_REFRESH
	end
	local onFoot = humanoid.Health > 0 and not humanoid.Sit and humanoid.SeatPart == nil and character:GetAttribute("ZipLine") == nil
		and character:GetAttribute("ClimbLine") == nil and not Interact.posing(character)
	local sprinting = SprintPose.weight(character) > 0.001
	local kind, t = gestureOf(character, b)
	-- the bag arm: a little straighter and out while the bag hangs in the left hand and nothing else has the arm
	local inHand = onFoot and character:GetAttribute("BagWorn") == "hand"
	if armTaken(character, mine, kind ~= nil) then
		b.busyUntil = now + A.Hold
	end
	local want = if inHand and now >= b.busyUntil then 1 else 0
	local rate = dt / math.max(0.05, A.Blend)
	b.arm = math.clamp(b.arm + math.clamp(want - b.arm, -rate, rate), 0, 1)
	if b.arm > 0.001 then
		local w = b.arm * b.arm * (3 - 2 * b.arm)
		if b.ls and b.ls.Parent then
			-- out from the body; the animation's swing cut (the weight pulls the arm down)
			local swing = baseOf(b.ls):ToEulerAnglesXYZ()
			lay(b.ls, CFrame.Angles(-swing * A.SwingCut * w, 0, 0) * CFrame.Angles(0, 0, -math.rad(A.Out) * w))
		end
		if b.le and b.le.Parent then
			local bend = baseOf(b.le):ToEulerAnglesXYZ()
			lay(b.le, CFrame.Angles(-math.max(0, bend) * A.Straight * w, 0, 0))
		end
	elseif written[b.ls] or written[b.le] then
		lay(b.ls, nil)
		lay(b.le, nil)
	end
	-- the torso: the counter-lean of a loaded bag in the hand and a gesture's turn (the throw, the bag), only standing
	-- or slow and not sprinting (ArmPose leans the waist itself faster, SprintPose owns it in the sprint)
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if onFoot and not sprinting and speed < A.Calm then
		b.calmSince = b.calmSince or now
	else
		b.calmSince = nil
	end
	local calm = b.calmSince ~= nil and now - (b.calmSince :: number) >= CALM_FOR
	local count = tonumber(player:GetAttribute("BagCount")) or 0
	local goal = if calm and inHand then math.rad(A.Lean) * math.clamp(count / math.max(1, A.Full), 0, 1) else 0
	b.lean = if calm then b.lean + (goal - b.lean) * math.min(1, rate) else 0
	local shape = if kind then Gestures.body(kind, t) else nil
	local weight = if kind then Gestures.weight(kind, t) else 0
	local waist = if calm and shape and shape.waist and weight > 0 then shape.waist else nil
	if calm and (math.abs(b.lean) > 1e-3 or waist) then
		-- (leaning away from the bag on the left: the torso tips to the right, a turn about its Z)
		local rotation = CFrame.Angles(0, 0, -b.lean)
		if waist then
			rotation = turned(waist, weight) * rotation
		end
		lay(b.waist, rotation)
	elseif written[b.waist] then
		lay(b.waist, nil)
	end
	local neck = if onFoot and not sprinting and shape and shape.neck and weight > 0 then shape.neck else nil
	if neck then
		lay(b.neck, turned(neck, weight))
	elseif written[b.neck] then
		lay(b.neck, nil)
	end
end

local function step(dt: number)
	local me = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local range = DeviceBudget.range(B.Range)
	for _, player in Bodies.players() do
		local character = player.Character
		if not character then
			continue
		end
		local humanoid, root = Bodies.of(character)
		if not humanoid or not root or (player ~= me and eye ~= nil and (root.Position - eye).Magnitude > range) then
			if recs[character] then
				forget(character)
			end
			if bodies[character] then
				letGoBody(character) -- 6.7
			end
			continue
		end
		bodyStep(player, character, humanoid :: Humanoid, root :: BasePart, dt, player == me, now) -- 6.7
		-- 6.4.1: your bag, once per spawn: a look whether it is really on you
		if player == me and checks[character] ~= true then
			local worn = character:GetAttribute("BagWorn")
			local since = checks[character]
			if type(worn) ~= "string" then
				checks[character] = nil
				-- 6.5.1: the bag is your hand but the server put none on you: say so once (the Output)
				if character:GetAttribute("Hand") == "bag" and not missingTold[character] then
					local at = missingSince[character]
					if not at then
						missingSince[character] = now
					elseif now - at > 4 then
						missingTold[character] = true
						warn("[BagSway] you hold your bag (2) but the server put none on you (no BagWorn): look for a [KitWear] line in the server Output")
					end
				else
					missingSince[character] = nil
				end
			elseif type(since) ~= "number" then
				checks[character] = now
			elseif now - since >= CHECK.After then
				-- (6.4.1 review: not on a dead body, nor while a body part is being swapped: the bag hangs loose
				-- for a moment then; look again a little later)
				local pivot = character:FindFirstChild("KitBagPivot")
				local joint = pivot and pivot:FindFirstChild("BagSwing")
				local part0 = if joint and joint:IsA("Motor6D") then joint.Part0 else nil
				if humanoid.Health <= 0 or (part0 ~= nil and part0.Parent ~= character) then
					checks[character] = now
				else
					checks[character] = true
					diagnose(character, worn)
				end
			end
		end
		local rec = recs[character]
		if not rec then
			rec = { joint = nil, hand = nil, state = BagSwing.new(), nextLook = 0, written = false, tuning = tuningOf(nil), worn = "hand", walked = 0, rel = nil, from = nil, fromAt = 0, relBag = nil }
			recs[character] = rec
		end
		local joint, hand = rec.joint, rec.hand
		local switchAt = character:GetAttribute("BagSwitchAt")
		local switching = type(switchAt) == "number" and serverNow - switchAt < SWITCH + 0.3
		if joint and (joint.Parent == nil or not hand or hand.Parent ~= character) then
			release(rec) -- (the bag went: put away, rebuilt)
			joint, hand = nil, nil
		end
		if not joint then
			if now < rec.nextLook and not switching then
				continue
			end
			rec.nextLook = now + LOOK
			joint, hand = find(character)
			if not joint or not hand then
				continue
			end
			rec.joint, rec.hand = joint, hand
			-- 6.4: the bag that hangs there and how it is worn (a new one is a new joint); moved between the front and
			-- the back just now: it starts from where it was (rec.rel) and moves over SWITCH seconds
			local pivot = (joint :: Motor6D).Parent
			local worn = if pivot then pivot:GetAttribute("Worn") else nil
			rec.worn = if type(worn) == "string" then worn else "hand"
			rec.tuning = if rec.worn == "hand" then tuningOf(pivot) else WEAR
			local bagId = if pivot then pivot:GetAttribute("Bag") else nil
			rec.from = if switching and rec.rel and rec.relBag == bagId then rec.rel else nil -- (the same bag only)
			rec.relBag = if type(bagId) == "string" then bagId else nil
			rec.fromAt = if type(switchAt) == "number" then switchAt else 0
		end
		local grip = (hand :: BasePart).CFrame * (joint :: Motor6D).C0
		local at = grip.Position
		handVec[1], handVec[2], handVec[3] = at.X, at.Y, at.Z
		local velocity = root.AssemblyLinearVelocity
		bodyVec[1], bodyVec[2], bodyVec[3] = velocity.X, velocity.Y, velocity.Z
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		rec.walked = (rec.walked + speed * dt) % (C.Step * 64)
		local transform: CFrame
		if rec.worn == "hand" then
			local tx, tz, twist = BagSwing.step(rec.state, dt, handVec, bodyVec, rec.tuning)
			-- The world orientation: your facing, the twist about the handles, tilted away from where the bottom went.
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			local facing = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
			local right = facing:Cross(Vector3.yAxis)
			local want = CFrame.fromMatrix(Vector3.zero, right, Vector3.yAxis) * CFrame.Angles(0, twist, 0)
			local size = math.sqrt(tx * tx + tz * tz)
			if size > 1e-4 then
				-- (the bottom moved toward (tx, tz): the up axis leans the other way; axis = bottom's way × up)
				local axis = Vector3.new(tx / size, 0, tz / size):Cross(Vector3.yAxis)
				want = CFrame.fromAxisAngle(axis, size) * want
			end
			transform = grip.Rotation:Inverse() * want
		else
			-- 6.4: on the shoulder or the hip a small stiff swing and a bounce with the steps; on the back a soft bob
			local back = rec.worn == "back"
			local want = grip.Rotation
			if not back then
				local tx, tz = BagSwing.step(rec.state, dt, handVec, bodyVec, rec.tuning)
				local size = math.sqrt(tx * tx + tz * tz)
				if size > 1e-4 then
					want = CFrame.fromAxisAngle(Vector3.new(tx / size, 0, tz / size):Cross(Vector3.yAxis), size) * want
				end
			end
			local lift = BagSwing.bob(rec.walked, speed, if back then C.BackBob else C.Bounce, C.Step, B.FullSpeed)
			transform = CFrame.new(0, lift, 0) * (grip.Rotation:Inverse() * want)
		end
		-- 6.4: the move between the front and the back (from where it was, relative to the body, to its new place)
		local from = rec.from
		if from then
			local u = math.clamp((serverNow - rec.fromAt) / SWITCH, 0, 1)
			if u >= 1 then
				rec.from = nil
			else
				local blend = u * u * (3 - 2 * u)
				transform = grip:Inverse() * (root.CFrame * from):Lerp(grip * transform, blend)
			end
		end
		if transform == transform then -- (never a NaN on a joint)
			(joint :: Motor6D).Transform = transform
			rec.written = true
			rec.rel = root.CFrame:Inverse() * (grip * transform)
		end
	end
	if now - sweptAt > SWEEP then
		sweptAt = now
		for character in recs do
			if not character.Parent then
				recs[character] = nil
			end
		end
		for character in checks do
			if not character.Parent then
				checks[character] = nil
			end
		end
		for character in bodies do
			if not character.Parent then
				bodies[character] = nil
			end
		end
		for joint in written do
			if not joint.Parent then
				written[joint] = nil
			end
		end
	end
end

function BagSway.start()
	RunService.PreSimulation:Connect(step)
end

return BagSway
