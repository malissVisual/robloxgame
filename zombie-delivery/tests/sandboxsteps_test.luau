-- 8.0 SANDBOX, the guide's steps (shared/SandboxSteps.luau; client/SandboxGuide.luau draws them): every row of the
-- owner's table gives its words and its target, a step done once goes quiet (the drive steps' arrow stays while you
-- drive), the path along the roads, the collection's state read. Run with tests/run_tests.py.
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

-- ── The owner's table, row by row ───────────────────────────────────────────
do
	local step = SandboxSteps.decide(state({}))
	check("no move: take a contract at the board (your plot's board)", step.id == "contract" and step.hint == "Take a contract at the board" and step.target == "board", show(step))
	step = SandboxSteps.decide(state({ move = true }))
	check("a move started, not at the house: drive to The Old Chalet (its curb)", step.id == "drive" and step.hint == "Drive to The Old Chalet" and step.target == "curb" and step.nav, show(step))
	check("… the house's name from SandboxMap", SandboxMap.House.name == "The Old Chalet")
	step = SandboxSteps.decide(state({ move = true, seated = true }))
	check("… driving there too", step.id == "drive", show(step))
	step = SandboxSteps.decide(state({ move = true, atHouse = true }))
	check("8.1 walk-in doors: at the house, outside: walk in through the front door (no E)", step.id == "door" and step.hint == "Walk in through the front door" and step.target == "door"
		and string.find(step.hint, "E at", 1, true) == nil, show(step))
	step = SandboxSteps.decide(state({ move = true, atHouse = true, inside = true }))
	check("in the house: carry the furniture out (the hint only, no 3D target inside)", step.id == "inside" and step.hint == "Carry the furniture out to your van (E to pick up)" and step.target == nil, show(step))
	step = SandboxSteps.decide(state({ move = true, atHouse = true, inside = true, carrying = true }))
	check("… carrying inside: still carry it out", step.id == "inside", show(step))
	step = SandboxSteps.decide(state({ move = true, atHouse = true, carrying = true }))
	check("carrying, outside: load it into the van (its back)", step.id == "load" and step.hint == "Load it into the van: walk in or E at the back" and step.target == "van", show(step))
	step = SandboxSteps.decide(state({ move = true, atHouse = true, carrying = true, vanLoad = 3 }))
	check("… with things in the van already: load this one first", step.id == "load", show(step))
	step = SandboxSteps.decide(state({ move = true, atHouse = true, vanLoad = 2 }))
	check("the van has things, the move is on: drive home to unload (your plot's unload circle)", step.id == "home"
		and step.hint == "Drive home to your warehouse to unload (or keep loading)" and step.target == "unload" and step.nav, show(step))
	step = SandboxSteps.decide(state({ move = true, vanLoad = 2, seated = true }))
	check("… driving home", step.id == "home", show(step))
	step = SandboxSteps.decide(state({ move = true, delivered = 4 }))
	check("a trip unloaded, the move still on: back to the house for more, or FINISH", step.id == "back" and step.target == "curb" and step.nav
		and step.hint == "Drive back to The Old Chalet for more, or FINISH", show(step))
	step = SandboxSteps.decide(state({ move = true, delivered = 4, atHouse = true }))
	check("… there again: in through the door", step.id == "door", show(step))
	step = SandboxSteps.decide(state({ stock = 3 }))
	check("stock has pieces, no move: put them on show (an empty stand)", step.id == "show" and step.hint == "Put your pieces on show: E at an empty stand" and step.target == "stand", show(step))
	step = SandboxSteps.decide(state({ stock = 3, freeStands = 2, shown = 1 }))
	check("… some on show already and stands free: still put the rest on show", step.id == "show", show(step))
	step = SandboxSteps.decide(state({ shown = 2 }))
	check("pieces on show: they earn money, take another contract (the board)", step.id == "earn"
		and step.hint == "Your pieces earn money while you play. Take another contract for more!" and step.target == "board" and step.info, show(step))
	step = SandboxSteps.decide(state({ shown = 6, stock = 2, freeStands = 0 }))
	check("… every stand full, more in the stock: they earn (nothing to put up)", step.id == "earn", show(step))
	step = SandboxSteps.decide(state({ stock = 2, freeStands = 0 }))
	check("stock but no free stand and nothing on show: take a contract", step.id == "contract", show(step))
	step = SandboxSteps.decide(state({ stock = 2, move = true }))
	check("a move wins over the stock", step.id == "drive", show(step))
	step = SandboxSteps.decide(state({ planning = true, planningMine = true }))
	check("the planning open (yours): press LAUNCH", step.id == "plan" and step.target == nil and string.find(step.hint, "LAUNCH", 1, true) ~= nil, show(step))
	step = SandboxSteps.decide(state({ planning = true }))
	check("… a crew's: the owner launches", step.id == "planCrew" and step.target == nil, show(step))
	for id, def in SandboxSteps.Steps do
		check(`{id}: one sentence in English, its id its key`, def.id == id and #def.hint > 10 and #def.hint <= 80 and string.find(def.hint, "%a") ~= nil, def.hint)
	end
end

-- ── Done once: quiet; the drive steps' arrow stays while you drive ──────────
do
	local done: { [string]: boolean } = {}
	local last: SandboxSteps.Last = {}
	local contract = SandboxSteps.Steps.contract
	local hint, guide = SandboxSteps.visible(contract, done, false)
	check("a new step: the hint and the 3D guide", hint and guide)
	hint, guide = SandboxSteps.visible(SandboxSteps.Steps.inside, done, false)
	check("in the house: the hint, no 3D guide", hint and not guide)
	SandboxSteps.doneBy(state({ move = true }), done, last)
	check("a move started: the contract is done", done.contract == true and done.drive == nil)
	hint, guide = SandboxSteps.visible(contract, done, false)
	check("… the contract's hint and guide quiet next time", not hint and not guide)
	SandboxSteps.doneBy(state({ move = true, seated = true }), done, last)
	check("driving to the house: not done yet", done.drive == nil)
	SandboxSteps.doneBy(state({ move = true, atHouse = true }), done, last)
	check("at the house: the drive is done", done.drive == true and done.door == nil)
	local drive = SandboxSteps.Steps.drive
	hint, guide = SandboxSteps.visible(drive, done, false)
	check("a done drive step on foot: quiet", not hint and not guide)
	hint, guide = SandboxSteps.visible(drive, done, true)
	check("… driving: the hint quiet, the arrow to the house stays", not hint and guide)
	SandboxSteps.doneBy(state({ move = true, atHouse = true, inside = true }), done, last)
	check("inside: the door is done", done.door == true and done.inside == nil)
	SandboxSteps.doneBy(state({ move = true, atHouse = true, carrying = true }), done, last)
	check("out with a piece: the inside step is done", done.inside == true and done.load == nil)
	SandboxSteps.doneBy(state({ move = true, atHouse = true, vanLoad = 1 }), done, last)
	check("a piece into the van: loading is done", done.load == true and done.home == nil)
	hint, guide = SandboxSteps.visible(SandboxSteps.Steps.load, done, false)
	check("… loading quiet next time", not hint and not guide)
	SandboxSteps.doneBy(state({ move = true, delivered = 3 }), done, last)
	check("a trip unloaded (delivered went up): home is done", done.home == true and done.back == nil)
	hint, guide = SandboxSteps.visible(SandboxSteps.Steps.home, done, true)
	check("… the arrow home stays while driving", not hint and guide)
	hint, guide = SandboxSteps.visible(SandboxSteps.Steps.back, done, false)
	check("back to the house the first time: said once", hint and guide)
	SandboxSteps.doneBy(state({ move = true, delivered = 3, atHouse = true }), done, last)
	check("… there again: back is done", done.back == true)
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
	check("the planning open: the contract was taken", fresh.contract == true and fresh.plan == nil)
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
	check("joining a move with things in the van already: loading and home not done", crew.load == nil and crew.home == nil)
	SandboxSteps.doneBy(state({}), crew, crewLast)
	SandboxSteps.doneBy(state({ move = true }), crew, crewLast)
	SandboxSteps.doneBy(state({ move = true, vanLoad = 1 }), crew, crewLast)
	check("… a new move: its first piece loaded counts", crew.load == true)
end

-- ── The words on a touch screen ─────────────────────────────────────────────
do
	local Steps = SandboxSteps.Steps
	check("8.1 walk-in doors: the front door is walked through on a touch screen too (nothing to tap)", SandboxSteps.text(Steps.door, true) == "Walk in through the front door", SandboxSteps.text(Steps.door, true))
	check("… pick up", SandboxSteps.text(Steps.inside, true) == "Carry the furniture out to your van (tap to pick up)", SandboxSteps.text(Steps.inside, true))
	check("… the van's back", SandboxSteps.text(Steps.load, true) == "Load it into the van: walk in or tap at the back")
	check("… a computer keeps E (the door: its own words, no key)", SandboxSteps.text(Steps.door, false) == Steps.door.hint and SandboxSteps.text(Steps.load, false) == Steps.load.hint)
	check("… words without a key unchanged (LAUNCH, FINISH keep their E)", SandboxSteps.text(Steps.plan, true) == Steps.plan.hint and SandboxSteps.text(Steps.back, true) == Steps.back.hint)
end

-- ── At the house ────────────────────────────────────────────────────────────
do
	local margin = Config.SandboxGuide.HouseMargin
	local curb, door = SandboxMap.House.curb, SandboxMap.House.door
	check("the curb (the van's place) is at the house", SandboxSteps.atHouse(curb.x, curb.z, margin))
	check("the front door is at the house", SandboxSteps.atHouse(door.x, door.z, margin))
	local t = SandboxMap.Turnaround
	check("the turnaround's north edge is not", not SandboxSteps.atHouse(t.x, t.z - t.r, margin))
	local plot = SandboxMap.Plots[1]
	check("your plot is not", not SandboxSteps.atHouse(plot.spawn.x, plot.spawn.z, margin))
	check("Main Street's middle is not", not SandboxSteps.atHouse(0, 200, margin))
end

-- ── The path along the roads ────────────────────────────────────────────────
do
	local out: { number } = {}
	local direct = Config.SandboxGuide.Direct
	local row = SandboxMap.Roads[2]
	local rowZ = (row.z0 + row.z1) / 2
	local function points(n: number): string
		local parts = {}
		for i = 1, n do
			table.insert(parts, `({out[i * 2 - 1]}, {out[i * 2]})`)
		end
		return table.concat(parts, " ")
	end
	local function onRoad(x: number, z: number): boolean
		for _, r in SandboxMap.Roads do
			if x >= r.x0 - 0.01 and x <= r.x1 + 0.01 and z >= r.z0 - 0.01 and z <= r.z1 + 0.01 then
				return true
			end
		end
		return false
	end
	local plot = SandboxMap.Plots[1]
	local curb = SandboxMap.House.curb
	local n = SandboxSteps.route(plot.spawn.x, plot.spawn.z, curb.x, curb.z, out, direct)
	check("from your plot to the house: out to Depot Row, along it, down Main Street", n == 4 and out[3] == plot.spawn.x and out[4] == rowZ
		and out[5] == 0 and out[6] == rowZ and out[7] == curb.x and out[8] == curb.z, points(n))
	local inner = true
	for i = 2, n - 1 do
		inner = inner and onRoad(out[i * 2 - 1], out[i * 2])
	end
	check("… every turn on a road", inner, points(n))
	n = SandboxSteps.route(curb.x, curb.z, plot.unload.x, plot.unload.z, out, direct)
	check("from the house home: up Main Street, along Depot Row, in to the unload circle", n == 4 and out[3] == 0 and out[4] == rowZ
		and out[5] == plot.unload.x and out[6] == rowZ and out[7] == plot.unload.x and out[8] == plot.unload.z, points(n))
	n = SandboxSteps.route(plot.spawn.x, plot.spawn.z, plot.board.x, plot.board.z, out, direct)
	check("on your plot to its board: straight", n == 2 and out[3] == plot.board.x and out[4] == plot.board.z, points(n))
	local other = SandboxMap.Plots[4]
	n = SandboxSteps.route(plot.spawn.x, plot.spawn.z, other.board.x, other.board.z, out, direct)
	check("to another plot: along Depot Row", n == 4 and out[4] == rowZ and out[6] == rowZ, points(n))
	n = SandboxSteps.route(0, 300, curb.x, curb.z, out, direct)
	check("on Main Street to the house: straight on", n == 2 and out[3] == curb.x and out[4] == curb.z, points(n))
	n = SandboxSteps.route(120, 200, curb.x, curb.z, out, direct)
	check("from the meadow: to Main Street first", n == 3 and out[3] == 0 and out[4] == 200, points(n))
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

-- ── Config.SandboxGuide ─────────────────────────────────────────────────────
do
	local G = Config.SandboxGuide
	check("the guide looks five times a second (the beam every 0.2 s)", G.Every == 0.2)
	check("a hold of G under two seconds, a fade under one", G.HideHold > 0.3 and G.HideHold < 2 and G.Fade > 0 and G.Fade < 1)
	check("the path's numbers sane", G.Direct > G.Near and G.Near > 0 and G.PathWidth > 0.5 and G.PathAlpha > 0 and G.PathAlpha < 1)
	check("the colour an RGB triple", #G.Color == 3 and G.Color[1] <= 255 and G.Color[2] <= 255 and G.Color[3] <= 255)
	check("the hint readable on a phone", G.TouchScale >= 0.75 and G.TextSize >= 14)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
