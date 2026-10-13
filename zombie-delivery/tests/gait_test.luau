-- Logic test of 6.24's gait (shared/Gait.luau, Config.Gait) in the standalone Luau CLI, driven as client/GaitPose.luau
-- drives it (60 steps a second) and looked at through forward kinematics on server/CharacterArt's block body (the
-- classic R15's proportions and joints): the cadence rises with the speed and the stride with the leg; the phase follows
-- the distance; the walk / run shares and the duty blend smoothly; the leg reaches its point; a planted foot does not
-- slide at any walking speed or way (backwards, sideways, aslant) and never sinks into the ground; the feet do not cross;
-- the landing squashes more from higher, never past client/Unstuck.luau's 0.8 studs; starting and stopping blend with
-- no snap and the body settles back to the animation; the hips turn to the way and the chest back to the aim; the tired
-- sprint pumps less and leans more; the lean into a turn; fidgets only standing still near the camera (none with
-- Reduced Motion), fitting the hands; catching the breath when spent; the holds' weights; no NaN, no table per step.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Gait = require("./Gait")
local Geometry = require("./CharacterGeometry")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local G = Config.Gait
local S = Config.Courier.Sprint
local B = Gait.Classic
local DT = 1 / 60
local rad, deg = math.rad, math.deg

-- ── Forward kinematics on the block body ─────────────────────────────────────────────────────────────────────────────

local spec = Geometry.spec("walker")
local centers, sizes = {}, {}
for _, bone in spec.bones do
	centers[bone.name], sizes[bone.name] = bone.at, bone.size
end
local slotOf = {}
for j, name in Gait.Names do
	slotOf[name] = j
end
local function mul(a, b)
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7], a[1] * b[2] + a[2] * b[5] + a[3] * b[8], a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7], a[4] * b[2] + a[5] * b[5] + a[6] * b[8], a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7], a[7] * b[2] + a[8] * b[5] + a[9] * b[8], a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
		a[1] * b[10] + a[2] * b[11] + a[3] * b[12] + a[10], a[4] * b[10] + a[5] * b[11] + a[6] * b[12] + a[11],
		a[7] * b[10] + a[8] * b[11] + a[9] * b[12] + a[12],
	}
end
local function tr(x, y, z)
	return { 1, 0, 0, 0, 1, 0, 0, 0, 1, x, y, z }
end
local function point(f, x, y, z)
	return f[1] * x + f[2] * y + f[3] * z + f[10], f[4] * x + f[5] * y + f[6] * z + f[11], f[7] * x + f[8] * y + f[9] * z + f[12]
end
-- Every part's world frame with the root at (x, y, z), each joint at the pose's full value.
local function frames(pose, x, y, z)
	local out = { HumanoidRootPart = tr(x, y, z) }
	for _, joint in spec.joints do
		local cp, cc, at = centers[joint.parent], centers[joint.child], joint.at
		local o = (slotOf[joint.name] - 1) * 12
		local m = pose.m
		local t = { m[o + 4], m[o + 5], m[o + 6], m[o + 7], m[o + 8], m[o + 9], m[o + 10], m[o + 11], m[o + 12], m[o + 1], m[o + 2], m[o + 3] }
		out[joint.child] = mul(mul(mul(out[joint.parent], tr(at[1] - cp[1], at[2] - cp[2], at[3] - cp[3])), t), tr(cc[1] - at[1], cc[2] - at[2], cc[3] - at[3]))
	end
	return out
end
local GROUND = -2.97 -- the block body's soles standing (its root at 0)
local FOOT = sizes.RightFoot
-- A foot's heel and toe on the sole (world).
local function sole(f)
	local hx, hy, hz = point(f, 0, -FOOT[2] / 2, FOOT[3] / 2)
	local tx, ty, tz = point(f, 0, -FOOT[2] / 2, -FOOT[3] / 2)
	return hx, hy, hz, tx, ty, tz
end

local function finite(pose): boolean
	for _, v in pose.m do
		if v ~= v or v == math.huge or v == -math.huge then
			return false
		end
	end
	for _, v in pose.w do
		if v ~= v or v < 0 or v > 1 then
			return false
		end
	end
	return true
