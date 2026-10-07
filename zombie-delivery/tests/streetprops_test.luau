-- 5.7, the street props (shared/StreetProps.luau): bins, hydrants, barricades, sandbags, debris on the kerbs, trash
-- bags and boarded shopfronts at the towers, abandoned cars at the kerb and red flares; off the people's walk lines,
-- the corners, the doors, piles, parks, stops, docks, ladders and alleys, the cars off the bus lines and the traffic's
-- lane; in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local BusLines = require("./BusLines")
local TrafficLanes = require("./TrafficLanes")
local RentalDocks = require("./RentalDocks")
local Shortcuts = require("./Shortcuts")
local ZipLines = require("./ZipLines")
local StreetProps = require("./StreetProps")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local t = Config.LivingCity.Street
local blocks = StreetProps.blocks()
check("the props are cached (the same on every call)", StreetProps.blocks() == blocks)

local counts: { [string]: number } = {}
local total = 0
local byDistrict: { [string]: number } = {}
local bad: { [string]: { string } } = {}
local function fail(rule: string, what: string)
	bad[rule] = bad[rule] or {}
	table.insert(bad[rule], what)
end
local seen: { [string]: boolean } = {}
local half = Map.BlockSize / 2
local walkReach = TrafficLanes.SidewalkInset - TrafficLanes.Body -- the walk line's near edge, in from the curb
for _, block in blocks do
	local key = `{block.district}:{block.i},{block.j}`
	if seen[key] then
		fail("one entry a block", key)
	end
	seen[key] = true
	if Map.special(block.district, block.i, block.j) then
		fail("ordinary blocks only", key)
	end
	local d = Map.districtById(block.district)
	local cx, cz = d.ox + block.i * Map.Cell, d.oz + block.j * Map.Cell
	byDistrict[block.district] = (byDistrict[block.district] or 0) + #block.props
	for n, prop in block.props do
		total += 1
		counts[prop.kind] = (counts[prop.kind] or 0) + 1
		local name = `{key} {prop.kind} {n}`
		if not table.find(StreetProps.KerbKinds, prop.kind) and not table.find(StreetProps.WallKinds, prop.kind) and prop.kind ~= "car" and prop.kind ~= "flare" then
			fail("a known kind", name)
		end
		if Map.isSafe(prop.x, prop.z) then
			fail("never in the safe zone", name)
		end
		if not StreetProps.clear(prop.x, prop.z) then
			fail("clear of the doors, piles, parks, stops, docks, ladders, alleys and crosswalks", name)
		end
		-- along the side, from the side's middle, and in from the curb
		local rx, rz = prop.x - cx, prop.z - cz
		local along = if prop.nx ~= 0 then math.abs(rz) else math.abs(rx)
		local depth = half - (if prop.nx ~= 0 then math.abs(rx) else math.abs(rz))
		if prop.road then
			if prop.kind ~= "car" then
				fail("only a car on the road", name)
			end
			-- at the kerb, on the road, clear of the traffic's lane (its cars about 6 wide)
			local fromMiddle = Map.Cell / 2 + depth -- (depth < 0: out on the road)
			local laneEdge = TrafficLanes.laneOffset(Map.RoadWidth) + 3
			if depth > -1 or fromMiddle - 2.6 < laneEdge then
				fail("a car at the kerb, out of the traffic's lane", `{name} {fromMiddle}`)
			end
			if along + prop.width / 2 > half - t.CarCornerClear + 1e-6 then
				fail("a car away from the junctions", name)
			end
			local roadX = if prop.nx ~= 0 then cx + prop.nx * Map.Cell / 2 else prop.x
			local roadZ = if prop.nz ~= 0 then cz + prop.nz * Map.Cell / 2 else prop.z
			if StreetProps.onBusLine(roadX, roadZ, prop.nz ~= 0) then
				fail("no car on a bus line's street", name)
			end
			for _, stop in BusLines.allStops() do
				if (stop.x - prop.x) ^ 2 + (stop.z - prop.z) ^ 2 < 30 * 30 then
					fail("no car by a bus stop", name)
				end
			end
		else
			if depth < 0 or along > half then
				fail("on its block's sidewalk", name)
			end
			if prop.kind ~= "flare" and along + prop.width / 2 > half - t.CornerClear + 1e-6 then
				fail("away from the corners (crosswalks, lamps, poles)", name)
			end
			if table.find(StreetProps.KerbKinds, prop.kind) then
				-- between the curb and the walk line: a barricade's depth is the deepest, about 1.2 either way
				if math.abs(depth - t.CurbDepth) > 1e-6 or depth + 1.3 > walkReach then
					fail("a kerb prop on the kerb, off the walk line", `{name} {depth}`)
				end
			elseif table.find(StreetProps.WallKinds, prop.kind) then
				if block.district ~= "downtown" or depth < TrafficLanes.DetourInsets[#TrafficLanes.DetourInsets] + 1 then
					fail("bags and boards against a Downtown tower, behind the walk lines", `{name} {depth}`)
				end
			end
		end
		for m, other in block.props do
			if m > n and other.kind ~= "flare" and prop.kind ~= "flare" and not other.road and not prop.road then
				if (other.x - prop.x) ^ 2 + (other.z - prop.z) ^ 2 < t.Spacing * t.Spacing then
					fail("no two props crowded", name)
				end
			end
		end
	end
end
-- The things a prop keeps away from, asked directly (a sample of each).
for _, alley in Shortcuts.alleys() do
	check(`{alley.name}: its mouths are kept clear`, not StreetProps.clear(alley.mouths[1].x, alley.mouths[1].z) and not StreetProps.clear(alley.mouths[2].x, alley.mouths[2].z))
end
for _, dock in RentalDocks.docks() do
	if StreetProps.clear(dock.x, dock.z) then
		fail("the docks are kept clear", dock.name)
	end
end
for _, line in ZipLines.lines() do
	if StreetProps.clear(line.ladderA.x, line.ladderA.z) or StreetProps.clear(line.ladderB.x, line.ladderB.z) then
		fail("the zip ladders are kept clear", line.name)
	end
end
for _, home in Map.Homes do
	if StreetProps.clear(home.door.x, home.door.z) or StreetProps.clear(home.pile.x, home.pile.z) or StreetProps.clear(home.park.x, home.park.z) then
		fail("the homes' doors, piles and parks are kept clear", home.name)
		break
	end
end
for _, stop in BusLines.allStops() do
	if StreetProps.clear(stop.kx, stop.kz) then
		fail("the bus stops are kept clear", stop.name)
	end
end

for _, kind in { "bin", "hydrant", "barricade", "sandbags", "debris", "bags", "boarded", "car", "flare" } do
	print(string.format("  %-10s %d", kind, counts[kind] or 0))
	check(`some {kind}s in town`, (counts[kind] or 0) >= 3, counts[kind])
end
for id, n in byDistrict do
	print(`  {id}: {n} props`)
end
check("props on most ordinary blocks", #blocks >= 70, #blocks)
check("a few hundred props in all (not a flood)", total >= 250 and total <= 700, total)
check("the cars stay few", (counts.car or 0) <= 40, counts.car)
for _, rule in { "one entry a block", "ordinary blocks only", "a known kind", "never in the safe zone", "clear of the doors, piles, parks, stops, docks, ladders, alleys and crosswalks", "only a car on the road", "a car at the kerb, out of the traffic's lane", "a car away from the junctions", "no car on a bus line's street", "no car by a bus stop", "on its block's sidewalk", "away from the corners (crosswalks, lamps, poles)", "a kerb prop on the kerb, off the walk line", "bags and boards against a Downtown tower, behind the walk lines", "no two props crowded", "the docks are kept clear", "the zip ladders are kept clear", "the homes' doors, piles and parks are kept clear", "the bus stops are kept clear" } do
	local list = bad[rule]
	check(rule, list == nil, if list then table.concat(list, ", ") else nil)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
