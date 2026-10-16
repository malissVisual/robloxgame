-- 8.9 SANDBOX on the map, 9.4 the countryside (design/countryside/plan.py, plan.json; the owner: "all the family houses
-- are gone; instead six different spots, no towns, no villages"): shared/SandboxMap.luau's map section
-- (tools/countryside/sandboxmap.py writes it from the plan: CountryPlan.luau, tests/run_tests.py's), shared/VillageScenery
-- .luau's layout and the world the real server/SandboxWorld.luau and server/VillageWorld.luau build (as SandboxWorldServer
-- .luau and VillageWorldServer.luau on tools/perf/world-mock.luau), the Auction House on:
--   * the fixed things exactly where they were: the plots, Depot Row, Pražská, the turnaround, the farmstead, the
--     Auction House's spot; the plan's roads, landmarks, fields, lawns, tree lines, woods, orchard and stream;
--   * every road joined to Depot Row (a van drives from the plots to every place), every curb in its yard;
--   * nothing over anything else: no road on another (they only meet), no road (its shoulder) on a place, a lot, a
--     landmark, a field, the stream, the D5 or a plot; no field on another, a lot, a landmark, a lawn or the stream; the
--     stream only through its weir, under its footbridge and into the pond; the places' lots apart;
--   * each place its own spot with its own surroundings: the farm's barn, tractor, bales, paddock and muck heap round
--     the farmstead; the fish pond by the cabin (its jetty); the lone house's garden and no neighbour within 300 studs;
--     the forest lodge in the forest's clearing, its woodpile; the old mill on its millrace (past its right-hand side as
--     you face its door), the weir and the footbridge; the orchard cottage in the orchard, its beehives, its fence;
--   * the trees where the rules let them stand (off the roads, lots, van ways, places, landmarks, the stream, the
--     clearing), the forest dense round the clearing, the orchard in rows; the hedges and fences, the stream's pieces;
--   * the world: the five places built once each, rich, in their own models; the countryside's pieces in Atomic chunks,
--     the D5 and the railway on every client, the far view outside the Bounds (no village on its horizon either);
--     nothing of it on a road, its shoulder, the turnaround, a plot, the farmstead's lot and path, a van's way, a place's
--     box or the Auction House; the words (MEADOW HALT; no village's: no CORNER DRUGSTORE, ROAD CLOSED, noticeboard);
--   * nothing of a village (no street of houses, no chapel, green, school, pitch, shop, hardware store, building site)
--     and nothing alpine in the sandbox's world; the part budget (SandboxScenery.Budget) with the Auction House.
-- Run with tests/run_tests.py.
local Mock = require("./WorldMock")
local G = Mock.globals
local Enum = G.Enum
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local VillageScenery = require("./VillageScenery")
local VillageLooks = require("./VillageLooks")
local CountryLooks = require("./CountryLooks")
local AuctionHouseLayout = require("./AuctionHouseLayout")
local SprinterLooks = require("./SprinterLooks")
local Plan = require("./CountryPlan")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

type Rect = { x0: number, x1: number, z0: number, z1: number }
local EPS = 1e-6
local MAP = SandboxMap
local B = MAP.Bounds
local TURN = MAP.Turnaround
local RUN = SandboxScenery.Run

local function same(a: Rect, b: Rect): boolean
	return math.abs(a.x0 - b.x0) < EPS and math.abs(a.x1 - b.x1) < EPS and math.abs(a.z0 - b.z0) < EPS and math.abs(a.z1 - b.z1) < EPS
end
local function rectOf(r: any): Rect
	return { x0 = r.x0, x1 = r.x1, z0 = r.z0, z1 = r.z1 }
end
local function grow(r: Rect, by: number): Rect
	return { x0 = r.x0 - by, x1 = r.x1 + by, z0 = r.z0 - by, z1 = r.z1 + by }
end
local function overlaps(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 - EPS and b.x0 < a.x1 - EPS and a.z0 < b.z1 - EPS and b.z0 < a.z1 - EPS
end
local function inRect(r: Rect, x: number, z: number): boolean
	return x >= r.x0 - EPS and x <= r.x1 + EPS and z >= r.z0 - EPS and z <= r.z1 + EPS
end
local function onAsphalt(x: number, z: number): boolean
	for _, r in MAP.Roads do
		if inRect(rectOf(r), x, z) then
			return true
		end
	end
	return SandboxScenery.circleOut(x, z) <= 0
end
local function mark(id: string): SandboxMap.Landmark?
	for _, l in MAP.Landmarks do
		if l.id == id then
			return l
		end
	end
	return nil
end
local function distance(a: Rect, b: Rect): number
	local dx = math.max(a.x0 - b.x1, 0, b.x0 - a.x1)
	local dz = math.max(a.z0 - b.z1, 0, b.z0 - a.z1)
	return math.sqrt(dx * dx + dz * dz)
end
-- The stream's water as squares along its middle line (for the overlap checks).
local function waterSquares(): { Rect }
	local out: { Rect } = {}
	for _, s in MAP.Streams do
		for i = 1, #s.points - 1 do
			local a, b = s.points[i], s.points[i + 1]
			local length = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
			local n = math.max(1, math.floor(length / 2))
			for k = 0, n do
				local x, z = a.x + (b.x - a.x) * k / n, a.z + (b.z - a.z) * k / n
				table.insert(out, { x0 = x - s.width / 2, x1 = x + s.width / 2, z0 = z - s.width / 2, z1 = z + s.width / 2 })
			end
		end
	end
	return out
end

-- ── The data: the plan's, the fixed things unchanged ───────────────────────

do
	check("the Bounds are the plan's (x -1180 … 420, z -680 … 760)", same(B, Plan.bounds) and B.x0 == -1180 and B.z1 == 760)
	local main, depot = MAP.Roads[1], MAP.Roads[2]
	check("Pražská and Depot Row first and where they always were (Pražská from z -74, through the junction, to the turnaround)",
		main.name == "Pražská" and same(rectOf(main), { x0 = -14, x1 = 14, z0 = -74, z1 = 470 }) and depot.name == "Depot Row"
			and same(rectOf(depot), { x0 = -270, x1 = 270, z0 = -74, z1 = -46 }) and not main.lane and not depot.lane and not main.yard)
	check("the turnaround, the ground's and the asphalt's tops, the doors' and the vans' gaps as they were",
		TURN.x == 0 and TURN.z == 470 and TURN.r == 34 and MAP.GroundTop == 0 and MAP.RoadTop == 0.4 and MAP.DoorWidth == 26 and MAP.VanGap == 6)
	local plotsOk = #MAP.Plots == 4
	for id, x in { -195, -65, 65, 195 } do
		local p = MAP.Plots[id]
		plotsOk = plotsOk and p.id == id and same(p.rect, { x0 = x - 60, x1 = x + 60, z0 = -230, z1 = -78 }) and p.warehouse.x == x and p.warehouse.z == -160
			and p.warehouse.sx == 80 and p.warehouse.sz == 60 and p.door.x == x and p.door.z == -130 and p.door.yaw == 180 and p.vanSpot.x == x
			and p.vanSpot.z == -113 and p.vanSpot.yaw == 180 and p.unload.z == -122 and p.spawn.x == x + 22 and p.board.x == x - 24
	end
	check("the four plots unchanged (rects, warehouses, doors, van spots, unload circles, spawns, boards)", plotsOk)
	local H = MAP.House
	check("the farmstead unchanged: its id, lot, box, door, curb and back door",
		H.id == "sandbox_house" and same(H.lot, { x0 = -60, x1 = 60, z0 = 504, z1 = 600 }) and H.house.x == 0 and H.house.z == 540 and H.house.sx == 44
			and H.house.sz == 34 and H.door.z == 523 and H.door.yaw == 0 and H.curb.z == 492 and H.back.z == 557)
	local spot = Config.Auction.House.Spot
	check("the Auction House's spot unchanged (158, -22, looking north; 48 × 32)", spot.x == 158 and spot.z == -22 and spot.yaw == 0 and Config.Auction.House.Width == 48 and Config.Auction.House.Depth == 32)

	-- the plan's roads, landmarks, fields, lawns, tree lines, woods, orchard and stream
	local roadsOk = #MAP.Roads == #Plan.roads
	for _, p in Plan.roads do
		local found = false
		for _, r in MAP.Roads do
			found = found or (r.name == p.name and same(rectOf(r), p.rect) and r.yard == p.yard and r.lane == (p.yard or math.min(r.x1 - r.x0, r.z1 - r.z0) < 28))
		end
		roadsOk = roadsOk and found
	end
	check(`the plan's {#Plan.roads} roads: Pražská, Depot Row and five lanes in their rects and yards (a lane narrower than Pražská)`, roadsOk)
	local marksOk = #MAP.Landmarks == #Plan.landmarks
	for n, p in Plan.landmarks do
		local m = MAP.Landmarks[n]
		marksOk = marksOk and m ~= nil and m.id == p.id and m.kind == p.kind and m.name == p.name and same(rectOf(m), p.rect) and m.yaw == p.yaw
	end
	check(`the plan's {#Plan.landmarks} landmarks (id, name, kind, rect, yaw)`, marksOk)
	local fieldsOk = #MAP.Fields == #Plan.fields
	for n, p in Plan.fields do
		local f = MAP.Fields[n]
		fieldsOk = fieldsOk and f ~= nil and f.kind == p.kind and same(rectOf(f), p.rect)
	end
	local lawnsOk = #MAP.Lawns == #Plan.lawns
	for n, p in Plan.lawns do
		local l = MAP.Lawns[n]
		lawnsOk = lawnsOk and l ~= nil and l.kind == p.kind and same(rectOf(l), p.rect)
	end
	check("the plan's fields and lawns (the forest's floor)", fieldsOk and lawnsOk and #MAP.Fields >= 12)
	local linesOk = #MAP.TreeLines == #Plan.lines
	for n, line in Plan.lines do
		local mine = MAP.TreeLines[n]
		linesOk = linesOk and mine ~= nil and mine.kind == line.kind and #mine.points == #line.points
		for i, p in line.points do
			linesOk = linesOk and mine.points[i].x == p.x and mine.points[i].z == p.z
		end
	end
	check("the plan's tree lines, hedges and fences", linesOk)
	local woodsOk = #MAP.Woods == #Plan.woods and same(MAP.Orchard, Plan.orchard) and #MAP.Streams == #Plan.streams
	for n, w in Plan.woods do
		local mine = MAP.Woods[n]
		woodsOk = woodsOk and mine.id == w.id and same(rectOf(mine), w.rect) and #mine.clearings == #w.clearings and same(mine.clearings[1], w.clearings[1])
	end
	for n, s in Plan.streams do
		local mine = MAP.Streams[n]
		woodsOk = woodsOk and mine.id == s.id and mine.width == s.width and #mine.points == #s.points
		for i, p in s.points do
			woodsOk = woodsOk and mine.points[i].x == p.x and mine.points[i].z == p.z
		end
	end
	check("the plan's forest (its clearing), orchard and millrace", woodsOk)
end

-- ── No village ─────────────────────────────────────────────────────────────

do
	local VILLAGE = { chapel = true, green = true, shop = true, school = true, pitch = true, hardware = true, lot = true, site = true, barrier = true, station = true }
	local found: string? = nil
	for _, l in MAP.Landmarks do
		if VILLAGE[l.kind] then
			found = l.id
		elseif not table.find(CountryLooks.Landmarks, l.kind) and l.kind ~= "motorway" then
			found = `{l.id}: a kind of no kit's`
		end
	end
	check("no village: no chapel, green, school, pitch, shop, hardware store, building site, station or barrier; every landmark the countryside's (or the D5)", found == nil, found)
	check("…no village's houses (SandboxMap.Village gone), no house but the six places", (MAP :: any).Village == nil and #MAP.Houses == 6 and #VillageScenery.houses() == 5)
	local streets: string? = nil
	for _, r in MAP.Roads do
		local known = r.name == "Pražská" or r.name == "Depot Row" or string.find(r.name, " Lane", 1, true) ~= nil or r.name == "Hill Road"
		streets = streets or (if known then nil else r.name)
	end
	check("…no village's streets (Hlavní, Školní, Lidická …): country lanes only", streets == nil, streets)
	local railway, halt = mark("railway"), mark("halt")
	check("…the railway along the south edge, a lone halt by it (no village's station)", railway ~= nil and halt ~= nil and railway.x0 == B.x0 and railway.z0 > 700
		and halt.z1 == railway.z0 and halt.x1 - halt.x0 <= 100)
end

-- ── The roads: all joined to Depot Row; every curb in its yard ─────────────

do
	-- two rects join where their asphalt meets along at least a van's width (a T, or one going on from the other)
	local function joins(a: Rect, b: Rect): boolean
		local x = math.min(a.x1, b.x1) - math.max(a.x0, b.x0)
		local z = math.min(a.z1, b.z1) - math.max(a.z0, b.z0)
		return (x >= -EPS and z >= 20) or (z >= -EPS and x >= 20)
	end
	local reached: { [number]: boolean } = { [2] = true }
	local grew = true
	while grew do
		grew = false
		for i, a in MAP.Roads do
			if not reached[i] then
				for j, b in MAP.Roads do
					if reached[j] and joins(rectOf(a), rectOf(b)) then
						reached[i] = true
						grew = true
					end
				end
			end
		end
	end
	local alone: { string } = {}
	for i, r in MAP.Roads do
		if not reached[i] then
			table.insert(alone, r.name)
		end
	end
	check(`every road's rect joined to Depot Row ({#MAP.Roads} rects: Mill Lane on from it, Wood Lane and Hill Road off it, Orchard Lane from its east end, Pond Lane off Pražská)`,
		#alone == 0, table.concat(alone, ", "))
	local main = MAP.Roads[1]
	check("the turnaround on Pražská's south end", TURN.z == main.z1 and TURN.r > (main.x1 - main.x0) / 2)
	-- the van at a curb: its back and nose on the asphalt
	local half = SprinterLooks.Length / 2
	local curbBad: string? = nil
	for index, h in MAP.Houses do
		local a = math.rad(h.curb.yaw)
		local lx, lz = -math.sin(a), -math.cos(a)
		local inYard = index == 1
		for _, r in MAP.Roads do
			inYard = inYard or (r.yard and r.name == h.street and inRect(rectOf(r), h.curb.x, h.curb.z))
		end
		if not inYard or not onAsphalt(h.curb.x + lx * half, h.curb.z + lz * half) or not onAsphalt(h.curb.x - lx * half, h.curb.z - lz * half) then
			curbBad = h.id
		end
	end
	check("every place's curb in its yard (the farmstead's on the turnaround), the van's back and nose on the asphalt", curbBad == nil, curbBad)
end

-- ── Nothing over anything else ─────────────────────────────────────────────

do
	local water = waterSquares()
	type Area = { name: string, kind: string, rect: Rect }
	local areas: { Area } = {}
	for n, r in MAP.Roads do
		table.insert(areas, { name = `{r.name} {n}`, kind = "road", rect = grow(rectOf(r), RUN) })
	end
	for _, p in MAP.Plots do
		table.insert(areas, { name = `plot {p.id}`, kind = "plot", rect = p.rect })
	end
	for _, h in MAP.Houses do
		table.insert(areas, { name = `{h.id}'s box`, kind = "box", rect = h.box })
		table.insert(areas, { name = `{h.id}'s lot`, kind = "lot", rect = h.lot })
	end
	for _, l in MAP.Landmarks do
		table.insert(areas, { name = l.id, kind = "landmark", rect = rectOf(l) })
	end
	for n, f in MAP.Fields do
		table.insert(areas, { name = `field {n}`, kind = "field", rect = rectOf(f) })
	end
	for n, w in water do
		table.insert(areas, { name = `the stream ({math.floor(w.x0)}, {math.floor(w.z0)})`, kind = "stream", rect = w })
	end
	local t = TURN
	table.insert(areas, { name = "the turnaround", kind = "turnaround", rect = { x0 = t.x - t.r - RUN, x1 = t.x + t.r + RUN, z0 = t.z - t.r - RUN, z1 = t.z + t.r + RUN } })
	-- what may meet: the roads one another (they meet, their shoulders over each other), a lot its yard's shoulder and
	-- its box, the stream its own squares, its weir, its footbridge, the pond it runs into and the mill on it
	local ALLOWED = { road_road = true, road_turnaround = true, lot_road = true, lot_turnaround = true, box_lot = true, stream_stream = true }
	local WET = { weir = true, footbridge = true, pond = true, old_mill = true }
	local bad: string? = nil
	for i, a in areas do
		for j = i + 1, #areas do
			local b = areas[j]
			local pair = if a.kind < b.kind then `{a.kind}_{b.kind}` else `{b.kind}_{a.kind}`
			if ALLOWED[pair] or (pair == "box_lot" or pair == "lot_lot") and false then
				continue
			end
			if pair == "landmark_stream" or pair == "box_stream" then
				local other = if a.kind == "stream" then b else a
				local id = if other.kind == "box" then string.gsub(other.name, "'s box", "") else other.name
				if WET[id] then
					continue
				end
			end
			if overlaps(a.rect, b.rect) then
				bad = `{a.name} on {b.name}`
			end
		end
	end
	check("nothing over anything else: no road (its shoulder) on another's asphalt but where they meet, on a place, a lot, a landmark, a field, the stream, the D5 or a plot; no field on another, a lot, a landmark or the stream (the stream only through its weir, under its footbridge, past the mill, into the pond)",
		bad == nil, bad)
	-- the roads' asphalt: none over another (Pražská's from Depot Row's far edge: its slab from Depot Row's south edge)
	local roadBad: string? = nil
	for i, a in MAP.Roads do
		for j, b in MAP.Roads do
			if j > i and not (i == 1 and j == 2) and overlaps(rectOf(a), rectOf(b)) then
				roadBad = `{a.name} {i} on {b.name} {j}`
			end
		end
	end
	check("no road's asphalt over another's (they only meet)", roadBad == nil, roadBad)
	-- no lawn on a field or a lot: no two ground tiles on one plane
	local lawnBad: string? = nil
	for n, l in MAP.Lawns do
		for _, f in MAP.Fields do
			lawnBad = lawnBad or (if overlaps(rectOf(l), rectOf(f)) then `lawn {n} on a field` else nil)
		end
		for m, o in MAP.Lawns do
			lawnBad = lawnBad or (if m > n and overlaps(rectOf(l), rectOf(o)) then `lawns {n} and {m}` else nil)
		end
		lawnBad = lawnBad or (if overlaps(rectOf(l), MAP.House.lot) then `lawn {n} on the farmstead's lot` else nil)
	end
	check("the lawns (the forest's floor) on no field, no other lawn, not the farmstead's lot", lawnBad == nil, lawnBad)
end

-- ── Each place its own spot ────────────────────────────────────────────────

do
	local function near(id: string, r: Rect, within: number): boolean
		local l = mark(id)
		return l ~= nil and distance(rectOf(l), r) <= within
	end
	local H = MAP.Houses
	local farm = MAP.House
	check("the farm: a barn, the old tractor and trailer, round bales and a haystack, a fenced paddock, a muck heap and woodpile round the farmstead's lot, fields beside it",
		near("barn", farm.lot, 60) and near("tractor", farm.lot, 120) and near("bales", farm.lot, 40) and near("paddock", farm.lot, 30) and near("muckheap", farm.lot, 60)
			and mark("barn").kind == "barn" and mark("paddock").kind == "paddock" and (function(): boolean
				for _, f in MAP.Fields do
					if distance(rectOf(f), farm.lot) < 120 then
						return true
					end
				end
				return false
			end)())
	local cabin = SandboxMap.house("pond_cabin") :: SandboxMap.House
	local pond = mark("pond")
	check("the Pond Cabin on the shore of the fish pond (its lot by the pond's rect)", pond ~= nil and pond.kind == "fishpond" and distance(rectOf(pond), cabin.lot) <= 2
		and distance(rectOf(pond), cabin.box) <= 10)
	local lone = SandboxMap.house("lone_house") :: SandboxMap.House
	local neighbour = math.huge
	for _, h in H do
		if h ~= lone then
			neighbour = math.min(neighbour, distance(h.box, lone.box))
		end
	end
	check(`the Lone House alone by Hill Road among fields, its garden (its nearest neighbour {math.floor(neighbour)} studs off)`, neighbour >= 300 and near("garden", lone.lot, 10)
		and lone.look == "old" and lone.street == "Hill Road")
	local lodge = SandboxMap.house("forest_lodge") :: SandboxMap.House
	local wood = MAP.Woods[1]
	local clearing = wood.clearings[1]
	check("the Forest Lodge in the forest's clearing (its box and lot in it, the clearing in the forest), its woodpile beside it", clearing.x0 <= lodge.lot.x0 and clearing.x1 >= lodge.lot.x1
		and clearing.z0 <= lodge.lot.z0 and clearing.x0 >= wood.x0 and clearing.x1 <= wood.x1 and clearing.z0 >= wood.z0 and clearing.z1 <= wood.z1
		and near("woodyard", lodge.lot, 20) and inRect(clearing, (mark("woodyard") :: any).x0, (mark("woodyard") :: any).z0))
	-- the mill: the millrace past its right-hand side (seen from outside facing its door), along its whole wall
	local mill = SandboxMap.house("old_mill") :: SandboxMap.House
	local a = math.rad(mill.yaw)
	local ox, oz = -math.sin(a), -math.cos(a) -- (out of its door)
	local rx, rz = oz, -ox -- (the right of somebody outside facing the door: they look (-ox, -oz))
	local b = mill.box
	local wallX = if rx < 0 then b.x0 elseif rx > 0 then b.x1 else nil
	local alongside = wallX ~= nil
	for z = b.z0, b.z1, 2 do
		alongside = alongside and wallX ~= nil and VillageScenery.streamDistance(wallX + rx * 3, z) <= 0
	end
	check("the Old Mill on its millrace: the water along its right-hand side (its west wall, as you face its door), the weir upstream, the footbridge downstream",
		alongside and near("weir", b, 140) and near("footbridge", b, 30) and (mark("weir") :: any).z1 < b.z0 and (mark("footbridge") :: any).z0 > b.z1, `{rx}, {rz}`)
	local cottage = SandboxMap.house("orchard_cottage") :: SandboxMap.House
	local orchard = MAP.Orchard
	local fenced = false
	for _, line in MAP.TreeLines do
		fenced = fenced or line.kind == "fence"
	end
	check("the Orchard Cottage in the orchard (its box in it), its beehives among the fruit trees, a fence round it", inRect(orchard, cottage.box.x0, cottage.box.z0)
		and inRect(orchard, cottage.box.x1, cottage.box.z1) and near("apiary", orchard, 0) and inRect(orchard, (mark("apiary") :: any).x0, (mark("apiary") :: any).z0) and fenced)
end

-- ── The layout ─────────────────────────────────────────────────────────────

local houses = VillageScenery.houses()
local marks = VillageScenery.landmarks()
local trees = VillageScenery.trees()
do
	local ids: { [string]: number } = {}
	local hookBad: string? = nil
	for _, h in houses do
		for _, id in h.ids do
			ids[id] = (ids[id] or 0) + 1
		end
		local place = VillageScenery.emptied(h)
		if not place or h.opts.rich ~= true or h.kind ~= place.look or VillageScenery.lookOf(place.look) ~= place.look then
			hookBad = `{h.id}: not its place's, rich, in its own look`
		end
		local made = VillageLooks.house(h.kind, h.box, h.yaw, h.seed, h.opts)
		if #made > VillageLooks.budget(h.kind, 1, true) and VillageLooks.budget(h.kind, 1, true) > 0 then
			hookBad = `{h.id}: {#made} parts over its budget`
		end
	end
	for index, h in MAP.Houses do
		if index > 1 and ids[h.id] ~= 1 then
			hookBad = `{h.id} built {ids[h.id] or 0} times`
		end
	end
	check(`the five places but the farmstead each built once, rich, in its own look (9.5: VillageLooks draws every one: no stand-in "old"), within its budget`,
		hookBad == nil and #houses == 5 and VillageScenery.houses() == houses and VillageScenery.houses(VillageScenery.enter()) == houses, hookBad)
	check("VillageScenery.lookOf: a look VillageLooks draws is itself (a family house's, the countryside's), one it does not is the old family house",
		VillageScenery.lookOf("old") == "old" and VillageScenery.lookOf("cabin") == "cabin" and VillageScenery.lookOf("mill") == "mill"
		and VillageScenery.lookOf("no such look") == "old")
	-- the landmarks: each looking its own yaw, the D5 and the railway kept on every client, none on a road or its shoulder
	local markBad: string? = nil
	local far = 0
	for _, m in marks do
		local l = mark(m.id)
		if not l or m.yaw ~= l.yaw or m.far ~= (m.kind == "motorway" or m.kind == "railway") then
			markBad = m.id
		end
		far += if m.far then 1 else 0
		for _, r in MAP.Roads do
			if overlaps(grow(m.box, RUN), rectOf(r)) then
				markBad = `{m.id} on {r.name}`
			end
		end
		if #VillageScenery.pieces(m) == 0 then
			markBad = `{m.id}: no pieces`
		end
	end
	check(`the landmarks ({#marks}): each its own yaw, none on a road or its shoulder; the D5 and the railway kept on every client`, markBad == nil and far == 3 and #marks == #MAP.Landmarks, markBad)

	-- the trees: where the rules let them; the forest dense round its clearing, none in it, none on the stream
	local treeBad: string? = nil
	local inForest, inOrchard = 0, 0
	local wood = MAP.Woods[1]
	for _, t in trees do
		local rule = VillageScenery.treeRule(t.x, t.z, t.radius)
		treeBad = treeBad or (if rule then `a tree at {math.floor(t.x)}, {math.floor(t.z)}: {rule}` else nil)
		for _, h in MAP.Houses do
			if SandboxScenery.rectDistance(h.box, t.x, t.z) < t.radius then
				treeBad = `a tree's crown over the place {h.id}`
			end
		end
		if inRect(wood.clearings[1], t.x, t.z) then
			treeBad = `a tree in the clearing at {math.floor(t.x)}, {math.floor(t.z)}`
		end
		if VillageScenery.streamDistance(t.x, t.z) < 0 then
			treeBad = `a tree in the stream at {math.floor(t.x)}, {math.floor(t.z)}`
		end
		inForest += if t.from == wood.id then 1 else 0
		inOrchard += if t.from == "orchard" then 1 else 0
	end
	local area = (wood.x1 - wood.x0) * (wood.z1 - wood.z0)
	check(`the trees ({#trees}): each where the rules let it (off the roads, plots, lots, van ways, places, landmarks, the Auction House, the stream, the clearing)`, treeBad == nil and #trees >= 250, treeBad)
	check(`…the forest dense round its clearing ({inForest} trees, one every {math.floor(area / math.max(inForest, 1))} studs²), the orchard in rows ({inOrchard} fruit trees)`,
		inForest >= 150 and area / inForest <= 1100 and inOrchard >= 40)
	-- the lines and the stream: their pieces, decoration
	local lines = VillageScenery.lines()
	local hedges, posts = 0, 0
	for _, p in lines do
		hedges += if p.name == "Hedge" then 1 else 0
		posts += if p.name == "FencePostCountry" then 1 else 0
	end
	local streams = VillageScenery.streams()
	local wet = 0
	for _, p in streams do
		wet += if p.name == "Water" then 1 else 0
	end
	check(`the hedges ({hedges}) and the orchard's fence ({posts} posts), the stream ({wet} stretches of water)`, hedges >= 3 and posts >= 20 and wet == #MAP.Streams[1].points - 1)
	-- the D5's lanes: two each way on the carriageways' tops, run past the Bounds onto the far D5
	local lanes = VillageScenery.lanes()
	local north, south = 0, 0
	local laneOk = #lanes == 4
	local farRoad: { number }? = nil
	local villageFar: string? = nil
	for _, p in VillageScenery.far() do
		if p.name == "FarCarriageway" then
			local x0, x1, _, y1, z0, z1 = VillageLooks.box(p)
			farRoad = { x0, x1, y1, z1 - z0 }
		elseif p.name == "FarHouse" or p.name == "FarRoof" or p.name == "FarChurch" or p.name == "FarSpire" then
			villageFar = p.name
		end
	end
	for _, l in lanes do
		north += if l.dz < 0 then 1 else 0
		south += if l.dz > 0 then 1 else 0
		laneOk = laneOk and farRoad ~= nil and l.x > farRoad[1] and l.x < farRoad[2] and math.abs(l.y - farRoad[3]) < 0.01
			and l.z0 == B.z0 - Config.VillageWorld.Cars.Beyond and l.z1 == B.z1 + Config.VillageWorld.Cars.Beyond and Config.VillageWorld.Cars.Beyond < farRoad[4]
			and (l.dz < 0) == (l.x > 360)
	end
	check("the D5's four lanes: two north on the east carriageway, two south on the west (right-hand), on the far D5 past the Bounds", laneOk and north == 2 and south == 2)
	check("…and no village on the far horizon either (no far roofs, no church tower)", villageFar == nil, villageFar)
end

-- ── The world ──────────────────────────────────────────────────────────────

Config.Auction.On = true -- (the most it holds)
local SandboxWorld = require("./SandboxWorldServer")
local world = SandboxWorld.build()
type Box = { part: any, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number }
local function boxOf(d: any): Box
	local size = d.Size
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
	local hx = (math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z) / 2
	local hy = (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2
	local hz = (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
	return { part = d, x0 = x - hx, x1 = x + hx, y0 = y - hy, y1 = y + hy, z0 = z - hz, z1 = z + hz }
end
local all: { Box } = {}
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(all, boxOf(d))
	end
end
local village = world:FindFirstChild("Village")
local motorway = world:FindFirstChild("Motorway")
local railway = world:FindFirstChild("Railway")
local far = world:FindFirstChild("Far")
local ground = world:FindFirstChild("Ground")
do
	local budget = SandboxScenery.Budget
	check(`the map's part budget holds with the Auction House on, with room to spare ({#all} parts, at most {budget}; {budget - #all} left)`, #all <= budget - 300 and #all > 1200, #all)
	print(`INFO  the map: {#all} parts ({village and #village:GetDescendants() or 0} in Village with models and words)`)
	check("the countryside in workspace.Sandbox: Village, the Persistent Motorway, Railway and Far, the Ground and the Roads Persistent too", village ~= nil and motorway ~= nil
		and motorway.ModelStreamingMode == Enum.ModelStreamingMode.Persistent and railway ~= nil and railway.ModelStreamingMode == Enum.ModelStreamingMode.Persistent
		and far ~= nil and far.ModelStreamingMode == Enum.ModelStreamingMode.Persistent and ground ~= nil and ground.ModelStreamingMode == Enum.ModelStreamingMode.Persistent
		and world:FindFirstChild("Roads").ModelStreamingMode == Enum.ModelStreamingMode.Persistent)
	-- the chunks: every model under Village an Atomic Village_<chunk>
	local chunkBad: string? = nil
	local chunks = 0
	for _, model in (if village then village:GetChildren() else {}) do
		chunks += 1
		if not (model:IsA("Model") and model.ModelStreamingMode == Enum.ModelStreamingMode.Atomic and string.sub(model.Name, 1, 8) == "Village_") then
			chunkBad = model.Name
		end
	end
	local houseModels, markModels = 0, 0
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("VillageHouse") then
			houseModels += 1
		elseif d:IsA("Model") and d:GetAttribute("VillageLandmark") then
			markModels += 1
		end
	end
	check(`the five places (SandboxWorld's), the landmarks ({markModels}) and the trees in {chunks} Atomic chunk models (Village_<chunk>)`, chunkBad == nil and chunks > 20
		and houseModels == 5 and markModels == #marks, chunkBad)
	-- the places to empty: each built once, rich (its look's rich pieces: the doorstep, the mailbox), in its own model
	local emptyBad: string? = nil
	local seenEmpty: { [string]: number } = {}
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("VillageHouse") then
			local id = d:GetAttribute("SandboxHouse")
			seenEmpty[id or "?"] = (seenEmpty[id or "?"] or 0) + 1
			local body = id and d:FindFirstChild("House_" .. id)
			if not (body and body:FindFirstChild("FrontDoor")) then
				emptyBad = `{id}: no body or door`
			end
		end
	end
	for index, h in MAP.Houses do
		if index > 1 and seenEmpty[h.id] ~= 1 then
			emptyBad = `{h.id} built {seenEmpty[h.id] or 0} times`
		end
	end
	check("the five places each built once, in its own model (SandboxHouse), its door", emptyBad == nil, emptyBad)
	-- nothing of the countryside on a road, its shoulder, the turnaround, a plot, the farmstead's lot and path, the vans'
	-- ways, a place's box or the Auction House
	local keep: { { name: string, rect: Rect } } = {}
	for n, r in MAP.Roads do
		table.insert(keep, { name = `{r.name} {n}`, rect = grow(rectOf(r), RUN) })
	end
	for _, plot in MAP.Plots do
		table.insert(keep, { name = `plot {plot.id}`, rect = plot.rect })
	end
	table.insert(keep, { name = "the farmstead's lot", rect = MAP.House.lot })
	table.insert(keep, { name = "the farmstead's path", rect = SandboxScenery.Path })
	for n, way in SandboxScenery.vanPaths() do
		table.insert(keep, { name = `van way {n}`, rect = way })
	end
	for index, h in MAP.Houses do
		if index > 1 then
			table.insert(keep, { name = `the place {h.id}`, rect = h.box })
		end
	end
	table.insert(keep, { name = "the Auction House", rect = AuctionHouseLayout.site() })
	local onRoad: string? = nil
	local seen = 0
	for _, b in all do
		local p = b.part
		if village and p:IsDescendantOf(village) then
			seen += 1
			-- (a place's own model stands on its own box, its lot and its yard's edge)
			local own: string? = nil
			local at = p.Parent
			while at and at ~= village do
				own = own or at:GetAttribute("SandboxHouse")
				at = at.Parent
			end
			if own then
				continue
			end
			for _, k in keep do
				-- (the millrace's flat water and bed may lie in the mill's van way: it keeps trees off, water is no obstacle)
				local flat = (p.Name == "Water" or p.Name == "StreamBed") and string.sub(k.name, 1, 8) == "van way "
				if not flat and overlaps({ x0 = b.x0, x1 = b.x1, z0 = b.z0, z1 = b.z1 }, k.rect) then
					onRoad = `{p.Name} of {p.Parent.Name} on {k.name}`
				end
			end
			local cx, cz = math.clamp(TURN.x, b.x0, b.x1), math.clamp(TURN.z, b.z0, b.z1)
			if (cx - TURN.x) ^ 2 + (cz - TURN.z) ^ 2 < (TURN.r + RUN) ^ 2 then
				onRoad = `{p.Name} on the turnaround`
			end
		end
	end
	check(`nothing of the countryside ({seen} parts) on a road or its shoulder, the turnaround, a plot, the farmstead's lot or path, a van's way, a place's box or the Auction House`,
		onRoad == nil and seen > 800, onRoad)
	-- the D5 and the railway inside the Bounds, the far view outside them
	local farBad: string? = nil
	for _, b in all do
		if far and b.part:IsDescendantOf(far) and b.y1 > MAP.GroundTop + EPS and b.x0 < B.x1 and b.x1 > B.x0 and b.z0 < B.z1 and b.z1 > B.z0 then
			farBad = b.part.Name
		elseif motorway and b.part:IsDescendantOf(motorway) and (b.x0 < B.x0 or b.x1 > B.x1 or b.z0 < B.z0 - EPS or b.z1 > B.z1 + EPS or b.x0 < 300) then
			farBad = `the D5's {b.part.Name}`
		elseif railway and b.part:IsDescendantOf(railway) and (b.x0 < B.x0 - EPS or b.x1 > B.x1 + EPS or b.z0 < 700 or b.z1 > B.z1) then
			farBad = `the railway's {b.part.Name}`
		end
	end
	check("the D5 at the map's east edge and the railway along its south edge inside the Bounds, the far view outside them", farBad == nil and motorway ~= nil
		and #motorway:GetChildren() == 1 and railway ~= nil and #railway:GetChildren() == 2, farBad)
	-- the words
	local texts: { [string]: number } = {}
	local contracts = 0
	for _, d in world:GetDescendants() do
		if d.ClassName == "TextLabel" then
			texts[d.Text] = (texts[d.Text] or 0) + 1
		elseif d:IsA("BasePart") and d:GetAttribute("VillageContracts") then
			contracts += 1
		end
	end
	check("the words: the halt's MEADOW HALT; none of a village's (no CORNER DRUGSTORE, ROAD CLOSED, MOVING CONTRACTS noticeboard)", texts["MEADOW HALT"] == 1
		and texts["CORNER DRUGSTORE"] == nil and texts["ROAD CLOSED"] == nil and texts["MOVING CONTRACTS"] == nil and contracts == 0)
	-- the ground: the fields (each a tile and its rows) and the lawns in the Ground, flush with the meadow
	local fields, lawns, high = 0, 0, nil :: string?
	for _, b in all do
		if ground and b.part:IsDescendantOf(ground) then
			fields += if b.part.Name == "Field" then 1 else 0
			lawns += if string.sub(b.part.Name, 1, 5) == "Lawn_" then 1 else 0
			if (b.part.Name == "Field" or string.sub(b.part.Name, 1, 5) == "Lawn_" or b.part.Name == "Meadow") and math.abs(b.y1 - MAP.GroundTop) > EPS then
				high = b.part.Name
			end
		end
	end
	check(`the ground: {fields} field tiles and {lawns} lawns (the forest's floor) in the Ground, their tops the meadow's`, fields == #MAP.Fields and lawns == #MAP.Lawns and high == nil, high)
end

-- nothing alpine left: no spruce's needles, no mound, hill, peak or snow, no wildflowers or rail fence round the edge,
-- no THE OLD CHALET; nothing of a village either (no chapel, green, shop parts)
do
	local ALPINE = { Needles = true, Mound = true, Hill = true, Peak = true, PeakSnow = true, Flower = true, FarMeadow = true, Spruce = true, Fir = true }
	local VILLAGE = { Nave = true, Apse = true, Tower = true, Noticeboard = true, Store = true, Shopfront = true, BarrierBoard = true, Hall = true, FarChurch = true, FarHouse = true }
	local found: string? = nil
	for _, b in all do
		local p = b.part
		if ALPINE[p.Name] or VILLAGE[p.Name] or p.Material == Enum.Material.Snow or p.Material == Enum.Material.Glacier then
			found = p.Name
		end
		local inGarden = p:FindFirstAncestor("TheOldFarmstead") ~= nil
		if (p.Name == "FencePost" or p.Name == "FenceRail") and not inGarden then
			found = `the rail fence's {p.Name}`
		end
	end
	local scenery = world:FindFirstChild("Scenery")
	for _, name in { "Trees", "Wildflowers", "Fence" } do
		if scenery and scenery:FindFirstChild(name) then
			found = `Scenery/{name}`
		end
	end
	for _, d in world:GetDescendants() do
		if d.ClassName == "TextLabel" and (string.find(string.upper(d.Text), "CHALET", 1, true) or string.find(string.upper(d.Text), "JINO", 1, true)) then
			found = d.Text
		end
	end
	check("nothing alpine nor of a village in the sandbox's world: no spruce, mound, hill, peak, snow, wildflowers, rail fence, chalet sign, chapel, shop or far roofs", found == nil, found)
end

Config.Auction.On = false

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
