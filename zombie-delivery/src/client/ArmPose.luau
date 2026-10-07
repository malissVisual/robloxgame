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
-- 5.0: the phone (the PhoneHeld attribute, server/KitWear.luau) is held the same way: the right forearm up.
-- 3.9: a holstered gun (the Holstered attribute, server/CloseCombat.luau; yours as client/Holster.luau shows it) is
-- hidden the same way on foot, so the arms hang empty. A melee swing (V) moves the right arm on top of whatever else
-- it does: a quick wind-up and a punch forward, or an overhead strike with the gun, about Config.Melee.SwingTime long
-- (shared/Melee.luau swing). The others' swings come from their MeleeAt / MeleeKind attributes, yours starts on the
-- key press (Holster.localSwing; your MeleeAt is not played again).
-- 3.10: getting into a car the right hand goes to the door's handle, getting out it pushes the door (the character's
-- BoardAt / BoardReach and AlightAt / AlightReach attributes, server/Vehicles.luau; the curve is shared/Boarding.luau
-- reach), laid on the right arm like the swing; everybody sees it, yours too from the same attributes.
-- 5.7: a short gesture on top of everything (shared/Gestures.luau: wave, give, take, knock), from the Gesture /
-- GestureAt attributes the server sets on characters and people (server/Npcs.luau Npcs.act): the receiver waves at the
-- door and reaches for the piece, the courier holds it out or reaches for it, knocks at the door. Both arms, R15 and R6.
-- 5.9.2, cheaper: each character's joints are looked up once (again every RIG_REFRESH seconds, or at once when one went
-- away); the other players farther than NPC_RANGE from the camera are left to the animation; the people in
-- workspace.Npcs are followed through their attributes (Carrying, PhoneHeld, Gesture / GestureAt) instead of a look at
-- every one of them every frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Joints = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Joints"))
local Melee = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Melee"))
local Boarding = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Boarding"))
local Gestures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Gestures"))
local Bodies = require(script.Parent.Bodies)
local CameraRig = require(script.Parent.CameraRig)
local Holster = require(script.Parent.Holster)
local SprintPose = require(script.Parent.SprintPose) -- 6.0.1: its run cycle leans the waist itself

local ArmPose = {}

local RAISE_TIME = 0.2 -- seconds for the arms to come up
local LOWER_TIME = 0.3
local CARRY_IN = 0.25 -- seconds to take the cargo into the arms
local CARRY_OUT = 0.3
local NPC_RANGE = 180 -- people (5.9.2: and other players) farther from the camera than this are not posed
local RIG_REFRESH = 2 -- 5.9.2: seconds a character's joints are kept before they are looked up again …
local RIG_RETRY = 0.5 -- … or this, while some are missing (a body still loading)
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

-- The joint goes from the animation toward `aim` (by aimT), then toward `carry` (by carryT), then (3.9) toward the
-- melee `swing` (by swingT); any may be nil. All 0 gives the joint back to the animation.
local function lay(joint: any, aim: CFrame?, aimT: number, carry: CFrame?, carryT: number, swing: CFrame?, swingT: number?, gesture: CFrame?, gestureT: number?)
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
	if swing and swingT and swingT > 0 then
		out = out:Lerp(swing, swingT)
	end
	if gesture and gestureT and gestureT > 0 then
		out = out:Lerp(gesture, gestureT) -- 5.7
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

