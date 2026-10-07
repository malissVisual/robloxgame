-- Logic test of 6.7's body in motion (shared/BodyMotion.luau, Config.Body, the "pickup" and "land" gestures of
-- shared/Gestures.luau) in the standalone Luau CLI: the two-bone reach really reaches (and bends the right way), the
-- crouch keeps the feet where they stood and flat, the breath, the weight shift and the blinks keep their timing, the
-- landing dip grows with the fall and never hangs the body lower than client/Unstuck.luau allows, the head looks only
-- ahead, the walk's weight follows the thighs.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local BodyMotion = require("./BodyMotion")
local Gestures = require("./Gestures")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local B = Config.Body
local rad = math.rad

-- The reach ----------------------------------------------------------------------------------------------------------

-- Where the limb's end lands for a joint rotation (the X and Y axes' images) and a bend: the upper bone along the
-- rotated -Y, the lower one turned by the bend about the upper bone's own X (as the R15 joints' Transform do).
local function tip(xx, xy, xz, yx, yy, yz, bend, upper, lower): (number, number, number)
	local zx, zy, zz = xy * yz - xz * yy, xz * yx - xx * yz, xx * yy - xy * yx
	local c, s = math.cos(bend), math.sin(bend)
	-- elbow = R (0, -upper, 0); forearm = R Rx(bend) (0, -lower, 0) = R (0, -lower c, -lower s)
	return -upper * yx - lower * (c * yx + s * zx), -upper * yy - lower * (c * yy + s * zy), -upper * yz - lower * (c * yz + s * zz)
end

