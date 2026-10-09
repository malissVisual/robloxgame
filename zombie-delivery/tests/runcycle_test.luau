-- Logic test of the 6.0.1 sprint (shared/RunCycle.luau, Config.Courier.Sprint) in the standalone Luau CLI: the cycle
-- is symmetric (the left leg is the right one half a cycle later, the arms against the legs), continuous (no jump
-- anywhere, through the end of the cycle too), its angles stay in range (the hips +55 / −35, the knees 10 at the front
-- to ~110 kicked up and never straight back, the elbows about square), the body bobs twice a cycle and the phase
-- follows the distance run.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local RunCycle = require("./RunCycle")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function deg(x: number): number
	return math.deg(x)
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local S = Config.Courier.Sprint
check("the sprint's numbers", S.From > Config.Movement.Walk and S.Full > S.From and S.Full <= Config.Movement.Sprint
	and S.Off < S.From and S.Off >= 18 and S.Stride > 4 and S.Stride < 16 and S.Hang >= 0 and S.Hang < 0.9 and S.BlendTime > 0 and S.BlendTime < 0.5
	and S.Range >= 100)

-- The full sprint, sampled finely.
local STEPS = 720
local poses = {}
for i = 0, STEPS do
	poses[i] = RunCycle.pose(i / STEPS, 1)
end

-- In range.
local hipMax, hipMin, kneeMax, kneeMin, elbowMax, elbowMin, armMax, bobMax, bobMin = -99, 99, -99, 99, -99, 99, 0, -99, 99
for i = 0, STEPS do
	local p = poses[i]
	for _, hip in { p.rightHip, p.leftHip } do
		hipMax, hipMin = math.max(hipMax, deg(hip)), math.min(hipMin, deg(hip))
	end
	for _, knee in { p.rightKnee, p.leftKnee } do
		kneeMax, kneeMin = math.max(kneeMax, -deg(knee)), math.min(kneeMin, -deg(knee))
	end
	for _, elbow in { p.rightElbow, p.leftElbow } do
		elbowMax, elbowMin = math.max(elbowMax, deg(elbow)), math.min(elbowMin, deg(elbow))
	end
	armMax = math.max(armMax, math.abs(deg(p.rightShoulder)), math.abs(deg(p.leftShoulder)))
	bobMax, bobMin = math.max(bobMax, p.bob), math.min(bobMin, p.bob)
end
check("the hips swing +66 forward (6.12.6: the slow-mo reach)", near(hipMax, 66, 0.01), hipMax)
check("the hips swing -42 back", near(hipMin, -42, 0.01), hipMin)
check("the knees never bend backward (always bent a little)", kneeMin >= 5, kneeMin)
check("the knees kick up to about 110 and no further", kneeMax >= 105 and kneeMax <= 116, kneeMax)
check("the knee is nearly straight reaching forward", near(-deg(poses[0].rightKnee), 10, 0.01), -deg(poses[0].rightKnee))
check("the elbows stay about square", elbowMin >= 75 and elbowMax <= 105, `{elbowMin}..{elbowMax}`)
check("the elbows bend more on the back swing", poses[0].rightElbow > poses[STEPS / 2].rightElbow and poses[0].rightShoulder < 0)
check("the arms swing +-76", near(armMax, 76, 0.01), armMax)
check("the lean forward at a full sprint is 16", near(deg(poses[0].lean), -16, 1e-6), deg(poses[0].lean))
check("the head kept about level", math.abs(deg(poses[0].lean + poses[0].neckPitch)) < 3)
check("the body bobs 0.32 studs", near(bobMax - bobMin, 0.32, 1e-3) and bobMin < 0, `{bobMin}..{bobMax}`)
local twistMax = 0
for i = 0, STEPS do
	twistMax = math.max(twistMax, math.abs(deg(poses[i].twist)))
end
check("the waist turns +-7 against the hips", near(twistMax, 7, 0.01), twistMax)

-- Symmetric: the left side is the right side half a cycle later; the arms against the legs.
local symmetric, opposite = true, true
for i = 0, STEPS / 2 do
	local a, b = poses[i], poses[i + STEPS / 2]
	symmetric = symmetric and near(a.rightHip, b.leftHip) and near(a.rightKnee, b.leftKnee)
		and near(a.rightShoulder, b.leftShoulder) and near(a.rightElbow, b.leftElbow) and near(a.bob, b.bob)
		and near(a.twist, -b.twist) and near(a.hipTurn, -b.hipTurn)
	-- The right arm goes back while the right thigh goes forward (and the left arm forward).
	local hipMid = (RunCycle.HipForward - RunCycle.HipBack) / 2
	local forward = a.rightHip - hipMid
	opposite = opposite and (math.abs(forward) < 1e-3 or (forward > 0) == (a.rightShoulder < 0))
		and near(a.rightShoulder, -a.leftShoulder)
