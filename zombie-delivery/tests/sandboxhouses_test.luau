-- 8.9 six houses, 9.4 the countryside (design/countryside/plan.py, plan.json): shared/SandboxMap.luau's Houses (the six
-- places to empty), its Bounds and Roads against design/countryside/plan.json (CountryPlan.luau, tests/run_tests.py
-- writes it from the plan), and their contracts (Config.Moving.Sandbox.Houses) with the economy's numbers
-- (Config.Furniture, shared/HouseLayout.luau):
--   * the data: the plan's six (`spots`, in its order: the farmstead first, SandboxMap.House, then the pond cabin, the
--     lone house, the forest lodge, the old mill, the orchard cottage) with their ids, names, roads, looks, boxes (the
--     owner's sizes: sx along its front × sz deep), doors, curbs, lots and yaws as the plan has them (a place's door
--     its look's: shared/VillageLooks.luau's door spot, Config.Village.Front less the door's 0.3 in from its box's
--     front edge); the back door only the farmstead's; each place's walls' box on its box, its lot round it up to its
--     yard, clear of every road, plot, other lot, landmark, field and the stream; the world's Bounds and roads the plan's
--     (Pražská from Depot Row's far edge, 8.0's), every place's yard at its lane's end, big enough to turn the van round
--   * every curb on asphalt with the van's back to the door (the Sprinter in its yard, its back and nose and its four
--     corners on it, the back nearer the door: plan.py's check), every door on its box's face looking at its road (its
--     yard: its curb in it), every place reachable by road from Depot Row (the rects that meet) and the guide's path to
--     every curb along them (SandboxSteps.route)
--   * the contracts: one per place and no other, a made-up Czech family each, the address on its road, its plan's kind
--     (big the farmstead, the spots' own the rest: HouseLayout's kinds), its clock past the horde's; the economy sane: a house
--     holds fewer pieces than the big house (Config.Furniture's Spots and collectibles, and the plans themselves:
--     HouseLayout.plan), gets less time, about the same minutes a piece
--   * the guide's words and places per house: "Drive to The Pond Cabin on Pond Lane", at the place by its own lot
--   * the places spread apart (each its own spot, 250 studs and more) and a drive of a few hundred studs to over a
--     thousand from the plots
-- Run with tests/run_tests.py.
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local SandboxSteps = require("./SandboxSteps")
local SprinterLooks = require("./SprinterLooks")
local HouseLayout = require("./HouseLayout")
local VillageLooks = require("./VillageLooks")
local VillageScenery = require("./VillageScenery")
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
local Houses = SandboxMap.Houses
local Roads = SandboxMap.Roads
local S = Config.Moving.Sandbox
local EPS = 1e-6

local function inRect(r: Rect, x: number, z: number, slack: number?): boolean
	local e = slack or 0
	return x >= r.x0 - e and x <= r.x1 + e and z >= r.z0 - e and z <= r.z1 + e
