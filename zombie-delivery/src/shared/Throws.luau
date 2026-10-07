--!strict
-- 6.0: throwing a delivery at a home's door, the pure part (no Roblox at its top level: tests/throws_test.luau runs it
-- in the standalone Luau). The client aims and draws the arc with it (client/Throw.luau), the server traces the same
-- arc to decide where the piece lands (server/Cargo.luau); both give `trace` their own raycast (`cast`), so the
-- preview and the outcome come from one piece of maths. Config.Throw has the numbers.
--
--   Throws.release(pos, look)        where the piece leaves the hand: from the body's position, its facing (flat)
--   Throws.aim(look)                 the throw's direction from the camera's look: its flat way, lifted by Lift and
--                                    kept within MinUp … MaxUp degrees over the flat (nil looking straight up / down)
--   Throws.charge(held)              the power 0 … 1 after holding `held` seconds (up over ChargeTime, back, again)
--   Throws.velocity(direction, power)  the launch velocity: the direction made unit and kept within MinUp … MaxUp,
--                                    MinSpeed … MaxSpeed by the power (nil for a broken direction)
--   Throws.trace(origin, velocity, cast)  the arc, Step by Step under Gravity for at most MaxTime: a surface facing up
--                                    (GroundNormal) is where it lands, a wall sends it back once (Bounce, MaxBounces),
--                                    after that it slides down it. points / times along it, land, time, bounced
--   Throws.at(trace, t)              the position `t` seconds into the flight (the flying piece)
--   Throws.flat(a, b)                the distance over the ground (x, z)
--   Throws.landed(land, door)        within DoorRadius of the door (flat, and not a floor away)
--   Throws.tip(distance, over, wall) the TRICKSHOT tip: far (FarFrom … Range: FarMin … FarMax), over (OverTip), off a
--                                    wall (WallTip) and their total
--   6.2, the auto-aim (the owner: "auto aim, and a perfect hit gets a bigger tip from the customer"):
--   Throws.solve(from, door, angle)  the launch speed that lands on the door's spot at `angle` degrees over the flat
--                                    (no air, no walls: the parabola), nil when that angle can't reach it
--   Throws.powerFor(speed)           the power 0 … 1 that throws at `speed` (nil outside MinSpeed … MaxSpeed)
--   Throws.direction(from, door, angle)  the unit way: flat toward the door, `angle` degrees up
--   Throws.landFlat(from, velocity, groundY)  where the parabola comes down to the height groundY (nil: never)
--   Throws.perfect(land, door)       within PerfectRadius of the door's spot: the customer's PERFECT tip
--   Throws.fragile(look, job)        too fragile to throw: a FragileLooks look, or every piece of a fragile job
--   Throws.throwable(look, job)      a light look (Config.Cargo.LightLooks) that is not fragile
--
-- A vector is { x, y, z } (y up); `cast(from, to)` returns the first hit on the segment ({ at, normal }) or nil.

local Config = require(script.Parent.Config)

local Throws = {}

export type Vec = { number }
export type Hit = { at: Vec, normal: Vec }
export type Cast = (from: Vec, to: Vec) -> Hit?
export type Trace = { points: { Vec }, times: { number }, land: Vec, time: number, bounced: boolean, grounded: boolean }
export type Tip = { total: number, far: number, over: number, wall: number }

local T = Config.Throw

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

local function length(v: Vec): number
	return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
end

local function distance(a: Vec, b: Vec): number
	return length({ a[1] - b[1], a[2] - b[2], a[3] - b[3] })
end

-- A direction `up` radians over the flat way (hx, hz unit), as a unit vector.
local function lifted(hx: number, hz: number, up: number): Vec
	local c = math.cos(up)
	return { hx * c, math.sin(up), hz * c }
end

