--!strict
-- 6.24: the gait, the pure maths (no Roblox at its top level: tests/gait_test.luau runs it in the standalone Luau and
-- tools/character-art/gait_sheet.py draws its key poses). The owner: "better animations, how he walks and moves".
-- client/GaitPose.luau feeds Gait.step every frame for every courier and person near the camera and writes the pose it
-- returns into the R15 joints' Transform (PreSimulation, through client/PoseLedger.luau's first stage: client/ArmPose,
-- BodyLife and BagSway lay their poses over it). Config.Gait holds the tuning, RunCycle the sprint.
--   * The walk is a cycle (Gait.stride: StrideBase legs + StrideGain × the speed, so the steps quicken with the speed)
--     whose phase moves with the distance walked. A foot on the ground is PLANTED: it goes back under the body at the
--     body's own speed (the leg reaches it with two bones, Gait.reach), rolling from the heel onto the toe (the ankle
--     over the pivot that stays put); the free foot swings forward, lifted. The hips dip just enough for the leg to
--     reach both feet (the walk's bob), shift over the foot on the ground, drop on the free side and turn with the leg
--     in front; the shoulders turn against them, the arms swing against the legs with the elbows bending, the head
--     stays level. Starting, the stride opens (StartTime); stopping, the trailing foot comes down beside the other
--     (SettleTime) and the body sways forward on its lean's spring.
--   * Any way: the hips turn toward where the body goes (at most StrafeYaw; going back, against it, and the legs walk
--     back), the chest back to the front (aiming: all of it, the arms stay on the gun), the feet never cross.
--   * From RunFrom the walk turns into the sprint's run cycle (shared/RunCycle.luau, Config.Courier.Sprint), tiring
--     out of breath (Gait.tired) and drooping once spent.
--   * The body leans into the speed it gains and against the braking (a spring: Gait.leanStep), into a turn about the
--     feet, into a slope (the feet land on it).
--   * The jump: a spring out of a crouch, the knees tucked rising, the legs reaching falling, a flail falling long; the
--     landing squashes by the height fallen (Gait.landDepth / landTimes / land), the knees bent, the feet planted.
--   * Idle: the stock idle (with client/BodyLife.luau's breath and weight shift) and now and then a fidget that fits the
--     hands (Gait.fidgetOf); spent with a hand free, the hands on the knees catching the breath. The gun out is held low
--     and ready, the bag in the left hand hangs out, a load in the hands widens the stance (ArmPose holds the load).
-- Frames: the root's (+X right, +Y up, -Z forward). About X a positive angle swings a thigh or an upper arm forward,
-- bends an elbow, lifts a toe and tips the upper body back; a knee bends with a negative X; about Y positive turns left;
-- about Z positive lifts the right side (the right arm out). Angles in radians, distances in studs.
-- A Pose holds, per joint slot (Gait.Names), its Transform as 12 numbers (x, y, z and the rotation's rows, as
-- CFrame.new(x, y, z, R00, R01, …, R22) takes them) and how far it is laid over the animation (0..1). Nothing is made
-- per step: the state, the input and the pose are each body's own tables, filled in place.
-- Why procedural, not KeyframeSequences built at runtime: the legs must follow each body's real speed, way, turn, slope
-- and breath every frame (a clip can only be sped up: its feet slide at any other speed or way), and every courier has
-- the same classic R15 body, so a pose is a few numbers; the stock tracks stay underneath as a far body's fallback.
-- Gait.step runs in parts (breathe, fly, move, stand, leanInto, hips, dip, rootOut, legsAim, legsOut, upper, holds,
-- upperOut) sharing one scratch record (F): keep each part small (Roblox compiles at -O0, 200 registers a function).

local Config = require(script.Parent.Config)
local RunCycle = require(script.Parent.RunCycle)
local BodyMotion = require(script.Parent.BodyMotion)

local Gait = {}

local G = Config.Gait
local S = Config.Courier.Sprint
local M = Config.Movement
local BA = Config.Courier.BagArm
local PI = math.pi
local TAU = 2 * PI
local GRAVITY = 196.2 -- studs / s² (workspace.Gravity's default)
local MAX_DT = 0.1
local rad = math.rad
local sin, cos, sqrt, abs, min, max = math.sin, math.cos, math.sqrt, math.abs, math.min, math.max
local clamp = math.clamp
local atan2 = math.atan2

-- The joint slots (client/GaitPose.luau finds each by its part and name).
Gait.ROOT, Gait.WAIST, Gait.NECK = 1, 2, 3
Gait.RH, Gait.RK, Gait.RA, Gait.LH, Gait.LK, Gait.LA = 4, 5, 6, 7, 8, 9
Gait.RS, Gait.RE, Gait.RW, Gait.LS, Gait.LE, Gait.LW = 10, 11, 12, 13, 14, 15
Gait.Count = 15
Gait.Names = { "Root", "Waist", "Neck", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle",
	"RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }
Gait.Parts = { "LowerTorso", "UpperTorso", "Head", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg",
	"LeftLowerLeg", "LeftFoot", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" }

-- A body's measures (studs, from its rig attachments: client/GaitPose.luau): the thigh (hip → knee), the shin (knee →
-- ankle), the ankle's height over the sole, the heel and the toe from the ankle along the foot, the hips' half spread and
-- their depth under the Root joint, how far the thigh and the shin lean forward standing (radians: the block body's
-- ankle sits a little ahead of its knee); `ground` is the Root joint's height over the ground standing, `leg` hip → sole.
export type Body = {
	thigh: number, shin: number, ankle: number, heel: number, toe: number, hipX: number, hipY: number,
	thighTilt: number, shinTilt: number, ground: number, leg: number, scale: number,
}

-- One frame's look at a body (client/GaitPose.luau fills it).
export type Input = {
	dt: number,
	vx: number, -- the velocity in the root's frame (studs / s: +X right, +Z back) …
	vz: number,
	vy: number, -- … and the world's up
	y: number, -- the root's height (world)
	yawRate: number, -- radians / s the root turns (+ left)
	air: boolean, -- off the ground (jumping, falling)
	slopeF: number, -- the ground's rise a stud forward and a stud right (the root's frame)
	slopeR: number,
	breath: number, -- 0..1; a negative one: guess it from the sprint (another courier)
	hands: string, -- "free" | "bag" (in the left hand) | "gun" (out, not aiming) | "carry" | "busy" (aim, phone, gesture)
	heavy: number, -- 0..1: the load slows the body (a heavy piece)
	aiming: boolean,
	detail: boolean, -- near: fidgets, the catch
	calm: boolean, -- Reduced Motion: no fidgets, no flail, half the wobble
}

export type State = {
	seed: number,
	phase: number, -- the right leg's 0..1 (0: its heel strikes), the left half a cycle on
	amp: number, -- the stride's share: 0 standing … 1 walking
	hold: number, -- how far the walk holds the body over the animation (all of it until the stride has closed)
	speed: number, -- the ground speed, smoothed
	dir: number, -- the way the body goes (radians from its front, + right), smoothed
	back: boolean, -- walking backwards (the hips turned against the way)
	yaw: number, -- the hips' turn toward the way (+ left)
	fwd: number, -- the forward speed last step …
	accel: number, -- … and its change (studs / s², smoothed)
	lean: number, -- the start / stop lean (+ forward) …
	leanV: number, -- … and its rate
	turn: number, -- the lean into a turn (+ left)
	sink: number, -- the walk's dip (studs), followed quickly (the reach's dip turns steeply near the leg's length)
	slopeF: number,
	slopeR: number,
	inAir: boolean,
	jumped: boolean,
	airT: number,
	peakY: number,
	airW: number, -- the air pose's share
	landT: number, -- seconds since the landing …
	landDepth: number, -- … its squash (legs), down and up seconds
	landDown: number,
	landUp: number,
	landW: number,
	breath: number, -- the guessed breath (another courier's)
	rest: number,
	spent: boolean,
	tired: number,
	spentW: number,
	gun: number, -- the holds' shares (eased)
	bag: number,
	carry: number,
	aim: number,
	catching: boolean,
	catch: number,
	stillT: number,
	idleT: number,
	nextAt: number,
	fidget: string?,
	fidgetT: number,
	fidgetCut: number,
	fidgetN: number,
	last: string?,
}

export type Pose = { m: { number }, w: { number } }

local function smooth(x: number): number
	local u = clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end
Gait.smooth = smooth

local function smoother(x: number): number
	local u = clamp(x, 0, 1)
	return u * u * u * (u * (u * 6 - 15) + 10)
end

local function hash(n: number): number
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end

local function wrap(p: number): number
	return p - math.floor(p)
end

local function wrapPi(a: number): number
	return (a + PI) % TAU - PI
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Toward `goal` by `per` at most (an even blend).
local function toward(x: number, goal: number, per: number): number
	if x < goal then
		return min(goal, x + per)
	end
	return max(goal, x - per)
end

-- Toward `goal` at `rate` per second (the rest shrinks evenly at any frame rate).
local function follow(x: number, goal: number, rate: number, dt: number): number
	return x + (goal - x) * (1 - math.exp(-rate * dt))
end

-- The larger of a and b, rounded off within k (no kink where they cross).
local function smax(a: number, b: number, k: number): number
	local d = a - b
	return (a + b + sqrt(d * d + k * k)) / 2
end

-- x, kept above `floor` (eased in over k).
local function above(x: number, floor: number, k: number): number
	local d = x - floor
	return floor + (d + sqrt(d * d + k * k)) / 2
end

-- ── Rotations as 9 numbers (rows) ────────────────────────────────────────────────────────────────────────────────────

-- Ry(yaw) · Rx(pitch) · Rz(roll): CFrame.fromEulerAnglesYXZ(pitch, yaw, roll); also Gestures' arms: CFrame.Angles(0, y,
-- 0) * CFrame.Angles(x, 0, z).
local function yxz(pitch: number, yaw: number, roll: number): (number, number, number, number, number, number, number, number, number)
	local cx, sx, cy, sy, cz, sz = cos(pitch), sin(pitch), cos(yaw), sin(yaw), cos(roll), sin(roll)
	return cy * cz + sy * sx * sz, -cy * sz + sy * sx * cz, sy * cx,
		cx * sz, cx * cz, -sx,
		-sy * cz + cy * sx * sz, sy * sz + cy * sx * cz, cy * cx
end
Gait.yxz = yxz

-- Rz(roll) · Rx(pitch): a hip (the leg's plane rolled out, the leg swung in it).
local function zx(roll: number, pitch: number): (number, number, number, number, number, number, number, number, number)
	local cc, sc, cp, sp = cos(roll), sin(roll), cos(pitch), sin(pitch)
	return cc, -sc * cp, sc * sp, sc, cc * cp, -cc * sp, 0, sp, cp
end

local function mul(a00: number, a01: number, a02: number, a10: number, a11: number, a12: number, a20: number, a21: number, a22: number,
	b00: number, b01: number, b02: number, b10: number, b11: number, b12: number, b20: number, b21: number, b22: number)
	: (number, number, number, number, number, number, number, number, number)
	return a00 * b00 + a01 * b10 + a02 * b20, a00 * b01 + a01 * b11 + a02 * b21, a00 * b02 + a01 * b12 + a02 * b22,
		a10 * b00 + a11 * b10 + a12 * b20, a10 * b01 + a11 * b11 + a12 * b21, a10 * b02 + a11 * b12 + a12 * b22,
		a20 * b00 + a21 * b10 + a22 * b20, a20 * b01 + a21 * b11 + a22 * b21, a20 * b02 + a21 * b12 + a22 * b22
end

local function put(m: { number }, j: number, x: number, y: number, z: number,
	r00: number, r01: number, r02: number, r10: number, r11: number, r12: number, r20: number, r21: number, r22: number)
	local o = (j - 1) * 12
	m[o + 1], m[o + 2], m[o + 3] = x, y, z
	m[o + 4], m[o + 5], m[o + 6] = r00, r01, r02
	m[o + 7], m[o + 8], m[o + 9] = r10, r11, r12
	m[o + 10], m[o + 11], m[o + 12] = r20, r21, r22
end

-- ── Makers ───────────────────────────────────────────────────────────────────────────────────────────────────────────

function Gait.body(thigh: number, shin: number, ankle: number, heel: number, toe: number, hipX: number, hipY: number,
	thighTilt: number?, shinTilt: number?): Body
	local tt, st = thighTilt or 0, shinTilt or 0
	local leg = max(thigh * cos(tt) + shin * cos(st) + max(ankle, 0), 0.3)
	return {
		thigh = max(thigh, 0.1), shin = max(shin, 0.1), ankle = max(ankle, 0), heel = max(heel, 0), toe = max(toe, 0),
		hipX = hipX, hipY = hipY, thighTilt = tt, shinTilt = st, ground = hipY + leg, leg = leg, scale = leg / 2,
	}
end

-- Roblox's classic R15 (server/CharacterArt's block stand-in: its rig; tests, the preview, a body whose rig cannot be
-- read). Its shin runs 0.1 forward to the ankle.
Gait.Classic = Gait.body(0.95, math.sqrt(0.77 * 0.77 + 0.01), 0.3, 0.6, 0.6, 0.5, 0.2, 0, math.atan2(0.1, 0.77))

function Gait.new(seed: number): State
	return {
		seed = seed, phase = G.DutySlow / 2, amp = 0, hold = 0, speed = 0, dir = 0, back = false, yaw = 0, fwd = 0, accel = 0, lean = 0,
		leanV = 0, turn = 0, sink = 0, slopeF = 0, slopeR = 0, inAir = false, jumped = false, airT = 0, peakY = 0, airW = 0,
		landT = math.huge, landDepth = 0, landDown = 0.1, landUp = 0.2, landW = 0, breath = 1, rest = math.huge,
		spent = false, tired = 0, spentW = 0, gun = 0, bag = 0, carry = 0, aim = 0, catching = false, catch = 0,
		stillT = 0, idleT = 0, nextAt = G.IdleAfter * (0.8 + 0.5 * hash(seed * 7.7)), fidget = nil, fidgetT = 0,
		fidgetCut = 1, fidgetN = 0, last = nil,
	}
end

function Gait.input(): Input
	return {
		dt = 0, vx = 0, vz = 0, vy = 0, y = 0, yawRate = 0, air = false, slopeF = 0, slopeR = 0, breath = -1,
		hands = "free", heavy = 0, aiming = false, detail = true, calm = false,
	}
end

function Gait.pose(): Pose
	local m: { number } = table.create(Gait.Count * 12, 0)
	for j = 1, Gait.Count do
		put(m, j, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	return { m = m, w = table.create(Gait.Count, 0) }
end

-- ── The pieces (each tested on its own) ──────────────────────────────────────────────────────────────────────────────

-- Studs a walk's cycle (two steps) covers at `speed` on legs of `leg` studs; the cadence is speed / stride.
function Gait.stride(speed: number, leg: number): number
	return leg * G.StrideBase + G.StrideGain * max(speed, 0)
end

-- The run's share of the gait at `speed` (0: the walk … 1: the sprint's run cycle, from Config.Courier.Sprint.From).
function Gait.runShare(speed: number): number
	return smooth((speed - G.RunFrom) / max(S.From - G.RunFrom, 0.1))
end

-- The share of a cycle a foot is down at `speed` (the walk's).
function Gait.duty(speed: number): number
	return lerp(G.DutySlow, G.DutyBrisk, clamp(speed / G.WalkRef, 0, 1))
end

-- A two-bone leg reaching from its hip to a point (dx, dy, dz: the ankle from the hip, in the hips' frame, -Z ahead):
-- the hip's roll out (about Z), its swing (about X, + forward) and the knee's bend (positive; the joint takes -bend),
-- the knee never straighter than Reach of the leg allows. A point out of reach is reached toward as far as it goes.
function Gait.reach(dx: number, dy: number, dz: number, thigh: number, shin: number): (number, number, number)
	local ahead, down, side = -dz, -dy, dx
	local roll = atan2(side, max(down, 1e-3))
	local inPlane = sqrt(down * down + side * side)
	local r = clamp(sqrt(ahead * ahead + inPlane * inPlane), abs(thigh - shin) + 0.05, (thigh + shin) * G.Reach)
	local bend = PI - math.acos(clamp((thigh * thigh + shin * shin - r * r) / (2 * thigh * shin), -1, 1))
	local swing = atan2(ahead, inPlane) + math.acos(clamp((thigh * thigh + r * r - shin * shin) / (2 * thigh * r), -1, 1))
	return roll, swing, bend
end

-- The ankle over the foot's pivot for a foot pitched `pitch` (+ toe up: about the heel; − heel up: about the toe),
-- from where it stands flat: along the foot (+ toward the toe) and up.
function Gait.rocker(pitch: number, b: Body): (number, number)
	if pitch >= 0 then
		return -b.heel + b.heel * cos(pitch) - b.ankle * sin(pitch), -b.ankle + b.heel * sin(pitch) + b.ankle * cos(pitch)
	end
	return b.toe - b.toe * cos(pitch) - b.ankle * sin(pitch), -b.ankle - b.toe * sin(pitch) + b.ankle * cos(pitch)
end

-- The landing's squash (legs) after falling `height` studs (0: none; a kerb's step is not a landing).
function Gait.landDepth(height: number): number
	if height <= 0 then
		return 0
	end
	if height < G.LandFrom then
		return G.LandMin * height / G.LandFrom
	end
	local k = clamp((height - G.LandFrom) / max(G.LandFull - G.LandFrom, 1), 0, 1)
	return G.LandMin + (G.LandMax - G.LandMin) * (1 - (1 - k) * (1 - k))
end

-- The landing's seconds down and back up after falling `height` studs.
function Gait.landTimes(height: number): (number, number)
	local k = clamp((height - G.LandFrom) / max(G.LandFull - G.LandFrom, 1), 0, 1)
	return G.LandDown * (1 + 0.6 * k), G.LandUp + (G.LandUpFull - G.LandUp) * k
end

-- How deep in the squash (0..1) `t` seconds after landing: quickly down, then smoothly back up.
function Gait.land(t: number, down: number, up: number): number
	if t <= 0 or t >= down + up then
		return 0
	end
	if t < down then
		return sin(PI / 2 * t / down)
	end
	return 1 - smoother((t - down) / up)
end

-- How tired the run is (0..1) with `breath` (0..1) left.
function Gait.tired(breath: number): number
	return smooth((G.TiredFrom - breath) / max(G.TiredFrom, 0.01))
end

-- One step of the start / stop lean's spring toward `goal` (radians), `dt` seconds: (lean, rate).
function Gait.leanStep(lean: number, rate: number, goal: number, dt: number): (number, number)
	local w = TAU * G.LeanHz
	local steps = math.max(1, math.ceil(dt * 240))
	local h = dt / steps
	for _ = 1, steps do
		rate += (w * w * (goal - lean) - 2 * G.LeanDamp * w * rate) * h
		lean += rate * h
	end
	return lean, rate
end

-- The fidgets for what the hands hold (nil: none).
local FIDGETS: { [string]: { string } } = {
	free = { "look", "stretch", "watch", "shoulders" },
	bag = { "look", "peek", "shoulders" },
	gun = { "look", "checkgun", "look" },
	carry = { "hoist", "look" },
}
function Gait.fidgetsFor(hands: string): { string }?
	return FIDGETS[hands]
end

-- The fidget a body plays as its `n`th (its own seed; never the same twice in a row).
function Gait.fidgetOf(hands: string, seed: number, n: number, last: string?): string?
	local list = FIDGETS[hands]
	if not list then
		return nil
	end
	local i = 1 + math.floor(hash(seed * 31.7 + n * 3.1) * #list) % #list
	if list[i] == last then
		i = i % #list + 1
	end
	return list[i]
end

-- A fidget's weight `t` seconds in (0 outside).
function Gait.fidgetWeight(kind: string, t: number): number
	local total = G.Fidgets[kind]
	if not total or t <= 0 or t >= total then
		return 0
	end
	return min(smooth(t / 0.35), smooth((total - t) / 0.45))
end

-- ── The step ─────────────────────────────────────────────────────────────────────────────────────────────────────────

-- (scratch, per leg and arm: 1 right, 2 left; filled and read within one step)
local footX, footY, footF, footP = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
local legC, legP, legK, legA = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
local armX, armY, armZ, armE, armW, armLift = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
local runPose = RunCycle.blank()
local ROCK_IN, ROCK_OUT = 0.15, 0.6 -- of the stance: the heel rolls down by …, the heel lifts from …
local BACK_IN, BACK_OUT = -0.2, 0.05 -- the way's share along the front: walking backwards under …, forwards again over

-- Blend arm `i` toward (x, y, z, elbow, wrist) by `t`.
local function armTo(i: number, t: number, x: number, y: number, z: number, e: number, w: number)
	if t <= 0 then
		return
	end
	armX[i] = lerp(armX[i], x, t)
	armY[i] = lerp(armY[i], y, t)
	armZ[i] = lerp(armZ[i], z, t)
	armE[i] = lerp(armE[i], e, t)
	armW[i] = lerp(armW[i], w, t)
end

-- A key's share: up over [a, b], held, down over [c, d] (seconds).
local function key(t: number, a: number, b: number, c: number, d: number): number
	return min(smooth((t - a) / max(b - a, 1e-3)), 1 - smooth((t - c) / max(d - c, 1e-3)))
end

-- The step's numbers its parts share (one record for every body: filled and read within one step, in order).
type Frame = {
	dt: number, leg: number, breath: number, v: number, vf: number, sp: number, ux: number, uf: number, n: number,
	run: number, walkStride: number, duty: number, amp: number, p: number, squash: number, landing: boolean,
	fidget: string?, fw: number, ft: number, yaw: number, pfX: number, pfF: number, prX: number, prF: number,
	ahead: number, sway: number, roll: number, hipTurn: number, chestTurn: number, heavy: number, drop: number,
	tired: number, spent: number, rootYaw: number, rootPitch: number, rootRoll: number, leanP: number, leanR: number,
	slopeLean: number, crouch: number, rising: number, flail: number, airClock: number, landShare: number,
	waistYaw: number, waistPitch: number, waistRoll: number, waistW: number, armWR: number, armWL: number,
	wristR: number, neckYawF: number, neckPitchF: number, neckRollF: number,
	r: { number }, -- the Root joint's rotation (rows) …
	tx: number, -- … and its place
	ty: number,
	tz: number,
}
local F: Frame = {
	dt = 0, leg = 2, breath = 1, v = 0, vf = 0, sp = 0, ux = 0, uf = 1, n = 0, run = 0, walkStride = 1, duty = 0.6,
	amp = 0, p = 0, squash = 0, landing = false, fidget = nil, fw = 0, ft = 0, yaw = 0, pfX = 0, pfF = 1, prX = 1,
	prF = 0, ahead = 1, sway = 0, roll = 0, hipTurn = 0, chestTurn = 0, heavy = 0, drop = 0, tired = 0, spent = 0,
	rootYaw = 0, rootPitch = 0, rootRoll = 0, leanP = 0, leanR = 0, slopeLean = 0, crouch = 0, rising = 0, flail = 0,
	airClock = 0, landShare = 0, waistYaw = 0, waistPitch = 0, waistRoll = 0, waistW = 0, armWR = 0, armWL = 0,
	wristR = 0, neckYawF = 0, neckPitchF = 0, neckRollF = 0, r = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, tx = 0, ty = 0, tz = 0,
}

-- The breath (yours from client/Stamina.luau; another courier's guessed: a sprint drains it, rest brings it back).
local function breathe(s: State, i: Input, dt: number)
	local breath = i.breath
	if breath < 0 then
		if s.speed > S.From and not s.inAir then
			s.breath = max(0, s.breath - dt / M.Stamina)
			s.rest = 0
		else
			s.rest += dt
			if s.rest > M.RecoverDelay then
				s.breath = min(1, s.breath + dt / M.Recover)
			end
		end
		breath = s.breath
	end
	if breath <= 0.05 then
		s.spent = true
	elseif breath >= 0.5 then
		s.spent = false
	end
	s.tired = follow(s.tired, Gait.tired(breath), 3, dt)
	s.spentW = toward(s.spentW, if s.spent then 1 else 0, dt / 0.5)
	F.breath = breath
end

-- In the air: the jump (up faster than JumpFrom leaving the ground) or a fall; the height fallen is the landing's.
local function fly(s: State, i: Input, dt: number)
	if i.air then
		if not s.inAir then
			s.inAir, s.airT, s.peakY, s.jumped = true, 0, i.y, i.vy > G.JumpFrom
		end
		s.airT += dt
		if i.y > s.peakY then
			s.peakY = i.y
		end
	elseif s.inAir then
		s.inAir = false
		if s.jumped or s.airT >= G.FallAfter then
			local height = max(0, s.peakY - i.y)
			local onTheMove = if s.speed > 4 then G.MoveLand else 1
			s.landDepth = Gait.landDepth(height) * onTheMove
			local down, up = Gait.landTimes(height)
			s.landDown, s.landUp, s.landT = down, up * onTheMove, 0
		end
	end
	if not s.inAir then
		s.landT += dt
	end
	local airPosed = s.inAir and (s.jumped or s.airT >= G.FallAfter)
	s.airW = toward(s.airW, if airPosed then 1 else 0, dt / (if s.jumped and s.inAir then G.JumpBlend else G.AirBlend))
	local landing = s.landT < s.landDown + s.landUp
	F.landing = landing
	F.squash = s.landDepth * Gait.land(s.landT, s.landDown, s.landUp) * F.leg
	s.landW = toward(s.landW, if landing then 1 else 0, dt / 0.12)
end

-- The ground speed, the way the body goes, the stride: it opens walking and closes standing (the settling step: on to
-- the moment the feet pass each other).
local function move(s: State, i: Input, b: Body, dt: number)
	local vx, vf = i.vx, -i.vz
	local v = sqrt(vx * vx + vf * vf)
	s.speed = follow(s.speed, v, 12, dt)
	local sp = s.speed
	if v > 0.4 then
		s.dir = wrapPi(s.dir + wrapPi(atan2(vx, vf) - s.dir) * (1 - math.exp(-14 * dt)))
	end
	local ux, uf = sin(s.dir), cos(s.dir)
	if s.back then
		if uf > BACK_OUT then
			s.back = false
		end
	elseif uf < BACK_IN then
		s.back = true
	end
	local run = Gait.runShare(sp)
	local slopeAlong = s.slopeF * uf + s.slopeR * ux
	local walkStride = Gait.stride(sp, b.leg) * (1 - G.SlopeStride * min(abs(slopeAlong), 1)) * lerp(1, G.CarryStride, s.carry)
	local stride = lerp(walkStride, S.Stride * b.scale, run)
	local duty = Gait.duty(sp)
	local go = not s.inAir and v > (if s.amp > 0.02 then G.StopBelow else G.MoveFrom)
	if go then
		s.amp = min(1, s.amp + dt / G.StartTime)
		s.phase = wrap(s.phase + v * dt / max(stride, 0.1))
	elseif not s.inAir and s.amp > 0 then
		local ahead = min(wrap(duty / 2 - s.phase), wrap(duty / 2 + 0.5 - s.phase))
		s.phase = wrap(s.phase + ahead * min(1, dt / max(s.amp * G.SettleTime, dt)))
		s.amp = max(0, s.amp - dt / G.SettleTime)
	end
	-- (the body stays the walk's until the stride has closed, then goes back to the animation over LetGo: the stock walk
	-- has faded out under it by then)
	s.hold = toward(s.hold, if s.amp > 0 then 1 else 0, dt / (if s.amp > 0 then 0.1 else G.LetGo))
	F.v, F.vf, F.sp, F.ux, F.uf = v, vf, sp, ux, uf
	F.n = clamp(sp / G.WalkRef, 0, 1)
	F.run, F.walkStride, F.duty, F.amp, F.p = run, walkStride, duty, s.amp, s.phase
end

-- The holds; standing still: catching the breath (spent, a hand free), a fidget now and then.
local function stand(s: State, i: Input, dt: number)
	local hands = i.hands
	local hold = dt / G.HoldBlend
	s.gun = toward(s.gun, if hands == "gun" then 1 else 0, hold)
	s.bag = toward(s.bag, if hands == "bag" then 1 else 0, hold)
	s.carry = toward(s.carry, if hands == "carry" then 1 else 0, hold)
	s.aim = toward(s.aim, if i.aiming then 1 else 0, dt / 0.2)
	local breath = F.breath
	local still = not s.inAir and F.v < G.StopBelow and F.amp < 0.05
	s.stillT = if still then s.stillT + dt else 0
	local free = hands == "free" or hands == "bag"
	if s.catching then
		if not still or not free or breath >= G.CatchUntil then
			s.catching = false
		end
	elseif still and free and i.detail and not F.landing and s.stillT > G.CatchAfter and (s.spent or breath < 0.2)
		and breath < G.CatchUntil then
		s.catching = true
	end
	s.catch = toward(s.catch, if s.catching then 1 else 0, dt / (if s.catching then 0.45 else 0.35))
	local idle = still and not s.catching and s.catch <= 0 and not F.landing and i.detail and not i.calm
	if idle then
		s.idleT += dt
	else
		s.idleT = 0
		if not s.fidget then
			s.nextAt = G.IdleAfter * (0.8 + 0.5 * hash(s.seed * 7.7 + s.fidgetN))
		end
	end
	local fidget = s.fidget
	local fw = 0
	if fidget then
		s.fidgetT += dt
		if not idle then
			s.fidgetCut = max(0, s.fidgetCut - dt / 0.2)
		end
		fw = Gait.fidgetWeight(fidget, s.fidgetT) * s.fidgetCut
		if s.fidgetT >= (G.Fidgets[fidget] or 0) or s.fidgetCut <= 0 then
			s.fidget, fidget, fw = nil, nil, 0
			s.nextAt = s.idleT + G.FidgetEvery * (0.6 + 0.8 * hash(s.seed * 13.1 + s.fidgetN))
		end
	elseif idle and s.idleT >= s.nextAt then
		local kind = Gait.fidgetOf(hands, s.seed, s.fidgetN, s.last)
		s.fidgetN += 1
		if kind then
			s.fidget, s.fidgetT, s.fidgetCut, s.last = kind, 0, 1, kind
		else
			s.nextAt = s.idleT + G.FidgetEvery
		end
	end
	F.fidget, F.fw, F.ft = fidget, fw, s.fidgetT
end

-- The lean into the speed gained (a spring: it sways forward once as the body stops), into a turn, into a slope.
local function leanInto(s: State, i: Input, dt: number)
	local accel = (F.vf - s.fwd) / max(dt, 1 / 240)
	s.fwd = F.vf
	s.accel = follow(s.accel, clamp(accel, -120, 120), 10, dt)
	local leanGoal = if s.inAir then 0 else clamp(rad(G.Accel) * s.accel, -rad(G.LeanBack), rad(G.LeanMax)) * (1 - 0.7 * s.aim)
	s.lean, s.leanV = Gait.leanStep(s.lean, s.leanV, leanGoal, dt)
	local turnGoal = if s.inAir then 0 else clamp(math.atan(G.TurnLean * F.sp * i.yawRate / GRAVITY), -rad(G.TurnMax), rad(G.TurnMax))
	s.turn = follow(s.turn, turnGoal * (if i.calm then 0.5 else 1), 8, dt)
	s.slopeF = follow(s.slopeF, clamp(i.slopeF, -1, 1), 8, dt)
	s.slopeR = follow(s.slopeR, clamp(i.slopeR, -1, 1), 8, dt)
end

-- The hips: turned toward the way (backwards: against it), shifted over the foot down, the free side dropped, turned
-- with the leg in front; the chest against them. The feet (the root's frame): planted while down (back under the body
-- at its speed, rolling heel → toe), swung forward lifted; never crossing.
local function hips(s: State, i: Input, b: Body, dt: number)
	local amp, n, run, p, duty, leg = F.amp, F.n, F.run, F.p, F.duty, F.leg
	local theta = if s.back then wrapPi(s.dir + PI) else s.dir
	local yawGoal = -clamp(theta, -rad(G.StrafeYaw), rad(G.StrafeYaw)) * amp * (1 - run)
	s.yaw = follow(s.yaw, yawGoal, G.YawRate, dt)
	local yaw = s.yaw
	local pfX, pfF = -sin(yaw), cos(yaw) -- the hips' front …
	local prX, prF = cos(yaw), sin(yaw) -- … and right, in the root's frame (X right, F ahead)
	local ux, uf = F.ux, F.uf
	local ahead = clamp((ux * pfX + uf * pfF) * 1.6, -1, 1) -- the way along the hips' front (−1 walking back)
	local cyc = cos(TAU * p)
	local stance = cos(TAU * (p - duty / 2)) -- + over the right foot, − over the left
	local heavy = s.carry * clamp(i.heavy, 0, 1)
	F.yaw, F.pfX, F.pfF, F.prX, F.prF, F.ahead, F.heavy = yaw, pfX, pfF, prX, prF, ahead, heavy
	F.sway = leg * lerp(G.SwaySlow, G.Sway, n) * stance * amp * (1 + (G.CarrySway - 1) * heavy) * (1 - run)
	F.roll = rad(G.HipRoll) * n * stance * amp * (1 - 0.5 * s.carry) * (1 - run)
	F.hipTurn = rad(G.HipTurn) * n * cyc * amp * ahead
	F.chestTurn = rad(G.ChestTurn) * n * cyc * amp * ahead * (1 - 0.7 * s.carry) * (1 - s.aim)
	local a = duty * F.walkStride / 2 * amp
	local lift = leg * lerp(G.LiftSlow, G.Lift, n) * sqrt(amp) -- (the settling step still lifts its foot)
	local heelUp, toeUp = rad(G.Heel) * n * amp * ahead, rad(G.Toe) * n * amp * ahead
	local wide = b.hipX + leg * G.CarryWide * s.carry
	local gap = leg * G.FootGap
	for side = 1, 2 do
		local sgn = if side == 1 then 1 else -1
		local pl = if side == 1 then p else wrap(p + 0.5)
		local along, up, pitch = 0, 0, 0
		if pl < duty then
			local q = pl / duty
			along = a * (1 - 2 * q)
			if q < ROCK_IN then
				local r = 1 - q / ROCK_IN
				pitch = heelUp * r * r
			elseif q > ROCK_OUT then
				local r = (q - ROCK_OUT) / (1 - ROCK_OUT)
				pitch = -toeUp * r * r
			end
		else
			local u = (pl - duty) / (1 - duty)
			along = -a + 2 * a * smoother(u)
			up = lift * sin(PI * u ^ 0.75)
			pitch = -toeUp + (toeUp + heelUp) * smooth(u)
		end
		local dA, dU = Gait.rocker(pitch, b)
		local ax = sgn * wide * prX + ux * along + pfX * dA
		local af = sgn * wide * prF + uf * along + pfF * dA
		local lat = ax * prX + af * prF
		local keep = sgn * above(sgn * lat, gap, gap * 0.5)
		ax += (keep - lat) * prX
		af += (keep - lat) * prF
		footX[side] = ax
		footF[side] = af
		footY[side] = -b.ground + b.ankle + dU + up + s.slopeF * af + s.slopeR * ax
		footP[side] = pitch
	end
end

-- The hips dip as far as the legs need to reach both feet (the walk's bob), at most MaxDrop (each hip where the hips'
-- turn and roll put it: the free side drops about the hip on the ground); the landing's squash, the catch's bend, a
-- hoist and an aim's soft knees on top.
local function dip(s: State, b: Body, dt: number)
	local leg, sway, roll = F.leg, F.sway, F.roll
	local reachMax = (b.thigh + b.shin) * G.Reach
	local need1, need2 = 0, 0
	local turned = F.yaw + F.hipTurn
	local tX, tF = cos(turned), sin(turned)
	for side = 1, 2 do
		local sgn = if side == 1 then 1 else -1
		local hx = sway * F.prX + sgn * b.hipX * tX
		local hf = sway * F.prF + sgn * b.hipX * tF
		local dx, df = footX[side] - hx, footF[side] - hf
		local h2 = dx * dx + df * df
		local rise = if h2 < reachMax * reachMax then sqrt(reachMax * reachMax - h2) else 0
		local needed = -b.hipY + sgn * b.hipX * sin(roll) - (footY[side] + rise)
		if side == 1 then
			need1 = needed
		else
			need2 = needed
		end
	end
	s.sink = follow(s.sink, clamp(smax(need1, need2, 0.04 * b.scale), 0, leg * G.MaxDrop), G.DipRate, dt)
	local drop = s.sink + leg * (G.AimDrop * s.aim + 0.02 * F.heavy)
	local hoist = if F.fidget == "hoist" then 0.06 * leg * F.fw * sin(PI * clamp(F.ft / 0.9, 0, 1)) else 0
	F.drop = smax(drop, F.squash, 0.02) + 0.13 * leg * s.catch + hoist
end

-- The Root joint: the hips' own move (the run's: the sprint's cycle), tipped about the feet by the lean, the turn and
-- the slope; a take-off springs out of a crouch (the first frames of the jump).
local function rootOut(s: State, i: Input, b: Body, m: { number })
	local run, p, leg = F.run, F.p, F.leg
	F.tired = s.tired * run
	if run > 0 then
		RunCycle.pose(RunCycle.hang(p + G.RunPhase, S.Hang or 0), RunCycle.effort(F.sp, S.From, S.Full), runPose)
	end
	local catchBack = 0.07 * leg * s.catch
	F.rootYaw = F.yaw + lerp(F.hipTurn, runPose.hipTurn, run)
	F.rootPitch = -rad(16) * s.catch
	F.rootRoll = F.roll + rad(G.TiredWobble) * F.tired * sin(TAU * p) * (if i.calm then 0.5 else 1)
	local tx = F.sway * F.prX - catchBack * F.pfX
	local tz = -(F.sway * F.prF - catchBack * F.pfF)
	local ty = lerp(-F.drop, runPose.bob * b.scale - F.squash, run)
	F.slopeLean = rad(G.SlopeLean) * clamp(s.slopeF * F.uf, -0.6, 0.6) * F.amp
	F.leanP = -(s.lean * G.LeanRoot + F.slopeLean * 0.4)
	F.leanR = s.turn
	F.crouch = if s.inAir and s.jumped then 1 - smooth(s.airT / G.TakeoffTime) else 0
	ty -= G.TakeoffDrop * leg * F.crouch * s.airW
	local l00, l01, l02, l10, l11, l12, l20, l21, l22 = yxz(F.rootPitch, F.rootYaw, F.rootRoll)
	local n00, n01, n02, n10, n11, n12, n20, n21, n22 = yxz(F.leanP, 0, F.leanR)
	local r = F.r
	r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] = mul(n00, n01, n02, n10, n11, n12, n20, n21, n22, l00, l01, l02, l10, l11, l12, l20, l21, l22)
	local g = b.ground
	F.tx = n00 * tx + n01 * ty + n02 * tz + g * n01
	F.ty = max(n10 * tx + n11 * ty + n12 * tz - g + g * n11, -G.Lowest) -- (never hung as low as client/Unstuck.luau resets)
	F.tz = n20 * tx + n21 * ty + n22 * tz + g * n21
	put(m, Gait.ROOT, F.tx, F.ty, F.tz, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end

-- The legs: each reaches its foot (in the hips' frame), blended into the run's and the air's (rising: the knees tucked,
-- a stride in the air on the move; falling: reaching down; long: a flail; the take-off: out of the crouch).
local function legsAim(s: State, i: Input, b: Body)
	local thigh, shin, run, p = b.thigh, b.shin, F.run, F.p
	local r = F.r
	local mv = smooth(F.sp / 8)
	local rising = smooth((i.vy + 8) / 40)
	local flail = if i.calm then 0 else smooth((s.airT - G.FlailAfter) / 0.5)
	local clock = s.airT * 7
	F.rising, F.flail, F.airClock = rising, flail, clock
	local kh, kk, ka = 0, 0, 0
	if F.squash > 1e-3 and run > 0 then
		kh, kk, ka = BodyMotion.crouch(F.squash, 0, thigh, shin)
	end
	for side = 1, 2 do
		local sgn = if side == 1 then 1 else -1
		local px, py, pz = footX[side] - F.tx, footY[side] - F.ty, -footF[side] - F.tz
		local lx = r[1] * px + r[4] * py + r[7] * pz - sgn * b.hipX
		local ly = r[2] * px + r[5] * py + r[8] * pz + b.hipY
		local lz = r[3] * px + r[6] * py + r[9] * pz
		local c, hp, k = Gait.reach(lx, ly, lz, thigh, shin)
		local fp = footP[side]
		if run > 0 then
			local rh = (if side == 1 then runPose.rightHip else runPose.leftHip) + kh
			local rk = -(if side == 1 then runPose.rightKnee else runPose.leftKnee) - kk
			local rp = wrap(p + G.RunPhase + (if side == 1 then 0 else 0.5))
			-- (the run's foot: pointed in the push-off and the kick-up, level landing)
			local rel = -rad(22) * max(0, sin(TAU * (rp - 0.3))) + rad(6) * max(0, cos(TAU * (rp - 0.08)))
			c, hp, k = lerp(c, 0, run), lerp(hp, rh, run), lerp(k, rk, run)
			fp = lerp(fp, rh - rk + rel + ka, run)
		end
		local t = s.airW
		if t > 0 then
			local lead = side == 1
			local ah = lerp(lerp(16, if lead then 24 else 4, mv), lerp(35, if lead then 55 else 12, mv), rising)
				+ flail * 22 * sin(clock + side * PI)
			local ak = lerp(lerp(22, if lead then 30 else 14, mv), lerp(62, if lead then 82 else 42, mv), rising)
				+ flail * 25 * sin(clock + side * PI + 1)
			local ch, ck = BodyMotion.crouch(G.TakeoffDrop * F.leg * F.crouch, 0, thigh, shin)
			local spring = if s.jumped then smooth(s.airT / G.TakeoffTime) else 1
			local airH = rad(lerp(math.deg(ch) - 4, ah, spring))
			local airK = rad(lerp(-math.deg(ck) + 4, ak, spring))
			local arel = rad(lerp(-30, lerp(6, -22, rising), spring))
			c, hp, k = lerp(c, 0, t), lerp(hp, airH, t), lerp(k, airK, t)
			fp = lerp(fp, airH - airK + arel, t)
		end
		legC[side], legP[side], legK[side], legA[side] = c, hp, k, fp
	end
end

-- The legs into the pose; the feet flat on the ground: the ankle undoes what the root, the hip and the knee turned,
-- then pitches the foot (on the slope).
local function legsOut(s: State, b: Body, m: { number })
	local r = F.r
	local onGround = 1 - s.airW
	local slopeFoot = math.atan(s.slopeR * F.pfX + s.slopeF * F.pfF) * onGround
	local slopeSide = math.atan(s.slopeR * F.prX + s.slopeF * F.prF) * onGround
	for side = 1, 2 do
		local hj = if side == 1 then Gait.RH else Gait.LH
		-- (the joints turn the bones from where they lean standing)
		local h00, h01, h02, h10, h11, h12, h20, h21, h22 = zx(legC[side], legP[side] - b.thighTilt)
		put(m, hj, 0, 0, 0, h00, h01, h02, h10, h11, h12, h20, h21, h22)
		local k00, k01, k02, k10, k11, k12, k20, k21, k22 = yxz(-legK[side] + b.thighTilt - b.shinTilt, 0, 0)
		put(m, hj + 1, 0, 0, 0, k00, k01, k02, k10, k11, k12, k20, k21, k22)
		local a00, a01, a02, a10, a11, a12, a20, a21, a22 = mul(r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], h00, h01, h02, h10, h11, h12, h20, h21, h22)
		a00, a01, a02, a10, a11, a12, a20, a21, a22 = mul(a00, a01, a02, a10, a11, a12, a20, a21, a22, k00, k01, k02, k10, k11, k12, k20, k21, k22)
		local f00, f01, f02, f10, f11, f12, f20, f21, f22 = yxz(legA[side] + slopeFoot, F.yaw, slopeSide)
		put(m, hj + 2, 0, 0, 0, mul(a00, a10, a20, a01, a11, a21, a02, a12, a22, f00, f01, f02, f10, f11, f12, f20, f21, f22))
	end
end

-- The waist (the chest over the hips: back to the front, all of it aiming; against the hips' swing; leaning into the
-- walk, the speed gained and the slope; the free side's drop taken out; the run's; tired, hunched) and the arms
-- (against the legs, the elbows bending more forward; the run's pump), then the air, the landing and the catch.
local function upper(s: State, i: Input)
	local run, n, amp, tired = F.run, F.n, F.amp, F.tired
	local spent = s.spentW * (1 - run)
	F.spent = spent
	local follows = (1 - s.aim) * G.ChestFollow
	F.waistYaw = lerp(F.yaw * (follows - 1) - F.chestTurn - F.hipTurn, runPose.twist, run)
	F.waistPitch = lerp(-rad(G.WalkLean) * n * amp, runPose.lean, run) - s.lean * (1 - G.LeanRoot) - F.slopeLean * 0.6
		- rad(G.TiredLean) * tired - rad(5) * spent
	F.waistRoll = -F.roll * 0.6
	local swing = lerp(rad(G.ArmSlow), rad(G.ArmSwing), n) * amp * (1 - (1 - G.SpentArms) * spent)
	local ca = cos(TAU * wrap(F.p - G.ArmLag))
	local elbow0 = lerp(rad(G.ElbowSlow), rad(G.Elbow), n) * amp
	for side = 1, 2 do
		local sgn = if side == 1 then 1 else -1
		local x = -sgn * swing * ca * F.ahead
		local forward = max(0, x) / max(swing, 1e-3)
		armX[side], armY[side], armZ[side] = x, sgn * rad(8) * n * forward, sgn * rad(G.ArmOut)
		armE[side], armW[side], armLift[side] = elbow0 + rad(G.ElbowForward) * n * forward * amp, 0, 0
		if run > 0 then
			local rx = (if side == 1 then runPose.rightShoulder else runPose.leftShoulder) * (1 - G.TiredArms * tired)
			local re = if side == 1 then runPose.rightElbow else runPose.leftElbow
			armX[side] = lerp(armX[side], rx - rad(8) * tired, run)
			armY[side] = lerp(armY[side], sgn * (runPose.inward + rad(14) * tired), run)
			armZ[side] = lerp(armZ[side], sgn * rad(4 + 6 * tired), run)
			armE[side] = lerp(armE[side], re - rad(18) * tired, run)
		end
	end
	-- The air: the arms up and out rising, wide falling, windmilling falling long; the take-off swings them up.
	local airW = s.airW
	if airW > 0 then
		local rising, flail = F.rising, F.flail
		local spring = if s.jumped then smooth(s.airT / G.TakeoffTime) else 1
		for side = 1, 2 do
			local sgn = if side == 1 then 1 else -1
			local x = lerp(rad(12), rad(38), rising) + flail * rad(70) * sin(F.airClock * 1.3 + side * PI)
			local z = sgn * lerp(rad(62), rad(34), rising) * (1 - 0.2 * flail) + sgn * flail * rad(14)
			armTo(side, airW, lerp(rad(-30), x, spring), sgn * rad(6), z, lerp(rad(24), rad(46), rising), 0)
		end
		F.waistPitch = lerp(F.waistPitch, lerp(rad(4), rad(-8), rising) + flail * rad(8) - rad(10) * (1 - spring), airW)
		F.waistYaw = lerp(F.waistYaw, 0, airW)
		F.waistRoll = lerp(F.waistRoll, 0, airW)
	end
	-- The landing: forward over the bent knees, the arms out for the balance.
	local landShare = if s.landDepth > 0 then F.squash / (G.LandMax * F.leg) else 0
	F.landShare = landShare
	if landShare > 0 then
		F.waistPitch -= rad(G.LandLean) * landShare
		for side = 1, 2 do
			local sgn = if side == 1 then 1 else -1
			armTo(side, min(1, landShare * 1.5), rad(30), sgn * rad(4), sgn * rad(24), rad(36), 0)
		end
	end
	-- Catching the breath: bent over, the hands on the knees (the bag's arm hangs).
	if s.catch > 0 then
		F.waistPitch = lerp(F.waistPitch, -rad(30), s.catch)
		armTo(1, s.catch, rad(34), 0, -rad(16), rad(8), 0)
		if i.hands == "bag" then
			armTo(2, s.catch, rad(14), 0, -rad(BA.Out), rad(6), 0)
		else
			armTo(2, s.catch, rad(34), 0, rad(16), rad(8), 0)
		end
	end
end

-- The fidgets (their joints by their weight), the gun held low and ready (the right arm; a little of the swing), the
-- bag's arm out and straighter.
local function holds(s: State)
	local fidget, fw, ft = F.fidget, F.fw, F.ft
	F.neckYawF, F.neckPitchF, F.neckRollF, F.waistW, F.armWR, F.armWL, F.wristR = 0, 0, 0, 0, 0, 0, 0
	if fidget and fw > 0 then
		if fidget == "look" then
			local look = rad(46) * (key(ft, 0.25, 0.9, 1.25, 1.65) - key(ft, 1.45, 1.9, 2.5, 3.0))
			F.neckYawF, F.neckPitchF = look * 0.75, rad(4)
			F.waistYaw = lerp(F.waistYaw, look * 0.25, fw)
			F.waistW = fw
		elseif fidget == "stretch" then
			local up = key(ft, 0.2, 0.9, 1.9, 2.6)
			armTo(1, fw, rad(28 + 140 * up), rad(10), rad(6 + 14 * up), rad(70 - 45 * up), 0)
			armTo(2, fw, rad(28 + 140 * up), -rad(10), -rad(6 + 14 * up), rad(70 - 45 * up), 0)
			F.waistPitch = lerp(F.waistPitch, rad(9) * up, fw)
			F.neckPitchF = rad(12) * up
			F.waistW, F.armWR, F.armWL = fw, fw, fw
		elseif fidget == "watch" then
			local up = key(ft, 0.15, 0.6, 1.5, 2.1)
			armTo(2, fw, rad(10 + 44 * up), -rad(44) * up, -rad(4), rad(10 + 95 * up), 0)
			F.neckPitchF, F.neckYawF = -rad(26) * up, rad(14) * up
			F.armWL = fw
		elseif fidget == "shoulders" then
			local shrug = sin(PI * clamp((ft - 0.2) / 0.7, 0, 1))
			armLift[1], armLift[2] = 0.07 * F.leg / 2 * shrug, 0.07 * F.leg / 2 * shrug
			F.neckRollF = rad(14) * sin(TAU * clamp((ft - 0.9) / 1.3, 0, 1))
			F.armWR, F.armWL = fw, fw
		elseif fidget == "checkgun" then
			local up = key(ft, 0.2, 0.7, 1.7, 2.3)
			armTo(1, fw, rad(24 + 26 * up), rad(8 + 26 * up), 0, rad(62 + 34 * up), rad(-14 + 10 * up))
			F.wristR = rad(40) * sin(TAU * clamp((ft - 0.7) / 1.0, 0, 1)) * up
			F.neckPitchF, F.neckYawF = -rad(22) * up, -rad(16) * up
			F.armWR = fw
		elseif fidget == "peek" then
			local up = key(ft, 0.2, 0.6, 1.4, 2.0)
			armTo(2, fw, rad(10 + 16 * up), -rad(6), -rad(BA.Out + 6 * up), rad(10 + 30 * up), 0)
			F.neckPitchF, F.neckYawF = -rad(30) * up, rad(18) * up
			F.waistPitch = lerp(F.waistPitch, -rad(7) * up, fw)
			F.waistYaw = lerp(F.waistYaw, rad(8) * up, fw)
			F.waistW, F.armWL = fw, fw
		elseif fidget == "hoist" then
			F.waistPitch = lerp(F.waistPitch, rad(5) * sin(PI * clamp(ft / 1.1, 0, 1)), fw)
			F.waistW = fw
		end
	end
	local amp = F.amp
	if s.gun > 0 then
		local hg = G.GunHold
		local t = s.gun / max(amp, s.gun, 1e-3)
		armTo(1, t * (1 - (if fidget == "checkgun" then fw else 0)), rad(hg[1]) + armX[1] * G.GunSwing, rad(hg[2]), rad(hg[3]), rad(hg[4]), rad(hg[5]))
	end
	if s.bag > 0 and s.catch <= 0 and not (fidget == "peek" and fw > 0) then
		armTo(2, s.bag / max(amp, s.bag, 1e-3), armX[2] * (1 - BA.SwingCut), 0, -rad(BA.Out), armE[2] * (1 - BA.Straight), 0)
	end
end

-- The arms, the waist and the head into the pose (the head level and to the front over everything under it, HeadKeep
-- of it; tired a little down; a fidget's look), and how far each joint is laid over the animation: the legs and the
-- body while walking, in the air, landing, catching the breath (a fidget's own joints by its weight); the gun's arm
-- while out; the wrists only for the gun.
local function upperOut(s: State, m: { number }, w: { number })
	for side = 1, 2 do
		local sj = if side == 1 then Gait.RS else Gait.LS
		put(m, sj, 0, armLift[side], 0, yxz(armX[side], armY[side], armZ[side]))
		put(m, sj + 1, 0, 0, 0, yxz(armE[side], 0, 0))
		put(m, sj + 2, 0, 0, 0, yxz(armW[side], if side == 1 then F.wristR else 0, 0))
	end
	put(m, Gait.WAIST, 0, 0, 0, yxz(F.waistPitch, F.waistYaw, F.waistRoll))
	local keep, fw = G.HeadKeep, F.fw
	local neckPitch = -(F.leanP + F.rootPitch + F.waistPitch) * keep * (1 - 0.45 * s.catch) - rad(G.TiredHead) * F.tired
		- rad(G.SpentHead) * F.spent + F.neckPitchF * fw - rad(8) * F.landShare
	local neckYaw = -(F.rootYaw + F.waistYaw) * keep + F.neckYawF * fw
	local neckRoll = -(F.leanR + F.rootRoll + F.waistRoll) * keep * 0.8 + F.neckRollF * fw
	put(m, Gait.NECK, 0, 0, 0, yxz(neckPitch, neckYaw, neckRoll))
	local fidget = F.fidget
	local body = max(s.hold, s.airW, s.landW, s.catch, if fidget == "hoist" then fw else 0)
	for j = Gait.ROOT, Gait.LA do
		w[j] = body
	end
	w[Gait.WAIST] = max(body, F.waistW)
	w[Gait.NECK] = max(body, if fidget then fw else 0)
	local armsBody = max(s.hold, s.airW, min(1, F.landShare * 1.5), s.catch)
	w[Gait.RS] = max(armsBody, s.gun, F.armWR)
	w[Gait.RE] = w[Gait.RS]
	w[Gait.RW] = max(s.gun, if fidget == "checkgun" then fw else 0)
	w[Gait.LS] = max(armsBody, F.armWL)
	w[Gait.LE] = w[Gait.LS]
	w[Gait.LW] = 0
end

function Gait.step(s: State, i: Input, b: Body, out: Pose)
	local dt = clamp(i.dt, 0, MAX_DT)
	F.dt, F.leg = dt, b.leg
	breathe(s, i, dt)
	fly(s, i, dt)
	move(s, i, b, dt)
	stand(s, i, dt)
	leanInto(s, i, dt)
	hips(s, i, b, dt)
	dip(s, b, dt)
	rootOut(s, i, b, out.m)
	legsAim(s, i, b)
	legsOut(s, b, out.m)
	upper(s, i)
	holds(s)
	upperOut(s, out.m, out.w)
end

-- How much the walk's own move is on (0 standing … 1 walking or running).
function Gait.moving(s: State): number
	return s.amp
end

-- The sprint's run cycle's share now (0 … 1).
function Gait.running(s: State): number
	return Gait.runShare(s.speed) * s.amp
end

return Gait
