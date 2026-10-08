--!strict
-- 5.6, the zip lines between Downtown's rooftops (Config.ZipLines), as plain numbers: which towers, where the
-- platforms, ladders and cables are, and where a rider is at every moment of a ride. server/ZipLines.luau builds them
-- and checks the rides, client/ZipRide.luau rides them; tests/ziplines_test.luau checks them. Pure Luau.
--
-- The towers (Map.lots: kind tower or apartment, on ordinary Downtown blocks, the same on every server) are boxes on
-- their lots: w × d, Map.WalkTop + h high (the roof). A line runs from a platform on the edge of a taller tower's roof
-- (the start) to one on a lower roof in another block across a road (the end), MinLength – MaxLength studs apart along
-- the ground, MinDrop or more down and never steeper than MaxSlope. The cable hangs CableHeight over both platforms'
-- floors and sags `Sag` per stud of length in its middle (a parabola). Every pair of towers is tried (in an order
-- Map.lcg shuffles, the same everywhere); a line is kept when the cable stays
--   * Margin + the roof's clutter over every other tower or storefront it crosses (the tests hold it to Clearance),
--   * Clearance over its own two roofs (it leaves and arrives over their edges),
--   * OverStreet over a street, a sidewalk, a lawn or a parking lot (the lamps, the trees),
-- never crosses a special block (the depot, the shops, City Hall …: their heights are their own) or leaves Downtown,
-- and uses no tower or block of another line, its middle Spread from every other line's.
--
-- Each tower of a line has a ladder on one of its outer walls (the street side; an apartment building's other street
-- side, away from its entrance): a "Climb" there takes you up to the platform, "Climb down" on a platform back to the
-- sidewalk at its foot (server/ZipLines.luau).
--
-- A ride (ZipLines.at): from standing to Speed in Ramp seconds, at Speed along the cable, slowing over the last Brake
-- studs to EndSpeed; the rider's root hangs Hang under the cable (the hands up on the trolley's handle).
--
--   ZipLines.lines()               every line (cached)
--   ZipLines.line(id)              one, or nil
--   ZipLines.cable(line, u)        the cable's point at u (0 the start's anchor … 1 the end's): x, y, z
--   ZipLines.travelled(line, t)    studs along the cable t seconds into a ride
--   ZipLines.at(line, t)           the trolley's point t seconds into a ride: x, y, z, and whether the ride is over
--   ZipLines.rider(line, t)        the rider's root there: x, y, z
--   ZipLines.canLetGo(line, t)     may the rider let go now (Space)? Only over one of the line's two roofs, the feet
--                                  no more than SafeDrop over it
--   ZipLines.surfaceAt(x, z)       what is under a point: "box" (a tower or storefront: its roof's height and the lot),
--                                  "open" (a block's sidewalk or open lot), "road", "special" or "outside"
--   ZipLines.boxOf(lot)            a lot's building as a box (x0, z0, x1, z1, top), nil for an open lot

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)

local ZipLines = {}

export type Platform = {
	x: number, -- the floor's middle
	z: number,
	floor: number, -- the floor's top
	fx: number, -- toward the other end of the line (unit, along X or Z)
	fz: number,
}
export type Ladder = {
	x: number, -- on the wall's face, at the foot
	z: number,
	nx: number, -- out of the wall (unit)
	nz: number,
	base: number, -- the sidewalk's top
	top: number, -- the roof
	street: string, -- the street it faces
}
export type Line = {
	id: number,
	name: string, -- "ZIP 3 · Oak St"
	start: Map.Lot,
	finish: Map.Lot,
	a: Platform,
	b: Platform,
	ladderA: Ladder,
	ladderB: Ladder,
	ax: number, -- the cable's ends (over the platforms)
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	length: number, -- along the ground
	span: number, -- the straight line between the ends
	sag: number,
	dx: number, -- the way along the ground (unit)
	dz: number,
	duration: number, -- seconds of a ride
	cruise: number, -- studs at full speed
}
export type Box = { x0: number, z0: number, x1: number, z1: number, top: number, extra: number, lot: Map.Lot }

local CELL = Map.Cell
local BLOCK = Map.BlockSize
local WALK = Map.WalkTop
local ROAD = Map.RoadTop
local STEP = 2 -- studs between two samples along the cable

-- ── The buildings as boxes ─────────────────────────────────────────────────

-- A lot's building as a box (nil: an open lot). `extra`: the clutter that may stand on its roof (a tower's roof box,
-- a storefront's fascia and extracts), kept clear of when a line is picked.
function ZipLines.boxOf(lot: Map.Lot): Box?
	if lot.kind == "tower" or lot.kind == "apartment" then
		return { x0 = lot.x - lot.w / 2, z0 = lot.z - lot.d / 2, x1 = lot.x + lot.w / 2, z1 = lot.z + lot.d / 2, top = WALK + lot.h, extra = 3, lot = lot }
	elseif lot.kind == "venue" and lot.venue then
		local venue = lot.venue
		local size = Map.VenueSize
		local hx = if venue.facing.x ~= 0 then size.d / 2 else size.w / 2
		local hz = if venue.facing.x ~= 0 then size.w / 2 else size.d / 2
		return { x0 = venue.x - hx, z0 = venue.z - hz, x1 = venue.x + hx, z1 = venue.z + hz, top = WALK + size.h, extra = 5, lot = lot }
	elseif lot.kind == "gas" or lot.kind == "house" or lot.kind == "estate" then
		-- (a gas station's canopy, a house: a box over the whole lot)
		local half = lot.size / 2
		return { x0 = lot.x - half, z0 = lot.z - half, x1 = lot.x + half, z1 = lot.z + half, top = WALK + 14, extra = 2, lot = lot }
	end
	return nil
end

local boxCache: { [string]: { Box } }? = nil
local function boxesAt(i: number, j: number): { Box }
	if not boxCache then
		local made: { [string]: { Box } } = {}
		for key, lots in Map.lots("downtown") do
			local list: { Box } = {}
			for _, lot in lots do
				local box = ZipLines.boxOf(lot)
				if box then
					table.insert(list, box)
				end
			end
			made[key] = list
		end
		boxCache = made
	end
	local cache = boxCache :: { [string]: { Box } }
	return cache[`{i},{j}`] or {}
end

function ZipLines.surfaceAt(x: number, z: number): (string, number, Box?)
	local d = Map.districtById("downtown")
	local i = math.floor((x - d.ox) / CELL + 0.5)
	local j = math.floor((z - d.oz) / CELL + 0.5)
	if i < d.i0 or i > d.i1 or j < d.j0 or j > d.j1 then
		-- the ring road around the district still counts as a road, beyond it is outside
		local x0, x1, z0, z1 = Map.districtEdges(d)
		if x >= x0 - Map.RoadWidth and x <= x1 + Map.RoadWidth and z >= z0 - Map.RoadWidth and z <= z1 + Map.RoadWidth then
			return "road", ROAD, nil
		end
		return "outside", ROAD, nil
	end
	local cx, cz = d.ox + i * CELL, d.oz + j * CELL
	if math.abs(x - cx) >= BLOCK / 2 or math.abs(z - cz) >= BLOCK / 2 then
		return "road", ROAD, nil
	end
	if Map.special(d.id, i, j) then
		return "special", WALK, nil
	end
	for _, box in boxesAt(i, j) do
		if x >= box.x0 and x <= box.x1 and z >= box.z0 and z <= box.z1 then
			return "box", box.top, box
		end
	end
	return "open", WALK, nil
end

-- ── The cable ──────────────────────────────────────────────────────────────

function ZipLines.cable(line: Line, u: number): (number, number, number)
	local v = math.clamp(u, 0, 1)
	return line.ax + (line.bx - line.ax) * v, line.ay + (line.by - line.ay) * v - line.sag * 4 * v * (1 - v), line.az + (line.bz - line.az) * v
end

-- A platform on the lot's roof, at its edge toward (ox, oz), as close to it as the roof allows.
local function platformOn(lot: Map.Lot, ox: number, oz: number): Platform
	local P = Config.ZipLines.Platform
	local hx, hz = lot.w / 2 - P / 2 - 0.3, lot.d / 2 - P / 2 - 0.3
	local dx, dz = ox - lot.x, oz - lot.z
	local floor = WALK + lot.h + 0.5
	if math.abs(dx) >= math.abs(dz) then
		local fx = if dx >= 0 then 1 else -1
		return { x = lot.x + fx * hx, z = math.clamp(oz, lot.z - hz, lot.z + hz), floor = floor, fx = fx, fz = 0 }
	end
	local fz = if dz >= 0 then 1 else -1
	return { x = math.clamp(ox, lot.x - hx, lot.x + hx), z = lot.z + fz * hz, floor = floor, fx = 0, fz = fz }
end

-- The street a lot's outer side faces (the names as Map.addresses gives them).
local function streetOf(lot: Map.Lot, nx: number, nz: number): string
	local d = Map.districtById(lot.district)
	if nz ~= 0 then
		local k = lot.j + (if nz > 0 then 0 else -1) - d.j0 + 1
		return d.streets[k % #d.streets + 1]
	end
	local k = lot.i + (if nx > 0 then 0 else -1) - d.i0 + 1
	return d.avenues[k % #d.avenues + 1]
end

-- The ladder on one of the tower's outer walls (a street side; an apartment building's other one, off its entrance),
-- near the lot's outer corner.
local function ladderOn(lot: Map.Lot): Ladder
	local sx, sz = if lot.a == 0 then -1 else 1, if lot.b == 0 then -1 else 1
	local onX = not (lot.kind == "apartment" and lot.facing.x ~= 0)
	if onX then
		return { x = lot.x + sx * lot.w / 2, z = lot.z + sz * (lot.d / 2 - 2.5), nx = sx, nz = 0, base = WALK, top = WALK + lot.h, street = streetOf(lot, sx, 0) }
	end
	return { x = lot.x + sx * (lot.w / 2 - 2.5), z = lot.z + sz * lot.d / 2, nx = 0, nz = sz, base = WALK, top = WALK + lot.h, street = streetOf(lot, 0, sz) }
end

-- The ride's numbers for a line (its duration, the studs at full speed).
local function timing(line: Line)
	local tuning = Config.ZipLines
	local V, Vend = tuning.Speed, tuning.EndSpeed
	local ramp = V * tuning.Ramp / 2
	local brake = math.min(tuning.Brake, math.max(0, line.span - ramp))
	line.cruise = math.max(0, line.span - ramp - brake)
	line.duration = tuning.Ramp + line.cruise / V + (if brake > 0 then 2 * brake / (V + Vend) else 0)
end

-- How the cable fares over the ground under it: (ok to pick, the least clearance over the roofs it crosses but its own
-- two, the least over its own two roofs, the least over the streets and open ground).
function ZipLines.survey(line: Line, margin: number?): (boolean, number, number, number)
	local tuning = Config.ZipLines
	local pick = margin or tuning.Margin
	local ok = true
	local overRoofs, overOwn, overGround = math.huge, math.huge, math.huge
	local steps = math.max(2, math.ceil(line.length / STEP))
	for n = 0, steps do
		local x, y, z = ZipLines.cable(line, n / steps)
		local kind, top, box = ZipLines.surfaceAt(x, z)
		if kind == "special" or kind == "outside" then
			ok = false
		elseif kind == "box" and box then
			if box.lot == line.start or box.lot == line.finish then
				overOwn = math.min(overOwn, y - top)
				if y - top < tuning.Clearance then
					ok = false
				end
			else
				overRoofs = math.min(overRoofs, y - top)
				if y - top < box.extra + pick then
					ok = false
				end
			end
		else
			overGround = math.min(overGround, y - top)
			if y - top < tuning.OverStreet then
				ok = false
			end
		end
	end
	return ok, overRoofs, overOwn, overGround
end

-- A line from one tower to another (not checked yet).
local function make(s: Map.Lot, e: Map.Lot): Line
	local tuning = Config.ZipLines
	local a = platformOn(s, e.x, e.z)
	local b = platformOn(e, s.x, s.z)
	local dx, dz = b.x - a.x, b.z - a.z
	local length = math.sqrt(dx * dx + dz * dz)
	local ay, by = a.floor + tuning.CableHeight, b.floor + tuning.CableHeight
	local line: Line = {
		id = 0,
		name = "",
		start = s,
		finish = e,
		a = a,
		b = b,
		ladderA = ladderOn(s),
		ladderB = ladderOn(e),
		ax = a.x,
		ay = ay,
		az = a.z,
		bx = b.x,
		by = by,
		bz = b.z,
		length = length,
		span = math.sqrt(length * length + (ay - by) ^ 2),
		sag = tuning.Sag * length,
		dx = if length > 0 then dx / length else 1,
		dz = if length > 0 then dz / length else 0,
		duration = 0,
		cruise = 0,
	}
	timing(line)
	return line
end

local cache: { Line }? = nil

function ZipLines.lines(): { Line }
	if cache then
		return cache
	end
	local tuning = Config.ZipLines
	local towers: { Map.Lot } = {}
	for _, lots in Map.lots("downtown") do
		for _, lot in lots do
			if (lot.kind == "tower" or lot.kind == "apartment") and lot.w > tuning.Platform + 2 and lot.d > tuning.Platform + 2 then
				table.insert(towers, lot)
			end
		end
	end
	-- (a fixed order: the dictionary's is not)
	local function key(lot: Map.Lot): number
		return ((lot.i + 10) * 100 + (lot.j + 10)) * 10 + lot.a * 2 + lot.b
	end
	table.sort(towers, function(p: Map.Lot, q: Map.Lot): boolean
		return key(p) < key(q)
	end)
	type Candidate = { line: Line, score: number, key: number }
	local candidates: { Candidate } = {}
	local rand = Map.lcg(Config.City.Seed + 57)
	for _, s in towers do
		for _, e in towers do
			if s == e or (s.i == e.i and s.j == e.j) then
				continue
			end
			local drop = s.h - e.h
			local far = math.sqrt((s.x - e.x) ^ 2 + (s.z - e.z) ^ 2)
			if drop < tuning.MinDrop or far < tuning.MinLength - 10 or far > tuning.MaxLength + 60 then
				continue
			end
			local line = make(s, e)
			if line.length < tuning.MinLength or line.length > tuning.MaxLength or (line.ay - line.by) / line.length > tuning.MaxSlope then
				continue
			end
			table.insert(candidates, { line = line, score = rand(), key = key(s) * 10000 + key(e) })
		end
	end
	table.sort(candidates, function(p: Candidate, q: Candidate): boolean
		if p.score ~= q.score then
			return p.score < q.score
		end
		return p.key < q.key
	end)
	local list: { Line } = {}
	local usedBlock: { [string]: boolean } = {}
	for _, candidate in candidates do
		if #list >= tuning.Count then
			break
		end
		local line = candidate.line
		local blockA, blockB = `{line.start.i},{line.start.j}`, `{line.finish.i},{line.finish.j}`
		if usedBlock[blockA] or usedBlock[blockB] then
			continue
		end
		local mx, mz = (line.ax + line.bx) / 2, (line.az + line.bz) / 2
		local spread = true
		for _, other in list do
			if ((other.ax + other.bx) / 2 - mx) ^ 2 + ((other.az + other.bz) / 2 - mz) ^ 2 < tuning.Spread * tuning.Spread then
				spread = false
				break
			end
		end
		if not spread or not (ZipLines.survey(line)) then
			continue
		end
		usedBlock[blockA], usedBlock[blockB] = true, true
		line.id = #list + 1
		line.name = `ZIP {line.id} · {line.ladderA.street}`
		table.insert(list, line)
	end
	cache = list
	return list
end

function ZipLines.line(id: number): Line?
	for _, line in ZipLines.lines() do
		if line.id == id then
			return line
		end
	end
	return nil
end

-- ── The ride ───────────────────────────────────────────────────────────────

function ZipLines.travelled(line: Line, t: number): number
	local tuning = Config.ZipLines
	local V, Vend = tuning.Speed, tuning.EndSpeed
	if t <= 0 then
		return 0
	end
	if t < tuning.Ramp then
		return 0.5 * (V / tuning.Ramp) * t * t
	end
	local ramp = V * tuning.Ramp / 2
	local t2 = t - tuning.Ramp
	if t2 < line.cruise / V then
		return ramp + V * t2
	end
	local brake = line.span - ramp - line.cruise
	if brake <= 0 then
		return line.span
	end
	local t3 = t2 - line.cruise / V
	local time = 2 * brake / (V + Vend)
	if t3 >= time then
		return line.span
	end
	local slow = (V - Vend) / time
	return math.min(line.span, ramp + line.cruise + V * t3 - 0.5 * slow * t3 * t3)
end

function ZipLines.at(line: Line, t: number): (number, number, number, boolean)
	local u = if line.span > 0 then ZipLines.travelled(line, t) / line.span else 1
	local x, y, z = ZipLines.cable(line, u)
	return x, y, z, t >= line.duration
end

function ZipLines.rider(line: Line, t: number): (number, number, number)
	local x, y, z = ZipLines.at(line, t)
	return x, y - Config.ZipLines.Hang, z
end

-- The rider's feet: this far under the root (an R15 body's hip height and half its root). 6.8 review: the courier's
-- (server/CharacterArt/Geometry.luau: HipHeight 2.8 + 1; it was 3, the 6.0 block body's)
ZipLines.Feet = 3.8

function ZipLines.canLetGo(line: Line, t: number): boolean
	local x, y, z = ZipLines.rider(line, t)
	local feet = y - ZipLines.Feet
	for _, lot in { line.start, line.finish } do
		local box = ZipLines.boxOf(lot)
		if box and x >= box.x0 and x <= box.x1 and z >= box.z0 and z <= box.z1 then
			local over = feet - box.top
			return over >= -1 and over <= Config.ZipLines.SafeDrop
		end
	end
	return false
end

return ZipLines