end
-- The angle (degrees) between two joint rotations of two poses.
local function turnBetween(m1, m2, j): number
	local o = (j - 1) * 12
	local tr3 = 0
	for r = 0, 2 do
		for c = 0, 2 do
			tr3 += m1[o + 4 + r * 3 + c] * m2[o + 4 + r * 3 + c]
		end
	end
	return deg(math.acos(math.clamp((tr3 - 1) / 2, -1, 1)))
end

-- ── The numbers ──────────────────────────────────────────────────────────────────────────────────────────────────────

check("the gait's numbers", G.StopBelow < G.MoveFrom and G.DutyBrisk < G.DutySlow and G.DutyBrisk >= 0.5
	and G.RunFrom > Config.Movement.Walk and G.RunFrom < S.From and G.Detail <= G.Range and G.MaxPosed >= 1
	and G.Reach < 1 and G.MaxDrop > 0 and G.LandMin < G.LandMax and G.LandFrom < G.LandFull and G.FarHz >= 10
	and G.IdleAfter > 0 and G.FidgetEvery > 0 and G.TiredFrom > 0 and G.CatchUntil > 0.2)
check("the deepest squash and the floor stay over client/Unstuck.luau's 0.8 studs", G.LandMax * B.leg < G.Lowest and G.Lowest < 0.8,
	G.LandMax * B.leg)
check("the classic body: the leg 2 studs, the root joint 2.22 over the soles", math.abs(B.leg - 2) < 0.05 and math.abs(B.ground - 2.22) < 0.01, `{B.leg} {B.ground}`)

-- ── Cadence, stride, phase, shares ───────────────────────────────────────────────────────────────────────────────────

local lastStride, lastCadence = 0, 0
local rising = true
for v = 1, 14 do
	local stride = Gait.stride(v, B.leg)
	local cadence = v / stride
	rising = rising and stride > lastStride and cadence > lastCadence
	lastStride, lastCadence = stride, cadence
end
check("the stride and the cadence both grow with the speed", rising)
local c35, c14 = 3.5 / Gait.stride(3.5, B.leg), 14 / Gait.stride(14, B.leg)
check("a careful aim step at 3.5: 1.3 to 2 cycles a second", c35 > 1.3 and c35 < 2, c35)
check("the brisk walk at 14: 2 to 2.8 cycles a second (4 to 5.6 steps)", c14 > 2 and c14 < 2.8, c14)
local kid = Gait.body(0.71, 0.58, 0.22, 0.45, 0.45, 0.37, 0.15)
check("shorter legs step quicker at the same speed", 5 / Gait.stride(5, kid.leg) > 5 / Gait.stride(5, B.leg))
local runPrev, dutyPrev, smoothRun = -1, 2, true
for k = 0, 400 do
	local v = k * 0.1
	local r, d = Gait.runShare(v), Gait.duty(v)
	smoothRun = smoothRun and r >= runPrev - 1e-9 and d <= dutyPrev + 1e-9 and (runPrev < 0 or math.abs(r - runPrev) < 0.05)
	runPrev, dutyPrev = r, d
end
check("the run's share and the duty change smoothly and one way with the speed", smoothRun)
check("the walk alone up to RunFrom, the run all from the sprint's From", Gait.runShare(Config.Movement.Walk) == 0
	and Gait.runShare(G.RunFrom) == 0 and Gait.runShare(S.From) == 1 and Gait.runShare(28) == 1)

-- The phase follows the distance.
do
	local s, i, pose = Gait.new(0.3), Gait.input(), Gait.pose()
	local turns, last = 0, s.phase
	local start = 0
	for f = 1, 600 do
		i.dt, i.vx, i.vz = DT, 0, -8
		Gait.step(s, i, B, pose)
		if s.phase < last then
			turns += 1
		end
		last = s.phase
		if f == 120 then
			start = turns + s.phase
		end
	end
	local cycles = turns + s.phase - start
	local expected = 8 * 480 * DT / Gait.stride(8, B.leg)
	check("the phase moves a cycle every stride walked", math.abs(cycles - expected) < 0.02, `{cycles} vs {expected}`)
end

-- ── The pieces ───────────────────────────────────────────────────────────────────────────────────────────────────────

