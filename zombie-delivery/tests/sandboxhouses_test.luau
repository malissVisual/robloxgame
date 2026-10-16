-- Jinočany step 1 (design/jinocany/NAVRH.md §2, §3, §6): shared/SandboxMap.luau's Houses (the six houses to empty), its
-- Bounds and Roads against design/jinocany/plan.json (JinocanyPlan.luau, tests/run_tests.py writes it from the plan),
-- and their contracts (Config.Moving.Sandbox.Houses) with the economy's numbers (Config.Furniture, shared/HouseLayout.luau):
--   * the data: the plan's six (`enter`, in its order: the farmstead first, SandboxMap.House) with their ids, boxes,
--     doors, curbs and yaws as the plan has them (a family house's door its village look's: shared/VillageLooks.luau's
--     door spot, Config.Village.Front less the door's 0.3 behind the plan's), their streets and looks the plan's village
--     houses'; the back door only
--     the farmstead's; each house's walls' box on its box, its lot round it up to its street, clear of every road, plot
--     and other lot; the world's Bounds and its step-1 roads the plan's (Pražská from Depot Row's far edge, 8.0's)
--   * every curb on asphalt with the van's back to the door (the Sprinter across the street, its back and nose and its
--     four corners on it, the back nearer the door: plan.py's check), every door on its box's face looking at its street
--     (its curb in that street), every house reachable by road from Depot Row (the roads that meet, both SandboxMap's and
--     the plan's) and the guide's path to every curb along them (SandboxSteps.route)
--   * the contracts: one per house and no other, a made-up Czech family each, a short place (9.5 the countryside's: "by
--     the Little Pond"), its plan's kind (big the farmstead; 9.5 the spots' own: HouseLayout's kinds), its clock past the
--     horde's (9.5: until the countryside's map only the farmstead's on the map, the spots' to come); the economy sane: a family
--     house holds fewer pieces than the big house (Config.Furniture's Spots and collectibles, and the plans themselves:
--     HouseLayout.plan), gets less time, about the same minutes a piece
--   * the guide's words and places per house: "Drive to The Linden House on Hlavní", at the house by its own lot
-- Run with tests/run_tests.py.
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local SandboxSteps = require("./SandboxSteps")
local SprinterLooks = require("./SprinterLooks")
local HouseLayout = require("./HouseLayout")
local VillageLooks = require("./VillageLooks")
local VillageScenery = require("./VillageScenery")
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
local planRoads: { any } = {}
for _, r in Plan.roads do
	if r.step == 1 then
		table.insert(planRoads, r)
	end
end

-- ── The data against the plan ─────────────────────────────────────────────

check("six houses to empty, the plan's (`enter`), in its order; the first the farmstead, SandboxMap.House", #Houses == 6 and #Plan.enter == 6
	and Houses[1] == SandboxMap.House and Houses[1].id == "sandbox_house" and Houses[1].name == "The Old Farmstead")
-- (Jinočany: a family house's door is its village look's, VillageLooks.doorSpots': just outside its door's piece, the
-- body's front wall Config.Village.Front in from the box's face; DOOR_IN behind the plan's door, along its look)
local DOOR_IN = Config.Village.Front - 0.3
local spots: { [string]: VillageLooks.DoorSpot } = {}
for _, placed in VillageScenery.houses(VillageScenery.enter()) do
	local h = VillageScenery.emptied(placed)
	if h then
		local unit = if placed.kind == "row" then placed.opts.richUnit else nil
		for _, spot in VillageLooks.doorSpots(VillageLooks.house(placed.kind, placed.box, placed.yaw, placed.seed, placed.opts), placed.box, placed.yaw) do
			if unit == nil or spot.unit == unit then
				spots[h.id] = spot
			end
		end
	end
end
do
	local bad: string? = nil
	local names: { [string]: boolean } = {}
	for index, h in Houses do
		local p = Plan.enter[index]
		local v = Plan.village[h.id]
		local d, c = h.door, h.curb
		local inset = if index > 1 then DOOR_IN else 0
		local ox, oz = look(p.door.yaw)
		local spot = spots[h.id]
		if h.id ~= p.id or h.kind ~= p.kind or not same(h.box, p.box) then
			bad = `{h.id}: its id, kind or box`
		elseif math.abs(d.x - (p.door.x - ox * inset)) > EPS or math.abs(d.z - (p.door.z - oz * inset)) > EPS or d.yaw ~= p.door.yaw
			or c.x ~= p.curb.x or c.z ~= p.curb.z or c.yaw ~= p.curb.yaw then
			bad = `{h.id}: its door or curb`
		elseif index > 1 and (spot == nil or math.abs(spot.x - d.x) > 1e-3 or math.abs(spot.z - d.z) > 1e-3 or spot.yaw ~= d.yaw) then
			bad = `{h.id}: its door not its village look's ({spot and spot.x}, {spot and spot.z})`
		elseif d.y ~= SandboxMap.GroundTop or c.y ~= SandboxMap.RoadTop or h.yaw ~= d.yaw then
			bad = `{h.id}: its door's or curb's height, its yaw`
		elseif index > 1 and (v == nil or v.street ~= h.street or v.kind ~= h.look or not same(v.box, h.box)) then
			bad = `{h.id}: not the plan's village house (its street, look)`
		elseif names[h.name] or names[h.id] then
			bad = `{h.id}: a name twice`
		elseif SandboxMap.house(h.id) ~= h then
			bad = `{h.id}: SandboxMap.house`
		end
		names[h.name], names[h.id] = true, true
	end
	check("…each one's id, kind, box, door (a family house's its village look's, 1.2 in) and curb the plan's; its street and look the plan's village house's; names each its own", bad == nil, bad)
end
check("the farmstead: big, on Pražská, its look its own, its back door in its back wall; the family houses: kind house, no back door",
	(function(): boolean
		local f = Houses[1]
		if f.kind ~= "big" or f.street ~= "Pražská" or f.look ~= "farmstead" or f.back == nil or f.back.z ~= f.box.z1 or f.number ~= nil then
			return false
		end
		for index = 2, #Houses do
			local h = Houses[index]
			if h.kind ~= "house" or h.back ~= nil or (h.look ~= "old" and h.look ~= "row") or type(h.number) ~= "number" then
				return false
			end
		end
		return true
	end)())
check("…the farmstead's box the owner's Blender house's as before (44 × 14.5 × 34, its lot, door, curb unmoved)", (function(): boolean
	local f = Houses[1]
	return f.house.sx == 44 and f.house.sy == 14.5 and f.house.sz == 34 and f.house.z == 540 and f.door.z == 523 and f.curb.z == 492 and f.lot.z0 == 504
end)())
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
			if overlap(h.lot, r :: any) then
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
		for id, v in Plan.village do
			if id ~= h.id and overlap(h.box, v.box) then
				bad = `{h.id}: on the village house {id}`
			end
		end
	end
	check("each house's walls on its box (its middle, its size; walls 9 high at least), its lot round it and its door, clear of every road, plot, other lot and village house",
		bad == nil, bad)
end
check("the world's Bounds the plan's (1 600 × 1 440)", same(SandboxMap.Bounds, Plan.bounds))
check("the roads the plan's step-1 roads, Pražská and Depot Row first (Pražská from Depot Row's far edge, as 8.0 laid it)", (function(): boolean
	if #Roads ~= #planRoads or Roads[1].name ~= "Pražská" or Roads[2].name ~= "Depot Row" then
		return false
	end
	for _, p in planRoads do
		local found = false
		for _, r in Roads do
			if r.name == p.name then
				local want = if r.name == "Pražská" then { x0 = p.rect.x0, x1 = p.rect.x1, z0 = Roads[2].z0, z1 = p.rect.z1 } else p.rect
				found = same(r :: any, want)
			end
		end
		if not found then
			return false
		end
	end
	return true
end)())
check("SandboxMap.houseAt: a house by its lot (its curb within a margin), none on Depot Row", SandboxMap.houseAt(Houses[2].door.x, Houses[2].door.z, 0) == Houses[2]
	and SandboxMap.houseAt(Houses[6].curb.x, Houses[6].curb.z, 15) == Houses[6] and SandboxMap.houseAt(0, -60, 0) == nil and SandboxMap.house("nowhere") == nil
	and SandboxMap.house(nil) == nil)

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
		for _, roads in { Roads :: { any }, planRoads } do
			for _, p in { { bx, bz }, { nx, nz }, { bx + px, bz + pz }, { bx - px, bz - pz }, { nx + px, nz + pz }, { nx - px, nz - pz } } do
				if not onAsphalt(roads, p[1], p[2]) then
					bad = `{h.id}: the van off the asphalt at {p[1]}, {p[2]}`
				end
			end
		end
		if (bx - d.x) ^ 2 + (bz - d.z) ^ 2 >= (nx - d.x) ^ 2 + (nz - d.z) ^ 2 then
			bad = `{h.id}: the van's nose to the door`
		end
	end
	check("every curb on asphalt (SandboxMap's and the plan's): the Sprinter across its street, its back, nose and corners on it, its back to the door",
		bad == nil, bad)
end
do
	local bad: string? = nil
	for index, h in Houses do
		local d, b = h.door, h.box
		local lx, lz = look(d.yaw)
		-- (on its box's face: a family house's DOOR_IN behind it, its village look's)
		local inset = if index > 1 then DOOR_IN else 0
		local fx, fz = d.x + lx * inset, d.z + lz * inset
		local onFace = (d.yaw == 0 and math.abs(fz - b.z0) < EPS) or (d.yaw == 180 and math.abs(fz - b.z1) < EPS) or (d.yaw == 90 and math.abs(fx - b.x0) < EPS)
			or (d.yaw == 270 and math.abs(fx - b.x1) < EPS)
		onFace = onFace and inRect(b, d.x, d.z)
		-- out of the door: the first road it meets is its street (within 30 studs), its curb on that street
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
		local street: any = nil
		for _, r in Roads do
			if r.name == h.street then
				street = r
			end
		end
		if h.id == SandboxMap.House.id then
			-- (the farmstead looks out over the turnaround to Pražská's end)
			local t = SandboxMap.Turnaround
			if not onFace or d.yaw ~= 0 or (h.curb.x - t.x) ^ 2 + (h.curb.z - t.z) ^ 2 > t.r * t.r or street == nil or math.abs(d.x - t.x) > EPS then
				bad = `{h.id}: its door`
			end
		elseif not onFace or met ~= h.street or street == nil or not inRect(street, h.curb.x, h.curb.z) then
			bad = `{h.id}: its door looks at {met}, not {h.street}`
		end
	end
	check("every door on its box's face (a family house's 1.2 behind it), looking out to its own street (the farmstead's over the turnaround), its curb in that street", bad == nil, bad)
end
-- The roads reachable from Depot Row (rects that meet), by name.
local function reach(roads: { any }): { [string]: boolean }
	local function rect(r: any): Rect
		return r.rect or r
	end
	local seen: { [string]: boolean } = { ["Depot Row"] = true }
	local grown = true
	while grown do
		grown = false
		for _, a in roads do
			if seen[a.name] then
				for _, b in roads do
					local ra, rb = rect(a), rect(b)
					if not seen[b.name] and ra.x0 <= rb.x1 + EPS and rb.x0 <= ra.x1 + EPS and ra.z0 <= rb.z1 + EPS and rb.z0 <= ra.z1 + EPS then
						seen[b.name] = true
						grown = true
					end
				end
			end
		end
	end
	return seen
end
check("every house reachable by road from Depot Row (the roads that meet: SandboxMap's and the plan's step-1 roads)", (function(): boolean
	local mine, theirs = reach(Roads), reach(planRoads)
	for _, h in Houses do
		if not mine[h.street] or not theirs[h.street] then
			return false
		end
	end
	for _, r in Roads do -- (no road on its own either)
		if not mine[r.name] then
			return false
		end
	end
	return true
end)())
do
	local out: { number } = {}
	local bad: string? = nil
	local most = 0
	for _, plot in SandboxMap.Plots do
		for _, h in Houses do
			for _, way in { { plot.spawn.x, plot.spawn.z, h.curb.x, h.curb.z }, { h.curb.x, h.curb.z, plot.unload.x, plot.unload.z } } do
				local n = SandboxSteps.route(way[1], way[2], way[3], way[4], out, Config.SandboxGuide.Direct)
				most = math.max(most, n)
				-- (its last point the target, or within 3 studs of it: a point that close to the one before is left out)
				if n > SandboxSteps.MaxPoints or (out[n * 2 - 1] - way[3]) ^ 2 + (out[n * 2] - way[4]) ^ 2 > 9 then
					bad = `{h.id} from plot {plot.id}: {n} points`
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
	check(`the guide's path to every house's curb and back home along the roads: every turn on the asphalt, straight legs, {SandboxSteps.MaxPoints} points at most ({most} here)`,
		bad == nil, bad)
	local n = SandboxSteps.route(SandboxMap.Plots[1].spawn.x, SandboxMap.Plots[1].spawn.z, Houses[4].curb.x, Houses[4].curb.z, out, Config.SandboxGuide.Direct)
	local pts = {}
	for k = 1, n do
		table.insert(pts, `({out[k * 2 - 1]}, {out[k * 2]})`)
	end
	check("…to the Schoolmaster's House: out to Depot Row, along it and Hlavní to Školní, up Školní to its curb (a stud off Školní's middle: left out)", n == 4
		and out[4] == -60 and out[5] == -560 and out[6] == -60 and out[7] == -560 and out[8] == Houses[4].curb.z, table.concat(pts, " "))
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
	check("a contract per house and no other (Config.Moving.Sandbox.Houses; 9.5 until the countryside's map only the farmstead's on it): a made-up Czech family, a short place, its plan's kind, its clock past the horde's",
		bad == nil and count == #Houses and (mapped == #Houses or (mapped == 1 and S.Houses[SandboxMap.House.id] ~= nil)), bad or `{mapped} of {#Houses} on the map`)
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
	check("the economy by Config.Furniture: a family house holds fewer pieces than the big house (Spots and collectibles: its most under the farmstead's least)",
		house.Spots[2] + house.Collectibles.Count[2] < big.Spots[1] + big.Collectibles.Count[1] and house.Stars <= big.Stars
			and house.Collectibles.Legendary <= big.Collectibles.Legendary, `{house.Spots[2]} + {house.Collectibles.Count[2]} vs {big.Spots[1]} + {big.Collectibles.Count[1]}`)
	-- the minutes a piece at the most pieces: a family house no rush beside the farmstead, nor a stroll
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
	check(`…and the plans: a family house's pieces (at most {mostHouse}) fewer than the big house's (at least {leastBig})`, mostHouse < leastBig, `{mostHouse} {leastBig}`)
end

-- ── The guide per house ─────────────────────────────────────────────────────

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
	check("the guide's drive steps name the move's house on its street (\"Drive to The Linden House on Hlavní\"), at the house by its own lot only", bad == nil, bad)
	check("…no house known: the farmstead's words, as before", SandboxSteps.words(steps.drive, {} :: any) == "Drive to The Old Farmstead on Pražská"
		and SandboxSteps.houseWords("nowhere") == "The Old Farmstead on Pražská" and SandboxSteps.atHouse(0, 523, 0))
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
