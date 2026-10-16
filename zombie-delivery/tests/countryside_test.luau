-- 9.5 the countryside (the owner: "instead of those houses make rather six different spots ... not any towns, and not
-- villages"): the four new places to empty, shared/Layouts/Countryside.luau's plans through shared/HouseLayout.luau's
-- plan(seed, kind) for "cabin" (The Pond Cabin), "lodge" (The Forest Lodge), "mill" (The Old Mill) and "cottage" (The
-- Orchard Cottage), in the standalone Luau CLI on the recorder (tools/fixtures/item-mock.luau), and their contracts
-- (Config.Moving.Sandbox.Houses). Built on their own; each spot on the map too (SandboxMap.house: its kind and box).
--   * the contracts: the five family houses gone, the five spots' (and the farmstead's as it was), each its kind
--     (HouseLayout knows it), a made-up Czech family, a short place for its address, a short blurb, its clock by its
--     size: 12 – 16 minutes, about the farmstead's minutes a piece
--   * every plan: the same seed the same plan; its inside its Box × Scale (Config.Furniture.Countryside); its rooms (the
--     cabin's main room, bunk room and store; the lodge's hall and three or four rooms; the mill's workroom and miller's
--     room; the cottage's kitchen with its bedroom and maybe its store), each reached from the front door through
--     doorways at least Door wide (the front door doors[1], FrontDoor wide, at the origin); its pieces Spots and 2 – 4
--     collectibles (uncommon to legendary, each once, never ★), each in its room, on the floor, turned square, none on
--     another or on a solid fixture; exactly Stars ★; its own things there (the outboard motor, the antler trophy, the
--     spare millstone, the sewing machine ...); every piece out of the front door (HouseLayout.stuck) and Danny's spot
--     beside each (shared/HouseRoute.luau reach within Route.Stand, a way there on open cells through no wall); its own
--     fixtures (the wood stove, the fireplace, the millstones and the pit wheel on the -X wall: the water wheel's side,
--     never mirrored); the seeds vary the rooms (mirrored, the lodge's great room, the cottage's two rooms)
--   * built (server/HouseInterior.luau): within its InteriorMaxParts, modest lights, everything anchored, a piece at every
--     spot, the EXIT sign; its own style (the cabin's boards, the mill's stone, the cottage's clay tiles) and fixtures
-- Run: python3 tests/run_tests.py [path to the luau binary]

local M = require("./ItemMock")
local Config = require("./Config")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local HouseRoute = require("./HouseRoute")
local Countryside = require("./Countryside")
local SandboxMap = require("./SandboxMap")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function finite(x: number): boolean
	return x == x and x > -math.huge and x < math.huge
end

local T = Config.Furniture
local C = (T :: any).Countryside
local R = Config.MoveHelper.Route
local Items = FurnitureLooks.Items
local SEEDS = 24

type Rect = { x0: number, z0: number, x1: number, z1: number }
local function rect(x0: number, z0: number, x1: number, z1: number): Rect
	return { x0 = math.min(x0, x1), z0 = math.min(z0, z1), x1 = math.max(x0, x1), z1 = math.max(z0, z1) }
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
local function apart(a: Rect, b: Rect): number -- the gap between two rects (negative: they overlap)
	return math.max(a.x0 - b.x1, b.x0 - a.x1, a.z0 - b.z1, b.z0 - a.z1)
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
	table.insert(out, tostring(#plan.faces) .. " " .. tostring(#plan.windows))
	return table.concat(out, "\n")
end

-- ── The contracts ─────────────────────────────────────────────────────────────
local S = Config.Moving.Sandbox
local SPOTS = {
	{ id = "pond_cabin", kind = "cabin", box = { 24, 18 } },
	{ id = "lone_house", kind = "house", box = { 30, 24 } },
	{ id = "forest_lodge", kind = "lodge", box = { 28, 22 } },
	{ id = "old_mill", kind = "mill", box = { 24, 26 } },
	{ id = "orchard_cottage", kind = "cottage", box = { 26, 20 } },
}
do
	local count = 0
	for _ in S.Houses do
		count += 1
	end
	local gone = true
	for _, id in { "Hlavní_n_5", "Hlavní_s_11", "Školní_e_20", "Lidická_e_30", "Smetanova_w_84" } do
		gone = gone and S.Houses[id] == nil
	end
	check("the five family houses' contracts are gone; six spots' contracts (the farmstead's as it was)", gone and count == 6
		and S.Houses.sandbox_house.Kind == "big" and S.Houses.sandbox_house.Time == 25 * 60 and S.Houses.sandbox_house.Client == "The Nováks", count)
	local farm = S.Houses.sandbox_house
	local farmPace = farm.Time / (T.Big.Spots[2] + T.Big.Collectibles.Count[2])
	local families: { [string]: boolean } = { [farm.Client] = true }
	local bad: string? = nil
	local lastArea, lastTime = 0, 0
	for _, spot in SPOTS do
		local c = S.Houses[spot.id]
		if not c then
			bad = bad or `{spot.id}: no contract`
			continue
		end
		local most = if spot.kind == "house" then T.Spots[2] + T.Collectibles.Count[2] else C[spot.kind].Spots[2] + C[spot.kind].Collectibles.Count[2]
		local pace = c.Time / most
		if c.Kind ~= spot.kind or not table.find(HouseLayout.Kinds, c.Kind) then
			bad = bad or `{spot.id}: its kind {c.Kind}`
		elseif string.sub(c.Client, 1, 4) ~= "The " or string.sub(c.Client, -1) ~= "s" or #c.Client > Config.MoveStory.Limits.Client or families[c.Client] then
			bad = bad or `{spot.id}: its family {c.Client}`
		elseif #c.Address == 0 or #c.Address > 24 or string.find(c.Address, "%d") then
			bad = bad or `{spot.id}: its address {c.Address} (a short place, no number)`
		elseif #c.Blurb == 0 or #c.Blurb > Config.MoveStory.Limits.Blurb then
			bad = bad or `{spot.id}: its blurb`
		elseif c.Time < 12 * 60 or c.Time > 18 * 60 or c.Time <= S.HordeAt or pace < farmPace * 0.9 or pace > farmPace * 1.5 then
			bad = bad or `{spot.id}: {c.Time / 60} min ({pace} s a piece against the farmstead's {farmPace})`
		end
		families[c.Client] = true
		if spot.kind ~= "house" then
			local K = C[spot.kind]
			bad = bad or (if K.Box[1] ~= spot.box[1] or K.Box[2] ~= spot.box[2] then `{spot.kind}: its box` else nil)
		end
		local area = spot.box[1] * spot.box[2]
		if area > lastArea and c.Time < lastTime and spot.kind ~= "mill" then
			bad = bad or `{spot.id}: a bigger place, a shorter clock`
		end
		lastArea, lastTime = math.max(lastArea, area), math.max(lastTime, c.Time)
	end
	check("the spots' contracts: Pond Cabin, Lone House, Forest Lodge, Old Mill, Orchard Cottage: their kinds, families, short places, blurbs; 12 – 18 minutes by size (about the farmstead's pace)",
		bad == nil, bad)
	check("HouseLayout knows the countryside's kinds", table.find(HouseLayout.Kinds, "cabin") ~= nil and table.find(HouseLayout.Kinds, "lodge") ~= nil
		and table.find(HouseLayout.Kinds, "mill") ~= nil and table.find(HouseLayout.Kinds, "cottage") ~= nil and table.find(HouseLayout.Kinds, "big") ~= nil)
	-- (with the countryside's map: each spot on it, of its kind, its box the one its contract's numbers are for)
	local missing: string? = nil
	for _, spot in SPOTS do
		local h = SandboxMap.house(spot.id)
		local quarter = h ~= nil and (h.yaw == 90 or h.yaw == 270)
		if not h or h.kind ~= spot.kind or (if quarter then h.box.z1 - h.box.z0 else h.box.x1 - h.box.x0) ~= spot.box[1]
			or (if quarter then h.box.x1 - h.box.x0 else h.box.z1 - h.box.z0) ~= spot.box[2] then
			missing = missing or spot.id
		end
	end
	check("…each spot on the map (SandboxMap.house): of its kind, its box the owner's", missing == nil, missing)
end

-- ── Every plan ─────────────────────────────────────────────────────────────────
local ROOMS: { [string]: { string } } = {
	cabin = { "main", "bunks", "store" },
	lodge = { "hall", "living", "kitchen", "bedroom" },
	mill = { "workroom", "millers" },
	cottage = { "kitchen", "bedroom" },
}
local THINGS: { [string]: { string } } = {
	cabin = { "outboard_motor", "fishing_rods", "oars", "tackle_box", "bunk_bed", "dining_table", "coal_scuttle" },
	lodge = { "antler_trophy", "gun_cabinet", "oak_table", "boot_rack", "stuffed_owl", "bed", "armchair" },
	mill = { "millstone", "grain_scales", "sack_trolley", "joiners_bench", "flour_sacks", "grain_crate", "grandfather_clock" },
	cottage = { "sewing_machine", "plate_dresser", "jam_shelf", "rocking_chair", "apple_press", "bee_box", "fruit_crates" },
}
local FIXTURES: { [string]: { string } } = {
	cabin = { "wood_stove", "sink", "counter", "shelves", "net", "lifebuoy" },
	lodge = { "fireplace", "tiled_stove", "sink", "antlers", "runner" },
	mill = { "millstones", "pit_wheel", "sack_hoist", "hanging_lantern", "wood_stove" },
	cottage = { "tiled_stove", "sink", "counter", "picture" },
}
local rarities = FurnitureLooks.Rarities
local totalTime, slowest = 0, 0
local variety: { [string]: { [string]: boolean } } = {}
local plans: { [string]: { any } } = {}
for _, kind in Countryside.Kinds do
	local K = C[kind]
	local W, D = Countryside.size(kind)
	variety[kind] = {}
	plans[kind] = {}
	local itemSets: { [string]: boolean } = {}
	local bad: { [string]: string } = {}
	local function fail(key: string, why: string)
		bad[key] = bad[key] or why
	end
	local mostPieces, leastPieces = 0, math.huge
	for seed = 1, SEEDS do
		local t0 = os.clock()
		local plan: any = HouseLayout.plan(seed, kind)
		local took = os.clock() - t0
		totalTime += took
		slowest = math.max(slowest, took)
		table.insert(plans[kind], plan)
		local tag = `{kind} {seed}`
		if signature(plan) ~= signature(HouseLayout.plan(seed, kind)) or signature(plan) ~= signature(Countryside.plan(seed, kind, nil, HouseLayout.Collectibles)) then
			fail("same", tag)
		end
		-- its box, its rooms
		local size = plan.size
		if plan.kind ~= kind or plan.seed ~= seed or math.abs(size.X - (W + T.Wall)) > 1e-6 or math.abs(size.Z - (D + T.Wall)) > 1e-6
			or plan.ceiling ~= K.Ceiling or (plan :: any).exits ~= nil then
			fail("box", `{tag}: {size.X} × {size.Z}`)
		end
		variety[kind]["mirrored " .. tostring(plan.mirrored)] = true
		variety[kind][#plan.rooms .. " rooms"] = true
		local byId: { [string]: any } = {}
		for _, room in plan.rooms do
			byId[room.id] = room
			if room.min.X < plan.min.X - 1e-6 or room.max.X > plan.max.X + 1e-6 or room.min.Z < plan.min.Z - 1e-6 or room.max.Z > plan.max.Z + 1e-6
				or math.abs(room.max.Y - K.Ceiling) > 1e-6 then
				fail("rooms", `{tag}: {room.id} out of the box`)
			end
		end
		for _, id in ROOMS[kind] do
			if not byId[id] then
				fail("rooms", `{tag}: no {id}`)
			end
		end
		-- the doors: the front one first, every room reached from the front room through doorways wide enough
		local front = plan.doors[1]
		if not front.front or front.width ~= T.FrontDoor or front.axis ~= "X" or math.abs(front.at.X) > 1e-6 or math.abs(front.at.Z) > 1e-6
			or front.rooms[2] ~= "outside" then
			fail("doors", `{tag}: the front door`)
		end
		local reached: { [string]: boolean } = { [front.rooms[1]] = true }
		for _ = 1, #plan.rooms do
			for n, d in plan.doors do
				if n > 1 and (d.width < T.Door or d.rooms[2] == "outside") then
					fail("doors", `{tag}: a doorway {d.width} wide or a second way out`)
				end
				if reached[d.rooms[1]] or reached[d.rooms[2]] then
					reached[d.rooms[1]], reached[d.rooms[2]] = true, true
				end
			end
		end
		for _, room in plan.rooms do
			if not reached[room.id] then
				fail("doors", `{tag}: {room.id} not reached`)
			end
		end
		-- the pieces
		local n, stars, collectibles = #plan.spots, 0, 0
		local seen: { [string]: boolean } = {}
		local items: { string } = {}
		local rects: { Rect } = {}
		for _, s in plan.spots do
			local def = Items[s.item]
			local room = byId[s.room]
			local r = footprint(s)
			table.insert(rects, r)
			table.insert(items, s.item)
			local p = s.at.Position
			if not def or not room or r.x0 < room.min.X - 1e-6 or r.x1 > room.max.X + 1e-6 or r.z0 < room.min.Z - 1e-6 or r.z1 > room.max.Z + 1e-6
				or math.abs(p.Y - def.size.Y / 2) > 1e-6 or s.turn % 90 ~= 0 then
				fail("spots", `{tag}: #{s.id} {s.item} in {s.room}`)
			end
			if s.star then
				stars += 1
			end
			if def and def.rarity then
				collectibles += 1
				if seen[s.item] or s.star or not table.find(rarities, def.rarity) then
					fail("collectibles", `{tag}: {s.item}`)
				end
				seen[s.item] = true
			end
		end
		mostPieces, leastPieces = math.max(mostPieces, n - collectibles), math.min(leastPieces, n - collectibles)
		if n - collectibles < K.Spots[1] or n - collectibles > K.Spots[2] + 1 then
			fail("count", `{tag}: {n - collectibles} pieces`)
		end
		if collectibles < K.Collectibles.Count[1] or collectibles > K.Collectibles.Count[2] then
			fail("collectibles", `{tag}: {collectibles} collectibles`)
		end
		if stars ~= K.Stars then
			fail("stars", `{tag}: {stars} ★`)
		end
		table.sort(items)
		itemSets[table.concat(items, ",")] = true
		for _, id in THINGS[kind] do
			if not table.find(items, id) then
				fail("things", `{tag}: no {id}`)
			end
		end
		for a = 1, #rects do
			for b = a + 1, #rects do
				if plan.spots[a].room == plan.spots[b].room and apart(rects[a], rects[b]) < T.Gap - 1e-6 then
					fail("overlap", `{tag}: {plan.spots[a].item} / {plan.spots[b].item}`)
				end
			end
			for _, f in plan.fixtures do
				if f.solid and f.room == plan.spots[a].room and apart(rects[a], fixtureRect(f)) < T.FixtureGap - 1e-6 then
					fail("overlap", `{tag}: {plan.spots[a].item} / {f.kind}`)
				end
			end
		end
		-- every piece out of the front door; Danny's spot beside each, a way there through no wall
		if #HouseLayout.stuck(plan) > 0 then
			fail("stuck", `{tag}: #{table.concat(HouseLayout.stuck(plan), ",")}`)
		end
		local grid = HouseRoute.grid(plan) :: HouseRoute.Grid
		HouseRoute.block(grid, rects)
		local entry = plan.entry.Position + ((plan.entry * M.Vector3.new(0, 0, -1)) - plan.entry.Position) * 1.5
		for index, r in rects do
			local x, z = HouseRoute.reach(grid, entry.X, entry.Z, r)
			if not x or not z or HouseRoute.toRect(x, z, r) > R.Stand + 1e-6 or not HouseRoute.sees(grid, x, z, (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2) then
				fail("danny", `{tag}: #{plan.spots[index].id} {plan.spots[index].item}`)
				continue
			end
			local points = HouseRoute.path(grid, entry.X, entry.Z, x, z)
			local ax, az = entry.X, entry.Z
			for k, q in points or {} do
				for _, w in grid.walls do
					if HouseRoute.cuts(ax, az, q.x, q.z, w) then
						fail("danny", `{tag}: {plan.spots[index].item}: a leg through a wall`)
					end
				end
				if k > 1 and not HouseRoute.clear(grid, ax, az, q.x, q.z) then
					fail("danny", `{tag}: {plan.spots[index].item}: a leg off the open cells`)
				end
				ax, az = q.x, q.z
			end
			if not points then
				fail("danny", `{tag}: {plan.spots[index].item}: no way`)
			end
		end
		-- its fixtures
		local kinds: { [string]: any } = {}
		for _, f in plan.fixtures do
			kinds[f.kind] = f
		end
		for _, id in FIXTURES[kind] do
			if not kinds[id] then
				fail("fixtures", `{tag}: no {id}`)
			end
		end
		if kind == "mill" then
			local wheel = kinds.pit_wheel
			local r = wheel and fixtureRect(wheel)
			if plan.mirrored or not r or r.x0 > plan.min.X + T.Wall + 1e-6 or byId.millers.min.X < byId.workroom.max.X then
				fail("mill", `{tag}: the pit wheel off the -X wall, or the miller's room on the -X side`)
			end
		end
		if #plan.windows < #plan.rooms then
			fail("windows", `{tag}: {#plan.windows} windows`)
		end
	end
	check(`{kind}: the same seed, the same plan (HouseLayout's and Countryside's own)`, bad.same == nil, bad.same)
	check(`{kind}: inside its Box × Scale ({W} × {D} studs, {K.Ceiling} high), one way out`, bad.box == nil, bad.box)
	check(`{kind}: its rooms ({table.concat(ROOMS[kind], ", ")} …), inside the box`, bad.rooms == nil, bad.rooms)
	check(`{kind}: the front door (doors[1], {T.FrontDoor} wide, at the origin), every room reached through doorways at least {T.Door} wide`, bad.doors == nil, bad.doors)
	check(`{kind}: {leastPieces} – {mostPieces} pieces ({K.Spots[1]} – {K.Spots[2]}) each in its room, on the floor, turned square`, bad.count == nil and bad.spots == nil, bad.count or bad.spots)
	check(`{kind}: {K.Collectibles.Count[1]} – {K.Collectibles.Count[2]} collectibles, each once, never ★; exactly {K.Stars} ★`, bad.collectibles == nil and bad.stars == nil, bad.collectibles or bad.stars)
	check(`{kind}: its own things ({table.concat(THINGS[kind], ", ")})`, bad.things == nil, bad.things)
	check(`{kind}: no piece on another or on a solid fixture`, bad.overlap == nil, bad.overlap)
	check(`{kind}: every piece out of the front door (HouseLayout.stuck)`, bad.stuck == nil, bad.stuck)
	check(`{kind}: Danny's spot beside every piece (within Route.Stand, no wall between), his way there through no wall, on open cells`, bad.danny == nil, bad.danny)
	check(`{kind}: its fixtures ({table.concat(FIXTURES[kind], ", ")}), windows in its rooms`, bad.fixtures == nil and bad.windows == nil and bad.mill == nil, bad.fixtures or bad.windows or bad.mill)
	local sets = 0
	for _ in itemSets do
		sets += 1
	end
	check(`{kind}: the seeds give other sets of pieces ({sets} of {SEEDS})`, sets >= SEEDS / 2)
end
check("the cabin, the lodge and the cottage mirrored both ways; the mill never", variety.cabin["mirrored true"] and variety.cabin["mirrored false"] and variety.lodge["mirrored true"]
	and variety.lodge["mirrored false"] and variety.cottage["mirrored true"] and variety.cottage["mirrored false"] and not variety.mill["mirrored true"])
check("the lodge with four rooms and a hall, now and then three (the great room the hall's depth); the cottage with three, now and then two",
	variety.lodge["5 rooms"] and variety.lodge["4 rooms"] and variety.cottage["3 rooms"] and variety.cottage["2 rooms"])
check(`a plan is quick to make (average {string.format("%.3f", totalTime / (SEEDS * 4))} s, slowest {string.format("%.3f", slowest)} s)`, totalTime / (SEEDS * 4) < 0.5)
do
	-- 8.3 economy: a legendary not in the move owner's book first
	local seed, kind = nil :: number?, "lodge"
	for s = 1, 400 do
		for _, spot in HouseLayout.plan(s, kind).spots do
			if Items[spot.item].rarity == "legendary" then
				seed = s
			end
		end
		if seed then
			break
		end
	end
	local book: { [string]: any } = {}
	local first: string? = nil
	for _, spot in HouseLayout.plan(seed or 1, kind).spots do
		if Items[spot.item].rarity == "legendary" then
			first = spot.item
			book[spot.item] = { n = 1, best = 1 }
		end
	end
	local again: string? = nil
	for _, spot in HouseLayout.plan(seed or 1, kind, book).spots do
		if Items[spot.item].rarity == "legendary" then
			again = spot.item
		end
	end
	check(`a legendary find (the lodge, seed {seed}: {first}): with it in the book, another legendary (one not found yet: {again})`, seed ~= nil and first ~= nil and again ~= nil and again ~= first)
end

-- ── Built ──────────────────────────────────────────────────────────────────────
for _, kind in Countryside.Kinds do
	local K = C[kind]
	local most, worstSeed = 0, 0
	local bad: string? = nil
	for n, plan in plans[kind] do
		if n > 8 then
			break
		end
		local origin = HouseInterior.slot(n)
		local ok, model, pieces = pcall(HouseInterior.build, plan, origin)
		local tag = `{kind} {plan.seed}`
		if not ok then
			bad = bad or `{tag}: {model}`
			continue
		end
		local parts, lights = 0, 0
		local names: { [string]: number } = {}
		local materials: { [string]: boolean } = {}
		for _, obj in model:GetDescendants() do
			if obj.ClassName == "PointLight" or obj.ClassName == "SurfaceLight" or obj.ClassName == "SpotLight" then
				lights += 1
				if obj.Shadows == true or (obj.Range or 0) > 40 or (obj.Brightness or 0) > 3 then
					bad = bad or `{tag}: a light`
				end
			end
			if not obj:IsA("BasePart") then
				continue
			end
			parts += 1
			names[obj.Name] = (names[obj.Name] or 0) + 1
			if obj.Name == "Wall" or obj.Name == "Floor" then
				materials[obj.Name .. " " .. tostring(obj.Material)] = true
			end
			local s, p = obj.Size, obj.CFrame.Position
			if not (finite(s.X) and finite(s.Y) and finite(s.Z) and s.X > 0 and s.Y > 0 and s.Z > 0 and finite(p.X) and finite(p.Y) and finite(p.Z)) then
				bad = bad or `{tag}: {obj.Name} unsound`
			end
			if obj.Anchored ~= true then
				local piece = obj.Parent
				local root = piece and piece.PrimaryPart
				if not (root and root.Anchored == true) then
					bad = bad or `{tag}: {obj.Name} loose`
				end
			end
		end
		if most < parts then
			most, worstSeed = parts, plan.seed
		end
		local count = 0
		for id, piece in pieces do
			count += 1
			local spot: any = nil
			for _, s in plan.spots do
				if s.id == id then
					spot = s
				end
			end
			if not spot or piece:GetAttribute("FurnitureId") ~= spot.item or piece:GetAttribute("Spot") ~= id then
				bad = bad or `{tag}: the piece at #{id}`
			end
		end
		if parts > K.InteriorMaxParts or lights < 1 or lights > 12 or count ~= #plan.spots or not names.ExitSign or not names.Ceiling then
			bad = bad or `{tag}: {parts} parts, {lights} lights, {count} pieces of {#plan.spots}`
		end
		local function has(list: { string }): boolean
			for _, name in list do
				if not names[name] then
					return false
				end
			end
			return true
		end
		local function made(key: string): boolean
			for m in materials do
				if string.find(m, key, 1, true) then
					return true
				end
			end
			return false
		end
		local own = if kind == "cabin" then has({ "Pipe", "Net", "Lifebuoy", "Float" }) and made("Wall WoodPlanks") and not names.Wainscot
			elseif kind == "lodge" then has({ "Firebox", "Antler", "Wainscot" }) and made("Wall Plaster")
			elseif kind == "mill" then has({ "Hopper", "Vat", "PitWheel", "Shaft", "Chain", "Lantern", "Pipe" }) and made("Wall Cobblestone") and made("Wall Plaster")
			else has({ "Range", "Wainscot", "Lace" }) and made("Floor CeramicTiles") and made("Wall Plaster")
		if not own then
			bad = bad or `{tag}: its own looks`
		end
		HouseInterior.destroy(model)
	end
	check(`{kind}: built within {K.InteriorMaxParts} parts (the busiest: seed {worstSeed}, {most}), modest lights, anchored, a piece at every spot, the EXIT sign, its own style and fixtures`, bad == nil, bad)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
