-- 8.1 SANDBOX, the upgrades on the server: the real server/Upgrades.luau with the real server/PlayerData.luau and
-- server/Collection.luau (UpgradesServer.luau, PlayerDataServer.luau, CollectionServer.luau through tests/run_tests.py)
-- on tests/runtime/CollectionRuntime.luau's players, DataStore, clock, Net, workspace and plots. Joining (an 8.0 save
-- gets none, the state goes out once), buying (the money taken with the reason "Upgrade", the level, the analytics, the
-- "bought" message, the stands and the lights through the collection), refusals (no save, no warehouse of your own, not
-- enough money, the top level, a second click on one card, garbage on the remote, the rate limit), the lights' income
-- exact (what the stands earned before is paid at the old rate), a small upgrade stand refusing a bed, the van's engine
-- (a van there and one that comes later; another player's untouched), Danny's attribute, the window's "open", the
-- admin's MAX / RESET (the pieces on the stands lost back to the stock), the save round trip (the flag, twice) and the
-- migration (an old save, a garbled one). Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
local Rules = require("./UpgradeRules")
local CollectionRules = require("./CollectionRules")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Upgrades = require("./UpgradesServer")

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
local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
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

-- What the hooks saw: every money change, every analytics event, every listener call.
local money: { { player: any, delta: number, reason: string?, sku: string? } } = {}
PlayerData.onMoney = function(player: Player, delta: number, reason: string?, sku: string?)
	table.insert(money, { player = player, delta = delta, reason = reason, sku = sku })
end
local events: { { player: any, name: string, value: any, a: any } } = {}
PlayerData.analytics.event = function(player: any, name: any, value: any, a: any)
	table.insert(events, { player = player, name = name, value = value, a = a })
end
local heard: { any } = {}
Upgrades.onChanged(function(player: Player)
	table.insert(heard, player)
end)
local function paid(player: any, reason: string, from: number?): number
	local sum = 0
	for index = (from or 0) + 1, #money do
		local m = money[index]
		if m.player == player and m.reason == reason then
			sum += m.delta
		end
	end
	return sum
end

-- An 8.0 save (every flag of its day and the collection's; an `sandboxUpgrades` field without its flag is not read).
local function save80(cash: number): any
	return {
		money = cash, xp = 0, deliveries = 3, tutorial = true, phone = true, starterKit = true, vestKit = true,
		noPacks = true, noJacket = true, noShoes = true, perGameBags = true, vanOnly = true, carStages = true,
		vanStages = true, xpCurve = Config.Levels.Curve, cars = { [Config.CompanyVan.Car] = true }, car = Config.CompanyVan.Car,
		collectionKept = true, collection = { entries = {}, nextUid = 1 }, sandboxUpgrades = { stands = 4, lights = 5 },
	}
end

PlayerData.start()
Collection.start()
Upgrades.start()
local U = Config.SandboxUpgrades

-- ── Joining ────────────────────────────────────────────────────────────────
E.saves.Player_101 = save80(5000)
local mark = #E.sent
local A = E.join(101, "Ann")
local profileA = PlayerData.get(A) :: any
check("an 8.0 save loads without upgrades (its sandboxUpgrades without the flag is not read)", profileA ~= nil and profileA.money == 5000 and same(profileA.sandboxUpgrades, {}))
E.flush()
local states = kinds(E.received(A, "Upgrades", mark), "state")
check("joining: the state goes out once (no levels, the money)", #states == 1 and same(states[1].levels, {}) and states[1].money == 5000, #states)
check("… Danny's attribute: level 0; Collection.stands 12, boost 1", A:GetAttribute(U.Danny) == 0 and Collection.stands(A) == 12 and Collection.boost(A) == 1)
local B = E.join(202, "Ben") -- a new player
check("a new player: none", same((PlayerData.get(B) :: any).sandboxUpgrades, {}))

-- ── Refusals before buying ──────────────────────────────────────────────────
local ok, why = Upgrades.buy(A, "stands")
check("no warehouse of your own (no plot): refused, says why; no money taken", ok == false and type(why) == "string" and string.find(why :: string, "warehouse of your own", 1, true) ~= nil and profileA.money == 5000, why)
E.plotOf[A] = 1
local stranger = E.player(303) -- here, but their save never loaded
E.plotOf[stranger] = 3
ok, why = Upgrades.buy(stranger, "stands")
check("no save loaded: refused", ok == false and why == "Your save isn't loaded yet.", why)
local junkOk = true
for _, id in { "nitro", 5, {}, nil, "", "STANDS" } do
	local yes, said = Upgrades.buy(A, id :: any)
	junkOk = junkOk and yes == false and said == "That's no upgrade."
end
check("no such upgrade (an unknown id, a number, a table, nil, \"\", the wrong case): refused", junkOk and profileA.money == 5000)

-- ── Buying ──────────────────────────────────────────────────────────────────
local moneyAt, eventsAt, heardAt = #money, #events, #heard
mark = #E.sent
ok, why = Upgrades.buy(A, "stands", 1)
E.flush()
check("More stands level 1: bought for $1,000 (the money taken)", ok == true and why == nil and profileA.money == 4000 and same(profileA.sandboxUpgrades, { stands = 1 }), why)
local spent = money[moneyAt + 1]
check("… PlayerData.spend: -$1,000, the reason \"Upgrade\", the SKU its id", spent ~= nil and spent.delta == -1000 and spent.reason == "Upgrade" and spent.sku == "stands" and #money == moneyAt + 1)
local bought = events[eventsAt + 1]
check("… analytics: UpgradeBought (the level, the id)", bought ~= nil and bought.name == "UpgradeBought" and bought.value == 1 and bought.a == "stands")
local msgs = E.received(A, "Upgrades", mark)
check("… the client: \"bought\" and one new state", #kinds(msgs, "bought") == 1 and kinds(msgs, "bought")[1].id == "stands" and kinds(msgs, "bought")[1].level == 1
	and #kinds(msgs, "state") == 1 and same(kinds(msgs, "state")[1].levels, { stands = 1 }) and kinds(msgs, "state")[1].money == 4000)
check("… 14 stands now: the collection's state says so, the listeners heard", Collection.stands(A) == 14 and #heard == heardAt + 1
	and kinds(E.received(A, "Collection", mark), "state")[1].stands == 14)
mark = #E.sent
ok = Upgrades.buy(A, "stands", 1)
E.flush()
check("a second click on the same card (the level it offered is bought): nothing bought, the state again", ok == false and profileA.money == 4000 and Rules.level(profileA.sandboxUpgrades, "stands") == 1
	and #kinds(E.received(A, "Upgrades", mark), "state") == 1 and lastNotice(A, mark) == "")
profileA.money = 100
mark = #E.sent
E.fire(A, "Upgrades", { kind = "buy", id = "engine", level = 1 })
check("not enough money: refused, the notice says the price and the money", profileA.money == 100 and Rules.level(profileA.sandboxUpgrades, "engine") == 0
	and lastNotice(A, mark) == "Van engine costs $600: you have $100.", lastNotice(A, mark))

-- the remote: garbage and the rate limit
profileA.money = 100000
E.advance(2)
local before = table.clone(profileA.sandboxUpgrades)
for _, message in { nil, "buy", 5, true, { kind = "buy" }, { kind = "buy", id = {} }, { kind = "buy", id = "stands", level = "x" }, { kind = "sell", id = "stands" }, { kind = 7 } } :: { any } do
	E.advance(1)
	E.fire(A, "Upgrades", message)
end
check("the remote: garbage buys nothing (no table, no id, a table id, a junk level, another kind)", same(profileA.sandboxUpgrades, before) and profileA.money == 100000)
E.advance(2)
mark = #E.sent
for _ = 1, 10 do
	E.fire(A, "Upgrades", { kind = "state" })
end
local answered = #kinds(E.received(A, "Upgrades", mark), "state")
check(`the rate limit: 10 requests at once, {Config.Robust.Limits.Upgrades} answered`, answered == Config.Robust.Limits.Upgrades, answered)
E.advance(2)
mark = #E.sent
E.fire(B, "Upgrades", { kind = "buy", id = "danny", level = 1 })
check("a player without a warehouse of their own (no plot) can't buy through the remote either", same((PlayerData.get(B) :: any).sandboxUpgrades, {}) and string.find(lastNotice(B, mark), "warehouse of your own", 1, true) ~= nil, lastNotice(B, mark))

-- ── The lights: the income exact across a purchase ─────────────────────────
local piano = Collection.add(A, { item = "piano", condition = 1 }) :: string
local radio = Collection.add(A, { item = "radio", condition = 1 }) :: string
Collection.display(A, piano, 1)
E.flush()
Collection.tick() -- (what came before: paid out)
E.advance(0.01)
local rate0 = Collection.incomePerMinute(A)
local incomeAt = #money
E.advance(30)
E.fire(A, "Upgrades", { kind = "buy", id = "lights", level = 1 })
check("Showroom lights level 1 bought ($750)", Rules.level(profileA.sandboxUpgrades, "lights") == 1 and profileA.money == 100000 - 750 + paid(A, "CollectionIncome", incomeAt), profileA.money)
local rate1 = Collection.incomePerMinute(A)
check("… the income × 1.1 (Collection.incomePerMinute, Collection.boost)", near(rate1, rate0 * 1.1) and near(Collection.boost(A), 1.1), `{rate0} {rate1}`)
E.advance(30)
Collection.tick()
local expect = rate0 * 0.5 + rate1 * 0.5
local got = paid(A, "CollectionIncome", incomeAt)
check("… the minute paid exactly: 30 s at the old rate, 30 s at the new (in whole dollars, the cents carried)", got <= expect + 1e-6 and got > expect - 1, `{got} of {expect}`)
mark = #E.sent
E.fire(A, "Collection", { kind = "state" })
local view = kinds(E.received(A, "Collection", mark), "state")[1]
local pianoView: any = nil
for _, entry in view.stock do
	if entry.uid == piano then
		pianoView = entry
	end
end
check("… the picker's and the HUD's numbers: the state's income and the piece's view × 1.1", pianoView ~= nil and near(view.income, math.floor(rate1 * 100 + 0.5) / 100)
	and near(pianoView.income, math.floor(CollectionRules.income({ item = "piano", condition = 1 }, 1.1) * 100 + 0.5) / 100))

-- ── A small upgrade stand ────────────────────────────────────────────────────
local bed = Collection.add(A, { item = "bed", condition = 1 }) :: string
ok, why = Collection.display(A, bed, 13)
check("upgrade stand 13 (small): the double bed is too big, says where it goes", ok == false and type(why) == "string" and string.find(why :: string, "too big", 1, true) ~= nil and string.find(why :: string, "1 – 12", 1, true) ~= nil, why)
ok = Collection.display(A, radio, 13)
check("… the kitchen radio goes on it; stand 15 (not bought yet) refused", ok == true and not Collection.display(A, bed, 15) and Collection.display(A, bed, 2))

-- ── The van's engine and Danny ──────────────────────────────────────────────
local vanA = E.addCar(101)
local vanB = E.addCar(202)
local vanNobody = E.addCar(999)
check("a van at level 0: SpeedMult 1", vanA:GetAttribute("SpeedMult") == 1 and vanB:GetAttribute("SpeedMult") == 1)
E.advance(1)
E.fire(A, "Upgrades", { kind = "buy", id = "engine", level = 1 })
E.advance(1)
E.fire(A, "Upgrades", { kind = "buy", id = "engine", level = 2 })
check("Van engine level 2: Ann's van's SpeedMult 1.10 at once; Ben's and nobody's untouched", near(vanA:GetAttribute("SpeedMult"), 1.1) and vanB:GetAttribute("SpeedMult") == 1 and vanNobody:GetAttribute("SpeedMult") == 1)
local vanA2 = E.addCar(101)
check("… a van of hers that comes later (PLAY, CAR, a move's START) gets it too", near(vanA2:GetAttribute("SpeedMult"), 1.1))
E.advance(1)
E.fire(A, "Upgrades", { kind = "buy", id = "danny", level = 1 })
check("Danny's training level 1: Ann's attribute 1 (Danny walks 10 % faster: shared/MoveHelperBrain.luau trained)", A:GetAttribute(U.Danny) == 1)

-- ── The top level ────────────────────────────────────────────────────────────
for level = 2, 4 do
	E.advance(1)
	E.fire(A, "Upgrades", { kind = "buy", id = "stands", level = level })
end
check("More stands to its top: 20 stands", Rules.level(profileA.sandboxUpgrades, "stands") == 4 and Collection.stands(A) == 20)
local cash = profileA.money
ok, why = Upgrades.buy(A, "stands")
check("… at its top: refused, says so, nothing taken", ok == false and why == "More stands is at its top level." and profileA.money == cash, why)

-- ── The window ──────────────────────────────────────────────────────────────
mark = #E.sent
Upgrades.open(A)
local opened = E.received(A, "Upgrades", mark)
check("Upgrades.open (the desk's prompt): the state, then { kind = \"open\" }", #opened == 2 and opened[1].kind == "state" and opened[2].kind == "open")
mark = #E.sent
Upgrades.open(stranger)
check("… without a save: a notice, no window", #kinds(E.received(stranger, "Upgrades", mark), "open") == 0 and lastNotice(stranger, mark) ~= "")

-- ── The save round trip ─────────────────────────────────────────────────────
local levels = table.clone(profileA.sandboxUpgrades)
check("Upgrades.levels: a copy", same(Upgrades.levels(A), levels) and Upgrades.levels(A) ~= profileA.sandboxUpgrades)
E.leave(A)
local stored = E.saves.Player_101
check("leaving saves the levels with the flag", stored ~= nil and stored.sandboxUpgradesKept == true and same(stored.sandboxUpgrades, levels) and stored[Rules.Flag] == true)
A = E.join(101, "Ann")
E.plotOf[A] = 1
profileA = PlayerData.get(A) :: any
E.flush()
check("rejoining: the same levels, 20 stands, the lights, Danny's attribute", same(profileA.sandboxUpgrades, levels) and Collection.stands(A) == 20 and near(Collection.boost(A), 1.1) and A:GetAttribute(U.Danny) == 1)
check("… the radio still on upgrade stand 13", (function()
	for _, entry in Collection.stock(A) do
		if entry.uid == radio then
			return entry.stand == 13
		end
	end
	return false
end)())
local vanA3 = E.addCar(101)
check("… a van that comes after rejoining: its engine", near(vanA3:GetAttribute("SpeedMult"), 1.1))
E.leave(A)
A = E.join(101, "Ann")
E.plotOf[A] = 1
profileA = PlayerData.get(A) :: any
check("twice: the same", same(profileA.sandboxUpgrades, levels))

-- ── The admin ───────────────────────────────────────────────────────────────
local said = Upgrades.admin(A, "max")
check("⬆ MAX UPGRADES: every one at its top, said (20 stands, ×1.61)", same(profileA.sandboxUpgrades, Rules.full()) and string.find(said, "20 stands", 1, true) ~= nil and string.find(said, "1.61", 1, true) ~= nil, said)
for _ = 1, 3 do
	Collection.add(A, { item = "box", condition = 1 })
end
local onTop = 0
for _, entry in Collection.stock(A) do
	if entry.stand == nil and onTop < 3 then
		onTop += 1
		Collection.display(A, entry.uid, 16 + onTop)
	end
end
local shownHigh = 0
for _, entry in Collection.stock(A) do
	shownHigh += if entry.stand and entry.stand > 12 then 1 else 0
end
said = Upgrades.admin(A, "reset")
local stillHigh = 0
for _, entry in Collection.stock(A) do
	stillHigh += if entry.stand and entry.stand > 12 then 1 else 0
end
check("↺ RESET UPGRADES: none, 12 stands; the pieces on 13 – 20 back to the stock, said", same(profileA.sandboxUpgrades, {}) and Collection.stands(A) == 12 and shownHigh >= 2 and stillHigh == 0
	and string.find(said, `{shownHigh} pieces went back`, 1, true) ~= nil and A:GetAttribute(U.Danny) == 0, said)
check("… the admin on a player without a save: says so", string.find(Upgrades.admin(stranger, "max"), "no save", 1, true) ~= nil)

-- ── The migration ───────────────────────────────────────────────────────────
E.saves.Player_404 = save80(50)
E.saves.Player_404.sandboxUpgradesKept = true
E.saves.Player_404.sandboxUpgrades = { stands = 99, lights = "x", engine = 2.5, junk = 3 }
local D = E.join(404, "Dee")
check("a garbled save with the flag: cleaned (the top for too much, a fraction down, junk dropped)", same((PlayerData.get(D) :: any).sandboxUpgrades, { stands = 4, engine = 2 }))
check("no warnings", #E.warnings == 0, E.warnings[1])

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
