-- 5.5, the city buses (shared/BusLines.luau): the three loops, their stops at the kerb, the timetable every client
-- works out from the server's clock and the route the HUD suggests, in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local BusLines = require("./BusLines")
local TrafficLanes = require("./TrafficLanes")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local lines = BusLines.lines()
check("three lines", #lines == 3 and #Config.Bus.Lines == 3, #lines)
check("lines are cached", BusLines.lines() == lines)
for _, line in lines do
	print(string.format("  line %d %-15s %4.0f studs, %2d stops, loop %5.1f s, %d buses, a bus every %4.1f s", line.id, line.name, line.length, #line.stops, line.period, line.buses, line.headway))
end

-- The loops are closed: every segment starts where the one before ends, the last one ends where the first starts.
for _, line in lines do
	local worst = 0
	local list = line.segments
	for n, seg in list do
		local nextSeg = list[n % #list + 1]
		local ex, ez = TrafficLanes.at(seg.piece, seg.s1)
		local sx, sz = TrafficLanes.at(nextSeg.piece, nextSeg.s0)
		worst = math.max(worst, math.sqrt((ex - sx) ^ 2 + (ez - sz) ^ 2))
	end
	check(`line {line.id}: the loop is closed and continuous`, worst < 0.6, worst)
	local total = 0
	for _, seg in list do
		total += seg.s1 - seg.s0
	end
	check(`line {line.id}: its length adds up`, math.abs(total - line.length) < 1e-3, total)
end

-- The stops: enough of them, about every 2 blocks, on a road at the kerb, never in a building or by a door.
local function inBuilding(x: number, z: number): string?
	local d, i, j = Map.blockAt(x, z)
	if not d then
		return nil
	end
	local special = Map.special(d.id, i, j)
	if special then
		return special
	end
	for _, lot in Map.lotsAt(d.id, i, j) do
		if lot.w > 0 and lot.kind ~= "house" and math.abs(x - lot.x) < lot.w / 2 + 1 and math.abs(z - lot.z) < lot.d / 2 + 1 then
			return lot.kind
		end
	end
	return nil
end
local clear2 = Config.Bus.StopClear ^ 2
for _, line in lines do
	check(`line {line.id}: at least 5 stops`, #line.stops >= 5, #line.stops)
	local worstGap, leastGap = 0, math.huge
	for k = 1, #line.stops do
		local gap = (line.stopArc[k % #line.stops + 1] - line.stopArc[k]) % line.length
		worstGap = math.max(worstGap, gap)
		leastGap = math.min(leastGap, gap)
	end
	check(`line {line.id}: a stop every ~2 blocks`, leastGap >= Config.Bus.StopGap * 0.6 and worstGap <= 700, `{math.floor(leastGap)} .. {math.floor(worstGap)} studs`)
	for k, stop in line.stops do
		local where = `line {line.id} stop {k} {stop.name}`
		check(`{where}: the bus stands on the road`, Map.onRoad(stop.x, stop.z) and Map.onRoad(stop.x + stop.nx * 3.9, stop.z + stop.nz * 3.9))
		check(`{where}: its kerb is the road's edge`, Map.onRoad(stop.kx - stop.nx * 2.5, stop.kz - stop.nz * 2.5) and not Map.onRoad(stop.kx + stop.nx * 0.6, stop.kz + stop.nz * 0.6))
		local out = (stop.kx - stop.x) * stop.nx + (stop.kz - stop.z) * stop.nz
		check(`{where}: the bus pulls in to the kerb`, math.abs(out - (Map.CurbPark + 1.5)) < 0.01, out)
		local ahead = (stop.kx - stop.x) * stop.hx + (stop.kz - stop.z) * stop.hz
		check(`{where}: the door is by the shelter`, math.abs(ahead - BusLines.DoorAhead) < 0.01, ahead)
		-- The shelter: 10 along the kerb, 3.4 in from the curb.
		local blocked: string? = nil
		for _, along in { -5, 0, 5 } do
			for _, depth in { 0, 1.7, 3.4 } do
				local x = stop.kx - stop.nx * 1.5 + stop.nx * depth + stop.hx * along
				local z = stop.kz - stop.nz * 1.5 + stop.nz * depth + stop.hz * along
				blocked = blocked or inBuilding(x, z)
			end
		end
		check(`{where}: the shelter stands in no building`, blocked == nil, blocked)
		local byDoor: string? = nil
		for _, home in Map.Homes do
			for _, p in { home.door, home.pile, home.park } do
				if (p.x - stop.kx) ^ 2 + (p.z - stop.kz) ^ 2 < clear2 then
					byDoor = home.name
				end
			end
		end
		for id, spot in Map.CargoSpots do
			if (spot.park.x - stop.kx) ^ 2 + (spot.park.z - stop.kz) ^ 2 < clear2 then
				byDoor = id
			end
		end
		check(`{where}: clear of the doors and the cargo spots`, byDoor == nil, byDoor)
		check(`{where}: named after its street`, stop.name ~= "" and string.find(stop.name, stop.street, 1, true) == 1, stop.name)
		check(`{where}: it knows its line`, table.find(stop.lines, line.id) ~= nil)
	end
end
do
	local ids, ok = {}, true
	for n, stop in BusLines.allStops() do
		ok = ok and stop.id == n and not ids[stop.id]
		ids[stop.id] = true
	end
	check("every stop once, numbered", ok and #BusLines.allStops() >= 20, #BusLines.allStops())
end

-- The timetable: every line within the longest wait; a bus is never more than a headway away.
for _, line in lines do
	check(`line {line.id}: a bus at least every {Config.Bus.MaxWait} s`, line.headway <= Config.Bus.MaxWait, line.headway)
	local worst = 0
	for k = 1, #line.stops do
		for step = 0, 200 do
			local now = 1000 + step * line.period / 200
			local wait = BusLines.nextArrival(line, k, now)
			worst = math.max(worst, wait)
		end
	end
	check(`line {line.id}: nextArrival ≤ the headway`, worst <= line.headway + 1e-6, `{worst} > {line.headway}`)
end

-- A bus stands at its stop for Dwell seconds when it arrives, then drives on; it drives no faster than Speed, never
-- jumps, stays on the road, and two buses of a line never meet.
for _, line in lines do
	local stop = line.stops[3]
	local now = 5000 - (5000 % line.period) + line.arrive[3] + 0.5
	local x, z, _, _, at, nextStop, leaveIn = BusLines.position(line, 0, now)
	check(`line {line.id}: standing at a stop`, at == 3 and nextStop == 3 % #line.stops + 1 and math.abs(x - stop.x) < 1e-6 and math.abs(z - stop.z) < 1e-6 and math.abs(leaveIn - (Config.Bus.Dwell - 0.5)) < 1e-6, `{at} {nextStop} {leaveIn}`)
	local _, _, _, _, at2, next2 = BusLines.position(line, 0, now + Config.Bus.Dwell)
	check(`line {line.id}: then it drives to the next`, at2 == 0 and next2 == 3 % #line.stops + 1, `{at2} {next2}`)
	local wait = BusLines.nextArrival(line, 3, now)
	check(`line {line.id}: nextArrival is 0 while one stands there`, wait == 0, wait)

	local dt = 0.05
	local fastest, offRoad, closest = 0, 0, math.huge
	local px, pz = BusLines.position(line, 0, 0)
	for step = 1, math.ceil(line.period / dt) do
		local t = step * dt
		local bx, bz = BusLines.position(line, 0, t)
		fastest = math.max(fastest, math.sqrt((bx - px) ^ 2 + (bz - pz) ^ 2) / dt)
		px, pz = bx, bz
		if step % 10 == 0 then
			if not Map.onRoad(bx, bz) then
				offRoad += 1
			end
			local ox, oz = BusLines.position(line, 1, t)
			closest = math.min(closest, math.sqrt((bx - ox) ^ 2 + (bz - oz) ^ 2))
		end
	end
	check(`line {line.id}: no faster than Speed, no jumps`, fastest <= Config.Bus.Speed * 1.08, fastest)
	check(`line {line.id}: always on the road`, offRoad == 0, offRoad)
	check(`line {line.id}: two buses never meet`, closest > 2 * BusLines.HalfLength + 6, closest)
	local a = { BusLines.position(line, 2, 12345.6) }
	local b = { BusLines.position(line, 2, 12345.6) }
	check(`line {line.id}: the same clock, the same bus`, a[1] == b[1] and a[2] == b[2] and a[5] == b[5])
	local c = { BusLines.position(line, 1, 777) }
	local d = { BusLines.position(line, 0, 777 - line.headway) }
	check(`line {line.id}: bus 1 is where bus 0 was a headway ago`, math.abs(c[1] - d[1]) < 1e-6 and math.abs(c[2] - d[2]) < 1e-6)
end

-- Riding: the ride from a stop to the next is shorter than to the one after; a whole loop is the period.
for _, line in lines do
	local one, two = BusLines.rideTime(line, 1, 2), BusLines.rideTime(line, 1, 3)
	check(`line {line.id}: ride times grow with the stops`, one > Config.Bus.Dwell and two > one and math.abs(BusLines.rideTime(line, 2, 2) - line.period) < 1e-6, `{one} {two}`)
end

-- Stops near a point, nearest first.
do
	local stop = BusLines.allStops()[5]
	local near = BusLines.stopsNear(stop.kx + 3, stop.kz, 25)
	check("stopsNear finds the stop", #near >= 1 and near[1].stop == stop and math.abs(near[1].distance - 3) < 1e-6)
	check("stopsNear: nobody far out", #BusLines.stopsNear(-2000, -2900, 25) == 0)
end

-- Routes: a long way across town takes a bus, a short walk does not; the walks and the stops add up; with a piece
-- in your hands (the carry walk) the bus pays off sooner.
do
	local ring = lines[1]
	local a, b = ring.stops[2], ring.stops[7]
	local route = BusLines.route(a.kx + 30, a.kz + 30, b.kx - 20, b.kz + 10)
	check("a long way across Downtown takes a bus", route ~= nil)
	if route then
		check("the route saves time", route.time + Config.Bus.RouteSaving <= route.walkTime, `{route.time} vs {route.walkTime}`)
		check("the route walks within reach", route.walkTo <= Config.Bus.RouteReach and route.walkFrom <= Config.Bus.RouteReach)
		check("the route counts its stops", route.stops == (route.leave - route.board) % #route.line.stops and route.stops >= 1, route.stops)
		check("the route names its stops", route.boardStop == route.line.stops[route.board] and route.leaveStop == route.line.stops[route.leave])
		print(`  across town: Line {route.line.id} from {route.boardStop.name} to {route.leaveStop.name}, {route.stops} stops, {math.floor(route.time)} s instead of {math.floor(route.walkTime)} s on foot`)
	end
	check("a short walk takes no bus", BusLines.route(100, -400, 220, -380) == nil and BusLines.route(100, -400, 220, -380, 8) == nil)
	local carried = BusLines.route(0, 300, -150, 1150, 8)
	check("Downtown to the Suburbs with a parcel in your hands takes a bus", carried ~= nil)
	if carried then
		print(`  to the Suburbs (carrying): Line {carried.line.id} from {carried.boardStop.name} to {carried.leaveStop.name}, {carried.stops} stops, {math.floor(carried.time)} s instead of {math.floor(carried.walkTime)} s`)
	end
	local walking = BusLines.route(0, 300, -150, 1150)
	print(`  to the Suburbs (hands free): {if walking then "Line " .. walking.line.id else "walk"}`)
end

check("the clock", BusLines.clock(0) == "NOW" and BusLines.clock(12.2) == "0:13" and BusLines.clock(65) == "1:05")

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
