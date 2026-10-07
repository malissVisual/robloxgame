--!strict
-- 6.1: the plastic bag in your hand as a pendulum on a spring, the pure part (no Roblox: tests/bagswing_test.luau runs it
-- in the standalone Luau). client/BagSway.luau feeds it every frame, for every character within Config.Courier.Bag's
-- Range, and turns what it returns into the BagSwing joint's Transform.
--
-- The swing is a small-angle vector (x, z: radians, the way the bag's BOTTOM has moved from hanging straight below the
-- hand, in the world's flat plane) on a damped spring (Spring = ω², Damp) around a goal:
--   * the acceleration: the hand speeding up pushes the goal back (Kick × the acceleration, as a real pendulum hangs
--     back at a / g), so it trails when you start, swings forward when you stop and out on a turn (the turn's pull);
--     the acceleration is the body's (its root's velocity, smoothed) plus HandShare of the hand's own (its grip's
--     position, differentiated), so the arms pumping in a sprint rock it without throwing it around;
--   * the air: the speed leans it back (Drag × speed², along the way you move).
-- At speed it flutters a little (Flutter degrees at FullSpeed, FlutterHz, along and across the way) and twists about
-- its handles (Twist). The tilt never goes over MaxTilt. A step larger than MAX_DT is cut short (a hitch), the spring
-- is integrated in SUB steps (semi-implicit Euler: stable for any frame rate), and the hand moving faster than Teleport
-- (a respawn, a seat) starts the swing again (`primed` off: the next step only learns where the hand is).
--
--   BagSwing.new()                                  a hanging bag
--   BagSwing.step(state, dt, hand, body, tuning)    hand = the grip's world position { x, y, z }, body = the body's
--                                                   velocity { x, y, z }; returns the tilt (x, z, radians) and the twist
--                                                   (radians about the handles)
--   BagSwing.tilt(state)                            the current tilt's size (radians)

local BagSwing = {}

export type Vec = { number }
export type Tuning = {
	Spring: number,
	Damp: number,
	Kick: number,
	HandShare: number,
	MaxAccel: number,
	Smooth: number,
	Drag: number,
	MaxTilt: number,
	FullSpeed: number,
	FlutterHz: number,
	Flutter: number,
	Twist: number,
	Teleport: number,
}
export type State = {
	x: number, -- the swing (radians, where the bottom has moved) …
	z: number,
	vx: number, -- … and its rate
	vz: number,
	hx: number, -- the hand's last position (flat)
	hz: number,
	hvx: number, -- the hand's smoothed velocity
	hvz: number,
	bvx: number, -- the body's smoothed velocity
	bvz: number,
	phase: number, -- the flutter's
	primed: boolean, -- the hand's position is known (a step can differentiate)
}

local MAX_DT = 0.1 -- seconds: a longer frame (a hitch) counts as this
local SUB = 1 / 120 -- seconds: the spring's integration step at most
local TAU = 2 * math.pi

function BagSwing.new(): State
	return { x = 0, z = 0, vx = 0, vz = 0, hx = 0, hz = 0, hvx = 0, hvz = 0, bvx = 0, bvz = 0, phase = 0, primed = false }
end

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

-- (x, z) no longer than `max`.
local function clampFlat(x: number, z: number, max: number): (number, number)
	local size = math.sqrt(x * x + z * z)
	if size > max and size > 0 then
		return x * max / size, z * max / size
	end
	return x, z
end

function BagSwing.tilt(state: State): number
	return math.sqrt(state.x * state.x + state.z * state.z)
end

function BagSwing.step(state: State, dt: number, hand: Vec, body: Vec, t: Tuning): (number, number, number)
	if not finite(dt) or dt <= 0 then
		return state.x, state.z, 0
	end
	dt = math.min(dt, MAX_DT)
	local px, pz = hand[1], hand[3]
	local bx, bz = body[1], body[3]
	if not (finite(px) and finite(pz) and finite(bx) and finite(bz)) then
		return state.x, state.z, 0
	end
	-- The hand's velocity from its position (a jump: the swing starts again from hanging).
	local hvx, hvz = 0, 0
	if state.primed then
		hvx, hvz = (px - state.hx) / dt, (pz - state.hz) / dt
		if hvx * hvx + hvz * hvz > t.Teleport * t.Teleport then
			state.primed = false
		end
	end
	state.hx, state.hz = px, pz
	if not state.primed then
		state.primed = true
		state.x, state.z, state.vx, state.vz = 0, 0, 0, 0
		state.hvx, state.hvz, state.bvx, state.bvz = bx, bz, bx, bz
		return 0, 0, 0
	end
	-- Smoothed velocities and their change: the accelerations.
	local k = math.clamp(dt / math.max(t.Smooth, dt), 0, 1)
	local nhx, nhz = state.hvx + (hvx - state.hvx) * k, state.hvz + (hvz - state.hvz) * k
	local nbx, nbz = state.bvx + (bx - state.bvx) * k, state.bvz + (bz - state.bvz) * k
	local ahx, ahz = (nhx - state.hvx) / dt, (nhz - state.hvz) / dt
	local abx, abz = (nbx - state.bvx) / dt, (nbz - state.bvz) / dt
	state.hvx, state.hvz, state.bvx, state.bvz = nhx, nhz, nbx, nbz
	local ax, az = clampFlat(abx + (ahx - abx) * t.HandShare, abz + (ahz - abz) * t.HandShare, t.MaxAccel)
	-- The goal: back against the acceleration, back along the way by the air.
	local speed = math.sqrt(nbx * nbx + nbz * nbz)
	local gx, gz = -ax * t.Kick, -az * t.Kick
	if speed > 0.01 then
		local lean = t.Drag * speed * speed
		gx -= nbx / speed * lean
		gz -= nbz / speed * lean
	end
	local maxTilt = math.rad(t.MaxTilt)
	gx, gz = clampFlat(gx, gz, maxTilt)
	-- The damped spring toward it.
	local left = dt
	while left > 1e-6 do
		local h = math.min(SUB, left)
		left -= h
		state.vx += (t.Spring * (gx - state.x) - t.Damp * state.vx) * h
		state.vz += (t.Spring * (gz - state.z) - t.Damp * state.vz) * h
		state.x += state.vx * h
		state.z += state.vz * h
	end
	state.x, state.z = clampFlat(state.x, state.z, maxTilt)
	-- The flutter at speed: along the way and a little across, and the twist about the handles.
	local fast = math.clamp(speed / math.max(t.FullSpeed, 1), 0, 1)
	state.phase = (state.phase + dt * t.FlutterHz * TAU * math.max(0.3, fast)) % (TAU * 64)
	local x, z = state.x, state.z
	local twist = 0
	if fast > 0.3 and speed > 0.01 then
		local amount = math.rad(t.Flutter) * (fast - 0.3) / 0.7
		local ux, uz = nbx / speed, nbz / speed
		local along = amount * math.sin(state.phase)
		local across = amount * 0.5 * math.sin(state.phase * 0.73 + 1.1)
		x += ux * along - uz * across
		z += uz * along + ux * across
		twist = math.rad(t.Twist) * (fast - 0.3) / 0.7 * math.sin(state.phase * 0.61 + 0.4)
	end
	x, z = clampFlat(x, z, maxTilt)
	return x, z, twist
end

return BagSwing