-- The leg reaches its point: the thigh and the shin end there (the hips' frame, -Z ahead).
local reachOk, softOk = true, true
for k = 1, 60 do
	local dx, dy, dz = math.sin(k) * 0.3, -0.9 - 0.3 * math.cos(k * 1.7), math.cos(k * 0.9) * 0.7
	local roll, swing, bend = Gait.reach(dx, dy, dz, B.thigh, B.shin)
	-- the thigh: down turned by Rz(roll)·Rx(swing); the shin `bend` back from it in the same plane
	local function dir(pitch)
		local x, y, z = 0, -math.cos(pitch), -math.sin(pitch)
		return x * math.cos(roll) - y * math.sin(roll), x * math.sin(roll) + y * math.cos(roll), z
	end
	local ax, ay, az = dir(swing)
	local bx, by, bz = dir(swing - bend)
	local ex, ey, ez = ax * B.thigh + bx * B.shin, ay * B.thigh + by * B.shin, az * B.thigh + bz * B.shin
	if math.sqrt((ex - dx) ^ 2 + (ey - dy) ^ 2 + (ez - dz) ^ 2) > 1e-4 then
		reachOk = false
	end
	if bend <= 0 then
		softOk = false
	end
end
local _, _, straight = Gait.reach(0, -(B.thigh + B.shin), 0, B.thigh, B.shin)
check("the leg reaches its point (two bones, the knee forward)", reachOk)
check("the knee never quite straightens (Reach)", softOk and straight > rad(5), deg(straight))
local _, farSwing, farBend = Gait.reach(0, -0.5, -3, B.thigh, B.shin)
check("a point out of reach: the leg goes straight-ish toward it", farBend < rad(25) and farSwing > rad(60), `{deg(farSwing)} {deg(farBend)}`)

-- The rocker: the pivot stays where the flat foot touched (the heel rolling, the toe pushing off).
local pivotOk = true
for _, pitch in { rad(-35), rad(-10), rad(5), rad(18) } do
	local dA, dU = Gait.rocker(pitch, B)
	local px, py = if pitch >= 0 then -B.heel else B.toe, -B.ankle
	-- the pivot seen from the pitched ankle: the flat offset turned by the pitch
	local c, s = math.cos(pitch), math.sin(pitch)
	local wx, wy = dA + px * c - py * s, (B.ankle + dU) + px * s + py * c
	if math.abs(wx - px) > 1e-6 or math.abs(wy - (B.ankle + py)) > 1e-6 then
		pivotOk = false
	end
end
check("the rolling foot turns about its heel or its toe (the pivot stays put)", pivotOk)
check("the ankle rises as the heel lifts", select(2, Gait.rocker(rad(-30), B)) > 0.2)

-- The landing.
local depthPrev, depthOk = -1, true
for h = 0, 60 do
	local d = Gait.landDepth(h)
	depthOk = depthOk and d >= depthPrev - 1e-9 and d <= G.LandMax + 1e-9
	depthPrev = d
end
check("the squash grows with the height fallen, at most LandMax", depthOk)
check("a kerb's half stud is no landing to speak of", Gait.landDepth(0.5) < 0.02 and Gait.landDepth(0) == 0)
local down, up = Gait.landTimes(6.4)
local down2, up2 = Gait.landTimes(30)
check("a higher fall takes longer to come back up from", up2 > up and down2 >= down)
check("the squash's curve: 0 at the touch, all of it at the bottom, 0 when done", Gait.land(0, down, up) == 0
	and math.abs(Gait.land(down, down, up) - 1) < 1e-6 and Gait.land(down + up, down, up) == 0 and Gait.land(down + up * 0.5, down, up) > 0.2)

-- The fidgets.
local fits = true
for _, hands in { "free", "bag", "gun", "carry" } do
	for n = 0, 12 do
		local kind = Gait.fidgetOf(hands, 0.37, n, nil)
		local list = Gait.fidgetsFor(hands) :: { string }
		if not kind or not table.find(list, kind) or not G.Fidgets[kind] then
			fits = false
		end
	end
end
check("each fidget fits the hands (and has its seconds)", fits and Gait.fidgetOf("busy", 0.2, 1, nil) == nil
	and Gait.fidgetOf("gun", 0.37, 3, "x") ~= "stretch" and Gait.fidgetOf("carry", 0.5, 2, nil) ~= "stretch")
local again = true
for n = 0, 20 do
	local a = Gait.fidgetOf("free", 0.61, n, nil)
	if Gait.fidgetOf("free", 0.61, n, a) == a then
		again = false
	end
end
check("never the same fidget twice in a row", again)

-- ── The walk through the body ────────────────────────────────────────────────────────────────────────────────────────

-- A walk at `speed` along `way` (radians from the front, + right): contact, slide (studs a stud walked), the deepest
-- the soles go under the ground, the Root joint's lowest, the feet's crossing.
local function walk(speed: number, way: number, setup: ((any) -> ())?)
	local s, i, pose = Gait.new(0.37), Gait.input(), Gait.pose()
	local x, z = 0, 0
	local contact, frames2, slide, sink, rootLow, crossed = 0, 0, 0, 0, 0, false
	local last = { false, false } :: { any }
	for f = 1, 360 do
		i.dt = DT
		i.vx, i.vz = speed * math.sin(way), -speed * math.cos(way)
		if setup then
			setup(i)
		end
		Gait.step(s, i, B, pose)
		x += i.vx * DT
		z += i.vz * DT
		if f > 90 then
			frames2 += 1
			local fr = frames(pose, x, 0, z)
			rootLow = math.min(rootLow, pose.m[2])
			for side, name in { "RightFoot", "LeftFoot" } do
				local hx, hy, hz, tx, ty, tz = sole(fr[name])
				sink = math.min(sink, math.min(hy, ty) - GROUND)
				if math.min(hy, ty) < GROUND + 0.003 then
					contact += 1
					local l = last[side]
					if l then
						slide += math.min(math.sqrt((hx - l[1]) ^ 2 + (hz - l[2]) ^ 2), math.sqrt((tx - l[3]) ^ 2 + (tz - l[4]) ^ 2))
					end
					last[side] = { hx, hz, tx, tz }
				else
					last[side] = false
				end
			end
			-- the feet's sides, in the hips' frame (the root's frame turned by the hips' yaw)
			local r, l = fr.RightFoot, fr.LeftFoot
			local yaw = s.yaw
			local rx = (r[10] - x) * math.cos(yaw) - (r[12] - z) * math.sin(yaw)
			local lx = (l[10] - x) * math.cos(yaw) - (l[12] - z) * math.sin(yaw)
			if rx - lx < 0.2 then
				crossed = true
			end
		end
	end
	return contact / (2 * frames2), slide / (speed * frames2 * DT), sink, rootLow, crossed, s, pose
end

for _, v in { 3.5, 5, 8, 14 } do
	local share, slide, sink = walk(v, 0)
	local duty = Gait.duty(v)
	check(string.format("walking %g: a planted foot does not slide (%.4f a stud)", v, slide), slide < 0.005)
	check(string.format("walking %g: the feet down for most of their stance (%.2f of %.2f)", v, share, duty),
		share > duty * (if v <= 8 then 0.85 else 0.7))
	check(string.format("walking %g: the soles never under the ground", v), sink > -0.004, sink)
end
for _, way in { 45, 135, 180, -60 } do
	local _, slide, sink, _, crossed = walk(3.5, rad(way), function(i)
		i.aiming, i.hands = true, "busy"
	end)
	check(string.format("aiming, walking %d° from the front: planted, on the ground, the feet not crossed", way),
		slide < 0.01 and sink > -0.004 and not crossed, `{slide} {sink} {crossed}`)
end
do
	local _, slide, _, _, crossed, s = walk(3.5, rad(90), function(i)
		i.aiming, i.hands = true, "busy"
	end)
	check("aiming, walking sideways: the feet shuffle a little, never cross", slide < 0.04 and not crossed, slide)
	check("sideways: the hips turned toward the way, at most StrafeYaw", s.yaw < -rad(G.StrafeYaw) * 0.9 and s.yaw >= -rad(G.StrafeYaw) - 1e-3, deg(s.yaw))
	local _, _, _, _, _, s2, pose2 = walk(3.5, rad(90), function(i)
		i.aiming, i.hands = true, "busy"
	end)
	-- the chest (the root's turn and the waist's) back to the front, aiming
	local rootYaw = math.atan2(pose2.m[6], pose2.m[12])
	local waistYaw = math.atan2(pose2.m[12 + 6], pose2.m[12 + 12])
	check("aiming sideways, the chest stays on the aim (the waist turns it back)", math.abs(deg(rootYaw + waistYaw)) < 4, deg(rootYaw + waistYaw))
	check("walking backwards: the hips stay to the front, the legs walk back", (function()
		local _, _, _, _, _, sb = walk(3.5, rad(180), function(i)
			i.aiming, i.hands = true, "busy"
		end)
		return sb.back and math.abs(sb.yaw) < rad(2)
	end)())
	local _ = s2
end
do
	local _, _, _, rootLow = walk(14, 0)
	check("the walk's bob stays within MaxDrop", -rootLow <= G.MaxDrop * B.leg + 0.02, rootLow)
end

-- Uphill: the foot ahead lands higher, the body leans in.
do
	local _, _, _, _, _, s, pose = walk(8, 0, function(i)
		i.slopeF = 0.35
	end)
	local fr = frames(pose, 0, 0, 0)
	local _, flatSlide = walk(8, 0)
	local waistPitch = math.asin(-math.clamp(pose.m[12 + 9], -1, 1))
	check("uphill: the body leans forward into it", waistPitch < -rad(4), deg(waistPitch))
	local _ = fr
	local _ = s
	local _ = flatSlide
end

-- ── Start, stop, no snap ─────────────────────────────────────────────────────────────────────────────────────────────

-- A joint "snaps" when it turns much more in one frame than in the frames around it (the legs at a brisk walk turn
-- fast, smoothly). The worst such spike in a run of frames (joints laid on in all four frames), and NaN.
local function spikes(frames: number, drive: (any, number, any) -> ()): (number, boolean, any)
	local s, i, pose = Gait.new(0.12), Gait.input(), Gait.pose()
	local hist = {}
	local ok = true
	for f = 1, frames do
		i.dt = DT
		drive(i, f * DT, s)
		Gait.step(s, i, B, pose)
		ok = ok and finite(pose)
		hist[f] = { m = table.clone(pose.m), w = table.clone(pose.w) }
	end
	local worst = 0
	for f = 3, frames - 1 do
		for j = 1, Gait.Count do
			if hist[f - 2].w[j] > 0.05 and hist[f - 1].w[j] > 0.05 and hist[f].w[j] > 0.05 and hist[f + 1].w[j] > 0.05 then
				local d0 = turnBetween(hist[f - 2].m, hist[f - 1].m, j)
				local d1 = turnBetween(hist[f - 1].m, hist[f].m, j)
				local d2 = turnBetween(hist[f].m, hist[f + 1].m, j)
				worst = math.max(worst, d1 - math.max(d0, d2))
			end
		end
	end
	return worst, ok, s
end
do
	-- 0 → 14 at 28 / s² (client/CameraRig.luau), walk, a sprint to 28, back, then 38 / s² down to a stop
	local v = 0
	local leanMax, leanMin = 0, 0
	local settledAt: number? = nil
	local releasedAt: number? = nil
	local weightJump = 0
	local lastW = 0
	local worst, ok, s = spikes(300, function(i, t, st)
		local goal = if t < 1.5 then 14 elseif t < 2.5 then 28 elseif t < 3 then 14 else 0
		v = if goal > v then math.min(goal, v + 28 * DT) else math.max(goal, v - 38 * DT)
		i.vx, i.vz = 0, -v
		leanMax, leanMin = math.max(leanMax, st.lean), math.min(leanMin, st.lean)
		local wNow = st.hold
		weightJump = math.max(weightJump, math.abs(wNow - lastW))
		lastW = wNow
		if t > 3.4 and not settledAt and st.amp <= 0 then
			settledAt = t
		end
		if t > 3.4 and not releasedAt and st.hold <= 0 then
			releasedAt = t
		end
	end)
	check("start, walk, sprint, stop: never a NaN", ok)
	check("start, walk, sprint, stop: no joint snaps (a spike under 15° a frame)", worst < 15, worst)
	check("the walk blends in and out (over 5 frames at least, no jump in its share)", weightJump <= 0.2, weightJump)
	check("the body leans into the start and back against the stop", leanMax > rad(2) and leanMin < -rad(2), `{deg(leanMax)} {deg(leanMin)}`)
	check("standing again, the stride closes soon after the stop", settledAt ~= nil and (settledAt :: number) < 3 + 0.37 + G.SettleTime + 0.5, settledAt)
	check("then the body goes back to the animation (LetGo after the stride closed)", releasedAt ~= nil and settledAt ~= nil
		and (releasedAt :: number) - (settledAt :: number) < G.LetGo + 0.05 and (releasedAt :: number) - (settledAt :: number) > G.LetGo * 0.5,
		`{releasedAt} {settledAt}`)
	check("stopped: the feet together again", s.amp == 0 and (math.abs(s.phase - Gait.duty(0) / 2) < 0.06
		or math.abs(s.phase - Gait.duty(0) / 2 - 0.5) < 0.06), s.phase)
	local strafe = spikes(300, function(i, t)
		i.aiming, i.hands = true, "busy"
		local a = if t < 2 then rad(80) else rad(110) -- (over into walking backwards)
		i.vx, i.vz = 3.5 * math.sin(a), -3.5 * math.cos(a)
	end)
	check("aiming, from sideways into backwards: no snap", strafe < 10, strafe)
	local hop = spikes(240, function(i, t)
		local tt = t - 1
		i.air = tt > 0 and 50 * tt - 98.1 * tt * tt > 0
		i.vy = if i.air then 50 - 196.2 * tt else 0
		i.y = if i.air then 50 * tt - 98.1 * tt * tt else 0
		i.vx, i.vz = 0, -14
	end)
	check("a running jump springs off quickly but never snaps (a spike under 30°)", hop < 30, hop)
	local fidgets = spikes(1800, function(i)
		i.vx, i.vz = 0, 0
	end)
	check("the fidgets flow (no spike over 3°)", fidgets < 3, fidgets)
end

-- ── The run and the tired sprint ─────────────────────────────────────────────────────────────────────────────────────

local function sprint(breath: number)
	local s, i, pose = Gait.new(0.5), Gait.input(), Gait.pose()
	local armMax, pitchSum, neckSum, n = 0, 0, 0, 0
	for f = 1, 240 do
		i.dt, i.vx, i.vz, i.breath = DT, 0, -28, breath
		Gait.step(s, i, B, pose)
		if f > 120 then
			armMax = math.max(armMax, math.abs(math.asin(math.clamp(-pose.m[(Gait.RS - 1) * 12 + 9], -1, 1))))
			pitchSum += math.asin(math.clamp(-pose.m[(Gait.WAIST - 1) * 12 + 9], -1, 1))
			neckSum += math.asin(math.clamp(-pose.m[(Gait.NECK - 1) * 12 + 9], -1, 1))
			n += 1
		end
	end
	return armMax, pitchSum / n, neckSum / n, s
end
local freshArm, freshPitch, freshNeck, fresh = sprint(1)
local tiredArm, tiredPitch, tiredNeck = sprint(0.04)
check("sprinting: the run cycle has it all", Gait.running(fresh) > 0.99)
check("out of breath: the arms pump less", tiredArm < freshArm * 0.9, `{deg(tiredArm)} vs {deg(freshArm)}`)
check("out of breath: the body hunches forward more", tiredPitch < freshPitch - rad(5), `{deg(tiredPitch)} vs {deg(freshPitch)}`)
check("out of breath: the head hangs lower", tiredNeck < freshNeck, `{deg(tiredNeck)} vs {deg(freshNeck)}`)
do
	-- another courier's breath, guessed from the sprint (Config.Movement.Stamina seconds)
	local s, i, pose = Gait.new(0.5), Gait.input(), Gait.pose()
	for _ = 1, math.floor((Config.Movement.Stamina + 0.5) / DT) do
		i.dt, i.vx, i.vz, i.breath = DT, 0, -28, -1
		Gait.step(s, i, B, pose)
	end
	check("another courier's breath runs out after a full sprint", s.breath < 0.1 and s.spent, s.breath)
end

-- ── Turning ──────────────────────────────────────────────────────────────────────────────────────────────────────────

local function turning(rate: number, calm: boolean)
	local s, i, pose = Gait.new(0.5), Gait.input(), Gait.pose()
	for _ = 1, 120 do
		i.dt, i.vx, i.vz, i.yawRate, i.calm = DT, 0, -14, rate, calm
		Gait.step(s, i, B, pose)
	end
	return s.turn
end
local left, right, calmLeft = turning(3, false), turning(-3, false), turning(3, true)
check("turning left the body leans left (into the turn), right right", left > rad(3) and right < -rad(3), `{deg(left)} {deg(right)}`)
check("the lean into a turn stays within TurnMax", turning(20, false) <= rad(G.TurnMax) + 1e-6)
check("Reduced Motion: half the lean into a turn", math.abs(calmLeft - left / 2) < rad(0.5), deg(calmLeft))

-- ── The jump and the landing ─────────────────────────────────────────────────────────────────────────────────────────

local function jump(fall: number, speed: number)
	local s, i, pose = Gait.new(0.5), Gait.input(), Gait.pose()
	local g = 196.2
	local v0 = math.sqrt(2 * g * 6.4)
	local rootLow, airMax, landed, ok = 0, 0, false, true
	local t = 0
	while t < 2.5 do
		local tt = t - 0.2
		i.dt, i.air = DT, t > 0.2 and (v0 * tt - 0.5 * g * tt * tt) > -fall
		i.vy = if i.air then v0 - g * tt else 0
		i.y = if i.air then v0 * tt - 0.5 * g * tt * tt elseif t > 0.2 then -fall else 0
		i.vx, i.vz = 0, -speed
		Gait.step(s, i, B, pose)
		ok = ok and finite(pose)
		rootLow = math.min(rootLow, pose.m[2])
		airMax = math.max(airMax, s.airW)
		if s.landT < 0.05 then
			landed = true
		end
		t += DT
	end
	return rootLow, airMax, landed, ok, s
end
local low1, air1, landed1, ok1, still1 = jump(0, 0)
local low2, _, landed2, ok2 = jump(25, 0)
local low3, _, _, ok3, moving3 = jump(0, 14)
check("a jump poses the air and lands", air1 > 0.99 and landed1 and landed2 and ok1 and ok2 and ok3)
check("the landing from higher squashes deeper", low2 < low1 - 0.15, `{low1} {low2}`)
check("never hung lower than client/Unstuck.luau's 0.8 studs", low1 > -0.8 and low2 > -0.8 and low3 > -0.8, `{low1} {low2} {low3}`)
check("landing on the move squashes less", moving3.landDepth < still1.landDepth * 0.7, `{moving3.landDepth} vs {still1.landDepth}`)
do
	-- a step off a kerb (in the air a moment, half a stud down) is no jump, no landing
	local s, i, pose = Gait.new(0.5), Gait.input(), Gait.pose()
	for f = 1, 60 do
		i.dt, i.air = DT, f >= 20 and f < 24
		i.vy, i.y = if i.air then -10 else 0, if f >= 24 then -0.5 else 0
		i.vx, i.vz = 0, -14
		Gait.step(s, i, B, pose)
	end
	check("a kerb's step down is neither a fall nor a landing", s.airW == 0 and s.landT > 0.5)
end

-- ── Idle: fidgets, catching the breath, holds ────────────────────────────────────────────────────────────────────────

local function stand(seconds: number, setup: (any, number) -> ())
	local s, i, pose = Gait.new(0.73), Gait.input(), Gait.pose()
	local seen: { [string]: boolean } = {}
	local t = 0
	while t < seconds do
		i.dt, i.vx, i.vz = DT, 0, 0
		setup(i, t)
		Gait.step(s, i, B, pose)
		if s.fidget then
			seen[s.fidget] = true
		end
		t += DT
	end
	return s, pose, seen
end
do
	local _, _, seen = stand(G.IdleAfter * 1.3 + 4 * G.FidgetEvery, function() end)
	local n = 0
	for kind in seen do
		n += 1
		check("a free-handed fidget: " .. kind, table.find(Gait.fidgetsFor("free") :: { string }, kind) ~= nil)
	end
	check("standing still a while, the body fidgets now and then", n >= 2, n)
	local _, _, calm = stand(30, function(i)
		i.calm = true
	end)
	check("Reduced Motion: no fidgets", next(calm) == nil)
	local _, _, far = stand(30, function(i)
		i.detail = false
	end)
	check("far from the camera: no fidgets", next(far) == nil)
	local _, _, gun = stand(40, function(i)
		i.hands = "gun"
	end)
	check("the gun out: only the gun's fidgets", next(gun) ~= nil and not gun.stretch and not gun.watch)
	local _, _, aim = stand(30, function(i)
		i.hands, i.aiming = "busy", true
	end)
	check("aiming (the hands busy): no fidgets", next(aim) == nil)
	-- moving off ends a fidget at once
	local s, i, pose = Gait.new(0.73), Gait.input(), Gait.pose()
	local t = 0
	while not s.fidget and t < 30 do
		i.dt, i.vx, i.vz = DT, 0, 0
		Gait.step(s, i, B, pose)
		t += DT
	end
	for _ = 1, 30 do
		i.dt, i.vx, i.vz = DT, 0, -8
		Gait.step(s, i, B, pose)
	end
	check("walking off ends a fidget", s.fidget == nil)
end
do
	-- spent, stopped: the hands on the knees until half the breath is back
	local s, pose = stand(1.5, function(i)
		i.breath = 0.03
	end)
	check("spent and stopped with free hands: catching the breath", s.catch > 0.99 and pose.w[Gait.ROOT] > 0.99, s.catch)
	local s2 = stand(1.5, function(i)
		i.breath, i.hands = 0.03, "carry"
	end)
	check("not with a load in the hands", s2.catch == 0)
	local s3 = stand(2.5, function(i, t)
		i.breath = if t < 1.5 then 0.03 else 0.7
	end)
	check("the breath back: standing up again", not s3.catching and s3.catch < 1)
end
do
	local _, pose = stand(1, function(i)
		i.hands = "gun"
	end)
	check("the gun out, standing: the gun's arm and wrist held low and ready, the rest the animation's",
		pose.w[Gait.RS] > 0.99 and pose.w[Gait.RW] > 0.99 and pose.w[Gait.LS] == 0 and pose.w[Gait.ROOT] == 0)
	local _, bag = stand(1, function(i)
		i.hands = "bag"
	end)
	check("the bag in the hand, standing: the arm is client/BagSway.luau's", bag.w[Gait.LS] == 0)
	local _, _, _, _, _, _, walked = walk(14, 0, function(i)
		i.hands = "bag"
	end)
	local lsX = math.asin(math.clamp(-walked.m[(Gait.LS - 1) * 12 + 9], -1, 1))
	check("the bag in the hand, walking: the gait holds the arm, out from the body", walked.w[Gait.LS] > 0.99
		and walked.m[(Gait.LS - 1) * 12 + 7] < -math.sin(rad(Config.Courier.BagArm.Out)) * 0.8, lsX)
end

-- ── No table per step ────────────────────────────────────────────────────────────────────────────────────────────────

do
	local s, i, pose = Gait.new(0.5), Gait.input(), Gait.pose()
	local function run(n: number): number
		collectgarbage("collect")
		-- (the full collect shrinks the Lua stack and the next step grows it back: 1–2 KB every run, however many
		-- steps; one step first, so only what the steps keep counts)
		Gait.step(s, i, B, pose)
		local before = collectgarbage("count")
		for f = 1, n do
			i.dt, i.vx, i.vz = DT, 3 * math.sin(f * 0.01), -14
			i.air = f % 300 > 260
			i.vy = if i.air then 20 else 0
			Gait.step(s, i, B, pose)
		end
		return collectgarbage("count") - before
	end
	-- The middle of three runs: the VM also grows by 3 KB once in a while (at most once a process, at a run's first
	-- step, as much for 3,000 steps as for 30,000), which broke the limit now and then; a table per step shows in
	-- every run, the more the longer.
	local function middle(n: number): number
		local a, b, c = run(n), run(n), run(n)
		return math.max(math.min(a, b), math.min(math.max(a, b), c))
	end
	run(600)
	local few, many = middle(3000), middle(30000)
	check("no new tables per step (the memory does not grow with the steps)", many < 4 and many < few + 2, `{few} KB, {many} KB`)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