function Throws.release(pos: Vec, look: Vec): Vec
	local r = T.Release
	local h = math.sqrt(look[1] * look[1] + look[3] * look[3])
	local fx, fz = if h > 1e-6 then look[1] / h else 0, if h > 1e-6 then look[3] / h else -1
	-- (the right of a flat way (fx, fz) is (-fz, fx): facing -z, the right is +x)
	return { pos[1] + fx * r.ahead - fz * r.side, pos[2] + r.up, pos[3] + fz * r.ahead + fx * r.side }
end

function Throws.aim(look: Vec): Vec?
	local h = math.sqrt(look[1] * look[1] + look[3] * look[3])
	if h < 0.05 or not finite(h) then
		return nil
	end
	local pitch = math.atan2(look[2], h)
	local up = math.clamp(pitch + math.rad(T.Lift), math.rad(T.MinUp), math.rad(T.MaxUp))
	return lifted(look[1] / h, look[3] / h, up)
end

function Throws.charge(held: number): number
	if not finite(held) or held <= 0 then
		return 0
	end
	local u = (held / T.ChargeTime) % 2
	return if u <= 1 then u else 2 - u
end

function Throws.velocity(direction: Vec, power: number): Vec?
	local x, y, z = direction[1], direction[2], direction[3]
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or not (finite(x) and finite(y) and finite(z)) then
		return nil
	end
	local h = math.sqrt(x * x + z * z)
	if h < 1e-3 then
		return nil
	end
	local up = math.clamp(math.atan2(y, h), math.rad(T.MinUp), math.rad(T.MaxUp))
	local p = if finite(power) then math.clamp(power, 0, 1) else 0
	local speed = T.MinSpeed + (T.MaxSpeed - T.MinSpeed) * p
	local unit = lifted(x / h, z / h, up)
	return { unit[1] * speed, unit[2] * speed, unit[3] * speed }
end

function Throws.trace(origin: Vec, velocity: Vec, cast: Cast?): Trace
	local g, dt = T.Gravity, T.Step
	local p: Vec = { origin[1], origin[2], origin[3] }
	local v: Vec = { velocity[1], velocity[2], velocity[3] }
	local points: { Vec } = { { p[1], p[2], p[3] } }
	local times: { number } = { 0 }
	local t = 0
	local bounces = 0
	local bounced = false
	-- (a cap on the steps: a cast that keeps hitting at once never stops the time)
	for _ = 1, math.ceil(T.MaxTime / dt) + 2 * T.MaxBounces + 8 do
		if t >= T.MaxTime then
			break
		end
		local nextP: Vec = { p[1] + v[1] * dt, p[2] + v[2] * dt - 0.5 * g * dt * dt, p[3] + v[3] * dt }
		local hit = if cast then cast(p, nextP) else nil
		if not hit then
			p = nextP
			v = { v[1], v[2] - g * dt, v[3] }
			t += dt
			table.insert(points, { p[1], p[2], p[3] })
			table.insert(times, t)
			continue
		end
		local span = distance(p, nextP)
		local f = if span > 1e-6 then math.clamp(distance(p, hit.at) / span, 0, 1) else 0
		t += dt * f
		local at: Vec = { hit.at[1], hit.at[2], hit.at[3] }
		local n = hit.normal
		if n[2] >= T.GroundNormal then
			table.insert(points, at)
			table.insert(times, t)
			return { points = points, times = times, land = at, time = t, bounced = bounced, grounded = true }
		end
		-- A wall (or a ceiling): back off it once, then down along it.
		local vv: Vec = { v[1], v[2] - g * dt * f, v[3] }
		if bounces < T.MaxBounces then
			bounces += 1
			bounced = true
			local dot = vv[1] * n[1] + vv[2] * n[2] + vv[3] * n[3]
			v = { (vv[1] - 2 * dot * n[1]) * T.Bounce, (vv[2] - 2 * dot * n[2]) * T.Bounce, (vv[3] - 2 * dot * n[3]) * T.Bounce }
		else
			v = { 0, math.min(vv[2], 0), 0 }
		end
		p = { at[1] + n[1] * 0.2, at[2] + n[2] * 0.2, at[3] + n[3] * 0.2 }
		table.insert(points, { p[1], p[2], p[3] })
		table.insert(times, t)
	end
	return { points = points, times = times, land = { p[1], p[2], p[3] }, time = t, bounced = bounced, grounded = false }
