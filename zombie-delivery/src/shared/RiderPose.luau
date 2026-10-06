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
