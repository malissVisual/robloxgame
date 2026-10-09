--!strict
-- 6.10: the E-Scooter's ride, the pure part (no Roblox at its top level, so tests/scooter_test.luau runs it in the
-- standalone Luau; the numbers are Config.Scooter and Config.Interact's Scooter… ones). A ZDC RIDE rental is the same
-- scooter. Used by client/Drive.luau (the handling and the wheelie of your own scooter), client/CarVisuals.luau (the
-- lean and the wheelie's pitch everybody sees) and client/CarBoarding.luau (the hop on and off).
--
--   ScooterRide.turnRate(speed, maxSpeed, turn)   how fast it turns (rad/s) at `speed`: LowTurn of the car's `turn` at
--                                                  walking pace easing to HighTurn at its top speed, faded in from a stand
--   ScooterRide.steerStep(current, input, dt)     the steering ramped toward the key (or the stick): no snap, quick back
--   ScooterRide.drive(speed, throttle, maxSpeed, accel)   the speed it heads for and how fast (the brake, the coast)
--   ScooterRide.pull(share)                       6.14.1: the share of the pull at a share of the top speed (Config.Scooter
--                                                  Pull: a soft first push, a glide into the top speed)
--   ScooterRide.carve(dt)                         6.14.1: how much of the way to its nose the motion turns in a step
--   ScooterRide.lean(yawRate, forward)            the lean into a turn (radians, the look only)
--   ScooterRide.wheelie() / wheelieStep(w, held, speed, braking, dt)   the wheelie: up while the key is held, rolling and
--                                                  not braking, down after MaxSeconds by itself (then let go, Cooldown)
--   ScooterRide.knock(w)                          a heavy hit: the wheelie comes down
--   ScooterRide.amountStep(amount, up, dt)        how far up it is drawn (0 … 1: Pop seconds up, Drop down)
--   ScooterRide.pitch(amount, time)               the deck's pitch back round the rear axle (radians, with the wobble)
--   ScooterRide.speedFactor(amount) / turnFactor(amount)   the top speed and the steering while up
--   ScooterRide.hop(u)                            the hop onto the deck (or off it): the share of the way, the arc, the turn

local Config = require(script.Parent.Config)

local ScooterRide = {}

export type Wheelie = {
	up: boolean, -- on the back wheel now (the server is told when this changes)
	time: number, -- seconds up
	rest: number, -- seconds before it may pop again
	armed: boolean, -- the key was let go since the last drop (or since getting on)
	amount: number, -- how far up it is drawn (0 … 1)
	held: number, -- 6.14.1: seconds the key has been held while armed (it pops at Config.Scooter.Wheelie.Hold)
}

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

-- ── The wheelie ─────────────────────────────────────────────────────────────

function ScooterRide.wheelie(): Wheelie
	return { up = false, time = 0, rest = 0, armed = false, amount = 0, held = 0 }
end

-- How far up it is drawn, one step on toward up (1) or down (0).
function ScooterRide.amountStep(amount: number, up: boolean, dt: number): number
	local cfg = Config.Scooter.Wheelie
	if up then
		return math.min(1, amount + dt / math.max(1e-3, cfg.Pop))
	end
	return math.max(0, amount - dt / math.max(1e-3, cfg.Drop))
end

-- One step of the wheelie: `held` the key, `speed` along the nose (studs/s), `braking` S while rolling forward. Up
-- when the key is held (pressed again since the last drop; 6.14.1: for Hold seconds, a tap is nothing), rolling at
-- MinSpeed or more and not braking; down when it is let go, on the brake, under DropSpeed or after MaxSeconds (the
-- balance). Returns whether `up` changed.
function ScooterRide.wheelieStep(w: Wheelie, held: boolean, speed: number, braking: boolean, dt: number): boolean
	local cfg = Config.Scooter.Wheelie
	local was = w.up
	w.rest = math.max(0, w.rest - dt)
	if not held then
		w.armed = true
		w.held = 0
	elseif w.armed and not w.up then
		w.held += dt
	end
	if w.up then
		w.time += dt
		if not held or braking or speed < cfg.DropSpeed or w.time >= cfg.MaxSeconds then
			w.up = false
			w.rest = cfg.Cooldown
			w.armed = false
		end
	elseif held and w.armed and w.rest <= 0 and not braking and speed >= cfg.MinSpeed and w.held >= (cfg.Hold or 0) - 1e-9 then
		w.up = true
		w.time = 0
	end
	w.amount = ScooterRide.amountStep(w.amount, w.up, dt)
	return w.up ~= was
end

-- A knock (the scooter hit something heavy: client/Drive.luau's bump): the balance is gone, it comes down next step.
function ScooterRide.knock(w: Wheelie)
	if w.up then
		w.time = math.max(w.time, Config.Scooter.Wheelie.MaxSeconds)
	end
end

-- The deck's pitch back round the rear axle (radians, positive lifts the front): Angle eased by how far up it is, and
-- the balance's wobble (a third of Wobble at the start, all of it at MaxSeconds) `time` seconds after it went up.
function ScooterRide.pitch(amount: number, time: number): number
	local cfg = Config.Scooter.Wheelie
	local a = math.clamp(amount, 0, 1)
	if a <= 0 then
		return 0
	end
	local t = math.clamp(time, 0, 600) -- (never a NaN from a huge time)
	local late = math.clamp(t / math.max(0.1, cfg.MaxSeconds), 0, 1)
	local wobble = math.rad(cfg.Wobble) * (1 + 2 * late) / 3 * math.sin(2 * math.pi * cfg.WobbleHz * t)
	return math.rad(cfg.Angle) * smooth(a) + wobble * a
end

-- The top speed's factor while up (amount: how far up).
function ScooterRide.speedFactor(amount: number): number
	return 1 + Config.Scooter.Wheelie.SpeedBonus * math.clamp(amount, 0, 1)
end

-- The steering's factor while up.
function ScooterRide.turnFactor(amount: number): number
	return 1 + (Config.Scooter.Wheelie.Turn - 1) * math.clamp(amount, 0, 1)
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
