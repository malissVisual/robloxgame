-- 8.2 SANDBOX, the daily tasks on the server: the real server/SandboxTasks.luau with the real server/PlayerData.luau,
-- server/Collection.luau and server/Upgrades.luau (SandboxTasksServer.luau, PlayerDataServer.luau, CollectionServer.luau,
-- UpgradesServer.luau through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's players, DataStore, clock
-- and Net, Moving's hooks and Danny's find from tests/runtime/SandboxTasksRuntime.luau. Checked: joining (an 8.1 save
-- starts fresh, the day's picks, the state once, the stock it had never counts), the progress from the real signals
-- (pieces home and the rare ones, pieces on show, a sale, the stands' income, an upgrade bought, a move's trips, a
-- clean move for the whole crew, the sofa with Danny), the "done" message, a claim that pays once (the reason, the
-- SKU), the bonus and the weekly, garbage on the remote and its rate limit, a player not loaded, the reset at 00:00
-- UTC (paid, told, no "upgrade" once all are bought), the save round trip (the flag) and the migration (an old save, a
-- garbled one, a lock-only record). Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local R = require("./SandboxTasksRuntime")
local Config = require("./Config")
local Rules = require("./SandboxTasks")
local CollectionRules = require("./CollectionRules")
local UpgradeRules = require("./UpgradeRules")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Upgrades = require("./UpgradesServer")
local Tasks = require("./SandboxTasksServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function kinds(messages: { any }, kind: string): { any }
	local out = {}
	for _, m in messages do
		if type(m) == "table" and m.kind == kind then
			table.insert(out, m)
		end
	end
	return out
end
local function lastNotice(player: any, from: number?): string
	local said = E.received(player, "Notice", from)
	return tostring(said[#said] or "")
end

local T = Config.SandboxTasks
local DAY = 86400
-- 2025-10-11 12:00 UTC, a Saturday: the next day is a Sunday, the one after it a Monday (a new week)
E.now = 20372 * DAY + 12 * 3600

-- What the hooks saw: every money change.
local money: { { player: any, delta: number, reason: string?, sku: string? } } = {}
PlayerData.onMoney = function(player: Player, delta: number, reason: string?, sku: string?)
	table.insert(money, { player = player, delta = delta, reason = reason, sku = sku })
end
local function paid(player: any, reason: string, from: number?): (number, number, string?)
	local sum, count, sku = 0, 0, nil
	for index = (from or 0) + 1, #money do
		local m = money[index]
		if m.player == player and m.reason == reason then
			sum += m.delta
			count += 1
			sku = m.sku
		end
	end
	return sum, count, sku
end

-- An 8.1 save (every flag of its day, the collection's and the upgrades'; a `sandboxTasks` field without its flag is
-- not read).
local function save81(cash: number, entries: { any }?): any
	return {
		money = cash, xp = 0, deliveries = 3, tutorial = true, phone = true, starterKit = true, vestKit = true,
		noPacks = true, noJacket = true, noShoes = true, perGameBags = true, vanOnly = true, carStages = true,
		vanStages = true, xpCurve = Config.Levels.Curve, cars = { [Config.CompanyVan.Car] = true }, car = Config.CompanyVan.Car,
		collectionKept = true, collection = { entries = entries or {}, nextUid = 50 }, sandboxUpgradesKept = true, sandboxUpgrades = {},
		sandboxTasks = { day = 1, week = 1, daily = { { id = "home", target = 8, progress = 8 } } },
	}
end

local function profileOf(player: any): any
	return PlayerData.get(player) :: any
end
-- The player's tasks set to these kinds at these targets (the picks are random: each part sets its own).
local function setTasks(player: any, daily: { { any } }, weekly: { any }?)
	local saved = profileOf(player).sandboxTasks
	saved.daily = {}
	for _, pair in daily do
		table.insert(saved.daily, { id = pair[1], target = pair[2], progress = 0, claimed = false })
	end
	saved.bonus = false
	saved.weekly = if weekly then { id = weekly[1], target = weekly[2], progress = 0, claimed = false } else nil
end
local function slot(player: any, index: any): any
	local saved = profileOf(player).sandboxTasks
	return if index == "weekly" then saved.weekly else saved.daily[index]
end
local function uidOf(player: any, item: string, nth: number?): string?
	local seen = 0
	for _, entry in Collection.stock(player) do
		if entry.item == item then
			seen += 1
			if seen == (nth or 1) then
				return entry.uid
			end
		end
	end
	return nil
end

PlayerData.start()
Collection.start()
Upgrades.start()
Tasks.start()
check("the hooks: Moving.onStored and onResult registered once each", #R.listeners.trip == 1 and #R.listeners.finish == 1)

-- ── Joining ────────────────────────────────────────────────────────────────
E.saves.Player_101 = save81(800, {
	{ uid = "101-1", item = "piano", variant = 1, condition = 1, name = "Piano", got = 1 },
	{ uid = "101-2", item = "sofa", variant = 1, condition = 1, name = "Sofa", got = 1 },
})
local mark = #E.sent
local A = E.join(101, "Ann")
E.flush()
local profileA = profileOf(A)
local day = Rules.dayOf(E.now)
check("an 8.1 save (no flag): its old tasks are not read, today's picks start fresh", profileA.sandboxTasks ~= nil and profileA.sandboxTasks.day == day
	and #profileA.sandboxTasks.daily == T.Daily and profileA.sandboxTasks.daily[1].progress == 0)
local picks = Rules.pickDaily(day, 101)
local samePicks = true
for index, pick in picks do
	samePicks = samePicks and profileA.sandboxTasks.daily[index].id == pick.id and profileA.sandboxTasks.daily[index].target == pick.target
end
check("… the day's picks for this UserId (SandboxTasks.pickDaily), the week's weekly", samePicks and profileA.sandboxTasks.weekly ~= nil
	and profileA.sandboxTasks.weekly.id == (Rules.pickWeekly(Rules.weekOf(E.now), 101) :: any).id)
local states = kinds(E.received(A, "SandboxTasks", mark), "state")
check("joining: the state goes out once (three dailies, the bonus, the weekly, the countdowns)", #states == 1 and #states[1].daily == 3 and states[1].bonus.money == T.AllDaily
	and states[1].weekly ~= nil and states[1].dayLeft == 12 * 3600 and states[1].ready == 0, #states)
check("SandboxTasks.state: the same view", Tasks.state(A) ~= nil and #(Tasks.state(A) :: any).daily == 3)

-- ── Pieces home, the rare ones, pieces on show, a sale ─────────────────────
setTasks(A, { { "home", 8 }, { "shown", 6 }, { "sell", 150 } }, { "w_rare", 20 })
mark = #E.sent
for _ = 1, 2 do
	Collection.add(A, { item = "sofa", condition = 1 }) -- (rare: $350)
end
for _ = 1, 3 do
	Collection.add(A, { item = "plant", condition = 0.9 }) -- (common)
end
E.flush()
check("five pieces home (a van unloaded): home 5/8; the stock the save had never counts", slot(A, 1).progress == 5, slot(A, 1).progress)
check("… two of them rare or better: the weekly 2/20", slot(A, "weekly").progress == 2 and CollectionRules.tierOf({ item = "sofa" }).rank >= T.RareRank)
check("… no task done yet: no \"done\"", #kinds(E.received(A, "SandboxTasks", mark), "done") == 0)
E.advance(1)
local stateNow = kinds(E.received(A, "SandboxTasks", mark), "state")
check("… the state followed (once for the burst)", #stateNow == 1 and stateNow[1].daily[1].progress == 5, #stateNow)
Collection.add(A, { item = "piano", condition = 1 }) -- (epic)
Collection.add(A, { item = "plant", condition = 1 })
Collection.add(A, { item = "plant", condition = 1 })
mark = #E.sent
Collection.add(A, { item = "box", condition = 1 })
E.flush()
local dones = kinds(E.received(A, "SandboxTasks", mark), "done")
check("eight home: the task done, \"done\" with its title and reward", slot(A, 1).progress == 8 and #dones == 1 and dones[1].title == "Bring 8 pieces home"
	and dones[1].money == Rules.rewardOf(Rules.def("home") :: Rules.Def, 8) and dones[1].weekly == false and slot(A, "weekly").progress == 3)
Collection.display(A, uidOf(A, "sofa") :: string, 1)
Collection.display(A, uidOf(A, "piano") :: string, 2)
Collection.display(A, uidOf(A, "sofa", 2) :: string, 3)
E.flush()
check("three on show: shown 3/6", slot(A, 2).progress == 3, slot(A, 2).progress)
Collection.undisplay(A, uidOf(A, "sofa", 2) :: string)
E.flush()
check("… one taken down: still 3 (the most at once)", slot(A, 2).progress == 3)
local moneyAt = #money
local price = Collection.sell(A, uidOf(A, "plant") :: string)
E.flush()
check("a plant sold: sell counts its price (CollectionSale)", price ~= nil and slot(A, 3).progress == price and paid(A, "CollectionSale", moneyAt) == price, price)

-- ── The stands' income ─────────────────────────────────────────────────────
setTasks(A, { { "income", 300 }, { "trips", 3 }, { "clean", 1 } }, { "w_income", 4000 })
moneyAt = #money
E.advance(Config.Collection.Tick * 3 + 0.5)
local income = paid(A, "CollectionIncome", moneyAt)
check("the stands paid (three payouts): income counts what they paid, the weekly too", income > 0 and slot(A, 1).progress == income and slot(A, "weekly").progress == income, income)

-- ── 8.3: the market's tasks (today's hot kinds, shared/Market.luau) ────────
do
	local Market = require("./Market")
	local hotKind = Market.pick(Market.dayOf(E.now)).hot[1]
	setTasks(A, { { "hotsell", 2 }, { "hotincome", 100 }, { "home", 8 } }, { "w_income", 4000 })
	Collection.add(A, { item = hotKind, condition = 1 })
	Collection.add(A, { item = hotKind, condition = 1 })
	Collection.add(A, { item = "box", condition = 1 }) -- (not hot: its sale counts no hot piece)
	E.flush()
	Collection.sell(A, uidOf(A, "box") :: string)
	E.flush()
	check(`8.3: a piece that isn't hot sold: hotsell 0/2`, slot(A, 1).progress == 0, slot(A, 1).progress)
	local hotPrice = Collection.sell(A, uidOf(A, hotKind) :: string)
	E.flush()
	check(`… a hot piece ({hotKind}) sold: hotsell 1/2`, hotPrice ~= nil and slot(A, 1).progress == 1, slot(A, 1).progress)
	Collection.display(A, uidOf(A, hotKind) :: string, 4)
	moneyAt = #money
	E.advance(Config.Collection.Tick * 6 + 0.5)
	local paidNow = paid(A, "CollectionIncome", moneyAt)
	check("… a hot piece on show: hotincome counts its part of what the stands paid (never more)", slot(A, 2).progress > 0 and slot(A, 2).progress < paidNow, `{slot(A, 2).progress} of {paidNow}`)
	Collection.undisplay(A, uidOf(A, hotKind) :: string)
	setTasks(A, { { "income", 300 }, { "trips", 3 }, { "clean", 1 } }, { "w_income", 4000 }) -- (as the moves below find them)
end

-- ── A move's trips, its end ────────────────────────────────────────────────
local B = E.join(202, "Ben") -- a new player, Ann's crew mate
E.flush()
check("a new player: today's picks", profileOf(B).sandboxTasks ~= nil and #profileOf(B).sandboxTasks.daily == T.Daily)
setTasks(B, { { "clean", 1 }, { "home", 8 } }, { "w_moves", 5 })
R.trip(A, { trips = 1 }, { 1, 2 })
check("a trip home: trips 1/3 (the owner's)", slot(A, 2).progress == 1)
R.trip(A, { trips = 2 }, { 3 })
mark = #E.sent
R.trip(A, { trips = 3 }, { 4 })
check("three trips in one move: done", slot(A, 2).progress == 3 and #kinds(E.received(A, "SandboxTasks", mark), "done") == 1)
R.trip(B, { trips = 1 }, { 1 })
check("… a crew mate's own trips are theirs (B has no trips task: nothing)", slot(B, 1).progress == 0)
local function move(states: { string }): any
	local made = { order = {}, things = {} }
	for index, state in states do
		table.insert(made.order, index)
		made.things[index] = { state = state }
	end
	return made
end
R.finish(A, move({ "delivered", "delivered", "home" }), { how = "cancelled", broken = 0 }, { A, B })
check("a move called off: nothing", slot(A, 3).progress == 0 and slot(B, 1).progress == 0)
R.finish(A, move({ "home", "home" }), { how = "done", broken = 0 }, { A, B })
check("a move with nothing home: nothing", slot(A, 3).progress == 0)
R.finish(A, move({ "delivered", "delivered", "home" }), { how = "done", broken = 1 }, { A, B })
check("a move with something broken: a move (B's weekly 1/5), not a clean one", slot(A, 3).progress == 0 and slot(B, 1).progress == 0 and slot(B, "weekly").progress == 1)
R.finish(A, move({ "delivered", "delivered", "home" }), { how = "late", broken = 0 }, { A, B, B })
check("a clean move (late counts): clean for the owner and the crew, a move once each", slot(A, 3).progress == 1 and slot(B, 1).progress == 1 and slot(B, "weekly").progress == 2)

-- ── An upgrade bought ──────────────────────────────────────────────────────
setTasks(A, { { "upgrade", 1 }, { "danny", 1 }, { "home", 8 } })
E.plotOf[A] = 1
profileA.money = 20000
local ok = Upgrades.buy(A, "engine", 1)
E.flush()
check("an upgrade bought at the desk: upgrade 1/1", ok == true and slot(A, 1).progress == 1)

-- ── The sofa with Danny ────────────────────────────────────────────────────
local DANNY = -2000000001
local function holding(item: string, carrier: number, helper: number?): any
	return { s = { move = { order = { 4 }, things = { [4] = { item = item, carrier = carrier, helper = helper, state = "carried" } } } }, id = DANNY }
end
R.helpers[A] = holding("armchair", 101, DANNY)
E.advance(T.DannyEvery * 2)
check("Danny holds the far end of your armchair: nothing", slot(A, 2).progress == 0)
R.helpers[A] = holding("sofa", 202, DANNY)
E.advance(T.DannyEvery * 2)
check("… of somebody else's sofa: nothing", slot(A, 2).progress == 0)
R.helpers[A] = holding("sofa", 101, nil)
E.advance(T.DannyEvery * 2)
check("… your sofa alone (dragged, nobody at its far end): nothing", slot(A, 2).progress == 0)
mark = #E.sent
R.helpers[A] = holding("sofa", 101, DANNY)
E.advance(T.DannyEvery * 2)
check("your sofa with Danny at its far end: done (the real MovingRules.holding)", slot(A, 2).progress == 1 and #kinds(E.received(A, "SandboxTasks", mark), "done") == 1)
R.helpers[A] = nil

-- ── Claims ─────────────────────────────────────────────────────────────────
setTasks(A, { { "home", 8 }, { "sell", 150 }, { "shown", 6 } }, { "w_moves", 5 })
slot(A, 1).progress = 8
moneyAt, mark = #money, #E.sent
local cashBefore = profileA.money
E.fire(A, "SandboxTasks", { kind = "claim", slot = 1 })
local reward = Rules.rewardOf(Rules.def("home") :: Rules.Def, 8)
local got, count, sku = paid(A, "SandboxTask", moneyAt)
check("CLAIM a done task: paid its reward (the reason SandboxTask, its id the SKU)", got == reward and count == 1 and sku == "home" and profileA.money == cashBefore + reward, got)
local claimed = kinds(E.received(A, "SandboxTasks", mark), "claimed")
local after = kinds(E.received(A, "SandboxTasks", mark), "state")
check("… \"claimed\" with its title and money, a new state (claimed, nothing waiting)", #claimed == 1 and claimed[1].title == "Bring 8 pieces home" and claimed[1].money == reward
	and #after >= 1 and after[#after].daily[1].claimed == true and after[#after].ready == 0)
E.advance(1)
moneyAt, mark = #money, #E.sent
E.fire(A, "SandboxTasks", { kind = "claim", slot = 1 })
check("CLAIM it again: refused (claimed already), nothing paid", paid(A, "SandboxTask", moneyAt) == 0 and lastNotice(A, mark) == "Claimed already.", lastNotice(A, mark))
E.advance(1)
mark = #E.sent
E.fire(A, "SandboxTasks", { kind = "claim", slot = 2 })
check("CLAIM one not done: refused, says why", paid(A, "SandboxTask", moneyAt) == 0 and lastNotice(A, mark) == "Not done yet.")
E.advance(1)
E.fire(A, "SandboxTasks", { kind = "claim", slot = "bonus" })
check("the bonus before every daily is done: refused", paid(A, "SandboxTask", moneyAt) == 0 and lastNotice(A) == "Finish every daily task first.")
slot(A, 2).progress, slot(A, 3).progress = 150, 6
for index = 2, 3 do
	E.advance(1)
	E.fire(A, "SandboxTasks", { kind = "claim", slot = index })
end
E.advance(1)
moneyAt = #money
E.fire(A, "SandboxTasks", { kind = "claim", slot = "bonus" })
got, count, sku = paid(A, "SandboxTask", moneyAt)
check("every daily claimed: the bonus pays AllDaily once (its SKU AllDaily)", got == T.AllDaily and count == 1 and sku == "AllDaily" and profileA.sandboxTasks.bonus == true)
E.advance(1)
moneyAt = #money
E.fire(A, "SandboxTasks", { kind = "claim", slot = "bonus" })
check("… a second time: nothing", paid(A, "SandboxTask", moneyAt) == 0 and lastNotice(A) == "The bonus is yours already.")
slot(A, "weekly").progress = 5
E.advance(1)
E.fire(A, "SandboxTasks", { kind = "claim", slot = "weekly" })
got, _, sku = paid(A, "SandboxTask", moneyAt)
check("the weekly done: its own claim, its bigger reward (SKU w_moves)", got == Rules.rewardOf(Rules.def("w_moves") :: Rules.Def, 5) and got >= 2000 and sku == "w_moves")
E.advance(5)
check("the claims saved a moment later (SaveDelay)", (E.saves.Player_101 :: any).sandboxTasks ~= nil and (E.saves.Player_101 :: any).sandboxTasks.bonus == true)

-- ── Garbage on the remote, the rate limit ──────────────────────────────────
setTasks(A, { { "home", 8 }, { "sell", 150 }, { "shown", 6 } })
slot(A, 1).progress = 8
E.advance(2)
moneyAt, mark = #money, #E.sent
local junk: { any } = {
	nil, 5, "claim", true, {}, { kind = 5 }, { kind = "explode" }, { kind = "claim" }, { kind = "claim", slot = 0 }, { kind = "claim", slot = 4 },
	{ kind = "claim", slot = 1.5 }, { kind = "claim", slot = "1" }, { kind = "claim", slot = 0 / 0 }, { kind = "claim", slot = math.huge },
	{ kind = "claim", slot = -1 }, { kind = "claim", slot = {} }, { kind = "claim", slot = "Bonus" },
}
local fine = true
for index = 1, #junk + 1 do
	E.advance(1)
	local okFire = pcall(E.fire, A, "SandboxTasks", junk[index])
	fine = fine and okFire
end
check("garbage on the remote (nil, numbers, strings, tables, unknown kinds, slots 0 / 4 / 1.5 / \"1\" / NaN / ∞ / -1 / a table): no error, nothing paid",
	fine and paid(A, "SandboxTask", moneyAt) == 0 and not slot(A, 1).claimed)
check("… and nothing but the state answered (no notice for junk)", #E.received(A, "Notice", mark) == 0, lastNotice(A, mark))
E.advance(2)
mark = #E.sent
for _ = 1, 12 do
	E.fire(A, "SandboxTasks", { kind = "state" })
end
local answered = #kinds(E.received(A, "SandboxTasks", mark), "state")
check("the rate limit: 12 requests at once, Limits.SandboxTasks answered", answered == Config.Robust.Limits.SandboxTasks, answered)
local stranger = E.player(909) -- here, but never loaded
local okStranger = pcall(function()
	E.fire(stranger, "SandboxTasks", { kind = "claim", slot = 1 })
	Tasks.note(stranger, "home", 5)
	Tasks.note(nil :: any, "home", 5)
	Tasks.note(A, 5 :: any, 5)
	Tasks.note(A, "home", 0 / 0)
end)
check("a player whose save never loaded, a nil player, garbage events: nothing, no error", okStranger and #E.received(stranger, "SandboxTasks") == 0 and Tasks.state(stranger) == nil)

-- ── The reset at 00:00 UTC ─────────────────────────────────────────────────
Upgrades.admin(A, "max") -- (every upgrade at its top: "upgrade" is never picked again)
E.flush()
setTasks(A, { { "home", 8 }, { "sell", 150 }, { "shown", 6 } }, { "w_home", 60 })
slot(A, 1).progress = 8 -- (done, not claimed)
slot(A, 2).progress = 150
slot(A, 2).claimed = true -- (done and claimed)
moneyAt, mark = #money, #E.sent
E.now = (day + 1) * DAY + 30 -- (Sunday 00:00:30 UTC)
E.advance(T.CheckEvery + 0.5)
local nextDay = day + 1
got, count, sku = paid(A, "SandboxTask", moneyAt)
check("00:00 UTC: the done-not-claimed daily paid at the reset (SKU Reset), once", got == Rules.rewardOf(Rules.def("home") :: Rules.Def, 8) and count == 1 and sku == "Reset", got)
local saidReset, saidNew = false, false
for _, text in E.received(A, "Notice", mark) do
	saidReset = saidReset or string.find(tostring(text), "Tasks paid at the reset", 1, true) ~= nil
	saidNew = saidNew or string.find(tostring(text), "New daily tasks", 1, true) ~= nil
end
check("… told: what was paid, the new dailies", saidReset and saidNew)
local skip = { upgrade = true }
local fresh = Rules.pickDaily(nextDay, 101, skip)
local same = profileA.sandboxTasks.day == nextDay and #profileA.sandboxTasks.daily == #fresh
for index, pick in fresh do
	-- (8.3: a kind the stands' payouts count, "income" or "hotincome", may have counted the payout after the reset)
	local event = (Rules.def(pick.id) :: Rules.Def).event
	same = same and profileA.sandboxTasks.daily[index].id == pick.id and (profileA.sandboxTasks.daily[index].progress == 0 or event == "income" or event == "hotincome")
end
check("… the new day's picks (none \"upgrade\": every upgrade is bought), the state sent", same and #kinds(E.received(A, "SandboxTasks", mark), "state") >= 1)
check("… the weekly kept (the same week)", profileA.sandboxTasks.weekly ~= nil and profileA.sandboxTasks.weekly.id == "w_home")
check("UpgradeRules: everything at its top", UpgradeRules.level(profileA.sandboxUpgrades, "stands") == (UpgradeRules.def("stands") :: any).max)
profileA.sandboxTasks.weekly.progress = 60
moneyAt = #money
E.now = (day + 2) * DAY + 30 -- (Monday: a new week)
E.advance(T.CheckEvery + 0.5)
got = paid(A, "SandboxTask", moneyAt)
check("Monday 00:00 UTC: a new weekly, the done one paid", profileA.sandboxTasks.week == Rules.weekOf(E.now) and profileA.sandboxTasks.weekly.progress == 0
	and got == Rules.rewardOf(Rules.def("w_home") :: Rules.Def, 60), got)

-- ── The save round trip, the migration ─────────────────────────────────────
setTasks(A, { { "home", 12 }, { "sell", 200 }, { "shown", 8 } }, { "w_rare", 25 })
slot(A, 1).progress = 7
slot(A, 3).progress, slot(A, 3).claimed = 8, true
slot(A, "weekly").progress = 4
local dayA = profileA.sandboxTasks.day
E.leave(A)
local stored = E.saves.Player_101 :: any
check("leaving saves the tasks with their flag", stored.sandboxTasksKept == true and stored.sandboxTasks ~= nil and stored.sandboxTasks.daily[1].progress == 7
	and stored.sandboxTasks.daily[3].claimed == true and stored.sandboxTasks.weekly.progress == 4)
local A2 = E.join(101, "Ann")
E.flush()
local back = profileOf(A2).sandboxTasks
check("joining again: the same tasks, progress and claims (the round trip)", back.day == dayA and back.daily[1].id == "home" and back.daily[1].target == 12 and back.daily[1].progress == 7
	and back.daily[3].claimed == true and back.weekly.id == "w_rare" and back.weekly.progress == 4)
E.leave(A2)
E.saves.Player_303 = save81(100)
E.saves.Player_303.sandboxTasksKept = true
E.saves.Player_303.sandboxTasks = { day = Rules.dayOf(E.now), week = Rules.weekOf(E.now), bonus = 1,
	daily = { { id = "home", target = 9, progress = 99 }, { id = "warp", target = 3 }, { id = "sell", target = "x" }, "x" }, weekly = { id = "home", target = 5 } }
local C = E.join(303, "Cid")
E.flush()
local cleaned = profileOf(C).sandboxTasks
check("a garbled save with the flag: checked (progress clamped, unknown and broken picks gone, no weekly from the daily pool)", cleaned ~= nil and #cleaned.daily == 1
	and cleaned.daily[1].progress == 9 and cleaned.bonus == false and cleaned.weekly == nil)
E.saves.Player_404 = { lock = { job = "other", at = 0 }, sandboxTasksKept = true, sandboxTasks = { day = 5, week = 5, daily = {} } } -- (a lock-only record)
local D = E.join(404, "Dee")
E.flush()
local fromLock = profileOf(D).sandboxTasks
check("a lock-only record (no money): not read, today's picks fresh", fromLock ~= nil and fromLock.day == Rules.dayOf(E.now) and #fromLock.daily == T.Daily)

check("no warnings", #E.warnings == 0, E.warnings[1])
print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
