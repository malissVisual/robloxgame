-- 5.6, the alley shortcuts (shared/Shortcuts.luau): 6 – 10 lit paths straight through Downtown blocks, only over two
-- open lots (a lawn or a parking lot), never through a home or a storefront, their mouths clear of the doors, piles,
-- parks, cargo spots and bus stops; in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local BusLines = require("./BusLines")
local TrafficLanes = require("./TrafficLanes")
local Shortcuts = require("./Shortcuts")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local alleys = Shortcuts.alleys()
local tuning = Config.Shortcuts
check("6 – 10 alleys", #alleys >= 6 and #alleys <= 10, #alleys)
check("the alleys are cached (the same on every call)", Shortcuts.alleys() == alleys)
check("the fences are low enough to hop (a jump clears 7 studs)", tuning.FenceHeight > 1 and tuning.FenceHeight <= 2.5)

local half = Map.BlockSize / 2
local blocks: { [string]: boolean } = {}
for _, alley in alleys do
	local d = Map.districtById(alley.district)
	local cx, cz = d.ox + alley.i * Map.Cell, d.oz + alley.j * Map.Cell
	print(string.format("  %s: block (%d, %d), %s, along %s, %s + %s", alley.name, alley.i, alley.j, alley.district, if alley.alongX then "X" else "Z", alley.lots[1].kind, alley.lots[2].kind))
	check(`{alley.name}: Downtown, an ordinary block`, alley.district == "downtown" and Map.special(alley.district, alley.i, alley.j) == nil)
	check(`{alley.name}: one alley a block`, not blocks[`{alley.i},{alley.j}`])
	blocks[`{alley.i},{alley.j}`] = true
	-- Two open lots of the block, neighbours across the path's line.
	local a, b = alley.lots[1], alley.lots[2]
	local open = (a.kind == "grass" or a.kind == "parking") and (b.kind == "grass" or b.kind == "parking")
	check(`{alley.name}: over two open lots (a lawn or a parking lot)`, open and a.i == alley.i and a.j == alley.j and b.i == alley.i and b.j == alley.j, `{a.kind} {b.kind}`)
	local neighbours = if alley.alongX then a.b == b.b and a.a ~= b.a else a.a == b.a and a.b ~= b.b
	check(`{alley.name}: the two lots are neighbours along the path`, neighbours)
	-- The path: straight through the block, over the lots, from one lot edge to the other.
	local length = math.sqrt((alley.x1 - alley.x0) ^ 2 + (alley.z1 - alley.z0) ^ 2)
	check(`{alley.name}: straight through the block`, math.abs(length - (Map.BlockSize - 2 * Map.DowntownInset)) < 1e-6, length)
	local straight = if alley.alongX then alley.z0 == alley.z1 else alley.x0 == alley.x1
	check(`{alley.name}: along one axis`, straight)
	-- Never through anything but the two open lots: no other lot's building or home overlaps the path.
	local x0, x1 = math.min(alley.x0, alley.x1), math.max(alley.x0, alley.x1)
	local z0, z1 = math.min(alley.z0, alley.z1), math.max(alley.z0, alley.z1)
	if alley.alongX then
		z0 -= alley.width / 2
		z1 += alley.width / 2
	else
		x0 -= alley.width / 2
		x1 += alley.width / 2
	end
	local through: string? = nil
	for _, lot in Map.lotsAt(alley.district, alley.i, alley.j) do
		local lx0, lx1 = lot.x - lot.size / 2, lot.x + lot.size / 2
		local lz0, lz1 = lot.z - lot.size / 2, lot.z + lot.size / 2
		local overlaps = lx0 < x1 and lx1 > x0 and lz0 < z1 and lz1 > z0
		if overlaps and lot ~= a and lot ~= b then
			through = lot.kind
		end
		if overlaps and (lot.home or lot.venue) then
			through = lot.kind
		end
	end
	check(`{alley.name}: never through a home, a storefront or a tower`, through == nil, through)
	-- The mouths: on the curb at both ends, clear of the doors, piles, parks, cargo spots and bus stops.
	check(`{alley.name}: two mouths on the curb`, #alley.mouths == 2 and math.abs(math.max(math.abs(alley.mouths[1].x - cx), math.abs(alley.mouths[1].z - cz)) - half) < 1e-6 and math.abs(math.max(math.abs(alley.mouths[2].x - cx), math.abs(alley.mouths[2].z - cz)) - half) < 1e-6)
	local worst = math.huge
	local function near(x: number, z: number)
		for _, mouth in alley.mouths do
			worst = math.min(worst, math.sqrt((mouth.x - x) ^ 2 + (mouth.z - z) ^ 2))
		end
	end
	for _, home in Map.Homes do
		near(home.door.x, home.door.z)
		near(home.pile.x, home.pile.z)
		near(home.park.x, home.park.z)
	end
	for _, venue in Map.Venues do
		near(venue.door.x, venue.door.z)
		near(venue.pile.x, venue.pile.z)
		near(venue.park.x, venue.park.z)
	end
	for _, spot in Map.CargoSpots do
		near(spot.park.x, spot.park.z)
		near(spot.pile.x, spot.pile.z)
	end
	for _, stop in BusLines.allStops() do
		near(stop.kx, stop.kz)
	end
	check(`{alley.name}: its mouths clear of doors, piles, parks, cargo spots and bus stops`, worst >= tuning.Clear, worst)
	for _, mouth in alley.mouths do
		check(`{alley.name}: out of the safe zone`, not Map.isSafe(mouth.x, mouth.z))
	end
	-- The fences just inside the lots, the lamps on them, the sign on the sidewalk off the walkers' line.
	local function inset(p: { x: number, z: number }): number
		return half - math.max(math.abs(p.x - cx), math.abs(p.z - cz))
	end
	check(`{alley.name}: a fence at each end, just inside the lots`, #alley.fences == 2 and inset(alley.fences[1]) > Map.DowntownInset and inset(alley.fences[1]) < Map.DowntownInset + 2 and inset(alley.fences[2]) > Map.DowntownInset and inset(alley.fences[2]) < Map.DowntownInset + 2)
	check(`{alley.name}: two lamps on the lots`, #alley.lamps == 2 and inset(alley.lamps[1]) > Map.DowntownInset and inset(alley.lamps[2]) > Map.DowntownInset)
	check(`{alley.name}: the sign on the sidewalk, off the people's walk line`, inset(alley.sign) > TrafficLanes.SidewalkInset + 2 and inset(alley.sign) < Map.DowntownInset)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
