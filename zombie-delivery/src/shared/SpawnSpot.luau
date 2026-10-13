--!strict
-- 6.26, a vehicle never comes out into something: the pure maths of the spot it is put on (no Roblox at its top level;
-- tests/spawnspot_test.luau runs it in the plain Luau CLI). server/Vehicles.luau (findRoom, Vehicles.spawnAt,
-- Vehicles.clearFor, Vehicles.standUp) casts the rays and asks the world; the numbers are Config.SpawnSpot.
--   * SpawnSpot.wheels(width, length, wheel, wheelWidth): where a vehicle's four wheels touch the ground, { x, z } in
--     its own space (-z its front), front left, front right, back left, back right (Vehicles' wheel colliders).
--   * SpawnSpot.level(heights, spread): the ground under the wheels even enough (no more than `spread` between the
--     highest and the lowest) and the height it stands on (the highest: it drops onto the others).
--   * SpawnSpot.box(width, length, top, lift, pad): the room the vehicle needs over that ground, as a box: its size
--     (x, y, z) and its middle's height over the ground. From `lift` up to the hull's `top`, `pad` wider all round.
--   * SpawnSpot.steps(width, length, gap): how far apart the spots tried are, along the way it faces and across it.
--   * SpawnSpot.candidates(tries, along, across, sides): the spots to try, { along, across } in studs from the one
--     asked for (first), then a small spiral round it: every spot one step away, then two … (in a ring: straight
--     along the way it faces before across it, ahead before behind, right before left); `sides` the steps to either
--     side at most (0: only along the way it faces). `along` and `across` are the steps (SpawnSpot.steps).

local SpawnSpot = {}

export type Wheel = { x: number, z: number }
export type Offset = { along: number, across: number }

function SpawnSpot.wheels(width: number, length: number, wheel: number, wheelWidth: number): { Wheel }
	-- (Vehicles build: the colliders' x and z)
	local x = width / 2 - wheelWidth / 2 + 0.3
	local z = length / 2 - wheel - 0.5
	return { { x = -x, z = -z }, { x = x, z = -z }, { x = -x, z = z }, { x = x, z = z } }
end

function SpawnSpot.level(heights: { number }, spread: number): (boolean, number)
	if #heights == 0 then
		return false, 0
	end
	local low, high = math.huge, -math.huge
	for _, h in heights do
		low, high = math.min(low, h), math.max(high, h)
	end
	return high - low <= spread + 1e-9, high
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
