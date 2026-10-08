--!strict
-- 5.1.1: the rider's pose on a bike, as numbers (pure Luau: client/BikeRider.luau lays them into the R15 joints'
-- Transform over the sit animation; tests/bikes_test.luau checks them). Two poses:
-- * "pedal" (the bikes, a saddle): the upper body leans forward, both arms reach for the grips, the thighs lowered from
--   the sit toward the pedals and pumping with the crank (crank: its angle in radians).
-- * "stand" (the E-Scooter, CarDef.stand: its DriverSeat sits a hip's height over the deck, server/Vehicles.luau): the
--   legs straightened out of the sit (the thighs down, the knees opened) so the feet stand on the deck, a slight
--   forward lean, both hands on the bar, the knees a little soft; no pedalling (the crank is ignored). 6.10: on the
--   back wheel (a wheelie) the knees bend and the body sits back (RiderPose.Wheelie, RiderPose.uprightAt).
-- Each joint gets rotations about X (forward is negative for the waist and the thighs: the R15 joints' own frames),
-- then Y (the arms turned in toward the bar). Angles in radians.

local RiderPose = {}

export type Angles = { x: number, y: number }
export type Pose = {
	waist: Angles,
	rightHip: Angles,
	rightKnee: Angles,
	leftHip: Angles,
	leftKnee: Angles,
	rightShoulder: Angles,
	leftShoulder: Angles,
	elbow: Angles, -- both elbows
}

-- The pedalling rider (5.1's numbers).
RiderPose.Pedal = {
	Lean = math.rad(-16), -- the waist: the upper body tipped forward
	Reach = math.rad(56), -- the upper arms forward toward the grips
	Inward = math.rad(7),
	Elbow = math.rad(16),
	Thigh = math.rad(-30), -- from the sit's level thighs down toward the pedals
	Pump = math.rad(15), -- each leg up and down with the crank
	Knee = math.rad(10),
}

-- The standing rider (5.1.1, the E-Scooter).
RiderPose.Stand = {
	Lean = math.rad(-9), -- a slight forward lean over the bar
	Reach = math.rad(56), -- the arms forward and down to the bar
	Inward = math.rad(6),
	Elbow = math.rad(14),
	Thigh = math.rad(-84), -- the sit's level thighs turned down: the legs under the body
	Knee = math.rad(78), -- the sit's bent knees opened: the shins in line, the knees a little soft
	Stagger = math.rad(4), -- the front foot a touch ahead of the back one (a rider's stance)
}

local function a(x: number, y: number?): Angles
	return { x = x, y = y or 0 }
end

-- 5.8.2: the standing rider ABSOLUTE (client/BikeRider.luau sets these from the rest pose, not on top of the sit
-- animation: whatever sit an avatar plays, the legs stand straight). The hands reach the bar through RiderPose.armIk;
-- Reach / Elbow are the fallback when the bar's points are missing. The body is raised or lowered on its Root joint
-- until the feet rest on the deck (BikeRider measures it).
RiderPose.Upright = {
	Lean = math.rad(-8), -- the waist: a slight forward lean over the bar
	Stagger = math.rad(4), -- the front foot a touch ahead (hips +/-)
	Knee = math.rad(-8), -- the knees a little soft (a negative X bends the shin back)
	Reach = math.rad(45), -- fallback: the upper arms forward
	Elbow = math.rad(25), -- fallback: the elbows bent
	Inward = math.rad(6), -- fallback: the arms turned in toward the bar
	MaxPitch = math.rad(110), -- the shoulder's forward swing at most
	MaxYaw = math.rad(40), -- the arm turned in or out at most
	MaxElbow = math.rad(140),
}

-- 6.10, the wheelie (shared/ScooterRide.luau: the deck pitched back round the rear axle, the rider on it tips back
-- with it): the knees bend and come forward, the hips drop, the upper body sits up over them; the hands stay on the
-- bar (RiderPose.armIk reaches the grips wherever they are). Blended in by how far up it is (RiderPose.uprightAt).
RiderPose.Wheelie = {
	Lean = math.rad(-2), -- the waist (Upright's -8: the forward lean eases off, the body sits back with the deck)
	Thigh = math.rad(20), -- both thighs forward of the standing legs
	Knee = math.rad(-34), -- the knees bent (the shins back)
}

-- The standing rider's waist lean, thighs (both hips, before the stagger) and knees with the wheelie `k` (0 on both
-- wheels … 1 up), radians about X.
function RiderPose.uprightAt(k: number): (number, number, number)
	local u, w = RiderPose.Upright, RiderPose.Wheelie
	local x = math.clamp(k, 0, 1)
	return u.Lean + (w.Lean - u.Lean) * x, w.Thigh * x, u.Knee + (w.Knee - u.Knee) * x
end

-- A two-bone arm reaching a point (pure): `dx, dy, dz` the grip from the shoulder in the shoulder joint's parent frame
-- (+X right, +Y up, -Z forward), `upper` / `lower` the bones' lengths (shoulder→elbow, elbow→grip). Returns the
-- shoulder's pitch (about X: 0 hangs straight down, positive swings forward), its yaw (about Y, applied first, as
-- BikeRider composes Angles(0, yaw, 0) * Angles(pitch, 0, 0)) and the elbow's bend (about X, positive bends the forearm
-- forward). A point out of reach is reached as far as the arm goes (straight toward it).
function RiderPose.armIk(dx: number, dy: number, dz: number, upper: number, lower: number): (number, number, number)
	local u = RiderPose.Upright
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-4 or upper <= 0 or lower <= 0 then
		return u.Reach, 0, u.Elbow
	end
	local reach = math.clamp(d, math.abs(upper - lower) + 1e-3, upper + lower - 1e-3)
	-- The bend: reach^2 = upper^2 + lower^2 + 2 upper lower cos(bend) (bend 0: the arm straight).
	local cosBend = math.clamp((reach * reach - upper * upper - lower * lower) / (2 * upper * lower), -1, 1)
	local bend = math.acos(cosBend)
	-- The chord's direction: pitch from straight down, yaw from the forward half (-Z).
	local chordPitch = math.acos(math.clamp(-dy / d, -1, 1))
	local yaw = if chordPitch > 1e-3 then math.atan2(-dx, -dz) else 0
	-- The upper arm sits below the chord by the triangle's angle at the shoulder (the forearm bends forward and up).
	local alpha = math.atan2(lower * math.sin(bend), upper + lower * math.cos(bend))
	local pitch = math.clamp(chordPitch - alpha, -0.5, u.MaxPitch)
	return pitch, math.clamp(yaw, -u.MaxYaw, u.MaxYaw), math.clamp(bend, 0, u.MaxElbow)
end

-- The pose this frame: stand (the E-Scooter) or pedal with the crank at `crank` radians.
function RiderPose.pose(stand: boolean, crank: number): Pose
	if stand then
		local s = RiderPose.Stand
		return {
			waist = a(s.Lean),
			rightHip = a(s.Thigh - s.Stagger),
			rightKnee = a(s.Knee),
			leftHip = a(s.Thigh + s.Stagger),
			leftKnee = a(s.Knee),
			rightShoulder = a(s.Reach, s.Inward),
			leftShoulder = a(s.Reach, -s.Inward),
			elbow = a(s.Elbow),
		}
	end
	local p = RiderPose.Pedal
	local pump = math.sin(crank)
	return {
		waist = a(p.Lean),
		rightHip = a(p.Thigh + p.Pump * pump),
		rightKnee = a(-p.Knee * pump),
		leftHip = a(p.Thigh - p.Pump * pump),
		leftKnee = a(p.Knee * pump),
		rightShoulder = a(p.Reach, p.Inward),
		leftShoulder = a(p.Reach, -p.Inward),
		elbow = a(p.Elbow),
	}
end

return RiderPose
