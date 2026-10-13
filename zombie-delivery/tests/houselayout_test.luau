-- 7.0 prototype, the moving: the house plans (shared/HouseLayout.luau, Config.Furniture) in the standalone Luau CLI, on
-- the recorder's Vector3 and CFrame (tools/fixtures/item-mock.luau): a plan is the same for the same seed; it has 6-8
-- rooms of every kind, a 7-wide front door and doorways at least 6 wide joining every room, corridors at least 6 wide,
-- a ceiling about 12 up; 18-24 pieces, each in its room (from the room's recipe), on the floor, none overlapping another
-- or a fixture or standing in a doorway's way, exactly 3 ★ (the sentimental ones first); every piece can be carried
-- out of the front door (a grid walk of this test's own, the piece's narrow side wide, past everything else); the
-- seeds give different houses (mirrored, other room orders, other pieces and places).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local M = require("./ItemMock")
local Config = require("./Config")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Furniture
local Items = FurnitureLooks.Items
local SEEDS = 40 -- every check
local WALKS = 12 -- the grid walk (the slow one) on this many of them

type Rect = { x0: number, z0: number, x1: number, z1: number }
local function rect(x0: number, z0: number, x1: number, z1: number): Rect
	return { x0 = math.min(x0, x1), z0 = math.min(z0, z1), x1 = math.max(x0, x1), z1 = math.max(z0, z1) }
end
local function apart(a: Rect, b: Rect): number -- the gap between two rects (negative: they overlap)
	local dx = math.max(a.x0 - b.x1, b.x0 - a.x1)
	local dz = math.max(a.z0 - b.z1, b.z0 - a.z1)
	return math.max(dx, dz)
end
local function dist(x: number, z: number, r: Rect): number
	local dx = math.max(r.x0 - x, 0, x - r.x1)
	local dz = math.max(r.z0 - z, 0, z - r.z1)
	return math.sqrt(dx * dx + dz * dz)
end
local function footprint(s: any): Rect
	local ex, ez = HouseLayout.extent(s.item, s.turn)
	local p = s.at.Position
	return rect(p.X - ex / 2, p.Z - ez / 2, p.X + ex / 2, p.Z + ez / 2)
end
local function fixtureRect(f: any): Rect
	local turned = (f.turn % 180) ~= 0
	local ex, ez = if turned then f.size.Z else f.size.X, if turned then f.size.X else f.size.Z
	local p = f.at.Position
	return rect(p.X - ex / 2, p.Z - ez / 2, p.X + ex / 2, p.Z + ez / 2)
end
local function signature(plan: any): string
	local out = { plan.kind, tostring(plan.mirrored), string.format("%.2f,%.2f,%.2f", plan.size.X, plan.size.Y, plan.size.Z) }
	for _, r in plan.rooms do
		table.insert(out, string.format("%s %.1f %.1f %.1f %.1f", r.id, r.min.X, r.min.Z, r.max.X, r.max.Z))
	end
	for _, d in plan.doors do
		table.insert(out, string.format("door %.1f %.1f %d %s", d.at.X, d.at.Z, d.width, d.axis))
	end
	for _, s in plan.spots do
		local p = s.at.Position
		table.insert(out, string.format("%d %s %s %.2f %.2f %.2f %d %s %d", s.id, s.item, s.room, p.X, p.Y, p.Z, s.turn, tostring(s.star), s.variant))
	end
	for _, f in plan.fixtures do
		local p = f.at.Position
		table.insert(out, string.format("%s %s %.2f %.2f %.2f", f.kind, f.room, p.X, p.Y, p.Z))
	end
	return table.concat(out, "\n")
end

-- ── The grid walk: can a piece be carried out of the front door? ─────────────────
-- The floor is the rooms' insides and the doorways (each doorway a box through its wall); in the way: the solid
-- fixtures and every other piece. A point on a 1-stud lattice is clear for a piece when the point and the four points
-- `r` from it are on the floor and nothing in the way is closer than `r`, r = half its narrow side less half a stud
-- (a squeeze), at least half a stud. A walk from the piece's place over clear points must reach the front doorway.
local function walkOut(plan: any): { string }
	local floors: { Rect } = {}
	for _, r in plan.rooms do
		table.insert(floors, rect(r.min.X, r.min.Z, r.max.X, r.max.Z))
	end
	local half = plan.wall / 2 + 0.01
	for _, d in plan.doors do
		local w = d.width / 2
		table.insert(floors, if d.axis == "X" then rect(d.at.X - w, d.at.Z - half, d.at.X + w, d.at.Z + half) else rect(d.at.X - half, d.at.Z - w, d.at.X + half, d.at.Z + w))
	end
	local front = plan.doors[1]
	-- (the porch outside the front door: you carry the piece out onto it)
	table.insert(floors, rect(front.at.X - front.width / 2, front.at.Z - 4, front.at.X + front.width / 2, front.at.Z))
	local function onFloor(x: number, z: number): boolean
		for _, r in floors do
			if x >= r.x0 - 1e-6 and x <= r.x1 + 1e-6 and z >= r.z0 - 1e-6 and z <= r.z1 + 1e-6 then
				return true
			end
		end
		return false
	end
	local solids: { Rect } = {}
	for _, f in plan.fixtures do
		if f.solid then
			table.insert(solids, fixtureRect(f))
		end
	end
	local pieces: { Rect } = {}
	for _, s in plan.spots do
		table.insert(pieces, footprint(s))
	end
	local x0, z0 = math.floor(plan.min.X), math.floor(plan.min.Z)
	local nx, nz = math.ceil(plan.max.X) - x0 + 1, math.ceil(plan.max.Z) - z0 + 1
	-- per lattice point: the floor, the nearest fixture, the two nearest pieces
	local floorAt, fixtureAt, near1, near1i, near2 = {}, {}, {}, {}, {}
	for j = 0, nz - 1 do
		for i = 0, nx - 1 do
			local k = j * nx + i + 1
			local x, z = x0 + i, z0 + j
			floorAt[k] = onFloor(x, z)
			local f = math.huge
			for _, r in solids do
				f = math.min(f, dist(x, z, r))
			end
			fixtureAt[k] = f
			local a, ai, b = math.huge, 0, math.huge
			for n, r in pieces do
				local d = dist(x, z, r)
				if d < a then
					a, ai, b = d, n, a
				elseif d < b then
					b = d
				end
			end
			near1[k], near1i[k], near2[k] = a, ai, b
		end
	end
	local floorMemo: { [string]: boolean } = {}
	local function clear(i: number, j: number, own: number, r: number): boolean
		if i < 0 or j < 0 or i >= nx or j >= nz then
			return false
		end
		local k = j * nx + i + 1
		if not floorAt[k] or fixtureAt[k] < r then
			return false
		end
		local other = if near1i[k] == own then near2[k] else near1[k]
		if other < r then
			return false
		end
		local key = `{k}:{r}`
		local memo = floorMemo[key]
		if memo == nil then
			local x, z = x0 + i, z0 + j
			memo = onFloor(x + r, z) and onFloor(x - r, z) and onFloor(x, z + r) and onFloor(x, z - r)
			floorMemo[key] = memo
		end
		return memo
	end
	local stuck: { string } = {}
	for n, s in plan.spots do
		local def = Items[s.item]
		local r = math.max(0.5, math.min(def.size.X, def.size.Z) / 2 - 0.5)
		local fp = pieces[n]
		local queue, seen = {}, {}
		for j = math.ceil(fp.z0) - z0, math.floor(fp.z1) - z0 do
			for i = math.ceil(fp.x0) - x0, math.floor(fp.x1) - x0 do
				if clear(i, j, n, r) then
					local k = j * nx + i + 1
					seen[k] = true
					table.insert(queue, { i, j })
				end
			end
		end
		local out, q = false, 1
		while q <= #queue do
			local i, j = queue[q][1], queue[q][2]
			q += 1
			local x, z = x0 + i, z0 + j
			if z <= front.at.Z + 0.01 and math.abs(x - front.at.X) <= front.width / 2 then
				out = true
				break
			end
			for _, step in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local a, b = i + step[1], j + step[2]
				local k = b * nx + a + 1
				if not seen[k] and clear(a, b, n, r) then
					seen[k] = true
					table.insert(queue, { a, b })
				end
			end
		end
		if not out then
			table.insert(stuck, `{s.id} {s.item} in the {s.room}`)
		end
	end
	return stuck
end

-- ── Every seed ─────────────────────────────────────────────────────────────────
local KINDS = {}
for _, k in FurnitureLooks.Rooms do
	KINDS[k] = true
end
local recipeHas: { [string]: { [string]: boolean } } = {}
for room, entries in HouseLayout.Recipes do
	recipeHas[room] = { box = true } -- (a filler box may go in any room)
	for _, e in entries do
		recipeHas[room][e.item] = true
	end
end

local mirrors, orders, itemSets, places = {}, {}, {}, {}
local slowest, totalTime = 0, 0
for seed = 1, SEEDS do
	local started = os.clock()
	local plan = HouseLayout.plan(seed, "house")
	local took = os.clock() - started
	slowest, totalTime = math.max(slowest, took), totalTime + took
	local again = HouseLayout.plan(seed, "house")
	local tag = `seed {seed}`
	check(`{tag}: the same seed, the same plan`, signature(plan) == signature(again))
	check(`{tag}: a house, its box (size {math.floor(plan.size.X)} × {math.floor(plan.size.Z)})`, plan.kind == "house" and plan.seed == seed
		and math.abs(plan.size.X - (plan.max.X - plan.min.X)) < 1e-6 and plan.size.X >= 50 and plan.size.X <= 90 and plan.size.Z >= 45 and plan.size.Z <= 80)
	mirrors[plan.mirrored] = true

	-- rooms
	local byId: { [string]: any } = {}
	local kinds: { [string]: boolean } = {}
	local okRooms = true
	for _, r in plan.rooms do
		okRooms = okRooms and byId[r.id] == nil and KINDS[r.kind] == true and r.max.X > r.min.X and r.max.Z > r.min.Z
			and math.abs(r.min.Y) < 1e-6 and r.max.Y >= 10 and r.max.Y <= 14
			and r.min.X >= plan.min.X and r.max.X <= plan.max.X and r.min.Z >= plan.min.Z and r.max.Z <= plan.max.Z
		byId[r.id] = r
		kinds[r.kind] = true
	end
	local allKinds = true
	for k in KINDS do
		allKinds = allKinds and kinds[k] == true
	end
	check(`{tag}: {#plan.rooms} rooms (6-8), every kind, inside the house, a ceiling about 12 up`, #plan.rooms >= 6 and #plan.rooms <= 8 and okRooms and allKinds)
	local overlap = false
	for a = 1, #plan.rooms do
		for b = a + 1, #plan.rooms do
			local ra, rb = plan.rooms[a], plan.rooms[b]
			overlap = overlap or apart(rect(ra.min.X, ra.min.Z, ra.max.X, ra.max.Z), rect(rb.min.X, rb.min.Z, rb.max.X, rb.max.Z)) < plan.wall - 1e-6
		end
	end
	check(`{tag}: the rooms do not overlap (a wall between them)`, not overlap)
	local narrow = {}
	for _, r in plan.rooms do
		if r.kind == "hall" and math.min(r.max.X - r.min.X, r.max.Z - r.min.Z) < 6 then
			table.insert(narrow, r.id)
		end
	end
	check(`{tag}: the hall and the corridor at least 6 wide`, #narrow == 0, table.concat(narrow, ", "))
	if seed == 1 then
		local rows = {}
		for _, r in plan.rooms do
			table.insert(rows, string.format("%s %.0f × %.0f", r.id, r.max.X - r.min.X, r.max.Z - r.min.Z))
		end
		print("(seed 1: " .. table.concat(rows, ", ") .. ")")
	end
	-- the back row's order (left to right)
	local back = {}
	for _, r in plan.rooms do
		if r.min.Z > byId.corridor.max.Z then
			table.insert(back, r)
		end
	end
	table.sort(back, function(a: any, b: any): boolean
		return a.min.X < b.min.X
	end)
	local names = {}
	for _, r in back do
		table.insert(names, r.id)
	end
	orders[table.concat(names, ",")] = true

	-- doors
	local front = plan.doors[1]
	check(`{tag}: the front door ({front.width} wide) into the hall`, front.front == true and front.width == T.FrontDoor and front.axis == "X"
		and math.abs(front.at.X) < 1e-6 and math.abs(front.at.Z) < 1e-6 and front.rooms[1] == "hall" and front.rooms[2] == "outside")
	local badDoors = {}
	local links: { [string]: { string } } = {}
	for n, d in plan.doors do
		if n > 1 then
			local a, b = byId[d.rooms[1]], byId[d.rooms[2]]
			local ok = d.width >= T.Door and not d.front and a ~= nil and b ~= nil
			if ok then
				-- on the wall between them: the opening inside both rooms' sides, the rooms on its two sides
				local w = d.width / 2
				for _, r in { a, b } do
					if d.axis == "X" then
						ok = ok and d.at.X - w >= r.min.X - 1e-6 and d.at.X + w <= r.max.X + 1e-6
							and (math.abs(r.min.Z - (d.at.Z + plan.wall / 2)) < 1e-6 or math.abs(r.max.Z - (d.at.Z - plan.wall / 2)) < 1e-6)
					else
						ok = ok and d.at.Z - w >= r.min.Z - 1e-6 and d.at.Z + w <= r.max.Z + 1e-6
							and (math.abs(r.min.X - (d.at.X + plan.wall / 2)) < 1e-6 or math.abs(r.max.X - (d.at.X - plan.wall / 2)) < 1e-6)
					end
				end
				links[a.id] = links[a.id] or {}
				links[b.id] = links[b.id] or {}
				table.insert(links[a.id], b.id)
				table.insert(links[b.id], a.id)
			end
			if not ok then
				table.insert(badDoors, `{n}: {d.rooms[1]}-{d.rooms[2]} {d.width}`)
			end
		end
	end
	check(`{tag}: {#plan.doors - 1} doorways, each at least {T.Door} wide on the wall between its rooms`, #badDoors == 0, table.concat(badDoors, "; "))
	local reached, queue = { hall = true }, { "hall" }
	local q = 1
	while q <= #queue do
		for _, other in links[queue[q]] or {} do
			if not reached[other] then
				reached[other] = true
				table.insert(queue, other)
			end
		end
		q += 1
	end
	check(`{tag}: every room is reached from the hall through doorways`, #queue == #plan.rooms)
	check(`{tag}: the doorways are tall enough ({plan.doorHeight} under a ceiling of {plan.ceiling})`, plan.doorHeight >= 8 and plan.doorHeight < plan.ceiling)

	-- spots
	local n = #plan.spots
	check(`{tag}: {n} pieces ({T.Spots[1]}-{T.Spots[2]})`, n >= T.Spots[1] and n <= T.Spots[2])
	local badSpots, stars, sentimentalPlaced, starredSentimental = {}, 0, 0, 0
	local set = {}
	for index, s in plan.spots do
		local def = Items[s.item]
		local room = byId[s.room]
		local p = s.at.Position
		local fp = footprint(s)
		local r = s.at.R
		local turnOk = s.turn % 90 == 0 and math.abs(r[1] - math.cos(math.rad(s.turn))) < 1e-6 and math.abs(r[3] - math.sin(math.rad(s.turn))) < 1e-6
		local ok = s.id == index and def ~= nil and room ~= nil and turnOk and math.abs(p.Y - def.size.Y / 2) < 1e-6
			and recipeHas[s.room] ~= nil and recipeHas[s.room][s.item] == true
			and fp.x0 >= room.min.X - 1e-6 and fp.x1 <= room.max.X + 1e-6 and fp.z0 >= room.min.Z - 1e-6 and fp.z1 <= room.max.Z + 1e-6
		if not ok then
			table.insert(badSpots, `{s.id} {s.item} in {s.room}`)
		end
		if s.star then
			stars += 1
		end
		if def and def.sentimental then
			sentimentalPlaced += 1
			if s.star then
				starredSentimental += 1
			end
		end
		table.insert(set, s.item)
		places[string.format("%s %.1f %.1f", s.item, p.X, p.Z)] = true
	end
	check(`{tag}: every piece in its room, from the room's recipe, on the floor, turned square`, #badSpots == 0, table.concat(badSpots, "; "))
	check(`{tag}: exactly {T.Stars} ★, the sentimental pieces first ({starredSentimental} of {sentimentalPlaced})`, stars == T.Stars
		and starredSentimental == math.min(sentimentalPlaced, T.Stars) and sentimentalPlaced >= 2)
	table.sort(set)
	itemSets[table.concat(set, ",")] = true

	-- nothing overlaps, nothing in a doorway's way
	local clash = {}
	for a = 1, n do
		local fa = footprint(plan.spots[a])
		for b = a + 1, n do
			if apart(fa, footprint(plan.spots[b])) < 0.25 then
				table.insert(clash, `{plan.spots[a].item}/{plan.spots[b].item}`)
			end
		end
		for _, f in plan.fixtures do
			if f.solid and apart(fa, fixtureRect(f)) < 0.2 then
				table.insert(clash, `{plan.spots[a].item}/{f.kind}`)
			end
		end
	end
	check(`{tag}: no two pieces overlap, nor a piece and a fixture`, #clash == 0, table.concat(clash, "; "))
	local blocking = {}
	for _, d in plan.doors do
		for _, id in d.rooms do
			local room = byId[id]
			if room then
				local w = d.width / 2
				local zone
				if d.axis == "X" then
					local into = if room.min.Z > d.at.Z then 1 else -1
					zone = rect(d.at.X - w, d.at.Z, d.at.X + w, d.at.Z + into * (plan.wall / 2 + 4))
				else
					local into = if room.min.X > d.at.X then 1 else -1
					zone = rect(d.at.X, d.at.Z - w, d.at.X + into * (plan.wall / 2 + 4), d.at.Z + w)
				end
				for _, s in plan.spots do
					if apart(zone, footprint(s)) < 0 then
						table.insert(blocking, `{s.item} in {id}`)
					end
				end
				for _, f in plan.fixtures do
					if f.solid and apart(zone, fixtureRect(f)) < 0 then
						table.insert(blocking, `{f.kind} in {id}`)
					end
				end
			end
		end
	end
	check(`{tag}: nothing stands in a doorway's way (4 studs either side)`, #blocking == 0, table.concat(blocking, "; "))

	-- the way in and out
	local e = plan.entry.Position
	local inHall = e.X > byId.hall.min.X and e.X < byId.hall.max.X and e.Z > byId.hall.min.Z and e.Z < byId.hall.max.Z
	local clearEntry = true
	for _, s in plan.spots do
		clearEntry = clearEntry and dist(e.X, e.Z, footprint(s)) >= 1.5
	end
	check(`{tag}: you come in inside the front door, facing into the house, nothing in your way`, inHall and clearEntry and plan.entry.R[9] < -0.99 and e.Y > 1)
	check(`{tag}: the exit is the front door's inside`, math.abs(plan.exit.X) < 1e-6 and plan.exit.Z >= 0 and plan.exit.Z <= 1 and plan.exit.Y > 0)

	-- every piece gets out: the layout's own check, and (on some seeds) this test's walk
	local stuck = HouseLayout.stuck(plan)
	check(`{tag}: HouseLayout.stuck finds no piece stuck`, #stuck == 0, table.concat(stuck, ", "))
	if seed <= WALKS then
		local walked = walkOut(plan)
		check(`{tag}: every piece can be carried out of the front door (grid walk)`, #walked == 0, table.concat(walked, "; "))
	end

	-- windows on the outer walls' inside faces, facing in
	local badWindows = 0
	for _, w in plan.windows do
		local room = byId[w.room]
		local onWall = room ~= nil and ((w.normal.Z > 0.5 and math.abs(w.at.Z - room.min.Z) < 1e-6) or (w.normal.Z < -0.5 and math.abs(w.at.Z - room.max.Z) < 1e-6)
			or (w.normal.X > 0.5 and math.abs(w.at.X - room.min.X) < 1e-6) or (w.normal.X < -0.5 and math.abs(w.at.X - room.max.X) < 1e-6))
		local outerWall = math.abs(w.at.Z - plan.min.Z - plan.wall) < 0.6 or math.abs(w.at.Z - plan.max.Z + plan.wall) < 0.6
			or math.abs(w.at.X - plan.min.X - plan.wall) < 0.6 or math.abs(w.at.X - plan.max.X + plan.wall) < 0.6
		if not (onWall and outerWall and w.at.Y - w.height / 2 >= 2 and w.at.Y + w.height / 2 < plan.ceiling) then
			badWindows += 1
		end
	end
	check(`{tag}: {#plan.windows} windows on the outer walls`, #plan.windows >= 6 and badWindows == 0)
	local kindsSeen = {}
	for _, f in plan.fixtures do
		kindsSeen[f.kind] = true
	end
	check(`{tag}: the kitchen, bathroom and garage fixtures are there`, kindsSeen.counter and kindsSeen.stove and kindsSeen.sink and kindsSeen.tub
		and kindsSeen.toilet and kindsSeen.basin and kindsSeen.workbench and kindsSeen.garage_door and kindsSeen.rug == true)
end

local function count(t: { [any]: boolean }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end
check("the seeds mirror the house both ways", mirrors[true] == true and mirrors[false] == true)
check(`the seeds give other back-row orders ({count(orders)})`, count(orders) >= 3)
check(`the seeds give other sets of pieces ({count(itemSets)} of {SEEDS})`, count(itemSets) >= SEEDS / 2)
check(`the pieces stand in many places ({count(places)})`, count(places) >= SEEDS * 8)
check(`a plan is quick to make (average {string.format("%.3f", totalTime / SEEDS)} s, slowest {string.format("%.3f", slowest)} s)`, totalTime / SEEDS < 0.5)

-- another kind falls back to a house (only "house" so far), a big or negative seed works
do
	local plan = HouseLayout.plan(7, "apartment")
	check("an unknown kind is a house for now", plan.kind == "house" and #plan.spots >= T.Spots[1] and table.find(HouseLayout.Kinds, "house") ~= nil)
	local big = HouseLayout.plan(2 ^ 40 + 0.5, "house")
	local negative = HouseLayout.plan(-12345, "house")
	check("a huge or a negative seed makes a plan", #big.spots >= T.Spots[1] and #negative.spots >= T.Spots[1])
end
local _ = M

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
