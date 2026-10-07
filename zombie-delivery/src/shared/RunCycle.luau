--!strict
-- 6.0.1: the courier's sprint as numbers (pure Luau: client/SprintPose.luau sets them ABSOLUTE into the R15 joints'
-- Transform, the rest pose times these rotations, over the stock run animation; tests/runcycle_test.luau checks them).
-- One cycle is two steps: `phase` 0..1 is the right leg's, the left leg is half a cycle behind and each arm swings
-- against its own side's leg. SprintPose advances the phase by the distance run (Config.Courier.Sprint.Stride studs a
-- cycle), so the cadence follows the speed.
--   phase 0     the right thigh fully forward (HipForward), the knee almost straight, reaching for the ground
--   phase 0.25  the right foot under the body: the knee loaded, the body at its lowest
--   phase 0.42  the push off: the right thigh behind (toward HipBack), the knee nearly straight
--   phase 0.68  the right heel kicked up high under the seat (the knee ~110), the thigh coming through
--   the left leg does the same half a cycle later; the body is highest between two steps (the flight, 0.5 and 0)
-- The joints' own frames (as shared/RiderPose.luau): about X a positive angle swings a thigh or an upper arm forward
-- and bends an elbow; a knee bends with a NEGATIVE X (the shin back); a negative waist X tips the upper body forward.
-- About Y a positive angle turns a part to the left (seen from above). Angles in radians, the Root bob in studs.
-- `effort` 0..1 (the speed between Sprint.From and Sprint.Full) scales the swing (from Calm of it) and the lean.

local RunCycle = {}

local TAU = 2 * math.pi
local rad = math.rad

RunCycle.HipForward = rad(55) -- the thigh's swing forward …
RunCycle.HipBack = rad(35) -- … and back
RunCycle.ArmSwing = rad(60) -- the upper arms forward / back, against the legs
RunCycle.Elbow = rad(92) -- the elbows bent about square …
RunCycle.ElbowBack = rad(10) -- … this much more on the back swing (less in front)
RunCycle.Inward = rad(10) -- the arms swing a little across the body in front
RunCycle.Lean = rad(14) -- the upper body forward (the waist) at a full sprint
RunCycle.Twist = rad(6) -- the upper body turns against the hips with the arms …
RunCycle.HipTwist = rad(4) -- … and the hips (the Root) with the legs
RunCycle.HeadKeep = 0.85 -- the neck takes back this share of the lean and the turn: the head stays level
RunCycle.Bob = 0.15 -- studs: the body rises and falls this much twice a cycle …
RunCycle.Sink = 0.06 -- … from this far under the rest height (the loaded knee at the lowest)
RunCycle.Calm = 0.75 -- the swing's share at the start of a sprint (effort 0)
RunCycle.CalmLean = 0.5 -- the lean's share at the start of a sprint

-- The knee's bend through the right leg's cycle (phase, degrees bent): a cycle, read with a smooth curve through them.
local KNEE: { { number } } = {
	{ 0.00, 10 }, -- the leg reaching forward, nearly straight
	{ 0.10, 20 }, -- the foot lands
	{ 0.25, 32 }, -- the body over the foot: the knee loaded
	{ 0.42, 16 }, -- the push off
	{ 0.55, 50 }, -- the foot leaves the ground behind
	{ 0.68, 110 }, -- the heel kicked up high
	{ 0.80, 88 }, -- the thigh comes through
	{ 0.92, 40 }, -- the shin swings out forward
}

local function wrap(p: number): number
	return p - math.floor(p)
end

-- Key `k` of a cycle of `n` keys, `k` may run past either end (the cycle goes on): its phase (shifted by the laps) and
-- value.
local function key(keys: { { number } }, n: number, k: number): (number, number)
	local lap = math.floor((k - 1) / n)
	local entry = keys[k - lap * n]
	return entry[1] + lap, entry[2]
end

-- A cyclic curve through `keys` (the first at phase 0; Hermite with the tangents from the neighbours: Catmull-Rom on
-- uneven spacing, so it is smooth through every key).
local function sample(keys: { { number } }, p: number): number
	local n = #keys
	p = wrap(p)
	local i = 1
	for k = 2, n do
		if keys[k][1] <= p then
			i = k
		end
	end
	local t0, v0 = key(keys, n, i - 1)
	local t1, v1 = key(keys, n, i)
	local t2, v2 = key(keys, n, i + 1)
	local t3, v3 = key(keys, n, i + 2)
	local span = t2 - t1
	local s = (p - t1) / span
	local m1 = (v2 - v0) / (t2 - t0) * span
	local m2 = (v3 - v1) / (t3 - t1) * span
	local s2, s3 = s * s, s * s * s
	return (2 * s3 - 3 * s2 + 1) * v1 + (s3 - 2 * s2 + s) * m1 + (-2 * s3 + 3 * s2) * v2 + (s3 - s2) * m2
