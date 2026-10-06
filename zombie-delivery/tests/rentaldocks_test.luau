-- 5.6, ZDC RIDE's docks (shared/RentalDocks.luau): about 20 docks on the kerbs of Downtown and the Suburbs, 2 – 3
-- scooters each, near a block corner past the crosswalk, off the people's walk line, clear of the homes, storefronts,
-- cargo spots, bus stops, gas stations, places and the alley shortcuts, out of the safe zone with one just outside it by
-- the depot; and clear of the zip lines' ladders. In the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local BusLines = require("./BusLines")
local TrafficLanes = require("./TrafficLanes")
local Shortcuts = require("./Shortcuts")
local ZipLines = require("./ZipLines")
local RentalDocks = require("./RentalDocks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local tuning = Config.Rental
local docks = RentalDocks.docks()
local downtown, suburbs, scooters, depot = 0, 0, 0, 0
for _, dock in docks do
	if dock.district == "downtown" then
		downtown += 1
	else
		suburbs += 1
	end
	scooters += #dock.slots
	if dock.depot then
		depot += 1
	end
end
print(`  {#docks} docks ({downtown} Downtown, {suburbs} in the Suburbs), {scooters} scooters`)
check("about 20 docks", #docks >= 16 and #docks <= tuning.Docks, #docks)
check("Downtown and the Suburbs both have docks", downtown >= 8 and downtown <= tuning.DowntownDocks and suburbs >= 4, `{downtown} / {suburbs}`)
check("the docks are cached", RentalDocks.docks() == docks)
check("a rental is the E-Scooter, free", tuning.CarId == "escooter" and tuning.Price == 0)
local car: Config.CarDef? = nil
for _, def in Config.Cars do
	if def.id == tuning.CarId then
		car = def
	end
end
check("the rental's car exists and is a standing scooter", car ~= nil and car.bike == true and car.stand == true)

local ids: { [string]: boolean } = {}
local half = Map.BlockSize / 2
for _, dock in docks do
	local d = Map.districtById(dock.district)
	local cx, cz = d.ox + dock.i * Map.Cell, d.oz + dock.j * Map.Cell
	check(`{dock.id} ({dock.name}): a unique id and a name`, not ids[dock.id] and #dock.name > 3)
	ids[dock.id] = true
	check(`{dock.id}: an ordinary block of Downtown or the Suburbs`, (dock.district == "downtown" or dock.district == "suburbs") and Map.special(dock.district, dock.i, dock.j) == nil)
	check(`{dock.id}: 2 – 3 scooters`, #dock.slots >= 2 and #dock.slots <= 3, #dock.slots)
	check(`{dock.id}: the scooters along the kerb (the dock's way), toward the street`, math.abs(dock.tx * dock.nx + dock.tz * dock.nz) < 1e-9 and math.abs(dock.nx) + math.abs(dock.nz) == 1 and math.abs(dock.tx) + math.abs(dock.tz) == 1)
	for n, slot in dock.slots do
		-- in from the curb by Depth (off the people's walk line), on the block's sidewalk, past the corner's crosswalk
		local fromCurb = half - (if dock.nx ~= 0 then dock.nx * (slot.x - cx) else dock.nz * (slot.z - cz))
		local fromCorner = half - math.abs(if dock.nx ~= 0 then slot.z - cz else slot.x - cx)
		check(`{dock.id} slot {n}: on the sidewalk, {tuning.Depth} in from the curb`, math.abs(fromCurb - tuning.Depth) < 1e-6, fromCurb)
		check(`{dock.id} slot {n}: off the people's walk line`, fromCurb + 1 <= TrafficLanes.SidewalkInset - 0.5)
		check(`{dock.id} slot {n}: past the crosswalk and the corner's pole`, fromCorner >= tuning.Start + tuning.SlotPitch / 2 - 1e-6 and fromCorner < half - 10, fromCorner)
		check(`{dock.id} slot {n}: out of the safe zone`, not Map.isSafe(slot.x, slot.z))
		if n > 1 then
			local prev = dock.slots[n - 1]
			check(`{dock.id} slot {n}: a scooter's length from the one before`, math.abs(math.sqrt((slot.x - prev.x) ^ 2 + (slot.z - prev.z) ^ 2) - tuning.SlotPitch) < 1e-6)
		end
	end
	-- Clear of the homes, the storefronts, the cargo spots, the bus stops, the gas stations, the places, the alleys.
	local worst, worstPark, worstStop, worstGas, worstPlace = math.huge, math.huge, math.huge, math.huge, math.huge
	for _, slot in dock.slots do
		local function dist(x: number, z: number): number
			return math.sqrt((slot.x - x) ^ 2 + (slot.z - z) ^ 2)
		end
		for _, home in Map.Homes do
			worst = math.min(worst, dist(home.door.x, home.door.z), dist(home.pile.x, home.pile.z))
			worstPark = math.min(worstPark, dist(home.park.x, home.park.z))
		end
		for _, venue in Map.Venues do
			worst = math.min(worst, dist(venue.door.x, venue.door.z), dist(venue.pile.x, venue.pile.z))
			worstPark = math.min(worstPark, dist(venue.park.x, venue.park.z))
		end
		for _, spot in Map.CargoSpots do
			worst = math.min(worst, dist(spot.park.x, spot.park.z), dist(spot.pile.x, spot.pile.z))
		end
		for _, alley in Shortcuts.alleys() do
			for _, mouth in alley.mouths do
				worst = math.min(worst, dist(mouth.x, mouth.z))
			end
		end
		for _, stop in BusLines.allStops() do
			worstStop = math.min(worstStop, dist(stop.kx, stop.kz), dist(stop.x, stop.z))
		end
		for _, station in Map.GasStations do
			worstGas = math.min(worstGas, dist(station.x, station.z))
		end
		for _, place in Map.Places do
			worstPlace = math.min(worstPlace, dist(place.x, place.z))
		end
		check(`{dock.id}: clear by the rules`, RentalDocks.clear(slot.x, slot.z))
	end
	check(`{dock.id}: clear of doors, piles, cargo spots and alley mouths`, worst >= tuning.Clear, worst)
	check(`{dock.id}: clear of the parks on the road`, worstPark >= tuning.ParkClear, worstPark)
	check(`{dock.id}: clear of the bus stops`, worstStop >= tuning.StopClear, worstStop)
	check(`{dock.id}: clear of the gas stations`, worstGas >= tuning.GasClear, worstGas)
	check(`{dock.id}: clear of the places`, worstPlace >= tuning.PlaceClear, worstPlace)
	-- Not where a zip line's ladder comes down (its foot, where Climb down puts you).
	local ladder = math.huge
	for _, line in ZipLines.lines() do
		for _, l in { line.ladderA, line.ladderB } do
			for _, slot in dock.slots do
				ladder = math.min(ladder, math.sqrt((slot.x - l.x - l.nx * 3.5) ^ 2 + (slot.z - l.z - l.nz * 3.5) ^ 2))
			end
		end
	end
	check(`{dock.id}: clear of the zip lines' ladders`, ladder >= tuning.Clear, ladder)
end

-- Spread out, and the one by the depot.
local closest = math.huge
for n, a in docks do
	for m, b in docks do
		if n < m then
			closest = math.min(closest, math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2))
		end
	end
end
check("no two docks within Spacing", closest >= tuning.Spacing, closest)
check("one dock by the depot", depot == 1 and docks[1].depot)
local byDepot = docks[1]
local outside = math.max(math.abs(byDepot.x), math.abs(byDepot.z)) - Config.City.SafeHalf
print(string.format("  by the depot: %s, %.0f studs out of the safe zone", byDepot.name, outside))
check("the depot's dock just outside the safe zone", outside > 0 and outside < 40, outside)

-- The nearest dock.
local dock, far = RentalDocks.nearest(docks[3].x + 1, docks[3].z)
check("the nearest dock", dock == docks[3] and math.abs(far - 1) < 1e-6)
check("a dock by its id", RentalDocks.dock(docks[2].id) == docks[2] and RentalDocks.dock("nope") == nil)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
