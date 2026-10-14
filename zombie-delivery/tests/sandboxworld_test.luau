-- 8.0 SANDBOX, the map (design/sandbox/KONTRAKT.md): shared/SandboxScenery.luau's numbers and the world the real
-- server/SandboxWorld.luau builds from them (as SandboxWorldServer.luau on tools/perf/world-mock.luau, WorldMock.luau):
-- everything we play on inside SandboxMap.Bounds (the far hills and peaks outside them), the asphalt over every road
-- and the turnaround with a shoulder down to the meadow on every edge (no step a wheel would catch), nothing that
-- collides on the roads, the turnaround, the plots (but their pads), the path from the curb to the house's door or in
-- the door's way, the trees off all of that and off the vans' ways, the part budget, the shadows only on bigger
-- parts, the chalet in its box with its FrontDoor at House.door, the signpost's and the mailbox's words, the light;
-- 8.1: the house's box the owner's Blender house's, its parts in House_sandbox_house for server/HouseMesh.luau, the
-- FrontDoor on the model's door;
-- 8.0.1: a van finds room on the first try at every vanSpot and at the house's curb (server/Vehicles.luau findRoom's
-- box query, Config.SpawnSpot.Pass leaving out the ground's mounds), and not where a player stands.
-- Run with tests/run_tests.py.
local Mock = require("./WorldMock")
local G = Mock.globals
local Enum = G.Enum
local workspace, game = Mock.workspace, Mock.game
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local SandboxWorld = require("./SandboxWorldServer")
local HouseMesh = require("./HouseMeshServer")
local HouseArt = require("./HouseArt")
local SpawnSpot = require("./SpawnSpot")
local SprinterLooks = require("./SprinterLooks")
local WarehouseLayout = require("./WarehouseLayout")

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
local TURN = SandboxMap.Turnaround
local HOUSE = SandboxMap.House
local MAIN, DEPOT = SandboxMap.Roads[1], SandboxMap.Roads[2]
local RUN = SandboxScenery.Run
local EPS = 1e-3

local function grow(r: Rect, by: number): Rect
	return { x0 = r.x0 - by, x1 = r.x1 + by, z0 = r.z0 - by, z1 = r.z1 + by }
end
local function inRect(r: Rect, x: number, z: number): boolean
	return x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1
end
local function onAsphalt(x: number, z: number): boolean
	for _, road in SandboxMap.Roads do
		if inRect(road :: any, x, z) then
			return true
		end
	end
	return SandboxScenery.circleOut(x, z) <= 0
end

-- ── The numbers ────────────────────────────────────────────────────────────