-- 5.9.2: a character's joints, looked up once: kind "r15" (the arms and the waist), "r6" (rs / ls: the shoulders) or
-- "none". Looked up again after RIG_REFRESH seconds (Roblox may swap a fresh body's Motor6Ds for AnimationConstraints),
-- RIG_RETRY while some are missing, and at once when one of them left the body.
type Rig = { kind: string, rs: any, re: any, rw: any, ls: any, le: any, lw: any, waist: any, expires: number }
local rigs: { [Model]: Rig } = {}

local function gone(joint: any): boolean
	return joint ~= nil and joint.Parent == nil
end

local function intact(rig: Rig): boolean
	return not (gone(rig.rs) or gone(rig.re) or gone(rig.rw) or gone(rig.ls) or gone(rig.le) or gone(rig.lw) or gone(rig.waist))
end

local function rigOf(character: Model): Rig
	local now = os.clock()
	local rig = rigs[character]
	if rig and now < rig.expires and intact(rig) then
		return rig
	end
	local made: Rig
	if character:FindFirstChild("UpperTorso") then
		made = {
			kind = "r15",
			rs = jointIn(character, "RightUpperArm", "RightShoulder"),
			re = jointIn(character, "RightLowerArm", "RightElbow"),
			rw = jointIn(character, "RightHand", "RightWrist"),
			ls = jointIn(character, "LeftUpperArm", "LeftShoulder"),
			le = jointIn(character, "LeftLowerArm", "LeftElbow"),
			lw = jointIn(character, "LeftHand", "LeftWrist"),
			waist = jointIn(character, "UpperTorso", "Waist"),
			expires = 0,
		}
	else
		local torso = character:FindFirstChild("Torso")
		made = {
			kind = if torso then "r6" else "none",
			rs = Joints.find(torso, "Right Shoulder"),
			re = nil,
			rw = nil,
			ls = Joints.find(torso, "Left Shoulder"),
			le = nil,
			lw = nil,
			waist = nil,
			expires = 0,
		}
	end
	local complete = if made.kind == "r15" then made.rs and made.re and made.rw and made.ls and made.le and made.lw and made.waist
		elseif made.kind == "r6" then made.rs and made.ls
		else nil
	made.expires = now + (if complete then RIG_REFRESH else RIG_RETRY)
	rigs[character] = made
	return made
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
	if kind == "phone" then
		-- 5.0: the phone in the right hand (the PhoneHeld attribute, server/KitWear.luau): the upper arm a little forward
		-- and in, the forearm up toward the chest, the screen turned up to the face; the left arm swings free.
		return {
			rs = CFrame.Angles(0, math.rad(16), 0) * CFrame.Angles(math.rad(26), 0, 0),
			re = CFrame.Angles(math.rad(70), 0, 0),
			rw = CFrame.Angles(math.rad(-6), 0, 0),
		}
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

-- 3.9, the melee swing of the right arm (R15): per kind the wind-up and the hit; the arm goes from one to the other
-- (Melee.swing's k). A punch pulls the fist back, bent, and drives it straight forward a little inward; a strike with
-- the gun raises it over the shoulder and chops it down and forward, the wrist snapping the gun's butt ahead.
type SwingShape = { wind: ArmGoals, hit: ArmGoals, r6Wind: number, r6Hit: number }
local SWINGS: { [string]: SwingShape } = {
	punch = {
		wind = {
			rs = CFrame.Angles(0, math.rad(-8), 0) * CFrame.Angles(math.rad(-22), 0, 0),
			re = CFrame.Angles(math.rad(100), 0, 0),
			rw = CFrame.identity,
		},
		hit = {
			rs = CFrame.Angles(0, math.rad(14), 0) * CFrame.Angles(math.rad(88), 0, 0),
			re = CFrame.Angles(math.rad(6), 0, 0),
			rw = CFrame.identity,
		},
		r6Wind = math.rad(-25), -- R6: the shoulder about Z (+ is forward)
		r6Hit = math.rad(95),
	},
	gun = {
		wind = {
			rs = CFrame.Angles(0, math.rad(10), 0) * CFrame.Angles(math.rad(150), 0, 0),
			re = CFrame.Angles(math.rad(70), 0, 0),
			rw = CFrame.Angles(math.rad(20), 0, 0),
		},
		hit = {
			rs = CFrame.Angles(0, math.rad(14), 0) * CFrame.Angles(math.rad(68), 0, 0),
			re = CFrame.Angles(math.rad(14), 0, 0),
			rw = CFrame.Angles(math.rad(-35), 0, 0),
		},
		r6Wind = math.rad(160),
		r6Hit = math.rad(65),
	},
	-- 3.10: the hand on a car door's handle (forward, a little out, the elbow soft, the wrist turned to grip); the
	-- same pose from start to end (only how far it is laid on changes).
	reach = {
		wind = {
			rs = CFrame.Angles(0, math.rad(-12), 0) * CFrame.Angles(math.rad(68), 0, 0),
			re = CFrame.Angles(math.rad(24), 0, 0),
			rw = CFrame.Angles(math.rad(-18), 0, 0),
		},
		hit = {
			rs = CFrame.Angles(0, math.rad(-12), 0) * CFrame.Angles(math.rad(68), 0, 0),
			re = CFrame.Angles(math.rad(24), 0, 0),
			rw = CFrame.Angles(math.rad(-18), 0, 0),
		},
		r6Wind = math.rad(72),
		r6Hit = math.rad(72),
	},
}

-- Where the swing is: t 0..1 (how far it is laid on), k 0..1 (wind-up → hit), the kind.
type Swing = { t: number, k: number, kind: string }
local NO_SWING: Swing = { t = 0, k = 0, kind = "punch" }

-- 5.7: a gesture this frame: how far it is laid on (0..1), the R15 goals, the R6 shoulders (radians, nil: left alone).
type Gesture = { t: number, goals: ArmGoals, r6Right: number?, r6Left: number? }

local function anglesOf(a: { number }?): CFrame?
	if not a then
		return nil
	end
	return CFrame.Angles(0, math.rad(a[2]), 0) * CFrame.Angles(math.rad(a[1]), 0, math.rad(a[3]))
end

local function between(a: CFrame?, b: CFrame?, k: number): CFrame?
	return if a and b then a:Lerp(b, k) else a or b
end

-- Every pose on a character: aim (t 0..1, pitch in radians, + is up), carry (t 0..1, the kind held) and the swing.
local function pose(character: Model, aimT: number, pitch: number, carryT: number, kind: string?, swing: Swing?, gesture: Gesture?)
	local kick = kicks[character] or 0
	local gt = if gesture then gesture.t else 0
	local g: ArmGoals = if gesture then gesture.goals else {}
	local up = math.rad(90) + pitch + kick * 0.11
	local c: ArmGoals = carryGoals(if carryT > 0 then kind else nil)
	local sw = swing or NO_SWING
	local shape = if sw.t > 0 then SWINGS[sw.kind] or SWINGS.punch else nil
	local rig = rigOf(character)
	if rig.kind == "r15" then
		-- R15: an arm hangs down (-Y); turning about X lifts it forward (-Z), about Y swings it in or out.
		local w: ArmGoals = if shape then shape.wind else {}
		local h: ArmGoals = if shape then shape.hit else {}
		lay(rig.rs, CFrame.Angles(0, math.rad(8), 0) * CFrame.Angles(up, 0, 0), aimT, c.rs, carryT, between(w.rs, h.rs, sw.k), sw.t, g.rs, gt)
		lay(rig.re, CFrame.Angles(kick * 0.08, 0, 0), aimT, c.re, carryT, between(w.re, h.re, sw.k), sw.t, g.re, gt)
		lay(rig.rw, CFrame.identity, aimT, c.rw, carryT, between(w.rw, h.rw, sw.k), sw.t, g.rw, gt)
		lay(rig.ls, CFrame.Angles(0, math.rad(-38), 0) * CFrame.Angles(up - math.rad(8), 0, 0), aimT, c.ls, carryT, nil, 0, g.ls, gt)
		lay(rig.le, CFrame.Angles(math.rad(12), 0, 0), aimT, c.le, carryT, nil, 0, g.le, gt)
		lay(rig.lw, CFrame.identity, aimT, c.lw, carryT, nil, 0, g.lw, gt)
		return
	end
	if rig.kind == "r6" then
		-- R6: the shoulders swing about their Z axis (mirrored on the left); no elbows, so the arms come well forward.
		local lead = kind == "horse"
		local rightCarry = if carryT > 0 then CFrame.Angles(0, 0, math.rad(if lead then 25 else 75)) else nil
		local leftCarry = if carryT > 0 and not lead then CFrame.Angles(0, 0, -math.rad(75)) else nil
		local rightSwing = if shape then CFrame.Angles(0, 0, shape.r6Wind + (shape.r6Hit - shape.r6Wind) * sw.k) else nil
		local r6Right = if gesture and gesture.r6Right then CFrame.Angles(0, 0, gesture.r6Right) else nil
		local r6Left = if gesture and gesture.r6Left then CFrame.Angles(0, 0, -gesture.r6Left) else nil
		lay(rig.rs, CFrame.Angles(0, 0, up), aimT, rightCarry, carryT, rightSwing, sw.t, r6Right, gt)
		lay(rig.ls, CFrame.Angles(0, 0, -(up - math.rad(10))), aimT, leftCarry, carryT, nil, 0, r6Left, gt)
	end
end

-- The aim pose on a character: t = 0 (the animation alone) .. 1 (the gun up), pitch in radians (+ is up).
function ArmPose.apply(character: Model, t: number, pitch: number)
	pose(character, t, pitch, 0, nil)
end

-- What a character holds (the server's Carrying attribute; 5.0: "phone" while the server shows the phone in its
-- right hand, the PhoneHeld attribute), or nil.
local function carryingOf(character: Model): string?
	local value = character:GetAttribute("Carrying")
	if type(value) == "string" and value ~= "" then
		return value
	end
	return if character:GetAttribute("PhoneHeld") == true then "phone" else nil
end

-- The gun in the hand is hidden (on this client) while the hands hold cargo or (3.9) it is holstered on foot, and comes
-- back after. Every client does it for every character, so everybody sees it away.
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
					elseif part:IsA("Light") then
						part.Enabled = true -- a glowing gun (GunModels piece.glow: Dead End)
					end
				end
			end
		end
		return
	end
	-- 6.1.1: hidden again when something showed it. Roblox's camera (the PlayerModule's TransparencyController) sets
	-- LocalTransparencyModifier on every part of your character each time a part is added or removed (the bag taken off
	-- or put on, the phone): the holstered gun came back in your hand after 1 (fists). One part tells (it sets them all).
	if gun and gun == hidden then
		local probe = gun:FindFirstChildWhichIsA("BasePart", true)
		if probe and probe.LocalTransparencyModifier < 1 then
			hiddenGuns[character] = nil
		end
	end
	if gun and gun ~= hiddenGuns[character] then
		hiddenGuns[character] = gun
		local parts = gun:GetDescendants()
		table.insert(parts, gun)
		for _, part in parts do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
			elseif part:IsA("Light") then
				part.Enabled = false -- a hidden part's light would still shine
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

local function leanBody(character: Model, humanoid: Humanoid?, root: BasePart?, dt: number)
	local waist = rigOf(character).waist
	if not waist or not root then
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
	-- (6.0.1: the sprint's lean is client/SprintPose.luau's run cycle while it runs: this one steps aside)
	local goal = if onFoot
		then LEAN_SPRINT * math.clamp((now - 12) / 9, 0, 1) * (1 - SprintPose.weight(character))
			- LEAN_BRAKE * math.clamp((braking - 15) / 40, 0, 1)
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

-- 3.9: the swing a character's arm is in (the others': their MeleeAt / MeleeKind attributes; yours: Holster). A new
-- MeleeAt plays from the moment it arrives here (a late attribute still shows the whole swing); an old one (you joined
-- later, it came back into view) does not play.
type Seen = { value: number, start: number }
local seenSwings: { [Model]: Seen } = {}
local swung: { [Model]: boolean } = {} -- swinging last frame (the arm goes back to the animation once it ends)

