--!strict
-- 6.16, the cars' visual suspension (the owner: "upgrade the visuals and the feel"): the pure maths of a body that sways
-- on its springs. Pure (no Roblox at its top level; tests/suspension_test.luau runs it in the plain Luau CLI). Numbers in
-- Config.DriveFeel.Sway.
--   * Suspension.tune(style): the springs of a car's style (its Soft share: a box truck or a bus sways more and
--     slower, the muscle car less and stiffer).
--   * Suspension.goal(tune, lateral, forward, vertical): where the body wants to sit for what it feels (studs/s²;
--     lateral: toward the car's left, forward: along its nose, vertical: up). It rolls OUT of a turn, dips its nose on
--     the brake, squats as it pulls away and sinks as it lands, each capped. Returns roll (radians about the car's
--     length: < 0 leans the roof to the right), pitch (radians about its width: < 0 dips the nose) and heave (studs up).
--   * Suspension.step(state, tune, roll, pitch, heave, dt): a spring-damper toward that goal (under-damped: it rocks
--     back once after a hard stop), in small steps however long the frame, so it always settles and never blows up.
--   * Suspension.new() / Suspension.resting(state): a body at rest / is it (near enough)?
-- client/CarSway.luau writes the result into the car's Motor6D "BodyRoll" (server/Vehicles.luau): only the look; the
-- hull, the wheels and the seats stay on the chassis.

local Config = require(script.Parent.Config)

local Suspension = {}

local Sway = Config.DriveFeel.Sway
local MAX_STEP = 1 / 120 -- seconds: the longest step of the spring (a long frame is cut into these)
local MAX_FRAME = 0.1 -- seconds: a longer frame (a hitch) counts as this long

export type Tune = {
	roll: number, -- radians of roll per stud/s² sideways
	dive: number, -- radians of pitch per stud/s² of braking
	squat: number, -- radians of pitch per stud/s² of pulling away
	sink: number, -- studs per stud/s² upward
	rollMax: number,
	pitchMax: number,
	heaveMax: number,
	k: number, -- the spring (1/s²)
	c: number, -- the damper (1/s)
}

export type State = {
	roll: number,
	rollSpeed: number,
	pitch: number,
	pitchSpeed: number,
	heave: number,
	heaveSpeed: number,
}

function Suspension.new(): State
	return { roll = 0, rollSpeed = 0, pitch = 0, pitchSpeed = 0, heave = 0, heaveSpeed = 0 }
end

-- The springs of a style (nil: a plain car).
function Suspension.tune(style: string?): Tune
	local soft = (if style then Sway.Soft[style] else nil) or 1
	local omega = 2 * math.pi * Sway.Frequency / math.sqrt(soft)
	return {
		roll = math.rad(Sway.Roll) / Sway.RollAt * soft,
		dive = math.rad(Sway.Dive) / Sway.DiveAt * soft,
		squat = math.rad(Sway.Squat) / Sway.SquatAt * soft,
		sink = Sway.Sink / Sway.SinkAt * soft,
		rollMax = math.rad(Sway.RollMax) * math.min(soft, 1.25),
		pitchMax = math.rad(Sway.PitchMax) * math.min(soft, 1.25),
		heaveMax = Sway.HeaveMax,
		k = omega * omega,
		c = 2 * Sway.Damping * omega,
	}
end

function Suspension.goal(tune: Tune, lateral: number, forward: number, vertical: number): (number, number, number)
	local roll = math.clamp(-lateral * tune.roll, -tune.rollMax, tune.rollMax)
	local pitch = math.clamp(forward * (if forward >= 0 then tune.squat else tune.dive), -tune.pitchMax, tune.pitchMax)
	local heave = math.clamp(-vertical * tune.sink, -tune.heaveMax, tune.heaveMax)
	return roll, pitch, heave
end

function Suspension.step(state: State, tune: Tune, roll: number, pitch: number, heave: number, dt: number)
	local frame = math.clamp(dt, 0, MAX_FRAME)
	local steps = math.max(1, math.ceil(frame / MAX_STEP))
	local h = frame / steps
	local k, c = tune.k, tune.c
	for _ = 1, steps do
		-- semi-implicit Euler: the speed first, then the place from the new speed (stable at these steps)
		state.rollSpeed += (k * (roll - state.roll) - c * state.rollSpeed) * h
		state.roll += state.rollSpeed * h
		state.pitchSpeed += (k * (pitch - state.pitch) - c * state.pitchSpeed) * h
		state.pitch += state.pitchSpeed * h
		state.heaveSpeed += (k * (heave - state.heave) - c * state.heaveSpeed) * h
		state.heave += state.heaveSpeed * h
	end
	-- the overshoot stays within half a cap more (a body never folds over, whatever it hit)
	state.roll = math.clamp(state.roll, -tune.rollMax * 1.5, tune.rollMax * 1.5)
	state.pitch = math.clamp(state.pitch, -tune.pitchMax * 1.5, tune.pitchMax * 1.5)
	state.heave = math.clamp(state.heave, -tune.heaveMax * 1.5, tune.heaveMax * 1.5)
end

-- At rest (nothing worth drawing: under a hundredth of a degree and a thousandth of a stud, barely moving).
function Suspension.resting(state: State): boolean
	local still = 2e-4
	return math.abs(state.roll) < still and math.abs(state.pitch) < still and math.abs(state.heave) < 1e-3
		and math.abs(state.rollSpeed) < still and math.abs(state.pitchSpeed) < still and math.abs(state.heaveSpeed) < 1e-3
end

-- Back to rest at once (a car out of range).
function Suspension.reset(state: State)
	state.roll, state.rollSpeed, state.pitch, state.pitchSpeed, state.heave, state.heaveSpeed = 0, 0, 0, 0, 0, 0
end

return Suspension
