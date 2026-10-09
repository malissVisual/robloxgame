-- Logic test of the analytics plan (6.13, shared/AnalyticsPlan.luau, Config.Analytics): the onboarding funnel's nine
-- steps (in order, once, the waiting and the implied ones, an old save past them all, a new one at none), the funnels'
-- steps, the custom events (a short fixed list of valid names, the failed orders' names), the custom fields (few,
-- short, cleaned), the money's reasons (every source and sink of the owner's list, the transaction types, the batched
-- ones, an unknown reason as Other), the level-ups, the errors' script and line, the budget and the admin line.
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
	local names = {}
	for _, step in Plan.Steps do
		table.insert(names, step.name)
	end
	check("nine onboarding steps", #Plan.Steps == 9, #Plan.Steps)
	check("the owner's steps in order", table.concat(names, " ") == "Joined PressedPlay WelcomeSeen FirstJob FirstDelivery Level2 FirstVehicle FirstMission FirstChapter", table.concat(names, " "))
	local seen, bad = {}, {}
	for _, name in names do
		if seen[name] or not Plan.validName(name) then
			table.insert(bad, name)
		end
		seen[name] = true
	end
	check("the step names are valid and unique", #bad == 0, table.concat(bad, ", "))
	check("only joined, PLAY and the welcome are implied", Plan.Steps[1].implied == true and Plan.Steps[2].implied == true and Plan.Steps[3].implied == true and not Plan.Steps[4].implied and not Plan.Steps[9].implied)
	check("ALL is every step", Plan.ALL == 511 and Plan.logged(Plan.ALL) == 9, Plan.ALL)
	check("stepOf by name", Plan.stepOf("Joined") == 1 and Plan.stepOf("Level2") == 6 and Plan.stepOf("FirstChapter") == 9 and Plan.stepOf("Nope") == nil)
end

do
	local mask, logged = 0, {}
	local function reach(step: number): { number }
		local out
		mask, out = Plan.reach(mask, step)
		for _, n in out do
			table.insert(logged, n)
		end
		return out
	end
	check("a new courier joins: step 1", same(reach(1), { 1 }))
	check("the same step again: nothing", same(reach(1), {}))
	check("PLAY: step 2", same(reach(2), { 2 }))
	local early = reach(5)
	check("a delivery before the first job: the welcome is implied, the delivery waits", same(early, { 3 }), list(early))
	check("… it is reached, not logged", Plan.has(mask, 5) and Plan.logged(mask) == 3)
	local catch = reach(4)
	check("the first job: it and the waiting delivery together", same(catch, { 4, 5 }), list(catch))
	reach(7)
	check("the first vehicle before level 2 waits", Plan.logged(mask) == 5)
	check("level 2 logs 6 and 7", same(reach(6), { 6, 7 }))
	check("a chapter without a mission start waits", same(reach(9), {}))
	check("the first mission logs 8 and 9", same(reach(8), { 8, 9 }))
	check("every step once, in order", same(logged, { 1, 2, 3, 4, 5, 6, 7, 8, 9 }), list(logged))
	check("then all reached", mask == Plan.ALL)
	local m2, out2 = Plan.reach(0, 4)
	check("a first job with nothing before it logs 1 – 4", same(out2, { 1, 2, 3, 4 }) and m2 == 15, list(out2))
	local m3, out3 = Plan.reach(0, 6)
	check("level 2 alone logs only the implied ones", same(out3, { 1, 2, 3 }) and Plan.has(m3, 6) and not Plan.has(m3, 4), list(out3))
	local m4, out4 = Plan.reach(7, 0)
	local m5, out5 = Plan.reach(7, 10)
	local m6, out6 = Plan.reach(7, 2.5)
	check("no step outside 1 – 9 or a fraction", m4 == 7 and m5 == 7 and m6 == 7 and #out4 + #out5 + #out6 == 0)
	local _, none = Plan.reach(Plan.ALL, 5)
	check("an old save logs nothing", #none == 0)
	check("mark sets one step, nothing outside 1 – 9", Plan.mark(0, 1) == 1 and Plan.mark(1, 3) == 5 and Plan.mark(5, 3) == 5 and Plan.mark(5, 0) == 5 and Plan.mark(5, 10) == 5 and Plan.mark(5, 1.5) == 5)
end

do
	check("no save: a new courier (0)", Plan.onboardingFrom(nil) == 0)
	check("a lock-only record (no money): a new courier (0)", Plan.onboardingFrom({ lock = { job = "x", at = 1 } }) == 0)
	check("a real save from before 6.13: past every step", Plan.onboardingFrom({ money = 40 }) == Plan.ALL)
	check("a real save keeps its steps", Plan.onboardingFrom({ money = 40, onboarding = 5 }) == 5)
	check("a bad number is checked", Plan.onboardingFrom({ money = 40, onboarding = 1e9 }) == Plan.ALL and Plan.onboardingFrom({ money = 40, onboarding = -3 }) == 0 and Plan.onboardingFrom({ money = 40, onboarding = 0 / 0 }) == Plan.ALL and Plan.onboardingFrom({ money = 40, onboarding = 6.7 }) == 6)
end

-- ── The funnels ───────────────────────────────────────────────────────────
do
	local delivery = Plan.Funnels.Delivery
	check("Delivery: taken, picked up, delivered", table.concat(delivery, " ") == "Taken PickedUp Delivered")
	check("Mission: started, completed", table.concat(Plan.Funnels.Mission, " ") == "Started Completed")
	check("the first step", same(Plan.funnelSteps(0, 1, 3), { 1 }))
	check("delivered without a logged pick-up fills it", same(Plan.funnelSteps(1, 3, 3), { 2, 3 }))
	check("nothing behind or past the end", #Plan.funnelSteps(3, 3, 3) == 0 and #Plan.funnelSteps(2, 1, 3) == 0 and same(Plan.funnelSteps(0, 5, 3), { 1, 2, 3 }))
	for funnel, steps in Plan.Funnels do
		local bad = {}
		for _, name in steps do
			if not Plan.validName(name) then
				table.insert(bad, name)
			end
		end
		check(`{funnel}: valid names`, Plan.validName(funnel) and #bad == 0, table.concat(bad, ", "))
	end
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
	check("a short fixed list", #Plan.Events >= 10 and #Plan.Events <= 16, #Plan.Events)
	local wanted = { "DeathOnJob", "JobFailedTime", "JobFailedCargo", "QueueAddAll", "ZipRide", "BusRide", "ScooterRental", "StylePurchase", "SessionLength", "ServerError", "ClientError" }
	local missing = {}
	for _, name in wanted do
		if not Plan.isEvent(name) then
			table.insert(missing, name)
		end
	end
	check("every event the owner asked for", #missing == 0, table.concat(missing, ", "))
	check("validName refuses spaces, lower case, digits first, empty, too long, not a string", not Plan.validName("Job failed") and not Plan.validName("jobFailed") and not Plan.validName("1Job") and not Plan.validName("") and not Plan.validName(string.rep("A", 33)) and not Plan.validName(nil) and Plan.validName(string.rep("A", 32)))
	local fails = { Plan.failEvent("time"), Plan.failEvent("cargo"), Plan.failEvent("gaveup"), Plan.failEvent(nil), Plan.failEvent("whatever") }
	check("the failed orders' names", table.concat(fails, " ") == "JobFailedTime JobFailedCargo JobGaveUp JobFailedOther JobFailedOther", table.concat(fails, " "))
	local unknown = {}
	for _, name in fails do
		if not Plan.isEvent(name) then
			table.insert(unknown, name)
		end
	end
	check("… all in the list", #unknown == 0, table.concat(unknown, ", "))
end

do
	check("the field keys are Roblox's", table.concat(Plan.FieldKeys, " ") == "CustomField01 CustomField02 CustomField03")
	check("no fields: nil", Plan.fields() == nil and Plan.fields("", nil, "  ") == nil)
	local f = Plan.fields("car", 3, nil) :: { [string]: string }
	check("fields by position", f.CustomField01 == "car" and f.CustomField02 == "3" and f.CustomField03 == nil)
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
	for _, reason in { "DeliveryPay", "Tip", "TaskReward", "MissionReward", "LevelReward", "Refund", "Admin" } do
		if not Plan.Sources[reason] then
			table.insert(missing, reason)
		end
	end
	for _, reason in { "Car", "Bike", "Gun", "Gear", "Item", "Kit", "Style", "Fuel", "Tow", "Repair", "Reroll", "RealEstate" } do
		if not Plan.Sinks[reason] then
			table.insert(missing, reason)
		end
	end
	check("every source and sink the owner listed", #missing == 0, table.concat(missing, ", "))
	check("the enum's types where they fit", Plan.Sinks.Car == "Shop" and Plan.Sinks.Fuel == "ContextualPurchase" and Plan.Sources.TaskReward == "TimedReward" and Plan.Sources.TutorialReward == "Onboarding" and Plan.Sources.DeliveryPay == "Gameplay")
	local other = Plan.money(nil, 5)
	local unknown = Plan.money("Lottery", -5)
	local wrongSide = Plan.money("Car", 5)
	check("no reason, an unknown one or the wrong side: Other", other.reason == "Other" and other.flow == "Source" and unknown.reason == "Other" and unknown.flow == "Sink" and wrongSide.reason == "Other" and wrongSide.flow == "Source" and not other.batch)
	check("the frequent ones are batched", Plan.money("KillReward", 5).batch and Plan.money("Fuel", -3).batch and Plan.money("Tip", 2).batch and not Plan.money("DeliveryPay", 50).batch and not Plan.money("Car", -500).batch)
	for reason in Plan.Batched do
		check(`batched {reason} is a known reason`, Plan.Sources[reason] ~= nil or Plan.Sinks[reason] ~= nil)
	end
end

-- ── The progression ───────────────────────────────────────────────────────
do
	check("the paths", Plan.validName(Plan.Paths.Level) and Plan.validName(Plan.Paths.Missions))
	check("a level-up completes the level left", same(Plan.levelUps(1, 2), { 1 }) and same(Plan.levelUps(3, 5), { 3, 4 }))
	check("no level-up, no event", #Plan.levelUps(5, 5) == 0 and #Plan.levelUps(6, 4) == 0)
	check("a jump of many levels: 20 at most", #Plan.levelUps(1, 100) == 20)
end

-- ── The errors ────────────────────────────────────────────────────────────
do
	local a, la = Plan.errorWhere("ServerScriptService.Server.Jobs:123: attempt to index nil with 'offer'", nil)
	check("a server error's script and line", a == "Jobs" and la == 123, `{a} {la}`)
	local b, lb = Plan.errorWhere("Players.Bob.PlayerScripts.Client.Hud:45: boom", "Hud")
	check("a client error's script and line", b == "Hud" and lb == 45, `{b} {lb}`)
	local c, lc = Plan.errorWhere("something broke", "Cargo")
	check("no place in the message: the script, line 0", c == "Cargo" and lc == 0)
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
	local on = Plan.summary("on", { onboarding = 3, economy = 7 }, "Economy Sink Car 500")
	local studio = Plan.summary("studio", { dropped = 2 }, nil)
	check("the admin line, on", string.find(on, "ON, sending", 1, true) ~= nil and string.find(on, "onboarding 3", 1, true) ~= nil and string.find(on, "economy 7", 1, true) ~= nil and string.find(on, "funnel 0", 1, true) ~= nil and string.find(on, "last: Economy Sink Car 500", 1, true) ~= nil, on)
	check("the admin line, Studio", string.find(studio, "OFF in Studio", 1, true) ~= nil and string.find(studio, "dropped 2", 1, true) ~= nil and string.find(studio, "last:", 1, true) == nil, studio)
	check("the admin line, off", string.find(Plan.summary("off", {}, ""), "OFF (Config", 1, true) ~= nil)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
