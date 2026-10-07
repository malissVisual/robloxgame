--!strict
-- 5.7, the street props (Config.LivingCity.Street), as plain numbers: what stands on the sidewalks of every ordinary
-- block of Downtown, the Harbor and the Suburbs (and now and then an abandoned car at its kerb), the same on every
-- server. server/StreetDressing.luau builds them (World's build list: "street props"), tests/streetprops_test.luau
-- checks them. Pure Luau.
--
-- The kinds:
--   on the kerb (CurbDepth in from the curb, between the curb and the people's walk line, 4.5 in:
--   shared/TrafficLanes.luau): a bin, a fire hydrant, a barricade, sandbags, debris
--   against a Downtown tower's street wall (behind the people's lines): trash bags, a boarded shopfront
--   on the road at the kerb: an abandoned car (CarShare of the sides, never on a street a bus line drives, never by a
--   junction or a road that comes in), a red flare on the kerb by it now and then (FlareShare), and by the wrecks on
--   the parking lots and the Suburbs' burnt-out lots
--
-- Every block rolls its own dice (Map.lcg on its district and place: a change on one block leaves the others). A prop
-- keeps CornerClear from the block's corners (the crosswalks, the lamps and the light poles) and away from everything
-- the deliveries and the rides use: the homes' and storefronts' doors, piles and parks, the cargo spots, the
-- employers' boards, the addresses, the places and the houses for sale, the bus stops, the gas stations, the alley
-- shortcuts' mouths, the zip lines' ladders, the ZDC RIDE docks, the crosswalks and the safe zone; no two props of a
-- block closer than Spacing.
--
--   StreetProps.blocks()       every block with its props (cached; a block without props is left out)
--   StreetProps.clear(x, z, r) is (x, z) clear of everything a prop keeps away from (r: a radius to add)?
--   StreetProps.onBusLine(x, z, alongX) is the road centre line through (x, z) along X (or Z) one a bus line drives?

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local BusLines = require(script.Parent.BusLines)
local Crossings = require(script.Parent.Crossings)
local RentalDocks = require(script.Parent.RentalDocks)
local Shortcuts = require(script.Parent.Shortcuts)
local ZipLines = require(script.Parent.ZipLines)

local StreetProps = {}

export type Prop = {
	kind: string, -- bin | hydrant | barricade | sandbags | debris | bags | boarded | car | flare
	x: number, -- the middle on the ground (the sidewalk; a car: the road)
	z: number,
	nx: number, -- out of the block toward the street (unit, along X or Z)
	nz: number,
	road: boolean, -- stands on the road (a car), not on the sidewalk
	width: number, -- along the kerb (a boarded shopfront's boards, a car's length)
	turn: number, -- a small turn of its own (radians), for the looks
	seed: number, -- dice for the looks
}
export type Block = { district: string, i: number, j: number, props: { Prop } }

StreetProps.KerbKinds = { "bin", "hydrant", "barricade", "sandbags", "debris" }
StreetProps.WallKinds = { "bags", "boarded" }

-- How often each kind comes up, by the district's style.
local WEIGHTS: { [string]: { [string]: number } } = {
	downtown = { bin = 3, hydrant = 2, barricade = 2, sandbags = 1.5, debris = 2, bags = 3, boarded = 1.5 },
	harbor = { bin = 1, hydrant = 1, barricade = 2, sandbags = 2, debris = 2 },
	suburbs = { bin = 4, hydrant = 2, barricade = 1, sandbags = 0.5, debris = 1 },
}
local ORDER = { "bin", "hydrant", "barricade", "sandbags", "debris", "bags", "boarded" }
-- Half a prop's size along the kerb (for the corners and the spacing).
local HALF: { [string]: number } = { bin = 0.8, hydrant = 0.5, barricade = 2.4, sandbags = 2, debris = 1.6, bags = 1.5, boarded = 3, flare = 0.3 }

local BLOCK = Map.BlockSize
local CELL = Map.Cell

-- ── What a prop keeps away from ────────────────────────────────────────────
-- Points with a radius, bucketed in a grid of GRID studs (no radius is bigger), built once.
local GRID = 64
type Keep = { x: number, z: number, r: number }
local grid: { [string]: { Keep } }? = nil