end

function Throws.at(trace: Trace, t: number): Vec
	local points, times = trace.points, trace.times
	local last = #points
	if t <= 0 or last <= 1 then
		return points[1]
	end
	if t >= times[last] then
		return points[last]
	end
	for i = 2, last do
		if times[i] >= t then
			local t0, t1 = times[i - 1], times[i]
			local k = if t1 > t0 then (t - t0) / (t1 - t0) else 1
			local a, b = points[i - 1], points[i]
			return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
		end
	end
	return points[last]
end

function Throws.flat(a: Vec, b: Vec): number
	local dx, dz = a[1] - b[1], a[3] - b[3]
	return math.sqrt(dx * dx + dz * dz)
end

function Throws.landed(land: Vec, door: Vec): boolean
	return Throws.flat(land, door) <= T.DoorRadius and math.abs(land[2] - door[2]) <= 6
end

function Throws.tip(span: number, over: boolean, wall: boolean): Tip
	local far = 0
	if finite(span) and span > T.FarFrom then
		local k = math.clamp((span - T.FarFrom) / math.max(1, T.Range - T.FarFrom), 0, 1)
		far = math.floor(T.FarMin + (T.FarMax - T.FarMin) * k + 0.5)
	end
	local o = if over then T.OverTip else 0
	local w = if wall then T.WallTip else 0
	return { total = far + o + w, far = far, over = o, wall = w }
end

function Throws.solve(from: Vec, door: Vec, angle: number): number?
	local d = Throws.flat(from, door)
	local dy = door[2] - from[2]
	local theta = math.rad(angle)
	local c = math.cos(theta)
	local denominator = 2 * c * c * (d * math.tan(theta) - dy)
	if d < 0.5 or denominator <= 1e-6 or not finite(denominator) then
		return nil
	end
	local speed = math.sqrt(T.Gravity * d * d / denominator)
	return if finite(speed) then speed else nil
end

function Throws.powerFor(speed: number): number?
	if not finite(speed) then
		return nil
	end
	local p = (speed - T.MinSpeed) / (T.MaxSpeed - T.MinSpeed)
	return if p >= 0 and p <= 1 then p else nil
end

function Throws.direction(from: Vec, door: Vec, angle: number): Vec?
	local dx, dz = door[1] - from[1], door[3] - from[3]
	local h = math.sqrt(dx * dx + dz * dz)
	if h < 1e-3 or not finite(h) then
		return nil
	end
	return lifted(dx / h, dz / h, math.rad(math.clamp(angle, T.MinUp, T.MaxUp)))
end

function Throws.landFlat(from: Vec, velocity: Vec, groundY: number): Vec?
	-- y(t) = y0 + vy t - g t² / 2 = groundY: the later root
	local g = T.Gravity
	local a, b, c = -0.5 * g, velocity[2], from[2] - groundY
	local disc = b * b - 4 * a * c
	if disc < 0 or not finite(disc) then
		return nil
	end
	local t = (-b - math.sqrt(disc)) / (2 * a)
	if t <= 0 or not finite(t) then
		return nil
	end
	return { from[1] + velocity[1] * t, groundY, from[3] + velocity[3] * t }
end

function Throws.perfect(land: Vec, door: Vec): boolean
	return Throws.flat(land, door) <= T.PerfectRadius and math.abs(land[2] - door[2]) <= 6
end

function Throws.fragile(look: string?, job: boolean): boolean
	return job or (look ~= nil and T.FragileLooks[look] == true)
end

function Throws.throwable(look: string?, job: boolean): boolean
	return look ~= nil and Config.Cargo.LightLooks[look] == true and not Throws.fragile(look, job)
end

return Throws
