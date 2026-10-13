--!strict
-- 6.26 (6.24's BikeUpright, now every vehicle of a player), a vehicle knocked over gets back up: the pure maths (no
-- Roblox at its top level; tests/carupright_test.luau runs it in the plain Luau CLI). server/CarRighting.luau looks at
-- every vehicle every Config.CarUpright.Check seconds and does what CarUpright.step says. Numbers in Config.CarUpright
-- (its Kinds: "car" for the cars, vans and trucks, "bike" for the bikes and the E-Scooter).
--   * CarUpright.tilt(upY): how far its top is off straight up (degrees, 0 … 180) from its up vector's Y.
--   * CarUpright.roll(rightY, upY): how far it rolled about its length (degrees, 0 … 180: 90 on its side, 180 on its
--     back), from its right and up vectors' Y; a climb (pitch) alone is no roll. For the Output's line.
--   * CarUpright.tipped(upY, limit) / settled(upY, limit): over `limit` degrees off upright / within it.
--   * CarUpright.down(tilt, speed, gap, missing, kind, slow, gapLimit): is it down? Past its side (over 90°) at any
--     speed; slower than `slow` and over the kind's Lean: a wheel `gapLimit` or more over the ground under it (`gap`:
--     the most of its four wheels; resting on its nose, a bumper or its side, a wheel in the air) or no ground under
--     a wheel at all (`missing`). On all its wheels it is never down, however steep the ground (a hill, a ramp).
--   * CarUpright.groundUp(points): the up of the ground under its four wheels (the points where their rays hit, front
--     left, front right, back left, back right, { x, y, z }), a unit { x, y, z } facing up; nil when they are in a line.
--   * CarUpright.angle(a, b): the degrees between two unit vectors ({ x, y, z }).
--   * CarUpright.facing(hx, hz, up): the way it faces on ground whose up is `up` (along that ground, its flat part the
--     heading hx, hz: no turn aside) and its right side: look, right ({ x, y, z } units), for the turn back's frame.
--   * CarUpright.noRoll(up, hx, hz): that ground's up with its roll across the heading taken out (the pitch kept): a
--     bike's level (its KeepUpright holds its right side level).
--   * CarUpright.heading(lx, ly, lz, ux, uz): which way it points on the ground (a flat unit x, z) however it lies:
--     its nose, or for one standing on its nose or its tail the way its top faces.
--   * CarUpright.step(state, down, settled, now, hold, give): "none" (upright), "wait" (down, not for `hold` seconds
--     yet), "start" (turn it back up now), "keep" (turning), "stop" (up again), "fallback" (still down `give` seconds
--     after the start: stand it up at once).

local CarUpright = {}

export type State = {
	since: number?, -- when it went down (os.clock), nil while it stands
	righting: number?, -- when the turn back up started, nil when none is running
}
export type Kind = { Lean: number, Hold: number, Settled: number, Give: number }
export type Vec = { number }

function CarUpright.new(): State
	return { since = nil, righting = nil }
end

function CarUpright.tilt(upY: number): number
	return math.deg(math.acos(math.clamp(upY, -1, 1)))
end

function CarUpright.roll(rightY: number, upY: number): number
	return math.abs(math.deg(math.atan2(rightY, upY)))
end

function CarUpright.tipped(upY: number, limit: number): boolean
	return CarUpright.tilt(upY) > limit
end

function CarUpright.settled(upY: number, limit: number): boolean
	return CarUpright.tilt(upY) <= limit
end

function CarUpright.down(tilt: number, speed: number, gap: number, missing: boolean, kind: Kind, slow: number, gapLimit: number): boolean
	if tilt > 90 then
		return true -- on its back or past its side: whatever it does
	end
	if speed >= slow or tilt <= kind.Lean then
		return false -- a jump, a stunt, a slide: let it be; standing about level: on its wheels
	end
	return missing or gap >= gapLimit -- (on all four wheels on a steep slope: not down)
end

local function sub(a: Vec, b: Vec): Vec
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function cross(a: Vec, b: Vec): Vec
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function length(a: Vec): number
	return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
end

function CarUpright.groundUp(points: { Vec }): Vec?
	if #points < 4 then
		return nil
	end
	-- (the two diagonals: front left → back right, front right → back left; their cross is the plane's normal)
	local n = cross(sub(points[4], points[1]), sub(points[3], points[2]))
	local size = length(n)
	if size < 1e-6 then
		return nil
	end
	local sign = if n[2] < 0 then -1 else 1
	return { n[1] / size * sign, n[2] / size * sign, n[3] / size * sign }
end

function CarUpright.angle(a: Vec, b: Vec): number
	local dot = (a[1] * b[1] + a[2] * b[2] + a[3] * b[3]) / math.max(1e-9, length(a) * length(b))
	return math.deg(math.acos(math.clamp(dot, -1, 1)))
end

function CarUpright.facing(hx: number, hz: number, up: Vec): (Vec, Vec)
	-- The way along that ground whose flat part is the heading: its climb from the plane (up · look = 0), no turn aside.
	local look: Vec = { hx, 0, hz }
	if math.abs(up[2]) > 1e-6 then
		look = { hx, -(hx * up[1] + hz * up[3]) / up[2], hz }
	end
	local size = length(look)
	if size < 1e-6 then
		look = { 0, 0, -1 }
	else
		look = { look[1] / size, look[2] / size, look[3] / size }
	end
	local right = cross(look, up) -- (look × up: the right side; -Z × Y = +X)
	local r = math.max(1e-9, length(right))
	return look, { right[1] / r, right[2] / r, right[3] / r }
end

function CarUpright.noRoll(up: Vec, hx: number, hz: number): Vec
	local look = CarUpright.facing(hx, hz, up)
	local right = cross(look, { 0, 1, 0 }) -- (level: no roll)
	local r = length(right)
	if r < 1e-6 then
		return { 0, 1, 0 }
	end
	local level = cross({ right[1] / r, right[2] / r, right[3] / r }, look)
	local size = math.max(1e-9, length(level))
	return { level[1] / size, level[2] / size, level[3] / size }
end

function CarUpright.heading(lx: number, ly: number, lz: number, ux: number, uz: number): (number, number)
	local x, z = lx, lz
	if math.sqrt(x * x + z * z) < 0.3 then
		-- On its nose (ly < 0) its top faces the way it went; on its tail (ly > 0) its top faces back.
		local sign = if ly > 0 then -1 else 1
		x, z = ux * sign, uz * sign
	end
	local size = math.sqrt(x * x + z * z)
	if size < 1e-3 then
		return 0, -1
	end
	return x / size, z / size
end

function CarUpright.step(state: State, down: boolean, settled: boolean, now: number, hold: number, give: number): string
	local righting = state.righting
	if righting then
		if settled then
			state.righting, state.since = nil, nil
			return "stop"
		elseif now - righting >= give then
			state.righting, state.since = nil, nil
			return "fallback"
		end
		return "keep"
	end
	if not down then
		state.since = nil
		return "none"
	end
	local since = state.since or now
	state.since = since
	if now - since >= hold then
		state.righting, state.since = now, nil
		return "start"
	end
	return "wait"
end

return CarUpright
