-- 7.0 prototype, MOVES (shared/MovingRules.luau, Config.Moving): the carry's speeds and hands, the damage, the truck
-- bed's packing (a turn of 90°, resting on the highest top with enough of it level there, an overhang, never on one
-- lamp or one edge, a fragile thing on top, the fill with the cracks and slivers nothing goes into, what may come
-- out), Marge's whole house loaded in seven orders into the old truck's bed and the ZDC Van's bay (every thing left out
-- has no room, nothing overlaps or floats, how full; lying on its side), a whole move on fake furniture (pick, help, let go,
-- load, unload, the refusals), the phases and the clock, the pay and the stars, the contract card's estimate and the
-- contract's house on the map. Run with tests/run_tests.py.
local Rules = require("./MovingRules")
local Config = require("./Config")
local Map = require("./Map")
local HouseLayout = require("./HouseLayout")
local FurnitureLooks = require("./FurnitureLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local T = Config.Moving

-- The carry ----------------------------------------------------------------------------------------------------------

check("hand: 1 − weight × 0.03", near(Rules.speedFactor("hand", 1), 0.97) and near(Rules.speedFactor("hand", 5), 0.85) and near(Rules.speedFactor("hand", 10), 0.7))
check("hand never under MinHand", Rules.speedFactor("hand", 99) >= T.Speed.MinHand and Rules.speedFactor("hand", 0 / 0) <= 1)
check("both × 0.75, pair × 0.7 (8.1: two carry slowly, was 0.8), drag × 0.35", near(Rules.speedFactor("both", 9), 0.75) and near(Rules.speedFactor("pair", 9), 0.7) and near(Rules.speedFactor("drag", 9), 0.35))
check("the carry's walk", near(Rules.carrySpeed(14, "pair", 8), 9.8) and near(Rules.carrySpeed(14, "drag", 8), 4.9))
check("dragging is the slowest, a light thing in a hand the fastest", Rules.speedFactor("drag", 1) < Rules.speedFactor("both", 1) and Rules.speedFactor("both", 1) < Rules.speedFactor("hand", 1))
check("a hand free only with a hand thing", Rules.hands("hand") == 1 and Rules.hands("both") == 2 and Rules.hands("pair") == 2 and Rules.hands("drag") == 2)
local thing = { class = "pair", helper = nil } :: any
check("a pair thing alone is dragged, with a helper carried", Rules.mode(thing) == "drag" and Rules.mode({ class = "pair", helper = 7 } :: any) == "pair")
check("hand and both are what they are", Rules.mode({ class = "hand" } :: any) == "hand" and Rules.mode({ class = "both" } :: any) == "both")
check("7.x: a both thing with Danny on its other side walks as a pair", Rules.mode({ class = "both", helper = 3 } :: any) == "pair")

-- Damage -------------------------------------------------------------------------------------------------------------

local D = T.Damage
check("no damage from a small drop", Rules.fallDamage(D.SafeDrop, false) == 0 and Rules.fallDamage(1, true) == 0 and Rules.fallDamage(0 / 0, true) == 0)
check("a fall: PerStud a stud over SafeDrop", near(Rules.fallDamage(D.SafeDrop + 5, false), 5 * D.PerStud))
check("fragile breaks faster", near(Rules.fallDamage(D.SafeDrop + 5, true), math.min(1, 5 * D.PerStud * D.Fragile)))
check("never more than all of it", Rules.fallDamage(1000, true) == 1 and Rules.hitDamage(1e6, false) == 1)
check("a bite: PerHp of the health lost", near(Rules.hitDamage(10, false), 10 * D.PerHp) and Rules.hitDamage(-5, false) == 0)
check("a death drops it hard", near(Rules.deathDamage(false), D.Death) and Rules.deathDamage(true) > Rules.deathDamage(false))
check("the truck's knocks", near(Rules.truckDamage(50, false), 50 * D.PerTruckHp) and Rules.truckDamage(0, true) == 0)
local vase = { condition = 1 } :: any
check("hurt takes it off", not Rules.hurt(vase, 0.3) and near(vase.condition, 0.7) and not Rules.broken(vase))
check("…and says when it broke", Rules.hurt(vase, 0.6) and Rules.broken(vase) and not Rules.hurt(vase, 0.5) and vase.condition == 0)
check("nothing for nothing", not Rules.hurt({ condition = 1 } :: any, 0 / 0))

-- The truck bed ------------------------------------------------------------------------------------------------------

local K = T.Pack
-- A thing set straight onto the bed (the test's own: for the support cases), on the highest top under it.
local function put(pk: Rules.Packing, spot: number, col: number, row: number, cols: number, rows: number, tall: number): Rules.Placement
	local base = 0
	for r = row, row + rows - 1 do
		for c = col, col + cols - 1 do
			base = math.max(base, pk.heights[(r - 1) * pk.cols + c])
		end
	end
	local at: Rules.Placement = { spot = spot, col = col, row = row, cols = cols, rows = rows, base = base, top = base + tall, turned = false }
	for r = row, row + rows - 1 do
		for c = col, col + cols - 1 do
			local i = (r - 1) * pk.cols + c
			pk.heights[i] = math.max(pk.heights[i], at.top)
		end
	end
	table.insert(pk.placed, at)
	return at
end
-- Replays a bed's placements in order (its own count, not the module's): what is wrong with it, nil when nothing.
-- Inside the bed and under the roof; each on the highest top under it when it went in, supported there (Pack.Support
-- of it within Pack.Level, round its middle); no two overlapping; the heights its tops.
local function audit(pk: Rules.Packing): string?
	local tops = table.create(pk.cols * pk.rows, 0)
	for n, at in pk.placed do
		if at.col < 1 or at.row < 1 or at.col + at.cols - 1 > pk.cols or at.row + at.rows - 1 > pk.rows then
			return `{at.spot} outside the bed`
		elseif at.top > pk.height + 1e-3 then
			return `{at.spot} through the roof`
		end
		local high, count = 0, 0
		local c0, c1, r0, r1 = math.huge, -math.huge, math.huge, -math.huge
		for r = at.row, at.row + at.rows - 1 do
			for c = at.col, at.col + at.cols - 1 do
				high = math.max(high, tops[(r - 1) * pk.cols + c])
			end
		end
		for r = at.row, at.row + at.rows - 1 do
			for c = at.col, at.col + at.cols - 1 do
				if tops[(r - 1) * pk.cols + c] >= at.base - K.Level - 1e-3 then
					count += 1
					c0, c1, r0, r1 = math.min(c0, c), math.max(c1, c), math.min(r0, r), math.max(r1, r)
				end
			end
		end
		if math.abs(high - at.base) > 1e-6 then
			return `{at.spot} not on the highest top under it ({at.base} vs {high})`
		elseif at.base > 0 and count < K.Support * at.cols * at.rows - 1e-6 then
			return `{at.spot} on too little ({count} of {at.cols * at.rows} cells)`
		elseif at.base > 0 and not (c0 - 1 < at.col - 1 + at.cols / 2 and c1 > at.col - 1 + at.cols / 2 and r0 - 1 < at.row - 1 + at.rows / 2 and r1 > at.row - 1 + at.rows / 2) then
			return `{at.spot} off balance (its middle not over what holds it)`
		end
		for r = at.row, at.row + at.rows - 1 do
			for c = at.col, at.col + at.cols - 1 do
				local i = (r - 1) * pk.cols + c
				tops[i] = math.max(tops[i], at.top)
			end
		end
		for m = 1, n - 1 do
			local o = pk.placed[m]
			local flat = at.col < o.col + o.cols and o.col < at.col + at.cols and at.row < o.row + o.rows and o.row < at.row + at.rows
			if flat and at.base < o.top - 1e-3 and o.base < at.top - 1e-3 then
				return `{at.spot} overlaps {o.spot}`
			end
		end
	end
	for i = 1, pk.cols * pk.rows do
		if math.abs(tops[i] - pk.heights[i]) > 1e-6 then
			return `the heights are not its tops at cell {i}`
		end
	end
	return nil
end

local p = Rules.newPacking(7, 10, 7.4, 0.5)
check("the bed's grid: 14 × 20 cells of half a stud", p.cols == 14 and p.rows == 20 and #p.heights == 280)
local c1, r1 = Rules.footprint({ X = 2, Y = 1, Z = 1.2 }, 0.5, false)
local c2, r2 = Rules.footprint({ X = 2, Y = 1, Z = 1.2 }, 0.5, true)
check("a footprint in cells, turned swaps it", c1 == 4 and r1 == 3 and c2 == 3 and r2 == 4, `{c1}x{r1} {c2}x{r2}`)
check("an exact size takes no extra cell", (Rules.footprint({ X = 1.5, Y = 1, Z = 0.5 }, 0.5, false)) == 3)
local sofa = { X = 7, Y = 3, Z = 3 }
local a = Rules.place(p, 1, sofa)
check("a sofa across the cab end", a ~= nil and a.col == 1 and a.row == 1 and a.base == 0 and not a.turned and a.cols == 14 and a.rows == 6)
local b = Rules.place(p, 2, { X = 3, Y = 7, Z = 2 })
check("a wardrobe stands on the floor behind it (too tall for its top)", b ~= nil and b.row == 7 and b.col == 1 and b.base == 0, b and `{b.col},{b.row}`)
local d = Rules.place(p, 3, { X = 1, Y = 2, Z = 1 })
check("a lamp snug in the cab's corner, on the sofa (two walls beside it)", d ~= nil and d.base == 3 and d.row == 1 and d.col == 1, d and `{d.col},{d.row} base {d.base}`)
check("the free ones: nothing on them (the lamp keeps the sofa in)", not Rules.free(p, 1) and Rules.free(p, 2) and Rules.free(p, 3) and not Rules.free(p, 99))
local turn = Rules.newPacking(7, 10, 7.4, 0.5)
local long = Rules.place(turn, 1, { X = 8, Y = 1, Z = 3 })
check("too wide across: turned 90° to fit along", long ~= nil and long.turned and long.cols == 6 and long.rows == 16 and long.base == 0)
local chest = Rules.place(p, 4, { X = 7, Y = 2, Z = 3 })
check("a chest turned onto the free floor beside them", chest ~= nil and chest.turned and chest.row == 7 and chest.col == 9 and chest.base == 0, chest and `{chest.col},{chest.row} base {chest.base}`)
local onTop = Rules.place(p, 5, { X = 7, Y = 2, Z = 3 })
check("the floor full for another: flat on the chest's top", onTop ~= nil and onTop.col == 9 and near(onTop.base, 2), onTop and `{onTop.col},{onTop.row} base {onTop.base}`)
check("the chest can't come out from under it", not Rules.free(p, 4) and Rules.free(p, 5) and not Rules.remove(p, 4))
check("the bed so far: every thing where the rules allow", audit(p) == nil, audit(p))
-- fill the floor, then the next goes on a flat top
local q = Rules.newPacking(4, 4, 6, 1)
Rules.place(q, 1, { X = 4, Y = 2, Z = 4 })
local top = Rules.place(q, 2, { X = 2, Y = 2, Z = 2 })
check("on the floor's full, stacked flat on top", top ~= nil and top.base == 2 and top.top == 4)
check("what rests on another keeps it in", not Rules.free(q, 1) and Rules.free(q, 2) and not Rules.remove(q, 1))
local tall = Rules.fit(q, { X = 2, Y = 5, Z = 2 })
check("never through the roof", tall == nil and not Rules.room(q, { X = 2, Y = 5, Z = 2 }))
check("a thing too big for the bed never fits", Rules.fit(Rules.newPacking(7, 10, 7.4, 0.5), { X = 8, Y = 1, Z = 11 }) == nil)
check("…nor one taller than the bed", not Rules.room(Rules.newPacking(7, 10, 7.4, 0.5), { X = 1, Y = 8, Z = 1 }))
check("removing the top one frees the bottom", Rules.remove(q, 2) and Rules.free(q, 1) and Rules.remove(q, 1) and #q.placed == 0 and q.heights[1] == 0)
-- (the packing fix) uneven tops: a thing rests on the highest top under it when enough of it lies level there
do
	-- a sofa (7 × 15 cells turned, the only way into a bed this narrow) on two dressers at its ends, 3.2 high
	local bridge = Rules.newPacking(3.5, 7.5, 7.4, 0.5)
	put(bridge, 1, 1, 1, 7, 4, 3.2)
	put(bridge, 2, 1, 12, 7, 4, 3.2)
	local on = Rules.place(bridge, 3, { X = 7.2, Y = 3.4, Z = 3.2 })
	check("a sofa on two dressers at its ends: it bridges them", on ~= nil and near(on.base, 3.2) and on.turned and on.row == 1, on and `base {on.base}`)
	check("…and keeps both in", not Rules.free(bridge, 1) and not Rules.free(bridge, 2) and Rules.free(bridge, 3))
	-- a bookshelf (9 × 4 cells, the bed's whole floor) over a floor lamp (3 × 3) in its middle: a quarter of it
	local shelf = Rules.newPacking(4.5, 2, 14, 0.5)
	put(shelf, 1, 4, 1, 3, 3, 5.2)
	check("a bookshelf on one lamp: no (a quarter of it held)", Rules.fit(shelf, { X = 4.2, Y = 6.6, Z = 1.6 }) == nil and not Rules.room(shelf, { X = 4.2, Y = 6.6, Z = 1.6 }))
	-- half on a box, half over the air: it would tip; five eighths on it: it rests there, overhanging
	local half = Rules.newPacking(4, 2, 10, 0.5)
	put(half, 1, 1, 1, 4, 4, 2)
	check("half on a box, half over the air: it would tip", Rules.fit(half, { X = 4, Y = 1, Z = 2 }) == nil)
	local most = Rules.newPacking(4, 2, 10, 0.5)
	put(most, 1, 1, 1, 5, 4, 2)
	local over = Rules.fit(most, { X = 4, Y = 1, Z = 2 })
	check("five eighths on it: it rests there, overhanging", over ~= nil and near(over.base, 2) and over.cols == 8, over and over.base)
	-- two tops within Pack.Level of each other are one level; a stud apart, the higher one holds half: no
	local level = Rules.newPacking(4, 4, 10, 1)
	put(level, 1, 1, 1, 2, 4, 1.8)
	put(level, 2, 3, 1, 2, 4, 2)
	local slab = Rules.fit(level, { X = 4, Y = 1, Z = 4 })
	check("tops 0.2 apart are one level: a slab rests on both", slab ~= nil and near(slab.base, 2), slab and slab.base)
	local step = Rules.newPacking(4, 4, 10, 1)
	put(step, 1, 1, 1, 2, 4, 1)
	put(step, 2, 3, 1, 2, 4, 2)
	check("tops a stud apart: not on half of it", Rules.fit(step, { X = 4, Y = 1, Z = 4 }) == nil)
	-- a fragile thing rides on top where it can (little room over it: little goes on it); a sturdy one takes the floor
	local crates = Rules.newPacking(4, 2, 4, 1)
	put(crates, 1, 1, 1, 2, 2, 2)
	local glass = Rules.fit(crates, { X = 1, Y = 1, Z = 1 }, true)
	local box = Rules.fit(crates, { X = 1, Y = 1, Z = 1 })
	check("a fragile thing rides on top, a sturdy one takes the floor", glass ~= nil and glass.base == 2 and box ~= nil and box.base == 0, `{glass and glass.base} {box and box.base}`)
end
-- the fill: up to every top, and to the roof where nothing goes any more
local f = Rules.newPacking(2, 2, 4, 1)
check("an empty bed is empty", Rules.fill(f) == 0)
Rules.place(f, 1, { X = 2, Y = 1, Z = 2 })
check("the fill: the share of the room taken", near(Rules.fill(f), 0.25))
Rules.place(f, 2, { X = 2, Y = 2.5, Z = 2 })
check("a sliver under the roof (no Headroom) counts full", near(Rules.fill(f), 1), Rules.fill(f))
do
	-- two things 3 high with a crack half a stud wide between them: under a roof 5 high the crack counts full
	local crack = Rules.newPacking(3, 2, 5, 0.5)
	put(crack, 1, 1, 1, 2, 4, 3)
	put(crack, 2, 4, 1, 3, 4, 3)
	check("a crack nothing goes into counts full", near(Rules.fill(crack), (20 * 3 + 4 * 5) / (24 * 5)), Rules.fill(crack))
	-- the air under an overhang is taken too (nothing reaches it any more)
	local roof = Rules.newPacking(4, 2, 10, 0.5)
	put(roof, 1, 1, 1, 5, 4, 2)
	Rules.place(roof, 2, { X = 4, Y = 1, Z = 2 })
	check("the air under an overhang counts", near(Rules.fill(roof), 3 / 10), Rules.fill(roof))
end
local w = Rules.newPacking(4, 6, 4, 1)
local at = Rules.place(w, 9, { X = 2, Y = 2, Z = 2 }) :: any
local x, y, z = Rules.where(w, at)
check("a placement's middle from the bed's middle", near(x, -1) and near(y, 1) and near(z, -2), `{x} {y} {z}`)

-- A whole move on fake furniture ---------------------------------------------------------------------------------------

local defs: { [string]: Rules.ItemDef } = {
	sofa = { id = "sofa", name = "Sofa", icon = "🛋", size = { X = 6, Y = 3, Z = 2.8 }, class = "pair", weight = 8, value = 300, fragile = false, room = "living" },
	tv = { id = "tv", name = "TV", icon = "📺", size = { X = 3, Y = 2, Z = 0.8 }, class = "both", weight = 4, value = 250, fragile = true, room = "living" },
	lamp = { id = "lamp", name = "Lamp", icon = "💡", size = { X = 1, Y = 3, Z = 1 }, class = "hand", weight = 1, value = 40, fragile = true, room = "living" },
	clock = { id = "clock", name = "Grandpa's Clock", icon = "🕰", size = { X = 1.5, Y = 6, Z = 1 }, class = "both", weight = 6, value = 400, fragile = true, room = "hall" },
	box = { id = "box", name = "Box of memories", icon = "📦", size = { X = 2, Y = 1.5, Z = 1.5 }, class = "hand", weight = 3, value = 120, fragile = false, room = "attic" },
	fridge = { id = "fridge", name = "Fridge", icon = "🧊", size = { X = 3, Y = 6, Z = 3 }, class = "pair", weight = 10, value = 200, fragile = false, room = "kitchen" },
}
local spots: { Rules.Spot } = {
	{ id = 1, item = "sofa", room = "living", star = false },
	{ id = 2, item = "tv", room = "living", star = false },
	{ id = 3, item = "lamp", room = "living", star = false },
	{ id = 4, item = "clock", room = "hall", star = true },
	{ id = 5, item = "box", room = "attic", star = true },
	{ id = 6, item = "fridge", room = "kitchen", star = true },
	{ id = 7, item = "piano", room = "living", star = false }, -- no such furniture: left out
	{ id = 4, item = "lamp", room = "hall", star = false }, -- a spot twice: once
}
local BIG = T.Beds.movingtruck -- (7.x van moves: the old Moving Truck's big bed; the van's is tests/farmmove_test.luau's)
local BED = { width = BIG.Width, length = BIG.Length, height = BIG.Height, cell = BIG.Cell }
local move = Rules.newMove(spots, defs, BED, 100, 600)
check("a thing a spot, unknown furniture and doubles left out", #move.order == 6 and move.things[7] == nil and move.things[4].item == "clock")
check("everything at home, whole, the clock running", move.things[1].state == "home" and move.things[1].condition == 1 and move.phase == "running" and move.endsAt == 700)
local counts = Rules.counts(move)
check("the checklist: 6 things, 3 ★, none out", counts.total == 6 and counts.stars == 3 and counts.out == 0 and counts.home == 6)
local ME, YOU, THEM = 11, 22, 33
check("pick up the lamp", (Rules.pick(move, 3, ME)) and move.things[3].carrier == ME and Rules.holding(move, ME) == 3)
local ok, why = Rules.pick(move, 2, ME)
check("one thing at a time", not ok and why == "full", why)
ok, why = Rules.pick(move, 3, YOU)
check("not one somebody holds", not ok and why == "taken", why)
check("the lamp into the truck", Rules.load(move, ME) ~= nil and move.things[3].state == "truck" and Rules.holding(move, ME) == nil)
local placed, noWhy = Rules.load(move, ME)
check("nothing to load with empty hands", placed == nil and noWhy == "empty", noWhy)
-- the sofa: lifted alone it is dragged; a crew mate takes the other end
check("lift the sofa alone: dragged", (Rules.pick(move, 1, ME)) and Rules.mode(move.things[1]) == "drag")
ok, why = Rules.help(move, 1, ME)
check("you can't help yourself", not ok and why == "yours", why)
check("a crew mate helps: carried by two", (Rules.help(move, 1, YOU)) and Rules.mode(move.things[1]) == "pair")
local _, role = Rules.holding(move, YOU)
check("the helper holds it too", role == "helper")
ok, why = Rules.help(move, 1, THEM)
check("two at most", not ok and why == "helped", why)
ok, why = Rules.help(move, 2, THEM)
check("only a pair thing takes a helper", not ok and why == "gone", why)
placed, noWhy = Rules.load(move, YOU)
check("the helper does not load it", placed == nil and noWhy == "helper", noWhy)
local spot, down = Rules.release(move, YOU)
check("the helper lets go: dragged again", spot == 1 and not down and move.things[1].helper == nil and move.things[1].state == "carried")
spot, down = Rules.release(move, ME)
check("the carrier sets it down", spot == 1 and down and move.things[1].state == "ground" and move.things[1].carrier == nil)
check("picked up again from the ground", (Rules.pick(move, 1, YOU)) and Rules.load(move, YOU) ~= nil)
check("the clock and the fridge in too", (Rules.pick(move, 4, ME)) and Rules.load(move, ME) ~= nil and (Rules.pick(move, 6, THEM)) and Rules.load(move, THEM) ~= nil)
-- 7.x: Danny's other side of a "both" thing (help's `both`): the pair's walk for both
check("7.x: the TV lifted alone: both hands", (Rules.pick(move, 2, ME)) and Rules.mode(move.things[2]) == "both")
ok, why = Rules.help(move, 2, THEM)
check("…a player's Help lift is for pair things only", not ok and why == "single", why)
ok, why = Rules.help(move, 2, THEM, true)
check("…Danny takes its other side: carried by two", ok and Rules.mode(move.things[2]) == "pair" and move.things[2].helper == THEM, why)
check("…its carrier loads it: both pairs of hands free", Rules.load(move, ME) ~= nil and Rules.holding(move, THEM) == nil and Rules.holding(move, ME) == nil)
check("the box too", (Rules.pick(move, 5, ME)) and Rules.load(move, ME) ~= nil)
counts = Rules.counts(move)
check("all out, all ★", counts.out == 6 and counts.starsOut == 3 and counts.home == 0)
check("the truck's fill shows", Rules.fill(move.packing) > 0 and Rules.fill(move.packing) < 1)
-- unload: the last one in that nothing rests on
local last = Rules.lastOut(move)
check("Unload takes the last one in", last == 5, last)
local out, outWhy = Rules.unload(move, ME)
check("…into your hands", out == 5 and outWhy == nil and move.things[5].state == "carried" and move.things[5].carrier == ME)
out, outWhy = Rules.unload(move, ME)
check("not with your hands full", out == nil and outWhy == "full", outWhy)
check("and back in", Rules.load(move, ME) ~= nil)
-- the truck's prompts (the owner's report: Unload over Load at the same spot, E fumbled): never both
local function shows(open: boolean, carrying: boolean, inside: boolean): string
	local load, unload, back = Rules.truckPrompts(open, carrying, inside)
	return `{if load then "L" else "-"}{if unload then "U" else "-"}{if back then "B" else "-"}`
end
check("carrying at an open back: Load only (no Unload, the back's E never shuts it)", shows(true, true, true) == "L--" and shows(true, true, false) == "L--", shows(true, true, true))
check("carrying at a shut back: only the back's E (to open it)", shows(false, true, true) == "--B" and shows(false, true, false) == "--B", shows(false, true, true))
check("empty hands, something inside an open back: Unload only (and the back's E)", shows(true, false, true) == "-UB", shows(true, false, true))
check("empty hands, an empty truck: neither Load nor Unload", shows(true, false, false) == "--B" and shows(false, false, false) == "--B", shows(true, false, false))
check("empty hands, a shut back with things in: no Unload", shows(false, false, true) == "--B", shows(false, false, true))
for _, open in { true, false } do
	for _, carrying in { true, false } do
		for _, inside in { true, false } do
			local load, unload = Rules.truckPrompts(open, carrying, inside)
			check(`never Load and Unload at once ({open}, {carrying}, {inside})`, not (load and unload))
		end
	end
end
-- a bed full: no room
local tiny = Rules.newMove({ { id = 1, item = "fridge", room = "k", star = false }, { id = 2, item = "fridge", room = "k", star = false } }, defs,
	{ width = 3, length = 3, height = 6, cell = 0.5 }, 0, 60)
Rules.pick(tiny, 1, ME)
Rules.load(tiny, ME)
Rules.pick(tiny, 2, ME)
placed, noWhy = Rules.load(tiny, ME)
check("no room: it stays in your hands", placed == nil and noWhy == "noroom" and tiny.things[2].state == "carried", noWhy)
check("the words for it", string.find(Rules.whyText("noroom"), "to the Wall first", 1, true) ~= nil and #Rules.whyText("whatever") > 0)
-- nothing after the move ended
local over = Rules.newMove(spots, defs, BED, 0, 60)
over.phase = "done"
ok, why = Rules.pick(over, 3, ME)
check("nothing moves once it is over", not ok and why == "over", why)

-- Marge's house into the truck (the packing fix) -----------------------------------------------------------------------
-- Her contract's plan (shared/HouseLayout.luau) and the furniture (shared/FurnitureLooks.luau) as server/Moving.luau
-- makes them, loaded thing by thing through the move's own Load in several orders (the plan's, the biggest first, the
-- smallest first, four shuffles); each refused one is set down and tried again later, until nothing more goes in. Then
-- every thing left out really has no room, the bed passes the audit, the share of the bed the things take and the fill.
-- The beds by their numbers: the old moving truck's 7 × 10 × 7.4 and the ZDC Van's bay, 6.2 × 6.4 × 4.3.

do
	local marge = T.Contracts[1]
	local plan = HouseLayout.plan(marge.seed, marge.kind)
	local furniture: { [string]: Rules.ItemDef } = {}
	for key, item in FurnitureLooks.Items do
		furniture[key] = { id = item.id, name = item.name, icon = item.icon, size = { X = item.size.X, Y = item.size.Y, Z = item.size.Z }, class = item.class, weight = item.weight, value = item.value, fragile = item.fragile, room = item.room }
	end
	local house: { Rules.Spot } = {}
	for _, s in plan.spots do
		table.insert(house, { id = s.id, item = s.item, room = s.room, star = s.star })
	end
	local function volume(size: Rules.Size): number
		return size.X * size.Y * size.Z
	end
	local MOVER = 7
	local function orders(m: Rules.Move): { { number } }
		local list = { table.clone(m.order) }
		local big = table.clone(m.order)
		table.sort(big, function(i, j)
			local vi, vj = volume(m.things[i].size), volume(m.things[j].size)
			return vi > vj or (vi == vj and i < j)
		end)
		table.insert(list, big)
		local small = table.clone(big)
		table.sort(small, function(i, j)
			local vi, vj = volume(m.things[i].size), volume(m.things[j].size)
			return vi < vj or (vi == vj and i < j)
		end)
		table.insert(list, small)
		for seed = 1, 4 do
			local o = table.clone(m.order)
			local r = seed * 7919
			for i = #o, 2, -1 do
				r = (r * 1103515245 + 12345) % 2147483648
				local j = r % i + 1
				o[i], o[j] = o[j], o[i]
			end
			table.insert(list, o)
		end
		return list
	end
	local NAMES = { "the plan's order", "the biggest first", "the smallest first", "shuffle 1", "shuffle 2", "shuffle 3", "shuffle 4" }
	-- Loads everything that goes in; returns the move, the share of the bed the things take and the fill.
	local function pack(bed: Rules.Bed, order: { number }): (Rules.Move, number, number)
		local m = Rules.newMove(house, furniture, bed, 0, 600)
		local more = true
		while more do
			more = false
			for _, spot in order do
				if m.things[spot].state ~= "truck" then
					Rules.pick(m, spot, MOVER)
					if Rules.load(m, MOVER) then
						more = true
					else
						Rules.release(m, MOVER)
					end
				end
			end
		end
		local inside = 0
		for _, at in m.packing.placed do
			inside += volume(m.things[at.spot].size)
		end
		return m, inside / (bed.width * bed.length * bed.height), Rules.fill(m.packing)
	end
	local function report(label: string, bed: Rules.Bed, m: Rules.Move, share: number, full: number)
		print(string.format("      %s, %s × %s × %s: %d of %d things in, %d%% of the bed, %d%% full", label, bed.width, bed.length, bed.height, #m.packing.placed, #m.order, math.floor(share * 100 + 0.5), math.floor(full * 100 + 0.5)))
	end
	-- every thing left out has no room; the bed passes the audit; the models sit inside the bed on their base
	local function sound(m: Rules.Move): string?
		for _, spot in m.order do
			local thing = m.things[spot]
			if thing.state ~= "truck" and Rules.canLoad(m, spot) then
				return `{thing.name} was refused but has room`
			elseif thing.state == "truck" and (thing.place == nil or table.find(m.packing.placed, thing.place) == nil) then
				return `{thing.name} in the truck without its place`
			end
		end
		local pk = m.packing
		for _, placed in pk.placed do
			local px, py, pz = Rules.where(pk, placed)
			local halfX, halfZ = placed.cols * pk.cell / 2, placed.rows * pk.cell / 2
			if math.abs(px) + halfX > pk.cols * pk.cell / 2 + 1e-6 or math.abs(pz) + halfZ > pk.rows * pk.cell / 2 + 1e-6 or not near(py - (placed.top - placed.base) / 2, placed.base) then
				return `{m.things[placed.spot].name}'s model outside the bed`
			end
		end
		return audit(pk)
	end

	local BED = { width = 7, length = 10, height = 7.4, cell = 0.5 }
	local rare = Config.Furniture.Collectibles.Count -- (8.0 SANDBOX: a house's collectibles come besides its 18 to 24 things)
	check(`Marge's house: 18 to 24 things and {rare[1]}-{rare[2]} collectibles, more than the truck takes`, #house >= 18 + rare[1] and #house <= 24 + rare[2])
	local probe = Rules.newMove(house, furniture, BED, 0, 600)
	local shares, fills = 0, 0
	local best, worst, worstFill = 0, 1, 1
	local planShare, planFill = 0, 0
	local packed: Rules.Move? = nil
	for n, order in orders(probe) do
		local m, share, full = pack(BED, order)
		report(NAMES[n], BED, m, share, full)
		check(`the default bed, {NAMES[n]}: everything sound`, sound(m) == nil, sound(m))
		shares += share
		fills += full
		best, worst, worstFill = math.max(best, share), math.min(worst, share), math.min(worstFill, full)
		if n == 1 then
			planShare, planFill, packed = share, full, m
		end
	end
	check("the truck, the plan's order: over 60% of it things, 85% full when nothing more goes in", planShare >= 0.6 and planFill >= 0.85, `{planShare} {planFill}`)
	check("the truck, any order: 80% full on average when nothing more goes in, never under 70%", fills / 7 >= 0.8 and worstFill >= 0.7, `{fills / 7} {worstFill}`)
	check("the truck, any order: on average 60% of it things (the old flat first-fit: 56%, 63% full)", shares / 7 >= 0.6, shares / 7)
	check("…the biggest first: over 70%", best >= 0.7, best)
	check("…on average 80% of the best order's things, the worst order 70%", shares / 7 >= 0.8 * best and worst >= 0.7 * best, `{shares / 7} {worst} vs {best}`)

	-- unloading: only what nothing rests on comes out, the last loaded first; the heights follow
	if packed then
		local m = packed
		local stuck: number? = nil
		for _, placed in m.packing.placed do
			if not Rules.free(m.packing, placed.spot) then
				stuck = placed.spot
				break
			end
		end
		check("Marge's load in the truck: something rests on another (stacked)", stuck ~= nil)
		if stuck then
			local got, why = Rules.unload(m, MOVER, stuck)
			check("…which can't come out from under it", got == nil and why == "under" and m.things[stuck].state == "truck", why)
		end
		local outs, fine = 0, true
		while true do
			local last = Rules.lastOut(m)
			if not last then
				break
			end
			local newest = true -- nothing loaded after it is free (it is the last free one)
			for index = #m.packing.placed, 1, -1 do
				local placed = m.packing.placed[index]
				if placed.spot == last then
					break
				elseif Rules.free(m.packing, placed.spot) then
					newest = false
				end
			end
			local got = Rules.unload(m, MOVER)
			fine = fine and got == last and newest and audit(m.packing) == nil
			Rules.release(m, MOVER)
			outs += 1
		end
		local empty = #m.packing.placed == 0
		for i = 1, m.packing.cols * m.packing.rows do
			empty = empty and m.packing.heights[i] == 0
		end
		check("Unload empties it top first, the last free one each time, the heights rebuilt", fine and empty and outs > 0, outs)
	end

	-- the ZDC Van's bay (6.2 × 6.4 × 4.3; Cell 0.4: its grid 15 × 16 cells, its whole length): the same rules, fewer
	-- things; a tall both / pair piece lies on its side (Pack.Lie), the bed is repacked when one does not go in as it is
	-- (Pack.Repack)
	local VAN = { width = 6.2, length = 6.4, height = 4.3, cell = 0.4 }
	local function vanRun(label: string?): (number, number, number)
		local shares, fills, worst = 0, 0, 1
		for n, order in orders(probe) do
			local m, share, full = pack(VAN, order)
			if label then
				report(NAMES[n], VAN, m, share, full)
				check(`the van, {NAMES[n]}: everything sound`, sound(m) == nil, sound(m))
				local upright = true
				for _, placed in m.packing.placed do
					local thing = m.things[placed.spot]
					upright = upright and placed.top <= 4.3 + 1e-6 and (thing.size.Y <= 4.3 + 1e-6 or placed.lying ~= nil)
				end
				check(`the van, {NAMES[n]}: a piece over 4.3 tall only lies in it, nothing through the roof`, upright)
			end
			shares += share
			fills += full
			worst = math.min(worst, share)
		end
		return shares / 7, fills / 7, worst
	end
	local vanShare, vanFill, vanWorst = vanRun("the van")
	check("the van, any order: on average 60% of it things, 85% full, never under 45% (the old packer: 49%, 62% full)", vanShare >= 0.6 and vanFill >= 0.85 and vanWorst >= 0.45, `{vanShare} {vanFill} {vanWorst}`)
	local lie, repack = K.Lie, K.Repack
	K.Lie, K.Repack = false, false
	local plainShare = vanRun(nil)
	K.Lie, K.Repack = lie, repack
	check("…lying down and repacking take more of Marge's things into the van", vanShare > plainShare, `{vanShare} vs {plainShare}`)
	-- Pack.Lie: a both / pair piece with no place standing lies on its side (a hand thing never; one that stands, stands)
	K.Lie = true
	local bay = Rules.newPacking(6.2, 6.4, 4.3, 0.4)
	local piano = furniture.piano.size
	local laid = Rules.fit(bay, piano, false, true)
	check("Lie: the piano (4.6 tall) lies down in the van", laid ~= nil and laid.lying ~= nil and laid.top <= 4.3 + 1e-6 and Rules.room(bay, piano, true) and not Rules.room(bay, piano), laid and laid.lying)
	local laidSize = if laid then Rules.laid(piano, laid.lying) else piano
	check("…its size on its side: the height swapped", near(laidSize.X * laidSize.Y * laidSize.Z, piano.X * piano.Y * piano.Z) and laidSize.Y < 4.3)
	check("…a hand thing never lies, nor one that stands", Rules.fit(bay, furniture.coat_rack.size, false, false) == nil and (Rules.fit(bay, furniture.armchair.size, false, true) :: any).lying == nil)
	K.Lie = false
	check("…and only with Pack.Lie", Rules.fit(bay, piano, false, true) == nil)
	K.Lie = lie
	-- Pack.Repack: a box and a lamp in first, then a slab the whole floor wide: no room as the bed is, so the movers
	-- repack it (the slab first, the box and the lamp on it); Load says which places changed; Take out still the top ones
	local stack: { [string]: Rules.ItemDef } = {
		box = { id = "box", name = "Box", icon = "📦", size = { X = 2, Y = 1.5, Z = 2 }, class = "hand", weight = 2, value = 40, fragile = false, room = "attic" },
		lamp = { id = "lamp", name = "Lamp", icon = "💡", size = { X = 1, Y = 2, Z = 1 }, class = "hand", weight = 1, value = 40, fragile = true, room = "living" },
		slab = { id = "slab", name = "Slab", icon = "🪨", size = { X = 6, Y = 2, Z = 6.4 }, class = "pair", weight = 9, value = 200, fragile = false, room = "hall" },
		sofa = { id = "sofa", name = "Sofa", icon = "🛋", size = { X = 6, Y = 3, Z = 2.8 }, class = "pair", weight = 8, value = 300, fragile = false, room = "living" },
	}
	local stackSpots: { Rules.Spot } = {
		{ id = 1, item = "box", room = "attic", star = false },
		{ id = 2, item = "lamp", room = "living", star = false },
		{ id = 3, item = "slab", room = "hall", star = false },
		{ id = 4, item = "sofa", room = "living", star = false },
	}
	local function loadOne(m: Rules.Move, spot: number): (Rules.Placement?, string?, { number }?)
		Rules.pick(m, spot, MOVER)
		local at, why, moved = Rules.load(m, MOVER)
		if not at then
			Rules.release(m, MOVER)
		end
		return at, why, moved
	end
	local rp = Rules.newMove(stackSpots, stack, VAN, 0, 600)
	loadOne(rp, 1)
	loadOne(rp, 2)
	check("Repack: the slab has no room as the bed is, but Load would take it (canLoad)", not Rules.room(rp.packing, stack.slab.size, true) and Rules.canLoad(rp, 3))
	local slabAt, _, moved = loadOne(rp, 3)
	local box, lampAt = rp.things[1].place, rp.things[2].place
	check("…Load repacks the bed: the slab on the floor, the box and the lamp on it", slabAt ~= nil and slabAt.base == 0 and box ~= nil and lampAt ~= nil and near(box.base, 2) and near(lampAt.base, 2)
		and table.find(rp.packing.placed, box) ~= nil and audit(rp.packing) == nil, slabAt and slabAt.base)
	check("…and says which places changed (the box's and the lamp's)", moved ~= nil and #moved == 2 and table.find(moved, 1) ~= nil and table.find(moved, 2) ~= nil)
	check("…Take out still takes a top one, never the slab under them", Rules.lastOut(rp) ~= 3 and Rules.lastOut(rp) ~= nil and not Rules.free(rp.packing, 3))
	check("…a sofa has no room even repacked: canLoad says so, Load refuses", not Rules.canLoad(rp, 4) and select(2, loadOne(rp, 4)) == "noroom" and rp.things[4].state == "ground")
	K.Repack = false
	local plain = Rules.newMove(stackSpots, stack, VAN, 0, 600)
	loadOne(plain, 1)
	loadOne(plain, 2)
	check("…without Pack.Repack: no room for the slab", not Rules.canLoad(plain, 3) and select(2, loadOne(plain, 3)) == "noroom")
	K.Repack = repack
	-- an odd bed (not whole cells, low): still sound
	local ODD = { width = 5.3, length = 7.9, height = 4.4, cell = 0.5 }
	local odd, oddShare = pack(ODD, probe.order)
	check("an odd bed (5.3 × 7.9 × 4.4): sound, and things in", sound(odd) == nil and oddShare > 0.3, sound(odd) or oddShare)
end

-- The phases and the clock -------------------------------------------------------------------------------------------

check("running → horde → done", Rules.advance("running", "horde") == "horde" and Rules.advance("horde", "deliver") == "done")
check("the clock runs out: late", Rules.advance("running", "timeout") == "late" and Rules.advance("horde", "timeout") == "late")
check("called off, lost", Rules.advance("horde", "cancel") == "cancelled" and Rules.advance("running", "lose") == "failed")
check("no second horde, nothing after the end", Rules.advance("horde", "horde") == nil and Rules.advance("done", "deliver") == nil and Rules.advance("late", "cancel") == nil)
check("the ends are ends", Rules.over("done") and Rules.over("cancelled") and not Rules.over("running") and not Rules.over("horde"))
local clock = Rules.newMove(spots, defs, BED, 0, T.Time)
check("the clock: nothing due at first", Rules.due(clock, 10) == nil)
check("the horde at HordeAt left", Rules.due(clock, T.Time - T.HordeAt) == "horde")
clock.phase = "horde"
check("…once", Rules.due(clock, T.Time - T.HordeAt + 1) == nil)
check("time's up at 0", Rules.due(clock, T.Time) == "timeout" and Rules.left(clock, T.Time + 5) == 0)
check("12 minutes, the horde at 3:00 left", T.Time == 720 and T.HordeAt == 180)

-- The pay --------------------------------------------------------------------------------------------------------------

local P = T.Pay
local function fresh(): Rules.Move
	local m = Rules.newMove(spots, defs, BED, 0, 600)
	return m
end
-- (7.x van moves: loaded and driven to the Wall: delivered, on time unless `at` is past the clock)
local function loadAll(m: Rules.Move, list: { number }, at: number?)
	for _, s in list do
		Rules.pick(m, s, ME)
		Rules.load(m, ME)
	end
	Rules.deliver(m, at or 0)
end
local whole = fresh()
loadAll(whole, { 1, 2, 3, 4, 5, 6 })
local r = Rules.result(whole, "done", 600) -- delivered with no time left: no time bonus
local values = (300 + 250 + 40 + 400 + 120 + 200) * P.Scale
local starred = (400 + 120 + 200) * P.Scale
check("Σ value × condition", near(r.base, values) and r.delivered == 6 and r.left == 0)
check("★ things × 1.5", near(r.starBonus, starred * (P.Star - 1)))
check("no time left, no time bonus", r.timeBonus == 0 and r.total == math.floor(values + starred * (P.Star - 1) + 0.5))
check("everything whole and every ★: 5 stars, the XP by the value brought", r.stars == 5
	and r.xp == math.min(P.XpMax, math.floor(P.Xp + (300 + 250 + 40 + 400 + 120 + 200) / P.XpPerValue + 5 * P.XpPerStar + 0.5)), r.xp)
do -- 7.0 review: a one-lamp move earns a little XP, not a full move's
	local one = fresh()
	loadAll(one, { 1 })
	local small = Rules.result(one, "done", 600)
	check("one lamp: a little XP", small.xp < r.xp / 2 and small.xp >= P.Xp, small.xp)
end
local quick = Rules.result(whole, "done", 300) -- half the time left
check("the time bonus: TimeBonus × the share left", near(quick.timeBonus, (values + starred * (P.Star - 1)) * P.TimeBonus * 0.5) and quick.total > r.total)
local lateMove = fresh()
loadAll(lateMove, { 1, 2, 3, 4, 5, 6 }, 600) -- (7.x van moves: delivered after the clock ran out)
local late = Rules.result(lateMove, "late", 600)
check("late: × LateShare, 3 stars at most", late.total == math.floor((values + starred * (P.Star - 1)) * P.LateShare + 0.5) and late.stars <= 3)
local partial = fresh()
loadAll(partial, { 1, 2, 3 })
local pr = Rules.result(partial, "done", 600)
check("a ★ left behind: 3 stars at most, the rest unpaid", pr.stars <= 3 and pr.left == 3 and pr.delivered == 3 and near(pr.base, (300 + 250 + 40) * P.Scale))
local smashed = fresh()
loadAll(smashed, { 1, 2, 3, 4, 5, 6 })
smashed.things[2].condition = 0.1 -- the TV broke
smashed.things[1].condition = 0.5 -- the sofa scuffed
local sr = Rules.result(smashed, "done", 600)
check("a broken thing pays nothing and costs its fine", sr.broken == 1 and near(sr.fine, 250 * P.Scale * P.BrokenFine))
check("a scuffed one pays its condition", near(sr.base, (150 + 40 + 400 + 120 + 200) * P.Scale))
check("…and fewer stars", sr.stars < 5 and sr.stars >= 1)
local none = Rules.result(fresh(), "done", 0)
check("nothing loaded: nothing paid, 1 star", none.total == 0 and none.stars == 1 and none.left == 6)
local off = Rules.result(whole, "cancelled", 0)
check("called off: nothing, no stars, no XP", off.total == 0 and off.stars == 0 and off.xp == 0 and off.delivered == 0)
check("lost: nothing either", Rules.result(whole, "failed", 0).total == 0)
local fined = fresh()
loadAll(fined, { 2 })
fined.things[2].condition = 0
check("never below nothing", Rules.result(fined, "done", 0).total == 0)
-- 7.2 review: what reached the Wall late (Counts.late): server/Moving.luau ends a move "late" only with something late
check("7.2 review: the things delivered late counted (all of the late move's, none of the one on time)", Rules.counts(lateMove).late == 6 and Rules.counts(whole).late == 0
	and Rules.counts(fresh()).late == 0)
-- 7.2 review: a chapter's move is done (server/Moving.luau chapterDone) only with every ★ thing at the Wall whole
-- (Rules.starsHome): one thing and FINISH is no chapter done. A ★ thing no van can take at all (too big for its empty bed,
-- lying down too, and not one that rides the hitch: Marge's Grandfather Clock in the ZDC Van) is not asked for.
check("7.2 review: every ★ thing at the Wall whole: the chapter's done", Rules.starsHome(whole))
check("…a ★ thing left behind, or nothing delivered: not", not Rules.starsHome(partial) and not Rules.starsHome(fresh()))
do
	local cracked = fresh()
	loadAll(cracked, { 1, 2, 3, 4, 5, 6 })
	cracked.things[4].condition = 0.1 -- (the ★ clock broke on the way)
	check("…a ★ thing broken: not", not Rules.starsHome(cracked))
	local vanBed = { width = T.Beds.zdcvan.Width, length = T.Beds.zdcvan.Length, height = T.Beds.zdcvan.Height, cell = T.Beds.zdcvan.Cell }
	local tall = table.clone(defs)
	tall.clock = { id = "clock", name = "Grandfather Clock", icon = "🕰", size = { X = 2, Y = 7.2, Z = 1.4 }, class = "pair", weight = 7, value = 900, fragile = true, room = "living" }
	local clockSpots: { Rules.Spot } = { { id = 1, item = "box", room = "attic", star = true }, { id = 2, item = "clock", room = "living", star = true }, { id = 3, item = "lamp", room = "living", star = false } }
	local inVan = Rules.newMove(clockSpots, tall, vanBed, 0, 600)
	check("…(the 7.2 clock never fits the ZDC Van's bay, not even lying down)", not Rules.canLoad(inVan, 2))
	loadAll(inVan, { 1 })
	check("…a ★ thing no van can take is not asked for: the box home whole is the chapter", Rules.starsHome(inVan) and inVan.things[2].state ~= "delivered")
end
check("the card's estimate: everything whole, ★ with its bonus", Rules.estimate(spots, defs) == math.floor(values + starred * (P.Star - 1) + 0.5))

-- The contract's place ---------------------------------------------------------------------------------------------------

check("at least one contract, the prologue Marge's", #T.Contracts >= 1 and T.Contracts[1].id == "marge" and T.Contracts[1].client == "Marge")
for _, contract in T.Contracts do
	if contract.kind == "farm" then
		-- 7.x farm move: a farm stands at a Map.Places place (its site in Config.Moving.Sites), out of the safe zone
		local place: Map.Place? = nil
		for _, p in Map.Places do
			if p.id == contract.place then
				place = p
			end
		end
		check(`{contract.id}: its place is on the map, out of the safe zone, its site set`, place ~= nil and not Map.isSafe(place.x, place.z) and T.Sites[contract.kind] ~= nil
			and #T.Sites[contract.kind].Doors == 2, contract.place)
		continue
	end
	local home = Map.home(contract.home or "")
	check(`{contract.id}: its house is a Suburbs house`, home ~= nil and home.kind == "house" and home.district == "suburbs", contract.home)
	if home then
		check(`{contract.id}: the truck parks on a road in front`, Map.onRoad(home.park.x, home.park.z))
		check(`{contract.id}: out of the safe zone (the zombies come)`, not Map.isSafe(home.door.x, home.door.z))
		local dist = math.sqrt((home.door.x - Map.Depot.x) ^ 2 + (home.door.z - Map.Depot.z) ^ 2)
		check(`{contract.id}: a short drive from the depot`, dist < 1400, dist)
	end
end
local dx, dz = Map.Depot.x + T.DropOff[1], Map.Depot.z + T.DropOff[2]
check("the drop-off (the Wall) is in the safe zone", Map.isSafe(dx, dz))
check("the board is in the safe zone", Map.isSafe(Map.Depot.x + T.Board[1], Map.Depot.z + T.Board[2]))
check("the drop-off reaches the road in front of the depot", T.DropRadius >= 15 and T.DropOff[2] + T.DropRadius > Map.BlockSize / 2 + 4)
check("7.x van moves: a move goes with the owner's ZDC Van, its bed set", T.Van == "zdcvan" and T.Beds[T.Van] ~= nil and T.Beds[T.Van].Cell > 0 and T.VanAgain > 0)
check("the numbers", T.Fade > 0 and T.Fade < 1 and T.Slots >= 2 and T.Tether >= 4 and T.Grace > 0 and Config.Robust.Limits.Moving > 0)
local van = nil
for _, def in Config.Cars do -- (7.x: the ZDC Van is the one car a player owns, Config.Cars)
	if def.id == T.Van then
		van = def
	end
end
check("7.x: the move's van is the player's own car (Config.Cars)", van ~= nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
