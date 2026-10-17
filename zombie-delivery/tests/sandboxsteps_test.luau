-- 8.0 SANDBOX, the guide's steps (shared/SandboxSteps.luau; client/SandboxGuide.luau draws them): every row of the
-- owner's table gives its words and its target (9.7 runs: the lobby's: walk to a portal, pick a difficulty, load the
-- truck, finish or beat the clock; no driving), a step done once goes quiet, the path (straight), the collection's state
-- read. Run with tests/run_tests.py.
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local SandboxSteps = require("./SandboxSteps")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- A state as client/SandboxGuide.luau fills it: no move, nothing anywhere (then the fields given).
local function state(fields: { [string]: any }): SandboxSteps.State
	local s: { [string]: any } = {
		plot = 2,
		move = false,
		inside = false,
		carrying = false,
		vanLoad = 0,
		delivered = 0,
		atHouse = false,
		seated = false,
		planning = false,
		planningMine = false,
		stock = 0,
		shown = 0,
		freeStands = nil,
	}
	for key, value in fields do
		s[key] = value
	end
	return s :: any
end

local function show(step: SandboxSteps.Step): string
	return `{step.id} | {step.hint} | {step.target}`
end

-- ── The owner's table, row by row (9.7 runs: the lobby's words, no driving) ─
do
	local step = SandboxSteps.decide(state({}))
	check("9.7 no run: walk to a portal (the nearest portal's pad)", step.id == "portal" and step.hint == "Walk to a portal: step onto a house's glowing pad" and step.target == "portal"
		and not step.nav, show(step))
	step = SandboxSteps.decide(state({ pad = true, padHost = true }))
	check("9.7 on a portal's pad, the host: pick a difficulty (no 3D target: the panel)", step.id == "pick" and step.target == nil
		and string.find(step.hint, "Pick a difficulty", 1, true) == 1, show(step))
	step = SandboxSteps.decide(state({ pad = true }))
	check("9.7 …on the pad, not the host: stay on it", step.id == "waitPad" and step.target == nil and string.find(step.hint, "Stay on the pad", 1, true) == 1, show(step))
	step = SandboxSteps.decide(state({ pad = true, stock = 3 }))
	check("9.7 …the pad wins over the stock", step.id == "waitPad", show(step))
	step = SandboxSteps.decide(state({ move = true }))
	check("9.7 a run started, outside, nothing loaded: walk in through the front door (no E; no drive: the party lands by it)", step.id == "door"
		and step.hint == "Walk in through the front door" and step.target == "door" and string.find(step.hint, "E at", 1, true) == nil and not step.nav, show(step))
	step = SandboxSteps.decide(state({ move = true, inside = true }))
	check("in the house: carry the loot out to the truck (the hint only, no 3D target inside)", step.id == "inside" and step.hint == "Carry the loot out to the truck (E to pick up)"
		and step.target == nil, show(step))
	step = SandboxSteps.decide(state({ move = true, inside = true, carrying = true }))
	check("… carrying inside: still carry it out", step.id == "inside", show(step))
	step = SandboxSteps.decide(state({ move = true, carrying = true }))
	check("carrying, outside: load the truck (its back)", step.id == "load" and step.hint == "Load the truck: walk in or E at its back" and step.target == "van", show(step))
	step = SandboxSteps.decide(state({ move = true, carrying = true, vanLoad = 3 }))
	check("… with things in the truck already: load this one first", step.id == "load", show(step))
	step = SandboxSteps.decide(state({ move = true, vanLoad = 2 }))
	check("9.7 the truck has things, the run is on: finish or beat the clock (the truck's back: FINISH there)", step.id == "finish"
		and string.find(step.hint, "Finish or beat the clock", 1, true) == 1 and step.target == "van" and not step.nav, show(step))
	step = SandboxSteps.decide(state({ move = true, vanLoad = 2, inside = true }))
	check("… back in the house: carry more out", step.id == "inside", show(step))
	step = SandboxSteps.decide(state({ stock = 3 }))
	check("stock has pieces, no run: put them on show (an empty stand)", step.id == "show" and step.hint == "Put your pieces on show: E at an empty stand" and step.target == "stand", show(step))
	step = SandboxSteps.decide(state({ stock = 3, freeStands = 2, shown = 1 }))
	check("… some on show already and stands free: still put the rest on show", step.id == "show", show(step))
	step = SandboxSteps.decide(state({ shown = 2 }))
	check("pieces on show: they earn money, walk into another house for more (a portal)", step.id == "earn"
		and step.hint == "Your pieces earn money while you play. Walk into another house for more!" and step.target == "portal" and step.info, show(step))
	step = SandboxSteps.decide(state({ shown = 6, stock = 2, freeStands = 0 }))
	check("… every stand full, more in the stock: they earn (nothing to put up)", step.id == "earn", show(step))
	step = SandboxSteps.decide(state({ stock = 2, freeStands = 0 }))
	check("stock but no free stand and nothing on show: walk to a portal", step.id == "portal", show(step))
	step = SandboxSteps.decide(state({ stock = 2, move = true }))
	check("a run wins over the stock", step.id == "door", show(step))
	step = SandboxSteps.decide(state({ planning = true, planningMine = true }))
	check("the planning open (yours): press LAUNCH", step.id == "plan" and step.target == nil and string.find(step.hint, "LAUNCH", 1, true) ~= nil, show(step))
	step = SandboxSteps.decide(state({ planning = true }))
	check("… a crew's: the owner launches", step.id == "planCrew" and step.target == nil, show(step))
	check("9.7: no contract board, no drive steps (contract, drive, home, back gone)", SandboxSteps.Steps.contract == nil and SandboxSteps.Steps.drive == nil
		and SandboxSteps.Steps.home == nil and SandboxSteps.Steps.back == nil)
	local navs = 0
	for id, def in SandboxSteps.Steps do
		check(`{id}: one sentence in English, its id its key`, def.id == id and #def.hint > 10 and #def.hint <= 80 and string.find(def.hint, "%a") ~= nil, def.hint)
		navs += if def.nav then 1 else 0
		local lower = string.lower(def.hint)
		if string.find(lower, "drive", 1, true) or string.find(lower, "contract", 1, true) then
			check(`{id}: 9.7 no driving, no contract in its words`, false, def.hint)
		end
	end
	check("9.7: no step's arrow stays while you drive (nobody drives)", navs == 0, navs)
end

-- ── Done once: quiet ────────────────────────────────────────────────────────
do
	local done: { [string]: boolean } = {}
	local last: SandboxSteps.Last = {}
	local portal = SandboxSteps.Steps.portal
	local hint, guide = SandboxSteps.visible(portal, done, false)
	check("a new step: the hint and the 3D guide", hint and guide)
	hint, guide = SandboxSteps.visible(SandboxSteps.Steps.inside, done, false)
	check("in the house: the hint, no 3D guide", hint and not guide)
	SandboxSteps.doneBy(state({ pad = true }), done, last)
	check("9.7 on a pad: the portal step is done", done.portal == true and done.pick == nil and done.waitPad == nil)
	hint, guide = SandboxSteps.visible(portal, done, false)
	check("… its hint and guide quiet next time", not hint and not guide)
	SandboxSteps.doneBy(state({ move = true }), done, last)
	check("9.7 the run started: picking and waiting on the pad done too", done.pick == true and done.waitPad == true and done.door == nil)
	SandboxSteps.doneBy(state({ move = true, inside = true }), done, last)
	check("inside: the door is done", done.door == true and done.inside == nil)
	SandboxSteps.doneBy(state({ move = true, carrying = true }), done, last)
	check("out with a piece: the inside step is done", done.inside == true and done.load == nil)
	SandboxSteps.doneBy(state({ move = true, vanLoad = 1 }), done, last)
	check("a piece into the truck: loading is done", done.load == true and done.finish == nil)
	hint, guide = SandboxSteps.visible(SandboxSteps.Steps.load, done, false)
	check("… loading quiet next time", not hint and not guide)
	hint, guide = SandboxSteps.visible(SandboxSteps.Steps.finish, done, true)
	check("… finish the first time: said, its arrow at the truck", hint and guide)
	SandboxSteps.doneBy(state({ stock = 1 }), done, last)
	check("9.7 the run over with something in the truck (it went home): finish is done", done.finish == true)
	SandboxSteps.doneBy(state({ stock = 4 }), done, last)
	check("pieces in the stock: putting them on show is not done", done.show == nil)
	SandboxSteps.doneBy(state({ shown = 1, stock = 3 }), done, last)
	check("one on show: done", done.show == true)
	hint, guide = SandboxSteps.visible(SandboxSteps.Steps.show, done, false)
	check("… its hint and guide quiet", not hint and not guide)
	check("earn only says something (the client counts it done after a while)", SandboxSteps.Steps.earn.info and done.earn == nil
		and Config.SandboxGuide.InfoSeconds >= 5 and Config.SandboxGuide.InfoSeconds <= 30)
	local fresh: { [string]: boolean } = {}
	local freshLast: SandboxSteps.Last = {}
	SandboxSteps.doneBy(state({ planning = true }), fresh, freshLast)
	check("the planning open: the way to a house was found (the portal step done)", fresh.portal == true and fresh.plan == nil)
	local empty: { [string]: boolean } = {}
	local emptyLast: SandboxSteps.Last = {}
	SandboxSteps.doneBy(state({ move = true }), empty, emptyLast)
	SandboxSteps.doneBy(state({}), empty, emptyLast)
	check("… a run that ended with nothing in the truck: finish not done", empty.finish == nil)
	-- what a save brings along (the first look, or the collection's first state) is not something you did
	local joined: { [string]: boolean } = {}
	local joinedLast: SandboxSteps.Last = {}
	SandboxSteps.doneBy(state({ shown = 4, stock = 2 }), joined, joinedLast)
	check("pieces on show from the save at the first look: putting on show not done", joined.show == nil and joinedLast.shown == 4)
	SandboxSteps.doneBy(state({ shown = 5, stock = 1 }), joined, joinedLast)
	check("… one more put on show while you play: done", joined.show == true)
	joinedLast.shown = nil -- (the client: the collection's first state came, its counts not known before)
	local again: { [string]: boolean } = {}
	SandboxSteps.doneBy(state({ shown = 9 }), again, joinedLast)
	check("… a count not known before is only taken", again.show == nil and joinedLast.shown == 9)
	local crew: { [string]: boolean } = {}
	local crewLast: SandboxSteps.Last = {}
	SandboxSteps.doneBy(state({ move = true, vanLoad = 3, delivered = 2 }), crew, crewLast)
	check("joining a run with things in the truck already: loading not done", crew.load == nil)
	SandboxSteps.doneBy(state({}), crew, crewLast)
	SandboxSteps.doneBy(state({ move = true }), crew, crewLast)
	SandboxSteps.doneBy(state({ move = true, vanLoad = 1 }), crew, crewLast)
	check("… a new run: its first piece loaded counts", crew.load == true)
end

-- ── The words on a touch screen ─────────────────────────────────────────────
do
	local Steps = SandboxSteps.Steps
	check("8.1 walk-in doors: the front door is walked through on a touch screen too (nothing to tap)", SandboxSteps.text(Steps.door, true) == "Walk in through the front door", SandboxSteps.text(Steps.door, true))
	check("… pick up", SandboxSteps.text(Steps.inside, true) == "Carry the loot out to the truck (tap to pick up)", SandboxSteps.text(Steps.inside, true))
	check("… the truck's back", SandboxSteps.text(Steps.load, true) == "Load the truck: walk in or tap at its back", SandboxSteps.text(Steps.load, true))
	check("… a computer keeps E (the door: its own words, no key)", SandboxSteps.text(Steps.door, false) == Steps.door.hint and SandboxSteps.text(Steps.load, false) == Steps.load.hint)
	check("… words without a key unchanged (LAUNCH, FINISH keep their words)", SandboxSteps.text(Steps.plan, true) == Steps.plan.hint and SandboxSteps.text(Steps.finish, true) == Steps.finish.hint
		and SandboxSteps.text(Steps.portal, true) == Steps.portal.hint)
end

-- ── At the house ────────────────────────────────────────────────────────────
do
	local margin = Config.SandboxGuide.HouseMargin
	local curb, door = SandboxMap.House.curb, SandboxMap.House.door
	check("the curb (the truck's place) is at the house", SandboxSteps.atHouse(curb.x, curb.z, margin))
	check("the front door is at the house", SandboxSteps.atHouse(door.x, door.z, margin))
	local plot = SandboxMap.Plots[1]
	check("your plot is not", not SandboxSteps.atHouse(plot.spawn.x, plot.spawn.z, margin))
	local zone = (SandboxMap.zone(SandboxMap.House.id) :: SandboxMap.Zone).rect
	check("9.7 the far end of its run zone is not", not SandboxSteps.atHouse((zone.x0 + zone.x1) / 2, zone.z1, margin))
	local spawn = SandboxMap.Lobby.spawn
	check("9.7 the lobby's spawn is not", not SandboxSteps.atHouse(spawn.x, spawn.z, margin))
end

-- ── The path (9.7: straight: no road to follow) ─────────────────────────────
do
	local out: { number } = {}
	local direct = Config.SandboxGuide.Direct
	local function points(n: number): string
		local parts = {}
		for i = 1, n do
			table.insert(parts, `({out[i * 2 - 1]}, {out[i * 2]})`)
		end
		return table.concat(parts, " ")
	end
	local plot = SandboxMap.Plots[1]
	local portal = SandboxMap.Lobby.portals[1]
	local px, pz = (portal.pad.x0 + portal.pad.x1) / 2, (portal.pad.z0 + portal.pad.z1) / 2
	local n = SandboxSteps.route(plot.spawn.x, plot.spawn.z, px, pz, out, direct)
	check("from your plot to a portal's pad: straight", n == 2 and out[1] == plot.spawn.x and out[2] == plot.spawn.z and out[3] == px and out[4] == pz, points(n))
	local zone = SandboxMap.zone(SandboxMap.House.id) :: SandboxMap.Zone
	local curb = SandboxMap.House.curb
	n = SandboxSteps.route(zone.arrive.x, zone.arrive.z, curb.x, curb.z, out, direct)
	check("from the run's arrival spot to the truck: straight", n <= 2 and out[n * 2 - 1] == curb.x and out[n * 2] == curb.z, points(n))
	n = SandboxSteps.route(plot.spawn.x, plot.spawn.z, plot.board.x, plot.board.z, out, direct)
	check("on your plot to its board: straight", n == 2 and out[3] == plot.board.x and out[4] == plot.board.z, points(n))
	n = SandboxSteps.route(5, 5, 5, 5, out, direct)
	check("already there: two points (a path of nothing)", n == 2, points(n))
	local count = 0
	for _ in out do
		count += 1
	end
	check("the path fits the guide's beams (6 points at most) and makes no table", count <= 12, count)
end

-- ── The collection's state ──────────────────────────────────────────────────
do
	local summary = SandboxSteps.collection({ kind = "state", stock = {
		{ uid = "a", item = "sofa", stand = nil },
		{ uid = "b", item = "lamp", stand = 2 },
		{ uid = "c", item = "vase", stand = 5 },
		{ uid = "d", item = "rug" },
	}, income = 12, stands = 8 }, nil)
	check("the stock (no stand) and those on show (a stand)", summary.stock == 2 and summary.shown == 2 and summary.taken[2] and summary.taken[5] and not summary.taken[1])
	check("… the free stands from the message's stands", summary.free == 6, summary.free)
	summary = SandboxSteps.collection({ kind = "state", stock = { { uid = "b", stand = 1 } }, stands = 8 }, 6)
	check("… the warehouse's own count wins", summary.free == 5, summary.free)
	summary = SandboxSteps.collection({ kind = "state", stock = { { uid = "b", stand = 1 }, { uid = "c" } }, stands = 1 }, nil)
	check("… `stands` no more than are shown: not known (taken as some)", summary.free == nil)
	summary = SandboxSteps.collection(nil, nil)
	check("nothing yet: an empty stock", summary.stock == 0 and summary.shown == 0)
	summary = SandboxSteps.collection({ kind = "state", stock = "broken" }, 4)
	check("a strange message: an empty stock", summary.stock == 0 and summary.free == 4)
	local spots = { { x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 }, { x = 20, y = 0, z = 0 } }
	check("the nearest empty stand", SandboxSteps.nearestFree(11, 0, spots, {}) == 2)
	check("… a taken one skipped", SandboxSteps.nearestFree(11, 0, spots, { [2] = true }) ~= 2)
	check("… all taken: none", SandboxSteps.nearestFree(11, 0, spots, { true, true, true }) == nil)
end

-- ── 8.3: the soft steps (the UPGRADES desk, the market, the PAINT shop) ──────
do
	local Steps = SandboxSteps.Steps
	local UpgradeRules = require("./UpgradeRules") -- (8.3: the ZDC Warehouse's upgrade level k is warehouse level k + 1)
	local G = Config.SandboxGuide
	local nothing: { [string]: boolean } = {}
	local NONE = {} -- (a field given as NONE is left out: not known)
	-- what makes every soft step fit: the warehouse full (4 waiting, 2 free), $2,000 at level 1 (the next level $1,000;
	-- 8.3 economy: every upgrade's first $1,500, PaintMoney $2,000), a hot Jukebox, in the lobby (9.7: its PAINT shop's
	-- booth there) and nothing painted
	local function rich(fields: { [string]: any }?): SandboxSteps.State
		local s: { [string]: any } = {
			stock = 4,
			shown = 0,
			freeStands = 2,
			money = 2000,
			levels = {},
			hot = "Jukebox",
			hotCount = 1,
			hotSold = false,
			day = 20000,
			painted = false,
			vanHome = true,
		}
		for key, value in fields or {} do
			s[key] = value
		end
		local made = state(s) :: any
		for key, value in made do
			if value == NONE then
				made[key] = nil
			end
		end
		return made
	end
	local doneShow = { show = true }
	local function chosen(s: SandboxSteps.State, done: { [string]: boolean }?): SandboxSteps.Step
		return SandboxSteps.choose(s, done or doneShow)
	end

	-- the order and their words
	check("the soft steps' order: grow, hot, upgrade, paint (8.9: then sell)", table.concat(SandboxSteps.Soft, ",") == "grow,hot,upgrade,paint,sell")
	for _, id in SandboxSteps.Soft do
		local def = Steps[id]
		check(`{id}: a soft step (its ✕ dismisses it), not a nav or info one`, def ~= nil and def.soft and not def.nav and not def.info)
	end
	for id, def in Steps do
		check(`{id}: soft only if one of the 8.3 steps (8.4: or Danny's)`, def.soft == (table.find(SandboxSteps.Soft, id) ~= nil or table.find(SandboxSteps.Danny, id) ~= nil))
	end
	local step = chosen(rich())
	local wprices = Config.SandboxUpgrades.List.warehouse.prices -- (8.3: the ZDC Warehouse's level k + 1 costs prices[k])
	local level2, level3 = wprices[1], wprices[2]
	check(`the warehouse full, the next level affordable: "Your warehouse is full: grow it at the UPGRADES desk ({UpgradeRules.money(level2)})" (the desk)`,
		step.id == "grow" and SandboxSteps.words(step, rich()) == `Your warehouse is full: grow it at the UPGRADES desk ({UpgradeRules.money(level2)})` and step.target == "desk", show(step))
	check(`… its price the next level's (the Deliveros Warehouse: level 2 costs {UpgradeRules.money(level2)})`, SandboxSteps.growPrice(rich()) == UpgradeRules.price("warehouse", 0)
		and UpgradeRules.price("warehouse", 0) == level2 and level2 <= 2000)
	check(`… at level 2 (the Workshop) the next one's ({UpgradeRules.money(level3)}) when the money reaches it`, SandboxSteps.growPrice(rich({ levels = { warehouse = 1 }, money = level3 })) == level3
		and SandboxSteps.words(Steps.grow, rich({ levels = { warehouse = 1 }, money = level3 })) == `Your warehouse is full: grow it at the UPGRADES desk ({UpgradeRules.money(level3)})`)
	check("… not short of the money", SandboxSteps.growPrice(rich({ money = level2 - 1 })) == nil)
	check("… not at the top level", SandboxSteps.growPrice(rich({ levels = { warehouse = (UpgradeRules.def("warehouse") :: any).max }, money = 1e9 })) == nil)
	check("… stock as many as the free stands: full", SandboxSteps.growPrice(rich({ stock = 2, freeStands = 2 })) == level2)
	check("… every stand taken, nothing waiting: full", SandboxSteps.growPrice(rich({ stock = 0, shown = 2, freeStands = 0 })) == level2)
	check("… fewer waiting than free stands: not full", SandboxSteps.growPrice(rich({ stock = 1, freeStands = 2 })) == nil)
	check("… nothing at all in the warehouse: not full", SandboxSteps.growPrice(rich({ stock = 0, shown = 0, freeStands = 2 })) == nil)
	check("… the free stands, the levels or the money not known: nothing said", SandboxSteps.growPrice(rich({ freeStands = NONE })) == nil
		and SandboxSteps.growPrice(rich({ levels = NONE })) == nil and SandboxSteps.growPrice(rich({ money = NONE })) == nil)
	step = chosen(rich(), { show = true, grow = true })
	check("grow done: the market's hot piece \"🔥 Your Jukebox is hot today: sell it or show it\" (a free stand, else the chip)",
		step.id == "hot" and SandboxSteps.words(step, rich()) == "🔥 Your Jukebox is hot today: sell it or show it" and step.target == "hot", show(step))
	check("… not when a hot kind was sold today (the market found)", chosen(rich({ hotSold = true }), { show = true, grow = true }).id ~= "hot")
	check("… not without a hot piece in the stock", chosen(rich({ hot = NONE, hotCount = 0 }), { show = true, grow = true }).id ~= "hot")
	step = chosen(rich(), { show = true, grow = true, hot = true })
	local cheapest, price = SandboxSteps.upgradeFor(rich())
	check("then another upgrade in reach (the cheapest, 8.3 economy: all three $1,500, the window's order breaks the tie: the lights): \"💡 New upgrade in reach: Showroom lights at the UPGRADES desk ($1,500)\"",
		step.id == "upgrade" and step.target == "desk" and cheapest == "lights" and price == 1500
		and SandboxSteps.words(step, rich()) == "💡 New upgrade in reach: Showroom lights at the UPGRADES desk ($1,500)", SandboxSteps.words(step, rich()))
	check("… the lights at their top: the next in the window's order at the same price (the van engine)", SandboxSteps.upgradeFor(rich({ levels = { lights = 5 } })) == "engine")
	check("… the lights' next level dearer ($4,000): the engine's $1,500 first", SandboxSteps.upgradeFor(rich({ money = 5000, levels = { lights = 1 } })) == "engine")
	check("… $1,400: none ($1,500 each)", select(2, SandboxSteps.upgradeFor(rich({ money = 1400 }))) == nil)
	check("… never the warehouse (grow's), nor a locked card (More stands below the Big Warehouse)", SandboxSteps.upgradeFor(rich({ money = 1e9, levels = { lights = 5, engine = 3, danny = 3 } })) == nil)
	check("… More stands once the warehouse is the Big Warehouse (level 4)", SandboxSteps.upgradeFor(rich({ money = 1e9, levels = { warehouse = 3, lights = 5, engine = 3, danny = 3 } })) == "stands")
	step = chosen(rich(), { show = true, grow = true, hot = true, upgrade = true })
	check("then the PAINT shop: \"🎨 Make your truck your own at the PAINT SHOP\" (9.7: the lobby's booth; the truck is seen in the runs)", step.id == "paint" and step.target == "paint"
		and SandboxSteps.words(step, rich()) == "🎨 Make your truck your own at the PAINT SHOP", show(step))
	check("… the same words on a phone and a computer (no key in them)", SandboxSteps.text(step, true, SandboxSteps.words(step, rich())) == step.hint
		and SandboxSteps.text(step, false, SandboxSteps.words(step, rich())) == step.hint)
	local afterAll = { show = true, grow = true, hot = true, upgrade = true }
	check(`… at {G.PaintMoney} or more in your pocket`, chosen(rich({ money = G.PaintMoney }), afterAll).id == "paint")
	check("… not under it at the first level", chosen(rich({ money = G.PaintMoney - 1 }), afterAll).id ~= "paint")
	check("… after the first warehouse level bought (past the Garage), whatever the money", chosen(rich({ money = 0, levels = { warehouse = 1 } }), afterAll).id == "paint")
	check("… not with something bought there already, nor before its state came (not known)", chosen(rich({ painted = true }), afterAll).id ~= "paint"
		and chosen(rich({ painted = NONE }), afterAll).id ~= "paint")
	check("… not out of the lobby (9.7: in a run; the booth is in the lobby)", chosen(rich({ vanHome = false }), afterAll).id ~= "paint")
	check("all done: the core's step again (quiet)", chosen(rich(), { show = true, grow = true, hot = true, upgrade = true, paint = true }).id == "show")

	-- the priority: the core loop wins
	check("a run wins over every soft step", chosen(rich({ move = true })).id == "door" and chosen(rich({ move = true, vanLoad = 3 })).id == "finish"
		and chosen(rich({ move = true, inside = true })).id == "inside" and chosen(rich({ move = true, carrying = true })).id == "load")
	check("… the planning too", chosen(rich({ planning = true, planningMine = true })).id == "plan")
	check("… a core step not done yet (putting the pieces on show)", chosen(rich(), nothing).id == "show")
	check("… walking to a portal not done yet (nothing in the warehouse)", chosen(rich({ stock = 0, shown = 0 }), nothing).id == "portal")
	check("… but `earn`, which only says something, gives way", chosen(rich({ stock = 2, shown = 4, freeStands = 0 }), nothing).id == "grow"
		and SandboxSteps.decide(rich({ stock = 2, shown = 4, freeStands = 0 })).id == "earn")
	check("never while something covers the screen (a grip check, a result card, a window)", chosen(rich({ covered = true })).id == "show")
	check("… nor while something else talks (a first-time hint, a soft step just ended)", chosen(rich({ hush = true })).id == "show")
	check("a state without the 8.3 fields: no soft step", chosen(state({ stock = 2, freeStands = 0, shown = 3 }), nothing).id == "earn"
		and chosen(state({ shown = 3 }), { earn = true }).id == "earn")

	-- done by what the player did
	local done: { [string]: boolean } = { show = true }
	local last: SandboxSteps.Last = {}
	SandboxSteps.doneBy(rich(), done, last)
	check("the first look takes the levels, the hot pieces and the day: nothing done", done.grow == nil and done.upgrade == nil and done.hot == nil
		and last.level == 1 and last.bought == 0 and last.hot == 1 and last.day == 20000)
	SandboxSteps.doneBy(rich({ window = "UpgradeUi" }), done, last)
	check("the UPGRADES window opened while grow and upgrade fit: both found", done.grow == true and done.upgrade == true)
	local early: { [string]: boolean } = {}
	SandboxSteps.doneBy(rich({ window = "UpgradeUi", money = 100 }), early, {})
	check("… opened while nothing is in reach: not (it may say so later)", early.grow == nil and early.upgrade == nil)
	local bought: { [string]: boolean } = {}
	local boughtLast: SandboxSteps.Last = {}
	SandboxSteps.doneBy(rich(), bought, boughtLast)
	SandboxSteps.doneBy(rich({ levels = { warehouse = 1 } }), bought, boughtLast)
	check("the warehouse grown while you play: grow done", bought.grow == true and bought.upgrade == nil)
	SandboxSteps.doneBy(rich({ levels = { warehouse = 1, lights = 1 } }), bought, boughtLast)
	check("another upgrade bought: upgrade done", bought.upgrade == true)
	local saved: { [string]: boolean } = {}
	SandboxSteps.doneBy(rich({ levels = { warehouse = 3, engine = 2 } }), saved, {})
	check("… levels a save brought along: nothing", saved.grow == nil and saved.upgrade == nil)
	local market: { [string]: boolean } = {}
	local marketLast: SandboxSteps.Last = {}
	SandboxSteps.doneBy(rich({ hotCount = 2 }), market, marketLast)
	SandboxSteps.doneBy(rich({ hotCount = 1 }), market, marketLast)
	check("a hot piece sold or put on show (fewer hot in the stock): the market found today", market.hot == true)
	SandboxSteps.doneBy(rich({ day = 20001, hotCount = 1 }), market, marketLast)
	check("… a new market day: it may say so again", market.hot == nil and marketLast.day == 20001)
	SandboxSteps.doneBy(rich({ day = 20001, window = "WarehouseUi" }), market, marketLast)
	check("… the STOCK list (or the picker) opened with a hot piece in it: found", market.hot == true)
	local noHot: { [string]: boolean } = {}
	SandboxSteps.doneBy(rich({ hot = NONE, hotCount = 0, window = "WarehouseUi" }), noHot, {})
	check("… opened with no hot piece: not", noHot.hot == nil)
	local turned: { [string]: boolean } = {}
	local turnedLast: SandboxSteps.Last = {}
	SandboxSteps.doneBy(rich({ hotCount = 3 }), turned, turnedLast)
	SandboxSteps.doneBy(rich({ hotCount = 0, day = 20001 }), turned, turnedLast)
	check("… the day turning (yesterday's hot kinds gone from the stock) is not a sale", turned.hot == nil)
	local painted: { [string]: boolean } = {}
	SandboxSteps.doneBy(rich({ window = "VanPaintUi" }), painted, {})
	check("the PAINT shop opened: paint done", painted.paint == true)
	local owns: { [string]: boolean } = {}
	SandboxSteps.doneBy(rich({ painted = true }), owns, {})
	check("… something bought there: paint done", owns.paint == true)

	-- the ✕
	local closed: { [string]: boolean } = { show = true }
	check("the ✕ on a core step is not a dismissal (the guide goes off instead)", not SandboxSteps.dismiss(Steps.portal, closed) and closed.portal == nil)
	check("the ✕ on a soft step: that step gone", SandboxSteps.dismiss(Steps.grow, closed) and closed.grow == true and chosen(rich(), closed).id == "hot")
	check("… the hot one: gone for the session", SandboxSteps.dismiss(Steps.hot, closed) and closed.hot == true and closed.hotGone == true)
	local closedLast: SandboxSteps.Last = { day = 20000, hot = 1 }
	SandboxSteps.doneBy(rich({ day = 20001 }), closed, closedLast)
	check("… even on a new market day", closed.hot == true)
	local hint, guide = SandboxSteps.visible(Steps.grow, closed, false)
	check("… a dismissed step quiet", not hint and not guide)
	hint, guide = SandboxSteps.visible(Steps.upgrade, closed, false)
	check("… the others still to say (hint and the 3D guide)", hint and guide)

	-- the words' details (the client makes the words again only when they change)
	local a, b = SandboxSteps.detail(Steps.grow, rich())
	check("details: grow its price", a == nil and b == level2)
	a, b = SandboxSteps.detail(Steps.upgrade, rich())
	check("… upgrade its id and price", a == "lights" and b == 1500)
	a, b = SandboxSteps.detail(Steps.hot, rich())
	check("… hot the piece's name", a == "Jukebox" and b == nil)
	a, b = SandboxSteps.detail(Steps.show, rich())
	check("… a core step none (its words its own)", a == nil and b == nil and SandboxSteps.words(Steps.show, rich()) == Steps.show.hint)
	for _, id in SandboxSteps.Soft do
		local words = SandboxSteps.words(Steps[id], rich({ levels = { warehouse = 3 }, money = 30000, hot = "Grandfather Clock" }))
		check(`{id}'s words with their price or piece: one line or two (≤ 80 characters)`, utf8.len(words) ~= nil and (utf8.len(words) :: number) <= 80, words)
	end
	check("UpgradeRules' order has the warehouse first and four others", UpgradeRules.Order[1] == "warehouse" and #UpgradeRules.Order == 5)

	-- the collection's market
	local summary = SandboxSteps.collection({ kind = "state", stock = {
		{ uid = "a", item = "jukebox", name = "Jukebox", market = "hot" },
		{ uid = "b", item = "radio", name = "Vintage Radio", market = "hot", stand = 1 },
		{ uid = "c", item = "globe", name = "Old Globe", market = "hot", broken = true },
		{ uid = "d", item = "sofa", name = "Sofa", market = "cold" },
		{ uid = "e", item = "radio", name = "Vintage Radio", market = "hot" },
	}, stands = 4, market = { day = 20375, hot = { "jukebox", "radio", "globe" }, cold = { "sofa" }, left = 100,
		demand = { sofa = { n = 2, sold = 2, back = 10 } } } }, nil)
	check("the hot pieces in the stock (not on show, not broken), the first one's name, the market's day", summary.hot == 2 and summary.hotName == "Jukebox"
		and summary.day == 20375 and summary.hotSold == false and summary.stock == 4 and summary.shown == 1, `{summary.hot} {summary.hotName} {summary.day}`)
	summary = SandboxSteps.collection({ kind = "state", stock = {}, market = { day = 1, hot = { "radio" }, cold = {}, demand = { radio = { n = 1, sold = 1 } } } }, 2)
	check("… a hot kind sold today: the market found", summary.hotSold == true and summary.hot == 0 and summary.hotName == nil)
	summary = SandboxSteps.collection({ kind = "state", stock = { { uid = "x", market = "hot", name = string.rep("x", 200) } }, market = "junk" }, 2)
	check("… a strange name or market: \"piece\", no day", summary.hot == 1 and summary.hotName == "piece" and summary.day == nil and not summary.hotSold)
	summary = SandboxSteps.collection({ kind = "state", stock = { { uid = "y", item = "lamp" } } }, 2)
	check("… a state without the market (before 8.3): none hot", summary.hot == 0 and summary.day == nil)
end

-- ── 8.4: Danny for hire (hire him, give him a piece, a heavy piece) ──────────
do
	local Steps = SandboxSteps.Steps
	local PRICE = 170
	-- a move with Danny on it, for hire, your money paying him (then the fields given; `false` for the money, his price
	-- or Danny: not known, left out)
	local function dannyState(fields: { [string]: any }?): SandboxSteps.State
		local s: { [string]: any } = { move = true, atHouse = true, money = 2000, helper = "offer", helperPrice = PRICE, heavy = 2 }
		for key, value in fields or {} do
			if value == false and (key == "money" or key == "helperPrice" or key == "helper") then
				s[key] = nil
			else
				s[key] = value
			end
		end
		return state(s)
	end
	local function chosen(s: SandboxSteps.State, done: { [string]: boolean }?): SandboxSteps.Step
		return SandboxSteps.choose(s, done or {})
	end
	local hire, give, lift = Steps.hire, Steps.give, Steps.lift

	-- the steps and their words (the same on every device; a gamepad's button after them)
	check("Danny's steps' order: lift, give, hire", table.concat(SandboxSteps.Danny, ",") == "lift,give,hire")
	for _, id in SandboxSteps.Danny do
		local def = Steps[id]
		check(`{id}: a soft step (said once, its ✕ dismisses it), not a nav or info one, no "click" or "tap" in its words`, def ~= nil and def.soft and not def.nav
			and not def.info and string.find(string.lower(def.hint), "click", 1, true) == nil and string.find(string.lower(def.hint), "tap", 1, true) == nil, def and def.hint)
	end
	check("their words: \"Hire Danny to carry with you\" (the chevron over him), 8.5 \"Take out your clipboard (Q) and pick a piece for Danny\", \"Heavy piece: press Lift and wait for Danny\"",
		hire.hint == "Hire Danny to carry with you" and hire.target == "danny" and give.hint == "Take out your clipboard (Q) and pick a piece for Danny" and give.target == nil
		and lift.hint == "Heavy piece: press Lift and wait for Danny" and lift.target == nil, give.hint)
	check("… his name Config's, the clipboard's key Config's", Config.MoveHelper.Name == "Danny" and Config.MoveHelper.Clipboard.Key == "Q")
	check("… a computer's and a phone's words as they are (no key: \"pick\" is a click or a tap; Lift its prompt's)", SandboxSteps.onDevice(hire, nil, "keys") == hire.hint
		and SandboxSteps.onDevice(hire, nil, "touch") == hire.hint and SandboxSteps.onDevice(lift, nil, "touch") == lift.hint)
	check("… 8.5 give's: the clipboard's key in the device's way (Q on a computer, \"tap 📋\" on a phone: its 📋 button)", SandboxSteps.onDevice(give, nil, "keys") == give.hint
		and SandboxSteps.onDevice(give, nil, "touch") == "Take out your clipboard (tap 📋) and pick a piece for Danny", SandboxSteps.onDevice(give, nil, "touch"))
	check("… a gamepad's: SandboxPad's buttons for him (\"(L1)\" at him, 8.5 R1 his clipboard's, in its place), Lift's own on the prompt",
		SandboxSteps.onDevice(hire, nil, "pad") == "Hire Danny to carry with you (L1)" and SandboxSteps.onDevice(give, nil, "pad") == "Take out your clipboard (R1) and pick a piece for Danny"
		and SandboxSteps.onDevice(lift, nil, "pad") == lift.hint, SandboxSteps.onDevice(give, nil, "pad"))
	-- 8.5 the clipboard out (orders mode): give's words say what to do now ("(R1)" with a gamepad: at a piece)
	local out = dannyState({ helper = "hired", helperQueue = 0, inside = true, clipboard = true })
	local outWords = SandboxSteps.words(give, out)
	check("8.5 the clipboard out: \"Pick a piece to give it to Danny\" (a click or a tap: no key; a gamepad's R1 after it)", outWords == "Pick a piece to give it to Danny"
		and SandboxSteps.onDevice(give, outWords, "keys") == outWords and SandboxSteps.onDevice(give, outWords, "touch") == outWords
		and SandboxSteps.onDevice(give, outWords, "pad") == "Pick a piece to give it to Danny (R1)", SandboxSteps.onDevice(give, outWords, "pad"))
	check("… its detail follows the clipboard (the client makes its words again)", SandboxSteps.detail(give, out) == "clipboard"
		and SandboxSteps.detail(give, dannyState({ helper = "hired", helperQueue = 0, inside = true })) == nil)
	check("… still give's step (the same step, other words)", chosen(out).id == "give")
	check("… the other steps on a device as before (a phone's tap, a gamepad's X)", SandboxSteps.onDevice(Steps.load, nil, "touch") == "Load the truck: walk in or tap at its back"
		and SandboxSteps.onDevice(Steps.load, nil, "pad") == "Load the truck: walk in or X at its back" and SandboxSteps.onDevice(Steps.load, nil, "keys") == Steps.load.hint)

	-- hire: during a move, for hire, the money pays him
	check("a move, Danny for hire, the money pays him: \"Hire Danny to carry with you\" before the move's own step", chosen(dannyState()).id == "hire"
		and chosen(dannyState({ atHouse = false })).id == "hire")
	check("… decide gives it only with `done` (the core alone without)", SandboxSteps.decide(dannyState()).id == "door" and SandboxSteps.decide(dannyState(), {}).id == "hire")
	check("… the money just enough", chosen(dannyState({ money = PRICE })).id == "hire")
	check("… not short of it", chosen(dannyState({ money = PRICE - 1 })).id == "door")
	check("… not with the money or his price not known", chosen(dannyState({ money = false })).id == "door" and chosen(dannyState({ helperPrice = false })).id == "door")
	check("… not without a move (no Danny then), nor in the planning (he comes with the move)", chosen(dannyState({ move = false }), { portal = true }).id ~= "hire"
		and chosen(dannyState({ move = false, planning = true, planningMine = true })).id == "plan")
	check("… not without Danny on the move", chosen(dannyState({ helper = false })).id == "door")
	check("… not while you sit (driving), carry a piece", chosen(dannyState({ seated = true })).id == "door" and chosen(dannyState({ carrying = true })).id == "load")
	check("… never while something covers the screen (his card, the move's cards, a grip check) or something else talks", chosen(dannyState({ covered = true })).id == "door"
		and chosen(dannyState({ hush = true })).id == "door")
	check("… done: the move's own step again", chosen(dannyState(), { hire = true }).id == "door")

	-- give: hired, his list empty, in the house
	check("hired, his list empty, in the house: \"Pick a piece to give it to Danny\"", chosen(dannyState({ helper = "hired", helperQueue = 0, inside = true })).id == "give")
	check("… not outside (the pieces are in the house: the move's step)", chosen(dannyState({ helper = "hired", helperQueue = 0 })).id == "door")
	check("… not with pieces on his list, nor with his list not known", chosen(dannyState({ helper = "hired", helperQueue = 2, inside = true })).id == "inside"
		and chosen(dannyState({ helper = "hired", inside = true })).id == "inside")
	check("… not while you carry one, nor while you wait for him", chosen(dannyState({ helper = "hired", helperQueue = 0, inside = true, carrying = true })).id == "inside"
		and chosen(dannyState({ helper = "hired", helperQueue = 0, inside = true, waiting = true })).id == "inside")
	check("… for hire: hire's, not give's", chosen(dannyState({ helperQueue = 0, inside = true })).id == "hire")

	-- lift: hired, a heavy piece near (the first time)
	check("hired, a two-person piece near: \"Heavy piece: press Lift and wait for Danny\" (before give)", chosen(dannyState({ helper = "hired", helperQueue = 0, inside = true, heavyNear = true })).id == "lift")
	check("… with pieces on his list too", chosen(dannyState({ helper = "hired", helperQueue = 3, inside = true, heavyNear = true })).id == "lift")
	check("… not for hire (a Lift then drags it alone: no wait for him)", chosen(dannyState({ heavyNear = true, inside = true, money = 0 })).id == "inside")
	check("… not without one near, nor with none left", chosen(dannyState({ helper = "hired", helperQueue = 3, inside = true })).id == "inside"
		and chosen(dannyState({ helper = "hired", helperQueue = 3, inside = true, heavyNear = true, heavy = 0 })).id == "inside")
	check("… not while you wait for him already, nor while you carry", chosen(dannyState({ helper = "hired", helperQueue = 3, inside = true, heavyNear = true, waiting = true })).id == "inside"
		and chosen(dannyState({ helper = "hired", helperQueue = 3, inside = true, heavyNear = true, carrying = true })).id == "inside")
	check("… done: give's (his list empty), then the move's", chosen(dannyState({ helper = "hired", helperQueue = 0, inside = true, heavyNear = true }), { lift = true }).id == "give"
		and chosen(dannyState({ helper = "hired", helperQueue = 0, inside = true, heavyNear = true }), { lift = true, give = true }).id == "inside")

	-- done by what the player did (once a session, as the other steps)
	local done: { [string]: boolean } = {}
	local last: SandboxSteps.Last = {}
	SandboxSteps.doneBy(dannyState(), done, last)
	check("for hire: nothing done", done.hire == nil and done.give == nil and done.lift == nil)
	SandboxSteps.doneBy(dannyState({ covered = true, window = "MoveHelperCard" }), done, last)
	check("his card opened while he is for hire (the offer seen): hire done", done.hire == true and done.give == nil)
	local hired: { [string]: boolean } = {}
	local hiredLast: SandboxSteps.Last = {}
	SandboxSteps.doneBy(dannyState({ helper = "hired", helperQueue = 0 }), hired, hiredLast)
	check("hired: hire done, give not (his list empty)", hired.hire == true and hired.give == nil and hiredLast.queue == 0)
	SandboxSteps.doneBy(dannyState({ helper = "hired", helperQueue = 1, inside = true }), hired, hiredLast)
	check("… a piece given him while you play (his list went up): give done", hired.give == true)
	local saved: { [string]: boolean } = {}
	local savedLast: SandboxSteps.Last = {}
	SandboxSteps.doneBy(dannyState({ helper = "hired", helperQueue = 2 }), saved, savedLast)
	check("… a list already there at the first look (a crew mate's): not yours", saved.give == nil)
	SandboxSteps.doneBy(dannyState({ helper = "hired", helperQueue = 2, covered = true, window = "MoveHelperCard" }), saved, savedLast)
	check("… his card opened while he is hired (it says how to give him pieces): give done", saved.give == true)
	SandboxSteps.doneBy(dannyState({ helper = "hired", helperQueue = 0, waiting = true }), saved, savedLast)
	check("your Lift called him to a heavy piece (you wait for him): lift done", saved.lift == true)
	local off: { [string]: boolean } = {}
	local offLast: SandboxSteps.Last = { queue = 1 }
	SandboxSteps.doneBy(dannyState({ move = false, helper = false }), off, offLast)
	check("no move: nothing of his, his list forgotten (the next move's first look takes it again)", off.hire == nil and off.give == nil and offLast.queue == nil)

	-- the ✕: that step alone, for the session
	local closed: { [string]: boolean } = {}
	check("the ✕ on Danny's step: that step gone (the guide stays on), the move's own step", SandboxSteps.dismiss(hire, closed) and closed.hire == true
		and chosen(dannyState(), closed).id == "door")
	check("… its details none (its words its own)", SandboxSteps.detail(hire, dannyState()) == nil and SandboxSteps.words(give, dannyState()) == give.hint)
	check("Config: a heavy piece \"near\" within a Lift's reach or so", Config.SandboxGuide.HeavyNear >= Config.Moving.Reach.Item and Config.SandboxGuide.HeavyNear <= 20)
end

-- ── 8.9: trading between players' step (set a price on a piece on show) ─────
do
	local Steps = SandboxSteps.Steps
	local G = Config.SandboxGuide
	local sell = Steps.sell
	local NONE = {} -- (a field given as NONE is left out: not known)
	-- no move, nothing in the stock (the core's `earn` only says something: it gives way), SellShown pieces on show,
	-- none with a sign, SellPlayers players on the server (then the fields given)
	local function selling(fields: { [string]: any }?): SandboxSteps.State
		local s: { [string]: any } = { stock = 0, shown = G.SellShown, freeStands = 0, players = G.SellPlayers, signs = 0 }
		for key, value in fields or {} do
			s[key] = value
		end
		local made = state(s) :: any
		for key, value in made do
			if value == NONE then
				made[key] = nil
			end
		end
		return made
	end
	local function chosen(s: SandboxSteps.State, done: { [string]: boolean }?): SandboxSteps.Step
		return SandboxSteps.choose(s, done or {})
	end

	check("8.9 Config: the sell step from 4 pieces on show and 2 players on the server", G.SellShown == 4 and G.SellPlayers == 2)
	check("the step: \"🏷 Sell to players: set a price on a piece on show\", a soft one (said once, its ✕ dismisses it), the chevron over a piece on show",
		sell ~= nil and sell.id == "sell" and sell.hint == "🏷 Sell to players: set a price on a piece on show" and sell.target == "sale" and sell.soft
		and not sell.nav and not sell.info and sell.pad == nil, sell and sell.hint)
	check("… the last soft step (after the existing steps' order)", SandboxSteps.Soft[#SandboxSteps.Soft] == "sell" and table.find(SandboxSteps.Danny, "sell") == nil)
	check("… its words the same on every device (no key: the stand's Set price prompt shows its own)", SandboxSteps.onDevice(sell, nil, "keys") == sell.hint
		and SandboxSteps.onDevice(sell, nil, "pad") == sell.hint and SandboxSteps.onDevice(sell, nil, "touch") == sell.hint
		and SandboxSteps.words(sell, selling()) == sell.hint and SandboxSteps.detail(sell, selling()) == nil)

	-- when it shows
	check(`{G.SellShown} pieces on show, no sign, {G.SellPlayers} players on the server: "🏷 Sell to players …"`, chosen(selling()).id == "sell")
	check("… with more of both too", chosen(selling({ shown = 9, players = 6 })).id == "sell")
	check(`… not with {G.SellShown - 1} on show`, chosen(selling({ shown = G.SellShown - 1 })).id ~= "sell")
	check("… not alone on the server (nobody to buy), nor with the players not known", chosen(selling({ players = 1 })).id ~= "sell"
		and chosen(selling({ players = NONE })).id ~= "sell")
	check("… not with a sign up already, nor before the collection's state came (signs not known)", chosen(selling({ signs = 1 })).id ~= "sell"
		and chosen(selling({ signs = NONE })).id ~= "sell")
	check("… never in a move or its planning (it never interrupts a move)", chosen(selling({ move = true })).id == "door"
		and chosen(selling({ move = true, atHouse = true, inside = true })).id == "inside" and chosen(selling({ planning = true, planningMine = true })).id == "plan")
	check("… never while something covers the screen or something else talks (a first-time hint)", chosen(selling({ covered = true })).id ~= "sell"
		and chosen(selling({ hush = true })).id ~= "sell")
	check("… after a core step not done yet (pieces in the stock, a stand free: put them on show first)", chosen(selling({ stock = 2, freeStands = 2 })).id == "show")
	local every = selling({ stock = 4, freeStands = 2, money = 2000, levels = {}, hot = "Jukebox", hotCount = 1, hotSold = false, day = 1, painted = false, vanHome = true })
	check("… after the existing soft steps (grow, hot, upgrade, paint first; then sell)", chosen(every, { show = true }).id == "grow"
		and chosen(every, { show = true, grow = true, hot = true, upgrade = true }).id == "paint"
		and chosen(every, { show = true, grow = true, hot = true, upgrade = true, paint = true }).id == "sell")
	local trade = Config.PlayerTrade
	trade.On = false
	check("… not while trading between players is off (Config.PlayerTrade.On)", chosen(selling()).id ~= "sell")
	trade.On = true

	-- done (once a session)
	local done: { [string]: boolean } = {}
	local last: SandboxSteps.Last = {}
	SandboxSteps.doneBy(selling(), done, last)
	check("no sign: not done", done.sell == nil)
	SandboxSteps.doneBy(selling({ signs = 1 }), done, last)
	check("a sign set: done", done.sell == true and chosen(selling(), done).id ~= "sell")
	local saved: { [string]: boolean } = {}
	SandboxSteps.doneBy(selling({ signs = 2 }), saved, {})
	check("… a sign a save brought along too (the player knows how)", saved.sell == true)
	local closed: { [string]: boolean } = {}
	check("its ✕: that step gone for the session", SandboxSteps.dismiss(sell, closed) and closed.sell == true and chosen(selling(), closed).id ~= "sell")
	local hint, guide = SandboxSteps.visible(sell, {}, false)
	check("… before: the hint and the chevron", hint and guide)
	hint, guide = SandboxSteps.visible(sell, { sell = true }, false)
	check("… done: quiet", not hint and not guide)

	-- the collection's signs and the nearest piece on show
	local summary = SandboxSteps.collection({ kind = "state", stands = 6, stock = {
		{ uid = "a", item = "sofa", stand = 1, sale = 1500 },
		{ uid = "b", item = "lamp", stand = 2 },
		{ uid = "c", item = "vase", stand = 3, sale = 0 },
		{ uid = "d", item = "rug", sale = 900 }, -- (no stand: no sign, whatever it says)
		{ uid = "e", item = "clock", stand = 4, sale = "x" },
	} }, nil)
	check("the Collection's state: the pieces on show with a FOR SALE sign (a price over 0, on a stand)", summary.signs == 1 and summary.shown == 4, summary.signs)
	check("… none: 0; nothing yet: 0", SandboxSteps.collection({ kind = "state", stock = { { uid = "z", stand = 1 } } }, 2).signs == 0 and SandboxSteps.collection(nil).signs == 0)
	local spots = { { x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 }, { x = 20, y = 0, z = 0 } }
	check("the nearest stand with a piece on show (the chevron's)", SandboxSteps.nearestShown(19, 0, spots, { [1] = true, [2] = true }) == 2
		and SandboxSteps.nearestShown(-5, 0, spots, { [3] = true }) == 3)
	check("… none on show: none", SandboxSteps.nearestShown(5, 0, spots, {}) == nil)
	check("… the nearest empty one as before", SandboxSteps.nearestFree(19, 0, spots, { [3] = true }) == 2)
end

-- ── Config.SandboxGuide ─────────────────────────────────────────────────────
do
	local G = Config.SandboxGuide
	check("the guide looks five times a second (the beam every 0.2 s)", G.Every == 0.2)
	check("a hold of G under two seconds, a fade under one", G.HideHold > 0.3 and G.HideHold < 2 and G.Fade > 0 and G.Fade < 1)
	check("the path's numbers sane", G.Direct > G.Near and G.Near > 0 and G.PathWidth > 0.5 and G.PathAlpha > 0 and G.PathAlpha < 1)
	check("the colour an RGB triple", #G.Color == 3 and G.Color[1] <= 255 and G.Color[2] <= 255 and G.Color[3] <= 255)
	check("the hint readable on a phone", G.TouchScale >= 0.75 and G.TextSize >= 14)
	check("8.3: a soft step shows long enough to walk to it, not for ever; the gap between two; the paint's money", G.SoftSeconds >= 20 and G.SoftSeconds <= 90
		and G.SoftGap >= 5 and G.SoftGap <= 60 and G.PaintMoney > 0 and G.PaintMoney < Config.SandboxUpgrades.List.warehouse.prices[2])
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
