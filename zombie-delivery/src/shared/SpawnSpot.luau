--!strict
-- 6.26, a vehicle never comes out into something: the pure maths of the spot it is put on (no Roblox at its top level;
-- tests/spawnspot_test.luau runs it in the plain Luau CLI). server/Vehicles.luau (findRoom: Vehicles.spawnAt,
-- Vehicles.standUp) casts the rays under the van's four wheels (its own wheelsOf) and asks the world; the numbers are
-- Config.SpawnSpot. (10.6: the city's cars' and bikes' wheel spots and a bike's level went with them, and with
-- server/CarRighting.luau shared/CarUpright.luau: its ground maths, the plane's up and the way along it, are here.)
--   * SpawnSpot.plane(points, spread, slope): is the ground under the four wheels (where their rays hit, { x, y, z },
--     in the wheels' order) one plane it can stand on? Not twisted (a wheel's ground off the plane of the other three
--     by more than `spread`: a crate, a step under one wheel) and no steeper than `slope` degrees (a hill road, a
--     ramp, two wheels up the curb are fine). Returns ok, why not, the plane's up and its middle ({ x, y, z }; given
--     for a plane too steep too).
--   * SpawnSpot.heightAt(up, middle, x, z): that plane's height at (x, z).
--   * SpawnSpot.frame(up, hx, hz): the axes it stands with on that plane, its flat heading (hx, hz) laid onto it:
--     look, right, up ({ x, y, z } units).
--   * SpawnSpot.box(width, length, top, lift, pad): the room the vehicle needs over that ground, as a box: its size
--     (x, y, z) and its middle's height over the ground. From `lift` up to the hull's `top`, `pad` wider all round.
--   * SpawnSpot.steps(width, length, gap): how far apart the spots tried are, along the way it faces and across it.
--   * SpawnSpot.candidates(tries, along, across, sides): the spots to try, { along, across } in studs from the one
--     asked for (first), then a small spiral round it: every spot one step away, then two … (in a ring: straight
--     along the way it faces before across it, ahead before behind, right before left); `sides` the steps to either
--     side at most (0: only along the way it faces). `along` and `across` are the steps (SpawnSpot.steps).


local SpawnSpot = {}

export type Vec = { number }
export type Wheel = { x: number, z: number }
export type Offset = { along: number, across: number }

local function sub(a: Vec, b: Vec): Vec
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function cross(a: Vec, b: Vec): Vec
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function length(a: Vec): number
	return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
end

-- The up of the ground under the four wheels (front left, front right, back left, back right): a unit { x, y, z }
-- facing up; nil when they are in a line.
local function groundUp(points: { Vec }): Vec?
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

-- The degrees between two vectors.
local function angle(a: Vec, b: Vec): number
	local dot = (a[1] * b[1] + a[2] * b[2] + a[3] * b[3]) / math.max(1e-9, length(a) * length(b))
	return math.deg(math.acos(math.clamp(dot, -1, 1)))
end

function SpawnSpot.plane(points: { Vec }, spread: number, slope: number): (boolean, string, Vec?, Vec?)
	if #points < 4 then
		return false, "no ground under a wheel", nil, nil
	end
	-- (on one plane the two diagonals' ends add up the same: front left + back right = front right + back left)
	local twist = math.abs(points[1][2] + points[4][2] - points[2][2] - points[3][2])
	if twist > spread + 1e-9 then
		return false, "uneven ground", nil, nil
	end
	local up = groundUp(points)
	if not up then
		return false, "uneven ground", nil, nil
	end
	local middle: Vec = { 0, 0, 0 }
	for _, p in points do
		middle = { middle[1] + p[1] / #points, middle[2] + p[2] / #points, middle[3] + p[3] / #points }
	end
	if angle(up, { 0, 1, 0 }) > slope + 1e-9 then
		return false, "ground too steep", up, middle -- (one plane all the same: what to stand it on when nothing is free)
	end
	return true, "", up, middle
end

function SpawnSpot.heightAt(up: Vec, middle: Vec, x: number, z: number): number
	return middle[2] - (up[1] * (x - middle[1]) + up[3] * (z - middle[3])) / math.max(1e-6, up[2])
end

function SpawnSpot.frame(up: Vec, hx: number, hz: number): (Vec, Vec, Vec)
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
	return look, { right[1] / r, right[2] / r, right[3] / r }, up
end

function SpawnSpot.box(width: number, length: number, top: number, lift: number, pad: number): (number, number, number, number)
	local height = math.max(0.2, top - lift)
	return width + pad * 2, height, length + pad * 2, lift + height / 2
end

function SpawnSpot.steps(width: number, length: number, gap: number): (number, number)
	return length + gap, width + gap
end

function SpawnSpot.candidates(tries: number, along: number, across: number, sides: number): { Offset }
	local list: { { a: number, s: number, ring: number } } = {}
	local reach = math.max(1, tries)
	for a = -reach, reach do
		for s = -sides, sides do
			table.insert(list, { a = a, s = s, ring = math.max(math.abs(a), math.abs(s)) })
		end
	end
	table.sort(list, function(p, q)
		if p.ring ~= q.ring then
			return p.ring < q.ring -- a small spiral: every spot one step away, then two …
		elseif math.abs(p.s) ~= math.abs(q.s) then
			return math.abs(p.s) < math.abs(q.s) -- along the way it faces (its lane, the kerb) before across it
		elseif math.abs(p.a) ~= math.abs(q.a) then
			return math.abs(p.a) < math.abs(q.a)
		elseif p.a ~= q.a then
			return p.a > q.a -- ahead before behind
		end
		return p.s > q.s -- right before left
	end)
	local out: { Offset } = {}
	for n = 1, math.min(tries, #list) do
		table.insert(out, { along = list[n].a * along, across = list[n].s * across })
	end
	return out
end

return SpawnSpot
