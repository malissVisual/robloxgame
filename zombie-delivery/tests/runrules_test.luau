-- 9.7 RUNS: shared/RunRules.luau, the rules of a run (Config.Runs): the difficulties in order (Easy and Normal open
-- from the start, each next one opened by a run finished at the one before it, any house), the clock per difficulty,
-- the save's migration (a real save written with the flag keeps its count), a host's pick; in a run: the party's vote to
-- finish, whose stock a piece in the truck goes into (whoever loaded it, else the host), the results card's sums. 10.4:
-- the party gathers in a lobby at the PLAY circle first (tests/partyrules_test.luau; the portals' pads are gone). The
-- server's side of it (the lobbies, the runs, the jumps): tests/party_runtime_test.luau and
-- tests/sandbox_e2e_runtime_test.luau. Run with tests/run_tests.py.
local Config = require("./Config")
local RunRules = require("./RunRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local R = Config.Runs

-- ── The difficulties ───────────────────────────────────────────────────────

do
	local ids = {}
	for _, def in RunRules.list() do
		table.insert(ids, def.id)
	end
	check("five difficulties in order: easy, normal, hard, insane, nightmare", table.concat(ids, ",") == "easy,normal,hard,insane,nightmare")
	local named, shorter = true, true
	for n, def in R.Difficulties do
		named = named and #def.name > 0 and #def.color == 3 and def.time > 0
		if n > 1 then
			shorter = shorter and def.time < R.Difficulties[n - 1].time
		end
	end
	check("…each a name, a colour and a time factor; each harder one a shorter clock (Easy's longest)", named and shorter)
	check("the default is Normal; Easy and Normal open from the start (Open 2)", R.Default == "normal" and R.Open == 2 and RunRules.index("normal") == 2)
	check("RunRules.index / def / clean: a known id; anything else none (clean: the default)", RunRules.index("hard") == 3 and RunRules.def("insane") == R.Difficulties[4]
		and RunRules.index("HARD") == nil and RunRules.def(5) == nil and RunRules.clean("nope") == "normal" and RunRules.clean(nil) == "normal"
		and RunRules.clean("easy") == "easy")
	check("the clock: the house's time × the difficulty's (whole seconds, a minute at least; an unknown one the default's)",
		RunRules.time(1500, "normal") == 1500 and RunRules.time(1500, "easy") == math.floor(1500 * R.Difficulties[1].time + 0.5)
			and RunRules.time(1500, "nightmare") == math.floor(1500 * R.Difficulties[5].time + 0.5) and RunRules.time(1500, "what") == 1500
			and RunRules.time(10, "nightmare") == 60)
	-- every house's clock at every difficulty: more than a few minutes, Easy the longest
	local houses = Config.Moving.Sandbox.Houses
	local sane = true
	for _, h in houses do
		local last = math.huge
		for _, def in R.Difficulties do
			local t = RunRules.time(h.Time, def.id)
			sane = sane and t >= 5 * 60 and t < last
			last = t
		end
	end
	check("…every house's clock at every difficulty at least 5 minutes, shorter the harder", sane)
	check("RunRules.clock: m:ss", RunRules.clock(0) == "0:00" and RunRules.clock(65) == "1:05" and RunRules.clock(1500) == "25:00" and RunRules.clock(-3) == "0:00")
end

-- ── The unlocks ────────────────────────────────────────────────────────────

do
	check("open with 2: Easy and Normal, not Hard", RunRules.isOpen(2, "easy") and RunRules.isOpen(2, "normal") and not RunRules.isOpen(2, "hard")
		and not RunRules.isOpen(2, "nightmare") and not RunRules.isOpen(2, "nope"))
	check("…a count under Open still opens Easy and Normal", RunRules.isOpen(0, "normal") and not RunRules.isOpen(0, "hard"))
	local count, opened = RunRules.unlock(2, "normal")
	check("a run finished at Normal opens Hard (count 3)", count == 3 and opened == "hard")
	count, opened = RunRules.unlock(2, "easy")
	check("…at Easy: nothing new (Normal is open already)", count == 2 and opened == nil)
	count, opened = RunRules.unlock(3, "hard")
	check("…at Hard: Insane", count == 4 and opened == "insane")
	count, opened = RunRules.unlock(4, "insane")
	check("…at Insane: Nightmare", count == 5 and opened == "nightmare")
	count, opened = RunRules.unlock(5, "nightmare")
	check("…at Nightmare: nothing more (all open)", count == 5 and opened == nil)
	count, opened = RunRules.unlock(4, "normal")
	check("…a run at an easier one never takes anything back", count == 4 and opened == nil)
	count, opened = RunRules.unlock(2, "junk")
	check("…an unknown difficulty: nothing", count == 2 and opened == nil)
	check("a host's pick: open → it; locked → the hardest open one under it; unknown → the default (or under it)", RunRules.choose(2, "easy") == "easy"
		and RunRules.choose(2, "hard") == "normal" and RunRules.choose(3, "nightmare") == "hard" and RunRules.choose(5, "nightmare") == "nightmare"
		and RunRules.choose(2, "junk") == "normal")
end

-- ── The save's migration (server/PlayerData.luau applySaved) ───────────────

do
	check("a real save written with the flag keeps its count", RunRules.fromSave({ money = 10, runUnlocked = 4, [R.Flag] = true }) == 4)
	check("…an old real save (no flag, from before 9.7): Easy and Normal", RunRules.fromSave({ money = 10, runUnlocked = 5 }) == R.Open
		and RunRules.fromSave({ money = 10 }) == R.Open)
	check("…no real save (no money: a lock-only record, nothing): Easy and Normal", RunRules.fromSave({ runUnlocked = 5, [R.Flag] = true }) == R.Open
		and RunRules.fromSave(nil) == R.Open and RunRules.fromSave("x") == R.Open)
	check("…junk counts: Open (not a whole number, NaN), clamped to Open … all", RunRules.fromSave({ money = 1, runUnlocked = 2.5, [R.Flag] = true }) == R.Open
		and RunRules.fromSave({ money = 1, runUnlocked = 0 / 0, [R.Flag] = true }) == R.Open and RunRules.fromSave({ money = 1, runUnlocked = 99, [R.Flag] = true }) == #R.Difficulties
		and RunRules.fromSave({ money = 1, runUnlocked = 0, [R.Flag] = true }) == R.Open and RunRules.fromSave({ money = 1, runUnlocked = "5", [R.Flag] = true }) == R.Open)
end

-- ── In a run ───────────────────────────────────────────────────────────────

do
	check("the vote: everybody but the host asked to finish → done", RunRules.voteDone({ [22] = true, [33] = true }, { 22, 33 })
		and not RunRules.voteDone({ [22] = true }, { 22, 33 }) and not RunRules.voteDone({}, {}))
	local present = function(id: number): boolean
		return id == 11 or id == 22
	end
	check("whose stock: whoever loaded it, while still in the game; else (nobody known, or gone) the host's", RunRules.stockOwner(22, 11, present) == 22
		and RunRules.stockOwner(33, 11, present) == 11 and RunRules.stockOwner(nil, 11, present) == 11)
	local sum = RunRules.summary({ { value = 100.4, to = 11 }, { value = 50, to = 22 }, { value = -5, to = 11 }, { value = 0 / 0 :: any, to = 22 } } :: any, 11)
	check("the results card's sums: every piece and its value (whole dollars; nothing negative), yours apart", sum.count == 4 and sum.mine == 2
		and sum.mineValue == 100 and sum.value == 150, `{sum.count} {sum.value} {sum.mine} {sum.mineValue}`)
	local none = RunRules.summary({}, 11)
	check("…an empty truck: nothing", none.count == 0 and none.value == 0 and none.mine == 0)
end

-- ── Config.Runs' numbers ───────────────────────────────────────────────────

do
	check("Config.Runs: 4 at most, the PLAY circle you stand in, the remote's rate limit", R.MaxParty == 4 and R.Play.Height > 3 and R.Play.Radius >= 10
		and type(Config.Robust.Limits.Runs) == "number" and Config.Robust.Limits.Runs >= 2 and Config.Robust.Limits.Runs <= 10)
	check("…the fades, the holds, the truck's prompts", R.Fade.Out > 0 and R.Fade.In > 0 and R.EndHold > R.Fade.Out and R.LeaveHold > 0 and R.Truck.Reach >= 6
		and #R.Truck.At == 3 and type(R.Truck.Attribute) == "string")
	local carded = true
	for _, h in { "sandbox_house", "pond_cabin", "lone_house", "forest_lodge", "old_mill", "orchard_cottage" } do
		local card = R.Houses[h]
		carded = carded and card ~= nil and #card.wall == 3 and #card.roof == 3 and card.icon ~= "" and card.line ~= ""
	end
	check("…10.4 a PLAY panel card for each of the six places, the circle's two colours (free, counting down); no portals any more", carded
		and #R.Play.Free == 3 and #R.Play.Waiting == 3 and (R :: any).Portal == nil and (R :: any).Countdown == nil)
end

-- ── 10.6 both in PLAY: one "house busy" check (RunRules.houseBusy) for the lobbies and the quick round ────────────
do
	local inRun = function(house: string): boolean
		return house == "pond_cabin"
	end
	local waiting = { house = "old_mill", phase = "wait" }
	check("10.6 houseBusy: the quick round's place while it counts down to it: \"round\" (a lobby picks another)", RunRules.houseBusy("old_mill", inRun, waiting) == "round")
	check("…while it plays there and while it rides back (over): \"round\" too", RunRules.houseBusy("old_mill", inRun, { house = "old_mill", phase = "play" }) == "round"
		and RunRules.houseBusy("old_mill", inRun, { house = "old_mill", phase = "over" }) == "round")
	check("…a house a run is in (a lobby's or the round's): \"run\"; any other: free (nil)", RunRules.houseBusy("pond_cabin", inRun, waiting) == "run"
		and RunRules.houseBusy("lone_house", inRun, waiting) == nil)
	check("…nobody queued (idle) or the rounds off (no round): the place is nobody's", RunRules.houseBusy("old_mill", inRun, { house = "old_mill", phase = "idle" }) == nil
		and RunRules.houseBusy("old_mill", inRun, nil) == nil)
	check("…the round's own pick (no round given) sees only the runs: never a house a lobby's run is in", RunRules.houseBusy("pond_cabin", inRun, nil) == "run"
		and RunRules.houseBusy("old_mill", inRun, nil) == nil)
	check("NEG. …junk (no house, a number): nil, no error", RunRules.houseBusy(nil, inRun, waiting) == nil and RunRules.houseBusy(5, inRun, waiting) == nil)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