-- 3.10: the hand on the handle (getting in) or on the door (getting out), from the later of BoardAt and AlightAt;
-- played from the moment it arrives here, like a swing.
local seenReaches: { [Model]: Seen } = {}

local function reachOf(character: Model): Swing
	local value: number? = nil
	local out = false
	local into = character:GetAttribute("BoardAt")
	if type(into) == "number" and character:GetAttribute("BoardReach") == true then
		value = into
	end
	local away = character:GetAttribute("AlightAt")
	if type(away) == "number" and character:GetAttribute("AlightReach") == true and (value == nil or away > value) then
		value, out = away, true
	end
	if value == nil then
		return NO_SWING
	end
	local seen = seenReaches[character]
	local start: number
	if seen and seen.value == value then
		start = seen.start
	else
		start = if workspace:GetServerTimeNow() - value < 1 then os.clock() else -math.huge
		seenReaches[character] = { value = value, start = start }
	end
	local t = Boarding.reach(os.clock() - start, out)
	return if t > 0 then { t = t, k = 1, kind = "reach" } else NO_SWING
end

local function swingOf(character: Model, mine: boolean): Swing
	if mine then
		local at, kind = Holster.localSwing()
		if not at then
			return reachOf(character)
		end
		local t, k = Melee.swing(os.clock() - at)
		return if t > 0 then { t = t, k = k, kind = kind } else reachOf(character)
	end
	local value = character:GetAttribute("MeleeAt")
	if type(value) ~= "number" then
		return reachOf(character)
	end
	local seen = seenSwings[character]
	local start: number
	if seen and seen.value == value then
		start = seen.start
	else
		local fresh = workspace:GetServerTimeNow() - value < 1
		start = if fresh then os.clock() else -math.huge
		seenSwings[character] = { value = value, start = start }
	end
	local t, k = Melee.swing(os.clock() - start)
	if t <= 0 then
		return reachOf(character)
	end
	local kind = character:GetAttribute("MeleeKind")
	return { t = t, k = k, kind = if type(kind) == "string" then kind else "punch" }