local x0, y0, z0, x1, y1, z1, rest = BodyMotion.reach(0, -1.9, 0, 1, 0.9, 0, 0, 1)
check("an arm reaching straight down: the rest pose", near(x0, 1, 1e-3) and near(y1, 1, 1e-3) and math.abs(rest) < 0.1, `{x0} {y1} {rest}`)
local seed = 12345
local function random(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local worst, orthogonal, poleSide, bends = 0, true, true, true
for _ = 1, 400 do
	local upper, lower = 0.9 + random() * 0.3, 0.8 + random() * 0.6
	local reachable = (upper + lower) * (0.35 + random() * 0.6)
	local dx, dy, dz = random() * 2 - 1, random() * 2 - 1.3, random() * 2 - 1.4
	local m = math.sqrt(dx * dx + dy * dy + dz * dz)
	dx, dy, dz = dx / m * reachable, dy / m * reachable, dz / m * reachable
	local px, py, pz = random() - 0.5, -1, 0.6
	local a, b, c, d, e, f, bend = BodyMotion.reach(dx, dy, dz, upper, lower, px, py, pz)
	local tx, ty, tz = tip(a, b, c, d, e, f, bend, upper, lower)
	worst = math.max(worst, math.sqrt((tx - dx) ^ 2 + (ty - dy) ^ 2 + (tz - dz) ^ 2))
	orthogonal = orthogonal and near(a * d + b * e + c * f, 0, 1e-6) and near(a * a + b * b + c * c, 1, 1e-6) and near(d * d + e * e + f * f, 1, 1e-6)
	bends = bends and bend >= 0 and bend <= math.pi
	-- the elbow (R (0, -upper, 0) = -upper * Y) leans toward the pole, away from the straight line
	local ex, ey, ez = -upper * d, -upper * e, -upper * f
	local along = (ex * dx + ey * dy + ez * dz) / (reachable * reachable)
	local ox, oy, oz = ex - along * dx, ey - along * dy, ez - along * dz
	poleSide = poleSide and (ox * px + oy * py + oz * pz) >= -1e-6
end
check("the reach lands on every reachable point", worst < 1e-4, worst)
check("the joint's axes stay square and unit", orthogonal)
check("the elbow bends forward, never backward", bends)
check("the elbow points toward the pole", poleSide)
local a, b, c, d, e, f, bend = BodyMotion.reach(0, 0, -9, 1, 1, 0, -1, 0)
local tx, ty, tz = tip(a, b, c, d, e, f, bend, 1, 1)
check("out of reach: straight toward it", near(tx, 0, 1e-3) and near(ty, 0, 1e-3) and near(tz, -2, 2e-3) and math.abs(bend) < 0.1, `{tx} {ty} {tz}`)
-- A knee: the pole forward, the hinge the other way round (a negative bend), the thigh not twisted about itself.
local ka, kb, kc, kd, ke, kf, knee = BodyMotion.reach(0, -2.2, -0.3, 1.25, 1.25, 0, 0, -1, true)
local kx, ky, kz = tip(ka, kb, kc, kd, ke, kf, knee, 1.25, 1.25)
check("a knee bends with a negative X", knee < 0 and ka > 0.99, `{knee} {ka}`)
check("the knee's reach lands too", near(kx, 0, 1e-4) and near(ky, -2.2, 1e-4) and near(kz, -0.3, 1e-4))

-- The crouch: the feet stay -----------------------------------------------------------------------------------------

local planted, flat = 0, true
for i = 0, 20 do
	local drop, back = 0.8 * i / 20, 0.2 * (i % 3) / 2
	local hip, kneeAngle, ankle = BodyMotion.crouch(drop, back, 1.25, 1.25)
	-- in the leg's side view: forward is -z; the thigh swings `hip` forward from straight down
	local kneeZ, kneeY = -1.25 * math.sin(hip), -1.25 * math.cos(hip)
	local shin = hip + kneeAngle
	local footZ, footY = kneeZ - 1.25 * math.sin(shin), kneeY - 1.25 * math.cos(shin)
	planted = math.max(planted, math.abs(footZ + back), math.abs(footY + 2.5 - drop))
	flat = flat and near(hip + kneeAngle + ankle, 0, 1e-9) and kneeAngle <= 1e-9
end
check("the crouch keeps the feet where they stood", planted < 1e-6, planted)
check("the feet stay flat, the knees bend forward", flat)
local h0, k0, a0 = BodyMotion.crouch(0, 0, 1.25, 1.25)
check("no crouch: straight legs", math.abs(h0) < 1e-3 and math.abs(k0) < 1e-3 and math.abs(a0) < 1e-3)

-- Breathing, the weight shift, blinks ---------------------------------------------------------------------------

local lo, hi, jump = math.huge, -math.huge, 0
local last = BodyMotion.breath(0, B.Breath)
for i = 1, 2000 do
	local v = BodyMotion.breath(i * 0.005, B.Breath)
	lo, hi = math.min(lo, v), math.max(hi, v)
	jump = math.max(jump, math.abs(v - last))
	last = v
end
check("the breath goes all the way in and out", near(lo, 0, 0.02) and near(hi, 1, 0.02), `{lo} {hi}`)
check("the breath moves smoothly", jump < 0.03, jump)
check("a breath repeats", near(BodyMotion.breath(1.3, B.Breath), BodyMotion.breath(1.3 + B.Breath, B.Breath), 1e-9))

local function shifts(seed: number): (number, number, number, number, number)
	local low, high, biggest, still = math.huge, -math.huge, 0, 0
	local was = BodyMotion.shift(0, seed)
	local steps = 6000
	for i = 1, steps do
		local v = BodyMotion.shift(i * 0.01, seed)
		low, high = math.min(low, v), math.max(high, v)
		biggest = math.max(biggest, math.abs(v - was))
		if v == was then
			still += 1
		end
		was = v
	end
	return low, high, biggest, still / steps, BodyMotion.shift(7.77, seed)
end
local low, high, biggest, still, sample = shifts(0.3)
local _, _, _, _, other = shifts(0.71)
check("the weight goes onto both feet in a minute", low < -0.5 and high > 0.5 and low >= -1 and high <= 1, `{low} {high}`)
check("the weight moves over smoothly", biggest < 0.03, biggest)
check("the weight rests on a foot most of the time", still > 0.5, still)
check("two people shift at their own moments", math.abs(sample - other) > 1e-3)

local shut, longest, gap, run, since, blinks = 0, 0, 0, 0, 0, 0
local open, within = true, true
for i = 1, 60000 do
	local v = BodyMotion.blink(i * 0.001, 0.42)
	within = within and v >= 0 and v <= 1
	if v > 0 then
		shut += 1
		run += 1
		if open then
			blinks += 1
			gap = math.max(gap, since)
			since = 0
		end
		open = false
	else
		longest = math.max(longest, run)
		run = 0
		open = true
		since += 1
	end
end
check("a blink within 0..1", within)
check("blinks every few seconds", blinks >= 60 / B.BlinkEvery * 0.8 and gap * 0.001 < B.BlinkEvery * 2, `{blinks} blinks, the longest gap {gap * 0.001}`)
check("a blink is quick", longest * 0.001 <= B.BlinkTime + 0.002 and shut / 60000 < 0.1, longest)

-- The landing and the flinch -------------------------------------------------------------------------------------

check("a step off a kerb: no dip", BodyMotion.landDrop(B.LandFrom - 1) == 0 and BodyMotion.landDrop(10) == 0)
local lastDrop = 0
local grows = true
for fall = B.LandFrom, 200, 5 do
	local drop = BodyMotion.landDrop(fall)
	grows = grows and drop >= lastDrop and drop >= B.LandMin and drop <= B.LandDrop
	lastDrop = drop
end
check("the dip grows with the fall, from LandMin to LandDrop", grows and near(lastDrop, B.LandDrop))
check("the deepest dip leaves the Root joint above Unstuck's 0.8", B.LandDrop < 0.8 and B.PickupDrop < 0.8)
local total = BodyMotion.landTime()
check("the dip: down quickly, up slower", B.LandDown < B.LandUp and total < 0.8)
check("the dip starts and ends at rest", BodyMotion.land(0) == 0 and BodyMotion.land(total) == 0 and BodyMotion.land(total + 1) == 0)
check("the dip's deepest right after the landing", near(BodyMotion.land(B.LandDown), 1, 1e-6))
local flinchTotal = BodyMotion.flinchTime()
check("the flinch starts and ends at rest", BodyMotion.flinch(0) == 0 and BodyMotion.flinch(flinchTotal) == 0 and near(BodyMotion.flinch(B.FlinchIn), 1))
check("the flinch is short", flinchTotal < 0.6 and B.FlinchIn < B.FlinchOut)

-- The head ---------------------------------------------------------------------------------------------------------

local yaw0, pitch0, ok0 = BodyMotion.look(0, 0, -5)
check("straight ahead: no turn", ok0 and near(yaw0, 0) and near(pitch0, 0))
local yawL, _, okL = BodyMotion.look(-5, 0, -5)
check("a person ahead on the left: the head turns left", okL and near(yawL, rad(45), 1e-6))
local yawFar, _, okFar = BodyMotion.look(-5, 0, 0.5)
check("round to the side: turned as far as it goes", okFar and near(yawFar, rad(B.LookYaw)))
local _, _, okBack = BodyMotion.look(0.5, 0, 5)
check("behind: not looked at", not okBack)
local _, pitchUp = BodyMotion.look(0, 10, -1)
check("high up: the head tips back as far as it goes", near(pitchUp, rad(B.LookPitch)))

-- The walk's weight ------------------------------------------------------------------------------------------------

local bobApart, armApart, twistApart = BodyMotion.stride(rad(B.Spread / 2), -rad(B.Spread / 2))
local bobTogether, armTogether = BodyMotion.stride(0, 0)
check("the body lowest with the legs apart, highest as they pass", bobApart < 0 and bobTogether > 0 and near(bobTogether - bobApart, B.WalkBob))
check("the right arm back with the right thigh forward", armApart > 0 and armTogether == 0 and twistApart < 0)

-- The gestures with the legs ---------------------------------------------------------------------------------------

for _, kind in { "pickup", "land" } do
	local seconds = Gestures.seconds(kind)
	check(`{kind}: its seconds from Config.Body`, seconds == B.Gestures[kind] and seconds ~= nil and seconds > 0.2 and seconds < 1.5)
	if not seconds then
		continue
	end
	check(`{kind}: in and out`, Gestures.weight(kind, 0) == 0 and Gestures.weight(kind, seconds) == 0 and Gestures.weight(kind, seconds / 2) > 0.99)
	local pose = Gestures.pose(kind, seconds / 2)
	check(`{kind}: arms, the waist and a crouch`, pose ~= nil and pose.rs ~= nil and pose.waist ~= nil and pose.crouch ~= nil)
	if pose then
		for joint, angles in pose do
			check(`{kind} {joint}: three numbers`, #angles == 3)
		end
		check(`{kind}: the body bends forward`, pose.waist[1] < 0 and pose.crouch[1] > 0 and pose.crouch[1] < 0.8)
	end
	check(`{kind}: an R6 body moves its arm`, (Gestures.r6(kind, seconds / 2)) ~= nil)
end
local reach = Gestures.pose("pickup", B.Gestures.pickup * 0.45) :: Gestures.Pose
local up = Gestures.pose("pickup", B.Gestures.pickup * 0.98) :: Gestures.Pose
check("pickup: the hand down to the piece, then up with it", reach.rs[1] > up.rs[1] and up.re[1] > reach.re[1])

-- The numbers ------------------------------------------------------------------------------------------------------

check("Config.Body: posed within range, a few at a time", B.Range > 0 and B.Range <= 200 and B.MaxPosed >= 10 and B.MaxPosed <= 60 and B.Retarget > 0 and B.Retarget < 1)
check("Config.Body: the walk below the sprint", B.WalkFrom > B.IdleBelow and B.WalkFrom < Config.Courier.Sprint.From)
check("Config.Body: small idle motions", B.BreathTilt < 4 and B.ShiftSway < 0.2 and B.ShiftRoll < 5 and B.WalkBob < 0.2)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
