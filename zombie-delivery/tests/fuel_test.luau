-- 5.4, fuel (Config.Fuel, shared/FuelMath.luau) and the gas stations (Map.GasStations): every car has a tank and a
-- burn, a bike none; the burn, the price, the crawl, the pump's pouring (never more than you can pay, the cents settled
-- at the end); a full tank lasts 3 – 5 typical jobs of the tier the car opens at; the stations stand on their own lots
-- (lot kind "gas", the Harbor's special block), off the roads, the venues, the homes and the places, their pumps and bays
-- on their floor, each a landmark with the gas map icon and the GAS STATION tag.
-- Run with tests/run_tests.py.
local Config = require("./Config")
local FuelMath = require("./FuelMath")
local Icons = require("./Icons")
local LocationTags = require("./LocationTags")
local Map = require("./Map")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end
local function car(id: string): Config.CarDef
	for _, def in Config.Cars do
		if def.id == id then
			return def
		end
	end
	error("no car " .. id)
end
local F = Config.Fuel

-- ── The tanks ──────────────────────────────────────────────────────────────

local tankProblem: string? = nil
for _, def in Config.Cars do
	if def.bike then
		if def.tank or def.burn or FuelMath.hasFuel(def) or FuelMath.tank(def) ~= 0 then
			tankProblem = `{def.id}: a bike with fuel`
		end
	elseif not def.tank or not def.burn or def.tank <= 0 or def.burn <= 0 or not FuelMath.hasFuel(def) then
		tankProblem = `{def.id}: no tank or burn`
	elseif F.TowLitres >= def.tank or F.CanLitres >= def.tank then
		tankProblem = `{def.id}: a tow or a jerry can fills it`
	end
end
check("every car has a tank and a burn, no bike has fuel, a tow or a can never fills a tank", tankProblem == nil, tankProblem)
check("the brief's tanks: the Old Van 40 L, the Box Truck 80 L, the Freight Truck 120 L", car("van").tank == 40 and car("boxtruck").tank == 80 and car("freight").tank == 120)

-- ── Burn, price, crawl ─────────────────────────────────────────────────────

local van = car("van")
check("burn: 1,000 studs in the Old Van burn its burn (6.12.7: ÷ Lasts)", near(FuelMath.burn(van, 1000), (van.burn :: number) / Config.Fuel.Lasts))
check("burn: half the way, half the fuel", near(FuelMath.burn(van, 500), FuelMath.burn(van, 1000) / 2))
check("burn: nothing for no way, a way back or NaN", FuelMath.burn(van, 0) == 0 and FuelMath.burn(van, -50) == 0 and FuelMath.burn(van, 0 / 0) == 0)
check("burn: a bike burns nothing", FuelMath.burn(car("rustbike"), 1000) == 0 and FuelMath.burn(nil, 1000) == 0)
check("range: a full tank's studs", near(FuelMath.range(van), 40 * 1000 / (van.burn :: number) * Config.Fuel.Lasts))
check("price: $2 a litre", F.PricePerLitre == 2 and near(FuelMath.cost(10), 20) and FuelMath.cost(-3) == 0)
check("charge: whole dollars, the cents up", FuelMath.charge(10) == 20 and FuelMath.charge(10.2) == 21 and FuelMath.charge(0) == 0)
check("crawl: an empty tank tops out at 6 studs/s", F.CrawlSpeed == 6 and FuelMath.topSpeed(42, 0, 40) == 6 and FuelMath.topSpeed(42, 0.0001, 40) == 6)
check("crawl: any fuel, the car's own top speed", FuelMath.topSpeed(42, 0.5, 40) == 42 and FuelMath.topSpeed(70, 35, 35) == 70)
check("crawl: never faster than the car itself, a car without a tank never crawls", FuelMath.topSpeed(4, 0, 40) == 4 and FuelMath.topSpeed(30, 0, 0) == 30)
check("low: under 15 % (empty too), not at 15 %", FuelMath.isLow(5.9, 40) and FuelMath.isLow(0, 40) and not FuelMath.isLow(6, 40) and not FuelMath.isLow(0, 0))
check("share: clamped, 0 without a tank", FuelMath.share(20, 40) == 0.5 and FuelMath.share(50, 40) == 1 and FuelMath.share(-1, 40) == 0 and FuelMath.share(5, 0) == 0)

-- ── The pump ───────────────────────────────────────────────────────────────

local litres, dollars = FuelMath.pourStep(40, 0.25, 0, 0, 1000)
check("pour: 8 L a second", F.PourRate == 8 and near(litres, 2) and dollars == 4, `{litres} {dollars}`)
litres, dollars = FuelMath.pourStep(1, 0.25, 0, 0, 1000)
check("pour: never more than the tank misses", near(litres, 1) and dollars == 2, `{litres} {dollars}`)
litres, dollars = FuelMath.pourStep(40, 0.25, 0, 0, 3)
check("pour: never more than the money pays", near(litres, 1.5) and dollars == 3, `{litres} {dollars}`)
litres, dollars = FuelMath.pourStep(40, 0.25, 0, 0, 0)
check("pour: no money, no fuel", litres == 0 and dollars == 0)
litres, dollars = FuelMath.pourStep(0, 0.25, 0, 0, 100)
check("pour: a full tank takes nothing", litres == 0 and dollars == 0)

-- A whole fill at the pump, step by step as server/Fuel.luau pours it.
local function fill(missing: number, money: number, step: number): (number, number, number)
	local poured, charged, seconds = 0, 0, 0
	for _ = 1, 10000 do
		local l, d = FuelMath.pourStep(missing - poured, step, poured, charged, money - charged)
		if l <= 0 then
			break
		end
		poured += l
		charged += d
		seconds += step
	end
	local rest = FuelMath.settle(poured, charged)
	return poured, charged + math.min(rest, money - charged), seconds
end
local p1, paid1, t1 = fill(40, 10000, 0.25)
check("fill the Old Van: 40 L in 5 s for $80", near(p1, 40) and paid1 == 80 and near(t1, 5), `{p1} L, ${paid1}, {t1} s`)
local p2, paid2 = fill(40, 33, 0.25)
check("fill on $33: 16.5 L for exactly $33", near(p2, 16.5, 1e-4) and paid2 == 33, `{p2} L, ${paid2}`)
local p3, paid3 = fill(13.3, 10000, 0.1)
check("an odd fill: the cents rounded up at the end", near(p3, 13.3, 1e-6) and paid3 == 27, `{p3} L, ${paid3}`)
check("settle: what the last litres still owe", FuelMath.settle(13.3, 26) == 1 and FuelMath.settle(10, 20) == 0 and FuelMath.settle(1, 5) == 0)

-- ── A tank lasts 3 – 5 jobs ────────────────────────────────────────────────

local last = 0
local growing = true
for index in Config.Jobs.Tiers do
	local d = FuelMath.jobDistance(index)
	growing = growing and d > last
	last = d
end
check("a typical job grows with the danger level", growing)
local jobsProblem: string? = nil
for _, def in Config.Cars do
	if def.bike or def.company then
		continue
	end
	local tier = FuelMath.tierFor(def)
	local jobs = FuelMath.jobsPerTank(def, tier)
	print(string.format("  %-14s tank %3d L, %4.1f L / 1,000 studs: %5d studs, %s job %4d studs: %.1f jobs a tank, $%d to fill", def.name, def.tank or 0, def.burn or 0, math.floor(FuelMath.range(def)), string.rep("★", Config.Jobs.Tiers[tier].stars), math.floor(FuelMath.jobDistance(tier)), jobs, FuelMath.charge(def.tank or 0)))
	if jobs < 3 * Config.Fuel.Lasts or jobs > 5 * Config.Fuel.Lasts then
		jobsProblem = `{def.id}: {jobs} jobs`
	end
end
check("every dealer car: a full tank lasts 3 – 5 jobs of the tier it opens at, times Lasts (6.12.7: 15 – 25)", Config.Fuel.Lasts >= 1 and jobsProblem == nil, jobsProblem)
check("the Old Van is meant for ★ jobs, the Rally Van for ★★★★", FuelMath.tierFor(van) == 1 and FuelMath.tierFor(car("rallyvan")) == 4)

-- ── The gas stations ───────────────────────────────────────────────────────

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
type Box = { x0: number, z0: number, x1: number, z1: number }
local function overlap(a: Box, b: Box): boolean
	return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0 and math.min(a.z1, b.z1) - math.max(a.z0, b.z0) > 0
end
local function inside(b: Box, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	return x > b.x0 - m and x < b.x1 + m and z > b.z0 - m and z < b.z1 + m
end
local L = Map.GasLayout
local function stationBox(station: Map.GasStation): Box
	local fx = station.facing.x
	local hx = if fx ~= 0 then L.depth / 2 else L.width / 2
	local hz = if fx ~= 0 then L.width / 2 else L.depth / 2
	return { x0 = station.x - hx, z0 = station.z - hz, x1 = station.x + hx, z1 = station.z + hz }
end

check("six gas stations: the old one, three of 5.4 and two by the safe zone (6.12.7)", #Map.GasStations == 6 and Map.gasStation("gas") ~= nil and Map.gasStation("gas_downtown") ~= nil
	and Map.gasStation("gas_harbor") ~= nil and Map.gasStation("gas_suburbs") ~= nil and Map.gasStation("gas_depot") ~= nil
	and Map.gasStation("gas_tower") ~= nil and Map.gasStation("moon") == nil)
do
	-- 6.12.7: the two new ones are close: within 360 studs of the park's middle and 450 of the depot, outside the safe zone
	local close = true
	for _, id in { "gas_depot", "gas_tower" } do
		local s = Map.gasStation(id) :: Map.GasStation
		local fromPark = math.sqrt(s.x * s.x + s.z * s.z)
		local fromDepot = math.sqrt((s.x - Map.Depot.x) ^ 2 + (s.z - Map.Depot.z) ^ 2)
		close = close and fromPark < 360 and fromDepot < 450 and (math.abs(s.x) > Config.City.SafeHalf or math.abs(s.z) > Config.City.SafeHalf)
	end
	check("the two new stations sit close to the safe zone and the depot", close)
end
check("the layout is Codex's 70 x 50 lot", L.width == 70 and L.depth == 50)
local landmarks: { [string]: Map.Landmark } = {}
for _, landmark in Map.Landmarks do
	landmarks[landmark.id] = landmark
end
local tags: { [string]: LocationTags.Tag } = {}
for _, tag in LocationTags.build() do
	tags[tag.id] = tag
end
local stationProblem: string? = nil
local boxes: { [string]: Box } = {}
for _, station in Map.GasStations do
	local fx, fz = station.facing.x, station.facing.z
	if math.abs(fx) + math.abs(fz) ~= 1 then
		stationProblem = `{station.id}: no front`
	end
	if not landmarks[station.id] then
		stationProblem = `{station.id}: not a landmark`
	elseif Icons.landmark(station.id) ~= "map_gas" then
		stationProblem = `{station.id}: not the gas map icon ({Icons.landmark(station.id)})`
	end
	if #station.pumps ~= 2 or #station.bays < 2 then
		stationProblem = `{station.id}: {#station.pumps} pumps, {#station.bays} bays`
	end
	for _, bay in station.bays do
		local pump = station.pumps[bay.pump]
		local gap = if pump then math.sqrt((pump.x - bay.x) ^ 2 + (pump.z - bay.z) ^ 2) else math.huge
		if gap > F.PumpReach then
			stationProblem = `{station.id}: a bay {gap} studs from its pump`
		end
		if math.abs(bay.look.x) + math.abs(bay.look.z) ~= 1 then
			stationProblem = `{station.id}: a bay looks nowhere`
		end
	end
	if station.id == "gas" then
		-- the old one: in its yard, the pumps and bays on the yard
		for _, spot in station.pumps do
			local yard = Map.inYard(spot.x, spot.z)
			if not yard or yard.id ~= "gas" then
				stationProblem = "gas: a pump off its yard"
			end
		end
		for _, bay in station.bays do
			local yard = Map.inYard(bay.x, bay.z)
			if not yard or yard.id ~= "gas" then
				stationProblem = "gas: a bay off its yard"
			end
		end
		if tags.gas == nil then
			stationProblem = "gas: no location tag"
		end
		continue
	end
	local box = stationBox(station)
	boxes[station.id] = box
	if not tags[station.id] or tags[station.id].sub ~= "GAS STATION" then
		stationProblem = `{station.id}: its location tag does not say GAS STATION`
	end
	-- on its block, off the roads; its front to its street (the landmark's point is on the asphalt in front)
	local d, i, j = Map.blockAt(station.x, station.z)
	if not d then
		stationProblem = `{station.id}: on no block`
		continue
	end
	local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
	local half = Map.BlockSize / 2
	if box.x0 < cx - half or box.x1 > cx + half or box.z0 < cz - half or box.z1 > cz + half then
		stationProblem = `{station.id}: past its block's edge`
	end
	for _, corner in { { box.x0, box.z0 }, { box.x1, box.z0 }, { box.x0, box.z1 }, { box.x1, box.z1 } } do
		if onAsphalt(corner[1], corner[2]) then
			stationProblem = `{station.id}: on a road`
		end
	end
	local front = landmarks[station.id]
	if not onAsphalt(front.x, front.z) or Map.isSafe(front.x, front.z) then
		stationProblem = `{station.id}: no street in front (or in the safe zone)`
	end
	-- the pumps and bays where the layout puts them, on the station's floor
	for n, spot in station.pumps do
		local p = L.pumps[n]
		local rx, rz = station.x - fz * p[1] - fx * p[2], station.z + fx * p[1] - fz * p[2]
		if not near(spot.x, rx) or not near(spot.z, rz) or not inside(box, spot.x, spot.z) then
			stationProblem = `{station.id}: pump {n} not where the layout has it`
		end
	end
	for _, bay in station.bays do
		if not inside(box, bay.x, bay.z) or bay.look.x ~= fx or bay.look.z ~= fz then
			stationProblem = `{station.id}: a bay off its floor or not looking out`
		end
	end
	-- its lots (a lot station) or its special block (the Harbor's)
	if station.district then
		if station.district ~= d.id or station.i ~= i or station.j ~= j or Map.special(d.id, i, j) then
			stationProblem = `{station.id}: not on its ordinary block`
		end
		for _, lot in Map.lotsAt(d.id, i, j) do
			local mine = lot.b == station.b
			if mine and (lot.kind ~= "gas" or lot.home or lot.venue or lot.facing.x ~= fx or lot.facing.z ~= fz) then
				stationProblem = `{station.id}: lot {lot.a}{lot.b} is a {lot.kind}`
			elseif not mine and lot.kind == "gas" then
				stationProblem = `{station.id}: the other row is a gas lot too`
			end
			-- the buildings on the other lots of the block stay clear of it
			local other: Box? = nil
			if not mine and (lot.kind == "tower" or lot.kind == "apartment") then
				other = { x0 = lot.x - lot.w / 2, z0 = lot.z - lot.d / 2, x1 = lot.x + lot.w / 2, z1 = lot.z + lot.d / 2 }
			elseif not mine and lot.home and lot.kind == "house" then
				local home = lot.home :: Map.Home
				local hx = if home.facing.x ~= 0 then lot.d / 2 else lot.w / 2
				local hz = if home.facing.z ~= 0 then lot.d / 2 else lot.w / 2
				local mx, mz = home.door.x - home.facing.x * lot.d / 2, home.door.z - home.facing.z * lot.d / 2
				other = { x0 = mx - hx, z0 = mz - hz, x1 = mx + hx, z1 = mz + hz }
			elseif not mine and lot.kind ~= "gas" then
				other = { x0 = lot.x - lot.size / 2, z0 = lot.z - lot.size / 2, x1 = lot.x + lot.size / 2, z1 = lot.z + lot.size / 2 }
			end
			if other and overlap(box, other) then
				stationProblem = `{station.id}: over the {lot.kind} on lot {lot.a}{lot.b}`
			end
		end
	elseif Map.special(d.id, i, j) ~= "gas" or #Map.lotsAt(d.id, i, j) > 0 then
		stationProblem = `{station.id}: not on a gas special block`
	end
	-- no venue, home, estate plot, place, cargo spot or employer near it
	for _, venue in Map.Venues do
		if inside(box, venue.door.x, venue.door.z, 2) or inside(box, venue.park.x, venue.park.z, 2) then
			stationProblem = `{station.id}: the venue {venue.id} is in the way`
		end
	end
	for _, home in Map.Homes do
		if inside(box, home.door.x, home.door.z, 2) or inside(box, home.pile.x, home.pile.z, 2) then
			stationProblem = `{station.id}: the home {home.id} is in the way`
		end
	end
	for id, plot in Map.EstatePlots do
		if inside(box, plot.x, plot.z, 20) then
			stationProblem = `{station.id}: the property {id} is in the way`
		end
	end
	for _, place in Map.Places do
		if inside(box, place.x, place.z, 10) then
			stationProblem = `{station.id}: the place {place.id} is in the way`
		end
	end
	for id, spot in Map.CargoSpots do
		if inside(box, spot.park.x, spot.park.z, 5) or inside(box, spot.pile.x, spot.pile.z, 5) then
			stationProblem = `{station.id}: the cargo spot {id} is in the way`
		end
	end
	for id, spot in Map.EmployerSpots do
		if inside(box, spot.x, spot.z, 5) then
			stationProblem = `{station.id}: the employer {id} is in the way`
		end
	end
	for _, a in Map.addresses() do
		if not a.poi and inside(box, a.x, a.z) then
			stationProblem = `{station.id}: the address {a.name} is on it`
		end
	end
end
check("every station: a landmark with the gas icon and the GAS STATION tag, on its own lots / block, off the roads and every place, its pumps and bays on its floor", stationProblem == nil, stationProblem)
local apart = true
for a, boxA in boxes do
	for b, boxB in boxes do
		if a < b and overlap(boxA, boxB) then
			apart = false
		end
	end
end
check("the stations stand apart", apart)
local spread = true
for n, a in Map.GasStations do
	for m = n + 1, #Map.GasStations do
		local b = Map.GasStations[m]
		spread = spread and math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) > 400 -- (6.12.7: 500; Tower Gas is 444 from Westside Gas)
	end
end
check("spread over the map (400+ studs apart)", spread)
local nearestHarbor = Map.nearestGas(1300, 100)
local nearestNorth = Map.nearestGas(150, -1100)
check("the nearest station: the Harbor's in the Harbor, the old one up north", nearestHarbor.id == "gas_harbor" and nearestNorth.id == "gas")
check("the jerry can is an item with its picture slot", Icons.item("jerrycan") == "jerrycan" and (function()
	for _, def in Config.Items do
		if def.id == "jerrycan" then
			return def.price == 35
		end
	end
	return false
end)())

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
