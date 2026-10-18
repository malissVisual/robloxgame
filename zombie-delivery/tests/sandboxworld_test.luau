-- 8.0 SANDBOX, the map (design/sandbox/KONTRAKT.md): shared/SandboxScenery.luau's numbers and the world the real
-- server/SandboxWorld.luau builds from them (as SandboxWorldServer.luau on tools/perf/world-mock.luau, WorldMock.luau):
-- everything we play on inside SandboxMap.Bounds (the far view outside them), the asphalt over every road and the
-- turnaround with a shoulder down to the meadow on every edge (no step a wheel would catch; 9.4 every country lane
-- and its yard, none across a junction), nothing that collides on the roads, the
-- turnaround, the plots (but their pads), the path from the curb to the house's door or in the door's way, the trees off
-- all of that and off the vans' ways, the part budget, the shadows only on bigger parts, the chalet in its box with
-- its FrontDoor at House.door, the signpost's and the mailbox's words, the light; 8.9 the Alps gone (flat ground, no
-- mound, spruce, wildflower, rail fence, hill or peak: tests/villageworld_test.luau checks the countryside itself);
-- 8.1: the house's box the owner's Blender house's, its parts in House_sandbox_house for server/HouseMesh.luau, the
-- FrontDoor on the model's door; 8.3 the big move and walk-in doors: the back door, the doors' leaves door leaves that
-- swing (shared/DoorSwing.luau's attributes; dressed, the Blender house's doors copied as leaves in front of them);
-- 8.5 walking through: the leaves swing out of the house, the doorways walkable (the House box not solid, HouseSolid
-- the box less a dark hall behind each doorway, nothing solid in a hall or its way out, the walls round it solid);
-- 8.0.1: a van finds room on the first try at every vanSpot and at the house's curb (server/Vehicles.luau findRoom's
-- box query, Config.SpawnSpot.Pass leaving out the ground), and not where a player stands. 9.4 the countryside: the
-- five other places to empty in their looks (SandboxWorld.villageHouse), each walked in as the farmstead is (its
-- FrontDoor on its door, two leaves, the walls less a dark hall), nothing in its door's way or its walk to its curb
-- (9.5: its eaves 8 up at least; the cabin's veranda deck walked up as a doorstep, its roof overhead no obstacle).
-- 9.7 runs (design/lobby/plan.py): no Pražská, Depot Row, lanes, turnaround, markings, street lamps or signpost; the
-- asphalt is the places' yards (a shoulder round each); no far view; the trucks find room at every house's curb; the
-- lobby itself: tests/lobby_test.luau. 10.8 the floating islands (design/islands/plan.py; tests/islands_test.luau holds
-- the plan): every island's grass its ground (its tiles round what has its own ground, each at its island's top), its
-- rock under it; every place, its yard, its shoulders, its walls and its house at its island's height; every map
-- island walled on its run zone's edge (its ZoneWalls, from its top up) with a low rim hedge (decoration) on the same
-- line; no walls on the Bounds (the sky round the islands); workspace.FallenPartsDestroyHeight Config.Islands.Destroy.
-- Run with tests/run_tests.py.
local Mock = require("./WorldMock")
local G = Mock.globals
local Enum = G.Enum
local workspace, game = Mock.workspace, Mock.game
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local VillageScenery = require("./VillageScenery")
local SandboxWorld = require("./SandboxWorldServer")
local HouseMesh = require("./HouseMeshServer")
local HouseArt = require("./HouseArt")
local SpawnSpot = require("./SpawnSpot")
local SprinterLooks = require("./SprinterLooks")
local WarehouseLayout = require("./WarehouseLayout")
local VillageLooks = require("./VillageLooks")

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
local B = SandboxMap.Bounds
local TOP, GROUND = SandboxMap.RoadTop, SandboxMap.GroundTop
local HOUSE = SandboxMap.House
local RUN = SandboxScenery.Run
local EPS = 1e-3

local function grow(r: Rect, by: number): Rect
	return { x0 = r.x0 - by, x1 = r.x1 + by, z0 = r.z0 - by, z1 = r.z1 + by }
end
local function inRect(r: Rect, x: number, z: number): boolean
	return x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1
end
local SLABS = SandboxScenery.asphalt()
local function onAsphalt(x: number, z: number): boolean
	for _, road in SandboxMap.Roads do
		if inRect(road :: any, x, z) then
			return true
		end
	end
	return false
end

-- ── The numbers ────────────────────────────────────────────────────────────

