-- 7.1, the Alps, step 1B (shared/AlpineLayout.luau, Config.Alpine): the ring of mountains stands just outside the box
-- (Map.Bounds: nothing you play on moved) and holds it (no gap a car could drive through, nor a swimmer: the river's
-- gorges and the lake are closed), the mountains are as high as asked, their layers nest, the far silhouettes hide
-- inside them, the West Pass keeps its road and its closed tunnel, and the budgets hold; a tighter box (step 2's) is
-- held the same way. 7.1 review: every layer exactly two rows of the terrain's 4-stud voxels on their grid, a layer left
-- out only where a bigger neighbour's hold it (the same terrain), the tunnel's air on the grid down to the road. The
-- forests: no tree on or over a road, near a junction, in a district, on a lot, a home, a storefront, a yard, a place
-- or a zone, in the water or on the ice; thinner near town, denser at the mountains, open meadows with wildflowers, a
-- few huts; the tree budget and its two parts. In the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local AlpineLayout = require("./AlpineLayout")
local Config = require("./Config")
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

local A = Config.Alpine
local T = A.Trees
local ring = AlpineLayout.ring()
local box = ring.box
local layer = A.Layer

-- ── The ring ───────────────────────────────────────────────────────────────

local B = Map.Bounds
check("step 1B: the ring stands round Map.Bounds (the world's walls)", box.x0 == B.x0 and box.z0 == B.z0 and box.x1 == B.x1 and box.z1 == B.z1)
check("the same ring every time (cached, and the same for the same box)", AlpineLayout.ring() == ring and #AlpineLayout.ring({ x0 = box.x0, z0 = box.z0, x1 = box.x1, z1 = box.z1 }).cones == #ring.cones)

local rows: { [string]: number } = {}
local tallest, frontLow, frontHigh = 0, math.huge, 0
for _, c in ring.cones do
	rows[c.row] = (rows[c.row] or 0) + 1
	local top = c.floor + #c.radii * layer
	tallest = math.max(tallest, top)
	if c.row == "front" then
		frontLow, frontHigh = math.min(frontLow, top), math.max(frontHigh, top)
	end
end
check("two rows, shoulders, a peak behind each gorge and over the pass", (rows.front or 0) >= 30 and (rows.back or 0) >= 20 and (rows.shoulder or 0) > 0 and rows.closer == #ring.gorges and rows.pass == #ring.portals, rows.front)
check("the summits 250 – 700 studs (the front row's foothills lower)", tallest <= 700 and tallest >= 600 and frontLow >= 220 and frontHigh <= 430, `{tallest} {frontLow} {frontHigh}`)

-- Nothing of a mountain reaches into the box: every layer nests inside the bottom one, whose foot stays Gap out.
local intrude, unnested = {}, {}
for _, c in ring.cones do
	local foot = AlpineLayout.boxDistance(box, c.x, c.z) - c.radii[1]
	local least = if c.row == "closer" then A.Gap + A.Gorge else A.Gap
	if foot < least - 0.5 then
		table.insert(intrude, `{c.id} {math.floor(foot)}`)
	end
	for i = 2, #c.radii do
		local ax, az = AlpineLayout.layerAt(c, i - 1)
		local bx, bz = AlpineLayout.layerAt(c, i)
		if math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) + c.radii[i] > c.radii[i - 1] + 1e-6 then
			table.insert(unnested, `{c.id}:{i}`)
			break
		end
	end
end
check("no mountain's foot nearer the box than Gap (the gorge's peak: past the gorge)", #intrude == 0, table.concat(intrude, ", "))
check("every layer lies inside the one under it (the lean keeps them nested)", #unnested == 0, table.concat(unnested, ", "))

-- Every fill outside the box (the cones' layers, the scree, the glaciers, the cliff); the cuts only on the pass's road.
local known = { Grass = true, Rock = true, Limestone = true, Snow = true, Glacier = true, Air = true }
local inside, unknown = {}, {}
for n, f in ring.fills do
	if not known[f.material] then
		table.insert(unknown, f.material)
	end
	local reach = 0
	if f.shape == "cylinder" then
		reach = f.a
	elseif f.shape == "ball" then
		reach = math.sqrt(math.max(f.a * f.a - f.y * f.y, 0))
	elseif f.shape == "block" and f.material ~= "Air" then
		reach = math.sqrt(f.a * f.a + f.c * f.c) / 2
	end
	if f.shape ~= "air" and f.shape ~= "wedge" and AlpineLayout.boxDistance(box, f.x, f.z) - reach < 7.5 then
		table.insert(inside, `{n} {f.shape} {f.material}`)
	end
end
check("every terrain fill stays out of the box", #inside == 0, table.concat(inside, ", "))
check("the fills are grass, rock, limestone, snow, glacier and air", #unknown == 0, table.concat(unknown, ", "))

-- 7.1 review: the terrain's voxels are 4 studs. Every layer is exactly two voxel rows on their grid (a layer that
-- reached into the next row wrote that row twice, a little of it), its cone's floor on the grid.
local VOXEL = 4
local function onGrid(v: number): boolean
	return math.abs(v / VOXEL - math.floor(v / VOXEL + 0.5)) < 1e-9
end
local offGrid = {}
check("a layer is two voxel rows (Layer 8), the floors on the grid", layer == 2 * VOXEL and onGrid(A.Floor) and onGrid(A.WetFloor))
local written: { [string]: { [number]: AlpineLayout.Fill } } = {}
local layers = 0
for _, c in ring.cones do
	layers += #c.radii
	if not onGrid(c.floor) then
		table.insert(offGrid, c.id)
	end
end
for _, f in ring.fills do
	if f.shape == "cylinder" then
		if f.b ~= layer or not onGrid(f.y - f.b / 2) then
			table.insert(offGrid, `{f.cone}:{f.layer}`)
		end
		local id, i = f.cone, f.layer
		if id and i then
			written[id] = written[id] or {}
			written[id][i] = f
		end
	end
end
check("every layer's fill exactly two voxel rows, on the grid", #offGrid == 0, table.concat(offGrid, ", "))
-- A layer left out: over each of its two voxel rows a bigger layer that was written holds its whole disc.
local left, unheld = 0, {}
for _, c in ring.cones do
	for i, r in c.radii do
		if written[c.id] and written[c.id][i] then
			continue
		end
		left += 1
		local x, z = AlpineLayout.layerAt(c, i)
		local y0 = c.floor + (i - 1) * layer
		for _, row in { y0, y0 + VOXEL } do
			local held = false
			for _, o in ring.grid[`{math.floor(x / 500)},{math.floor(z / 500)}`] or {} do
				local j = math.floor((row - o.floor) / layer) + 1
				local f = written[o.id] and written[o.id][j]
				if f and o ~= c and f.a > r and math.sqrt((x - f.x) ^ 2 + (z - f.z) ^ 2) + r <= f.a + 1e-6 then
					held = true
					break
				end
			end
			if not held then
				table.insert(unheld, `{c.id}:{i}@{row}`)
				break
			end
		end
	end
end
print(`  {layers} layers, {left} left out (inside a bigger neighbour's), {#ring.fills} fills`)
check("a layer is left out only where bigger written layers hold it over both its rows (the same terrain)", #unheld == 0 and left > 0, `{left} left out; not held: {table.concat(unheld, ", ")}`)
for _, s in ring.solids do
	check("the pass's cliff stands Gap out from the box, over the tunnel's mouth", math.abs(AlpineLayout.boxDistance(box, s.x, s.z) - A.Gap) < 0.5 and s.height >= A.Portal.Height + 20)
end

-- The ring holds the box: no way out over ground lower than Seal, not by car, not even swimming.
local carHeld, cx, cz = AlpineLayout.sealed(ring, 25, false)
check("the ring holds the box: no gap a car could drive through", carHeld, `{cx}, {cz}`)
local swimHeld, sx, sz = AlpineLayout.sealed(ring, 25, true)
check("… nor a swimmer (the river's gorges and the lake are closed)", swimHeld, `{sx}, {sz}`)
-- Step 2 pulls the box in (Config.Alpine.Box): a tighter ring holds its box the same way.
local tight = AlpineLayout.ring({ x0 = -1500, z0 = -2300, x1 = 1500, z1 = 1300 })
local tightCar = AlpineLayout.sealed(tight, 25, false)
local tightSwim = AlpineLayout.sealed(tight, 25, true)
check("a tighter box (step 2's) gets its own ring, and it holds", tight ~= ring and tightCar and tightSwim and #tight.cones > 0)
local tightIn = 0
for _, c in tight.cones do
	if AlpineLayout.boxDistance(tight.box, c.x, c.z) - c.radii[1] < A.Gap - 0.5 and c.row ~= "closer" then
		tightIn += 1
	end
end
check("… and stays out of its box", tightIn == 0, tightIn)

-- The gorges, the waterfall, the glaciers, the scree.
check("the river leaves through a gorge north and south", #ring.gorges == 2)
local fall = ring.waterfall
check("a waterfall where the river comes out of the north gorge (its foot in the river)", fall ~= nil and fall.points[1][1] > Map.River.x0 and fall.points[1][1] < Map.River.x1 and fall.points[#fall.points][2] >= 140)
check("glacier tongues down a few tall summer peaks", #ring.glaciers >= 4 and #ring.glaciers <= A.Glaciers.Count, #ring.glaciers)
check("scree at the foothills' feet", #ring.scree >= 10, #ring.scree)
local winterTops, summerSnow = 0, 0
for _, c in ring.cones do
	local top = AlpineLayout.layerMaterial(c, #c.radii, c.floor + (#c.radii - 0.5) * layer)
	local foot = AlpineLayout.layerMaterial(c, 2, c.floor + 1.5 * layer)
	if c.winter and foot == "Snow" then
		winterTops += 1
	elseif not c.winter and top == "Snow" and foot == "Grass" then
		summerSnow += 1
	end
end
check("the winter's mountains (north-west) snowy to the foot, the summer's green at the foot under snowy summits", winterTops >= 10 and summerSnow >= 20, `{winterTops} {summerSnow}`)

-- The silhouettes: inside their mountains' layers by Margin everywhere (a corner wedge pyramid and its cap).
local byId: { [string]: AlpineLayout.Cone } = {}
for _, c in ring.cones do
	byId[c.id] = c
end
local poking = {}
local function pyramidInside(c: AlpineLayout.Cone, x: number, z: number, base: number, half: number, height: number, yaw: number, margin: number): boolean
	local hd = half * math.sqrt(2)
	for i, r in c.radii do
		local y0, y1 = c.floor + (i - 1) * layer, c.floor + i * layer
		if y1 <= base or y0 >= base + height then
			continue
		end
		local y = math.max(y0, base)
		local d = hd * (1 - (y - base) / height)
		local lx, lz = AlpineLayout.layerAt(c, i)
		for q = 0, 3 do
			local a = yaw + math.pi / 4 + q * math.pi / 2
			local px, pz = x + math.cos(a) * d, z + math.sin(a) * d
			if math.sqrt((px - lx) ^ 2 + (pz - lz) ^ 2) > r - margin + 1e-6 then
				return false
			end
		end
	end
	return base + height <= c.floor + #c.radii * layer
end
for _, s in ring.silhouettes do
	local c = byId[s.cone]
	if not pyramidInside(c, s.x, s.z, s.base, s.half, s.height, s.yaw, A.Silhouettes.Margin) then
		table.insert(poking, s.cone)
	elseif s.capY < math.huge and not pyramidInside(c, s.x, s.z, s.capY, s.capHalf, s.capHeight, s.yaw, A.Silhouettes.Margin - 2) then
		table.insert(poking, s.cone .. " cap")
	end
end
check("a far silhouette for most big peaks", #ring.silhouettes >= 40, #ring.silhouettes)
check("every silhouette hides inside its mountain (Margin studs in, the cap too)", #poking == 0, table.concat(poking, ", "))

local function farmYard(): Map.Area
	for _, y in Map.Yards do
		if y.id == "farm" then
			return y
		end
	end
	error("no Old Farm")
end

-- The West Pass: on the box's west edge, on the West Highway's line past the Old Farm; the barrier in the box, the
-- mouth cut out of the cliff, the shutter closing it, the road clear of the yards and the other roads.
local pass = ring.portals[1]
check("the West Pass on the box's west edge at the West Highway's line", pass ~= nil and pass.x == box.x0 and pass.z == 520 and pass.nx == -1)
if pass then
	local parts, signs = AlpineLayout.portalParts(pass)
	local barrierIn, shutterOut, road = true, false, nil :: AlpineLayout.PartSpec?
	for _, p in parts do
		if p.name == "Barrier" and AlpineLayout.boxDistance(box, p.x, p.z) > -4 then
			barrierIn = false
		elseif p.name == "Shutter" then
			shutterOut = AlpineLayout.boxDistance(box, p.x, p.z) > A.Gap
		elseif p.name == "PassRoad" then
			road = p
		end
	end
	check("the ROAD CLOSED barrier inside the box, the shutter deep in the mouth", barrierIn and shutterOut)
	check("the barrier's board says ROAD CLOSED — EVACUATION ZONE", signs[1] ~= nil and signs[1].text == "ROAD CLOSED — EVACUATION ZONE")
	local cut = ring.cuts[1]
	check("the mouth is cut out of the cliff (Depth deep)", cut ~= nil and cut.x1 - cut.x0 >= A.Gap + A.Portal.Depth - 0.5 and cut.y1 >= A.Portal.Height)
	-- 7.1 review: whole voxels of air from the voxel row the road's top is in (a partly cut voxel keeps a skin of rock)
	local cutsOk = #ring.cuts > 0
	for _, c in ring.cuts do
		cutsOk = cutsOk and onGrid(c.x0) and onGrid(c.z0) and onGrid(c.x1) and onGrid(c.z1) and onGrid(c.y0) and onGrid(c.y1)
			and c.y0 <= Map.RoadTop and c.y0 > Map.RoadTop - VOXEL
	end
	check("the tunnel's air on the voxel grid, from the road's own voxel row up (no terrain skin on its road)", cutsOk)
	if road then
		local x0, x1 = road.x - road.sz / 2, road.x + road.sz / 2
		local z0, z1 = road.z - road.sx / 2, road.z + road.sx / 2
		local overlaps = {}
		for _, y in Map.Yards do
			if x0 < y.x1 - 0.5 and x1 > y.x0 + 0.5 and z0 < y.z1 and z1 > y.z0 then
				table.insert(overlaps, y.name)
			end
		end
		for _, s in Map.Segments do
			local half = s.width / 2
			if math.max(s.ax, s.bx) + half > x0 + 0.5 and math.min(s.ax, s.bx) - half < x1 and math.max(s.az, s.bz) + half > z0 and math.min(s.az, s.bz) - half < z1 then
				table.insert(overlaps, s.name or s.kind)
			end
		end
		check("the pass's road starts at the Old Farm's yard and crosses nothing", math.abs(x1 - farmYard().x0) < 1 and #overlaps == 0, table.concat(overlaps, ", "))
	end
end

-- ── The budgets ────────────────────────────────────────────────────────────

local forest = AlpineLayout.forest()
local volume = AlpineLayout.volume(ring.fills)
check("the terrain within its budget (studs³, fills)", volume <= A.Budget.Volume and #ring.fills <= A.Budget.Fills, `{math.floor(volume / 1e6)}M, {#ring.fills}`)
local parts = AlpineLayout.parts(ring, forest)
check("the parts within their budget", parts <= A.Budget.Parts, parts)
check(`at most {T.Max} trees`, #forest.trees <= T.Max and #forest.trees >= T.Max * 0.9, #forest.trees)
local badParts = 0
for _, t in forest.trees do
	local list = AlpineLayout.treeParts(t)
	if #list ~= T.Parts or not list[1].collide or list[1].shape ~= "cylinder" then
		badParts += 1
		continue
	end
	for n = 2, #list do
		if list[n].collide or list[n].shape ~= "ellipsoid" or list[n].sx / 2 > t.canopy + 1e-6 or list[n].sz / 2 > t.canopy + 1e-6 then
			badParts += 1
		end
	end
end
check(`every tree is {T.Parts} parts: a trunk that collides, one needle spire inside its canopy that does not`, badParts == 0, badParts)

-- ── The forests' rules ─────────────────────────────────────────────────────

local function segDistance(s: Map.Segment, x: number, z: number): number
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
	return math.sqrt((x - s.ax - dx * t) ^ 2 + (z - s.az - dz * t) ^ 2)
end
local function inRect(x: number, z: number, x0: number, z0: number, x1: number, z1: number, m: number): boolean
	return x > x0 - m and x < x1 + m and z > z0 - m and z < z1 + m
end

local broken: { [string]: number } = {}
local example: { [string]: string } = {}
local function fail(rule: string, t: AlpineLayout.Tree)
	broken[rule] = (broken[rule] or 0) + 1
	example[rule] = example[rule] or string.format("%.0f, %.0f", t.x, t.z)
end
local valley, slope = 0, 0
for _, t in forest.trees do
	local c = t.canopy
	if t.slope then
		slope += 1
		if AlpineLayout.boxDistance(box, t.x, t.z) < A.Gap then
			fail("a slope tree in the gap", t)
		end
		local h = AlpineLayout.heightAt(ring, t.x, t.z)
		if math.abs(h - t.y) > 0.01 or h < 4 or h > T.Treeline[2] then
			fail("a slope tree off the ring's lower slopes", t)
		end
		continue
	end
	valley += 1
	-- the roads (every one, not the rules' lookup): the canopy never over one, the drivers' view at the junctions
	for _, s in Map.Segments do
		if segDistance(s, t.x, t.z) - s.width / 2 < math.max(T.RoadClear, c + 4) - 1e-6 then
			fail("on or over a road", t)
			break
		end
	end
	for _, s in Map.Connectors do
		if math.min((t.x - s.ax) ^ 2 + (t.z - s.az) ^ 2, (t.x - s.bx) ^ 2 + (t.z - s.bz) ^ 2) < T.JunctionClear ^ 2 then
			fail("at a junction", t)
			break
		end
	end
	for _, d in Map.Districts do
		local x0, x1, z0, z1 = Map.districtEdges(d)
		if inRect(t.x, t.z, x0, z0, x1, z1, Map.RoadWidth / 2 + T.TownClear + c) then
			fail("in a district", t)
		end
	end
	-- the lots, the homes, the storefronts, the gas stations (all in the districts: checked anyway)
	for _, district in Map.AllLots do
		for _, block in district do
			for _, lot in block do
				if inRect(t.x, t.z, lot.x - lot.size / 2, lot.z - lot.size / 2, lot.x + lot.size / 2, lot.z + lot.size / 2, T.LotClear + c) then
					fail("on a lot", t)
				end
			end
		end
	end
	for _, home in Map.Homes do
		if (t.x - home.door.x) ^ 2 + (t.z - home.door.z) ^ 2 < 40 ^ 2 or (t.x - home.park.x) ^ 2 + (t.z - home.park.z) ^ 2 < 40 ^ 2 then
			fail("at a home", t)
		end
	end
	for _, venue in Map.Venues do
		if (t.x - venue.x) ^ 2 + (t.z - venue.z) ^ 2 < 50 ^ 2 or (t.x - venue.park.x) ^ 2 + (t.z - venue.park.z) ^ 2 < 40 ^ 2 then
			fail("at a storefront", t)
		end
	end
	for _, station in Map.GasStations do
		if (t.x - station.x) ^ 2 + (t.z - station.z) ^ 2 < 70 ^ 2 then
			fail("at a gas station", t)
		end
	end
	-- the homes out of town (the mansions, the villas, the cottage, the garages: their house, garden and drive)
	for _, plot in Map.EstatePlots do
		local ax, az = Map.plotPoint(plot, -plot.w / 2, -plot.front - 20)
		local bx, bz = Map.plotPoint(plot, plot.w / 2, plot.back)
		if inRect(t.x, t.z, math.min(ax, bx), math.min(az, bz), math.max(ax, bx), math.max(az, bz), T.LotClear + c) then
			fail("on a home's lot", t)
		end
	end
	-- the special places and the zones
	for _, y in Map.Yards do
		if inRect(t.x, t.z, y.x0, y.z0, y.x1, y.z1, T.YardClear + c) then
			fail("in a yard", t)
		end
	end
	for _, y in Map.Clearings do
		if inRect(t.x, t.z, y.x0, y.z0, y.x1, y.z1, c) then
			fail("in a clearing", t)
		end
	end
	for _, place in Map.Places do
		if (t.x - place.x) ^ 2 + (t.z - place.z) ^ 2 < (T.PlaceClear + c) ^ 2 then
			fail("at a place", t)
		end
	end
	for _, spot in Map.CargoSpots do
		if (t.x - spot.park.x) ^ 2 + (t.z - spot.park.z) ^ 2 < 30 ^ 2 or (t.x - spot.pile.x) ^ 2 + (t.z - spot.pile.z) ^ 2 < 30 ^ 2 then
			fail("at a cargo spot", t)
		end
	end
	for _, spot in Map.EmployerSpots do
		if (t.x - spot.x) ^ 2 + (t.z - spot.z) ^ 2 < 30 ^ 2 then
			fail("at an employer", t)
		end
	end
	for _, secret in Map.Secrets do
		if (t.x - secret.x) ^ 2 + (t.z - secret.z) ^ 2 < 20 ^ 2 then
			fail("at a lost package", t)
		end
	end
	if Map.isSafe(t.x, t.z) then
		fail("in the safe zone", t)
	end
	local park = Map.Park
	if (t.x - park.x) ^ 2 + (t.z - park.z) ^ 2 < (Map.BlockSize * 0.75) ^ 2 then
		fail("in the park", t)
	end
	local hills = Map.SunsetHills
	if inRect(t.x, t.z, hills.x0, hills.z0, hills.x1, hills.z1, 100) then
		fail("in Sunset Hills", t)
	end
	local m = Map.Mountain
	if (t.x - m.x) ^ 2 + (t.z - m.z) ^ 2 < (m.radius + 40) ^ 2 then
		fail("on Mount Rot", t)
	end
	for _, k in T.Keep do
		if inRect(t.x, t.z, k.x0, k.z0, k.x1, k.z1, c) then
			fail("in a kept-clear spot (the ski lift)", t)
		end
	end
	-- the water and the ice
	if Map.inWater(t.x - c, t.z) or Map.inWater(t.x + c, t.z) or Map.onIce(t.x, t.z) or Map.onIce(t.x + c, t.z) or Map.onIce(t.x - c, t.z) then
		fail("in the water or on the ice", t)
	end
	if AlpineLayout.treeRule(t.x, t.z, c) ~= nil then
		fail("against the layout's own rule", t)
	end
end
local list = {}
for rule, n in broken do
	table.insert(list, `{rule}: {n} (e.g. {example[rule]})`)
end
table.sort(list)
check("no tree on or over a road, at a junction, in a district, on a lot, at a home, a storefront, a yard, a place, a zone, the water or the ice", #list == 0, table.concat(list, "; "))
check(`about {math.floor(T.Slope * 100)} % of the trees up the ring's lower slopes`, math.abs(slope - T.Max * T.Slope) <= T.Max * 0.05, `{slope} of {#forest.trees}`)

-- No two trees in each other (their trunks at least the grid's spacing less both jitters apart).
local grid: { [string]: { AlpineLayout.Tree } } = {}
local crowded = 0
local least = T.Spacing - 2 * T.Jitter - 0.01
for _, t in forest.trees do
	local gx, gz = math.floor(t.x / 50), math.floor(t.z / 50)
	for dx = -1, 1 do
		for dz = -1, 1 do
			for _, o in grid[`{gx + dx},{gz + dz}`] or {} do
				if (o.x - t.x) ^ 2 + (o.z - t.z) ^ 2 < least * least then
					crowded += 1
				end
			end
		end
	end
	local key = `{gx},{gz}`
	grid[key] = grid[key] or {}
	table.insert(grid[key], t)
end
check("no two trees in each other", crowded == 0, crowded)
local unchunked = 0
for _, t in forest.trees do
	if t.chunk ~= AlpineLayout.chunkOf(t.x, t.z) then
		unchunked += 1
	end
end
check("every tree in its chunk (one Atomic model each)", unchunked == 0, unchunked)

-- Thinner near town, denser toward the mountains: trees per open square stud near the box's edge vs near town.
local function bandDensity(near: (number, number) -> boolean): number
	local trees, open = 0, 0
	for x = box.x0 + 20, box.x1, 40 do
		for z = box.z0 + 20, box.z1, 40 do
			if near(x, z) and AlpineLayout.treeRule(x, z, 0) == nil then
				open += 1
			end
		end
	end
	for _, t in forest.trees do
		if not t.slope and near(t.x, t.z) then
			trees += 1
		end
	end
	return trees / math.max(open, 1)
end
local function townDistance(x: number, z: number): number
	local best = math.huge
	for _, d in Map.Districts do
		local x0, x1, z0, z1 = Map.districtEdges(d)
		local dx = math.max(x0 - x, 0, x - x1)
		local dz = math.max(z0 - z, 0, z - z1)
		best = math.min(best, math.sqrt(dx * dx + dz * dz))
	end
	return best
end
local edgeDense = bandDensity(function(x: number, z: number): boolean
	return -AlpineLayout.boxDistance(box, x, z) < 500 and townDistance(x, z) > 500
end)
local townDense = bandDensity(function(x: number, z: number): boolean
	return townDistance(x, z) < 450
end)
check("thinner near town, denser toward the mountains", edgeDense > townDense * 2 and townDense > 0, string.format("%.2f vs %.2f", edgeDense, townDense))

-- Meadows: open valley land with no tree near (most of it), the wildflowers and the huts in them.
local openLand, meadow = 0, 0
for x = box.x0 + 50, box.x1, 100 do
	for z = box.z0 + 50, box.z1, 100 do
		if AlpineLayout.treeRule(x, z, 0) == nil then
			openLand += 1
			local free = true
			for _, t in forest.trees do
				if (t.x - x) ^ 2 + (t.z - z) ^ 2 < 50 ^ 2 then
					free = false
					break
				end
			end
			if free then
				meadow += 1
			end
		end
	end
end
check("meadows left open (most of the open valley has no tree within 50 studs)", meadow > openLand * 0.4 and meadow < openLand * 0.97, `{meadow} of {openLand}`)
local M = A.Meadows
local patchBad = 0
for n, p in forest.patches do
	if Map.isWinter(p.x, p.z) or AlpineLayout.treeRule(p.x, p.z, 10) ~= nil or #p.flowers ~= M.Flowers then
		patchBad += 1
	end
	local edge = AlpineLayout.roadEdge(p.x, p.z)
	if edge < M.Road[1] - 1e-6 or edge > M.Road[2] + 1e-6 then
		patchBad += 1
	end
	for _, f in p.flowers do
		if (f.x - p.x) ^ 2 + (f.z - p.z) ^ 2 > 9 ^ 2 then
			patchBad += 1
		end
	end
	for k = 1, n - 1 do
		local o = forest.patches[k]
		if (o.x - p.x) ^ 2 + (o.z - p.z) ^ 2 < M.Gap * M.Gap then
			patchBad += 1
		end
	end
	for _, t in forest.trees do
		if (t.x - p.x) ^ 2 + (t.z - p.z) ^ 2 < (t.canopy + 10) ^ 2 then
			patchBad += 1
		end
	end
end
check(`{M.Patches} wildflower meadows, in the open by the roads, apart, out of the winter`, #forest.patches == M.Patches and patchBad == 0, patchBad)
local H = A.Huts
local hutBad = 0
for n, hut in forest.huts do
	if AlpineLayout.treeRule(hut.x, hut.z, 16) ~= nil then
		hutBad += 1
	end
	local edge = AlpineLayout.roadEdge(hut.x, hut.z)
	if edge < H.Road[1] - 1e-6 or edge > H.Road[2] + 1e-6 then
		hutBad += 1
	end
	for k = 1, n - 1 do
		local o = forest.huts[k]
		if (o.x - hut.x) ^ 2 + (o.z - hut.z) ^ 2 < H.Gap * H.Gap then
			hutBad += 1
		end
	end
	for _, t in forest.trees do
		if (t.x - hut.x) ^ 2 + (t.z - hut.z) ^ 2 < (t.canopy + 16) ^ 2 then
			hutBad += 1
		end
	end
end
local barns = 0
for _, hut in forest.huts do
	if hut.kind == "barn" then
		barns += 1
	end
end
check(`{H.Count} hay barns and huts in the meadows, by a road, apart, clear of the trees`, #forest.huts == H.Count and hutBad == 0 and barns >= 1 and barns < #forest.huts, hutBad)

-- Shadows only near the roads (the far forests throw none).
local shadowFar = 0
for _, t in forest.trees do
	if t.shadow and (t.slope or AlpineLayout.roadEdge(t.x, t.z) >= T.ShadowNear) then
		shadowFar += 1
	end
end
check("only the trees near a road throw shadows", shadowFar == 0, shadowFar)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
