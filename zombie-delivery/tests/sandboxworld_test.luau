-- 8.0 SANDBOX, the map (design/sandbox/KONTRAKT.md): shared/SandboxScenery.luau's numbers and the world the real
-- server/SandboxWorld.luau builds from them (as SandboxWorldServer.luau on tools/perf/world-mock.luau, WorldMock.luau):
-- everything we play on inside SandboxMap.Bounds (the far hills and peaks outside them), the asphalt over every road
-- and the turnaround with a shoulder down to the meadow on every edge (no step a wheel would catch), nothing that
-- collides on the roads, the turnaround, the plots (but their pads), the path from the curb to the house's door or in
-- the door's way, the trees off all of that and off the vans' ways, the part budget, the shadows only on bigger
-- parts, the chalet in its box with its FrontDoor at House.door, the signpost's and the mailbox's words, the light.
-- Run with tests/run_tests.py.
local Mock = require("./WorldMock")
local G = Mock.globals
local Enum = G.Enum
local workspace, game = Mock.workspace, Mock.game
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local SandboxWorld = require("./SandboxWorldServer")

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

-- the chalet: in House.house's box, facing north, its FrontDoor at House.door
do
	local chalet = world:FindFirstChild("TheOldChalet")
	check("the chalet is a model with its house's id", chalet ~= nil and chalet:IsA("Model") and chalet:GetAttribute("SandboxHouse") == HOUSE.id)
	local h = HOUSE.house
	local body = named("House")[1]
	check("its body fills House.house's footprint", body ~= nil and math.abs(body.x0 - (h.x - h.sx / 2)) < EPS and math.abs(body.x1 - (h.x + h.sx / 2)) < EPS and math.abs(body.z0 - (h.z - h.sz / 2)) < EPS and math.abs(body.z1 - (h.z + h.sz / 2)) < EPS and math.abs(body.y0 - h.y) < EPS)
	local top, outside = -math.huge, nil :: string?
	for _, b in boxes do
		if chalet and b.part:IsDescendantOf(chalet) then
			top = math.max(top, b.y1)
			if b.x0 < HOUSE.lot.x0 - EPS or b.x1 > HOUSE.lot.x1 + EPS or b.z0 < HOUSE.lot.z0 - EPS or b.z1 > HOUSE.lot.z1 + EPS then
				outside = b.name
			end
		end
	end
	check(`the chalet's top ({string.format("%.1f", top)}) within House.house's height`, top <= h.y + h.sy + 0.05 and top > h.y + h.sy - 2)
	check("all of the chalet and its garden on the house's lot", outside == nil, outside)
	local doors = named("FrontDoor")
	local door = doors[1]
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