end

-- 5.7: the gesture a character or a person is in (their Gesture / GestureAt attributes, server/Npcs.luau Npcs.act),
-- played from the moment it arrives here like a swing (an old one, from before it came into view, does not play).
local seenGestures: { [Model]: Seen } = {}
local gestured: { [Model]: boolean } = {} -- in a gesture last frame (the arms go back once it ends)

local function gestureOf(character: Model): Gesture?
	local value = character:GetAttribute("GestureAt")
	local kind = character:GetAttribute("Gesture")
	if type(value) ~= "number" or type(kind) ~= "string" then
		return nil
	end
	local seen = seenGestures[character]
	local start: number
	if seen and seen.value == value then
		start = seen.start
	else
		start = if workspace:GetServerTimeNow() - value < 1 then os.clock() else -math.huge
		seenGestures[character] = { value = value, start = start }
	end
	local t = os.clock() - start
	local weight = Gestures.weight(kind, t)
	local shape = if weight > 0 then Gestures.pose(kind, t) else nil
	if not shape then
		return nil
	end
	local right, left = Gestures.r6(kind, t)
	return {
		t = weight,
		goals = {
			rs = anglesOf(shape.rs),
			re = anglesOf(shape.re),
			rw = anglesOf(shape.rw),
			ls = anglesOf(shape.ls),
			le = anglesOf(shape.le),
			lw = anglesOf(shape.lw),
		},
		r6Right = if right then math.rad(right) else nil,
		r6Left = if left then math.rad(left) else nil,
	}
