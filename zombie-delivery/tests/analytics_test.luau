-- Logic test of the analytics plan (6.13, shared/AnalyticsPlan.luau, Config.Analytics): the onboarding funnel's ten
-- steps (8.2: their order, only joining and PLAY implied, an upgrade or a sale before the move waits, the save's flag
-- and an old save past them all), the custom events (a short fixed list of valid names), the custom fields (few,
-- short, cleaned), the money's reasons (every source and sink the game passes, the transaction types, the batched
-- ones, an unknown reason as Other), the errors' script and line, the budget and the admin line; how a move ended in a
-- word (the real ends' words), the counts' bands and the grip checks' sampling (one a window of GripEvery, a random
-- one). 10.6: the city's funnel, events, reasons and levels went with it.
-- (tests/run_tests.py also checks that every reason and event name used in src/server is one of the plan's.)
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Plan = require("./AnalyticsPlan")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function same(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function list(t: { number }): string
	local parts = {}
	for _, n in t do
		table.insert(parts, tostring(n))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- ── The onboarding funnel ─────────────────────────────────────────────────
do
	local S = Plan.SandboxSteps
	local names = {}
	for _, step in S do
		table.insert(names, step.name)
	end
	check("8.2: ten steps, in the owner's order", table.concat(names, " ") == "Joined PressedPlay FirstContract EnteredHouse FirstPieceInVan FirstTripHome FirstPieceOnShow FirstIncome FirstSale FirstUpgrade",
		table.concat(names, " "))
	local seen, bad = {}, {}
	for _, name in names do
		if seen[name] or not Plan.validName(name) then
			table.insert(bad, name)
		end
		seen[name] = true
	end
	check("8.2: the step names are valid and unique", #bad == 0, table.concat(bad, ", "))
	local implied = {}
	for index, step in S do
		if step.implied then
			table.insert(implied, index)
		end
	end
	check("8.2: only joining and PLAY are implied (an upgrade never implies a move)", same(implied, { 1, 2 }), list(implied))
	check("8.2: allOf: every step", Plan.allOf(S) == 1023 and Plan.logged(Plan.allOf(S), S) == 10)
	check("8.2: stepOf by name (a city name is none of them)", Plan.stepOf("FirstContract", S) == 3 and Plan.stepOf("FirstUpgrade", S) == 10
		and Plan.stepOf("Joined", S) == 1 and Plan.stepOf("Level2", S) == nil)
	check("10.6: without steps: the game's", Plan.stepOf("FirstUpgrade") == 10 and Plan.logged(1023) == 10 and Plan.mark(5, 10) == 517 and Plan.has(512, 10))

	-- the owner's way through, with an upgrade bought before the first move and a sale before the show
	local mask, logged = 0, {}
	local function reach(name: string): { number }
		local out
		mask, out = Plan.reach(mask, Plan.stepOf(name, S) :: number, S)
		for _, n in out do
			table.insert(logged, n)
		end
		return out
	end
	check("8.2: joined", same(reach("Joined"), { 1 }))
	check("8.2: an upgrade bought right after joining: PLAY is implied, the upgrade waits", same(reach("FirstUpgrade"), { 2 }) and Plan.has(mask, 10, S) and Plan.logged(mask, S) == 2)
	check("8.2: the contract", same(reach("FirstContract"), { 3 }))
	check("8.2: the same step again: nothing", same(reach("FirstContract"), {}))
	check("8.2: into the house, a piece in the van, the trip home", same(reach("EnteredHouse"), { 4 }) and same(reach("FirstPieceInVan"), { 5 }) and same(reach("FirstTripHome"), { 6 }))
	check("8.2: a sale before the show waits (it never implies the show or the income)", same(reach("FirstSale"), {}) and Plan.logged(mask, S) == 6)
	check("8.2: on show", same(reach("FirstPieceOnShow"), { 7 }))
	local paid = reach("FirstIncome")
	check("8.2: the income: it with the sale and the upgrade that waited", same(paid, { 8, 9, 10 }), list(paid))
	check("8.2: every step once, in order", same(logged, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }) and mask == Plan.allOf(S), list(logged))
	local m2, out2 = Plan.reach(0, 4, S)
	check("8.2: into the house with nothing before it (a crew mate): only joined and PLAY, the house waits for a contract", same(out2, { 1, 2 }) and Plan.has(m2, 4, S) and not Plan.has(m2, 3, S), list(out2))
	local m3, out3 = Plan.reach(5, 11, S)
	local m4, out4 = Plan.reach(5, 0, S)
	local m5, out5 = Plan.reach(5, 2.5, S)
	check("8.2: no step outside 1 – 10 or a fraction", m3 == 5 and m4 == 5 and m5 == 5 and #out3 + #out4 + #out5 == 0 and Plan.mark(5, 11, S) == 5
		and Plan.mark(5, 10, S) == 517 and Plan.mark(5, 1.5, S) == 5 and not Plan.has(1023, 11, S))
	local _, none = Plan.reach(Plan.allOf(S), 5, S)
	check("8.2: an old save logs nothing", #none == 0)
end

do
	local all = Plan.allOf(Plan.SandboxSteps)
	local flag = Plan.SandboxFlag
	check("8.2: the save's flag", flag == "sandboxOnboardingKept")
	check("8.2: no save: a new player (0)", Plan.sandboxFrom(nil) == 0)
	check("8.2: a lock-only record (no money): a new player (0)", Plan.sandboxFrom({ lock = { job = "x", at = 1 } }) == 0)
	check("8.2: a real save from before 8.2 (no flag): past every step", Plan.sandboxFrom({ money = 40 }) == all and Plan.sandboxFrom({ money = 40, sandboxOnboarding = 3 }) == all)
	check("8.2: a real save with the flag keeps its steps", Plan.sandboxFrom({ money = 40, sandboxOnboarding = 7, [flag] = true }) == 7
		and Plan.sandboxFrom({ money = 40, sandboxOnboarding = 0, [flag] = true }) == 0)
	check("8.2: a bad number is checked", Plan.sandboxFrom({ money = 40, sandboxOnboarding = 1e9, [flag] = true }) == all
		and Plan.sandboxFrom({ money = 40, sandboxOnboarding = -3, [flag] = true }) == 0 and Plan.sandboxFrom({ money = 40, sandboxOnboarding = 0 / 0, [flag] = true }) == all
		and Plan.sandboxFrom({ money = 40, sandboxOnboarding = 6.7, [flag] = true }) == 6 and Plan.sandboxFrom({ money = 40, sandboxOnboarding = "7", [flag] = true }) == all)
	check("8.2: the city's old funnel field is none of it", Plan.sandboxFrom({ money = 40, onboarding = 5, sandboxOnboarding = 9, [flag] = true }) == 9)
end

-- ── 8.2: the moves' words, the bands, the grip's sampling ─────────────────
do
	local events = { "MoveStarted", "MoveFinished", "MoveFinishedValue", "MoveGaveUp", "GripCheck", "CollectibleFound", "UpgradeBought", "CollectionAdded" }
	local missing = {}
	for _, name in events do
		if not Plan.isEvent(name) then
			table.insert(missing, name)
		end
	end
	check("8.2: every move's event in the plan (and the upgrades' and the collection's)", #missing == 0, table.concat(missing, ", "))
	-- the words server/Moving.luau's ends say (tests/sandboxmove_runtime_test.luau checks them on the real module)
	local how = Plan.moveHow
	check("8.2: FINISH", how("done", "Finished: what came home is in your warehouse", 300, false) == "finish"
		and how("done", "Finished: what was still in the van stayed behind", 300, false) == "finish")
	check("8.2: everything home", how("done", "Everything is home in your warehouse", 300, true) == "all")
	check("8.2: the clock (nothing home, a late trip, a FINISH in the grace)", how("failed", "Time's up: nothing reached your warehouse", -1, false) == "time"
		and how("late", nil, -30, false) == "time" and how("done", "Time's up: what reached your warehouse is yours", 0, false) == "time"
		and how("done", "Finished: what came home is in your warehouse", -10, false) == "time")
	check("8.2: GIVE UP, after a trip or before", how("done", "You called it off: what came home is yours", 300, false) == "giveup"
		and how("cancelled", "You called it off", 300, false) == "giveup")
	check("8.2: the owner left", how("done", "Ann left the game: what came home is in their warehouse", 300, false) == "left"
		and how("cancelled", "Ann left the game", 300, false) == "left")
	check("8.2: the admin's end", how("cancelled", "Called off by the admin", 300, false) == "admin" and how("done", nil, 300, false) == "admin")
	local words = {}
	for _, word in { "finish", "all", "time", "giveup", "left", "admin" } do
		if Plan.fieldValue(word) ~= word then
			table.insert(words, word)
		end
	end
	check("8.2: every word survives as a field", #words == 0, table.concat(words, ", "))
	local B = Plan.band
	check("8.2: bands of one (the trips)", B(0, 1, 6) == "0" and B(3, 1, 6) == "3" and B(5, 1, 6) == "5" and B(6, 1, 6) == "6plus" and B(40, 1, 6) == "6plus")
	check("8.2: bands of five (the pieces)", B(1, 5, 30) == "0-4" and B(4, 5, 30) == "0-4" and B(5, 5, 30) == "5-9" and B(17, 5, 30) == "15-19" and B(29, 5, 30) == "25-29"
		and B(30, 5, 30) == "30plus" and B(400, 5, 30) == "30plus")
	check("8.2: a band of a non-number or under 0: as 0, whole", B(nil, 5, 30) == "0-4" and B(0 / 0, 1, 6) == "0" and B(-3, 1, 6) == "0" and B(2.9, 1, 6) == "2")
	check("8.2: a band is a field as it is", Plan.fieldValue(B(17, 5, 30)) == "15-19" and Plan.fieldValue(B(99, 5, 30)) == "30plus")
	check("8.2: Config.Analytics.GripEvery: one in 10", Config.Analytics.GripEvery == 10)
	-- the grip's sampling: one check a window of `every`, a random one of it
	local function run(every: number, checks: number, rolls: { number }): { number }
		local at = 0
		local function roll(): number
			at += 1
			return rolls[(at - 1) % #rolls + 1]
		end
		local sampler = Plan.sampler(every, roll())
		local sent = {}
		for n = 1, checks do
			if Plan.sample(sampler, every, roll()) then
				table.insert(sent, n)
			end
		end
		return sent
	end
	local sent = run(10, 100, { 0.37, 0.05, 0.91, 0.5, 0.0, 0.999, 0.2 })
	local perWindow, inRange = {}, true
	for _, n in sent do
		local window = (n - 1) // 10 + 1
		perWindow[window] = (perWindow[window] or 0) + 1
	end
	for window = 1, 10 do
		inRange = inRange and perWindow[window] == 1
	end
	check("8.2: 100 checks: 10 sent, one in each window of 10", #sent == 10 and inRange, list(sent))
	local first = run(10, 10, { 0 })
	local last = run(10, 10, { 0.9999 })
	check("8.2: the roll picks the window's check (0: its first, under 1: its last)", same(first, { 1 }) and same(last, { 10 }), `{list(first)} {list(last)}`)
	check("8.2: under a window: one at most", #run(10, 9, { 0.95 }) == 0 and #run(10, 9, { 0.1 }) == 1)
	check("8.2: every 1: all of them; a bad roll is the first", #run(1, 5, { 0.5 }) == 5 and same(run(10, 10, { 0 / 0 }), { 1 }))
end

-- ── The custom events ─────────────────────────────────────────────────────
do
	local seen, bad = {}, {}
	for _, name in Plan.Events do
		if seen[name] or not Plan.validName(name) then
			table.insert(bad, name)
		end
		seen[name] = true
	end
	check("the events: valid and unique names", #bad == 0, table.concat(bad, ", "))
	check("a short fixed list", #Plan.Events >= 10 and #Plan.Events <= 40, #Plan.Events)
	local wanted = { "DeathOnJob", "SessionLength", "ServerError", "ClientError", "MoveDone", "VisitorOffer", "PlayerTrade", "CollectionSold" }
	local missing = {}
	for _, name in wanted do
		if not Plan.isEvent(name) then
			table.insert(missing, name)
		end
	end
	check("every event the game sends", #missing == 0, table.concat(missing, ", "))
	local city = {}
	for _, name in { "JobFailedTime", "ZipRide", "BusRide", "ScooterRental", "GoldenDone", "MissionCleared", "HordeBeaten" } do
		if Plan.isEvent(name) then
			table.insert(city, name)
		end
	end
	check("10.6: none of the city's", #city == 0, table.concat(city, ", "))
	check("validName refuses spaces, lower case, digits first, empty, too long, not a string", not Plan.validName("Job failed") and not Plan.validName("jobFailed") and not Plan.validName("1Job") and not Plan.validName("") and not Plan.validName(string.rep("A", 33)) and not Plan.validName(nil) and Plan.validName(string.rep("A", 32)))
end

do
	check("the field keys are Roblox's", table.concat(Plan.FieldKeys, " ") == "CustomField01 CustomField02 CustomField03")
	check("no fields: nil", Plan.fields() == nil and Plan.fields("", nil, "  ") == nil)
	local f = Plan.fields("rare", 3, nil) :: { [string]: string }
	check("fields by position", f.CustomField01 == "rare" and f.CustomField02 == "3" and f.CustomField03 == nil)
	local g = Plan.fields(nil, "Picked up!") :: { [string]: string }
	check("a value is cleaned (letters, digits, _ and -)", g.CustomField01 == nil and g.CustomField02 == "Pickedup")
	check("a value is short", #Plan.fieldValue(string.rep("x", 100)) == 32 and Plan.fieldValue({}) == "")
end

-- ── The economy ───────────────────────────────────────────────────────────
do
	local customTypes = { Refund = true, Sale = true, Admin = true, Other = true }
	local bad = {}
	for reason, kind in Plan.Sources do
		if not Plan.validName(reason) or not (table.find(Plan.EnumTypes, kind) or customTypes[kind]) then
			table.insert(bad, `{reason}: {kind}`)
		end
		local rule = Plan.money(reason, 10)
		if rule.flow ~= "Source" or rule.reason ~= reason or rule.kind ~= kind then
			table.insert(bad, `{reason} as a source`)
		end
		if Plan.Sinks[reason] then
			table.insert(bad, `{reason} both ways`)
		end
	end
	for reason, kind in Plan.Sinks do
		if not Plan.validName(reason) or not table.find(Plan.EnumTypes, kind) then
			table.insert(bad, `{reason}: {kind}`)
		end
		local rule = Plan.money(reason, -10)
		if rule.flow ~= "Sink" or rule.reason ~= reason or rule.kind ~= kind then
			table.insert(bad, `{reason} as a sink`)
		end
	end
	check("every reason: a valid name, one side, a known transaction type", #bad == 0, table.concat(bad, "; "))
	local missing = {}
	for _, reason in { "CollectionIncome", "CollectionSale", "SandboxTask", "BookMilestone", "VisitorOffer", "PlayerSale", "CrewRescue", "KillReward", "Admin" } do
		if not Plan.Sources[reason] then
			table.insert(missing, reason)
		end
	end
	for _, reason in { "Upgrade", "VanPaint", "CrewDischarge", "PlayerBuy", "TradeFee" } do
		if not Plan.Sinks[reason] then
			table.insert(missing, reason)
		end
	end
	check("every source and sink the game passes", #missing == 0, table.concat(missing, ", "))
	check("the enum's types where they fit", Plan.Sinks.Upgrade == "Shop" and Plan.Sinks.TradeFee == "ContextualPurchase" and Plan.Sources.SandboxTask == "TimedReward"
		and Plan.Sources.CollectionIncome == "Gameplay" and Plan.Sources.CollectionSale == "Sale")
	check("10.6: none of the city's reasons", Plan.Sources.DeliveryPay == nil and Plan.Sources.LevelReward == nil and Plan.Sinks.Car == nil and Plan.Sinks.Fuel == nil)
	local other = Plan.money(nil, 5)
	local unknown = Plan.money("Lottery", -5)
	local wrongSide = Plan.money("Upgrade", 5)
	check("no reason, an unknown one or the wrong side: Other", other.reason == "Other" and other.flow == "Source" and unknown.reason == "Other" and unknown.flow == "Sink" and wrongSide.reason == "Other" and wrongSide.flow == "Source" and not other.batch)
	check("the frequent ones are batched", Plan.money("KillReward", 5).batch and Plan.money("CollectionIncome", 2).batch and not Plan.money("CollectionSale", 50).batch and not Plan.money("Upgrade", -500).batch)
	for reason in Plan.Batched do
		check(`batched {reason} is a known reason`, Plan.Sources[reason] ~= nil or Plan.Sinks[reason] ~= nil)
	end
end

-- ── The errors ────────────────────────────────────────────────────────────
do
	local a, la = Plan.errorWhere("ServerScriptService.Server.Moving:123: attempt to index nil with 'piece'", nil)
	check("a server error's script and line", a == "Moving" and la == 123, `{a} {la}`)
	local b, lb = Plan.errorWhere("Players.Bob.PlayerScripts.Client.Hud:45: boom", "Hud")
	check("a client error's script and line", b == "Hud" and lb == 45, `{b} {lb}`)
	local c, lc = Plan.errorWhere("something broke", "Runs")
	check("no place in the message: the script, line 0", c == "Runs" and lc == 0)
	local d, ld = Plan.errorWhere(nil, nil)
	check("nothing at all: Unknown", d == "Unknown" and ld == 0)
	check("a script name with spaces or too long: Unknown", Plan.scriptName("a b") == "Unknown" and Plan.scriptName(string.rep("x", 41)) == "Unknown" and Plan.scriptName("Main") == "Main")
end

-- ── The rest ──────────────────────────────────────────────────────────────
do
	local A = Config.Analytics
	check("Config.Analytics: on, Cash, a batch time", A.Enabled == true and A.Currency == "Cash" and A.BatchSeconds >= 10)
	check("the budget grows with the players", Plan.budget(0, A.Budget) == A.Budget.Base and Plan.budget(10, A.Budget) == A.Budget.Base + 10 * A.Budget.PerPlayer)
	check("a few client errors a minute at most", Config.Robust.Limits.ClientError > 0 and Config.Robust.Limits.ClientError * 60 <= 5 and A.ClientErrorsMax >= 1 and A.ErrorsPerMinute >= 1)
	check("a session's minutes", Plan.minutes(90) == 1.5 and Plan.minutes(0) == 0 and Plan.minutes(-5) == 0 and Plan.minutes(3600) == 60)
	local on = Plan.summary("on", { onboarding = 3, economy = 7 }, "Economy Sink Upgrade 500")
	local studio = Plan.summary("studio", { dropped = 2 }, nil)
	check("the admin line, on", string.find(on, "ON, sending", 1, true) ~= nil and string.find(on, "onboarding 3", 1, true) ~= nil and string.find(on, "economy 7", 1, true) ~= nil and string.find(on, "custom 0", 1, true) ~= nil and string.find(on, "last: Economy Sink Upgrade 500", 1, true) ~= nil, on)
	check("the admin line, Studio", string.find(studio, "OFF in Studio", 1, true) ~= nil and string.find(studio, "dropped 2", 1, true) ~= nil and string.find(studio, "last:", 1, true) == nil, studio)
	check("the admin line, off", string.find(Plan.summary("off", {}, ""), "OFF (Config", 1, true) ~= nil)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