end
check("left = right half a cycle later", symmetric)
check("the arms swing against the legs", opposite)
check("the hips turn with the forward thigh, the shoulders against them", poses[0].hipTurn > 0 and poses[0].twist < 0)

-- Continuous: small steps everywhere, and the end of the cycle meets its start.
local worst, worstBob = 0, 0
for i = 1, STEPS do
	local a, b = poses[i - 1], poses[i]
	for _, field in { "rightHip", "leftHip", "rightKnee", "leftKnee", "rightShoulder", "leftShoulder", "rightElbow", "leftElbow", "lean", "twist", "neckPitch", "neckTurn", "hipTurn" } do
		worst = math.max(worst, math.abs(deg((b :: any)[field] - (a :: any)[field])))
	end
	worstBob = math.max(worstBob, math.abs(b.bob - a.bob))
end
check("no jumps within the cycle (under 2 degrees per 1/720)", worst < 2, worst)
check("the bob moves smoothly", worstBob < 0.005, worstBob)
local first, last = RunCycle.pose(0, 1), RunCycle.pose(1 - 1e-9, 1)
check("the cycle closes", near(first.rightKnee, last.rightKnee, 1e-5) and near(first.leftKnee, last.leftKnee, 1e-5) and near(first.rightHip, last.rightHip, 1e-5))
-- The knee curve is smooth through its keys too (no corner: the slope on both sides agrees).
local corner = 0
for i = 1, STEPS - 1 do
	local a, b, c = RunCycle.knee((i - 1) / STEPS), RunCycle.knee(i / STEPS), RunCycle.knee((i + 1) / STEPS)
	corner = math.max(corner, math.abs(deg((c - b) - (b - a))))
end
check("the knee curve has no corners", corner < 0.3, corner)

-- The phase follows the distance: one cycle per Stride studs.
local phase = 0
for _ = 1, 100 do
	phase = RunCycle.advance(phase, S.Stride / 100, S.Stride)
end
check("one stride of distance is one cycle", near(phase, 0, 1e-6) or near(phase, 1, 1e-6), phase)
check("half a stride is half a cycle", near(RunCycle.advance(0.75, S.Stride / 2, S.Stride), 0.25, 1e-9))
check("the effort runs 0..1 over From..Full", RunCycle.effort(S.From, S.From, S.Full) == 0 and RunCycle.effort(S.Full + 5, S.From, S.Full) == 1
	and RunCycle.effort((S.From + S.Full) / 2, S.From, S.Full) > 0.4)

-- A calm sprint swings less and leans less; the given table is reused.
local out = RunCycle.blank()
local calm = RunCycle.pose(0, 0, out)
check("the pose is written into the given table", calm == out)
check("a calm sprint swings less", calm.rightHip < poses[0].rightHip and calm.rightHip > 0 and math.abs(calm.lean) < math.abs(poses[0].lean))

-- 6.12.6, the slow-mo hang: the flights keep their place, the phase never runs back, it is slow in the air and quick
-- through the steps, and one cycle is still one.
do
	local k = S.Hang
	check("the hang keeps the flights and the steps in place", near(RunCycle.hang(0, k), 0, 1e-9) and near(RunCycle.hang(0.5, k), 0.5, 1e-9)
		and near(RunCycle.hang(0.25, k), 0.25, 1e-9) and near(RunCycle.hang(0.75, k), 0.75, 1e-9))
	local back, last = false, RunCycle.hang(0, k)
	for i = 1, 720 do
		local h = RunCycle.hang(i / 720, k)
		local step = h - last
		if step < 0 then
			step += 1
		end
		if step <= 0 or step > 0.01 then
			back = true
		end
		last = h
	end
	check("the hung phase always moves on", not back)
	local d = 1e-4
	local air = RunCycle.hang(d, k) - RunCycle.hang(0, k)
	local step = RunCycle.hang(0.25 + d, k) - RunCycle.hang(0.25, k)
	check("slow in the flight, quick through the step", near(air / d, 1 - k, 1e-3) and near(step / d, 1 + k, 1e-3), `{air / d} / {step / d}`)
	check("no hang at 0", near(RunCycle.hang(0.3, 0), 0.3, 1e-12))
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
