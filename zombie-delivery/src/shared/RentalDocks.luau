--!strict
-- 5.6, ZDC RIDE: where the rental e-scooter docks stand (Config.Rental), as plain numbers. server/Rental.luau builds
-- them and runs the rentals, client/MapView.luau marks them on the maps, the phone's GARAGE app names the nearest
-- one (client/PhoneApps.luau); tests/rentaldocks_test.luau checks them. Pure Luau.
--
-- A dock stands on the sidewalk of an ordinary Downtown or Suburbs block, along one side of it near a corner: it starts
-- Config.Rental.Start studs from the corner (past the crosswalk and the corner's lamp or light pole) and holds 2 – 3
-- scooters nose to tail along the kerb, Config.Rental.Depth in from the curb (the people walk 4.5 in:
-- shared/TrafficLanes.luau). Every block corner and side is a candidate; Map.lcg orders them (the same everywhere),
-- and a dock is kept when it is clear (Config.Rental: of the homes' and storefronts' doors, piles and parks, the cargo
-- spots, the employers' boards, the addresses, the bus stops, the gas stations, the places, the alley shortcuts' mouths,
-- the zip lines' ladders, the safe zone) and no other dock is within Spacing. The first one is the clear candidate nearest the depot (just
-- outside the safe zone); then at most DowntownDocks Downtown and the rest in the Suburbs, Docks in all.
--
--   RentalDocks.docks()            every dock (cached)
--   RentalDocks.dock(id)           one by its id ("dock3"), or nil
--   RentalDocks.nearest(x, z)      the nearest dock and its distance (along the ground, straight)
--   RentalDocks.clear(x, z)        is a dock allowed to stand here (the rules above, but the spacing)?

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local BusLines = require(script.Parent.BusLines)
local Shortcuts = require(script.Parent.Shortcuts)
local ZipLines = require(script.Parent.ZipLines)

local RentalDocks = {}

export type Slot = { x: number, z: number } -- a docked scooter's middle on the ground
export type Dock = {
	id: string, -- "dock1" …
	name: string, -- "Maple St · 3rd Ave": the street it stands on, the corner's cross street
	district: string,
	i: number, -- the block
	j: number,
	x: number, -- the dock's middle (on the sidewalk)
	z: number,
	nx: number, -- out of the block, toward the street (unit, along X or Z)
	nz: number,
	tx: number, -- along the kerb, the way the scooters face (unit)
	tz: number,
	length: number, -- along the kerb
	slots: { Slot },
	depot: boolean, -- the one by the depot
}

local BLOCK = Map.BlockSize

-- The street a block side faces (the names as Map.addresses gives them).
local function streetOf(d: Map.District, i: number, j: number, nx: number, nz: number): string
	if nz ~= 0 then
		local k = j + (if nz > 0 then 0 else -1) - d.j0 + 1
		return d.streets[k % #d.streets + 1]
	end
	local k = i + (if nx > 0 then 0 else -1) - d.i0 + 1
	return d.avenues[k % #d.avenues + 1]
end

-- What a dock keeps away from: points with a radius, bucketed in a grid of CELL studs (no radius is bigger), built once.
local CELL = 64
type Keep = { x: number, z: number, r: number }
local grid: { [string]: { Keep } }? = nil

local function keeps(): { [string]: { Keep } }
	if grid then
		return grid
	end
	local r = Config.Rental
	local made: { [string]: { Keep } } = {}
	local function add(x: number, z: number, radius: number)
		local key = `{math.floor(x / CELL)},{math.floor(z / CELL)}`
		local list = made[key]
		if not list then
			list = {}
			made[key] = list
		end
		table.insert(list, { x = x, z = z, r = radius })
	end
	for _, home in Map.Homes do
		add(home.door.x, home.door.z, r.Clear)
		add(home.pile.x, home.pile.z, r.Clear)
		add(home.park.x, home.park.z, r.ParkClear)
	end
	for _, venue in Map.Venues do
		add(venue.door.x, venue.door.z, r.Clear)
		add(venue.pile.x, venue.pile.z, r.Clear)
		add(venue.park.x, venue.park.z, r.ParkClear)
	end
	for _, spot in Map.CargoSpots do
		add(spot.park.x, spot.park.z, r.Clear)
		add(spot.pile.x, spot.pile.z, r.Clear)
	end
	for _, spot in Map.EmployerSpots do
		add(spot.x, spot.z, r.Clear)
	end
	for _, address in Map.addresses() do
		add(address.x, address.z, r.Clear)
	end
	for _, place in Map.Places do
		add(place.x, place.z, r.PlaceClear)
	end
	for _, plot in Map.EstatePlots do
		add(plot.x, plot.z, r.PlaceClear)
	end
	for _, stop in BusLines.allStops() do
		add(stop.kx, stop.kz, r.StopClear)
		add(stop.x, stop.z, r.StopClear)
	end
	for _, station in Map.GasStations do
		add(station.x, station.z, r.GasClear)
	end
	for _, alley in Shortcuts.alleys() do
		for _, mouth in alley.mouths do
			add(mouth.x, mouth.z, r.Clear)
		end
	end
	for _, line in ZipLines.lines() do
		for _, ladder in { line.ladderA, line.ladderB } do
			add(ladder.x + ladder.nx * 3.5, ladder.z + ladder.nz * 3.5, r.Clear)
		end
	end
	grid = made
	return made
end

-- Is (x, z) clear of everything a dock keeps away from (RentalDocks.clear: the tests ask too)?
local function clearAt(x: number, z: number): boolean
	if Map.isSafe(x, z) then
		return false
	end
	local made = keeps()
	local gx, gz = math.floor(x / CELL), math.floor(z / CELL)
	for ax = gx - 1, gx + 1 do
		for az = gz - 1, gz + 1 do
			local list = made[`{ax},{az}`]
			if list then
				for _, keep in list do
					if (x - keep.x) ^ 2 + (z - keep.z) ^ 2 < keep.r * keep.r then
						return false
					end
				end
			end
		end
	end
	return true
end
RentalDocks.clear = clearAt

-- A dock on block (i, j) of d, on its side facing (nx, nz), at the corner toward (cx, cz) + (sx, sz) × half, with
-- `count` scooters; nil when it is not clear.
local function candidate(d: Map.District, i: number, j: number, nx: number, nz: number, sx: number, sz: number, count: number): Dock?
	local r = Config.Rental
	local half = BLOCK / 2
	local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
	-- along the kerb from the corner toward the side's middle
	local tx, tz = if nx ~= 0 then 0 else -sx, if nz ~= 0 then 0 else -sz
	local cornerX = if nx ~= 0 then cx + nx * (half - r.Depth) else cx + sx * half
	local cornerZ = if nz ~= 0 then cz + nz * (half - r.Depth) else cz + sz * half
	local length = count * r.SlotPitch
	local slots: { Slot } = {}
	for n = 1, count do
		local along = r.Start + r.SlotPitch * (n - 0.5)
		table.insert(slots, { x = cornerX + tx * along, z = cornerZ + tz * along })
	end
	local mid = r.Start + length / 2
	local x, z = cornerX + tx * mid, cornerZ + tz * mid
	-- the dock's ends and middle, and every scooter
	local checks: { Slot } = { { x = x, z = z }, { x = cornerX + tx * r.Start, z = cornerZ + tz * r.Start }, { x = cornerX + tx * (r.Start + length), z = cornerZ + tz * (r.Start + length) } }
	for _, slot in slots do
		table.insert(checks, slot)
	end
	for _, point in checks do
		if not clearAt(point.x, point.z) then
			return nil
		end
	end
	local street = streetOf(d, i, j, nx, nz)
	local cross = if nx ~= 0 then streetOf(d, i, j, 0, sz) else streetOf(d, i, j, sx, 0)
	return {
		id = "",
		name = `{street} · {cross}`,
		district = d.id,
		i = i,
		j = j,
		x = x,
		z = z,
		nx = nx,
		nz = nz,
		tx = tx,
		tz = tz,
		length = length,
		slots = slots,
		depot = false,
	}
end

local cache: { Dock }? = nil

function RentalDocks.docks(): { Dock }
	if cache then
		return cache
	end
	local r = Config.Rental
	local rand = Map.lcg(Config.City.Seed + 560)
	type Candidate = { dock: Dock, key: number }
	local candidates: { Candidate } = {}
	for _, d in Map.Districts do
		if d.style ~= "downtown" and d.style ~= "suburbs" then
			continue
		end
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				if Map.special(d.id, i, j) then
					continue
				end
				for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
					local sx, sz = corner[1], corner[2]
					for side = 1, 2 do
						-- (every candidate rolls the same dice, kept or not)
						local key, count = rand(), r.Slots[1 + math.floor(rand() * #r.Slots)]
						local nx, nz = if side == 1 then sx else 0, if side == 1 then 0 else sz
						local dock = candidate(d, i, j, nx, nz, sx, sz, count)
						if not dock and count > r.Slots[1] then
							dock = candidate(d, i, j, nx, nz, sx, sz, r.Slots[1])
						end
						if dock then
							table.insert(candidates, { dock = dock, key = key })
						end
					end
				end
			end
		end
	end
	table.sort(candidates, function(p: Candidate, q: Candidate): boolean
		return p.key < q.key
	end)
	-- The one by the depot first (the clear candidate nearest the middle of the safe zone).
	local first: Candidate? = nil
	for _, c in candidates do
		if not first or c.dock.x ^ 2 + c.dock.z ^ 2 < first.dock.x ^ 2 + first.dock.z ^ 2 then
			first = c
		end
	end
	local list: { Dock } = {}
	local downtown, suburbs = 0, 0
	local function take(dock: Dock): boolean
		for _, other in list do
			if (other.x - dock.x) ^ 2 + (other.z - dock.z) ^ 2 < r.Spacing * r.Spacing then
				return false
			end
		end
		if dock.district == "downtown" then
			if downtown >= r.DowntownDocks then
				return false
			end
			downtown += 1
		else
			if suburbs >= r.Docks - r.DowntownDocks then
				return false
			end
			suburbs += 1
		end
		table.insert(list, dock)
		dock.id = `dock{#list}`
		return true
	end
	if first then
		first.dock.depot = true
		take(first.dock)
	end
	for _, c in candidates do
		if #list >= r.Docks then
			break
		end
		if c ~= first then
			take(c.dock)
		end
	end
	cache = list
	return list
end

function RentalDocks.dock(id: string): Dock?
	for _, dock in RentalDocks.docks() do
		if dock.id == id then
			return dock
		end
	end
	return nil
end

function RentalDocks.nearest(x: number, z: number): (Dock?, number)
	local best: Dock? = nil
	local bestD = math.huge
	for _, dock in RentalDocks.docks() do
		local dd = math.sqrt((dock.x - x) ^ 2 + (dock.z - z) ^ 2)
		if dd < bestD then
			best, bestD = dock, dd
		end
	end
	return best, bestD
end

return RentalDocks