end

-- The thigh's swing (radians, + forward) at the leg's `phase`.
function RunCycle.hip(phase: number): number
	local mid = (RunCycle.HipForward - RunCycle.HipBack) / 2
	local amp = (RunCycle.HipForward + RunCycle.HipBack) / 2
	return mid + amp * math.cos(TAU * phase)
end

-- The knee's bend (radians, positive = bent; the joint takes it as a negative X) at the leg's `phase`.
function RunCycle.knee(phase: number): number
	return rad(sample(KNEE, phase))
end

-- The phase after running `distance` studs with `stride` studs a cycle.
function RunCycle.advance(phase: number, distance: number, stride: number): number
	return wrap(phase + distance / math.max(stride, 0.1))
end

-- The sprint's share 0..1 between `from` and `full` studs / s.
function RunCycle.effort(speed: number, from: number, full: number): number
	return math.clamp((speed - from) / math.max(full - from, 0.1), 0, 1)
end

export type Pose = {
	rightHip: number, -- X
	leftHip: number,
	rightKnee: number, -- X (negative: bent)
	leftKnee: number,
	rightShoulder: number, -- X
	leftShoulder: number,
	rightElbow: number, -- X (positive: bent)
	leftElbow: number,
	inward: number, -- the shoulders' Y (the right arm +, the left arm −), applied before their X
	lean: number, -- the waist's X (negative: forward) …
	twist: number, -- … then its Y
	neckPitch: number, -- the neck's Y first, then its X: the waist undone (HeadKeep of it)
	neckTurn: number,
	hipTurn: number, -- the Root's Y
	bob: number, -- the Root's Y position (studs)
}

function RunCycle.blank(): Pose
	return {
		rightHip = 0, leftHip = 0, rightKnee = 0, leftKnee = 0, rightShoulder = 0, leftShoulder = 0, rightElbow = 0,
		leftElbow = 0, inward = 0, lean = 0, twist = 0, neckPitch = 0, neckTurn = 0, hipTurn = 0, bob = 0,
	}
end

-- The pose at `phase` with `effort` (0..1); written into `out` when given (no new table every frame).
function RunCycle.pose(phase: number, effort: number, out: Pose?): Pose
	local pose = out or RunCycle.blank()
	local e = math.clamp(effort, 0, 1)
	local swing = RunCycle.Calm + (1 - RunCycle.Calm) * e
	local p = wrap(phase)
	local q = wrap(p + 0.5)
	pose.rightHip = RunCycle.hip(p) * swing
	pose.leftHip = RunCycle.hip(q) * swing
	pose.rightKnee = -RunCycle.knee(p) * swing
	pose.leftKnee = -RunCycle.knee(q) * swing
	-- The arms against the legs: the right arm back while the right thigh is forward.
	local c = math.cos(TAU * p)
	pose.rightShoulder = -RunCycle.ArmSwing * c * swing
	pose.leftShoulder = RunCycle.ArmSwing * c * swing
	pose.rightElbow = RunCycle.Elbow + RunCycle.ElbowBack * c
	pose.leftElbow = RunCycle.Elbow - RunCycle.ElbowBack * c
	pose.inward = RunCycle.Inward
	-- The body: the hips turn with the forward thigh, the shoulders against them, the head kept level.
	local lean = -RunCycle.Lean * (RunCycle.CalmLean + (1 - RunCycle.CalmLean) * e)
	local hipTurn = RunCycle.HipTwist * c * swing
	local twist = -RunCycle.Twist * c * swing
	pose.lean = lean
	pose.twist = twist
	pose.hipTurn = hipTurn
	pose.neckTurn = -(hipTurn + twist) * RunCycle.HeadKeep
	pose.neckPitch = -lean * RunCycle.HeadKeep
	-- Lowest with a foot under the body (phase 0.25 and 0.75), highest in the flight between.
	pose.bob = RunCycle.Bob * 0.5 * (1 - math.cos(2 * TAU * (p - 0.25))) - RunCycle.Sink
	return pose
end

return RunCycle
