--!strict
-- 6.16, the body sways (the owner: "upgrade the visuals and the feel"): every player's car near the camera rolls out of
-- a turn, dips its nose on the brake, squats as it pulls away and sinks as it lands (shared/Suspension.luau's springs,
-- Config.DriveFeel.Sway). It writes the Transform of the car's Motor6D "BodyRoll" (server/Vehicles.luau: the body's
-- looks hang on it; the hull, the wheels and the seats stay on the chassis, the driving's physics are as they were)
-- from how the chassis moves: sideways (its speed along the nose × how fast it turns), along the nose (how fast that
-- speed changes) and up. Every frame, from client/CarVisuals.luau's perCar hook: your car's numbers smoothed over
-- Sway.Smooth, another player's over Sway.SmoothOthers (their speed arrives over the network in steps). Within
-- Sway.Range of the camera (a phone: DeviceBudget.range); further away the body rests (written once).
-- CarSway.motion(car) shares the smoothed numbers with client/TyreFx.luau and client/CrashFx.luau (a bike too: it has
-- no BodyRoll, its motion is still worked out).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Suspension = require(Shared:WaitForChild("Suspension"))

local CarVisuals = require(script.Parent.CarVisuals)
local DeviceBudget = require(script.Parent.DeviceBudget)

local CarSway = {}

local Sway = Config.DriveFeel.Sway
local LOOK_AGAIN = 2 -- seconds: a car without a BodyRoll (a bike, a bandit's) is looked at again this often
local SPIKE = 400 -- studs/s²: more than this in one frame is a hit or a jump of the picture; it counts as this
local SWEEP_EVERY = 5 -- seconds between forgetting the cars that are gone

export type Motion = {
	forward: number, -- studs/s along the nose (this frame)
	accel: number, -- studs/s² along the nose, smoothed (< 0: slowing down while going forward)
	lateral: number, -- studs/s² toward the car's left, smoothed
	lift: number, -- studs/s² up, smoothed
	slide: number, -- studs/s sideways (this frame; the ice, the snow)
	speed: number, -- studs/s over the ground (this frame)
	at: number, -- os.clock() of this frame
}

type Entry = {
	motor: Motor6D?,
	lookedAt: number,
	tune: Suspension.Tune,
	state: Suspension.State,
	motion: Motion,
	lastVy: number,
	fresh: boolean, -- no frame before this one: no acceleration yet
	resting: boolean, -- written at rest
}

local entries: { [Model]: Entry } = {}
local sweepAt = 0

local function entryOf(car: Model): Entry
	local entry = entries[car]
	if entry then
		return entry
	end
	local made: Entry = {
		motor = nil,
		lookedAt = -math.huge,
		tune = Suspension.tune(nil),
		state = Suspension.new(),
		motion = { forward = 0, accel = 0, lateral = 0, lift = 0, slide = 0, speed = 0, at = 0 },
		lastVy = 0,
		fresh = true,
		resting = true,
	}
	entries[car] = made
	return made
end

-- How the car moves, smoothed (nil: not near enough to be worked out this frame).
function CarSway.motion(car: Model): Motion?
	local entry = entries[car]
	if not entry or entry.fresh or os.clock() - entry.motion.at > 0.25 then
		return nil
	end
	return entry.motion
end

local function rest(entry: Entry, motor: Motor6D?)
	if not entry.resting then
		entry.resting = true
		Suspension.reset(entry.state)
		if motor then
			motor.Transform = CFrame.identity
		end
	end
end

local function step(car: Model, chassis: BasePart, dt: number, distance: number, mine: boolean)
	local now = os.clock()
	if now > sweepAt then
		sweepAt = now + SWEEP_EVERY
		for known in entries do
			if known.Parent == nil then
				entries[known] = nil
			end
		end
	end
	local entry = entryOf(car)
	local motor = entry.motor
	if (motor == nil or motor.Parent ~= chassis) and now - entry.lookedAt > LOOK_AGAIN then
		entry.lookedAt = now
		local found = chassis:FindFirstChild("BodyRoll")
		motor = if found and found:IsA("Motor6D") then found else nil
		entry.motor = motor
		entry.resting = motor == nil
		if motor then
			local style = motor:GetAttribute("Style")
			entry.tune = Suspension.tune(if type(style) == "string" then style else nil)
		end
	end
	if distance > DeviceBudget.range(Sway.Range) or dt <= 0 then
		entry.fresh = true
		rest(entry, motor)
		return
	end

	-- How it moves (the tyres and the sparks read this too).
	local frame = chassis.CFrame
	local velocity = chassis.AssemblyLinearVelocity
	local forward = velocity:Dot(frame.LookVector)
	local yaw = chassis.AssemblyAngularVelocity:Dot(frame.UpVector)
	local m = entry.motion
	if entry.fresh then
		entry.fresh = false
		m.accel, m.lateral, m.lift = 0, 0, 0
	else
		local k = 1 - math.exp(-dt / (if mine then Sway.Smooth else Sway.SmoothOthers))
		local accel = math.clamp((forward - m.forward) / dt, -SPIKE, SPIKE)
		local lift = math.clamp((velocity.Y - entry.lastVy) / dt, -SPIKE, SPIKE)
		m.accel += (accel - m.accel) * k
		m.lift += (lift - m.lift) * k
		m.lateral += (forward * yaw - m.lateral) * k
	end
	m.forward = forward
	m.slide = velocity:Dot(frame.RightVector)
	m.speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	m.at = now
	entry.lastVy = velocity.Y

	-- The sway.
	if not motor or motor.Parent ~= chassis then
		return
	end
	local roll, pitch, heave = Suspension.goal(entry.tune, m.lateral, m.accel, m.lift)
	local state = entry.state
	Suspension.step(state, entry.tune, roll, pitch, heave, dt)
	if Suspension.resting(state) and math.abs(roll) + math.abs(pitch) + math.abs(heave) < 1e-4 then
		rest(entry, motor)
		return
	end
	entry.resting = false
	motor.Transform = CFrame.new(0, state.heave, 0) * CFrame.Angles(state.pitch, 0, state.roll)
end

function CarSway.start()
	table.insert(CarVisuals.perCar, step)
end

return CarSway
