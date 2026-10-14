-- 8.3 SANDBOX, the Roblox badges' rules (shared/SandboxBadgeRules.luau, Config.SandboxBadges): the list as the owner
-- asked (10 – 14 badges, short English names and descriptions, every id 0 until he sets them up), the ids checked (0,
-- junk: not set up), Studio off unless the flag, which moment earns which badge (a move's end, a sale, a piece home,
-- the player's state), the TOP MOVERS board's leader on a full server, the moves' counter in the save (only a real save
-- written with the flag) and the admin panel's line. Run with tests/run_tests.py (the server: tests/sandboxbadges_runtime_test.luau).
local Config = require("./Config")
local Rules = require("./SandboxBadgeRules")
local CollectionBookRules = require("./CollectionBookRules")
local UpgradeRules = require("./UpgradeRules")
local VanPaintRules = require("./VanPaintRules")
local WarehouseLevels = require("./WarehouseLevels")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function list(t: { string }): string
	return table.concat(t, ",")
end
local B = Config.SandboxBadges

-- ── The list ───────────────────────────────────────────────────────────────
local count, keysOk, words = 0, true, true
for key, def in B.Badges do
	count += 1
	keysOk = keysOk and table.find(Rules.Order, key) ~= nil
	words = words and type(def.name) == "string" and #def.name >= 3 and #def.name <= 30 and type(def.description) == "string"
		and #def.description >= 10 and #def.description <= 80 and string.find(def.description, "%.$") ~= nil
		and not string.find(def.name .. def.description, "[\128-\255]") -- (plain English: no accents, no emoji in Roblox's form)
end
check("10 – 14 badges, each of Order in Config and nothing else", count >= 10 and count <= 14 and count == #Rules.Order and keysOk, count)
local seen = {}
local unique = true
for _, key in Rules.Order do
	unique = unique and not seen[key] and B.Badges[key] ~= nil
	seen[key] = true
end
check("Order: each key once, each in Config.SandboxBadges.Badges", unique)
check("names and descriptions: short plain English, a description a sentence", words)
local names = {}
local namesUnique = true
for _, def in B.Badges do
	namesUnique = namesUnique and not names[def.name]
	names[def.name] = true
end
check("every name its own", namesUnique)
local allZero = true
for _, def in B.Badges do
	allZero = allZero and def.id == 0
end
check("every id 0 as shipped (the owner sets them up): nothing ready", allZero and #Rules.ready() == 0)
local statesOk = true
for _, key in Rules.States do
	statesOk = statesOk and table.find(Rules.Order, key) ~= nil
end
check("States: badge keys (the state's: not cleanMove, the sales or the board)", statesOk and table.find(Rules.States, "cleanMove") == nil
	and table.find(Rules.States, "firstSale") == nil and table.find(Rules.States, "topMover") == nil)
check("the numbers: 10 moves, level 5 (the Logistics centre, the top), a full server's players, retries", B.Moves == 10
	and B.Level == WarehouseLevels.Count and B.TopPlayers == Config.Sandbox.MaxPlayers and B.TopEvery > 0 and B.Tries >= 2 and B.Wait > 0
	and B.Studio == false and B.Flag == "sandboxMovesKept" and Rules.Flag == B.Flag)

-- ── The ids ────────────────────────────────────────────────────────────────
local saved = {}
for key, def in B.Badges do
	saved[key] = def.id
end
B.Badges.firstMove.id = 2124567890123
B.Badges.painted.id = 77
check("idOf: a whole id over 0 is the badge's", Rules.idOf("firstMove") == 2124567890123 and Rules.idOf("painted") == 77)
check("ready(): the keys set up, in Order", list(Rules.ready()) == "firstMove,painted", list(Rules.ready()))
local junkOk = Rules.idOf("tenMoves") == nil and Rules.idOf("nope") == nil and Rules.idOf(nil) == nil and Rules.idOf(5) == nil and Rules.def("nope") == nil
for _, junk in { -3, 0.5, 0 / 0, math.huge, "123", true, 2 ^ 60 } do
	B.Badges.tenMoves.id = junk :: any
	junkOk = junkOk and Rules.idOf("tenMoves") == nil
end
check("idOf: 0, a negative, a fraction, NaN, inf, a string, junk, no such key: not set up (nil)", junkOk)
for key, id in saved do
	B.Badges[key].id = id
end
check("live: on a live server yes, in Studio no (Studio off)", Rules.live(false) and not Rules.live(true))
B.Studio = true
check("live: in Studio with Config.SandboxBadges.Studio on", Rules.live(true))
B.Studio = false

-- ── A move's end ───────────────────────────────────────────────────────────
local function move(states: { string }): any
	local m = { order = {}, things = {} }
	for index, state in states do
		table.insert(m.order, index)
		m.things[index] = { state = state }
	end
	return m
end
local f, c = Rules.finished(move({ "delivered", "ground" }), { how = "done", broken = 0 })
check("finished: done with a piece home, nothing broken: finished and clean", f and c)
f, c = Rules.finished(move({ "delivered" }), { how = "late", broken = 2 })
check("… late with a piece home, two broken: finished, not clean", f and not c)
f, c = Rules.finished(move({ "ground", "truck" }), { how = "done", broken = 0 })
check("… nothing home: not finished", not f and not c)
f = Rules.finished(move({ "delivered" }), { how = "cancelled", broken = 0 })
local g = Rules.finished(move({ "delivered" }), { how = "failed", broken = 0 })
check("… called off or lost: not finished (whatever came home)", not f and not g)
check("… junk: not finished", not Rules.finished(nil, nil) and not Rules.finished({}, { how = "done" }) and not Rules.finished(move({ "delivered" }), "done"))
check("fromMove: not finished: nothing", #Rules.fromMove(false, true, 10) == 0)
check("fromMove: the first, clean", list(Rules.fromMove(true, true, 1)) == "firstMove,cleanMove")
check("fromMove: the ninth, not clean", list(Rules.fromMove(true, false, 9)) == "firstMove")
check("fromMove: the tenth (and on)", list(Rules.fromMove(true, false, 10)) == "firstMove,tenMoves" and list(Rules.fromMove(true, true, 25)) == "firstMove,tenMoves,cleanMove")

-- ── Sales, pieces home ─────────────────────────────────────────────────────
check("fromSale: a sale", list(Rules.fromSale("sale", 120, 0)) == "firstSale")
check("fromSale: a sale with a hot piece in it", list(Rules.fromSale("sale", 120, 1)) == "firstSale,hotSale")
check("fromSale: the stands' income, nothing for nothing, junk: nothing", #Rules.fromSale("income", 50, 3) == 0 and #Rules.fromSale("sale", 0, 1) == 0
	and #Rules.fromSale("sale", 0 / 0, 1) == 0 and #Rules.fromSale(nil, 5, nil) == 0 and list(Rules.fromSale("sale", 5, "x")) == "firstSale")
local legendaryItem, plainItem = nil, nil
for _, item in CollectionBookRules.Pieces do
	if CollectionBookRules.rarityOf(item) == "legendary" then
		legendaryItem = legendaryItem or item
	elseif CollectionBookRules.rarityOf(item) == Config.Collection.Order[1] then
		plainItem = plainItem or item
	end
end
check("fromAdded: a legendary piece came home", legendaryItem ~= nil and list(Rules.fromAdded(legendaryItem)) == "legendary", legendaryItem)
check("fromAdded: a common one, an unknown one, junk: nothing", plainItem ~= nil and #Rules.fromAdded(plainItem) == 0 and #Rules.fromAdded("no_such_piece") == 0 and #Rules.fromAdded(nil) == 0)

-- ── The state ──────────────────────────────────────────────────────────────
check("upgraded: none bought, the warehouse at its start, junk: no", not Rules.upgraded(UpgradeRules.empty()) and not Rules.upgraded({ warehouse = WarehouseLevels.Start })
	and not Rules.upgraded(nil) and not Rules.upgraded({ lights = "x" }))
check("upgraded: a level of the lights, the warehouse grown: yes", Rules.upgraded({ lights = 1 }) and Rules.upgraded({ warehouse = WarehouseLevels.Start + 1 }))
local paint = VanPaintRules.empty()
check("painted: the factory's look, nothing bought: no", not Rules.painted(paint) and not Rules.painted(nil) and not Rules.painted({ owned = "x", worn = 5 }))
VanPaintRules.buy(paint, "white")
check("painted: Arctic white bought (and worn)", Rules.painted(paint))
check("painted: bought, the factory's worn again: still (it was bought)", Rules.painted({ owned = { alpine = true }, worn = table.clone(VanPaintRules.Default) }))
check("painted: a free item 'owned' or an unknown one: no", not Rules.painted({ owned = { cream = true, zdc = true, bogus = true }, worn = table.clone(VanPaintRules.Default) }))

local empty = Rules.stateOf({}, false)
check("stateOf: a new profile: nothing (level 1, the book empty)", empty.moves == 0 and not empty.shown and empty.legendary == 0 and empty.found == 0
	and empty.total == #CollectionBookRules.Pieces and empty.warehouse == WarehouseLevels.Start and not empty.upgraded and not empty.painted)
check("fromState: a new profile earns nothing", #Rules.fromState(empty) == 0 and #Rules.fromState(Rules.stateOf(nil, nil)) == 0)
local book = CollectionBookRules.empty()
CollectionBookRules.record(book, legendaryItem :: string, 0.8)
local state = Rules.stateOf({ sandboxMoves = 3, collectionBook = book, sandboxUpgrades = { lights = 2 }, vanPaint = paint }, true)
check("stateOf: the counter, a piece on show, the book's legendary, the upgrades, the paint", state.moves == 3 and state.shown and state.legendary == 1
	and state.found == 1 and state.upgraded and state.painted and state.warehouse == WarehouseLevels.Start)
check("fromState: firstMove, firstShow, legendary, firstUpgrade, painted", list(Rules.fromState(state)) == "firstMove,firstShow,legendary,firstUpgrade,painted",
	list(Rules.fromState(state)))
CollectionBookRules.fill(book)
local full = Rules.stateOf({ sandboxMoves = 12, collectionBook = book, sandboxUpgrades = { warehouse = 5 } }, false)
check("fromState: ten moves, the book full, the warehouse at level 5 (grown: an upgrade too)", list(Rules.fromState(full)) == "firstMove,tenMoves,legendary,fullBook,firstUpgrade,warehouse5",
	list(Rules.fromState(full)))
local four = Rules.fromState(Rules.stateOf({ sandboxUpgrades = { warehouse = 4 } }, false))
check("fromState: level 4 is not level 5", list(four) == "firstUpgrade", list(four))
local onlyStates = true
for _, key in Rules.fromState(full) do
	onlyStates = onlyStates and table.find(Rules.States, key) ~= nil
end
check("fromState: only keys of States", onlyStates)

-- ── The TOP MOVERS board ───────────────────────────────────────────────────
local rows = {
	{ userId = 1, value = 9000, rank = 1 },
	{ userId = 2, value = 4000, rank = 2 },
	{ userId = 3, value = 100, rank = 3 },
	{ userId = 4, value = 0, rank = 4 },
}
check("topOf: alone at the top of a full board (4 players)", Rules.topOf(rows, 4) == 1)
check("topOf: three players: nobody (not a full server)", Rules.topOf({ rows[1], rows[2], rows[3] }, 4) == nil)
check("topOf: five players (one without a plot): still the leader", Rules.topOf({ rows[1], rows[2], rows[3], rows[4], { userId = 5, value = 0, rank = 4 } }, 4) == 1)
check("topOf: a tie at the top: nobody", Rules.topOf({ { userId = 1, value = 500, rank = 1 }, { userId = 2, value = 500, rank = 1 }, rows[3], rows[4] }, 4) == nil)
check("topOf: everybody at $0: nobody", Rules.topOf({ { userId = 1, value = 0, rank = 1 }, { userId = 2, value = 0, rank = 1 }, { userId = 3, value = 0, rank = 1 }, { userId = 4, value = 0, rank = 1 } }, 4) == nil)
check("topOf: junk: nobody", Rules.topOf(nil, 4) == nil and Rules.topOf({ "x", "y", "z", "w" }, 4) == nil and Rules.topOf({}, 0 / 0) == nil)

-- ── The save ───────────────────────────────────────────────────────────────
check("movesFromSave: a real save written with the flag keeps its count", Rules.movesFromSave({ money = 10, sandboxMovesKept = true, sandboxMoves = 7 }) == 7)
check("movesFromSave: without the flag (an older save), a new player, a lock-only record: 0", Rules.movesFromSave({ money = 10, sandboxMoves = 7 }) == 0
	and Rules.movesFromSave(nil) == 0 and Rules.movesFromSave({ lock = { job = "x" }, sandboxMovesKept = true, sandboxMoves = 3 }) == 0)
check("movesFromSave: junk counts checked (a fraction down, under 0, NaN, a string: 0; a huge one capped)", Rules.movesFromSave({ money = 1, sandboxMovesKept = true, sandboxMoves = 4.7 }) == 4
	and Rules.movesFromSave({ money = 1, sandboxMovesKept = true, sandboxMoves = -2 }) == 0 and Rules.movesFromSave({ money = 1, sandboxMovesKept = true, sandboxMoves = 0 / 0 }) == 0
	and Rules.movesFromSave({ money = 1, sandboxMovesKept = true, sandboxMoves = "9" }) == 0 and Rules.movesFromSave({ money = 1, sandboxMovesKept = true, sandboxMoves = 1e300 }) == 1e9)
check("count: one more; junk is 0 before; never past the cap", Rules.count(0) == 1 and Rules.count(9) == 10 and Rules.count(nil) == 1 and Rules.count(0 / 0) == 1 and Rules.count(1e9) == 1e9)

-- ── The admin panel's line ─────────────────────────────────────────────────
local none = Rules.summary(nil, nil)
check("summary: none set up says so (and where the guide is)", string.find(none, "No badge is set up", 1, true) ~= nil and string.find(none, "BADGES.md", 1, true) ~= nil, none)
B.Badges.firstMove.id = 11
B.Badges.topMover.id = 12
local some = Rules.summary(true, 3)
check("summary: 2 of 12 set up, awarded here, the count, the names set up and not", string.find(some, `2 of {#Rules.Order} set up`, 1, true) ~= nil
	and string.find(some, "awarded on this server", 1, true) ~= nil and string.find(some, "3 awarded", 1, true) ~= nil
	and string.find(some, "Set up: First Move, Top Mover.", 1, true) ~= nil and string.find(some, "Id 0 (off): Seasoned Mover", 1, true) ~= nil, some)
local studio = Rules.summary(false, 0)
check("summary: in Studio with the flag off: not awarded here", string.find(studio, "not awarded here", 1, true) ~= nil, studio)
for key, id in saved do
	B.Badges[key].id = id
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