local function keeps(): { [string]: { Keep } }
	if grid then
		return grid
	end
	local t = Config.LivingCity.Street
	local made: { [string]: { Keep } } = {}
	local function add(x: number, z: number, radius: number)
		local key = `{math.floor(x / GRID)},{math.floor(z / GRID)}`
		local list = made[key]
		if not list then
			list = {}
			made[key] = list
		end
		table.insert(list, { x = x, z = z, r = radius })
	end
	-- A door's way out to the kerb: the point on the curb band straight in front of it (a house's path, a storefront's
	-- forecourt, the people coming out).
	local function front(x: number, z: number, fx: number, fz: number)
		local d, i, j = Map.blockAt(x, z)
		if d then
			local cx, cz = d.ox + i * CELL, d.oz + j * CELL
			local out = BLOCK / 2 - t.CurbDepth
			add(if fx ~= 0 then cx + fx * out else x, if fz ~= 0 then cz + fz * out else z, t.Clear)
		end
	end
	for _, home in Map.Homes do
		add(home.door.x, home.door.z, t.Clear)
		add(home.pile.x, home.pile.z, t.Clear)
		add(home.park.x, home.park.z, t.ParkClear)
		front(home.door.x, home.door.z, home.facing.x, home.facing.z)
	end
	for _, venue in Map.Venues do
		add(venue.door.x, venue.door.z, t.Clear)
		add(venue.pile.x, venue.pile.z, t.Clear)
		add(venue.park.x, venue.park.z, t.ParkClear)
		front(venue.door.x, venue.door.z, venue.facing.x, venue.facing.z)
	end
	for _, spot in Map.CargoSpots do
		add(spot.park.x, spot.park.z, t.ParkClear)
		add(spot.pile.x, spot.pile.z, t.Clear)
	end
	for _, spot in Map.EmployerSpots do
		add(spot.x, spot.z, t.Clear)
	end
	for _, address in Map.addresses() do
		add(address.x, address.z, t.ParkClear)
	end
	for _, place in Map.Places do
		add(place.x, place.z, t.PlaceClear)
	end
	for _, plot in Map.EstatePlots do
		add(plot.x, plot.z, t.PlaceClear)
	end
	for _, hub in Map.FreightDocks do
		for _, dock in hub.docks do
			add(dock.park.x, dock.park.z, t.ParkClear)
		end
	end
	for _, stop in BusLines.allStops() do
		add(stop.kx, stop.kz, t.StopClear)
		add(stop.x, stop.z, t.StopClear)
	end
	for _, station in Map.GasStations do
		add(station.x, station.z, t.GasClear)
	end
	for _, alley in Shortcuts.alleys() do
		for _, mouth in alley.mouths do
			add(mouth.x, mouth.z, t.Clear)
		end
		add(alley.sign.x, alley.sign.z, t.Clear)
	end
	for _, line in ZipLines.lines() do
		for _, ladder in { line.ladderA, line.ladderB } do
			add(ladder.x, ladder.z, t.LadderClear)
			add(ladder.x + ladder.nx * 3.5, ladder.z + ladder.nz * 3.5, t.LadderClear)
		end
	end
	for _, dock in RentalDocks.docks() do
		add(dock.x, dock.z, t.Clear + dock.length / 2)
		for _, slot in dock.slots do
			add(slot.x, slot.z, t.Clear)
		end
	end
	for _, crosswalk in Crossings.crosswalks() do
		add(crosswalk.x, crosswalk.z, t.Clear)
	end
	grid = made
	return made
end

-- Is (x, z) clear of everything a prop keeps away from, with r more room?
function StreetProps.clear(x: number, z: number, r: number?): boolean
	if Map.isSafe(x, z) then
		return false
	end
	local extra = r or 0
	local made = keeps()
	local gx, gz = math.floor(x / GRID), math.floor(z / GRID)
	for ax = gx - 1, gx + 1 do
		for az = gz - 1, gz + 1 do
			local list = made[`{ax},{az}`]
			if list then
				for _, keep in list do
					local reach = keep.r + extra
					if (x - keep.x) ^ 2 + (z - keep.z) ^ 2 < reach * reach then
						return false
					end
				end
			end
		end
	end
	return true
end

-- ── The bus lines' streets ─────────────────────────────────────────────────