end

-- One character this frame: the aim and the carry pose blend in or out and go onto the joints, the swing on top.
-- holstered (3.9): the gun in the hand is hidden while on foot.
local function poseCharacter(character: Model, humanoid: Humanoid?, aiming: boolean, pitch: number, raise: number, dt: number, holstered: boolean?, swing: Swing?, gesture: Gesture?)
	local alive = humanoid ~= nil and humanoid.Health > 0 and not humanoid.Sit
	local kind = if alive then carryingOf(character) else nil
	-- Hands full: no gun.
	if kind or not alive then
		aiming = false
	end
	if kind or (holstered and humanoid ~= nil and not humanoid.Sit) then
		showGun(character, false)
	elseif hiddenGuns[character] then
		showGun(character, true)
	end
	local sw = if alive and not kind and swing and swing.t > 0 then swing else nil
	local gs = if alive and gesture and gesture.t > 0 then gesture else nil -- 5.7 (over the carry too: a reach)
	local blend = blends[character] or 0
	blend = if aiming then math.min(1, blend + dt / raise) else math.max(0, blend - dt / LOWER_TIME)
	local carry = carries[character]
	local carryBlend = if carry then carry.t else 0
	carryBlend = if kind then math.min(1, carryBlend + dt / CARRY_IN) else math.max(0, carryBlend - dt / CARRY_OUT)
	if blend <= 0 and carryBlend <= 0 and not sw and not gs then
		if blends[character] or carry or swung[character] or gestured[character] then
			pose(character, 0, 0, 0, nil) -- back to the animation alone
			blends[character] = nil
			carries[character] = nil
			swung[character] = nil
			gestured[character] = nil
		end
		return
	end
	if gs then
		gestured[character] = true
	else
		gestured[character] = nil
	end
	if sw then
		swung[character] = true
	else
		swung[character] = nil
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
	pose(character, ease(blend), math.clamp(pitch, -1.1, 1.1), ease(carryBlend), held, sw, gs)
end

