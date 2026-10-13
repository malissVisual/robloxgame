-- 7.x, Walt's farm (shared/Layouts/Farm.luau through shared/HouseLayout.luau's plan(seed, "farm"), Config.Furniture.Farm)
-- in the standalone Luau CLI on the recorder's Vector3 and CFrame (tools/fixtures/item-mock.luau): a plan is the same for
-- the same seed; it has the farmhouse's five rooms, the yard and the barn's three, each where it belongs (the yard
-- between the buildings, open to the sky; the barn taller); the front door is doors[1] and exit, the barn doors (at
-- least 10 wide, in the threshing floor's back wall) the second exit: exits lists both, in the doors' order; every room
-- is reached through doorways at least 6 wide; 22-30 pieces, each in its room from the room's recipe, on the floor,
-- none overlapping another or a fixture or standing in a doorway's way, exactly 3 ★ (the farm's keepsakes), the musts
-- there (the hay wagon in the threshing floor); every piece can be carried out of an exit it may use (the layout's own
-- check and a grid walk of this test's own) and the hay wagon, a bigDoor piece, only out of the barn doors (it does not
-- fit the farmhouse's doorways); the stalls, the stoves, the barn doors and the lanterns are there; the seeds give
-- different farms; a plan is quick to make.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local M = require("./ItemMock")
local Config = require("./Config")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local Farm = require("./Farm")

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
local F = T.Farm
local Items = FurnitureLooks.Items
local SEEDS = 40 -- every check
local WALKS = 10 -- the grid walk (the slow one) on this many of them

type Rect = { x0: number, z0: number, x1: number, z1: number }
local function rect(x0: number, z0: number, x1: number, z1: number): Rect
	return { x0 = math.min(x0, x1), z0 = math.min(z0, z1), x1 = math.max(x0, x1), z1 = math.max(z0, z1) }
end
local function apart(a: Rect, b: Rect): number -- the gap between two rects (negative: they overlap)
	return math.max(a.x0 - b.x1, b.x0 - a.x1, a.z0 - b.z1, b.z0 - a.z1)
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
	for _, e in plan.exits do
		table.insert(out, string.format("exit %.2f %.2f %.2f", e.X, e.Y, e.Z))
	end
	for _, s in plan.spots do
		local p = s.at.Position
		table.insert(out, string.format("%d %s %s %.2f %.2f %.2f %d %s %d", s.id, s.item, s.room, p.X, p.Y, p.Z, s.turn, tostring(s.star), s.variant))
	end
	for _, f in plan.fixtures do
		local p = f.at.Position
		table.insert(out, string.format("%s %s %.2f %.2f %.2f", f.kind, f.room, p.X, p.Y, p.Z))
	end
	table.insert(out, tostring(#plan.faces))
	return table.concat(out, "\n")
end

-- ── The grid walk: can a piece be carried out of an exit it may use? ───────────────
-- As tests/houselayout_test.luau's: the floor is the rooms' insides, the doorways (a box through the wall) and the
-- ground outside the two exits (the porch, the barn doors' apron); in the way the solid fixtures and every other
-- piece. A point of a 1-stud lattice is clear for a piece when it and the four points `r` from it are on the floor and
-- nothing in the way is closer than `r`. `squeeze`: r = half the piece's narrow side less half a stud (at least half a
-- stud), else exactly half its narrow side. A walk over clear points must reach the outside of one of `exits`.
local function walkOut(plan: any, only: { [number]: { number } }?, squeeze: boolean): { string }
	local floors: { Rect } = {}
	for _, r in plan.rooms do
		table.insert(floors, rect(r.min.X, r.min.Z, r.max.X, r.max.Z))
	end
	local half = plan.wall / 2 + 0.01
	local outside: { Rect } = {}
	for _, d in plan.doors do
		local w = d.width / 2
		table.insert(floors, if d.axis == "X" then rect(d.at.X - w, d.at.Z - half, d.at.X + w, d.at.Z + half) else rect(d.at.X - half, d.at.Z - w, d.at.X + half, d.at.Z + w))
		if d.rooms[2] == "outside" then
			-- 4 studs of ground beyond the doorway (away from its room), the walk's goal
			local room: any = nil
			for _, r in plan.rooms do
				if r.id == d.rooms[1] then
					room = r
				end
			end
			local away = if (room.min.Z + room.max.Z) / 2 > d.at.Z then -1 else 1
			local ground = rect(d.at.X - w, d.at.Z + away * half, d.at.X + w, d.at.Z + away * (half + 4))
			table.insert(floors, ground)
			table.insert(outside, ground)
		end
	end
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
	local x0, z0 = math.floor(plan.min.X) - 5, math.floor(plan.min.Z) - 5
	local nx, nz = math.ceil(plan.max.X) - x0 + 6, math.ceil(plan.max.Z) - z0 + 6
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
	local memo: { [string]: boolean } = {}
	local function clear(i: number, j: number, own: number, r: number): boolean
		if i < 0 or j < 0 or i >= nx or j >= nz then
			return false
		end
		local k = j * nx + i + 1
		if not floorAt[k] or fixtureAt[k] < r or (if near1i[k] == own then near2[k] else near1[k]) < r then
			return false
		end
		local key = `{k}:{r}`
		local m = memo[key]
		if m == nil then
			local x, z = x0 + i, z0 + j
			m = onFloor(x + r, z) and onFloor(x - r, z) and onFloor(x, z + r) and onFloor(x, z - r)
			memo[key] = m
		end
		return m
	end
	local stuck: { string } = {}
	for n, s in plan.spots do
		local goals = only and only[n] or Farm.exitsFor(plan, s.item)
		local def = Items[s.item]
		local narrow = math.min(def.size.X, def.size.Z)
		local r = if squeeze then math.max(0.5, narrow / 2 - 0.5) else narrow / 2
		local fp = pieces[n]
		local queue, seen = {}, {}
		for j = math.ceil(fp.z0) - z0, math.floor(fp.z1) - z0 do
			for i = math.ceil(fp.x0) - x0, math.floor(fp.x1) - x0 do
				if clear(i, j, n, r) then
					seen[j * nx + i + 1] = true
					table.insert(queue, { i, j })
				end
			end
		end
		local out, q = false, 1
		while q <= #queue and not out do
			local i, j = queue[q][1], queue[q][2]
			q += 1
			local x, z = x0 + i, z0 + j
			for _, e in goals do
				local g = outside[e]
				if g and x >= g.x0 - 1e-6 and x <= g.x1 + 1e-6 and z >= g.z0 - 1e-6 and z <= g.z1 + 1e-6 then
					out = true
				end
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
local ROOMS: { [string]: string } = {
	mudroom = "hall",
	stube = "living",
	kitchen = "kitchen",
	bedroom = "bedroom",
	pantry = "pantry",
	yard = "yard",
	stable = "stable",
	barn = "barn",
	workshop = "workshop",
}
local HOUSE = { mudroom = true, stube = true, kitchen = true, bedroom = true, pantry = true }
local BARN = { stable = true, barn = true, workshop = true }
local recipeHas: { [string]: { [string]: boolean } } = {}
local musts: { [string]: { string } } = {}
local keepsakes: { [string]: boolean } = {}
for room, entries in Farm.Recipes do
	recipeHas[room] = { box = true } -- (a filler box may go in any room)
	musts[room] = {}
	for _, e in entries do
		recipeHas[room][e.item] = true
		if e.must then
			table.insert(musts[room], e.item)
		end
		if e.star then
			keepsakes[e.item] = true
		end
	end
end
local keepsakeCount = 0
for item in keepsakes do
	keepsakeCount += 1
	check(`the keepsake {item} is a sentimental piece`, Items[item] ~= nil and Items[item].sentimental)
end
check(`the farm has {keepsakeCount} ★ candidates for its {F.Stars} ★`, keepsakeCount > F.Stars)
check("HouseLayout knows the farm", table.find(HouseLayout.Kinds, "farm") ~= nil and table.find(HouseLayout.Kinds, "house") ~= nil)

local mirrors, sides, itemSets, starSets, places = {}, {}, {}, {}, {}
local slowest, totalTime = 0, 0
for seed = 1, SEEDS do
	local started = os.clock()
	local plan: any = HouseLayout.plan(seed, "farm")
	local took = os.clock() - started
	slowest, totalTime = math.max(slowest, took), totalTime + took
	local tag = `seed {seed}`
	check(`{tag}: the same seed, the same farm (also from Farm.plan)`, signature(plan) == signature(HouseLayout.plan(seed, "farm")) and signature(plan) == signature(Farm.plan(seed)))
	check(`{tag}: a farm, its box (size {math.floor(plan.size.X)} × {math.floor(plan.size.Z)}, {plan.size.Y} high)`, plan.kind == "farm" and plan.seed == seed
		and math.abs(plan.size.X - (plan.max.X - plan.min.X)) < 1e-6 and plan.size.X >= 50 and plan.size.X <= 80 and plan.size.Z >= 70 and plan.size.Z <= 95
		and plan.max.Y == F.BarnCeiling and plan.ceiling == T.Ceiling)
	mirrors[plan.mirrored] = true

	-- rooms
	local byId: { [string]: any } = {}
	local badRooms = {}
	for _, r in plan.rooms do
		local top = if HOUSE[r.id] then T.Ceiling elseif BARN[r.id] then F.BarnCeiling else F.Fence
		if byId[r.id] or ROOMS[r.id] ~= r.kind or r.max.X <= r.min.X or r.max.Z <= r.min.Z or math.abs(r.min.Y) > 1e-6 or r.max.Y ~= top
			or r.min.X < plan.min.X or r.max.X > plan.max.X or r.min.Z < plan.min.Z or r.max.Z > plan.max.Z then
			table.insert(badRooms, r.id)
		end
		byId[r.id] = r
	end
	local all = true
	for id in ROOMS do
		all = all and byId[id] ~= nil
	end
	check(`{tag}: the nine rooms, each its kind and height, inside the box`, #plan.rooms == 9 and all and #badRooms == 0, table.concat(badRooms, ", "))
	local overlap = false
	for a = 1, #plan.rooms do
		for b = a + 1, #plan.rooms do
			local ra, rb = plan.rooms[a], plan.rooms[b]
			overlap = overlap or apart(rect(ra.min.X, ra.min.Z, ra.max.X, ra.max.Z), rect(rb.min.X, rb.min.Z, rb.max.X, rb.max.Z)) < plan.wall - 1e-6
		end
	end
	check(`{tag}: the rooms do not overlap (a wall between them)`, not overlap)
	if not all then
		continue
	end
	local yard = byId.yard
	local houseBack, barnFront = -math.huge, math.huge
	for id in HOUSE do
		houseBack = math.max(houseBack, byId[id].max.Z)
	end
	for id in BARN do
		barnFront = math.min(barnFront, byId[id].min.Z)
	end
	check(`{tag}: the yard between the farmhouse and the barn, a wall from each`, yard.min.Z > houseBack and yard.max.Z < barnFront
		and math.abs(yard.min.Z - houseBack - plan.wall) < 1e-6 and math.abs(barnFront - yard.max.Z - plan.wall) < 1e-6)
	local houseX0, houseX1 = math.huge, -math.huge
	for id in HOUSE do
		houseX0, houseX1 = math.min(houseX0, byId[id].min.X), math.max(houseX1, byId[id].max.X)
	end
	local barnX0, barnX1 = math.huge, -math.huge
	for id in BARN do
		barnX0, barnX1 = math.min(barnX0, byId[id].min.X), math.max(barnX1, byId[id].max.X)
	end
	check(`{tag}: the yard spans the farmhouse ({houseX1 - houseX0} wide), the barn spans the yard ({barnX1 - barnX0})`, math.abs(yard.min.X - houseX0) < 1e-6
		and math.abs(yard.max.X - houseX1) < 1e-6 and barnX0 <= yard.min.X + 1e-6 and barnX1 >= yard.max.X - 1e-6)
	local stableLeft = byId.stable.min.X < byId.barn.min.X
	sides[stableLeft] = true
	check(`{tag}: the threshing floor between the stable and the workshop`, (byId.stable.max.X < byId.barn.min.X and byId.workshop.min.X > byId.barn.max.X)
		or (byId.workshop.max.X < byId.barn.min.X and byId.stable.min.X > byId.barn.max.X))

	-- doors and exits
	local front = plan.doors[1]
	check(`{tag}: the front door ({front.width} wide) into the mud room is doors[1]`, front.front == true and front.width == T.FrontDoor and front.axis == "X"
		and math.abs(front.at.X) < 1e-6 and math.abs(front.at.Z) < 1e-6 and front.rooms[1] == "mudroom" and front.rooms[2] == "outside")
	local outs = {}
	local badDoors, links = {}, {}
	for n, d in plan.doors do
		if d.rooms[2] == "outside" then
			table.insert(outs, d)
			continue
		end
		local a, b = byId[d.rooms[1]], byId[d.rooms[2]]
		local ok = d.width >= T.Door and not d.front and a ~= nil and b ~= nil
		if ok then
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
	check(`{tag}: {#plan.doors - #outs} doorways inside, each at least {T.Door} wide on the wall between its rooms`, #badDoors == 0, table.concat(badDoors, "; "))
	local barnDoors = outs[2]
	local barn = byId.barn
	check(`{tag}: two exits, the second the barn doors ({barnDoors and barnDoors.width} wide) in the threshing floor's back wall`, #outs == 2 and outs[1] == front
		and barnDoors.rooms[1] == "barn" and barnDoors.width == F.BarnDoor and barnDoors.width >= 10 and barnDoors.axis == "X"
		and math.abs(barnDoors.at.Z - (barn.max.Z + plan.wall / 2)) < 1e-6 and barnDoors.at.X - barnDoors.width / 2 >= barn.min.X - 1e-6
		and barnDoors.at.X + barnDoors.width / 2 <= barn.max.X + 1e-6)
	local e1, e2 = plan.exits[1], plan.exits[2]
	check(`{tag}: exits: the front door's inside (exit), then the barn doors' inside`, #plan.exits == 2 and e1 == plan.exit
		and math.abs(e1.X) < 1e-6 and e1.Z >= 0 and e1.Z <= 1 and math.abs(e1.Y - T.EntryUp) < 1e-6
		and math.abs(e2.X - barnDoors.at.X) < 1e-6 and e2.Z < barnDoors.at.Z and e2.Z >= barnDoors.at.Z - 1 and math.abs(e2.Y - T.EntryUp) < 1e-6)
	local wagonExits, boxExits = Farm.exitsFor(plan, "hay_wagon"), Farm.exitsFor(plan, "box")
	check(`{tag}: the hay wagon may leave only by the barn doors, a box by either exit`, #wagonExits == 1 and wagonExits[1] == 2 and #boxExits == 2)
	local reached, queue = { mudroom = true }, { "mudroom" }
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
	check(`{tag}: every room is reached from the mud room through doorways`, #queue == #plan.rooms)

	-- spots
	local n = #plan.spots
	check(`{tag}: {n} pieces ({F.Spots[1]}-{F.Spots[2]})`, n >= F.Spots[1] and n <= F.Spots[2])
	local badSpots, stars, starItems = {}, 0, {}
	local set, has = {}, {}
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
			table.insert(starItems, s.item)
		end
		has[s.room .. "/" .. s.item] = true
		table.insert(set, s.item)
		places[string.format("%s %.1f %.1f", s.item, p.X, p.Z)] = true
	end
	check(`{tag}: every piece in its room, from the room's recipe, on the floor, turned square`, #badSpots == 0, table.concat(badSpots, "; "))
	table.sort(starItems)
	local allKeepsakes = true
	for _, item in starItems do
		allKeepsakes = allKeepsakes and keepsakes[item] == true
	end
	check(`{tag}: exactly {F.Stars} ★, all the farm's keepsakes ({table.concat(starItems, ", ")})`, stars == F.Stars and allKeepsakes)
	starSets[table.concat(starItems, ",")] = true
	local missing = {}
	for room, items in musts do
		for _, item in items do
			if not has[room .. "/" .. item] then
				table.insert(missing, `{item} in {room}`)
			end
		end
	end
	check(`{tag}: every must is there (the hay wagon in the threshing floor)`, #missing == 0 and has["barn/hay_wagon"] == true, table.concat(missing, ", "))
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

	-- the way in
	local e = plan.entry.Position
	local mud = byId.mudroom
	local clearEntry = true
	for _, s in plan.spots do
		clearEntry = clearEntry and dist(e.X, e.Z, footprint(s)) >= 1.5
	end
	check(`{tag}: you come in inside the front door, facing into the farmhouse, nothing in your way`, e.X > mud.min.X and e.X < mud.max.X and e.Z > mud.min.Z
		and e.Z < mud.max.Z and clearEntry and plan.entry.R[9] < -0.99 and e.Y > 1)

	-- every piece gets out: the layout's own check (also through HouseLayout.stuck), and (on some seeds) this test's walk
	local stuck = Farm.stuck(plan)
	check(`{tag}: Farm.stuck finds no piece stuck (HouseLayout.stuck agrees)`, #stuck == 0 and #HouseLayout.stuck(plan) == 0, table.concat(stuck, ", "))
	if seed <= WALKS then
		local walked = walkOut(plan, nil, true)
		check(`{tag}: every piece can be carried out of an exit it may use (grid walk)`, #walked == 0, table.concat(walked, "; "))
		-- the hay wagon does not fit the farmhouse's doorways: carried honestly it gets out of the barn doors, never the front
		local wagon = 0
		for index, s in plan.spots do
			if s.item == "hay_wagon" then
				wagon = index
			end
		end
		if wagon > 0 then
			local onlyFront: { [number]: { number } } = { [wagon] = { 1 } }
			local onlyBarn: { [number]: { number } } = { [wagon] = { 2 } }
			local function stuckWagon(only: { [number]: { number } }): boolean
				for _, line in walkOut(plan, only, false) do
					if string.find(line, "hay_wagon", 1, true) then
						return true
					end
				end
				return false
			end
			check(`{tag}: the hay wagon leaves by the barn doors, it cannot by the front door`, not stuckWagon(onlyBarn) and stuckWagon(onlyFront))
		end
	end

	-- walls, windows, fixtures
	local fences, barnHigh, houseHigh, wallsOk = 0, true, true, true
	for _, f in plan.faces do
		wallsOk = wallsOk and f.max.X > f.min.X and f.max.Z > f.min.Z and f.max.Y > f.min.Y
		if f.room == "yard" and f.outer and not f.header then
			fences += 1
			wallsOk = wallsOk and math.abs(f.max.Y - F.Fence) < 1e-6
		end
		if BARN[f.room] then
			barnHigh = barnHigh and math.abs(f.max.Y - F.BarnCeiling) < 1e-6
		end
		if HOUSE[f.room] then
			houseHigh = houseHigh and math.abs(f.max.Y - T.Ceiling) < 1e-6
		end
	end
	check(`{tag}: {#plan.faces} wall faces: the yard's two fences {F.Fence} high, the barn's {F.BarnCeiling}, the farmhouse's {T.Ceiling}`, fences == 2 and barnHigh and houseHigh and wallsOk)
	local badWindows = 0
	for _, w in plan.windows do
		local room = byId[w.room]
		local onWall = room ~= nil and ((w.normal.Z > 0.5 and math.abs(w.at.Z - room.min.Z) < 1e-6) or (w.normal.Z < -0.5 and math.abs(w.at.Z - room.max.Z) < 1e-6)
			or (w.normal.X > 0.5 and math.abs(w.at.X - room.min.X) < 1e-6) or (w.normal.X < -0.5 and math.abs(w.at.X - room.max.X) < 1e-6))
		if not (onWall and w.at.Y - w.height / 2 >= 2 and w.at.Y + w.height / 2 < room.max.Y) then
			badWindows += 1
		end
	end
	check(`{tag}: {#plan.windows} windows, each on its room's wall`, #plan.windows >= 8 and badWindows == 0)
	local kinds: { [string]: number } = {}
	for _, f in plan.fixtures do
		kinds[f.kind] = (kinds[f.kind] or 0) + 1
	end
	check(`{tag}: the stalls ({kinds.stall}), the stoves, the larder, the loft, the forge, the barn doors, the lanterns ({kinds.lantern}) are there`,
		kinds.stall == F.Stalls and kinds.manger == F.Stalls and kinds.stall_wall == F.Stalls - 1 and kinds.kachelofen == 1 and kinds.tiled_stove == 1
		and kinds.larder == 1 and kinds.hay_loft == 1 and kinds.forge == 1 and kinds.workbench == 1 and kinds.barn_doors == 1 and kinds.lantern == 4
		and kinds.trough == 1 and kinds.woodpile == 1)
end

local function count(t: { [any]: boolean }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end
check("the seeds mirror the farm both ways", mirrors[true] == true and mirrors[false] == true)
check("the stable stands on either side of the threshing floor", sides[true] == true and sides[false] == true)
check(`the seeds give other sets of pieces ({count(itemSets)} of {SEEDS})`, count(itemSets) >= SEEDS / 2)
check(`the seeds give other ★ ({count(starSets)} sets)`, count(starSets) >= 3)
check(`the pieces stand in many places ({count(places)})`, count(places) >= SEEDS * 8)
check(`a plan is quick to make (average {string.format("%.3f", totalTime / SEEDS)} s, slowest {string.format("%.3f", slowest)} s)`, totalTime / SEEDS < 0.5)

-- a big or negative seed works; the house is still a house
do
	local big = HouseLayout.plan(2 ^ 40 + 0.5, "farm")
	local negative = HouseLayout.plan(-12345, "farm")
	check("a huge or a negative seed makes a farm", big.kind == "farm" and #big.spots >= F.Spots[1] and #negative.spots >= F.Spots[1])
	check("the house is still a house (no exits of its own)", HouseLayout.plan(1955, "house").kind == "house" and (HouseLayout.plan(1955, "house") :: any).exits == nil)
end
local _ = M

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
