-- 6.11, the centre (shared/Map.luau Map.Park, Map.Depot, Map.FormerBlocks): the Central Park on the middle block, its
-- pond in the very middle of the map and of the safe zone, its layout leaving the people's walk line free; the depot on
-- block (1, -1) north-east of it with every spot of its yard (the spawn, the rack, the kiosk, the board, Marge) on its
-- block and in the safe zone, its yard open to Bone St; the depot's block was four towers: their dice still roll, so
-- every other lot and home of the city stays as it was (the lots made with the block ordinary again are the same); no
-- zip line, bus stop or dock on the new blocks, and no bus stop named after the depot far from it.
-- Run with tests/run_tests.py.
local Config = require("./Config")
local Map = require("./Map")
local BusLines = require("./BusLines")
local RentalDocks = require("./RentalDocks")
local ZipLines = require("./ZipLines")
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

local CELL, HALF = Map.Cell, Map.BlockSize / 2

-- ── The park ───────────────────────────────────────────────────────────────

local P = Map.Park
check("the park is the middle block", Map.special("downtown", P.i, P.j) == "park" and P.i == 0 and P.j == 0 and P.x == P.i * CELL and P.z == P.j * CELL)
check("the park's pond is the middle of the map's safe zone", Map.isSafe(P.x, P.z) and P.x == 0 and P.z == 0)
-- Its rings from the middle out: the pond (and its coping), the ring path, the benches by it, the trees' lawn, the
-- sidewalk band with the people's walk line (TrafficLanes: the line and its detours, a body each side).
local outermost = 0
for _, inset in TrafficLanes.DetourInsets do
	outermost = math.max(outermost, inset)
