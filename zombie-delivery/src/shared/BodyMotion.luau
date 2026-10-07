--!strict
-- 6.7: the body in motion, the pure maths (no Roblox at its top level: tests/bodymotion_test.luau runs it in the
-- standalone Luau). The clients turn these numbers into the R15 joints' Transform in PreSimulation (client/BodyLife.luau:
-- the idle life, the landing, the flinch, the walk's weight; client/ArmPose.luau: the carry's reach to the box and the
-- gestures with the legs). Config.Body holds the tuning.
--   BodyMotion.reach(dx, dy, dz, upper, lower, px, py, pz, negative)  a two-bone limb (an arm, a leg) reaching a point
--        (dx, dy, dz) from its joint, in the joint's parent frame; `upper` / `lower` the bones' lengths (the joint to the
--        middle joint, the middle joint to the point the limb reaches with); (px, py, pz) the pole: where the elbow
--        (the knee) points. Returns the joint's rotation as the images of its X and Y axes (CFrame.fromMatrix(zero, X, Y)
--        on the client: the bone's rest "down" turns onto the upper bone) and the middle joint's bend about its own X
--        (positive bends an elbow; `negative` for a knee: the hinge the other way round, the bend negative). A point out
--        of reach is reached as far as the limb goes, straight toward it.
--   BodyMotion.crouch(drop, back, thigh, shin)  the legs bent for hips `drop` studs lower and `back` studs further back
--        with the feet where they stood: the hip's swing (X, + forward), the knee (X, negative) and the ankle (X, the
--        foot kept flat).
--   BodyMotion.breath(t, period)   0..1: the breath in (a quick breath in, a slower one out)
--   BodyMotion.shift(t, seed)      -1..1: the weight on the left (-) or the right (+) foot: held, then moved over (each
--                                  body its own `seed`, so a crowd does not sway in step)
--   BodyMotion.blink(t, seed)      0..1: how shut the eyes are
--   BodyMotion.landDrop(fall)      studs the hips dip landing at `fall` studs / s (0: no dip)
--   BodyMotion.land(t) / BodyMotion.landTime()      0..1 of the dip `t` seconds after the landing; its length
--   BodyMotion.flinch(t) / BodyMotion.flinchTime()  0..1 of the flinch `t` seconds after the hit; its length
--   BodyMotion.look(dx, dy, dz)    the head's yaw (+ left) and pitch (+ up) toward a point in the body's frame, clamped;
--                                  false for a point too far round behind
--   BodyMotion.stride(hipR, hipL)  the walk's weight from the stock walk's own thighs (their X swing, radians): the
--                                  body's bob (studs), the arms' extra swing (radians: the right arm minus it, the left
--                                  plus) and the chest's turn (radians)
--   BodyMotion.gesture(kind, t)    the "pickup" and "land" gestures in shared/Gestures.luau's format, with the body
--                                  keys: waist / neck { x, y, z } degrees, crouch { drop, back (studs), hips (degrees
--                                  the pelvis tips forward) }: client/ArmPose.luau bends the legs to it
-- Frames (as shared/RunCycle.luau): +X right, +Y up, -Z forward; about X a positive angle swings a thigh or an upper arm
-- forward and bends an elbow, a knee bends with a negative X, a negative waist X tips the upper body forward; about Y a
-- positive angle turns to the left. Angles in radians unless said.

local Config = require(script.Parent.Config)

local BodyMotion = {}

local B = Config.Body
local rad = math.rad

