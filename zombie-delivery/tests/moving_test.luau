-- 7.0 prototype, MOVES (shared/MovingRules.luau, Config.Moving): the carry's speeds and hands, the damage, the truck
-- bed's packing (first-fit, a turn of 90°, stacking only on a flat top, what may come out), a whole move on fake
-- furniture (pick, help, let go, load, unload, the refusals), the phases and the clock, the pay and the stars, the
-- contract card's estimate and the contract's house on the map. Run with tests/run_tests.py.
local Rules = require("./MovingRules")
local Config = require("./Config")
local Map = require("./Map")

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
check("both × 0.75, pair × 0.8, drag × 0.35", near(Rules.speedFactor("both", 9), 0.75) and near(Rules.speedFactor("pair", 9), 0.8) and near(Rules.speedFactor("drag", 9), 0.35))
check("the carry's walk", near(Rules.carrySpeed(14, "pair", 8), 11.2) and near(Rules.carrySpeed(14, "drag", 8), 4.9))
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
check("a lamp: the floor before a top (the lowest place first)", d ~= nil and d.base == 0 and d.row == 7 and d.col == 7, d and `{d.col},{d.row} base {d.base}`)
check("the free ones: nothing on them", Rules.free(p, 1) and Rules.free(p, 2) and Rules.free(p, 3) and not Rules.free(p, 99))
local turn = Rules.newPacking(7, 10, 7.4, 0.5)
local long = Rules.place(turn, 1, { X = 8, Y = 1, Z = 3 })
check("too wide across: turned 90° to fit along", long ~= nil and long.turned and long.cols == 6 and long.rows == 16 and long.base == 0)
local chest = Rules.place(p, 4, { X = 7, Y = 2, Z = 3 })
check("a chest turned onto the free floor beside them", chest ~= nil and chest.turned and chest.row == 7 and chest.col == 9 and chest.base == 0, chest and `{chest.col},{chest.row} base {chest.base}`)
local onTop = Rules.place(p, 5, { X = 7, Y = 2, Z = 3 })
check("the floor full for another: flat on the lowest top (the chest's)", onTop ~= nil and onTop.col == 9 and near(onTop.base, 2), onTop and `{onTop.col},{onTop.row} base {onTop.base}`)
check("the chest can't come out from under it", not Rules.free(p, 4) and Rules.free(p, 5) and not Rules.remove(p, 4))
-- fill the floor, then the next goes on a flat top
local q = Rules.newPacking(4, 4, 6, 1)
Rules.place(q, 1, { X = 4, Y = 2, Z = 4 })
local top = Rules.place(q, 2, { X = 2, Y = 2, Z = 2 })
check("on the floor's full, stacked flat on top", top ~= nil and top.base == 2 and top.top == 4)
check("what rests on another keeps it in", not Rules.free(q, 1) and Rules.free(q, 2) and not Rules.remove(q, 1))
local tall = Rules.fit(q, { X = 2, Y = 5, Z = 2 })
check("never through the roof", tall == nil)
check("a thing too big for the bed never fits", Rules.fit(Rules.newPacking(7, 10, 7.4, 0.5), { X = 8, Y = 1, Z = 11 }) == nil)
-- not on an uneven top: a 1-high and a 2-high side by side, a 4 × 4 slab over both does not fit
local u = Rules.newPacking(4, 4, 10, 1)
Rules.place(u, 1, { X = 2, Y = 1, Z = 4 })
Rules.place(u, 2, { X = 2, Y = 2, Z = 4 })
check("never on an uneven top", Rules.fit(u, { X = 4, Y = 1, Z = 4 }) == nil)
check("removing the top one frees the bottom", Rules.remove(q, 2) and Rules.free(q, 1) and Rules.remove(q, 1) and #q.placed == 0 and q.heights[1] == 0)
local f = Rules.newPacking(2, 2, 2, 1)
check("an empty bed is empty", Rules.fill(f) == 0)
Rules.place(f, 1, { X = 2, Y = 1, Z = 2 })
check("the fill: the share of the room taken", near(Rules.fill(f), 0.5))
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
local BED = { width = T.Bed.Width, length = T.Bed.Length, height = T.Bed.Height, cell = T.Bed.Cell }
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
-- a bed full: no room
local tiny = Rules.newMove({ { id = 1, item = "fridge", room = "k", star = false }, { id = 2, item = "fridge", room = "k", star = false } }, defs,
	{ width = 3, length = 3, height = 6, cell = 0.5 }, 0, 60)
Rules.pick(tiny, 1, ME)
Rules.load(tiny, ME)
Rules.pick(tiny, 2, ME)
placed, noWhy = Rules.load(tiny, ME)
check("no room: it stays in your hands", placed == nil and noWhy == "noroom" and tiny.things[2].state == "carried", noWhy)
check("the words for it", string.find(Rules.whyText("noroom"), "bigger truck", 1, true) ~= nil and #Rules.whyText("whatever") > 0)
-- nothing after the move ended
local over = Rules.newMove(spots, defs, BED, 0, 60)
over.phase = "done"
ok, why = Rules.pick(over, 3, ME)
check("nothing moves once it is over", not ok and why == "over", why)

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
local function loadAll(m: Rules.Move, list: { number })
	for _, s in list do
		Rules.pick(m, s, ME)
		Rules.load(m, ME)
	end
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
local late = Rules.result(whole, "late", 600)
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
check("the card's estimate: everything whole, ★ with its bonus", Rules.estimate(spots, defs) == math.floor(values + starred * (P.Star - 1) + 0.5))

-- The contract's place ---------------------------------------------------------------------------------------------------

check("at least one contract, the prologue Marge's", #T.Contracts >= 1 and T.Contracts[1].id == "marge" and T.Contracts[1].client == "Marge")
for _, contract in T.Contracts do
	local home = Map.home(contract.home)
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
local truck = nil
for _, def in Config.Cars do
	if def.id == T.Truck then
		truck = def
	end
end
check("the truck is a company vehicle", truck ~= nil and truck.company == true)
check("the numbers", T.Fade > 0 and T.Fade < 1 and T.Slots >= 2 and T.Tether >= 4 and T.Grace > 0 and T.Bed.Cell > 0 and Config.Robust.Limits.Moving > 0)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