end
check("the sidewalk band holds the walk line and its detours", P.walk >= math.max(TrafficLanes.SidewalkInset, outermost) + TrafficLanes.Body, P.walk)
check("room for the coping, the ring path, the benches and the trees", P.pond + 1.5 + P.ring + 3 + 10 <= HALF - P.walk, HALF - P.walk - (P.pond + 1.5 + P.ring))
check("the island in the pond, the water round it wide enough to swim and to bridge", P.island > 3 and P.pond - 0.3 - P.island >= 10)
check("the pond deep enough to swim, its surface the top of a layer of Terrain cells", P.depth >= 3.5 and P.depth % 4 == 0)
check("the park's own dice (not the city's seeds)", P.seed ~= Config.City.Seed + 53 and P.seed ~= Config.City.Seed + 56 and P.seed ~= Config.City.Seed + 57)
check("no lots, homes or addresses on the park", #Map.lotsAt("downtown", P.i, P.j) == 0 and #Map.formerLotsAt("downtown", P.i, P.j) == 0)
local parkLandmark: Map.Landmark? = nil
for _, landmark in Map.Landmarks do
	if landmark.id == P.id then
		parkLandmark = landmark
	end
end
check("the park is a landmark (the map's list, the GPS, the location tag)", parkLandmark ~= nil and parkLandmark.x == P.x and parkLandmark.z == P.z and parkLandmark.name == P.name)

-- ── The depot ──────────────────────────────────────────────────────────────

local D = Map.Depot
check("the depot is block (1, -1), north-east of the park", Map.special("downtown", D.i, D.j) == "depot" and D.i == 1 and D.j == -1 and D.x == D.i * CELL and D.z == D.j * CELL)
check("the depot garage and the depot's landmark are its middle", Map.Shops.depot.x == D.x and Map.Shops.depot.z == D.z and (function()
	for _, landmark in Map.Landmarks do
		if landmark.id == "depot" then
			return landmark.x == D.x and landmark.z == D.z
		end
	end
	return false
end)())
-- Its yard's spots (from its middle): on its block, in the safe zone.
local function onDepot(x: number, z: number): boolean
	local d, i, j = Map.blockAt(x, z)
	return d ~= nil and d.id == "downtown" and i == D.i and j == D.j and Map.isSafe(x, z)
end
local rack = Config.Rental.SpawnRack
local spots = {
	spawn = { D.x, D.z + 26 },
	board = { D.x + Config.Goal.BoardSpot[1], D.z + Config.Goal.BoardSpot[2] },
	marge = { D.x + Config.Tutorial.NpcSpot[1], D.z + Config.Tutorial.NpcSpot[2] },
	bags = { Map.Shops.bags.x, Map.Shops.bags.z },
	rack = { D.x + rack.x, D.z + rack.z },
}
for name, spot in spots do
	check(`the depot's {name} on its block, in the safe zone`, onDepot(spot[1], spot[2]), `{spot[1]}, {spot[2]}`)
end
local rx, rz = Map.nearestRoad(D.x, D.z + 26)
check("the yard opens to Bone St, the street in front of the spawn (south)", math.abs(rx - D.x) < 1e-6 and math.abs(rz - (D.z + CELL / 2)) < 1e-6 and (function()
	local district = Map.districtById("downtown")
	local k = D.j - district.j0 + 1 -- (the street south of row j, as Map.addresses names it)
	return district.streets[k % #district.streets + 1] == "Bone St"
end)(), `{rx} {rz}`)
local first = RentalDocks.docks()[1]
check("the scooter rack at the spawn is the first dock, in the depot's yard", first.spawn and onDepot(first.x, first.z))

-- ── The rest of the city as it was ─────────────────────────────────────────

check("the depot's block was ordinary, the park's was not (it was the depot's)", Map.wasOrdinary("downtown", D.i, D.j) and not Map.wasOrdinary("downtown", P.i, P.j))
for districtId, blocks in Map.FormerBlocks do
	for key in blocks do
		local i, j = string.match(key, "^(-?%d+),(-?%d+)$")
		check(`a former block ({districtId} {key}) is special now`, i ~= nil and Map.special(districtId, tonumber(i) :: number, tonumber(j) :: number) ~= nil)
	end
end
local former = Map.formerLotsAt("downtown", D.i, D.j)
local towers = 0
for _, lot in former do
	if lot.kind == "tower" and lot.home == nil then
		towers += 1
	end
end
check("the depot's block had four plain towers (server/World.luau rolls their dice dry: tower(..., true))", #former == 4 and towers == 4, `{towers}/{#former}`)
check("nothing stands on the depot's block's lots any more", #Map.lotsAt("downtown", D.i, D.j) == 0)
-- The lots made with the depot's block ordinary again: every lot and home the same, its four the former ones.
do
	local savedSpecial, savedFormer = Map.SpecialBlocks.downtown["1,-1"], Map.FormerBlocks.downtown["1,-1"]
	Map.SpecialBlocks.downtown["1,-1"] = nil
	Map.FormerBlocks.downtown["1,-1"] = nil
	local before, homesBefore = Map.makeLots()
	Map.SpecialBlocks.downtown["1,-1"] = savedSpecial
	Map.FormerBlocks.downtown["1,-1"] = savedFormer
	local function same(a: Map.Lot, b: Map.Lot): boolean
		return a.kind == b.kind and a.x == b.x and a.z == b.z and a.w == b.w and a.d == b.d and a.h == b.h and a.seed == b.seed
			and a.facing.x == b.facing.x and a.facing.z == b.facing.z and (a.home == nil) == (b.home == nil)
	end
	local lotsSame, count = true, 0
	for districtId, blocks in before do
		for key, list in blocks do
			local now = if key == "1,-1" and districtId == "downtown" then former else (Map.AllLots[districtId][key] or {})
			if #now ~= #list then
				lotsSame = false
			end
			for n, lot in list do
				count += 1
				if not now[n] or not same(lot, now[n]) then
					lotsSame = false
				end
			end
		end
	end
	check("every lot of the city is as it was (the depot's four are its former lots)", lotsSame and count > 300, count)
	local homesSame = #homesBefore == #Map.Homes
	for n, home in homesBefore do
		local now = Map.Homes[n]
		homesSame = homesSame and now ~= nil and now.id == home.id and now.name == home.name and now.park.x == home.park.x and now.park.z == home.park.z
	end
	check("every home and address of a home is as it was", homesSame, `{#homesBefore} / {#Map.Homes}`)
end

-- ── Nothing of the city's on the new blocks ────────────────────────────────

local function onBlock(x: number, z: number, i: number, j: number): boolean
	return math.abs(x - i * CELL) <= HALF and math.abs(z - j * CELL) <= HALF
end
local zipsClear = true
for _, line in ZipLines.lines() do
	for _, lot in { line.start, line.finish } do
		if (lot.i == D.i and lot.j == D.j) or (lot.i == P.i and lot.j == P.j) then
			zipsClear = false
		end
	end
end
check("no zip line starts or ends on the park or the depot", zipsClear)
local stopsClear, namedFar = true, nil :: string?
for _, stop in BusLines.allStops() do
	if onBlock(stop.kx, stop.kz, D.i, D.j) or onBlock(stop.kx, stop.kz, P.i, P.j) then
		stopsClear = false
	end
	if stop.name == "Depot" and math.sqrt((stop.kx - D.x) ^ 2 + (stop.kz - D.z) ^ 2) > Config.Bus.NameReach then
		namedFar = stop.name
	end
end
check("no bus stop by the park's or the depot's kerb", stopsClear)
check("no bus stop named after the depot away from it (its pull stays on the park's middle, where no stop can stand)", namedFar == nil)
local docksClear = true
for _, dock in RentalDocks.docks() do
	if not dock.spawn and (onBlock(dock.x, dock.z, D.i, D.j) or onBlock(dock.x, dock.z, P.i, P.j)) then
		docksClear = false
	end
end
check("no dock on the park or the depot but the spawn's rack", docksClear)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
