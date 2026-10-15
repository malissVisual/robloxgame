-- 8.9 SANDBOX, Jinočany step 1 on the map (design/jinocany/NAVRH.md §4, §7): shared/SandboxMap.luau's village section
-- (tools/village/sandboxmap.py writes it from design/jinocany/plan.json: JinocanyPlan.luau, tests/run_tests.py's),
-- shared/VillageScenery.luau's layout and the world the real server/SandboxWorld.luau and server/VillageWorld.luau build
-- (as SandboxWorldServer.luau and VillageWorldServer.luau on tools/perf/world-mock.luau), the Auction House on:
--   * the fixed things exactly where they were (§1): the plots, Depot Row, Pražská, the turnaround, the farmstead, the
--     Auction House's spot; the step-1 roads, houses, landmarks, fields and tree lines the plan's;
--   * every road joined to Depot Row (a van can drive from the plots to it), every house's curb (the village's and the
--     six to empty) on its street's asphalt with the van's back and nose on it;
--   * no house, tree or landmark on a road, its shoulder, a plot, the farmstead's lot and path or a house to empty's box
--     (but Hornická's barrier, across its road on purpose); the trees where the rules let them stand;
--   * every village house's door looking out onto its street;
--   * the village's houses, landmarks and trees in Atomic chunk models, the D5 and the far view on every client, the
--     words (CORNER DRUGSTORE, ROAD CLOSED, MOVING CONTRACTS), the D5's lanes for the client's cars;
--   * nothing alpine left in the sandbox's world; the part budget (SandboxScenery.Budget) with the Auction House.
-- Run with tests/run_tests.py.
local Mock = require("./WorldMock")
local G = Mock.globals
local Enum = G.Enum
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local VillageScenery = require("./VillageScenery")
local VillageLooks = require("./VillageLooks")
local AuctionHouseLayout = require("./AuctionHouseLayout")
local SprinterLooks = require("./SprinterLooks")
local Plan = require("./JinocanyPlan")

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
local function roadNamed(name: string): SandboxMap.Road?
	for _, r in MAP.Roads do
		if r.name == name then
			return r
		end
	end
	return nil
end
local function onAsphalt(x: number, z: number): boolean
	for _, r in MAP.Roads do
		if x >= r.x0 - EPS and x <= r.x1 + EPS and z >= r.z0 - EPS and z <= r.z1 + EPS then
			return true
		end
	end
	return SandboxScenery.circleOut(x, z) <= 0
end

-- ── The data: the plan's step 1, the fixed things unchanged ────────────────

do
	check("the Bounds are the plan's (x -1180 … 420, z -680 … 760)", same(B, Plan.bounds) and B.x0 == -1180 and B.z1 == 760)
	-- (today's, before the village: shared/SandboxMap.luau 8.8)
	local main, depot = MAP.Roads[1], MAP.Roads[2]
	check("Pražská and Depot Row first and where they always were (Pražská from z -74, through the junction, to the turnaround)",
		main.name == "Pražská" and same(rectOf(main), { x0 = -14, x1 = 14, z0 = -74, z1 = 470 }) and depot.name == "Depot Row"
			and same(rectOf(depot), { x0 = -270, x1 = 270, z0 = -74, z1 = -46 }) and not main.lane and not depot.lane)
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

	-- the plan's step-1 roads, each in Roads with its rect (Pražská from Depot Row's north edge as today); a lane narrower
	local roadsOk, count = true, 0
	for _, r in Plan.roads do
		local found = roadNamed(r.name)
		if r.step <= 1 then
			count += 1
			local want = if r.name == "Pražská" then { x0 = -14, x1 = 14, z0 = -74, z1 = 470 } else r.rect
			roadsOk = roadsOk and found ~= nil and same(rectOf(found), want)
				and found.lane == (math.min(found.x1 - found.x0, found.z1 - found.z0) < 28)
		else
			roadsOk = roadsOk and found == nil
		end
	end
	check(`the plan's {count} step-1 streets, none of the later steps' (Severní, Žižkova, Tylova, Čapkova)`, roadsOk and count == #MAP.Roads and #MAP.Roads == 10)
	-- the plan's step-1 houses but the ones to empty, each with its box, yaw, door and curb
	local houses, enter, bad = 0, 0, nil :: string?
	local byId: { [string]: SandboxMap.VillageHouse } = {}
	for _, h in MAP.Village do
		byId[h.id] = h
	end
	for _, h in Plan.houses do
		local mine = byId[h.id]
		if h.step <= 1 and not h.enter then
			houses += 1
			if not mine or not same(rectOf(mine), h.box) or mine.yaw ~= h.yaw or mine.street ~= h.street or mine.kind ~= h.kind
				or mine.door.x ~= h.door.x or mine.door.z ~= h.door.z or mine.curb.x ~= h.curb.x or mine.curb.z ~= h.curb.z then
				bad = h.id
			end
		elseif mine then
			bad = `{h.id} (to empty or a later step) is in Village`
		end
		enter += if h.enter then 1 else 0
	end
	check(`the plan's {houses} step-1 houses in Village (box, yaw, street, kind, door, curb); none of the {enter} to empty (the moves' own)`, bad == nil and houses == #MAP.Village and houses > 70 and enter == 5, bad)
	local marks, markBad = 0, nil :: string?
	for _, l in Plan.landmarks do
		local found: SandboxMap.Landmark? = nil
		for _, m in MAP.Landmarks do
			if m.id == l.id then
				found = m
			end
		end
		if l.step <= 1 and l.kind ~= "orchard" then
			marks += 1
			-- (the drugstore's west edge moved from 40 to 56: tools/village/sandboxmap.py ADJUST, the TOP MOVERS board's room)
			local want = if l.id == "drugstore" then { x0 = 56, x1 = l.rect.x1, z0 = l.rect.z0, z1 = l.rect.z1 } else l.rect
			markBad = markBad or (if found and same(rectOf(found), want) and found.kind == l.kind then nil else l.id)
		elseif l.kind == "orchard" then
			markBad = markBad or (if same(MAP.Orchard, l.rect) then nil else "the orchard")
		else
			markBad = markBad or (if found then `{l.id} is a later step's` else nil)
		end
	end
	check(`the plan's {marks} step-1 landmarks (the green, the chapel, the drugstore, the pond, the D5) and the orchard`, markBad == nil and marks == #MAP.Landmarks, markBad)
	local linesOk = #MAP.TreeLines == #Plan.lines
	for n, line in Plan.lines do
		local mine = MAP.TreeLines[n]
		linesOk = linesOk and mine ~= nil and mine.kind == line.kind and #mine.points == #line.points
		for i, p in line.points do
			linesOk = linesOk and mine.points[i].x == p.x and mine.points[i].z == p.z
		end
	end
	check("the plan's tree lines", linesOk)
	-- the fields: inside the plan's, none over another, a plot, the farmstead's lot or a lawn
	local fieldBad: string? = nil
	if #MAP.Fields ~= #Plan.fields then
		fieldBad = "a field missing"
	end
	for n, f in MAP.Fields do
		local p = Plan.fields[n]
		local r = rectOf(f)
		if not p or f.kind ~= p.kind or r.x0 < p.rect.x0 or r.x1 > p.rect.x1 or r.z0 < p.rect.z0 or r.z1 > p.rect.z1 then
			fieldBad = `field {n} not the plan's`
		end
		for m, g in MAP.Fields do
			if m > n and overlaps(r, rectOf(g)) then
				fieldBad = `fields {n} and {m} over each other`
			end
		end
		for _, plot in MAP.Plots do
			fieldBad = fieldBad or (if overlaps(r, plot.rect) then `field {n} on plot {plot.id}` else nil)
		end
		for _, lawn in MAP.Lawns do
			fieldBad = fieldBad or (if overlaps(r, lawn) then `field {n} on a lawn` else nil)
		end
		fieldBad = fieldBad or (if overlaps(r, MAP.House.lot) then `field {n} on the farmstead's lot` else nil)
	end
	check("the fields: the plan's, cut apart where two met (no two ground tiles on one plane), off the plots, the farmstead's lot and the lawns", fieldBad == nil, fieldBad)
end

-- ── The streets: all joined to Depot Row; every curb on its street ─────────

do
	-- two streets join where their asphalt meets along at least a van's width (a T, or one going on from the other)
	local function joins(a: Rect, b: Rect): boolean
		local x = math.min(a.x1, b.x1) - math.max(a.x0, b.x0)
		local z = math.min(a.z1, b.z1) - math.max(a.z0, b.z0)
		return (x >= -EPS and z >= 20) or (z >= -EPS and x >= 20)
	end
	local reached: { [string]: boolean } = { ["Depot Row"] = true }
	local grew = true
	while grew do
		grew = false
		for _, a in MAP.Roads do
			if not reached[a.name] then
				for _, b in MAP.Roads do
					if reached[b.name] and joins(rectOf(a), rectOf(b)) then
						reached[a.name] = true
						grew = true
					end
				end
			end
		end
	end
	local alone: { string } = {}
	for _, r in MAP.Roads do
		if not reached[r.name] then
			table.insert(alone, r.name)
		end
	end
	check(`every street joined to Depot Row ({#MAP.Roads}: Hlavní on from it, the lanes off Hlavní, Mirešická to Pražská)`, #alone == 0, table.concat(alone, ", "))
	local main = MAP.Roads[1]
	check("the turnaround on Pražská's south end", TURN.z == main.z1 and TURN.r > (main.x1 - main.x0) / 2)

	-- the van at a curb (the Sprinter across the road, nose away from the door): its back and nose on the asphalt
	local half = SprinterLooks.Length / 2
	local function vanOn(curb: { x: number, z: number }, yaw: number): boolean
		local a = math.rad(yaw)
		local lx, lz = -math.sin(a), -math.cos(a) -- (the way its nose looks: the spot's yaw)
		return onAsphalt(curb.x + lx * half, curb.z + lz * half) and onAsphalt(curb.x - lx * half, curb.z - lz * half)
	end
	local curbBad: string? = nil
	for _, h in MAP.Village do
		local street = roadNamed(h.street)
		if not street then
			curbBad = `{h.id}: no street {h.street}`
		elseif not (h.curb.x >= street.x0 and h.curb.x <= street.x1 and h.curb.z >= street.z0 and h.curb.z <= street.z1) or not vanOn(h.curb, h.yaw) then
			curbBad = `{h.id}'s curb off {h.street}`
		end
	end
	local toEmpty = 0
	for _, h in Plan.houses do
		if h.enter then
			toEmpty += 1
			local street = roadNamed(h.street)
			if not street or not (h.curb.x >= street.x0 and h.curb.x <= street.x1 and h.curb.z >= street.z0 and h.curb.z <= street.z1) or not vanOn(h.curb, h.yaw) then
				curbBad = `{h.id}'s curb (a house to empty) off {h.street}`
			end
		end
	end
	check(`every curb on its street's asphalt, the van's back and nose on it: the village's {#MAP.Village} and the {toEmpty} new houses to empty`, curbBad == nil and toEmpty == 5, curbBad)
end

-- ── The layout ─────────────────────────────────────────────────────────────

local houses = VillageScenery.houses()
local marks = VillageScenery.landmarks()
local trees = VillageScenery.trees()
do
	local ids: { [string]: number } = {}
	for _, h in houses do
		for _, id in h.ids do
			ids[id] = (ids[id] or 0) + 1
		end
	end
	local once = true
	for _, h in MAP.Village do
		once = once and ids[h.id] == 1
	end
	check(`the village's {#MAP.Village} houses each built once ({#houses} bodies: the terraced ones in their groups)`, once)
	-- every door looks out onto its street: from just outside it, straight ahead, the street's asphalt within 20 studs
	local doorBad: string? = nil
	local doors = 0
	for _, h in houses do
		local street = roadNamed(h.street) :: SandboxMap.Road
		local spots = VillageLooks.doorSpots(VillageLooks.house(h.kind, h.box, h.yaw, h.seed, h.opts), h.box, h.yaw)
		if #spots ~= #h.ids then
			doorBad = `{h.id}: {#spots} doors for {#h.ids} houses`
		end
		for _, d in spots do
			doors += 1
			local a = math.rad(d.yaw)
			local lx, lz = -math.sin(a), -math.cos(a)
			local reaches = false
			for t = 0, 20, 0.5 do
				local x, z = d.x + lx * t, d.z + lz * t
				reaches = reaches or (x >= street.x0 and x <= street.x1 and z >= street.z0 and z <= street.z1)
			end
			if not reaches or d.yaw ~= h.yaw then
				doorBad = `{h.id}'s door (unit {d.unit or 1}) does not look onto {h.street}`
			end
		end
	end
	check(`every village house's door ({doors}) looks out onto its street, 20 studs at most`, doorBad == nil and doors == #MAP.Village, doorBad)

	-- the hook for the five new houses to empty (their exteriors are the moves' for now): with them, each built once and
	-- rich, the terraced one in its row's group (its richUnit), every one within its budget, its door onto its street
	local extra: { VillageLooks.PlanHouse } = {}
	for _, h in Plan.houses do
		if h.enter then
			table.insert(extra, { id = h.id, kind = h.kind, box = h.box, yaw = h.yaw, step = 1, enter = true, street = h.street })
		end
	end
	local withRich = VillageScenery.houses(extra)
	local seenIds: { [string]: number } = {}
	local hookBad: string? = nil
	for _, h in withRich do
		local rich = h.opts.rich == true
		for _, id in h.ids do
			seenIds[id] = (seenIds[id] or 0) + 1
		end
		local made = VillageLooks.house(h.kind, h.box, h.yaw, h.seed, h.opts)
		if #made > VillageLooks.budget(h.kind, #h.ids, rich) then
			hookBad = `{h.id}: {#made} parts over its budget`
		end
		for _, e in extra do
			if table.find(h.ids, e.id) and not rich then
				hookBad = `{e.id} not rich`
			end
		end
		if h.kind == "row" and h.opts.richUnit and h.ids[h.opts.richUnit :: number] == nil then
			hookBad = `{h.id}'s richUnit outside its group`
		end
	end
	for _, e in extra do
		hookBad = hookBad or (if seenIds[e.id] == 1 then nil else `{e.id} built {seenIds[e.id] or 0} times`)
	end
	check(`the hook for the {#extra} new houses to empty: built once each, rich, the terraced one in its row's group, within the budgets`, hookBad == nil and #extra == 5
		and #withRich > #houses and VillageScenery.houses() == houses, hookBad)

	-- the landmarks: each in its rect off every road; the barrier across Hornická at its west end
	local kinds: { [string]: number } = {}
	local markBad: string? = nil
	for _, m in marks do
		kinds[m.kind] = (kinds[m.kind] or 0) + 1
		if m.kind ~= "barrier" then
			for _, r in MAP.Roads do
				if overlaps(grow(m.box, RUN), rectOf(r)) then
					markBad = `{m.id} on {r.name}`
				end
			end
		end
	end
	local hornicka = roadNamed("Hornická") :: SandboxMap.Road
	local barrier: VillageScenery.Mark? = nil
	for _, m in marks do
		if m.kind == "barrier" then
			barrier = m
		end
	end
	check("the landmarks: the green, the chapel, the pond, the drugstore, the D5 and Hornická's barrier, none on a road or its shoulder", markBad == nil and kinds.green == 1 and kinds.chapel == 1
		and kinds.pond == 1 and kinds.shop == 1 and kinds.motorway == 1 and kinds.barrier == 1, markBad)
	check("the barrier across Hornická near the map's west edge, looking east to the village", barrier ~= nil and barrier.box.z0 == hornicka.z0 and barrier.box.z1 == hornicka.z1
		and barrier.box.x0 > B.x0 and barrier.box.x1 < B.x0 + 30 and barrier.yaw == 270)

	-- the trees: where the rules let them; the windbreak along Mirešická moved off its road (16 studs: too close)
	local treeBad: string? = nil
	local moved = 0
	for _, t in trees do
		local rule = VillageScenery.treeRule(t.x, t.z, t.radius)
		treeBad = treeBad or (if rule then `a tree at {math.floor(t.x)}, {math.floor(t.z)}: {rule}` else nil)
		for _, h in Plan.houses do
			if h.step <= 1 and SandboxScenery.rectDistance(h.box, t.x, t.z) < t.radius then
				treeBad = `a tree's crown over the house {h.id}`
			end
		end
		if t.from == "windbreak 1" and t.z > 340.5 then
			moved += 1
		end
	end
	local lineOne = 0
	for _, t in trees do
		lineOne += if t.from == "windbreak 1" then 1 else 0
	end
	check(`the trees ({#trees}): each where the rules let it (off the roads, plots, lots, van ways, houses, landmarks, the Auction House), no crown over a step-1 house of the plan's (the ones to empty too)`, treeBad == nil and #trees >= 150, treeBad)
	check(`the windbreak along Mirešická: {lineOne} trees, {moved} of them moved off the road (Config.VillageWorld.Trees.Nudge)`, lineOne >= 25 and moved > 0 and moved <= lineOne)
	-- the D5's lanes: two each way on the carriageways' tops, run past the Bounds onto the far D5
	local lanes = VillageScenery.lanes()
	local north, south = 0, 0
	local laneOk = #lanes == 4
	local farRoad: { number }? = nil
	for _, p in VillageScenery.far() do
		if p.name == "FarCarriageway" then
			local x0, x1, _, y1, z0, z1 = VillageLooks.box(p)
			farRoad = { x0, x1, y1, z1 - z0 }
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
local far = world:FindFirstChild("Far")
local ground = world:FindFirstChild("Ground")
do
	local budget = SandboxScenery.Budget
	check(`the map's part budget holds with the Auction House on ({#all} parts, at most {budget}; {budget - #all} left)`, #all <= budget and #all > 1500, #all)
	print(`INFO  the map: {#all} parts ({village and #village:GetDescendants() or 0} in Village with models and words)`)
	check("the village in workspace.Sandbox: Village, the Persistent Motorway and Far, the Ground and the Roads Persistent too", village ~= nil and motorway ~= nil
		and motorway.ModelStreamingMode == Enum.ModelStreamingMode.Persistent and far ~= nil and far.ModelStreamingMode == Enum.ModelStreamingMode.Persistent
		and ground ~= nil and ground.ModelStreamingMode == Enum.ModelStreamingMode.Persistent and world:FindFirstChild("Roads").ModelStreamingMode == Enum.ModelStreamingMode.Persistent)
	-- the chunks: every model under Village an Atomic Village_<chunk>, everything of it in its cell (by its middle)
	local chunkBad: string? = nil
	local chunks = 0
	for _, model in (if village then village:GetChildren() else {}) do
		chunks += 1
		if not (model:IsA("Model") and model.ModelStreamingMode == Enum.ModelStreamingMode.Atomic and string.sub(model.Name, 1, 8) == "Village_") then
			chunkBad = model.Name
		end
	end
	local houseModels, markModels = 0, 0
	for _, d in (if village then village:GetDescendants() else {}) do
		if d:IsA("Model") and d:GetAttribute("VillageHouse") then
			houseModels += 1
		elseif d:IsA("Model") and d:GetAttribute("VillageLandmark") then
			markModels += 1
		end
	end
	check(`the village's houses ({houseModels}), landmarks ({markModels}) and trees in {chunks} Atomic chunk models (Village_<chunk>)`, chunkBad == nil and chunks > 20
		and houseModels == #houses and markModels == #marks - 1, chunkBad)
	-- nothing of the village (but the barrier) on a road, its shoulder, the turnaround, a plot, the farmstead's lot
	-- and path, the vans' ways or a house to empty's box
	local keep: { { name: string, rect: Rect } } = {}
	for _, r in MAP.Roads do
		table.insert(keep, { name = r.name, rect = grow(rectOf(r), RUN) })
	end
	for _, plot in MAP.Plots do
		table.insert(keep, { name = `plot {plot.id}`, rect = plot.rect })
	end
	table.insert(keep, { name = "the farmstead's lot", rect = MAP.House.lot })
	table.insert(keep, { name = "the farmstead's path", rect = SandboxScenery.Path })
	for n, way in SandboxScenery.vanPaths() do
		table.insert(keep, { name = `van way {n}`, rect = way })
	end
	for _, h in Plan.houses do
		if h.enter then
			table.insert(keep, { name = `the house to empty {h.id}`, rect = h.box })
		end
	end
	table.insert(keep, { name = "the Auction House", rect = AuctionHouseLayout.site() })
	local barrier = village and village:FindFirstChild("Landmark_barrier", true)
	local onRoad: string? = nil
	local seen = 0
	for _, b in all do
		local p = b.part
		if village and p:IsDescendantOf(village) and not (barrier and p:IsDescendantOf(barrier)) then
			seen += 1
			for _, k in keep do
				if overlaps({ x0 = b.x0, x1 = b.x1, z0 = b.z0, z1 = b.z1 }, k.rect) then
					onRoad = `{p.Name} of {p.Parent.Name} on {k.name}`
				end
			end
			local cx, cz = math.clamp(TURN.x, b.x0, b.x1), math.clamp(TURN.z, b.z0, b.z1)
			if (cx - TURN.x) ^ 2 + (cz - TURN.z) ^ 2 < (TURN.r + RUN) ^ 2 then
				onRoad = `{p.Name} on the turnaround`
			end
		end
	end
	check(`no house, tree or landmark ({seen} parts) on a road or its shoulder, the turnaround, a plot, the farmstead's lot or path, a van's way, a house to empty or the Auction House (but Hornická's barrier)`, onRoad == nil and seen > 1000, onRoad)
	-- the D5 inside the Bounds at the east edge, the far view outside them
	local farBad: string? = nil
	for _, b in all do
		if far and b.part:IsDescendantOf(far) and b.y1 > MAP.GroundTop + EPS and b.x0 < B.x1 and b.x1 > B.x0 and b.z0 < B.z1 and b.z1 > B.z0 then
			farBad = b.part.Name
		elseif motorway and b.part:IsDescendantOf(motorway) and (b.x0 < B.x0 or b.x1 > B.x1 or b.z0 < B.z0 - EPS or b.z1 > B.z1 + EPS or b.x0 < 300) then
			farBad = `the D5's {b.part.Name}`
		end
	end
	check("the D5 at the map's east edge inside the Bounds, the far view outside them", farBad == nil and motorway ~= nil and #motorway:GetChildren() == 1, farBad)
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
	check("the words: CORNER DRUGSTORE, ROAD CLOSED, the green's MOVING CONTRACTS noticeboard (decoration: VillageContracts)", texts["CORNER DRUGSTORE"] == 1 and texts["ROAD CLOSED"] == 1
		and texts["MOVING CONTRACTS"] == 1 and contracts == 1)
	-- the ground: the fields (each a tile and its rows) and the lawns in the Ground, flush with the meadow
	local fields, lawns, high = 0, 0, nil :: string?
	for _, b in all do
		if ground and b.part:IsDescendantOf(ground) then
			fields += if b.part.Name == "Field" then 1 else 0
			lawns += if b.part.Name == "VillageLawn" then 1 else 0
			if (b.part.Name == "Field" or b.part.Name == "VillageLawn" or b.part.Name == "Meadow") and math.abs(b.y1 - MAP.GroundTop) > EPS then
				high = b.part.Name
			end
		end
	end
	check(`the ground: {fields} field tiles and {lawns} lawn in the Ground, their tops the meadow's`, fields == #MAP.Fields and lawns == #MAP.Lawns and high == nil, high)
end

-- nothing alpine left: no spruce's needles, no mound, hill, peak or snow, no wildflowers or rail fence round the edge,
-- no THE OLD CHALET
do
	local ALPINE = { Needles = true, Mound = true, Hill = true, Peak = true, PeakSnow = true, Flower = true, FarMeadow = true, Spruce = true, Fir = true }
	local found: string? = nil
	for _, b in all do
		local p = b.part
		if ALPINE[p.Name] or p.Material == Enum.Material.Snow or p.Material == Enum.Material.Glacier then
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
		if d.ClassName == "TextLabel" and string.find(string.upper(d.Text), "CHALET", 1, true) then
			found = d.Text
		end
	end
	check("nothing alpine in the sandbox's world: no spruce, mound, hill, peak, snow, wildflowers, rail fence or chalet sign", found == nil, found)
end

Config.Auction.On = false

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