-- Is the road centre line through (x, z), along X (alongX) or Z, part of a bus line's loop (within its corners)?
function StreetProps.onBusLine(x: number, z: number, alongX: boolean): boolean
	for _, def in Config.Bus.Lines do
		local corners = def.corners
		for n = 1, #corners do
			local a, b = corners[n], corners[n % #corners + 1]
			if alongX and a[2] == b[2] and math.abs(z - a[2]) < 1 then
				if x >= math.min(a[1], b[1]) - CELL / 2 and x <= math.max(a[1], b[1]) + CELL / 2 then
					return true
				end
			elseif not alongX and a[1] == b[1] and math.abs(x - a[1]) < 1 then
				if z >= math.min(a[2], b[2]) - CELL / 2 and z <= math.max(a[2], b[2]) + CELL / 2 then
					return true
				end
			end
		end
	end
	return false
end

-- Does a road other than the street (along X or Z) come within its width / 2 + margin of (x, z)?
local function nearOtherRoad(x: number, z: number, alongX: boolean, margin: number): boolean
	for _, s in Map.Segments do
		local dx, dz = s.bx - s.ax, s.bz - s.az
		local length = math.sqrt(dx * dx + dz * dz)
		if length < 1e-6 then
			continue
		end
		local parallel = if alongX then math.abs(dz) / length < 0.05 else math.abs(dx) / length < 0.05
		local t = math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / (length * length), 0, 1)
		local distance = math.sqrt((x - s.ax - dx * t) ^ 2 + (z - s.az - dz * t) ^ 2)
		if not parallel and distance < s.width / 2 + margin then
			return true
		end
	end
	return false
end

-- ── The blocks ─────────────────────────────────────────────────────────────

local function pick(rand: () -> number, weights: { [string]: number }): string
	local total = 0
	for _, kind in ORDER do
		total += weights[kind] or 0
	end
	local roll = rand() * total
	for _, kind in ORDER do
		local w = weights[kind] or 0
		if roll < w then
			return kind
		end
		roll -= w
	end
	return "bin"
end

-- The four sides of a block: (nx, nz) out of it, (tx, tz) along it.
local SIDES = { { 0, -1, 1, 0 }, { 1, 0, 0, 1 }, { 0, 1, -1, 0 }, { -1, 0, 0, -1 } }

