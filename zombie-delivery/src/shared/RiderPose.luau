--!strict
-- 5.1.1: the rider's pose on a bike, as numbers (pure Luau: client/BikeRider.luau lays them into the R15 joints'
-- Transform over the sit animation; tests/bikes_test.luau checks them). Two poses:
-- * "pedal" (the bikes, a saddle): the upper body leans forward, both arms reach for the grips, the thighs lowered from
--   the sit toward the pedals and pumping with the crank (crank: its angle in radians).
-- * "stand" (the E-Scooter, CarDef.stand: its DriverSeat sits a hip's height over the deck, server/Vehicles.luau): the
--   legs straightened out of the sit (the thighs down, the knees opened) so the feet stand on the deck, a slight
--   forward lean, both hands on the bar, the knees a little soft; no pedalling (the crank is ignored).
-- Each joint gets rotations about X (forward is negative for the waist and the thighs: the R15 joints' own frames),
-- then Y (the arms turned in toward the bar). Angles in radians.
-- 6.19 (the owner: "make it visible how he pedals the bike, even when it's an e-bike"): the seated rider is posed
-- ABSOLUTE now, like 5.8.2's standing one (client/BikeRider.luau): the hips on the saddle (RiderPose.Ride), each foot ON
-- its pedal round the crank (RiderPose.legIk, a two-bone leg: hip -> knee -> ankle, the knee always forward), the hands
-- on the grips (RiderPose.armIk), a forward lean. The crank turns with the speed and rests one pedal forward when the
-- bike stops (RiderPose.crankStep; the E-Bike calmer). RiderPose.pose's "pedal" numbers stay only as the end of the
-- mount move (shared/InteractPose.luau bikeMount), not the ride.

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

-- 6.19: the pedalling rider, absolute (client/BikeRider.luau; distances in studs, in the bike's frame).
RiderPose.Ride = {
	Lean = math.rad(-22), -- the waist: the upper body over the bars
	HipUp = 0.42, -- the hip joints this far over the saddle's top (the classic R15's thick thighs clear it)
	HipBack = 0.08, -- ... and this far behind its middle
	AnkleBack = 0.12, -- the ankle behind the pedal's axle (the ball of the foot on the pedal)
	PedalTop = 0.04, -- the pedal's top over its axle
	Toe = math.rad(-8), -- the foot's toes a touch down
	Ankling = math.rad(10), -- ... more as the pedal goes down the front
	MaxRoll = math.rad(20), -- a thigh turned out or in at most
	MaxKnee = math.rad(150), -- the knee bent at most
	-- The crank (RiderPose.crankStep): turns per stud ridden (5.1's 0.42 per 1.3-stud wheel turn), the E-Bike's share of
	-- it, at most MaxCrank rad/s; under RestSpeed studs/s it settles (RestRate per second) to one pedal forward.
	Cadence = 0.42 / 1.3,
	Calm = 0.72,
	MaxCrank = 12,
	RestSpeed = 0.6,
	RestRate = 5,
}

-- 6.19: a two-bone leg reaching a point (pure): `dx, dy, dz` the ankle's target from the hip in the hip joint's parent
-- frame (+X right, +Y up, -Z forward), `thigh` / `shin` the bones (hip->knee, knee->ankle). Returns the hip's pitch
-- (about X: 0 hangs straight down, positive swings the thigh forward), its roll (about Z, applied first:
-- client/BikeRider.luau composes Angles(0, 0, roll) * Angles(pitch, 0, 0); positive moves the foot to +X) and the
-- knee's angle (about X, never positive: the shin bends back, the knee stays forward). A point out of reach is reached
-- as far as the leg goes.
function RiderPose.legIk(dx: number, dy: number, dz: number, thigh: number, shin: number): (number, number, number)
	local r = RiderPose.Ride
	if thigh <= 0 or shin <= 0 or dx * dx + dy * dy + dz * dz < 1e-8 then
		return 0, 0, 0
	end
	-- The leg's plane: turned about Z so the target lies in it (Y-Z), the turn kept small.
	local roll = math.clamp(math.atan2(dx, -dy), -r.MaxRoll, r.MaxRoll)
	local ty = -dx * math.sin(roll) + dy * math.cos(roll)
	local d = math.sqrt(ty * ty + dz * dz)
	local reach = math.clamp(d, math.abs(thigh - shin) + 1e-3, thigh + shin - 1e-3)
	-- The bend: reach^2 = thigh^2 + shin^2 + 2 thigh shin cos(bend) (0: the leg straight).
	local bend = math.acos(math.clamp((reach * reach - thigh * thigh - shin * shin) / (2 * thigh * shin), -1, 1))
	bend = math.min(bend, r.MaxKnee)
	-- The chord's pitch from straight down; the thigh ahead of it by the triangle's angle at the hip (the knee forward).
	local chord = math.atan2(-dz, -ty)
	local alpha = math.atan2(shin * math.sin(bend), thigh + shin * math.cos(bend))
	return chord + alpha, roll, -bend
end

-- 6.19: the ankle's angle that keeps the foot on its pedal: level with the bike (the thigh's pitch and the knee undone)
-- with the toes a touch down, more on the way down the front of the stroke (`crank`: this pedal's angle, 0 at its top,
-- -pi/2 forward: the crank turns down from the front as the bike rolls on).
function RiderPose.ankle(pitch: number, knee: number, crank: number): number
	local r = RiderPose.Ride
	return -(pitch + knee) + r.Toe - r.Ankling * math.max(0, -math.sin(crank))
end

-- 6.19: the crank's angle after `dt` seconds at `forward` studs/s (client/CarVisuals.luau; `calm`: the E-Bike's motor
-- helps, a calmer cadence). Under Ride.RestSpeed it settles to the nearest rest: one pedal forward, level (the
-- right one at -pi/2 + k*pi). Kept within one turn.
function RiderPose.crankStep(crank: number, forward: number, dt: number, calm: boolean?): number
	local r = RiderPose.Ride
	local out: number
	if math.abs(forward) < r.RestSpeed then
		local rest = math.floor((crank + math.pi / 2) / math.pi + 0.5) * math.pi - math.pi / 2
		out = crank + (rest - crank) * math.min(1, dt * r.RestRate)
	else
		local rate = math.clamp(forward * r.Cadence * (if calm then r.Calm else 1), -r.MaxCrank, r.MaxCrank)
		out = crank - rate * dt
	end
	return out % (2 * math.pi)
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
