-- 6.12.14, Lead & Co.'s shooting range (shared/Map.luau Map.GunRange, Map.gunRangeAt, Map.Shops.guns, Map.FormerGunShop;
-- Config.GunRange; server/GunRange.luau builds it): the compound fills Downtown block (-2, 1), a block that was
-- ordinary (its dice still roll), outside the safe zone and within reach of the park, its gate on a street; it stands
-- on no road and clear of every storefront, zip line, alley, rental dock, bus stop, gas station, home, address, estate
-- plot, mission place, cargo spot and employer; its counter (the "guns" shop) inside the range shop, the shop's radius
-- over the gate; the lanes, the targets and the berm inside the fence; the old shop's block special and shopless; every
-- other block of the city as it was; the words players read.
-- Run with tests/run_tests.py.
local Config = require("./Config")
local Map = require("./Map")
local ZipLines = require("./ZipLines")
local Shortcuts = require("./Shortcuts")
local RentalDocks = require("./RentalDocks")
local BusLines = require("./BusLines")
local LocationTags = require("./LocationTags")
local Icons = require("./Icons")
local Explore = require("./Explore")
local Career = require("./Career")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local R = Config.GunRange
local G = Map.GunRange
local CELL = Map.Cell
local HALF = Map.BlockSize / 2
type Box = { x0: number, z0: number, x1: number, z1: number }

-- A box of the range's frame (right x0 … x1, back z0 … z1) on the map.
local function boxOf(x0: number, z0: number, x1: number, z1: number): Box
	local ax, az = Map.gunRangeAt(x0, z0)
	local bx, bz = Map.gunRangeAt(x1, z1)
	return { x0 = math.min(ax, bx), z0 = math.min(az, bz), x1 = math.max(ax, bx), z1 = math.max(az, bz) }
end
local function inside(b: Box, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	return x > b.x0 - m and x < b.x1 + m and z > b.z0 - m and z < b.z1 + m
end
local function overlap(a: Box, b: Box): boolean
	return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0 and math.min(a.z1, b.z1) - math.max(a.z0, b.z0) > 0
end
-- Is any road's asphalt here (the yards do not count)?
local function onAsphalt(x: number, z: number): boolean
	for _, s in Map.Segments do
		local dx, dz = s.bx - s.ax, s.bz - s.az
		local length2 = dx * dx + dz * dz
		local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
		local px, pz = s.ax + dx * t, s.az + dz * t
		if (x - px) ^ 2 + (z - pz) ^ 2 <= (s.width / 2) ^ 2 + 1e-6 then
			return true
		end
	end
	return false
end

-- ── Its block ──────────────────────────────────────────────────────────────

check("the range's block: Downtown (-2, 1), its middle Map.GunRange", G.i == -2 and G.j == 1 and G.x == -2 * CELL and G.z == CELL and R.Block[1] == G.i and R.Block[2] == G.j)
check("a special block that was ordinary (Map.FormerBlocks: its dice still roll)", Map.special("downtown", G.i, G.j) == "gunrange" and Map.wasOrdinary("downtown", G.i, G.j))
check("nothing of an ordinary block stands on it any more: no lots, homes or addresses", #Map.lotsAt("downtown", G.i, G.j) == 0 and (function()
	for _, home in Map.Homes do
		if math.abs(home.x - G.x) < HALF and math.abs(home.z - G.z) < HALF then
			return false
		end
	end
	for _, a in Map.addresses() do
		if not a.poi and math.abs(a.x - G.x) <= HALF + 7 and math.abs(a.z - G.z) <= HALF + 7 and math.abs(a.x - G.x) + math.abs(a.z - G.z) < HALF + 40 then
			return false
		end
	end
	return true
end)())
local former = Map.formerLotsAt("downtown", G.i, G.j)
local kinds: { [string]: number } = {}
for _, lot in former do
	kinds[lot.kind] = (kinds[lot.kind] or 0) + 1
