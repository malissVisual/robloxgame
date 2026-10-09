--!strict
-- 6.10: the E-Scooter's ride, the pure part (no Roblox at its top level, so tests/scooter_test.luau runs it in the
-- standalone Luau; the numbers are Config.Scooter and Config.Interact's Scooter… ones). A ZDC RIDE rental is the same
-- scooter. Used by client/Drive.luau (the handling of your own scooter), client/CarVisuals.luau (the lean everybody
-- sees) and client/CarBoarding.luau (the hop on and off). (6.14.2: the 6.10 wheelie is gone, the owner: "take the
-- wheelie away, it looks silly".)
--
--   ScooterRide.turnRate(speed, maxSpeed, turn)   how fast it turns (rad/s) at `speed`: LowTurn of the car's `turn` at
--                                                  walking pace easing to HighTurn at its top speed, faded in from a stand
--   ScooterRide.steerStep(current, input, dt)     the steering ramped toward the key (or the stick): no snap, quick back
--   ScooterRide.drive(speed, throttle, maxSpeed, accel)   the speed it heads for and how fast (the brake, the coast)
--   ScooterRide.pull(share)                       6.14.1: the share of the pull at a share of the top speed (Config.Scooter
--                                                  Pull: a soft first push, a glide into the top speed)
--   ScooterRide.carve(dt)                         6.14.1: how much of the way to its nose the motion turns in a step
--   ScooterRide.lean(yawRate, forward)            the lean into a turn (radians, the look only)
--   ScooterRide.hop(u)                            the hop onto the deck (or off it): the share of the way, the arc, the turn

local Config = require(script.Parent.Config)

local ScooterRide = {}

local function smooth(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end

local function toward(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

-- The turn rate (rad/s, never negative) at `speed` (studs/s, either way), for a scooter whose CarDef.turn is `turn` and
-- top speed `maxSpeed`.
function ScooterRide.turnRate(speed: number, maxSpeed: number, turn: number): number
	local cfg = Config.Scooter
	local s = math.abs(speed)
	local grip = math.clamp(s / math.max(0.1, cfg.GripSpeed), 0, 1)
	local ease = smooth((s - cfg.EaseFrom) / math.max(1, maxSpeed - cfg.EaseFrom))
	return turn * (cfg.LowTurn + (cfg.HighTurn - cfg.LowTurn) * ease) * grip
end

-- The steering (-1 … 1) one step toward `input` (a key's full lock, or a stick's share): out at SteerIn, back to the
-- middle at the quicker SteerOut (the other way: through the middle first).
function ScooterRide.steerStep(current: number, input: number, dt: number): number
	local cfg = Config.Scooter
	local goal = math.clamp(input, -1, 1)
	if current * goal < 0 then
		return toward(current, 0, cfg.SteerOut * dt)
	end
	local rate = if math.abs(goal) > math.abs(current) then cfg.SteerIn else cfg.SteerOut
	return toward(current, goal, rate * dt)
end

-- 6.14.1: the share of the pull (× Accel) at `share` of the top speed: Start at a stand rising to all of it at Full, all
-- of it up to Ease, then down to Top at the top speed (and past it).
function ScooterRide.pull(share: number): number
	local p = Config.Scooter.Pull
	local s = math.max(0, share)
	if s < p.Full then
		return p.Start + (1 - p.Start) * smooth(s / math.max(1e-3, p.Full))
	elseif s <= p.Ease then
		return 1
	end
	return 1 + (p.Top - 1) * smooth((s - p.Ease) / math.max(1e-3, 1 - p.Ease))
end

-- 6.14.1: the share of the way from where it moves to where its nose points that one step of `dt` turns (Carve 1/s).
function ScooterRide.carve(dt: number): number
	return 1 - math.exp(-Config.Scooter.Carve * math.max(0, dt))
end

-- The speed the scooter heads for (studs/s along its nose) and the rate it gets there (studs/s²): the pull of `accel`
-- (electric: no torque curve; 6.14.1: a soft first push and a glide into the top speed, ScooterRide.pull), the brake
-- on S while rolling forward, a long coast with no key, a slow walk back on S from a stand.
function ScooterRide.drive(speed: number, throttle: number, maxSpeed: number, accel: number): (number, number)
	local cfg = Config.Scooter
	if throttle > 0 then
		if speed < -1 then
			return maxSpeed * throttle, cfg.Brake -- (rolling back: W brakes first)
		end
		return maxSpeed * throttle, accel * ScooterRide.pull(speed / math.max(1, maxSpeed))
	elseif throttle < 0 then
		if speed > 1 then
			return maxSpeed * cfg.Reverse * throttle, cfg.Brake
		end
		return maxSpeed * cfg.Reverse * throttle, accel
	end
	return 0, cfg.Coast
end

-- The lean into a turn (radians about the scooter's length, as client/CarVisuals.luau's BikeLean takes it: positive
-- leans left, into a left turn): by how fast it turns (rad/s about up) at its forward speed.
function ScooterRide.lean(yawRate: number, forward: number): number
	local cfg = Config.Scooter
	return math.clamp(yawRate * forward * cfg.LeanRate, -cfg.LeanMax, cfg.LeanMax)
end

-- ── The hop on (and off) ────────────────────────────────────────────────────

-- The hop at u (0 … 1 of the move; getting off plays it from the deck to the ground): the share of the way along
-- (quick off the ground, soft at the end), the arc up (studs, the most halfway) and the share of the turn to the end's
-- facing (done by 70%).
function ScooterRide.hop(u: number): (number, number, number)
	local x = math.clamp(u, 0, 1)
	local k = x * (2 - x)
	local lift = Config.Interact.ScooterArc * math.sin(math.pi * x)
	return k, lift, smooth(x / 0.7)
end

return ScooterRide