local function smooth(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end
BodyMotion.smooth = smooth

-- A repeatable 0..1 from a number (a body's own moment for a blink or a shift).
local function hash(n: number): number
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end

local function unit(x: number, y: number, z: number): (number, number, number)
	local m = math.sqrt(x * x + y * y + z * z)
	if m < 1e-9 then
		return 0, 0, 0
	end
	return x / m, y / m, z / m
end

function BodyMotion.reach(dx: number, dy: number, dz: number, upper: number, lower: number, px: number, py: number, pz: number, negative: boolean?): (number, number, number, number, number, number, number)
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-4 or upper <= 0 or lower <= 0 then
		return 1, 0, 0, 0, 1, 0, 0
	end
	local hx, hy, hz = dx / d, dy / d, dz / d
	local span = math.clamp(d, math.abs(upper - lower) + 1e-3, upper + lower - 1e-3)
	-- The pole square to the reach (a pole along it: behind, else to the right).
	local dot = px * hx + py * hy + pz * hz
	local qx, qy, qz = unit(px - dot * hx, py - dot * hy, pz - dot * hz)
	if qx == 0 and qy == 0 and qz == 0 then
		qx, qy, qz = unit(-hz * hx, -hz * hy, 1 - hz * hz)
		if qx == 0 and qy == 0 and qz == 0 then
			qx, qy, qz = 1, 0, 0
		end
	end
	-- The upper bone leaves the reach toward the pole by the triangle's angle at the joint.
	local cosA = math.clamp((upper * upper + span * span - lower * lower) / (2 * upper * span), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local ux, uy, uz = cosA * hx + sinA * qx, cosA * hy + sinA * qy, cosA * hz + sinA * qz
	-- The hinge: square to both (pole × reach); the lower bone runs from the middle joint to the point.
	local nx, ny, nz = qy * hz - qz * hy, qz * hx - qx * hz, qx * hy - qy * hx
	local fx, fy, fz = unit(hx * span - ux * upper, hy * span - uy * upper, hz * span - uz * upper)
	local bend = math.acos(math.clamp(ux * fx + uy * fy + uz * fz, -1, 1))
	if negative then
		return -nx, -ny, -nz, -ux, -uy, -uz, -bend
	end
	return nx, ny, nz, -ux, -uy, -uz, bend
end

function BodyMotion.crouch(drop: number, back: number, thigh: number, shin: number): (number, number, number)
	if thigh <= 0 or shin <= 0 then
		return 0, 0, 0
	end
	local h = thigh + shin - math.max(0, drop)
	local d = math.clamp(math.sqrt(h * h + back * back), math.abs(thigh - shin) + 1e-3, thigh + shin)
	local gamma = math.atan2(back, h) -- the feet ahead of the hip: the chord swings forward
	local alpha = math.acos(math.clamp((thigh * thigh + d * d - shin * shin) / (2 * thigh * d), -1, 1))
	local inner = math.acos(math.clamp((thigh * thigh + shin * shin - d * d) / (2 * thigh * shin), -1, 1))
	local bend = math.pi - inner
	local hip = gamma + alpha
	return hip, -bend, bend - hip
end

function BodyMotion.breath(t: number, period: number): number
	local u = t / math.max(period, 0.2)
	u -= math.floor(u)
	if u < 0.4 then
		return smooth(u / 0.4)
	end
	return 1 - smooth((u - 0.4) / 0.6)
end

-- The foot a shift ends on (alternating, each a little different).
local function side(k: number, seed: number): number
	local sign = if k % 2 == 0 then 1 else -1
	return sign * (0.55 + 0.45 * hash(k * 1.7 + seed))
end

function BodyMotion.shift(t: number, seed: number): number
	local period, move = B.ShiftEvery, math.min(B.ShiftTime, B.ShiftEvery)
	local s = t / period + seed * 7.31
	local k = math.floor(s)
	local into = (s - k) * period
	local start = hash(k + seed * 3.7) * (period - move)
	local from, to = side(k - 1, seed), side(k, seed)
	if into <= start then
		return from
	end
	return from + (to - from) * smooth((into - start) / math.max(move, 0.01))
end

function BodyMotion.blink(t: number, seed: number): number
	local every, shut = B.BlinkEvery, B.BlinkTime
	local s = t / every + seed * 5.17
	local k = math.floor(s)
	local into = (s - k) * every
	local at = every * 0.1 + hash(k * 2.3 + seed) * (every * 0.6)
	local x = (into - at) / shut
	if x > 0 and x < 1 then
		return math.sin(math.pi * x)
	end
	-- now and then a second blink right after the first
	if hash(k * 4.1 + seed) > 0.75 then
		x -= 1.7
		if x > 0 and x < 1 then
			return math.sin(math.pi * x)
		end
	end
	return 0
end

function BodyMotion.landDrop(fall: number): number
	if fall < B.LandFrom then
		return 0
	end
	local k = math.clamp((fall - B.LandFrom) / math.max(B.LandFull - B.LandFrom, 1), 0, 1)
	return B.LandMin + (B.LandDrop - B.LandMin) * k
end

function BodyMotion.landTime(): number
	return B.LandDown + B.LandUp
end

function BodyMotion.land(t: number): number
	if t <= 0 then
		return 0
	end
	if t < B.LandDown then
		return smooth(t / B.LandDown)
	end
	return 1 - smooth((t - B.LandDown) / math.max(B.LandUp, 0.01))
end

function BodyMotion.flinchTime(): number
	return B.FlinchIn + B.FlinchOut
end

function BodyMotion.flinch(t: number): number
	if t <= 0 then
		return 0
	end
	if t < B.FlinchIn then
		return smooth(t / B.FlinchIn)
	end
	return 1 - smooth((t - B.FlinchIn) / math.max(B.FlinchOut, 0.01))
end

function BodyMotion.look(dx: number, dy: number, dz: number): (number, number, boolean)
	local flat = math.sqrt(dx * dx + dz * dz)
	if flat < 0.3 then
		return 0, 0, false
	end
	local yaw = math.atan2(-dx, -dz)
	if math.abs(yaw) > rad(B.LookBehind) then
		return 0, 0, false
	end
	local pitch = math.atan2(dy, flat)
	return math.clamp(yaw, -rad(B.LookYaw), rad(B.LookYaw)), math.clamp(pitch, -rad(B.LookPitch), rad(B.LookPitch)), true
end

function BodyMotion.stride(hipR: number, hipL: number): (number, number, number)
	local spread = hipR - hipL
	local k = math.clamp(spread / rad(B.Spread), -1, 1)
	local bob = B.WalkBob * (0.5 - math.abs(k))
	return bob, B.WalkArm * spread * 0.5, -rad(B.WalkTwist) * k
end

-- 6.7: the gestures with the legs (shared/Gestures.luau names them; Config.Body.Gestures their seconds).
function BodyMotion.gesture(kind: string, t: number): { [string]: { number } }?
	if kind == "pickup" then
		-- Down on the knees, the back bent, the right hand reaching to the piece on the ground; then up with it, the
		-- forearm bending it in.
		local u = math.clamp(t / (B.Gestures.pickup or 0.7), 0, 1)
		local reach = smooth(u / 0.45)
		local lift = smooth((u - 0.6) / 0.4)
		return {
			crouch = { B.PickupDrop, 0.15, B.PickupHips },
			waist = { -B.PickupBend, 0, 0 },
			neck = { 22, 0, 0 },
			rs = { 62 + 24 * reach - 34 * lift, 8, 0 },
			re = { 8 + 52 * lift, 0, 0 },
			rw = { -12, 0, 0 },
			ls = { 40, -8, -6 },
			le = { 30, 0, 0 },
		}
	elseif kind == "land" then
		-- A short dip on landing, the arms a little out for the balance.
		return {
			crouch = { 0.3, 0.06, 6 },
			waist = { -10, 0, 0 },
			neck = { 8, 0, 0 },
			rs = { 16, 0, 14 },
			re = { 18, 0, 0 },
			ls = { 16, 0, -14 },
			le = { 18, 0, 0 },
		}
	end
	return nil
end

return BodyMotion
