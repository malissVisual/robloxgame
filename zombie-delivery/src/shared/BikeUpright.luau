--!strict
-- 6.24, a bike knocked over gets back up: the pure maths (no Roblox at its top level; tests/bikeupright_test.luau runs
-- it in the plain Luau CLI). server/BikeRighting.luau looks at every bike every Config.BikeUpright.Check seconds and
-- does what BikeUpright.step says. Numbers in Config.BikeUpright.
--   * BikeUpright.tilt(upY): how far its top is off straight up (degrees, 0 … 180) from its up vector's Y.
--   * BikeUpright.roll(rightY, upY): how far it rolled about its length (degrees, 0 … 180: 90 on its side, 180 on its
--     back), from its right and up vectors' Y; a climb (pitch) alone is no roll. For the Output's line.
--   * BikeUpright.tipped(upY, limit) / settled(upY, limit): over `limit` degrees off upright / within it.
--   * BikeUpright.heading(lx, ly, lz, ux, uz): which way it points on the ground (a flat unit x, z) however it lies:
--     its nose, or for a bike standing on its nose or its tail the way its top faces.
--   * BikeUpright.step(state, tipped, settled, now, hold, give): "none" (upright), "wait" (tipped, not for `hold`
--     seconds yet), "start" (turn it back up now), "keep" (turning), "stop" (up again), "fallback" (still down `give`
--     seconds after the start: stand it up at once).

local BikeUpright = {}

export type State = {
	since: number?, -- when it tipped over (os.clock), nil while it stands
	righting: number?, -- when the turn back up started, nil when none is running
}

function BikeUpright.new(): State
	return { since = nil, righting = nil }
end

function BikeUpright.tilt(upY: number): number
	return math.deg(math.acos(math.clamp(upY, -1, 1)))
end

function BikeUpright.roll(rightY: number, upY: number): number
	return math.abs(math.deg(math.atan2(rightY, upY)))
end

function BikeUpright.tipped(upY: number, limit: number): boolean
	return BikeUpright.tilt(upY) > limit
end

function BikeUpright.settled(upY: number, limit: number): boolean
	return BikeUpright.tilt(upY) <= limit
end

function BikeUpright.heading(lx: number, ly: number, lz: number, ux: number, uz: number): (number, number)
	local x, z = lx, lz
	if math.sqrt(x * x + z * z) < 0.3 then
		-- On its nose (ly < 0) its top faces the way it went; on its tail (ly > 0) its top faces back.
		local sign = if ly > 0 then -1 else 1
		x, z = ux * sign, uz * sign
	end
	local length = math.sqrt(x * x + z * z)
	if length < 1e-3 then
		return 0, -1
	end
	return x / length, z / length
end

function BikeUpright.step(state: State, tipped: boolean, settled: boolean, now: number, hold: number, give: number): string
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
	if not tipped then
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

return BikeUpright