do
	-- the meadow's tiles fill the Bounds but the holes, none over another or a hole
	local tiles, holes = SandboxScenery.meadow()
	local area = 0
	local overlap: string? = nil
	for i, t in tiles do
		area += (t.x1 - t.x0) * (t.z1 - t.z0)
		if t.x0 < B.x0 or t.x1 > B.x1 or t.z0 < B.z0 or t.z1 > B.z1 or t.x1 - t.x0 > 2048 or t.z1 - t.z0 > 2048 then
			overlap = `tile {i} out of the Bounds or too big`
		end
		for j, u in tiles do
			if j > i and t.x0 < u.x1 - EPS and u.x0 < t.x1 - EPS and t.z0 < u.z1 - EPS and u.z0 < t.z1 - EPS then
				overlap = `tiles {i} and {j}`
			end
		end
		for _, h in holes do
			if t.x0 < h.x1 - EPS and h.x0 < t.x1 - EPS and t.z0 < h.z1 - EPS and h.z0 < t.z1 - EPS then
				overlap = `tile {i} over a hole`
			end
		end
	end
	local holeArea = 0
	for _, h in holes do
		holeArea += (h.x1 - h.x0) * (h.z1 - h.z0)
	end
	check("the meadow's tiles cover the Bounds but the pads and the lawn, none overlapping", overlap == nil and math.abs(area + holeArea - (B.x1 - B.x0) * (B.z1 - B.z0)) < 1, overlap or area)

	-- the mounds stay well off the roads, the turnaround, the plots and the house's lot, inside the fence
	local bad: string? = nil
	for _, m in SandboxScenery.mounds() do
		local keep = m.base + 10
		for _, road in SandboxMap.Roads do
			if SandboxScenery.rectDistance(road :: any, m.x, m.z) < keep + RUN then
				bad = `mound at {m.x}, {m.z} by {road.name}`
			end
		end
		for _, plot in SandboxMap.Plots do
			if SandboxScenery.rectDistance(plot.rect, m.x, m.z) < keep then
				bad = `mound at {m.x}, {m.z} by plot {plot.id}`
			end
		end
		if SandboxScenery.rectDistance(HOUSE.lot, m.x, m.z) < keep or SandboxScenery.circleOut(m.x, m.z) < keep + RUN then
			bad = `mound at {m.x}, {m.z} by the house`
		end
		if SandboxScenery.outside(m.x, m.z) > -(m.base + SandboxScenery.FenceInset + 2) then
			bad = `mound at {m.x}, {m.z} at the edge`
		end
		if m.radius * 2 > 2048 then
			bad = "a mound's ball too big for a part"
		end
	end
	check("the mounds keep off the roads, the plots and the house, inside the fence", bad == nil, bad)

	-- the shoulders: wherever a wheel leaves the asphalt it rolls down a slope, never off a step
	local ramps = SandboxScenery.ramps()
	local function shoulder(x: number, z: number): number
		local best = GROUND
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
		local want = GROUND + (top - GROUND) * (1 - out / RUN) - (sag or 0)
		local margin = shoulder(x, z) - want
		if margin < worst then
			worst, at = margin, string.format("%.1f, %.1f (%.1f out)", x, z, out)
		end
	end
	for _, out in { 0.3, 1.5, 3 } do
		for x = DEPOT.x0, DEPOT.x1, 5 do
			edgePoint(x, DEPOT.z0 - out, out, TOP)
			edgePoint(x, DEPOT.z1 + out, out, TOP)
		end
		for z = DEPOT.z0, DEPOT.z1, 4 do
			edgePoint(DEPOT.x0 - out, z, out, TOP)
			edgePoint(DEPOT.x1 + out, z, out, TOP)
		end
		for _, c in { { DEPOT.x0, DEPOT.z0, -1, -1 }, { DEPOT.x0, DEPOT.z1, -1, 1 }, { DEPOT.x1, DEPOT.z0, 1, -1 }, { DEPOT.x1, DEPOT.z1, 1, 1 } } do
			for _, a in { 0.2, 0.5, 0.8 } do
				local dx, dz = math.cos(a * math.pi / 2), math.sin(a * math.pi / 2)
				edgePoint(c[1] + c[3] * dx * out, c[2] + c[4] * dz * out, out, TOP)
			end
		end
		for z = DEPOT.z1, TURN.z - TURN.r, 5 do
			edgePoint(MAIN.x0 - out, z, out, TOP)
			edgePoint(MAIN.x1 + out, z, out, TOP)
		end
		-- (the ring's wedges stand on chords just inside the asphalt's edge: mid-piece the slope starts its sag lower)
		local top = SandboxScenery.TurnaroundTop
		local sag = (top - GROUND) * TURN.r * (1 - math.cos(math.pi / SandboxScenery.RingPieces)) / RUN
		for deg = 0, 359, 3 do
			local a = math.rad(deg)
			edgePoint(TURN.x + math.cos(a) * (TURN.r + out), TURN.z + math.sin(a) * (TURN.r + out), out, top, sag)
		end
	end
	check("a shoulder slopes from the asphalt down to the meadow along every edge (no step)", worst >= -0.01, string.format("%d points, worst %.3f at %s", samples, worst, at))
	local tall: string? = nil
	for _, r in ramps do
		if r.y + r.sy / 2 > TOP + EPS or r.y - r.sy / 2 < GROUND - EPS or r.sz ~= RUN then
			tall = `a {r.kind} at {r.x}, {r.z}`
		end
	end
	check("no shoulder rises over the asphalt or sinks under the meadow", tall == nil, tall)

	-- the trees: 60 – 120, each where the rules let it stand, apart from each other
	local trees = SandboxScenery.trees()
	local why: string? = nil
	for i, t in trees do
		local rule = SandboxScenery.treeRule(t.x, t.z, t.canopy)
		if rule then
			why = `tree {i}: {rule}`
		end
		for j = i + 1, #trees do
			local u = trees[j]
			if (t.x - u.x) ^ 2 + (t.z - u.z) ^ 2 < 9 ^ 2 then
				why = `trees {i} and {j} too close`
			end
		end
		if t.variant < 1 or t.variant > 3 then
			why = `tree {i}'s variant {t.variant}`
		end
	end
	check("60 – 120 trees, every one where the rules let it stand", #trees >= 60 and #trees <= 120 and why == nil, why or #trees)
	local again = SandboxScenery.trees()
	check("the same trees every time", again == trees and #again == #trees)

	-- far away: the hills' and the peaks' feet outside the Bounds, the far meadow round them
	local near: string? = nil
	for _, h in SandboxScenery.hills() do
		if SandboxScenery.outside(h.x, h.z) < h.base + 20 then
			near = `a hill at {math.floor(h.x)}, {math.floor(h.z)}`
		end
		if h.radius * 2 > 2048 then
			near = "a hill's ball too big for a part"
		end
	end
	for _, p in SandboxScenery.peaks() do
		if SandboxScenery.outside(p.x, p.z) < p.half * math.sqrt(2) + 100 then
			near = `a peak at {math.floor(p.x)}, {math.floor(p.z)}`
		end
		if p.half > 2048 or p.height > 2048 or p.capY + p.capHeight < p.base + p.height then
			near = "a peak too big for its parts or its cap under its top"
		end
	end
	check("the hills and the peaks stand outside the Bounds", near == nil, near)
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
local boxes: { Box } = {}
local byName: { [string]: { Box } } = {}
local unanchored = 0
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
		local box: Box = { part = d, name = d.Name, x0 = x - hx, x1 = x + hx, y0 = y0, y1 = y1, z0 = z - hz, z1 = z + hz, far = far ~= nil and d:IsDescendantOf(far), cap = cap }
		table.insert(boxes, box)
		byName[d.Name] = byName[d.Name] or {}
		table.insert(byName[d.Name], box)
		if not d.Anchored then
			unanchored += 1
		end
	end
end
local function named(name: string): { Box }
	return byName[name] or {}
end
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
	check("everything but the far view is inside SandboxMap.Bounds", out == nil, out)
	check("the far meadow, hills and peaks are all outside the Bounds", farIn == nil and #named("Peak") > 0 and #named("Hill") > 0, farIn)
	check("the far view is one Persistent model", far ~= nil and far:IsA("Model") and far.ModelStreamingMode == Enum.ModelStreamingMode.Persistent)
	local walls = named("InvisibleWall")
	local sides = { x0 = false, x1 = false, z0 = false, z1 = false }
	local real = true
	for _, w in walls do
		local p = w.part
		sides.x0 = sides.x0 or (math.abs(w.x0 - B.x0) < EPS and w.z0 <= B.z0 + EPS and w.z1 >= B.z1 - EPS)
		sides.x1 = sides.x1 or (math.abs(w.x1 - B.x1) < EPS and w.z0 <= B.z0 + EPS and w.z1 >= B.z1 - EPS)
		sides.z0 = sides.z0 or (math.abs(w.z0 - B.z0) < EPS and w.x0 <= B.x0 + EPS and w.x1 >= B.x1 - EPS)
		sides.z1 = sides.z1 or (math.abs(w.z1 - B.z1) < EPS and w.x0 <= B.x0 + EPS and w.x1 >= B.x1 - EPS)
		real = real and p.Transparency >= 1 and p.CanCollide and w.y0 <= GROUND and w.y1 >= 100
	end
	check("invisible walls stand on all four sides of the Bounds", #walls == 4 and real and sides.x0 and sides.x1 and sides.z0 and sides.z1)
end

-- the asphalt covers SandboxMap.Roads and the turnaround, its top at RoadTop
do
	local asphalt = {}
	for _, b in named("Road") do
		table.insert(asphalt, b)
	end
	local disc = named("Turnaround")[1]
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
				if not covered(x, z, asphalt, TOP, EPS) then
					missed = `{road.name} at {x}, {z}`
				end
			end
		end
	end
	check("the asphalt covers every road of SandboxMap.Roads at RoadTop", missed == nil and #asphalt == 2, missed)
	local ok = disc ~= nil and disc.part.Shape == Enum.PartType.Cylinder and math.abs((disc.x1 - disc.x0) / 2 - TURN.r) < EPS
	if disc then
		for deg = 0, 359, 10 do
			for _, r in { 0, TURN.r * 0.5, TURN.r - 0.5 } do
				local x, z = TURN.x + math.cos(math.rad(deg)) * r, TURN.z + math.sin(math.rad(deg)) * r
				if not covered(x, z, { disc }, TOP, 0.03) then
					ok = false
				end
			end
		end
	end
	check("the turnaround is an asphalt disc on the Turnaround (its top within a hair of RoadTop)", ok)
	check("a shoulder part for every piece of SandboxScenery.ramps", #named("Shoulder") == #SandboxScenery.ramps())
	check("the markings: centre lines, edge lines, the give-way line", #named("CentreLine") > 20 and #named("EdgeLine") > 10 and #named("GiveWay") == 1)
	local raised: string? = nil
	for _, name in { "CentreLine", "EdgeLine", "GiveWay" } do
		for _, b in named(name) do
			if b.part.CanCollide or b.y1 > TOP + 0.06 or not onAsphalt((b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2) then
				raised = `{name} at {math.floor(b.x0)}, {math.floor(b.z0)}`
			end
		end
	end
	check("the markings lie flat on the asphalt and never collide", raised == nil, raised)
end

-- nothing that collides stands on the roads, the turnaround, the plots (their pads are the floor), the path from the
-- curb to the door or in the door's way; the floors themselves never rise over the asphalt's top
do
	local FLOOR = { Road = true, Turnaround = true, Shoulder = true, Pad = true, Meadow = true, Lawn = true }
	local areas: { { name: string, rect: Rect, circle: boolean? } } = {}
	for _, road in SandboxMap.Roads do
		table.insert(areas, { name = road.name, rect = road :: any })
	end
	table.insert(areas, { name = "the turnaround", rect = { x0 = TURN.x - TURN.r, x1 = TURN.x + TURN.r, z0 = TURN.z - TURN.r, z1 = TURN.z + TURN.r }, circle = true })
	for _, plot in SandboxMap.Plots do
		table.insert(areas, { name = `plot {plot.id}`, rect = plot.rect })
	end
	table.insert(areas, { name = "the path from the curb to the door", rect = { x0 = SandboxScenery.Path.x0, x1 = SandboxScenery.Path.x1, z0 = SandboxScenery.Path.z0, z1 = HOUSE.door.z - 0.01 } })
	local d = HOUSE.door
	table.insert(areas, { name = "the front door's way", rect = { x0 = d.x - 2.5, x1 = d.x + 2.5, z0 = d.z - 5, z1 = d.z - 0.01 } })
	local blocked: string? = nil
	local floorHigh: string? = nil
	for _, b in boxes do
		if b.far or not b.part.CanCollide then
			continue
		end
		if FLOOR[b.name] then
			if b.y1 > TOP + EPS then
				floorHigh = `{b.name} at {math.floor(b.x0)}, {math.floor(b.z0)}`
			end
			continue
		end
		if b.y1 <= GROUND + 0.05 or b.y0 >= 14 then
			continue
		end
		for _, a in areas do
			local r = a.rect
			if b.x0 < r.x1 - EPS and b.x1 > r.x0 + EPS and b.z0 < r.z1 - EPS and b.z1 > r.z0 + EPS then
				local hit = true
				if a.circle then
					local cx = math.clamp(TURN.x, b.x0, b.x1)
					local cz = math.clamp(TURN.z, b.z0, b.z1)
					hit = (cx - TURN.x) ^ 2 + (cz - TURN.z) ^ 2 < (TURN.r - EPS) ^ 2
				end
				if hit then
					blocked = `{b.name} on {a.name}`
				end
			end
		end
	end
	check("nothing that collides on the roads, the turnaround, the plots, the path to the door or the door's way", blocked == nil, blocked)
	check("no floor (asphalt, shoulder, pad, meadow, lawn) rises over RoadTop", floorHigh == nil, floorHigh)
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
	check("a concrete pad on every plot's rect, flush with the meadow", padOk)
end

-- the trees keep off the roads (and their shoulders), the turnaround, the plots, the house's lot, the path and the vans'
-- ways
do
	local trunks = named("Trunk")
	local keep: { { name: string, rect: Rect, circle: boolean? } } = {}
	for _, road in SandboxMap.Roads do
		table.insert(keep, { name = road.name, rect = grow(road :: any, RUN) })
	end
	table.insert(keep, { name = "the turnaround", rect = grow({ x0 = TURN.x - TURN.r, x1 = TURN.x + TURN.r, z0 = TURN.z - TURN.r, z1 = TURN.z + TURN.r }, RUN), circle = true })
	for _, plot in SandboxMap.Plots do
		table.insert(keep, { name = `plot {plot.id}`, rect = plot.rect })
	end
	table.insert(keep, { name = "the house's lot", rect = HOUSE.lot })
	table.insert(keep, { name = "the path", rect = SandboxScenery.Path })
	for n, way in SandboxScenery.vanPaths() do
		table.insert(keep, { name = `van way {n}`, rect = way })
	end
	local hit: string? = nil
	for _, name in { "Trunk", "Needles" } do
		for _, b in named(name) do
			for _, k in keep do
				local r = k.rect
				if b.x0 < r.x1 and b.x1 > r.x0 and b.z0 < r.z1 and b.z1 > r.z0 then
					local inside = true
					if k.circle then
						local cx = math.clamp(TURN.x, b.x0, b.x1)
						local cz = math.clamp(TURN.z, b.z0, b.z1)
						inside = (cx - TURN.x) ^ 2 + (cz - TURN.z) ^ 2 < (TURN.r + RUN) ^ 2
					end
					if inside then
						hit = `a tree's {name} on {k.name} at {math.floor(b.x0)}, {math.floor(b.z0)}`
					end
				end
			end
		end
	end
	check(`the trees ({#trunks}) keep off the roads, the turnaround, the plots, the house's lot, the path and the vans' ways`, hit == nil and #trunks == #SandboxScenery.trees() and #named("Needles") == #trunks, hit)
	local solid = true
	for _, b in trunks do
		solid = solid and b.part.CanCollide
	end
	for _, b in named("Needles") do
		solid = solid and not b.part.CanCollide
	end
	check("a trunk collides, its needles do not", solid)
end

-- the chalet: in House.house's box, facing north, its FrontDoor at House.door. 8.1: its parts in the Model
-- "House_sandbox_house" (attribute Home) that server/HouseMesh.luau dresses, on the owner's Blender house's box (HouseMesh
-- dresses only a house of that size; HouseArt: design/blender-house's manifest, tests/run_tests.py), the FrontDoor on the
-- model's front door; no import here, so the chalet as it is (tools/house-art/check.py dresses it). 8.3 the big move:
-- its doors' leaves and its back door (House.back) on the model's back door.
do
	local chalet = world:FindFirstChild("TheOldChalet")
	check("the chalet is a model with its house's id", chalet ~= nil and chalet:IsA("Model") and chalet:GetAttribute("SandboxHouse") == HOUSE.id)
	local own = chalet and chalet:FindFirstChild("House_" .. HOUSE.id)
	local h = HOUSE.house
	local body = named("House")[1]
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
	local leavesOk, count = true, 0
	for _, want in { { "FrontLeafWest", "front", "west", door }, { "FrontLeafEast", "front", "east", door }, { "BackLeaf", "back", "west", back } } do
		local list = named(want[1])
		local leaf, way = list[1], want[4]
		count += #list
		leavesOk = leavesOk and #list == 1 and way ~= nil and leaf.part:GetAttribute("DoorLeaf") == want[2] and leaf.part:GetAttribute("Hinge") == want[3]
			and not leaf.part.CanCollide and leaf.part.Transparency == 0 and leaf.part.Parent == own
			and leaf.x0 >= way.x0 - 0.05 and leaf.x1 <= way.x1 + 0.05 and leaf.y0 >= way.y0 - 0.05 and leaf.y1 <= way.y1 + 0.05
			and (if want[3] == "west" then math.abs(leaf.x0 - way.x0) < 0.1 else math.abs(leaf.x1 - way.x1) < 0.1)
	end
	check("8.3: the doors' leaves shut in their doorways (FrontLeafWest west, FrontLeafEast east, BackLeaf west), the FrontDoor unseen behind them",
		leavesOk and count == 3 and door ~= nil and door.part.Transparency == 1)
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
	check(`the garden (fence, gate, mailbox, flower boxes, path: {gardenParts} parts) never collides`, gardenSolid == nil and #named("FlowerBox") >= 3 and #named("Mailbox") == 1 and #named("Path") == 1, gardenSolid)
end

-- the words: the signpost's boards, the gate's and the mailbox's
do
	local texts: { [string]: number } = {}
	local mailbox: string? = nil
	for _, d in world:GetDescendants() do
		if d.ClassName == "TextLabel" then
			texts[d.Text] = (texts[d.Text] or 0) + 1
			if d.Parent and d.Parent.Parent and d.Parent.Parent.Name == "MailboxName" then
				mailbox = d.Text
			end
		end
	end
	check("the signpost: ← WAREHOUSES, THE OLD CHALET → (and the other ways round)", texts["← WAREHOUSES"] == 2 and texts["WAREHOUSES →"] == 2 and texts["THE OLD CHALET →"] == 1 and texts["← THE OLD CHALET"] == 1)
	check("the mailbox says THE OLD CHALET", mailbox == "THE OLD CHALET", mailbox)
end

-- the street lamps along Main Street, off its shoulders
do
	local poles = named("LampPole")
	local ok = #poles >= 4
	for _, b in poles do
		local x = (b.x0 + b.x1) / 2
		local z = (b.z0 + b.z1) / 2
		local off = math.min(math.abs(x - MAIN.x0), math.abs(x - MAIN.x1))
		ok = ok and off > RUN and off < RUN + 4 and z > DEPOT.z1 and z < TURN.z - TURN.r and not onAsphalt(x, z)
	end
	check(`street lamps along Main Street ({#poles})`, ok)
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
-- cap, a disc, else a part's box), and the Sprinter (SprinterLooks: its hull, its wheels) at every plot's vanSpot and
-- at the house's curb has its four wheels on one plane and its room free on the first try; a player standing there
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
	for _, plot in SandboxMap.Plots do
		table.insert(spots, { name = `plot {plot.id}'s vanSpot`, spot = plot.vanSpot })
	end
	table.insert(spots, { name = "the house's curb", spot = HOUSE.curb })
	local mounded = 0
	for _, at in spots do
		local spot = at.spot
		local free, why = firstTry(spot, nil, true)
		check(`a van at {at.name} finds room on the first try ({why})`, free, why)
		-- the mounds' boxes (left out by the pass) would take it
		local _, unpassed = firstTry(spot, nil, false)
		if string.find(unpassed, "Mound", 1, true) then
			mounded += 1
		end
		-- a player standing there (their body's box: 2 wide, 1 deep, 5 tall on the ground)
		local feet = if spot == HOUSE.curb then SandboxScenery.TurnaroundTop else GROUND
		local body: Solid = { name = "a player", x0 = spot.x - 1, x1 = spot.x + 1, y0 = feet, y1 = feet + 5, z0 = spot.z - 0.5, z1 = spot.z + 0.5, passed = false }
		local taken, whyTaken = firstTry(spot, { body }, true)
		check(`… a player standing at {at.name} takes it`, not taken and whyTaken == "a player in the way", whyTaken)
	end
	check(`without the pass the mounds' boxes take every spot (here: {mounded} of {#spots})`, mounded == #spots, mounded)
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