-- 5.9.2: a character out of range: its arms and its waist given back to the animation (once).
local function letGo(character: Model)
	if blends[character] or carries[character] or swung[character] or gestured[character] then
		pose(character, 0, 0, 0, nil)
		blends[character] = nil
		carries[character] = nil
		swung[character] = nil
		gestured[character] = nil
	end
	if leans[character] then
		leans[character] = nil
		local rig = rigs[character]
		if rig and rig.waist and written[rig.waist] then
			layer(rig.waist, nil)
		end
	end
end

-- 5.9.2: the people of the world who carry something or gesture (or still blend out of it), from their attributes.
local npcActive: { [Model]: boolean } = {}
local npcHooks: { [Instance]: RBXScriptConnection } = {}
local npcFolder: Instance? = nil

local function npcCheck(model: Model)
	if carryingOf(model) or model:GetAttribute("GestureAt") ~= nil then
		npcActive[model] = true
	end
end

local function watchNpcs(folder: Instance)
	if npcFolder == folder then
		return
	end
	npcFolder = folder
	local function add(child: Instance)
		if not child:IsA("Model") or npcHooks[child] then
			return
		end
		local model = child
		npcHooks[model] = model.AttributeChanged:Connect(function(name: string)
			if name == "Carrying" or name == "PhoneHeld" or name == "GestureAt" or name == "Gesture" then
				npcCheck(model)
			end
		end)
		npcCheck(model)
	end
	for _, child in folder:GetChildren() do
		add(child)
	end
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(function(child: Instance)
		local hook = npcHooks[child]
		if hook then
			hook:Disconnect()
			npcHooks[child] = nil
		end
		if child:IsA("Model") then
			npcActive[child] = nil
		end
	end)
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
		-- (5.9.2: the far ones are left to the animation; yours never)
		if not mine and eye and (not root or (root.Position - eye).Magnitude > NPC_RANGE) then
			letGo(character)
			continue
		end
		local aiming: boolean, pitch: number
		if mine then
			aiming, pitch = CameraRig.aimPose()
		else
			aiming = character:GetAttribute("Aiming") == true
			local p = character:GetAttribute("AimPitch")
			pitch = if type(p) == "number" then p else 0
		end
		if aiming and mine and humanoid and humanoid.Health > 0 and not humanoid.Sit then
			report(character)
		end
		if rigOf(character).kind == "r15" then
			leanBody(character, humanoid, root, dt)
		end
		-- Yours come up slower out of a sprint (CameraRig decides); the others' at the normal pace.
		local raise = if mine then math.max(0.1, CameraRig.raiseTime() - 0.05) else RAISE_TIME
		-- 3.9: the holster (yours as you just chose it) and the melee swing.
		local holstered = if mine then Holster.holstered() else character:GetAttribute("Holstered") == true
		poseCharacter(character, humanoid, aiming, pitch, raise, dt, holstered, swingOf(character, mine), gestureOf(character))
	end
	-- The people of the world (givers, receivers) carry too (5.9.2: only the ones that do, or gesture).
	if eye then
		for model in npcActive do
			if not model.Parent then
				npcActive[model] = nil
				continue
			end
			local humanoid, root = Bodies.of(model)
			if root and (root.Position - eye).Magnitude <= NPC_RANGE then
				poseCharacter(model, humanoid, false, 0, RAISE_TIME, dt, nil, nil, gestureOf(model))
			end
			if not carries[model] and not carryingOf(model) and not gestured[model] and model:GetAttribute("GestureAt") == nil then
				npcActive[model] = nil
			end
		end
	end
	for character in rigs do
		if not character.Parent then
			rigs[character] = nil
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
	for character in seenSwings do
		if not character.Parent then
			seenSwings[character] = nil
		end
	end
	for character in seenReaches do
		if not character.Parent then
			seenReaches[character] = nil
		end
	end
	for character in swung do
		if not character.Parent then
			swung[character] = nil
		end
	end
	for character in seenGestures do
		if not character.Parent then
			seenGestures[character] = nil
			gestured[character] = nil
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
	-- 5.9.2: the people of the world, followed from their folder (made by the server, maybe later)
	local folder = workspace:FindFirstChild("Npcs")
	if folder then
		watchNpcs(folder)
	end
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Npcs" then
			watchNpcs(child)
		end
	end)
end

return ArmPose