end
check("its former lots: three towers and a car park (server/World.luau rolls their dice dry)", #former == 4 and kinds.tower == 3 and kinds.parking == 1, `{kinds.tower} towers, {kinds.parking} car parks`)
check("its front: east, to 4th Ave and the park (Map.gunRangeAt: right is south, back is west)", G.fx == 1 and G.fz == 0 and (function()
	local x, z = Map.gunRangeAt(10, 20)
	return x == G.x - 20 and z == G.z + 10
end)())

-- ── Where the compound stands ──────────────────────────────────────────────

local fence = boxOf(-R.Fence, -R.Fence, R.Fence, R.Fence)
local safe = Config.City.SafeHalf
check("the fenced compound is outside the safe zone (all of it)", fence.x1 <= -safe or fence.x0 >= safe or fence.z1 <= -safe or fence.z0 >= safe, `{fence.x0} … {fence.x1}`)
check("… its gate 5 or more studs past the line", fence.x1 <= -safe - 5)
local fromPark = math.sqrt((G.x - Map.Park.x) ^ 2 + (G.z - Map.Park.z) ^ 2)
local fromDepot = math.sqrt((G.x - Map.Depot.x) ^ 2 + (G.z - Map.Depot.z) ^ 2)
check("near the town: 300 – 700 studs from the park's middle (and within 600 of the depot)", fromPark >= 300 and fromPark <= 700 and fromDepot <= 600, `{math.floor(fromPark)} / {math.floor(fromDepot)}`)
check("about 90 × 90 (room for a 60 × 110 compound's lanes, its cabin and the yard), on its block, 10 in from the curb", R.Fence == HALF - 10 and fence.x1 - fence.x0 == 2 * R.Fence and fence.z1 - fence.z0 == 2 * R.Fence)
local onRoad = nil :: string?
for u = 0, 20 do
	for v = 0, 20 do
		local x, z = fence.x0 + (fence.x1 - fence.x0) * u / 20, fence.z0 + (fence.z1 - fence.z0) * v / 20
		if onAsphalt(x, z) then
			onRoad = `{x}, {z}`
		end
	end
end
check("on no road", onRoad == nil, onRoad)
local gx, gz = Map.gunRangeAt(R.Gate.X, -R.Fence)
local sx, sz = Map.gunRangeAt(R.Gate.X, -(HALF + Map.RoadWidth / 2))
check("its gate on its street (4th Ave in front, reachable by road and on foot: a car fits through)", onAsphalt(sx, sz) and not onAsphalt(gx, gz) and R.Gate.Width >= 12
	and Map.isSafe(sx, sz), `{sx}, {sz}`)

local problem: string? = nil
for _, venue in Map.Venues do
	if inside(fence, venue.door.x, venue.door.z, 8) or inside(fence, venue.park.x, venue.park.z, 8) or inside(fence, venue.pile.x, venue.pile.z, 8) or inside(fence, venue.x, venue.z, 20) then
		problem = `the storefront {venue.id}`
	end
end
for _, line in ZipLines.lines() do
	for _, lot in { line.start, line.finish } do
		if lot.i == G.i and lot.j == G.j then
			problem = `zip line {line.id} on the block`
		end
	end
	for _, ladder in { line.ladderA, line.ladderB } do
		if inside(fence, ladder.x, ladder.z, 6) then
			problem = `zip line {line.id}'s ladder`
		end
	end
	for n = 0, 100 do
		local x, _, z = ZipLines.cable(line, n / 100)
		if inside(fence, x, z, 10) then
			problem = `zip line {line.id}'s cable`
		end
	end
end
for _, alley in Shortcuts.alleys() do
	if alley.i == G.i and alley.j == G.j and alley.district == "downtown" then
		problem = `alley {alley.id} on the block`
	end
	for _, mouth in alley.mouths do
		if inside(fence, mouth.x, mouth.z, 10) then
			problem = `alley {alley.id}'s mouth`
		end
	end
end
for _, dock in RentalDocks.docks() do
	if inside(fence, dock.x, dock.z, 12) then
		problem = `rental dock {dock.id}`
	end
end
for _, stop in BusLines.allStops() do
	if inside(fence, stop.kx, stop.kz, 12) then
		problem = `bus stop {stop.name}`
	end
end
for _, station in Map.GasStations do
	local w, d = Map.GasLayout.width / 2, Map.GasLayout.depth / 2
	local hx, hz = if station.facing.x ~= 0 then d else w, if station.facing.x ~= 0 then w else d
	if overlap(fence, { x0 = station.x - hx - 10, z0 = station.z - hz - 10, x1 = station.x + hx + 10, z1 = station.z + hz + 10 }) then
		problem = `the gas station {station.id}`
	end
end
for _, home in Map.Homes do
	if inside(fence, home.door.x, home.door.z, 10) or inside(fence, home.park.x, home.park.z, 6) then
		problem = `the home {home.id}`
	end
end
for id, plot in Map.EstatePlots do
	if inside(fence, plot.x, plot.z, 30) then
		problem = `the property {id}`
	end
end
for _, place in Map.Places do
	if inside(fence, place.x, place.z, 15) then
		problem = `the place {place.id}`
	end
end
for id, spot in Map.CargoSpots do
	if inside(fence, spot.park.x, spot.park.z, 10) or inside(fence, spot.pile.x, spot.pile.z, 10) then
		problem = `the cargo spot {id}`
	end
end
for id, spot in Map.EmployerSpots do
	if inside(fence, spot.x, spot.z, 15) then
		problem = `the employer {id}`
	end
end
check("clear of every storefront, zip line, alley, rental dock, bus stop, gas station, home, estate plot, place, cargo spot and employer", problem == nil, problem)

-- ── The compound inside ────────────────────────────────────────────────────

local cabin = R.Cabin
local cabinBox = { x0 = cabin.X - cabin.Width / 2, z0 = cabin.Z - cabin.Depth / 2, x1 = cabin.X + cabin.Width / 2, z1 = cabin.Z + cabin.Depth / 2 }
local lanes = R.Lanes
local lx0, lx1 = lanes.X[1] - lanes.Width / 2, lanes.X[#lanes.X] + lanes.Width / 2
local laneBox = { x0 = lx0, z0 = lanes.Line - 7, x1 = lx1, z1 = R.Berm.Z + R.Berm.Depth }
local function within(b: Box): boolean
	return b.x0 >= -R.Fence and b.x1 <= R.Fence and b.z0 >= -R.Fence and b.z1 <= R.Fence
end
check("a small range shop: about 20 × 14, its door to the gate's side", cabin.Width >= 18 and cabin.Width <= 24 and cabin.Depth >= 12 and cabin.Depth <= 16 and cabin.Height <= 12)
check("the cabin, the lanes and the berm inside the fence, apart", within(cabinBox) and within(laneBox) and not overlap(cabinBox, laneBox))
check("the gate clear of the cabin and the lanes (a way in to both)", R.Gate.X - R.Gate.Width / 2 >= cabinBox.x1 and R.Gate.X + R.Gate.Width / 2 <= lx0 and cabinBox.z0 > -R.Fence + 8)
check("four lanes side by side, a target in each at 25, 50 and 75 studs, the berm right behind the farthest", #lanes.X == 4 and table.concat(lanes.Targets, ",") == "25,50,75" and #R.Plates == #lanes.Targets
	and lanes.Line + lanes.Targets[3] < R.Berm.Z and R.Berm.Z - (lanes.Line + lanes.Targets[3]) <= 2 and R.Berm.Z + R.Berm.Depth <= R.Fence and R.Berm.Height >= 6)
local platesFit = true
for n, plate in R.Plates do
	platesFit = platesFit and plate[1] < lanes.Width - 2 and (n == 1 or plate[1] >= R.Plates[n - 1][1])
end
check("the plates fit their lanes, bigger farther out", platesFit)
for n = 2, #lanes.X do
	check(`lane {n} beside lane {n - 1}`, lanes.X[n] - lanes.X[n - 1] == lanes.Width)
end
check("the firing line under the pavilion near the front fence (the shooters' room behind the benches)", lanes.Line - (-R.Fence) >= 6 and lanes.Line - (-R.Fence) <= 9)
check("a target stays down a few seconds", R.Down >= 2 and R.Down <= 8)

-- ── The shop ───────────────────────────────────────────────────────────────

local shop = Map.Shops.guns
local cx, cz = Map.gunRangeAt(cabin.X, cabin.Z + R.Counter.Z - R.Counter.Deep / 2)
check("Lead & Co. (\"guns\"): its spot the range shop's counter front", shop ~= nil and shop.name == "Lead & Co." and shop.x == cx and shop.z == cz)
check("… its own radius (the cabin, its forecourt, the gate)", shop.radius == R.Radius and Map.shopRadius("guns") == R.Radius and R.Radius < Map.ShopRadius
	and math.sqrt((gx - shop.x) ^ 2 + (gz - shop.z) ^ 2) <= R.Radius)
check("the counter inside the cabin, inside the compound, out of the safe zone", inside(boxOf(cabinBox.x0, cabinBox.z0, cabinBox.x1, cabinBox.z1), shop.x, shop.z) and inside(fence, shop.x, shop.z)
	and not Map.isSafe(shop.x, shop.z) and R.Counter.Width < cabin.Width - 4 and math.abs(R.Counter.Z) + R.Counter.Deep / 2 + 1.6 + 1 < cabin.Depth / 2)
check("the shop's radius stays on its block (it reaches no other shop)", (function()
	for id, other in Map.Shops do
		if id ~= "guns" and math.sqrt((other.x - shop.x) ^ 2 + (other.z - shop.z) ^ 2) < R.Radius + Map.shopRadius(id) then
			return false
		end
	end
	return true
end)())

-- ── The map, the tag, the GPS, the words ───────────────────────────────────

local landmark: Map.Landmark? = nil
local onOldBlock = 0
for _, l in Map.Landmarks do
	if l.id == "guns" then
		landmark = l
	end
	if l.kind == "shop" and math.abs(l.x - Map.FormerGunShop.x) < HALF and math.abs(l.z - Map.FormerGunShop.z) < HALF then
		onOldBlock += 1
	end
end
check("its landmark (the map icon, the GPS) at the counter, the gun map icon", landmark ~= nil and landmark.x == shop.x and landmark.z == shop.z and landmark.kind == "shop" and Icons.landmark("guns") == "map_guns")
check("its line says where: the range, just outside the safe zone", landmark ~= nil and string.find(landmark.description, "range", 1, true) ~= nil and string.find(landmark.description, "just outside the safe zone", 1, true) ~= nil)
local tags: { [string]: LocationTags.Tag } = {}
for _, tag in LocationTags.build() do
	tags[tag.id] = tag
end
check("its location tag: LEAD & CO. over GUN SHOP · RANGE, near from its radius", tags.guns ~= nil and tags.guns.name == "Lead & Co." and tags.guns.sub == "GUN SHOP · RANGE" and tags.guns.near == R.Radius)
local start: Explore.Set = {}
for _, index in Explore.cellsInSquare(0, 0, Config.Explore.StartHalf) do
	start[index] = true
end
check("a new player knows where it is (its cell in the starting square)", Explore.knows(start, "guns"))
local named: string? = nil
for _, stop in BusLines.allStops() do
	if stop.landmark == "guns" or string.find(stop.name, "Lead", 1, true) then
		named = stop.name
	end
end
check("no bus stop named after Lead & Co. (the lines kept their stops: its old block still draws them)", named == nil, named)
check("the board: LEAD & CO. · RANGE", string.find(R.Board, "LEAD & CO. · RANGE", 1, true) == 1)
local gunWords: string? = nil
local starterWords: string? = nil
for _, step in Career.road() do
	for _, unlock in step.unlocks do
		if unlock.kind == "gun" then
			if unlock.id == Config.Arms.Starter then
				starterWords = unlock.name
			elseif not gunWords then
				gunWords = unlock.name
			end
		end
	end
end
check("the career road: a gun you buy says where (Lead & Co.'s range), the starter pistol only its name", gunWords ~= nil and string.find(gunWords, "at Lead & Co.'s range", 1, true) ~= nil
	and starterWords ~= nil and string.find(starterWords, "Lead", 1, true) == nil, gunWords)

-- ── The old shop's block ───────────────────────────────────────────────────

local old = Map.FormerGunShop
check("Lead & Co.'s old building: block (-1, 0), special, shopless, in the safe zone", old.i == -1 and old.j == 0 and old.x == -CELL and old.z == 0 and Map.special("downtown", old.i, old.j) == "guns"
	and not Map.wasOrdinary("downtown", old.i, old.j) and #Map.lotsAt("downtown", old.i, old.j) == 0 and onOldBlock == 0 and Map.isSafe(old.x, old.z))
check("no shop's spot on the old block any more", (function()
	for _, other in Map.Shops do
		if math.abs(other.x - old.x) < HALF and math.abs(other.z - old.z) < HALF then
			return false
		end
	end
	return true
end)())

-- ── The rest of the city as it was ─────────────────────────────────────────

do
	local key = `{G.i},{G.j}`
	local savedSpecial, savedFormer = Map.SpecialBlocks.downtown[key], Map.FormerBlocks.downtown[key]
	Map.SpecialBlocks.downtown[key] = nil
	Map.FormerBlocks.downtown[key] = nil
	local before, homesBefore = Map.makeLots()
	Map.SpecialBlocks.downtown[key] = savedSpecial
	Map.FormerBlocks.downtown[key] = savedFormer
	local function same(a: Map.Lot, b: Map.Lot): boolean
		return a.kind == b.kind and a.x == b.x and a.z == b.z and a.w == b.w and a.d == b.d and a.h == b.h and a.seed == b.seed
			and a.facing.x == b.facing.x and a.facing.z == b.facing.z and (a.home == nil) == (b.home == nil)
	end
	local lotsSame, count, dice = true, 0, true
	for districtId, blocks in before do
		for k, list in blocks do
			if districtId == "downtown" and k == key then
				-- its own four: the same dice as its former lots (the towers' look, the car park)
				for n, lot in list do
					local was = former[n]
					dice = dice and was ~= nil and was.seed == lot.seed and was.w == lot.w and was.d == lot.d and was.h == lot.h
						and (was.kind == lot.kind or (was.kind == "tower" and lot.kind == "apartment"))
				end
				continue
			end
			local now = Map.AllLots[districtId][k] or {}
			lotsSame = lotsSame and #now == #list
			for n, lot in list do
				count += 1
				if not now[n] or not same(lot, now[n]) then
					lotsSame = false
				end
			end
		end
	end
	check("every other lot of the city is as it was", lotsSame and count > 300, count)
	check("its former lots roll the dice its lots rolled (the same seeds and sizes)", dice and #former == 4)
	local gone, kept = 0, true
	local index: { [string]: Map.Home } = {}
	for _, home in Map.Homes do
		index[home.id] = home
	end
	for _, home in homesBefore do
		local now = index[home.id]
		if string.find(home.id, `home_downtown_{G.i}_{G.j}_`, 1, true) == 1 then
			gone += 1
			kept = kept and now == nil
		else
			kept = kept and now ~= nil and now.name == home.name and now.park.x == home.park.x and now.park.z == home.park.z
		end
	end
	check("every other home as it was; the block's own three gone", kept and gone == 3 and #Map.Homes == #homesBefore - 3, `{gone} gone`)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