do
	-- 10.8 every island's grass: its tiles fill its top but the holes on it, none over another or a hole, each at its
	-- island's top
	local tiles = SandboxScenery.tops()
	local holes = SandboxScenery.holes()
	local overlap: string? = nil
	local areas: { [string]: number } = {}
	for i, t in ipairs(tiles) do
		local r = t.rect
		local island = SandboxMap.island(t.island)
		areas[t.island] = (areas[t.island] or 0) + (r.x1 - r.x0) * (r.z1 - r.z0)
		if not island or r.x0 < island.rect.x0 - EPS or r.x1 > island.rect.x1 + EPS or r.z0 < island.rect.z0 - EPS or r.z1 > island.rect.z1 + EPS
			or t.top ~= island.top or r.x1 - r.x0 > 2048 or r.z1 - r.z0 > 2048 then
			overlap = `tile {i} off its island or too big`
		end
		for j, u in ipairs(tiles) do
			local q = u.rect
			if j > i and r.x0 < q.x1 - EPS and q.x0 < r.x1 - EPS and r.z0 < q.z1 - EPS and q.z0 < r.z1 - EPS then
				overlap = `tiles {i} and {j}`
			end
		end
		for _, h in holes do
			if r.x0 < h.x1 - EPS and h.x0 < r.x1 - EPS and r.z0 < h.z1 - EPS and h.z0 < r.z1 - EPS then
				overlap = `tile {i} over a hole`
			end
		end
	end
	local covered = true
	for _, island in SandboxMap.Islands do
		local r = island.rect
		local holeArea = 0
		for _, h in holes do
			local w = math.min(h.x1, r.x1) - math.max(h.x0, r.x0)
			local d = math.min(h.z1, r.z1) - math.max(h.z0, r.z0)
			if w > 0 and d > 0 then
				holeArea += w * d
			end
		end
		covered = covered and math.abs((areas[island.id] or 0) + holeArea - (r.x1 - r.x0) * (r.z1 - r.z0)) < 1
	end
	check("10.8 every island's grass tiles cover its top but the pads, the plaza, the lawns, none overlapping, each at its island's top", overlap == nil and covered, overlap)

	-- 10.8: every island's top flat at its height (8.9: no mound); off the islands the lobby's level (nothing stands there)
	local flat = true
	for _, island in SandboxMap.Islands do
		local r = island.rect
		for x = r.x0 + 1, r.x1 - 1, 20 do
			for z = r.z0 + 1, r.z1 - 1, 20 do
				flat = flat and SandboxScenery.groundAt(x, z) == island.top
			end
		end
	end
	check("10.8: every island's top flat at its height (no mound)", flat and SandboxScenery.groundAt(B.x0 + 1, B.z0 + 1) == GROUND)

	-- the shoulders: wherever a wheel leaves the asphalt it rolls down a slope, never off a step
	local ramps = SandboxScenery.ramps()
	local function shoulder(x: number, z: number, base: number): number
		local best = base
		for _, r in ramps do
			local y = SandboxScenery.shoulderAt(r, x, z)
			if y and y > best then
				best = y
			end
		end
		return best
	end
	local samples, worst, at = 0, math.huge, ""
	local function edgePoint(x: number, z: number, out: number, top: number, sag: number?)
		if onAsphalt(x, z) then
			return
		end
		samples += 1
		local base = top - (TOP - GROUND) -- (10.8: its island's grass)
		local want = base + (top - base) * (1 - out / RUN) - (sag or 0)
		local margin = shoulder(x, z, base) - want
		if margin < worst then
			worst, at = margin, string.format("%.1f, %.1f (%.1f out)", x, z, out)
		end
	end
	for _, out in { 0.3, 1.5, 3 } do
		-- (9.7: every yard's slab, each side and corner)
		for _, r in SLABS do
			for x = r.x0, r.x1, 5 do
				edgePoint(x, r.z0 - out, out, r.top)
				edgePoint(x, r.z1 + out, out, r.top)
			end
			for z = r.z0, r.z1, 4 do
				edgePoint(r.x0 - out, z, out, r.top)
				edgePoint(r.x1 + out, z, out, r.top)
			end
			for _, c in { { r.x0, r.z0, -1, -1 }, { r.x0, r.z1, -1, 1 }, { r.x1, r.z0, 1, -1 }, { r.x1, r.z1, 1, 1 } } do
				for _, a in { 0.2, 0.5, 0.8 } do
					local dx, dz = math.cos(a * math.pi / 2), math.sin(a * math.pi / 2)
					edgePoint(c[1] + c[3] * dx * out, c[2] + c[4] * dz * out, out, r.top)
				end
			end
		end
	end
	check("a shoulder slopes from the asphalt down to the grass along every edge (no step; 10.8 at its island's height)", worst >= -0.01, string.format("%d points, worst %.3f at %s", samples, worst, at))
	local tall: string? = nil
	for _, r in ramps do
		local base = SandboxMap.groundAt(r.x, r.z)
		if r.y + r.sy / 2 > base + TOP - GROUND + EPS or r.y - r.sy / 2 < base - EPS or r.sz ~= RUN then
			tall = `a {r.kind} at {r.x}, {r.z}`
		end
	end
	check("no shoulder rises over the asphalt or sinks under the grass", tall == nil, tall)
	local slabsOk = true
	for _, r in SLABS do
		slabsOk = slabsOk and math.abs(r.top - SandboxMap.roadAt((r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2)) < EPS and SandboxMap.islandAt(r.x0, r.z0) ~= nil
			and SandboxMap.islandAt(r.x0, r.z0) == SandboxMap.islandAt(r.x1, r.z1)
	end
	check("10.8 every yard's asphalt on one island, at its road level (its top RoadTop - GroundTop over the island's)", slabsOk)

	-- 8.9 the trees: the countryside's (shared/VillageScenery.luau), each where the rules let it stand, apart from each other
	local trees = VillageScenery.trees()
	local why: string? = nil
	for i, t in trees do
		local rule = VillageScenery.treeRule(t.x, t.z, t.radius)
		if rule then
			why = `tree {i}: {rule}`
		end
		for j = i + 1, #trees do
			local u = trees[j]
			if (t.x - u.x) ^ 2 + (t.z - u.z) ^ 2 < 9 ^ 2 then
				why = `trees {i} and {j} too close`
			end
		end
	end
	check(`8.9: {#trees} trees of the orchard and 9.4 the forest (10.8: on their islands), every one where the rules let it stand`, #trees >= 40 and why == nil, why or #trees)
	local again = VillageScenery.trees()
	check("the same trees every time", again == trees and #again == #trees)

	-- far away: 9.7 none (every run zone ends at its screen hedge, the lobby at its own)
	check("9.7: no far view (VillageScenery.far: nothing)", #VillageScenery.far() == 0)
end

-- ── The built world ────────────────────────────────────────────────────────

-- (8.1: what the build hands to HouseMesh.dress)
local dressed: { { model: any, id: string, result: boolean } } = {}
do
	local dress = HouseMesh.dress
	HouseMesh.dress = function(model: any, id: string): boolean
		local result = dress(model, id)
		table.insert(dressed, { model = model, id = id, result = result })
		return result
	end
end
local world = SandboxWorld.build()
check("SandboxWorld.build makes workspace.Sandbox", world ~= nil and world.Parent == workspace and workspace:FindFirstChild("Sandbox") == world)
check("a second build returns it as it is", SandboxWorld.build() == world)

-- (cap: a buried ball's round cap, its radius at the ground; its box is the square round it)
type Box = { part: any, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, far: boolean, cap: number? }
local far = world:FindFirstChild("Far")
-- (10.8: the clouds under the islands reach past the Bounds: decoration seen from afar, as the far view was)
local islandsModel = world:FindFirstChild("Islands")
local cloudsFolder = islandsModel and islandsModel:FindFirstChild("Clouds")
local boxes: { Box } = {}
local byName: { [string]: { Box } } = {} -- (the other places to empty's parts are in standBoxes, by their id)
local standBoxes: { [string]: { Box } } = {}
local unanchored = 0
-- (the house to empty a part is of, when it is a family house's: its nearest model with SandboxHouse, not the farmstead)
local function standInOf(d: any): string?
	local at = d.Parent
	while at and at ~= world do
		local id = at:GetAttribute("SandboxHouse")
		if id ~= nil then
			return if id ~= HOUSE.id then id else nil
		end
		at = at.Parent
	end
	return nil
end
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") then
		local size = d.Size
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
		local hx = (math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z) / 2
		local hy = (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2
		local hz = (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
		local y0, y1 = y - hy, y + hy
		local cap: number? = nil
		if d.Shape == Enum.PartType.Ball and y < GROUND then
			-- a buried ball (a mound, a hill): what shows is its cap
			local r = size.X / 2
			cap = math.sqrt(math.max(0, r * r - (GROUND - y) ^ 2))
			hx, hz, y0 = cap :: number, cap :: number, GROUND
		end
		local box: Box = { part = d, name = d.Name, x0 = x - hx, x1 = x + hx, y0 = y0, y1 = y1, z0 = z - hz, z1 = z + hz,
			far = (far ~= nil and d:IsDescendantOf(far)) or (cloudsFolder ~= nil and d:IsDescendantOf(cloudsFolder)), cap = cap }
		table.insert(boxes, box)
		local standIn = standInOf(d)
		if standIn then
			standBoxes[standIn] = standBoxes[standIn] or {}
			table.insert(standBoxes[standIn], box)
		else
			byName[d.Name] = byName[d.Name] or {}
			table.insert(byName[d.Name], box)
		end
		if not d.Anchored then
			unanchored += 1
		end
	end
end
local function named(name: string): { Box }
	return byName[name] or {}
end
-- (8.9: the countryside has its own House, Trunk … : a name in one model or folder)
local function namedIn(name: string, root: any): { Box }
	local out: { Box } = {}
	for _, b in named(name) do
		if root and b.part:IsDescendantOf(root) then
			table.insert(out, b)
		end
	end
	return out
end
local roadsFolder = world:FindFirstChild("Roads")
local barrier = world:FindFirstChild("Landmark_barrier", true)
check(`the part budget holds ({#boxes} parts, at most {SandboxScenery.Budget})`, #boxes <= SandboxScenery.Budget and #boxes > 300, #boxes)
check("every part is anchored", unanchored == 0, unanchored)

-- everything we play on inside the Bounds; far away outside them
do
	local out: string? = nil
	local farIn: string? = nil
	for _, b in boxes do
		if b.far then
			local cap = b.cap
			if cap then
				if SandboxScenery.outside((b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2) < cap then
					farIn = `{b.name}'s foot at {math.floor(b.x0)}, {math.floor(b.z0)}`
				end
			elseif b.y1 > GROUND + EPS and b.x0 < B.x1 - EPS and b.x1 > B.x0 + EPS and b.z0 < B.z1 - EPS and b.z1 > B.z0 + EPS then
				farIn = `{b.name} at {math.floor(b.x0)}, {math.floor(b.z0)}`
			end
		elseif b.x0 < B.x0 - EPS or b.x1 > B.x1 + EPS or b.z0 < B.z0 - EPS or b.z1 > B.z1 + EPS then
			out = `{b.name} at {math.floor(b.x0)} … {math.floor(b.x1)}, {math.floor(b.z0)} … {math.floor(b.z1)}`
		end
	end
	check("everything is inside SandboxMap.Bounds (but the clouds under it all)", out == nil and farIn == nil, out or farIn)
	check("9.7: no far view (no Far model, no far field, no peak, no hill), no D5, no railway", far == nil and #named("FarField") == 0 and #named("Peak") == 0 and #named("Hill") == 0
		and world:FindFirstChild("Motorway") == nil and world:FindFirstChild("Railway") == nil)
	-- 10.8: no walls on the Bounds (the sky round the islands; nobody gets there); FallenPartsDestroyHeight far under
	-- every island
	local lowest = math.huge
	for _, island in SandboxMap.Islands do
		lowest = math.min(lowest, island.top - island.depth)
	end
	check("10.8: no invisible walls on the Bounds; workspace.FallenPartsDestroyHeight Config.Islands.Destroy, under every island", #named("InvisibleWall") == 0
		and workspace.FallenPartsDestroyHeight == Config.Islands.Destroy and Config.Islands.Destroy < lowest - 100, workspace.FallenPartsDestroyHeight)
	-- 9.7 runs: every run zone walled on its edge (four ZoneWalls, unseen, solid, Config.Runs.Zone.Wall high; 10.8 from
	-- its island's top up) and its low rim hedge on the same line (CountryLooks' Hedge: decoration, the walls stop you)
	local zoneWalls, zoneOk, why = named("ZoneWall"), true, nil :: string?
	local hedges = named("Hedge")
	for _, zone in SandboxMap.Zones do
		local q = zone.rect
		local base = SandboxMap.groundAt((q.x0 + q.x1) / 2, (q.z0 + q.z1) / 2)
		local mine, rimmed = 0, 0
		for _, w in zoneWalls do
			if w.part:GetAttribute("RunZone") == zone.id then
				mine += 1
				local onEdge = math.abs(w.x1 - q.x0) < 0.01 or math.abs(w.x0 - q.x1) < 0.01 or math.abs(w.z1 - q.z0) < 0.01 or math.abs(w.z0 - q.z1) < 0.01
				zoneOk = zoneOk and onEdge and w.part.Transparency >= 1 and w.part.CanCollide and math.abs(w.y0 - base) < EPS and w.y1 >= base + Config.Runs.Zone.Wall - EPS
			end
		end
		for _, hb in hedges do
			local cx, cz = (hb.x0 + hb.x1) / 2, (hb.z0 + hb.z1) / 2
			local onEdge = (math.abs(cx - q.x0) < 0.01 or math.abs(cx - q.x1) < 0.01) and cz > q.z0 and cz < q.z1
				or (math.abs(cz - q.z0) < 0.01 or math.abs(cz - q.z1) < 0.01) and cx > q.x0 and cx < q.x1
			if onEdge then
				rimmed += 1
				zoneOk = zoneOk and not hb.part.CanCollide and math.abs(hb.y0 - base) < 0.05 and hb.y1 < base + 5
			end
		end
		if mine ~= 4 or rimmed < 4 then
			zoneOk, why = false, `{zone.id}: {mine} walls, {rimmed} rim hedges`
		end
	end
	check("9.7, 10.8: every map island walled on its run zone's edge (4 ZoneWalls, unseen, solid, high, from its top up) with a low rim hedge (not solid) on it", zoneOk and #zoneWalls == 4 * #SandboxMap.Zones, why)
	check("10.8: no tall screen hedges (9.7's), no meadow under everything", #named("ScreenHedge") == 0 and #named("Meadow") == 0)
end

-- the asphalt covers SandboxMap.Roads, its top at its island's road level (RoadTop on the lobby's)
do
	local asphalt = {}
	for _, b in named("Road") do
		table.insert(asphalt, b)
	end
	local function covered(x: number, z: number, list: { Box }, top: number, tolerance: number): boolean
		for _, b in list do
			if x >= b.x0 - EPS and x <= b.x1 + EPS and z >= b.z0 - EPS and z <= b.z1 + EPS and math.abs(b.y1 - top) <= tolerance then
				return true
			end
		end
		return false
	end
	local missed: string? = nil
	for _, road in SandboxMap.Roads do
		for x = road.x0, road.x1, 2 do
			for z = road.z0, road.z1, 2 do
				if not covered(x, z, asphalt, SandboxMap.roadAt(x, z), EPS) then
					missed = `{road.name} at {x}, {z}`
				end
			end
		end
	end
	check(`the asphalt covers every road of SandboxMap.Roads at its road level ({#asphalt} slabs: 9.7 the places' yards)`, missed == nil and #asphalt == #SLABS and #SLABS == #SandboxMap.Roads and #SLABS == #SandboxMap.Houses, missed)
	local labelled = true
	for _, road in SandboxMap.Roads do
		local found = false
		for _, b in asphalt do
			found = found or b.part:GetAttribute("Road") == road.name
		end
		labelled = labelled and found
	end
	check("…each slab says its road (the attribute Road: Mill Lane, Pond Lane …)", labelled)
	check("9.7: no turnaround", #named("Turnaround") == 0)
	check("a shoulder part for every piece of SandboxScenery.ramps", #named("Shoulder") == #SandboxScenery.ramps())
	check("9.7: no markings (the yards have none)", #namedIn("CentreLine", roadsFolder) == 0 and #namedIn("EdgeLine", roadsFolder) == 0 and #namedIn("GiveWay", roadsFolder) == 0)
end

-- nothing that collides stands on the roads, the turnaround, the plots (their pads are the floor), the path from the
-- curb to the door or in the door's way; the floors themselves never rise over the asphalt's top
do
	local FLOOR = { Road = true, Shoulder = true, Pad = true, Meadow = true, Lawn = true, Field = true, VillageLawn = true, Plaza = true, Grass = true }
	local areas: { { name: string, rect: Rect, circle: boolean?, top: number? } } = {}
	for _, road in SandboxMap.Roads do
		table.insert(areas, { name = road.name, rect = road :: any })
	end
	for _, plot in SandboxMap.Plots do
		table.insert(areas, { name = `plot {plot.id}`, rect = plot.rect })
	end
	table.insert(areas, { name = "the path from the curb to the door", rect = { x0 = SandboxScenery.Path.x0, x1 = SandboxScenery.Path.x1, z0 = SandboxScenery.Path.z0, z1 = HOUSE.door.z - 0.01 } })
	local d = HOUSE.door
	table.insert(areas, { name = "the front door's way", rect = { x0 = d.x - 2.5, x1 = d.x + 2.5, z0 = d.z - 5, z1 = d.z - 0.01 } })
	-- every zone's arrival spot (somebody lands there); 10.4 the PLAY circle (a party gathers there; 9.7: the portals'
	-- pads): its own check below (a circle)
	local play = SandboxMap.Lobby.play
	for _, zone in SandboxMap.Zones do
		local a = zone.arrive
		table.insert(areas, { name = `{zone.id}'s arrival`, rect = { x0 = a.x - 6, x1 = a.x + 6, z0 = a.z - 6, z1 = a.z + 6 }, top = 8 })
	end
	-- (every other place to empty's door's way, 5 out of it, and its walk to its curb, under its eaves: up to 8
	-- high, a mover and whatever goes through a door 7.2 high)
	for index, h in SandboxMap.Houses do
		if index > 1 then
			local hd, c = h.door, h.curb
			local ox, oz = -math.sin(math.rad(hd.yaw)), -math.cos(math.rad(hd.yaw))
			local ax, az = hd.x + ox * 0.01, hd.z + oz * 0.01
			local bx, bz = hd.x + ox * 5, hd.z + oz * 5
			local wide = if ox ~= 0 then 0 else 2.5
			local deep = if oz ~= 0 then 0 else 2.5
			table.insert(areas, { name = `{h.name}'s door's way`, rect = { x0 = math.min(ax, bx) - wide, x1 = math.max(ax, bx) + wide, z0 = math.min(az, bz) - deep, z1 = math.max(az, bz) + deep }, top = 8 })
			table.insert(areas, { name = `{h.name}'s walk to its curb`, rect = { x0 = math.min(hd.x, c.x) - wide, x1 = math.max(hd.x, c.x) + wide, z0 = math.min(hd.z + oz * 0.01, c.z) - deep, z1 = math.max(hd.z + oz * 0.01, c.z) + deep }, top = 8 })
		end
	end
	local blocked: string? = nil
	local floorHigh: string? = nil
	for _, b in boxes do
		if b.far or not b.part.CanCollide or (barrier and b.part:IsDescendantOf(barrier)) or b.name == "InvisibleWall" then
			continue -- (the Bounds' wall ends the map; 8.9's barrier, none now)
		end
		local base = SandboxMap.groundAt((b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2) -- (10.8: its island's top)
		if FLOOR[b.name] then
			if b.y1 > base + TOP - GROUND + EPS then
				floorHigh = `{b.name} at {math.floor(b.x0)}, {math.floor(b.z0)}`
			end
			continue
		end
		if b.y1 <= base + 0.05 or b.y0 >= base + 14 or (b.name == "Step" and b.y1 <= base + 0.45) or (b.name == "Deck" and b.y1 <= base + 0.55) then
			continue -- (a place's doorstep, 0.4 high, walked up; 9.5 the cabin's veranda deck, its plinth's 0.5)
		end
		for _, a in areas do
			local r = a.rect
			if a.top and b.y0 >= base + a.top then
				continue
			end
			if b.x0 < r.x1 - EPS and b.x1 > r.x0 + EPS and b.z0 < r.z1 - EPS and b.z1 > r.z0 + EPS then
				blocked = `{b.name} on {a.name}`
			end
		end
	end
	check("nothing that collides on the yards, the plots, the path to the door, the doors' ways or the zones' arrival spots", blocked == nil and barrier == nil, blocked)
	local inPlay: string? = nil
	for _, b in boxes do
		if not b.far and b.part.CanCollide and b.y1 > GROUND + 0.05 and b.y0 < 14 then
			local dx = math.max(b.x0 - play.x, 0, play.x - b.x1)
			local dz = math.max(b.z0 - play.z, 0, play.z - b.z1)
			if dx * dx + dz * dz < play.r * play.r then
				inPlay = `{b.name} at {math.floor(b.x0)}, {math.floor(b.z0)}`
			end
		end
	end
	check("10.4 nothing that collides in the PLAY circle (its lit posts outside its ring): you walk in from every side", inPlay == nil, inPlay)
	check("no floor (asphalt, shoulder, pad, grass, lawn, field) rises over its island's road level", floorHigh == nil, floorHigh)
	local pads = named("Pad")
	local padOk = #pads == #SandboxMap.Plots
	for _, plot in SandboxMap.Plots do
		local found = false
		for _, p in pads do
			local r = plot.rect
			if p.part:GetAttribute("Plot") == plot.id and math.abs(p.x0 - r.x0) < EPS and math.abs(p.x1 - r.x1) < EPS and math.abs(p.z0 - r.z0) < EPS and math.abs(p.z1 - r.z1) < EPS and math.abs(p.y1 - GROUND) < EPS then
				found = true
			end
		end
		padOk = padOk and found
	end
	check("a concrete pad on every plot's rect, flush with the lobby's grass", padOk)
end

-- the trees keep off the roads (and their shoulders), the turnaround, the plots, the house's lot, the path and the vans'
-- ways
do
	local trunks = named("Trunk")
	local keep: { { name: string, rect: Rect, circle: boolean? } } = {}
	for _, road in SandboxMap.Roads do
		table.insert(keep, { name = road.name, rect = grow(road :: any, RUN) })
	end
	for _, plot in SandboxMap.Plots do
		table.insert(keep, { name = `plot {plot.id}`, rect = plot.rect })
	end
	table.insert(keep, { name = "the house's lot", rect = HOUSE.lot })
	table.insert(keep, { name = "the path", rect = SandboxScenery.Path })
	for n, way in SandboxScenery.vanPaths() do
		table.insert(keep, { name = `van way {n}`, rect = way })
	end
	local hit: string? = nil
	for _, name in { "Trunk", "Crown" } do
		for _, b in named(name) do
			for _, k in keep do
				local r = k.rect
				if b.x0 < r.x1 and b.x1 > r.x0 and b.z0 < r.z1 and b.z1 > r.z0 then
					hit = `a tree's {name} on {k.name} at {math.floor(b.x0)}, {math.floor(b.z0)}`
				end
			end
		end
	end
	local own = 0 -- (the green's lindens, the pond's willows: the landmarks' own)
	for _, m in VillageScenery.landmarks() do
		for _, p in VillageScenery.pieces(m) do
			own += if p.name == "Trunk" then 1 else 0
		end
	end
	local lobbyTrees = 0 -- (9.7: the lobby's own, server/LobbyWorld.luau's)
	for _, b in trunks do
		lobbyTrees += if SandboxMap.inLobby(b.x0, b.z0) then 1 else 0
	end
	check(`the trees ({#trunks}) keep off the yards, the plots, the house's lot, the path and the trucks' spots`, hit == nil and #trunks == #VillageScenery.trees() + own + lobbyTrees
		and lobbyTrees == #SandboxMap.Lobby.trees and #named("Crown") == #trunks and #named("Needles") == 0, hit or `{#trunks} trunks, {lobbyTrees} in the lobby`)
	local solid = true
	for _, b in trunks do
		solid = solid and b.part.CanCollide
	end
	for _, b in named("Crown") do
		solid = solid and not b.part.CanCollide
	end
	check("a trunk collides, its crown does not", solid)
end

-- the chalet: in House.house's box, facing north, its FrontDoor at House.door. 8.1: its parts in the Model
-- "House_sandbox_house" (attribute Home) that server/HouseMesh.luau dresses, on the owner's Blender house's box (HouseMesh
-- dresses only a house of that size; HouseArt: design/blender-house's manifest, tests/run_tests.py), the FrontDoor on the
-- model's front door; no import here, so the chalet as it is (tools/house-art/check.py dresses it). 8.3 the big move:
-- its doors' leaves and its back door (House.back) on the model's back door.
do
	local chalet = world:FindFirstChild("TheOldFarmstead")
	check("the chalet is a model with its house's id", chalet ~= nil and chalet:IsA("Model") and chalet:GetAttribute("SandboxHouse") == HOUSE.id)
	local own = chalet and chalet:FindFirstChild("House_" .. HOUSE.id)
	local h = HOUSE.house
	local body = namedIn("House", chalet)[1]
	local doors = named("FrontDoor")
	local door = doors[1]
	check("its parts in a Model House_sandbox_house (Home = its id) as World's Marge's house, the garden beside it",
		own ~= nil and own:IsA("Model") and own:GetAttribute("Home") == HOUSE.id and body ~= nil and body.part.Parent == own
			and door ~= nil and door.part.Parent == own and chalet:FindFirstChild("Garden") ~= nil and own:FindFirstChild("Garden") == nil)
	check("its body fills House.house's footprint", body ~= nil and math.abs(body.x0 - (h.x - h.sx / 2)) < EPS and math.abs(body.x1 - (h.x + h.sx / 2)) < EPS and math.abs(body.z0 - (h.z - h.sz / 2)) < EPS and math.abs(body.z1 - (h.z + h.sz / 2)) < EPS and math.abs(body.y0 - h.y) < EPS)
	local box = HouseArt.box
	local size = body and body.part.Size
	check(`the house's box is the Blender house's ({box[1]} × {box[2]} × {box[3]}: HouseMesh dresses only that size)`,
		math.abs(h.sx - box[1]) < 1e-4 and math.abs(h.sy - box[2]) < 1e-4 and math.abs(h.sz - box[3]) < 1e-4 and size ~= nil
			and math.abs(size.X - box[1]) < 1e-4 and math.abs(size.Y - box[2]) < 1e-4 and math.abs(size.Z - box[3]) < 1e-4,
		size and tostring(size))
	local front = h.z - h.sz / 2
	check("its front wall where the door, the path and the curb are (House.door on it)", math.abs(front - HOUSE.door.z) < EPS and math.abs(h.x - HOUSE.door.x) < EPS and HOUSE.door.yaw == 0)
	local call = dressed[1]
	check("SandboxWorld hands that model to HouseMesh.dress, which lists the house (no import here: the chalet stays)",
		HouseMesh.Homes[HOUSE.id] == true and #dressed == 1 and call.model == own and call.id == HOUSE.id and call.result == false
			and own ~= nil and own:GetAttribute("MeshArt") == nil and body ~= nil and body.part.Transparency == 0, #dressed)
	local top, outside = -math.huge, nil :: string?
	for _, b in boxes do
		if chalet and b.part:IsDescendantOf(chalet) then
			top = math.max(top, b.y1)
			if b.x0 < HOUSE.lot.x0 - EPS or b.x1 > HOUSE.lot.x1 + EPS or b.z0 < HOUSE.lot.z0 - EPS or b.z1 > HOUSE.lot.z1 + EPS then
				outside = b.name
			end
		end
	end
	check(`the chalet's roof over its box, its top ({string.format("%.1f", top)}) under the Blender house's ({string.format("%.1f", HouseArt.top)})`, top > h.y + h.sy + 5 and top <= h.y + HouseArt.top + 0.05)
	check("all of the chalet and its garden on the house's lot", outside == nil, outside)
	local d = HOUSE.door
	local okDoor = #doors == 1
		and door.part:GetAttribute("SandboxDoor") == true
		and not door.part.CanCollide
		and math.abs((door.x0 + door.x1) / 2 - d.x) < 0.1
		and math.abs(door.z0 - d.z) < 0.5
		and math.abs(door.y0 - d.y) < 0.1
		and door.part:IsDescendantOf(chalet)
	check("one FrontDoor (SandboxDoor = true, no collision) at House.door", okDoor, door and string.format("%.2f, %.2f, %.2f", (door.x0 + door.x1) / 2, door.y0, door.z0))
	check("the door is on the north wall, facing the road", door ~= nil and body ~= nil and door.z1 <= body.z0 + EPS)
	-- the Blender house's door leaves in the world (the house's frame: its bottom's middle, -Z to the road)
	local frame = G.CFrame.new(h.x, h.y, h.z) * G.CFrame.Angles(0, math.rad(d.yaw), 0)
	local a = HouseArt.door
	local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	for _, x in { a.x0, a.x1 } do
		for _, y in { a.y0, a.y1 } do
			for _, z in { a.z0, a.z1 } do
				local p = frame * G.Vector3.new(x, y, z)
				lo = { math.min(lo[1], p.X), math.min(lo[2], p.Y), math.min(lo[3], p.Z) }
				hi = { math.max(hi[1], p.X), math.max(hi[2], p.Y), math.max(hi[3], p.Z) }
			end
		end
	end
	local onLeaves = door ~= nil
		and math.abs((door.x0 + door.x1) / 2 - (lo[1] + hi[1]) / 2) < 0.1
		and math.abs((door.x1 - door.x0) - (hi[1] - lo[1])) < 0.25
		and math.abs(door.y0 - lo[2]) < 0.25
		and math.abs(door.y1 - hi[2]) < 0.25
		and door.z1 <= lo[3] + EPS
		and lo[3] - door.z1 < 0.5
	check("the FrontDoor on the Blender house's door: across it, as wide and tall, just in front of its leaves", onLeaves,
		door and string.format("FrontDoor %.2f … %.2f, %.2f … %.2f, %.2f … %.2f; leaves %.2f … %.2f, %.2f … %.2f, %.2f … %.2f",
			door.x0, door.x1, door.y0, door.y1, door.z0, door.z1, lo[1], hi[1], lo[2], hi[2], lo[3], hi[3]))
	-- 8.3 walk-in doors: the Blender house's front door is part of its model (it cannot move): dressed, two leaves made
	-- like it (SandboxScenery.frontLeaves) stand just in front of it and swing (SandboxWorld.doorLeaves): together they
	-- cover its leaves, meet in its middle, their backs on the wall's face (its brass handles reach that), hinged at the
	-- opening's sides; every detail in front of its leaf
	local leaves = SandboxScenery.frontLeaves()
	local llo, lhi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	local leavesOk = #leaves == 2
	local edges: { number } = {}
	for _, leaf in leaves do
		local parts = leaf.parts
		local leafBody = parts[1]
		leavesOk = leavesOk and leafBody.name == "DoorLeaf" and math.abs(leaf.hinge) == 1 and leafBody.at[1] * leaf.hinge > 0 and #parts == 8
		for i = 1, 3 do
			local o = ({ d.x, d.y, d.z })[i]
			llo[i] = math.min(llo[i], o + leafBody.at[i] - leafBody.size[i] / 2)
			lhi[i] = math.max(lhi[i], o + leafBody.at[i] + leafBody.size[i] / 2)
		end
		table.insert(edges, leafBody.at[1] - leaf.hinge * leafBody.size[1] / 2) -- (its free end)
		for n = 2, #parts do
			local part = parts[n]
			leavesOk = leavesOk and part.at[3] + part.size[3] / 2 <= leafBody.at[3] - leafBody.size[3] / 2 + 0.03 + 1e-6
				and math.abs(part.at[1] - leafBody.at[1]) + part.size[1] / 2 <= leafBody.size[1] / 2 + 1e-6
		end
	end
	check("8.3 the Blender house's door copied as two leaves: they cover its leaves from the front, meet in its middle, hinged at its sides",
		leavesOk and llo[1] <= lo[1] + 1e-6 and lhi[1] >= hi[1] - 1e-6 and math.abs(llo[2] - lo[2]) < 0.02 and math.abs(lhi[2] - hi[2]) < 0.02
			and lhi[3] <= d.z + 1e-6 and lhi[3] <= lo[3] and math.abs(edges[1] - edges[2]) < 1e-6,
		string.format("leaves %.2f … %.2f, %.2f … %.2f, %.2f … %.2f", llo[1], lhi[1], llo[2], lhi[2], llo[3], lhi[3]))
	local made = if chalet then SandboxWorld.doorLeaves(chalet) else {}
	check("…the chalet (no import here): its own leaves are the door leaves (FrontLeafWest, FrontLeafEast, BackLeaf)", #made == 3
		and made[1].Name == "FrontLeafWest" and made[2].Name == "FrontLeafEast" and made[3].Name == "BackLeaf" and door.part:GetAttribute("DoorLeaf") == nil)
	-- a house dressed in the model (as the owner's import does): the three leaves in it (the front door's two, the back
	-- door's one), the FrontDoor only the prompt's, the chalet's own leaves (hidden with it) no door leaves
	local dressedHouse = G.Instance.new("Model")
	local dressedBody = G.Instance.new("Model")
	dressedBody.Name = "House_" .. HOUSE.id
	dressedBody:SetAttribute("MeshArt", true)
	dressedBody.Parent = dressedHouse
	local prompt = G.Instance.new("Part")
	prompt.Name = "FrontDoor"
	prompt.Parent = dressedBody
	local hidden = G.Instance.new("Part")
	hidden.Name = "BackLeaf"
	hidden.Parent = dressedBody
	local built = SandboxWorld.doorLeaves(dressedHouse)
	local backLeaves = SandboxScenery.backLeaves()
	local builtOk = #built == 3 and prompt:GetAttribute("DoorLeaf") == nil and hidden:GetAttribute("DoorLeaf") == nil
	for n, leaf in built do
		local primary = leaf.PrimaryPart
		local parts = 0
		local still = true
		for _, part in leaf:GetChildren() do
			parts += 1
			still = still and part.CanCollide == false and part.CanQuery == false and part.CanTouch == false
		end
		local want = if n <= 2 then leaves[n] else backLeaves[1]
		builtOk = builtOk and want ~= nil and leaf.ClassName == "Model" and leaf.Name == (if n <= 2 then "FrontDoorLeaf" else "BackDoorLeaf") and leaf.Parent == dressedHouse
			and leaf:GetAttribute("DoorLeaf") == want.hinge and leaf:GetAttribute("DoorSwing") == -1 and leaf:GetAttribute("DoorDark") == true
			and leaf:GetAttribute("DoorAngle") == Config.Moving.Doors.Wide -- (8.5.1: past square, never edge-on)
			and primary ~= nil and primary.Name == "DoorLeaf" and primary.Color == HouseMesh.Looks.door.color and parts == 8 and still
	end
	check("…dressed in the Blender house: two FrontDoorLeaf models and a BackDoorLeaf in it (DoorLeaf ±1, 8.5 DoorSwing -1: out of the house, 8.5.1 DoorAngle Wide, DoorDark; the model's finishes), never colliding; the chalet's own leaves none",
		builtOk, #built)
	-- 8.3 the big move: the FrontDoor unseen behind its two leaves; the back door at House.back on the Blender house's back
	-- door (BackDoor: SandboxBackDoor, unseen, no collision; across it, as wide and tall, just outside its leaf) with its
	-- leaf; each leaf shut in its doorway, hinged at a jamb (DoorLeaf, Hinge), not solid, seen; all the house's own parts
	local backs = named("BackDoor")
	local back = backs[1]
	local B = HouseArt.back
	local blo, bhi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	for _, x in { B.x0, B.x1 } do
		for _, y in { B.y0, B.y1 } do
			for _, z in { B.z0, B.z1 } do
				local p = frame * G.Vector3.new(x, y, z)
				blo = { math.min(blo[1], p.X), math.min(blo[2], p.Y), math.min(blo[3], p.Z) }
				bhi = { math.max(bhi[1], p.X), math.max(bhi[2], p.Y), math.max(bhi[3], p.Z) }
			end
		end
	end
	local hb = HOUSE.back
	check("8.3: one BackDoor (SandboxBackDoor = true, unseen, no collision) at House.back, on the back wall, the house's own", #backs == 1
		and back.part:GetAttribute("SandboxBackDoor") == true and not back.part.CanCollide and back.part.Transparency == 1 and back.part.Parent == own
		and math.abs((back.x0 + back.x1) / 2 - hb.x) < 0.1 and math.abs(back.z1 - hb.z) < 0.5 and back.z0 >= body.z1 - EPS and hb.yaw == 180,
		back and string.format("%.2f, %.2f, %.2f", (back.x0 + back.x1) / 2, back.y0, back.z0))
	check("8.3: …on the Blender house's back door: across it, as wide and tall, just outside its leaf", back ~= nil
		and math.abs((back.x0 + back.x1) / 2 - (blo[1] + bhi[1]) / 2) < 0.1 and math.abs((back.x1 - back.x0) - (bhi[1] - blo[1])) < 0.25
		and math.abs(back.y0 - blo[2]) < 0.3 and math.abs(back.y1 - bhi[2]) < 0.3 and back.z0 >= bhi[3] - EPS and back.z0 - bhi[3] < 0.5,
		back and string.format("BackDoor %.2f … %.2f, %.2f … %.2f, %.2f … %.2f; leaf %.2f … %.2f, %.2f … %.2f, %.2f … %.2f",
			back.x0, back.x1, back.y0, back.y1, back.z0, back.z1, blo[1], bhi[1], blo[2], bhi[2], blo[3], bhi[3]))
	-- (8.3 walk-in doors: door leaves of shared/DoorSwing.luau, each hinged at its jamb (DoorLeaf ±1 along its own X: the
	-- front door's frame's, the back door's turned round), 8.5 swinging out of the house (DoorSwing -1, was 1), a dark
	-- doorway behind)
	local leavesOk, count = true, 0
	for _, want in { { "FrontLeafWest", -1, "west", door }, { "FrontLeafEast", 1, "east", door }, { "BackLeaf", SandboxScenery.BackDoor.Hinge, "east", back } } do
		local list = named(want[1])
		local leaf, way = list[1], want[4]
		count += #list
		leavesOk = leavesOk and #list == 1 and way ~= nil and leaf.part:GetAttribute("DoorLeaf") == want[2] and leaf.part:GetAttribute("DoorSwing") == -1
			and leaf.part:GetAttribute("DoorAngle") == Config.Moving.Doors.Wide -- (8.5.1)
			and leaf.part:GetAttribute("DoorDark") == true and not leaf.part.CanCollide and leaf.part.Transparency == 0 and leaf.part.Parent == own
			and leaf.x0 >= way.x0 - 0.05 and leaf.x1 <= way.x1 + 0.05 and leaf.y0 >= way.y0 - 0.05 and leaf.y1 <= way.y1 + 0.05
			and (if want[3] == "west" then math.abs(leaf.x0 - way.x0) < 0.1 else math.abs(leaf.x1 - way.x1) < 0.1)
	end
	check("8.3: the doors' leaves shut in their doorways, door leaves hinged at a jamb (FrontLeafWest west, FrontLeafEast east, BackLeaf east: DoorLeaf -1 / 1 / -1, 8.5 DoorSwing -1, 8.5.1 DoorAngle Wide, DoorDark), the FrontDoor unseen behind them",
		leavesOk and count == 3 and door ~= nil and door.part.Transparency == 1)
	-- dressed, the back door's leaf copied (SandboxScenery.backLeaves) the same way in front of the Blender house's back
	-- door: it covers its leaf from outside, hung on the side away from its handle (house.py's: HouseArt.backKnob)
	local backCopy = backLeaves[1]
	local bframe = G.CFrame.new(hb.x, hb.y, hb.z) * G.CFrame.Angles(0, math.rad(hb.yaw), 0)
	local klo, khi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	local knobX, knobs = 0, 0
	local copyOk = #backLeaves == 1 and backCopy.hinge == SandboxScenery.BackDoor.Hinge and #backCopy.parts == 8
	for n, spec in (if backCopy then backCopy.parts else {}) do
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = bframe * G.Vector3.new(spec.at[1] + sx * spec.size[1] / 2, spec.at[2] + sy * spec.size[2] / 2, spec.at[3] + sz * spec.size[3] / 2)
					if n == 1 then
						klo = { math.min(klo[1], p.X), math.min(klo[2], p.Y), math.min(klo[3], p.Z) }
						khi = { math.max(khi[1], p.X), math.max(khi[2], p.Y), math.max(khi[3], p.Z) }
					end
				end
			end
		end
		if spec.finish == "brass" then
			knobX += (bframe * G.Vector3.new(spec.at[1], spec.at[2], spec.at[3])).X
			knobs += 1
		end
	end
	local modelKnob = (frame * G.Vector3.new(HouseArt.backKnob, 0, 0)).X
	check("8.3 …and the Blender house's back door copied as one leaf: it covers its leaf from outside, hung on the side away from its handle",
		copyOk and klo[1] <= blo[1] + 1e-6 and khi[1] >= bhi[1] - 1e-6 and math.abs(klo[2] - blo[2]) < 0.02 and math.abs(khi[2] - bhi[2]) < 0.02
			and klo[3] >= bhi[3] - 1e-6 and klo[3] - bhi[3] < 0.5 and knobs == 2 and math.abs(knobX / knobs - modelKnob) < 0.05,
		string.format("copy %.2f … %.2f, %.2f … %.2f, %.2f … %.2f; its handle %.2f, the model's %.2f", klo[1], khi[1], klo[2], khi[2], klo[3], khi[3], knobX / math.max(knobs, 1), modelKnob))
	local garden = chalet and chalet:FindFirstChild("Garden")
	local gardenSolid: string? = if garden then nil else "no garden"
	local gardenParts = 0
	for _, b in boxes do
		if garden and b.part:IsDescendantOf(garden) then
			gardenParts += 1
			if b.part.CanCollide then
				gardenSolid = b.name
			end
		end
	end
	check(`the garden (fence, gate, mailbox, flower boxes, path: {gardenParts} parts) never collides`, gardenSolid == nil and #namedIn("FlowerBox", garden) >= 3 and #namedIn("Mailbox", garden) == 1 and #namedIn("Path", garden) == 1, gardenSolid)
end

-- 8.5 walking through (the owner: "so it doesn't feel like I bumped into the door, but I keep walking smoothly"): the
-- doorways walkable. The House box (what stopped you at the door: solid under the Blender house) collides with nothing
-- and stops no ray; the house's HouseSolid pieces are the box less a hall behind each doorway (Config.Moving.Doors.Hall
-- Depth deep, the opening's width, the door's height): nothing that collides in a hall or in the door's way out in
-- front of it (the leaves, the doorways, the model's door, the dark lining included), the walls either side, over the
-- doorway and past the hall as solid as ever; each hall lined dark (DoorHalls: its back, sides, ceiling, floor),
-- decoration only.
do
	local D = Config.Moving.Doors
	local h = HOUSE.house
	local body = namedIn("House", world:FindFirstChild("TheOldFarmstead"))[1]
	local solids = named("HouseSolid")
	local volume, inBox = 0, true
	for _, b in solids do
		local s = b.part.Size
		volume += s.X * s.Y * s.Z
		inBox = inBox and b.x0 >= h.x - h.sx / 2 - EPS and b.x1 <= h.x + h.sx / 2 + EPS and b.z0 >= h.z - h.sz / 2 - EPS and b.z1 <= h.z + h.sz / 2 + EPS
			and b.y0 >= h.y - EPS and b.y1 <= h.y + h.sy + EPS and b.part.CanCollide and b.part.CanQuery and b.part.Transparency == 1
	end
	local top = named("FrontDoor")[1].part.Size.Y
	local depth = D.Hall.Depth
	local halls = {
		{ name = "the front door's hall", x = HOUSE.door.x, half = SandboxScenery.FrontDoor.Width / 2, z0 = HOUSE.door.z, z1 = HOUSE.door.z + depth, out = -1 },
		{ name = "the back door's hall", x = HOUSE.back.x, half = SandboxScenery.BackDoor.Width / 2, z0 = HOUSE.back.z - depth, z1 = HOUSE.back.z, out = 1 },
	}
	local hallVolume = 0
	for _, hall in halls do
		hallVolume += 2 * hall.half * top * depth
	end
	check(`8.5 the House box collides with nothing and stops no ray; {#solids} HouseSolid pieces, unseen, are the box less a hall behind each doorway`,
		body ~= nil and body.part.CanCollide == false and body.part.CanQuery == false and #solids == 7 and inBox
			and math.abs(volume - (h.sx * h.sy * h.sz - hallVolume)) < 0.01 and depth >= 10 and depth < h.sz / 2,
		`{volume} of {h.sx * h.sy * h.sz - hallVolume}`)
	-- what collides in a box x0 … x1, y0 … y1 (over the house's island's top: 10.8), z0 … z1 (the floors under y 0.05:
	-- the lawn the hall stands on)
	local g = h.y
	local function solidIn(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number): string?
		for _, b in boxes do
			if b.part.CanCollide and not b.far and b.x0 < x1 - EPS and b.x1 > x0 + EPS and b.y0 < g + y1 - EPS and b.y1 > g + y0 + EPS and b.z0 < z1 - EPS and b.z1 > z0 + EPS then
				return b.name
			end
		end
		return nil
	end
	local blocked: string? = nil
	local walls = true
	for _, hall in halls do
		local x0, x1 = hall.x - hall.half, hall.x + hall.half
		-- the hall and the door's way out in front of it (5 studs, a body's height)
		local inHall = solidIn(x0, x1, 0.05, top, hall.z0, hall.z1)
		local way = if hall.out < 0 then solidIn(x0, x1, 0.05, top, hall.z0 - 5, hall.z0) else solidIn(x0, x1, 0.05, top, hall.z1, hall.z1 + 5)
		blocked = blocked or (if inHall then `{inHall} in {hall.name}` elseif way then `{way} in front of {hall.name}` else nil)
		-- the walls either side of it, over the doorway and past the hall's end: solid
		local zMid = (hall.z0 + hall.z1) / 2
		local past = if hall.out < 0 then hall.z1 + 0.5 else hall.z0 - 0.5
		walls = walls and solidIn(x0 - 1, x0 - 0.5, 1, 6, zMid - 0.5, zMid + 0.5) ~= nil and solidIn(x1 + 0.5, x1 + 1, 1, 6, zMid - 0.5, zMid + 0.5) ~= nil
			and solidIn(x0 + 0.5, x1 - 0.5, top + 0.5, top + 1, zMid - 0.5, zMid + 0.5) ~= nil and solidIn(x0 + 0.5, x1 - 0.5, 1, 6, past - 0.25, past + 0.25) ~= nil
	end
	check("8.5 the doorways walkable: nothing that collides in either door's hall or its way out (leaves, doorway, the House box)", blocked == nil, blocked)
	check("8.5 …the house's walls either side of each hall, over its doorway and past its end still solid", walls)
	local lining = named("DoorHall")
	local holder = world:FindFirstChild("TheOldFarmstead"):FindFirstChild("DoorHalls")
	local liningOk = #lining == 10 and holder ~= nil
	for _, b in lining do
		local c = b.part.Color
		local inside = false
		for _, hall in halls do
			inside = inside or (b.x0 >= hall.x - hall.half - EPS and b.x1 <= hall.x + hall.half + EPS and b.z0 >= hall.z0 - EPS and b.z1 <= hall.z1 + EPS
				and b.y0 >= g - EPS and b.y1 <= g + top + EPS)
		end
		liningOk = liningOk and inside and b.part.Parent == holder and not b.part.CanCollide and not b.part.CanQuery and not b.part.CastShadow
			and b.part.Transparency == 0 and math.abs(c.R * 255 - D.Hall.Color[1]) < 1 and math.abs(c.G * 255 - D.Hall.Color[2]) < 1 and math.abs(c.B * 255 - D.Hall.Color[3]) < 1
	end
	check("8.5 …each hall lined dark (DoorHalls: its back, sides, ceiling and floor, in the hall, seen, never colliding)", liningOk, #lining)
end

-- 9.4 the countryside: the five other places to empty in their looks (SandboxWorld.villageHouse: VillageScenery.houses,
-- rich; 9.5 each its own look): each a model of its own
-- (SandboxHouse = its id, VillageHouse its Placed's) in its Atomic chunk (world.Village's Village_<chunk>), its pieces in
-- House_<id> (Home) inside its box (a row's: its group's; 9.5 but its look's overhangs, VillageLooks.Overhangs: the
-- cabin's veranda past its front edge, the mill's wheel past its right-hand side, each its reach at most and no more of
-- it), its walls (House, a row's Row) the PrimaryPart and no longer
-- solid, its FrontDoor (SandboxDoor, no collision, unseen; -Z out of the house as the farmstead's) the door's piece, its
-- outer face on its door (SandboxMap's: VillageLooks.doorSpots'), two leaves (door leaves, out of the house), no back
-- door; walkable as the farmstead's (4 HouseSolid pieces: the walls less the front door's hall; nothing colliding in the
-- hall or in the door's way but its doorstep, the cabin's its veranda's deck; the walls either side, over the doorway
-- and past the hall's end solid), the plinth no longer solid (9.5 the mill has none: its stone walls on the ground), the
-- hall lined dark (its floor over the plinth, the mill's over the ground), its name on its mailbox.
do
	local D = Config.Moving.Doors
	local placedOf: { [string]: VillageScenery.Placed } = {}
	for _, p in VillageScenery.houses() do
		local h = VillageScenery.emptied(p)
		if h then
			placedOf[h.id] = p
		end
	end
	local made, okAll, why = 0, true, nil :: string?
	local village = world:FindFirstChild("Village")
	for index, h in SandboxMap.Houses do
		if index == 1 then
			continue
		end
		local model: any = nil
		local models = 0
		for _, d in world:GetDescendants() do
			if d.ClassName == "Model" and d:GetAttribute("SandboxHouse") == h.id then
				model, models = d, models + 1
			end
		end
		local placed = placedOf[h.id]
		local list = standBoxes[h.id] or {}
		local function all(name: string): { Box }
			local found = {}
			for _, b in list do
				if b.name == name then
					table.insert(found, b)
				end
			end
			return found
		end
		local body = model and model:FindFirstChild("House_" .. h.id)
		local walls, doors, solids, lining = all(if h.look == "row" then "Row" else "House"), all("FrontDoor"), all("HouseSolid"), all("DoorHall")
		local west, east, plinths = all("FrontLeafWest"), all("FrontLeafEast"), all("Plinth")
		local wall, door = walls[1], doors[1]
		local chunk = model and model.Parent
		local box = if placed then placed.box else h.box
		local stage = "its model"
		local ok = models == 1 and placed ~= nil and chunk ~= nil and chunk.ClassName == "Model" and chunk.ModelStreamingMode == Enum.ModelStreamingMode.Atomic
			and string.sub(chunk.Name, 1, 8) == "Village_" and chunk.Parent == village and model:GetAttribute("VillageHouse") == placed.id
			and body ~= nil and body:GetAttribute("Home") == h.id and #walls == 1 and #doors == 1 and #west == 1 and #east == 1
			and #plinths == (if h.look == "mill" then 0 else 1) and #all("BackDoor") == 0 and #all("BackLeaf") == 0 and (h.look ~= "row" or #placed.ids > 1)
		if ok then
			stage = "its walls"
			ok = body.PrimaryPart == wall.part and model.PrimaryPart == wall.part and not wall.part.CanCollide and not wall.part.CanQuery
				and (#plinths == 0 or (not plinths[1].part.CanCollide and not plinths[1].part.CanQuery))
			-- (all of it in its box: a row's, its group's; 9.5 but its look's overhangs, each its reach at most past its side:
			-- the front, out of the door; the right-hand side seen from outside facing the door, the look's frame's +X)
			local over = VillageLooks.Overhangs[h.look]
			local turn = math.rad(VillageLooks.turnOf(h.yaw))
			local right = over ~= nil and over.side == "right"
			local sx = if right then math.cos(turn) else -math.sin(math.rad(h.yaw))
			local sz = if right then -math.sin(turn) else -math.cos(math.rad(h.yaw))
			local reached = 0
			for _, b in list do
				local r = if over and table.find(over.pieces, b.name) then over.reach else 0
				local x0, x1 = box.x0 - (if sx < -0.5 then r else 0), box.x1 + (if sx > 0.5 then r else 0)
				local z0, z1 = box.z0 - (if sz < -0.5 then r else 0), box.z1 + (if sz > 0.5 then r else 0)
				if b.x0 < x0 - 0.01 or b.x1 > x1 + 0.01 or b.z0 < z0 - 0.01 or b.z1 > z1 + 0.01 then
					ok, stage = false, `its {b.name} out of its box`
				end
				reached = math.max(reached, b.x1 - box.x1, box.x0 - b.x0, b.z1 - box.z1, box.z0 - b.z0)
			end
			if ok and over and reached <= 0.01 then
				ok, stage = false, "its overhang inside its box (none past its side)"
			end
		end
		local ox, oz = -math.sin(math.rad(h.door.yaw)), -math.cos(math.rad(h.door.yaw)) -- (out of the door)
		if ok then
			stage = "its door"
			local dx, dz = (door.x0 + door.x1) / 2, (door.z0 + door.z1) / 2
			local along = (dx - h.door.x) * ox + (dz - h.door.z) * oz
			local look = door.part.CFrame.LookVector
			ok = door.part:GetAttribute("SandboxDoor") == true and not door.part.CanCollide and door.part.Transparency == 1
				and math.abs((dx - h.door.x) * oz - (dz - h.door.z) * ox) < 0.1 -- (across: its middle on the door's)
				and along < 0 and along > -0.5 -- (its outer face on the door, just outside the front wall)
				and math.abs(door.y0 - h.door.y) < 0.01 and look.X * ox + look.Z * oz > 0.99 -- (on the ground, -Z out; 10.8 its island's)
			for _, leaf in { west[1], east[1] } do
				ok = ok and leaf.part:GetAttribute("DoorSwing") == -1 and leaf.part:GetAttribute("DoorDark") == true and not leaf.part.CanCollide
					and leaf.part.Transparency == 0
			end
			ok = ok and west[1].part:GetAttribute("DoorLeaf") == -1 and east[1].part:GetAttribute("DoorLeaf") == 1
		end
		-- the hall: nothing that collides from 5 out of the door to the hall's end, the opening's width wide (but the
		-- doorstep, 0.4 high); the walls either side, over the doorway and past its end solid
		local blocked: string? = nil
		if ok then
			stage = "its hall"
			local deep = math.abs(ox) * (wall.x1 - wall.x0) + math.abs(oz) * (wall.z1 - wall.z0)
			local hallDepth = math.min(D.Hall.Depth, deep / 2 - 1)
			local doorX, doorZ = (door.x0 + door.x1) / 2, (door.z0 + door.z1) / 2
			local half = SandboxScenery.FrontDoor.Width / 2
			-- what collides in a box `a0 … a1` along out of the door (from its middle), `c0 … c1` across it, y0 … y1
			local g = h.door.y -- (10.8: its island's top)
			local function solidIn(a0: number, a1: number, c0: number, c1: number, y0: number, y1: number, skipStep: boolean): string?
				for _, b in boxes do
					if b.part.CanCollide and not b.far and b.y1 > g + y0 and b.y0 < g + y1
						and not (skipStep and ((b.name == "Step" and b.y1 <= g + 0.45) or (b.name == "Deck" and b.y1 <= g + 0.55))) then
						local cx, cz = (b.x0 + b.x1) / 2 - doorX, (b.z0 + b.z1) / 2 - doorZ
						local hxb, hzb = (b.x1 - b.x0) / 2, (b.z1 - b.z0) / 2
						local a, aHalf = cx * ox + cz * oz, math.abs(ox) * hxb + math.abs(oz) * hzb
						local c, cHalf = cx * oz - cz * ox, math.abs(oz) * hxb + math.abs(ox) * hzb
						if a + aHalf > a0 + EPS and a - aHalf < a1 - EPS and c + cHalf > c0 + EPS and c - cHalf < c1 - EPS then
							return b.name
						end
					end
				end
				return nil
			end
			local inner = -door.part.Size.Z / 2 -- (the front wall, from the door's middle: the door's piece just outside it)
			blocked = solidIn(inner - hallDepth + 0.2, 5, -half + 0.2, half - 0.2, 0.05, 6, true)
			local mid = inner - hallDepth / 2
			local sides = solidIn(mid - 0.5, mid + 0.5, -half - 1, -half - 0.5, 1, 6, false) ~= nil and solidIn(mid - 0.5, mid + 0.5, half + 0.5, half + 1, 1, 6, false) ~= nil
				and solidIn(mid - 0.5, mid + 0.5, -half + 0.5, half - 0.5, door.part.Size.Y + 0.5, door.part.Size.Y + 1, false) ~= nil
				and solidIn(inner - hallDepth - 0.75, inner - hallDepth - 0.25, -half + 0.5, half - 0.5, 1, 6, false) ~= nil
			ok = blocked == nil and sides and #solids == 4
			if not ok then
				stage = if blocked then `{blocked} in its hall or its door's way` else `{#solids} HouseSolid pieces, the walls round the hall solid: {sides}`
			end
		end
		if ok then
			stage = "its lining and name"
			local floorTop = -math.huge
			for _, b in lining do
				ok = ok and not b.part.CanCollide and not b.part.CanQuery and b.part.Parent ~= nil and b.part.Parent.Name == "DoorHalls"
				if b.y0 < h.door.y + 0.01 and b.y1 < h.door.y + 3 then -- (its floor)
					floorTop = math.max(floorTop, b.y1)
				end
			end
			local plinthTop = if plinths[1] then plinths[1].y1 else h.door.y
			local texts: { string } = {}
			for _, d in model:GetDescendants() do
				if d.ClassName == "TextLabel" and d.Parent and d.Parent.Parent and d.Parent.Parent.Name == "Mailbox" then
					table.insert(texts, d.Text)
				end
			end
			ok = ok and #lining == 5 and floorTop >= plinthTop and floorTop < plinthTop + 0.1 and table.find(texts, string.upper(h.name)) ~= nil
		end
		if ok then
			made += 1
		elseif okAll then
			okAll, why = false, `{h.name}: {stage}`
		end
	end
	check("the five other places in their looks, each its model (SandboxHouse) in its Atomic chunk, its walls the PrimaryPart in its box (but the cabin's veranda and the mill's wheel, VillageLooks.Overhangs), its FrontDoor (SandboxDoor, -Z out) on its door, two leaves, no back door",
		okAll and made == 5, why)
	check("…walkable as the farmstead's (4 HouseSolid pieces: the walls less the front door's hall, nothing solid in the hall or the door's way but the doorstep or the cabin's deck; the plinth no longer solid), the hall lined dark over the plinth (the mill's over the ground), its name on its mailbox",
		okAll, why)
	-- (a Placed that holds no place to empty, an old save's village house's id: nothing built)
	local nowhere: VillageScenery.Placed = { id = "Hlavní_n_5", kind = "old", box = { x0 = 0, x1 = 30, z0 = 0, z1 = 24 }, yaw = 0, seed = 1, opts = { rich = true }, ids = { "Hlavní_n_5" }, street = "Hlavní" }
	check("SandboxWorld.villageHouse and SandboxWorld.walkIn: the places to empty's builders (one that holds no place: none)", type(SandboxWorld.walkIn) == "function"
		and type(SandboxWorld.villageHouse) == "function" and type(SandboxWorld.doorLeaves) == "function" and #VillageScenery.houses() == 5
		and SandboxWorld.villageHouse(G.Instance.new("Folder"), nowhere) == nil)
end

-- the words: the mailbox's (9.7: no signpost; the portals' signs: tests/lobby_test.luau)
do
	local mailbox: string? = nil
	local signpost = 0
	for _, d in world:GetDescendants() do
		if d.ClassName == "TextLabel" then
			if d.Parent and d.Parent.Parent and d.Parent.Parent.Name == "MailboxName" then
				mailbox = d.Text
			end
			if string.find(d.Text, "WAREHOUSES", 1, true) then
				signpost += 1
			end
		end
	end
	local lamps = 0 -- (street lamps out of the lobby: the dispatch kiosk's lamp is in it)
	for _, b in named("LampArm") do
		lamps += if SandboxMap.inLobby(b.x0, b.z0) then 0 else 1
	end
	check("the mailbox says THE OLD FARMSTEAD; 9.7 no signpost, no street lamps (the lobby's lamps are on its plaza)", mailbox == "THE OLD FARMSTEAD" and signpost == 0
		and #named("SignBoard") == 0 and lamps == 0, `{mailbox}, {signpost} signposts, {lamps} street lamps`)
end

-- shadows only from the bigger parts
do
	local small: string? = nil
	local casting = 0
	for _, b in boxes do
		if b.part.CastShadow then
			casting += 1
			local s = b.part.Size
			local long = math.max(s.X, s.Y, s.Z)
			local short = math.min(s.X, s.Y, s.Z)
			if long < SandboxScenery.Shadow.Long or s.X + s.Y + s.Z - long - short < SandboxScenery.Shadow.Wide or b.far or b.part.Transparency >= 1 then
				small = b.name
			end
		end
	end
	check(`shadows only from the bigger parts ({casting} of {#boxes})`, small == nil and casting < #boxes / 2, small)
end

-- 8.0.1 review: a van finds room at its spots. server/Vehicles.luau findRoom asks GetPartBoundsInBox for the room the
-- van's hull needs (Config.SpawnSpot: from Lift over its wheels' ground up to its roof, Pad wider all round; only what
-- collides), leaving out the folders of Config.SpawnSpot.Pass. That query sees a part's whole box: a mound's buried
-- ball is a cube some 480 studs wide whose top stands over the meadow, so without the pass every van's spot was
-- "taken" and the van went down anyway, onto a player too. Here the built world and every plot's warehouse
-- (WarehouseLayout.pieces, its solid ones) stand in for the workspace, the wheels' rays find the ground (a ball's
-- cap, a disc, else a part's box), and the Sprinter (SprinterLooks: its hull, its wheels) at every house's curb (9.7:
-- where a run parks it) has its four wheels on one plane and its room free on the first try; a player standing there
-- takes it.
do
	local Cfg = Config.SpawnSpot
	type Solid = { name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, passed: boolean, ball: { number }?, disc: { number }? }
	local passes: { any } = {}
	for _, path in Cfg.Pass do
		local found: any = workspace
		for name in string.gmatch(path, "[^%.]+") do
			found = if found then found:FindFirstChild(name) else nil
		end
		if found and found ~= workspace then
			table.insert(passes, found)
		end
	end
	check("Config.SpawnSpot.Pass finds the sandbox's ground (workspace.Sandbox.Ground)", table.find(passes, world:FindFirstChild("Ground")) ~= nil and table.find(Cfg.Pass, "Loot") ~= nil and table.find(Cfg.Pass, "Animals") ~= nil)
	local solids: { Solid } = {}
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			local size = d.Size
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
			local hx = (math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z) / 2
			local hy = (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2
			local hz = (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
			local passed = false
			for _, folder in passes do
				passed = passed or d:IsDescendantOf(folder)
			end
			local solid: Solid = { name = d.Name, x0 = x - hx, x1 = x + hx, y0 = y - hy, y1 = y + hy, z0 = z - hz, z1 = z + hz, passed = passed }
			if d.Shape == Enum.PartType.Ball then
				solid.ball = { x, y, z, size.X / 2 }
			elseif d.Shape == Enum.PartType.Cylinder and math.abs(r10) > 0.999 then
				solid.disc = { x, z, size.Y / 2, y + hy } -- (its axis, the part's X, standing up)
			end
			table.insert(solids, solid)
		end
	end
	for _, plot in SandboxMap.Plots do
		for _, p in WarehouseLayout.pieces(plot) do
			if p.solid then
				local x0, x1, y0, y1, z0, z1 = WarehouseLayout.bounds(p)
				table.insert(solids, { name = `warehouse {plot.id}'s {p.name}`, x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = z0, z1 = z1, passed = false })
			end
		end
	end
	-- a wheel's ray from `from` down Probe studs: the highest top it meets (nil: none)
	local function ray(x: number, z: number, from: number): number?
		local best: number? = nil
		for _, s in solids do
			local top: number? = nil
			local ball, disc = s.ball, s.disc
			if ball then
				local d2 = (x - ball[1]) ^ 2 + (z - ball[3]) ^ 2
				if d2 < ball[4] ^ 2 then
					top = ball[2] + math.sqrt(ball[4] ^ 2 - d2)
				end
			elseif disc then
				if (x - disc[1]) ^ 2 + (z - disc[2]) ^ 2 <= disc[3] ^ 2 then
					top = disc[4]
				end
			elseif x >= s.x0 and x <= s.x1 and z >= s.z0 and z <= s.z1 then
				top = s.y1
			end
			if top and top <= from and top >= from - Cfg.Probe and (best == nil or top > (best :: number)) then
				best = top
			end
		end
		return best
	end
	local hullTop = 0
	for _, b in SprinterLooks.hull() do
		hullTop = math.max(hullTop, b.at[2] + b.size[2] / 2)
	end
	local sx, sy, sz, cy = SpawnSpot.box(SprinterLooks.Width, SprinterLooks.Length, hullTop, Cfg.Lift, Cfg.Pad)
	local wheels = { { -SprinterLooks.Track, -SprinterLooks.Axle }, { SprinterLooks.Track, -SprinterLooks.Axle }, { -SprinterLooks.Track, SprinterLooks.Axle }, { SprinterLooks.Track, SprinterLooks.Axle } }
	-- findRoom's first try at a spot: the ground's plane under the wheels, then what takes the room over it
	local function firstTry(spot: SandboxMap.Spot, extra: { Solid }?, pass: boolean): (boolean, string)
		local turn = math.rad(spot.yaw)
		local c, s = math.cos(turn), math.sin(turn)
		local points: { { number } } = {}
		for _, w in wheels do
			-- (CFrame.Angles(0, yaw, 0) * (x, 0, z))
			local x, z = spot.x + c * w[1] + s * w[2], spot.z - s * w[1] + c * w[2]
			local top = ray(x, z, spot.y + Cfg.Probe / 2)
			if not top then
				return false, `no ground under a wheel at {x}, {z}`
			end
			table.insert(points, { x, top, z })
		end
		local even, why, up, middle = SpawnSpot.plane(points, Cfg.Spread, Cfg.Slope)
		if not even or not up or not middle then
			return false, why
		end
		if math.abs(up[2] - 1) > 1e-6 then
			return false, "the ground under it is not level"
		end
		local ground = SpawnSpot.heightAt(up, middle, spot.x, spot.z)
		-- (yaw 0 or 180: the room's box lies along the axes)
		local hx, hz = sx / 2, sz / 2
		if math.abs(s) > 1e-6 then
			hx, hz = sz / 2, sx / 2
		end
		local bx0, bx1, by0, by1, bz0, bz1 = spot.x - hx, spot.x + hx, ground + cy - sy / 2, ground + cy + sy / 2, spot.z - hz, spot.z + hz
		local all = table.clone(solids)
		for _, e in extra or {} do
			table.insert(all, e)
		end
		for _, b in all do
			if (pass and b.passed) then
				continue
			end
			if b.x0 < bx1 and b.x1 > bx0 and b.y0 < by1 and b.y1 > by0 and b.z0 < bz1 and b.z1 > bz0 then
				return false, `{b.name} in the way`
			end
		end
		return true, string.format("its wheels at %.2f", ground)
	end
	local spots: { { name: string, spot: SandboxMap.Spot } } = {}
	for _, h in SandboxMap.Houses do -- (9.7 runs: a run parks its truck at its house's curb; none at the plots)
		table.insert(spots, { name = `{h.name}'s curb`, spot = h.curb })
	end
	local grounded = 0
	for _, at in spots do
		local spot = at.spot
		local free, why = firstTry(spot, nil, true)
		check(`a van at {at.name} finds room on the first try ({why})`, free, why)
		-- 8.9: the ground is flat, its parts all under the van's room: even without the pass nothing of it takes the spot
		local freeAnyway = firstTry(spot, nil, false)
		if freeAnyway then
			grounded += 1
		end
		-- a player standing there (their body's box: 2 wide, 1 deep, 5 tall on the ground)
		local feet = spot.y -- (10.8: its island's road level)
		local body: Solid = { name = "a player", x0 = spot.x - 1, x1 = spot.x + 1, y0 = feet, y1 = feet + 5, z0 = spot.z - 0.5, z1 = spot.z + 0.5, passed = false }
		local taken, whyTaken = firstTry(spot, { body }, true)
		check(`… a player standing at {at.name} takes it`, not taken and whyTaken == "a player in the way", whyTaken)
	end
	check(`8.9: no mound any more: even without the pass the ground takes none of the spots ({grounded} of {#spots} free)`, grounded == #spots, grounded)
end

-- the light: a fixed warm afternoon
do
	local Lighting = game:GetService("Lighting")
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	local grade = Lighting:FindFirstChild("SandboxGrade")
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	check("the light: an afternoon clock, shadows, the air, the sky, the clouds, the grade", Lighting.ClockTime >= 14 and Lighting.ClockTime <= 17 and Lighting.GlobalShadows == true and air ~= nil and air.Density > 0 and Lighting:FindFirstChildOfClass("Sky") ~= nil and clouds ~= nil and grade ~= nil and grade.TintColor.B < grade.TintColor.R)
	check("the clock attributes say a still afternoon", workspace:GetAttribute("Night") == false and workspace:GetAttribute("ClockRate") == 0 and workspace:GetAttribute("Weather") == "clear")
	SandboxWorld.lighting()
	local count = 0
	for _, child in Lighting:GetChildren() do
		if child.ClassName == "Atmosphere" or child.ClassName == "Sky" or child.Name == "SandboxGrade" then
			count += 1
		end
	end
	check("lighting() again changes nothing (one sky, one air, one grade)", count == 3, count)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
