-- 5.6, ZDC RIDE's docks (shared/RentalDocks.luau): about 20 docks on the kerbs of Downtown and the Suburbs, 2 – 3
-- scooters each, near a block corner past the crosswalk, off the people's walk line, clear of the homes, storefronts,
-- cargo spots, bus stops, gas stations, places and the alley shortcuts, out of the safe zone with one just outside it by
-- the depot; and clear of the zip lines' ladders. 6.3: and first of all the rack at the spawn, in the depot's yard by the
-- spawn pad. In the standalone Luau CLI.
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
local downtown, suburbs, scooters, depot, spawns = 0, 0, 0, 0, 0
for _, dock in docks do
	scooters += #dock.slots
	if dock.spawn then
		spawns += 1
		continue
	end
	if dock.district == "downtown" then
		downtown += 1
	else
		suburbs += 1
	end
	if dock.depot then
		depot += 1
	end
end
print(`  {#docks} docks (the spawn's rack, {downtown} Downtown, {suburbs} in the Suburbs), {scooters} scooters`)
check("about 20 docks on the kerbs", downtown + suburbs >= 16 and downtown + suburbs <= tuning.Docks, downtown + suburbs)
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
	if dock.spawn then
		-- 6.3: the spawn's rack, its own rules (below), then the same clearances as every dock.
	else
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
		if not dock.spawn then
			check(`{dock.id}: clear by the rules`, RentalDocks.clear(slot.x, slot.z))
		end
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

-- Spread out (6.3: the spawn's rack aside, in the safe zone), and the one by the depot (the first on the kerbs, nearest
-- the middle of the safe zone: 6.11, the park's; the depot has its rack).
local closest = math.huge
for n, a in docks do
	for m, b in docks do
		if n < m and not a.spawn and not b.spawn then
			closest = math.min(closest, math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2))
		end
	end
end
check("no two docks within Spacing", closest >= tuning.Spacing, closest)
check("one dock by the depot, the first on the kerbs", depot == 1 and docks[2].depot)
local byDepot = docks[2]
local outside = math.max(math.abs(byDepot.x), math.abs(byDepot.z)) - Config.City.SafeHalf
print(string.format("  by the depot: %s, %.0f studs out of the safe zone", byDepot.name, outside))
check("the depot's dock just outside the safe zone", outside > 0 and outside < 40, outside)

-- 6.3: the rack at the spawn: the first dock, the only one in the safe zone, in the depot's yard within 30 studs of
-- the spawn (server/World.luau's DepotSpawn: 26 south of the depot's middle, a 10 × 10 pad; 6.11: the depot is
-- Map.Depot) and more than 8 clear of the pad, behind it (the shed, the job board and Marge are in front), its scooters
-- side by side facing the yard's open south edge.
do
	local rack = docks[1]
	local spec = tuning.SpawnRack
	check("one spawn rack, the first dock", spawns == 1 and rack.spawn and not rack.depot and rack.id == "dock1")
	check("the spawn rack holds its scooters", #rack.slots == spec.slots and spec.slots >= 4, #rack.slots)
	local ox, oz = Map.Depot.x, Map.Depot.z
	local spawnX, spawnZ, pad = ox, oz + 26, 5
	local farthest, padGap, offBlock = 0, math.huge, false
	local d, i, j = Map.blockAt(rack.x, rack.z)
	check("the spawn rack stands on the depot's block", d ~= nil and Map.special(d.id, i, j) == "depot" and i == Map.Depot.i and j == Map.Depot.j)
	for n, slot in rack.slots do
		farthest = math.max(farthest, math.sqrt((slot.x - spawnX) ^ 2 + (slot.z - spawnZ) ^ 2))
		-- (the scooter's body: a stud and a half each side, 2.5 ahead and behind)
		local gapX = math.max(0, math.abs(slot.x - spawnX) - pad - 1.5)
		local gapZ = math.max(0, math.abs(slot.z - spawnZ) - pad - 2.5)
		padGap = math.min(padGap, math.sqrt(gapX * gapX + gapZ * gapZ))
		offBlock = offBlock or math.abs(slot.x - ox) > half - 6 or math.abs(slot.z - oz) > half - 6 or Map.onRoad(slot.x, slot.z)
		check(`spawn rack slot {n}: in the safe zone`, Map.isSafe(slot.x, slot.z))
		check(`spawn rack slot {n}: behind the spawn pad, out of the shed's way`, slot.z > spawnZ + pad and slot.z - oz > -9 + 20)
		if n > 1 then
			local prev = rack.slots[n - 1]
			check(`spawn rack slot {n}: side by side with the one before`, math.abs(slot.x - prev.x - spec.pitch) < 1e-6 and slot.z == prev.z)
		end
	end
	check("the spawn rack within 30 studs of the spawn", farthest <= 30, farthest)
	check("the spawn rack clear of the spawn pad", padGap > 8, padGap)
	check("the spawn rack in the yard, off the road", not offBlock)
	check("the spawn rack faces the yard's open edge", rack.nx == 0 and rack.nz == 1 and rack.tx == 1 and rack.tz == 0)
	local near, far = RentalDocks.nearest(spawnX, spawnZ)
	check("the nearest dock to the spawn is its rack", near == rack and far < 30, far)
end

-- The nearest dock.
local dock, far = RentalDocks.nearest(docks[3].x + 1, docks[3].z)
check("the nearest dock", dock == docks[3] and math.abs(far - 1) < 1e-6)
check("a dock by its id", RentalDocks.dock(docks[2].id) == docks[2] and RentalDocks.dock("nope") == nil)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
