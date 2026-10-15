-- 7.0 prototype, the moving: the house plans (shared/HouseLayout.luau, Config.Furniture) in the standalone Luau CLI, on
-- the recorder's Vector3 and CFrame (tools/fixtures/item-mock.luau): a plan is the same for the same seed; it has 6-8
-- rooms of every kind, a 7-wide front door and doorways at least 6 wide joining every room, corridors at least 6 wide,
-- a ceiling about 12 up; 18-24 pieces, each in its room (from the room's recipe), on the floor, none overlapping another
-- or a fixture or standing in a doorway's way, exactly 3 ★ (the sentimental ones first); every piece can be carried
-- out of the front door (a grid walk of this test's own, the piece's narrow side wide, past everything else); the
-- seeds give different houses (mirrored, other room orders, other pieces and places). 7.x alpine: the Kachelofen on the
-- living room's outer wall, the kitchen's corner bench and its corner shelf, the antlers and pictures high on the walls
-- clear of windows and doorways, the alpine pieces drawn, and Marge's House (seed 1955) keeping its story's ★. 8.0
-- SANDBOX: 2-4 collectibles a house besides its pieces (over 200 seeds: the legendary rate, no overlaps, reachable, the
-- house's own pieces unchanged).
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
local A = T.Alpine
local Items = FurnitureLooks.Items
local SEEDS = 40 -- every check
local WALKS = 12 -- the grid walk (the slow one) on this many of them
local alpineDrawn: { [string]: number } = {} -- (7.x: how often each piece came into a house)

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
for _, e in HouseLayout.Collectibles do -- (8.0: a collectible in the room its catalogue entry names)
	local room = Items[e.item].room
	recipeHas[room] = recipeHas[room] or { box = true }
	recipeHas[room][e.item] = true
end
local C = T.Collectibles
local plans: { [number]: any } = {} -- (8.0: the collectibles' 200 seeds reuse these)

local mirrors, orders, itemSets, places = {}, {}, {}, {}
local slowest, totalTime = 0, 0
for seed = 1, SEEDS do
	local started = os.clock()
	local plan = HouseLayout.plan(seed, "house")
	local took = os.clock() - started
	slowest, totalTime = math.max(slowest, took), totalTime + took
	local again = HouseLayout.plan(seed, "house")
	plans[seed] = plan
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
	local rare = 0 -- (8.0: the collectibles come besides the house's Spots)
	for _, s in plan.spots do
		if Items[s.item] and Items[s.item].rarity then
			rare += 1
		end
	end
	check(`{tag}: {n - rare} pieces ({T.Spots[1]}-{T.Spots[2]}) and {rare} collectibles ({C.Count[1]}-{C.Count[2]})`, n - rare >= T.Spots[1]
		and n - rare <= T.Spots[2] and rare >= C.Count[1] and rare <= C.Count[2])
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

	-- 7.x alpine: the Kachelofen against the living room's outer side wall; the kitchen's corner bench in its back outer
	-- corner (both legs on the back wall, the long one on the outer wall too) and the corner shelf right in that corner
	local function of(kind: string): { any }
		local out = {}
		for _, f in plan.fixtures do
			if f.kind == kind then
				table.insert(out, f)
			end
		end
		return out
	end
	local living, kitchen = byId.living, byId.kitchen
	local outerX = function(r: Rect, room: any): boolean -- on the room's side wall that is the house's outside
		return (math.abs(r.x0 - room.min.X) < 1e-6 and math.abs(room.min.X - plan.min.X - plan.wall) < 1e-6)
			or (math.abs(r.x1 - room.max.X) < 1e-6 and math.abs(room.max.X - plan.max.X + plan.wall) < 1e-6)
	end
	local stoves = of("kachelofen")
	check(`{tag}: the Kachelofen against the living room's outer side wall`, #stoves == 1 and stoves[1].room == "living" and stoves[1].solid
		and outerX(fixtureRect(stoves[1]), living) and math.abs(stoves[1].size.Y - A.Stove[2]) < 1e-6)
	local long, short, shelves = of("corner_bench"), of("bench"), of("corner_shelf")
	local benchOk = #long == 1 and #short == 1 and #shelves == 1 and long[1].room == "kitchen" and short[1].room == "kitchen" and long[1].solid and short[1].solid
	if benchOk then
		local a, b = fixtureRect(long[1]), fixtureRect(short[1])
		benchOk = outerX(a, kitchen) and math.abs(a.z1 - kitchen.max.Z) < 1e-6 and math.abs(b.z1 - kitchen.max.Z) < 1e-6
			and apart(a, b) < 1e-6 and apart(a, b) > -1e-6 -- (the legs meet)
		-- the shelf's corner (its frame's +X, +Z) in the bench's corner, over it, not in the way
		local s = shelves[1]
		local corner = (s.at * M.CFrame.new(s.size.X / 2, 0, s.size.Z / 2)).Position
		local cx = if math.abs(a.x0 - kitchen.min.X) < 1e-6 then kitchen.min.X else kitchen.max.X
		benchOk = benchOk and not s.solid and math.abs(corner.X - cx) < 1e-6 and math.abs(corner.Z - kitchen.max.Z) < 1e-6
			and math.abs(corner.Y - A.Shelf[2]) < 1e-6 and A.Shelf[2] > long[1].size.Y
	end
	check(`{tag}: the corner bench in the kitchen's back outer corner, the Herrgottswinkel's shelf over its corner`, benchOk)

	-- the wall decor: the antlers in the living room, a picture in the hall and in the bedroom; high on a wall of its
	-- room (over every piece), clear of the windows and the doorways on that wall
	local decorOk, decorWhy = true, {}
	for _, want in { { "antlers", "living" }, { "picture", "hall" }, { "picture", "bedroom" } } do
		local found = nil
		for _, f in of(want[1]) do
			if f.room == want[2] then
				found = f
			end
		end
		if not found then
			decorOk = false
			table.insert(decorWhy, `no {want[1]} in the {want[2]}`)
			continue
		end
		local f = found
		local room = byId[f.room]
		local p = f.at.Position
		local turn = f.turn % 360
		local alongX = turn % 180 == 0
		-- the wall behind it: N (turn 0: back +Z), S (180), W (270), E (90)
		local back = if turn == 0 then room.max.Z elseif turn == 180 then room.min.Z elseif turn == 270 then room.min.X else room.max.X
		local t0, t1 = (if alongX then p.X else p.Z) - f.size.X / 2, (if alongX then p.X else p.Z) + f.size.X / 2
		local r = fixtureRect(f)
		local onWall = if turn == 0 then math.abs(r.z1 - back) < 1e-6 elseif turn == 180 then math.abs(r.z0 - back) < 1e-6
			elseif turn == 270 then math.abs(r.x0 - back) < 1e-6 else math.abs(r.x1 - back) < 1e-6
		local inSpan = if alongX then t0 >= room.min.X - 1e-6 and t1 <= room.max.X + 1e-6 else t0 >= room.min.Z - 1e-6 and t1 <= room.max.Z + 1e-6
		if f.solid or not onWall or not inSpan or math.abs(p.Y - A.Decor) > 1e-6 then
			decorOk = false
			table.insert(decorWhy, `{want[1]} in the {want[2]} not high on its wall`)
		end
		for _, w in plan.windows do
			local sameWall = (alongX and math.abs(w.normal.X) < 0.5 and math.abs(w.at.Z - back) < 1e-6) or (not alongX and math.abs(w.normal.Z) < 0.5 and math.abs(w.at.X - back) < 1e-6)
			local wt = if alongX then w.at.X else w.at.Z
			if sameWall and t1 > wt - w.width / 2 and t0 < wt + w.width / 2 and w.at.Y + w.height / 2 > A.Decor then
				decorOk = false
				table.insert(decorWhy, `{want[1]} over a window in the {want[2]}`)
			end
		end
		for _, d in plan.doors do
			local sameWall = (alongX and d.axis == "X" and math.abs(d.at.Z - back) <= plan.wall / 2 + 1e-6) or (not alongX and d.axis == "Z" and math.abs(d.at.X - back) <= plan.wall / 2 + 1e-6)
			local dt = if alongX then d.at.X else d.at.Z
			if sameWall and t1 > dt - d.width / 2 - 0.4 and t0 < dt + d.width / 2 + 0.4 then
				decorOk = false
				table.insert(decorWhy, `{want[1]} over a doorway in the {want[2]}`)
			end
		end
	end
	check(`{tag}: the antlers and the pictures high on their walls, clear of the windows and doorways`, decorOk, table.concat(decorWhy, "; "))
	for _, s in plan.spots do
		alpineDrawn[s.item] = (alpineDrawn[s.item] or 0) + 1
	end
	if seed == 1 then
		-- (a plan's dice are its own: the decor's are apart, the same seed always hangs them the same: the signature)
		check("the wall decor is in the plan's signature (the same seed hangs it the same)", string.find(signature(plan), "antlers", 1, true) ~= nil)
	end
end

-- 7.x alpine: the decor hangs over the tallest piece and under the beams; the chalet's pieces come into the houses;
-- Marge's House (Config.Moving.Contracts' seed) keeps the ★ its story names: the clock, the record player, the rocking
-- horse (shared/MoveStory.luau)
do
	local tallest = 0
	for _, def in Items do
		tallest = math.max(tallest, def.size.Y)
	end
	check(`the wall decor over every piece (from {A.Decor}, the tallest {tallest}) and under the beams`, A.Decor > tallest
		and A.Decor + math.max(A.Picture[2], A.Antlers[2]) <= T.Ceiling - A.Beam)
	local alpine = { "cuckoo_clock", "accordion", "heart_chair", "stein_crate", "painted_cupboard", "carved_chest", "edelweiss_frame", "ski_bundle" }
	local total, missing = 0, {}
	for _, id in alpine do
		total += alpineDrawn[id] or 0
		if not alpineDrawn[id] then
			table.insert(missing, id)
		end
	end
	check(`the alpine pieces come into the houses ({string.format("%.2f", total / SEEDS)} a house; every one in some)`, total / SEEDS >= 1 and #missing == 0,
		table.concat(missing, ", "))
	local marge = Config.Moving.Contracts[1]
	local plan = HouseLayout.plan(marge.seed, marge.kind)
	local stars = {}
	for _, s in plan.spots do
		if s.star then
			table.insert(stars, s.item)
		end
	end
	table.sort(stars)
	check(`Marge's House (seed {marge.seed}): its ★ are the story's ({table.concat(stars, ", ")})`, table.concat(stars, ",") == "grandfather_clock,record_player,rocking_horse")
end

-- 8.0 SANDBOX collectibles (HouseLayout.Collectibles, Config.Furniture.Collectibles) over 200 seeds: every house holds
-- Count of them (8.3 economy: 1-2), none twice, each in the room its catalogue entry names, never ★; a legendary one at
-- about Legendary's rate (one at most: 8.3 economy, one house in 25), every rarity turning up somewhere, the commoner the
-- oftener, and every collectible (with the dice turned up a moment: 8.3 economy's 5 % epics may miss one in 200); none
-- overlapping a piece or a solid fixture or standing in a doorway's way; every piece still gets out (HouseLayout.stuck on
-- all of them, this test's own grid walk on a few with a big one); and the house's own pieces and its ★ are exactly
-- those of the same house without any collectible (their own dice change nothing else).
do
	local SEEDS2 = 200
	local function doorZones(plan: any): { Rect }
		local byId: { [string]: any } = {}
		for _, r in plan.rooms do
			byId[r.id] = r
		end
		local zones: { Rect } = {}
		for _, d in plan.doors do
			for _, id in d.rooms do
				local room = byId[id]
				if room then
					local w = d.width / 2
					if d.axis == "X" then
						local into = if room.min.Z > d.at.Z then 1 else -1
						table.insert(zones, rect(d.at.X - w, d.at.Z, d.at.X + w, d.at.Z + into * (plan.wall / 2 + 4)))
					else
						local into = if room.min.X > d.at.X then 1 else -1
						table.insert(zones, rect(d.at.X, d.at.Z - w, d.at.X + into * (plan.wall / 2 + 4), d.at.Z + w))
					end
				end
			end
		end
		return zones
	end
	local legendary, total = 0, 0
	local perRarity: { [string]: number } = {}
	local perItem: { [string]: number } = {}
	local bad, overlaps, stuckOnes, walkBad = {}, {}, {}, {}
	local walkSeeds: { number } = {} -- (a few houses with a big collectible: the grid walk, below)
	for seed = 1, SEEDS2 do
		local plan = plans[seed] or HouseLayout.plan(seed, "house")
		plans[seed] = plan
		local tag = `seed {seed}`
		local found, legends, big = 0, 0, false
		local seen: { [string]: boolean } = {}
		local zones = doorZones(plan)
		for index, s in plan.spots do
			local def = Items[s.item]
			if not def.rarity then
				continue
			end
			found += 1
			perRarity[def.rarity] = (perRarity[def.rarity] or 0) + 1
			perItem[s.item] = (perItem[s.item] or 0) + 1
			legends += if def.rarity == "legendary" then 1 else 0
			big = big or def.class == "pair" or def.size.Y > 6
			if seen[s.item] or s.room ~= def.room or s.star then
				table.insert(bad, `{tag}: {s.item} in the {s.room}{if s.star then " ★" else ""}`)
			end
			seen[s.item] = true
			local fp = footprint(s)
			for other, o in plan.spots do
				if other ~= index and apart(fp, footprint(o)) < 0.25 then
					table.insert(overlaps, `{tag}: {s.item}/{o.item}`)
				end
			end
			for _, f in plan.fixtures do
				if f.solid and apart(fp, fixtureRect(f)) < 0.2 then
					table.insert(overlaps, `{tag}: {s.item}/{f.kind}`)
				end
			end
			for _, z in zones do
				if apart(z, fp) < 0 then
					table.insert(overlaps, `{tag}: {s.item} in a doorway's way`)
				end
			end
		end
		total += found
		if found < C.Count[1] or found > C.Count[2] or legends > 1 then
			table.insert(bad, `{tag}: {found} collectibles, {legends} legendary`)
		end
		legendary += if legends > 0 then 1 else 0
		local stuck = HouseLayout.stuck(plan)
		if #stuck > 0 then
			table.insert(stuckOnes, `{tag}: {table.concat(stuck, ",")}`)
		end
		if big and #walkSeeds < 6 then
			table.insert(walkSeeds, seed)
		end
	end
	local rate = legendary / SEEDS2
	check(`the collectibles over {SEEDS2} seeds ({string.format("%.2f", total / SEEDS2)} a house): {C.Count[1]}-{C.Count[2]} each, none twice, in its own room, never ★`,
		#bad == 0, table.concat(bad, "; "))
	local spread = 3 * math.sqrt(C.Legendary * (1 - C.Legendary) / SEEDS2) + 0.01
	check(`a legendary one in {legendary} houses of {SEEDS2} ({string.format("%.3f", rate)}): about Legendary's {C.Legendary} (8.3 economy: one in 25)`,
		math.abs(rate - C.Legendary) <= spread and legendary > 0, spread)
	local u, r, e, l = perRarity.uncommon or 0, perRarity.rare or 0, perRarity.epic or 0, perRarity.legendary or 0
	check(`every rarity turns up, the commoner the oftener ({u} uncommon, {r} rare, {e} epic, {l} legendary)`, u > r and r > e and e > l and l > 0)
	-- (8.3 economy: 1-2 a house, 5 % of them epic: with the dice turned up a moment, Config read at each plan, the rest
	-- turns up too: every collectible is one a house can hold)
	local saved = { C.Count, C.Legendary, C.Odds }
	C.Count, C.Legendary, C.Odds = { 5, 6 }, 0.5, { uncommon = 1, rare = 1, epic = 1 }
	local boosted: { [string]: boolean } = {}
	for seed = 1, 30 do
		for _, s in HouseLayout.plan(seed, "house").spots do
			if Items[s.item].rarity then
				boosted[s.item] = true
			end
		end
	end
	C.Count, C.Legendary, C.Odds = saved[1], saved[2], saved[3]
	local never, missed = {}, {}
	for _, id in FurnitureLooks.Collectibles do
		if not perItem[id] and not boosted[id] then
			table.insert(never, id)
		elseif not perItem[id] then
			table.insert(missed, id)
		end
	end
	check(`every collectible turns up in some house ({#missed} only with the dice turned up: {table.concat(missed, ", ")})`, #never == 0 and #missed <= 4, table.concat(never, ", "))
	check("no collectible overlaps a piece or a solid fixture or stands in a doorway's way", #overlaps == 0, table.concat(overlaps, "; "))
	check(`every piece still gets out (HouseLayout.stuck, {SEEDS2} seeds)`, #stuckOnes == 0, table.concat(stuckOnes, "; "))
	-- the same houses without any collectible: their own pieces where they were (colours, turns), the same ★; and the
	-- grid walk finds no piece stuck that the house without them lets out (the walk is stricter than the layout's own
	-- check by a stud's lattice: a few thin pieces at a wall stick in it with or without the collectibles)
	local count0, legendary0 = C.Count, C.Legendary
	C.Count, C.Legendary = { 0, 0 }, 0
	local changed = {}
	local function stuckSet(plan: any): { [string]: boolean }
		local set: { [string]: boolean } = {}
		for _, line in walkOut(plan) do
			set[(string.gsub(line, "^%d+ ", ""))] = true -- (the spot's number differs between the two)
		end
		return set
	end
	for _, seed in walkSeeds do
		local before = stuckSet(HouseLayout.plan(seed, "house"))
		for line in stuckSet(plans[seed]) do
			if not before[line] then
				table.insert(walkBad, `seed {seed}: {line}`)
			end
		end
	end
	local function own(plan: any): (string, number)
		local out, rare = {}, 0
		for _, s in plan.spots do
			if Items[s.item].rarity then
				rare += 1
			else
				local p = s.at.Position
				table.insert(out, string.format("%s %s %.2f %.2f %d %s %d", s.item, s.room, p.X, p.Z, s.turn, tostring(s.star), s.variant))
			end
		end
		return table.concat(out, "\n"), rare
	end
	for seed = 1, 12 do
		local bare, none = own(HouseLayout.plan(seed, "house"))
		local with = own(plans[seed])
		if bare ~= with or none > 0 then
			table.insert(changed, `seed {seed}`)
		end
	end
	C.Count, C.Legendary = count0, legendary0
	check("the house's own pieces and ★ are those of the same house without its collectibles", #changed == 0, table.concat(changed, ", "))
	check(`the grid walk: nothing stuck by the collectibles ({#walkSeeds} houses with a big one: {table.concat(walkSeeds, ", ")})`, #walkSeeds >= 4
		and #walkBad == 0, table.concat(walkBad, "; "))

	-- 8.3 economy: HouseLayout.plan(seed, kind, found): a house that rolls a legendary tries the ones not in the move
	-- owner's collection book first; an empty book, or one with every legendary, changes nothing (the same plan). 8.7
	-- review: a legendary only bought from a player (its page marked bought) is not in the book: the same plan too
	local function legendaryOf(plan: any): string?
		for _, s in plan.spots do
			if Items[s.item].rarity == "legendary" then
				return s.item
			end
		end
		return nil
	end
	local function sameSpots(a: any, b: any): boolean
		if #a.spots ~= #b.spots then
			return false
		end
		for index, s in a.spots do
			local t = b.spots[index]
			if s.item ~= t.item or s.room ~= t.room or (s.at.Position - t.at.Position).Magnitude > 1e-6 or s.variant ~= t.variant then
				return false
			end
		end
		return true
	end
	local allLegendary: { [string]: any } = {}
	for _, id in FurnitureLooks.Collectibles do
		if Items[id].rarity == "legendary" then
			allLegendary[id] = { n = 1, best = 1 }
		end
	end
	local tried, other, same, boughtSame = 0, 0, 0, 0
	local biasBad = {}
	for seed = 1, SEEDS2 do
		local was = legendaryOf(plans[seed])
		if not was or tried >= 4 then
			continue
		end
		tried += 1
		if sameSpots(HouseLayout.plan(seed, "house", {}), plans[seed]) and sameSpots(HouseLayout.plan(seed, "house", allLegendary), plans[seed]) then
			same += 1
		end
		if sameSpots(HouseLayout.plan(seed, "house", { [was :: string] = { n = 1, best = 1, bought = true } }), plans[seed]) then
			boughtSame += 1
		end
		local book = { [was :: string] = { n = 1, best = 1 }, sofa = { n = 3, best = 0.9 } }
		local now = legendaryOf(HouseLayout.plan(seed, "house", book))
		if now and now ~= was and not book[now] then
			other += 1
		else
			table.insert(biasBad, `seed {seed}: {was} → {tostring(now)}`)
		end
		local again = HouseLayout.plan(seed, "house", book)
		if legendaryOf(again) ~= now then
			table.insert(biasBad, `seed {seed}: not the same twice`)
		end
	end
	check(`8.3 economy: an empty book or one with every legendary: the same plan ({same} of {tried} houses with a legendary)`, tried >= 3 and same == tried)
	check(`… the book holds the house's legendary: it gets another one, not in the book, the same every time ({other} of {tried})`, other == tried and #biasBad == 0, table.concat(biasBad, "; "))
	check(`8.7 review: … only bought (its page marked bought): no find, the same plan as an empty book ({boughtSame} of {tried})`, boughtSame == tried, boughtSame)
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