-- The Downtown towers on this side of the block (out (nx, nz), along (tx, tz)): each wall's distance in from the curb
-- and its span along the side (from the side's middle, along (tx, tz)).
local function towerWalls(lots: { Map.Lot }, cx: number, cz: number, nx: number, nz: number, tx: number, tz: number): { { number } }
	local walls: { { number } } = {}
	for _, lot in lots do
		if lot.kind ~= "tower" and lot.kind ~= "apartment" then
			continue
		end
		local onSide = (nx ~= 0 and (lot.a == 0) == (nx < 0)) or (nz ~= 0 and (lot.b == 0) == (nz < 0))
		if not onSide then
			continue
		end
		local inward = if nx ~= 0 then lot.w / 2 else lot.d / 2
		local reach = if nx ~= 0 then lot.d / 2 else lot.w / 2
		local outer = (lot.x - cx) * nx + (lot.z - cz) * nz + inward -- the wall, out from the block's middle
		local middle = (lot.x - cx) * tx + (lot.z - cz) * tz
		table.insert(walls, { BLOCK / 2 - outer, middle - reach, middle + reach })
	end
	return walls
end

local function blockProps(d: Map.District, i: number, j: number, index: number): { Prop }
	local t = Config.LivingCity.Street
	local rand = Map.lcg(Config.City.Seed * 3 + index * 7919 + (i + 50) * 211 + (j + 50) * 17 + 570)
	local cx, cz = d.ox + i * CELL, d.oz + j * CELL
	local lots = Map.lotsAt(d.id, i, j)
	local props: { Prop } = {}
	local weights = WEIGHTS[d.style] or WEIGHTS.downtown
	local count = t.Props[1] + math.floor(rand() * (t.Props[2] - t.Props[1] + 1))
	if d.style == "harbor" then
		count = math.ceil(count / 2)
	end
	local function spaced(x: number, z: number, half: number): boolean
		for _, other in props do
			local gap = t.Spacing + half + (HALF[other.kind] or 1)
			if (x - other.x) ^ 2 + (z - other.z) ^ 2 < gap * gap then
				return false
			end
		end
		return true
	end
	local function add(kind: string, x: number, z: number, nx: number, nz: number, road: boolean, width: number)
		table.insert(props, { kind = kind, x = x, z = z, nx = nx, nz = nz, road = road, width = width, turn = (rand() - 0.5) * 0.3, seed = math.floor(rand() * 1e6) })
	end

	-- The sidewalk props.
	local tries = 0
	local placed = 0
	while placed < count and tries < count * 8 do
		tries += 1
		local side = SIDES[math.floor(rand() * 4) + 1]
		local nx, nz, tx, tz = side[1], side[2], side[3], side[4]
		local kind = pick(rand, weights)
		local along = (rand() * 2 - 1) * (BLOCK / 2 - t.CornerClear - (HALF[kind] or 1))
		local depth = t.CurbDepth
		local width = HALF[kind] * 2
		if kind == "bags" or kind == "boarded" then
			-- against a tower's street wall on this side, inside its span (else: a kerb bin instead)
			local walls = towerWalls(lots, cx, cz, nx, nz, tx, tz)
			local wall = if #walls > 0 then walls[math.floor(rand() * #walls) + 1] else nil
			if wall and wall[3] - wall[2] > HALF[kind] * 2 + 4 then
				along = wall[2] + 2 + HALF[kind] + rand() * (wall[3] - wall[2] - 4 - HALF[kind] * 2)
				depth = wall[1] - (if kind == "bags" then 1 else 0.35)
				if kind == "boarded" then
					width = math.min(8, wall[3] - wall[2] - 6)
					along = math.clamp(along, wall[2] + 3 + width / 2, wall[3] - 3 - width / 2)
				end
			else
				kind = "bin"
				width = HALF.bin * 2
			end
		end
		local out = BLOCK / 2 - depth
		local x, z = cx + nx * out + tx * along, cz + nz * out + tz * along
		if math.abs(along) + width / 2 > BLOCK / 2 - t.CornerClear then
			continue
		end
		if not StreetProps.clear(x, z, width / 2) or not spaced(x, z, width / 2) then
			continue
		end
		add(kind, x, z, nx, nz, false, width)
		placed += 1
	end

	-- An abandoned car at the kerb now and then (a flare by it), never where a bus drives or a road comes in.
	for _, side in SIDES do
		local nx, nz, tx, tz = side[1], side[2], side[3], side[4]
		local roll, at = rand(), rand()
		if roll >= t.CarShare or d.style == "harbor" and roll >= t.CarShare / 2 then
			continue
		end
		local alongX = nz ~= 0 -- the street runs along X on a north or south side
		local roadX, roadZ = if nx ~= 0 then cx + nx * CELL / 2 else cx, if nz ~= 0 then cz + nz * CELL / 2 else cz
		if StreetProps.onBusLine(roadX, roadZ, alongX) then
			continue
		end
		local length = 11
		local along = (at * 2 - 1) * (BLOCK / 2 - t.CarCornerClear - length / 2)
		local out = BLOCK / 2 + t.CarKerb
		local x, z = cx + nx * out + tx * along, cz + nz * out + tz * along
		if not StreetProps.clear(x, z, length / 2) or nearOtherRoad(x, z, alongX, 8) then
			continue
		end
		add("car", x, z, nx, nz, true, length)
		if rand() < t.FlareShare then
			local fx, fz = cx + nx * (BLOCK / 2 - 1) + tx * (along - length / 2 - 1.5), cz + nz * (BLOCK / 2 - 1) + tz * (along - length / 2 - 1.5)
			if StreetProps.clear(fx, fz) then
				add("flare", fx, fz, nx, nz, false, 0.6)
			end
		end
	end

	-- A flare by a wreck on a lot (a parking lot's, a burnt-out Suburbs lot's: World puts it in the lot's middle),
	-- toward the lot's street; not on an alley's lots (the alley takes the wreck away).
	for _, lot in lots do
		if (lot.kind == "parking" or lot.kind == "wreck") and rand() < t.FlareShare * 0.5 then
			local onAlley = false
			for _, alley in Shortcuts.alleys() do
				for _, used in alley.lots do
					if used == lot then
						onAlley = true
					end
				end
			end
			local fx, fz = lot.x + lot.facing.x * 9, lot.z + lot.facing.z * 9
			if not onAlley and StreetProps.clear(fx, fz) then
				add("flare", fx, fz, lot.facing.x, lot.facing.z, false, 0.6)
			end
		end
	end
	return props
end

local cache: { Block }? = nil

function StreetProps.blocks(): { Block }
	if cache then
		return cache
	end
	local list: { Block } = {}
	for index, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				if Map.special(d.id, i, j) then
					continue
				end
				local props = blockProps(d, i, j, index)
				if #props > 0 then
					table.insert(list, { district = d.id, i = i, j = j, props = props })
				end
			end
		end
	end
	cache = list
	return list
end

return StreetProps