end
local function overlap(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 - EPS and b.x0 < a.x1 - EPS and a.z0 < b.z1 - EPS and b.z0 < a.z1 - EPS
end
local function same(a: Rect, b: Rect): boolean
	return math.abs(a.x0 - b.x0) < EPS and math.abs(a.x1 - b.x1) < EPS and math.abs(a.z0 - b.z0) < EPS and math.abs(a.z1 - b.z1) < EPS
end
local function look(yaw: number): (number, number)
	local r = math.rad(yaw)
	return -math.sin(r), -math.cos(r)
end
-- On asphalt: SandboxMap's roads (`roads`: a list of rects with names) or the turnaround.
local function onAsphalt(roads: { any }, x: number, z: number): boolean
	for _, r in roads do
		if inRect(r.rect or r, x, z) then
			return true
		end
	end
	local t = SandboxMap.Turnaround
	return (x - t.x) ^ 2 + (z - t.z) ^ 2 <= t.r * t.r + EPS
end
-- The rects of a road (a lane's: its rects and its yard; none: an empty list).
local function rectsOf(name: string): { SandboxMap.Road }
	local out = {}
	for _, r in Roads do
		if r.name == name then
			table.insert(out, r)
		end
	end
	return out
end

-- ── The data against the plan ─────────────────────────────────────────────

check("six places to empty, the plan's (`spots`), in its order; the first the farmstead, SandboxMap.House", #Houses == 6 and #Plan.spots == 6
	and Houses[1] == SandboxMap.House and Houses[1].id == "sandbox_house" and Houses[1].name == "The Old Farmstead")
-- the owner's six: id, name, road, look, box (sx along its front × sz deep)
local WANT = {
	{ "sandbox_house", "The Old Farmstead", "Pražská", "farmstead", 44, 34 },
	{ "pond_cabin", "The Pond Cabin", "Pond Lane", "cabin", 24, 18 },
	{ "lone_house", "The Lone House", "Hill Road", "old", 30, 24 },
	{ "forest_lodge", "The Forest Lodge", "Wood Lane", "lodge", 28, 22 },
	{ "old_mill", "The Old Mill", "Mill Lane", "mill", 24, 26 },
	{ "orchard_cottage", "The Orchard Cottage", "Orchard Lane", "cottage", 26, 20 },
}
do
	local bad: string? = nil
	for index, w in WANT do
		local h = Houses[index]
		local quarter = h.yaw == 90 or h.yaw == 270
		local sx = if quarter then h.box.z1 - h.box.z0 else h.box.x1 - h.box.x0
		local sz = if quarter then h.box.x1 - h.box.x0 else h.box.z1 - h.box.z0
		if h.id ~= w[1] or h.name ~= w[2] or h.street ~= w[3] or h.look ~= w[4] or sx ~= w[5] or sz ~= w[6] then
			bad = `{h.id}: {h.name}, {h.street}, {h.look}, {sx} × {sz}`
		end
	end
	check("…their ids, names, roads, looks and boxes the owner's (sx along the front × sz deep: the farmstead 44 × 34, the cabin 24 × 18, the lone house 30 × 24, the lodge 28 × 22, the mill 24 × 26, the cottage 26 × 20)",
		bad == nil, bad)
end
-- (a place's door is its look's, VillageLooks.doorSpots': just outside its door's piece, the body's front wall
-- Config.Village.Front in from the box's face)
local spots: { [string]: VillageLooks.DoorSpot } = {}
for _, placed in VillageScenery.houses() do
	local h = VillageScenery.emptied(placed)
	if h then
		for _, spot in VillageLooks.doorSpots(VillageLooks.house(placed.kind, placed.box, placed.yaw, placed.seed, placed.opts), placed.box, placed.yaw) do
			spots[h.id] = spot
		end
	end
end
do
	local bad: string? = nil
	local names: { [string]: boolean } = {}
	for index, h in Houses do
		local p = Plan.spots[index]
		local d, c = h.door, h.curb
		local spot = spots[h.id]
		if h.id ~= p.id or h.name ~= p.name or h.street ~= p.street or h.look ~= p.look or h.kind ~= p.kind or not same(h.box, p.box) or not same(h.lot, p.lot) then
			bad = `{h.id}: its id, name, road, look, kind, box or lot`
		elseif math.abs(d.x - p.door.x) > EPS or math.abs(d.z - p.door.z) > EPS or d.yaw ~= p.door.yaw or c.x ~= p.curb.x or c.z ~= p.curb.z or c.yaw ~= p.curb.yaw then
			bad = `{h.id}: its door or curb`
		elseif index > 1 and (spot == nil or math.abs(spot.x - d.x) > 1e-3 or math.abs(spot.z - d.z) > 1e-3 or spot.yaw ~= d.yaw) then
			bad = `{h.id}: its door not its look's ({spot and spot.x}, {spot and spot.z})`
		elseif d.y ~= SandboxMap.GroundTop or c.y ~= SandboxMap.RoadTop or h.yaw ~= d.yaw or h.yaw ~= p.yaw then
			bad = `{h.id}: its door's or curb's height, its yaw`
		elseif names[h.name] or names[h.id] then
			bad = `{h.id}: a name twice`
		elseif SandboxMap.house(h.id) ~= h then
			bad = `{h.id}: SandboxMap.house`
		end
		names[h.name], names[h.id] = true, true
	end
	check("…each one's id, name, road, look, kind, box, lot, door (its look's: 1.2 in from its box's front edge), curb and yaw the plan's; names each its own", bad == nil, bad)
end
check("the farmstead: big, on Pražská, its look its own, its back door in its back wall; the other five: kind house, no number, no back door",
	(function(): boolean
		local f = Houses[1]
		if f.kind ~= "big" or f.street ~= "Pražská" or f.look ~= "farmstead" or f.back == nil or f.back.z ~= f.box.z1 or f.number ~= nil then
			return false
		end
		for index = 2, #Houses do
			local h = Houses[index]
			if h.kind ~= "house" or h.back ~= nil or h.number ~= nil then
				return false
			end
		end
		return true
	end)())
check("…the farmstead's box the owner's Blender house's as before (44 × 14.5 × 34, its lot, door, curb unmoved)", (function(): boolean
	local f = Houses[1]
	return f.house.sx == 44 and f.house.sy == 14.5 and f.house.sz == 34 and f.house.z == 540 and f.door.z == 523 and f.curb.z == 492 and f.lot.z0 == 504
end)())
check("an old save's village house (8.9's Hlavní_n_5, Školní_e_20 …) is no place now: SandboxMap.house says none", SandboxMap.house("Hlavní_n_5") == nil
	and SandboxMap.house("Školní_e_20") == nil and SandboxMap.house("Smetanova_w_84") == nil)
do
	local bad: string? = nil
	for _, h in Houses do
		local b, w = h.box, h.house
		if math.abs(w.x - (b.x0 + b.x1) / 2) > EPS or math.abs(w.z - (b.z0 + b.z1) / 2) > EPS or math.abs(w.sx - (b.x1 - b.x0)) > EPS
			or math.abs(w.sz - (b.z1 - b.z0)) > EPS or w.y ~= SandboxMap.GroundTop or w.sy < 9 then
			bad = `{h.id}: its walls' box`
		elseif not (h.lot.x0 <= b.x0 and h.lot.x1 >= b.x1 and h.lot.z0 <= b.z0 and h.lot.z1 >= b.z1) or not inRect(h.lot, h.door.x, h.door.z) then
			bad = `{h.id}: its lot round it`
		end
		for _, r in Roads do
			if overlap(h.lot, r :: any) and not (h == SandboxMap.House and r.name == "Pražská") then
				bad = `{h.id}: its lot on {r.name}`
			end
		end
		for _, p in SandboxMap.Plots do
			if overlap(h.lot, p.rect) then
				bad = `{h.id}: its lot on plot {p.id}`
			end
		end
		for _, other in Houses do
			if other ~= h and overlap(h.lot, other.lot) then
				bad = `{h.id}: its lot on {other.id}'s`
			end
		end
		for _, l in SandboxMap.Landmarks do
			if overlap(h.lot, l :: any) then
				bad = `{h.id}: its lot on the landmark {l.id}`
			end
		end
		for _, f in SandboxMap.Fields do
			if overlap(h.lot, f :: any) then
				bad = `{h.id}: its lot on a field`
			end
		end
		if h.id ~= "old_mill" then -- (the mill's west wall stands on its millrace)
			for x = h.lot.x0, h.lot.x1, 2 do
				for z = h.lot.z0, h.lot.z1, 2 do
					if VillageScenery.streamDistance(x, z) < 0 then
						bad = `{h.id}: its lot in the stream`
					end
				end
			end
		end
	end
	check("each place's walls on its box (its middle, its size; walls 9 high at least), its lot round it and its door, clear of every road, plot, other lot, landmark, field and the stream",
		bad == nil, bad)
end
check("the world's Bounds the plan's (1 600 × 1 440)", same(SandboxMap.Bounds, Plan.bounds))
check("the roads the plan's, Pražská and Depot Row first (Pražská from Depot Row's far edge, as 8.0 laid it), each lane's rects and yard", (function(): boolean
	if #Roads ~= #Plan.roads or Roads[1].name ~= "Pražská" or Roads[2].name ~= "Depot Row" then
		return false
	end
	local used: { [number]: boolean } = {}
	for _, p in Plan.roads do
		local found = false
		for n, r in Roads do
			if not used[n] and r.name == p.name and same(r :: any, p.rect) and r.yard == p.yard then
				used[n], found = true, true
				break
			end
		end
		if not found then
			return false
		end
	end
	return same(Roads[1] :: any, { x0 = -14, x1 = 14, z0 = -74, z1 = 470 })
end)())
do
	local bad: string? = nil
	for index, h in Houses do
		if index > 1 then
			local yard: SandboxMap.Road? = nil
			for _, r in rectsOf(h.street) do
				if r.yard then
					yard = if yard then nil else r -- (one yard a lane)
				end
			end
			if not yard then
				bad = `{h.id}: no yard (or two) on {h.street}`
			elseif not inRect(yard :: any, h.curb.x, h.curb.z) or math.min(yard.x1 - yard.x0, yard.z1 - yard.z0) < 48 or not yard.lane then
				bad = `{h.id}: its yard ({yard.x1 - yard.x0} × {yard.z1 - yard.z0}) too small for the van to turn round, or its curb not in it`
			end
		end
		for _, r in rectsOf(h.street) do
			if not r.lane and index > 1 then
				bad = `{h.id}: {h.street} not a lane`
			elseif r.lane and math.min(r.x1 - r.x0, r.z1 - r.z0) >= 28 and not r.yard then
				bad = `{h.id}: {h.street} as wide as Pražská`
			end
		end
	end
	check("every place but the farmstead at the end of its own lane (narrower than Pražská, 22 wide: the van drives it), its curb in its yard there, 48 × 48 at least: the van turns round",
		bad == nil, bad)
end
check("SandboxMap.houseAt: a place by its lot (its curb within a margin), none on Depot Row", SandboxMap.houseAt(Houses[2].door.x, Houses[2].door.z, 0) == Houses[2]
	and SandboxMap.houseAt(Houses[6].curb.x, Houses[6].curb.z, 15) == Houses[6] and SandboxMap.houseAt(0, -60, 0) == nil and SandboxMap.house("nowhere") == nil
	and SandboxMap.house(nil) == nil)
do
	-- each its own spot: no two places' lots within 250 studs of each other
	local least, pair = math.huge, ""
	for i, a in Houses do
		for j, b in Houses do
			if j > i then
				local dx = math.max(a.lot.x0 - b.lot.x1, 0, b.lot.x0 - a.lot.x1)
				local dz = math.max(a.lot.z0 - b.lot.z1, 0, b.lot.z0 - a.lot.z1)
				local d = math.sqrt(dx * dx + dz * dz)
				if d < least then
					least, pair = d, `{a.id} and {b.id}`
				end
			end
		end
	end
	check(`the places spread apart, each its own spot (the nearest two, {pair}, {math.floor(least)} studs apart)`, least >= 250, least)
end

-- ── The curbs, the doors, the way there ───────────────────────────────────

do
	local half, width = SprinterLooks.Length / 2, SprinterLooks.Width / 2
	local bad: string? = nil
	for _, h in Houses do
		local c, d = h.curb, h.door
		local lx, lz = look(c.yaw)
		local bx, bz = c.x - lx * half, c.z - lz * half -- (its back)
		local nx, nz = c.x + lx * half, c.z + lz * half -- (its nose)
		local px, pz = -lz * width, lx * width -- (across it)
		for _, p in { { bx, bz }, { nx, nz }, { bx + px, bz + pz }, { bx - px, bz - pz }, { nx + px, nz + pz }, { nx - px, nz - pz } } do
			if not onAsphalt(Roads, p[1], p[2]) or not onAsphalt(Plan.roads, p[1], p[2]) then
				bad = `{h.id}: the van off the asphalt at {p[1]}, {p[2]}`
			end
		end
		if (bx - d.x) ^ 2 + (bz - d.z) ^ 2 >= (nx - d.x) ^ 2 + (nz - d.z) ^ 2 then
			bad = `{h.id}: the van's nose to the door`
		end
	end
	check("every curb on asphalt (SandboxMap's and the plan's): the Sprinter in its yard, its back, nose and corners on it, its back to the door",
		bad == nil, bad)
end
do
	local bad: string? = nil
	for index, h in Houses do
		local d, b = h.door, h.box
		local lx, lz = look(d.yaw)
		-- (on its box's face: a place's door 1.2 behind it, its look's)
		local inset = if index > 1 then Config.Village.Front - 0.3 else 0
		local fx, fz = d.x + lx * inset, d.z + lz * inset
		local onFace = (d.yaw == 0 and math.abs(fz - b.z0) < EPS) or (d.yaw == 180 and math.abs(fz - b.z1) < EPS) or (d.yaw == 90 and math.abs(fx - b.x0) < EPS)
			or (d.yaw == 270 and math.abs(fx - b.x1) < EPS)
		onFace = onFace and inRect(b, d.x, d.z)
		-- out of the door: the first road it meets is its road (its yard, within 30 studs), its curb on that road
		local met: string? = nil
		for t = 1, 30 do
			local x, z = d.x + lx * t, d.z + lz * t
			for _, r in Roads do
				if met == nil and inRect(r :: any, x, z) then
					met = r.name
				end
			end
			if met then
				break
			end
		end
		local curbOn = false
		for _, r in rectsOf(h.street) do
			curbOn = curbOn or inRect(r :: any, h.curb.x, h.curb.z)
		end
		if h.id == SandboxMap.House.id then
			-- (the farmstead looks out over the turnaround to Pražská's end)
			local t = SandboxMap.Turnaround
			if not onFace or d.yaw ~= 0 or (h.curb.x - t.x) ^ 2 + (h.curb.z - t.z) ^ 2 > t.r * t.r or #rectsOf(h.street) == 0 or math.abs(d.x - t.x) > EPS then
				bad = `{h.id}: its door`
			end
		elseif not onFace or met ~= h.street or not curbOn then
			bad = `{h.id}: its door looks at {met}, not {h.street}`
		end
	end
	check("every door on its box's face (a place's 1.2 behind it), looking out to its own road's yard (the farmstead's over the turnaround), its curb there", bad == nil, bad)
end
-- The roads reachable from Depot Row (rects that meet, by their index).
local function reach(roads: { any }): { [string]: boolean }
	local function rect(r: any): Rect
		return r.rect or r
	end
	local seen: { [number]: boolean } = {}
	for n, r in roads do
		seen[n] = r.name == "Depot Row" or nil
	end
	local grown = true
	while grown do
		grown = false
		for i, a in roads do
			if seen[i] then
				for j, b in roads do
					local ra, rb = rect(a), rect(b)
					if not seen[j] and ra.x0 <= rb.x1 + EPS and rb.x0 <= ra.x1 + EPS and ra.z0 <= rb.z1 + EPS and rb.z0 <= ra.z1 + EPS then
						seen[j] = true
						grown = true
					end
				end
			end
		end
	end
	local names: { [string]: boolean } = {}
	for n, r in roads do
		if seen[n] then
			names[r.name] = true
		else
			names["unreached " .. r.name] = true
		end
	end
	return names
end
check("every place reachable by road from Depot Row (the rects that meet: SandboxMap's and the plan's), no road on its own", (function(): boolean
	local mine, theirs = reach(Roads), reach(Plan.roads)
	for _, h in Houses do
		if not mine[h.street] or not theirs[h.street] then
			return false
		end
	end
	for name in mine do
		if string.sub(name, 1, 10) == "unreached " then
			return false
		end
	end
	return true
end)())
do
	local out: { number } = {}
	local bad: string? = nil
	local most = 0
	local longest = 0
	local shortest = math.huge
	for _, plot in SandboxMap.Plots do
		for _, h in Houses do
			for leg, way in { { plot.spawn.x, plot.spawn.z, h.curb.x, h.curb.z }, { h.curb.x, h.curb.z, plot.unload.x, plot.unload.z } } do
				local n = SandboxSteps.route(way[1], way[2], way[3], way[4], out, Config.SandboxGuide.Direct)
				most = math.max(most, n)
				-- (its last point the target, or within 3 studs of it: a point that close to the one before is left out)
				if n > SandboxSteps.MaxPoints or (out[n * 2 - 1] - way[3]) ^ 2 + (out[n * 2] - way[4]) ^ 2 > 9 then
					bad = `{h.id} from plot {plot.id}: {n} points`
				end
				local length = 0
				for i = 2, n do
					length += math.abs(out[i * 2 - 1] - out[i * 2 - 3]) + math.abs(out[i * 2] - out[i * 2 - 2])
				end
				if leg == 1 then
					longest, shortest = math.max(longest, length), math.min(shortest, length)
				end
				for i = 2, n - 1 do
					if not onAsphalt(Roads, out[i * 2 - 1], out[i * 2]) then
						bad = `{h.id} from plot {plot.id}: a turn off the road at {out[i * 2 - 1]}, {out[i * 2]}`
					end
					if i > 2 then -- (the legs between two road points: along a road's middle line, never slanting)
						local dx, dz = out[i * 2 - 1] - out[i * 2 - 3], out[i * 2] - out[i * 2 - 2]
						if math.abs(dx) > 1e-6 and math.abs(dz) > 1e-6 then
							local pts = {}
							for k = 1, n do
								table.insert(pts, `({out[k * 2 - 1]}, {out[k * 2]})`)
							end
							bad = `{h.id} from plot {plot.id}: a slanting leg along the roads: {table.concat(pts, " ")}`
						end
					end
				end
			end
		end
	end
	check(`the guide's path to every place's curb and back home along the roads: every turn on the asphalt, straight legs, {SandboxSteps.MaxPoints} points at most ({most} here)`,
		bad == nil, bad)
	check(`…a drive of {math.floor(shortest)} to {math.floor(longest)} studs from a plot to a place (about 15 to 45 s in the Sprinter)`, shortest >= 500 and longest <= 2200, `{shortest} {longest}`)
	local lone = SandboxMap.house("lone_house") :: SandboxMap.House
	local n = SandboxSteps.route(SandboxMap.Plots[1].spawn.x, SandboxMap.Plots[1].spawn.z, lone.curb.x, lone.curb.z, out, Config.SandboxGuide.Direct)
	local pts = {}
	for k = 1, n do
		table.insert(pts, `({out[k * 2 - 1]}, {out[k * 2]})`)
	end
	check("…to The Lone House: out to Depot Row, along it and Mill Lane to Hill Road, up Hill Road to its yard, across it to the curb", n == 5
		and out[4] == -60 and out[5] == -520 and out[6] == -60 and out[7] == -520 and out[8] == lone.curb.z and out[9] == lone.curb.x and out[10] == lone.curb.z,
		table.concat(pts, " "))
end

-- ── The contracts and the economy ──────────────────────────────────────────

do
	local count = 0
	for _ in S.Houses do
		count += 1
	end
	-- 9.5 the countryside: the contracts the six spots' (tests/countryside_test.luau: their families, places, kinds and
	-- clocks by id), a short place each ("by the Little Pond"), no longer a street's number. A house of the map without
	-- one (the family houses, until the countryside's map brings the spots) gets the fallback's card (Moving's
	-- SB.newContract): the map's houses either all with a contract or only the farmstead
	local bad: string? = nil
	local mapped = 0
	for _, h in Houses do
		local c = S.Houses[h.id]
		if not c then
			continue
		end
		mapped += 1
		if string.sub(c.Client, 1, 4) ~= "The " or string.sub(c.Client, -1) ~= "s" or #c.Client > Config.MoveStory.Limits.Client then
			bad = `{h.id}: its family ({c.Client})`
		elseif #c.Address == 0 or #c.Address > 24 then
			bad = `{h.id}: its address ({c.Address})`
		elseif not table.find(HouseLayout.Kinds, c.Kind) or (h == SandboxMap.House and c.Kind ~= h.kind) then
			bad = `{h.id}: its kind`
		elseif c.Time <= S.HordeAt or #c.Blurb == 0 or #c.Blurb > Config.MoveStory.Limits.Blurb then
			bad = `{h.id}: its clock or its words`
		end
	end
	check("a contract per place and no other (Config.Moving.Sandbox.Houses): a made-up Czech family, the address on its road, its plan's kind, its clock past the horde's",
		bad == nil and count == #Houses and mapped == #Houses, bad or `{mapped} of {#Houses} on the map`)
	local families: { [string]: boolean } = {}
	local distinct = true
	for _, c in S.Houses do
		distinct = distinct and not families[c.Client]
		families[c.Client] = true
	end
	check("…every family its own (The Nováks the farmstead's)", distinct and S.Houses[SandboxMap.House.id].Client == "The Nováks")
end
do
	local F = Config.Furniture
	local big, house = F.Big, F
	check("the economy by Config.Furniture: a house holds fewer pieces than the big house (Spots and collectibles: its most under the farmstead's least)",
		house.Spots[2] + house.Collectibles.Count[2] < big.Spots[1] + big.Collectibles.Count[1] and house.Stars <= big.Stars
			and house.Collectibles.Legendary <= big.Collectibles.Legendary, `{house.Spots[2]} + {house.Collectibles.Count[2]} vs {big.Spots[1]} + {big.Collectibles.Count[1]}`)
	-- the minutes a piece at the most pieces: a house no rush beside the farmstead, nor a stroll
	local farm = S.Houses[SandboxMap.House.id]
	local farmPace = farm.Time / (big.Spots[2] + big.Collectibles.Count[2])
	-- (9.5: every other contract by its kind's numbers: a family house's, or the countryside's own)
	local bad: string? = nil
	for id, c in S.Houses do
		if id == SandboxMap.House.id then
			continue
		end
		local own = if c.Kind == "house" then house else F.Countryside[c.Kind]
		local pace = c.Time / (own.Spots[2] + own.Collectibles.Count[2])
		if c.Time >= farm.Time or pace < farmPace * 0.9 or pace > farmPace * 1.5 then
			bad = `{id}: {c.Time / 60} min, {pace} s a piece against {farmPace}`
		end
	end
	check("…every other house's clock shorter than the farmstead's, about the same time a piece (0.9 – 1.5 ×)", bad == nil, bad)
	-- the plans themselves (HouseLayout.plan, the seeds 1 … 12 of each kind): every family house's pieces fewer than any
	-- big one's
	local mostHouse, leastBig = 0, math.huge
	for seed = 1, 12 do
		mostHouse = math.max(mostHouse, #HouseLayout.plan(seed, "house").spots)
		leastBig = math.min(leastBig, #HouseLayout.plan(seed, "big").spots)
	end
	check(`…and the plans: a house's pieces (at most {mostHouse}) fewer than the big house's (at least {leastBig})`, mostHouse < leastBig, `{mostHouse} {leastBig}`)
end

-- ── The guide per place ─────────────────────────────────────────────────────

do
	local steps = SandboxSteps.Steps
	local bad: string? = nil
	for _, h in Houses do
		local state: any = { house = h.id }
		local drive, back = SandboxSteps.words(steps.drive, state), SandboxSteps.words(steps.back, state)
		if drive ~= `Drive to {h.name} on {h.street}` or back ~= `Drive back to {h.name} on {h.street} for more, or FINISH` then
			bad = drive
		elseif SandboxSteps.detail(steps.drive, state) ~= h.id then
			bad = `{h.id}: detail`
		elseif not SandboxSteps.atHouse(h.curb.x, h.curb.z, Config.SandboxGuide.HouseMargin, h.id) or not SandboxSteps.atHouse(h.door.x, h.door.z, 0, h.id) then
			bad = `{h.id}: not at its own house`
		end
		for _, other in Houses do
			if other ~= h and SandboxSteps.atHouse(other.door.x, other.door.z, Config.SandboxGuide.HouseMargin, h.id) then
				bad = `{h.id}: at {other.id} too`
			end
		end
	end
	check("the guide's drive steps name the move's place on its road (\"Drive to The Pond Cabin on Pond Lane\"), at the place by its own lot only", bad == nil, bad)
	check("…no house known (or an old save's village house): the farmstead's words, as before", SandboxSteps.words(steps.drive, {} :: any) == "Drive to The Old Farmstead on Pražská"
		and SandboxSteps.houseWords("nowhere") == "The Old Farmstead on Pražská" and SandboxSteps.houseWords("Hlavní_n_5") == "The Old Farmstead on Pražská"
		and SandboxSteps.atHouse(0, 523, 0))
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
