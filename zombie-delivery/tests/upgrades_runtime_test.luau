-- 8.1 SANDBOX, the upgrades on the server: the real server/Upgrades.luau with the real server/PlayerData.luau and
-- server/Collection.luau (UpgradesServer.luau, PlayerDataServer.luau, CollectionServer.luau through tests/run_tests.py)
-- on tests/runtime/CollectionRuntime.luau's players, DataStore, clock, Net, workspace and plots. Joining (an 8.0 save
-- gets none, the state goes out once), buying (the money taken with the reason "Upgrade", the level, the analytics, the
-- "bought" message, the stands and the lights through the collection), refusals (no save, no warehouse of your own, not
-- enough money, the top level, a second click on one card, garbage on the remote, the rate limit), the lights' income
-- exact (what the stands earned before is paid at the old rate), a small upgrade stand refusing a bed, the van's engine
-- (a van there and one that comes later; another player's untouched), Danny's attribute, the window's "open", the
-- admin's MAX / RESET (the pieces on the stands lost back to the stock), the save round trip (the flag, twice) and the
-- migration (an old save, a garbled one).
-- 8.3, the warehouse's levels (design/warehouse-levels/KONTRAKT.md): a save from before 8.3 (no warehouseLevelKept)
-- loads with the warehouse at level 4 (the building it had) and keeps its stands and the pieces on them; a new player
-- has the garage (level 1, 2 stands); the player attribute WarehouseLevel; More stands refused below level 4 (the
-- reason as the notice, nothing taken); the ZDC Warehouse bought level by level (the money, the stands, the attribute,
-- the pieces on their stands, the listeners) up to the Logistics Center, More stands there; the save keeps the level
-- with the flag (a new player's garage stays a garage, never the migration's level 4); the admin's MAX (level 5),
-- RESET (the garage) and 🏗 LV n (a level down: a piece too big for its stand now back to the stock). Run: python3
-- tests/run_tests.py [path to the luau binary]

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
local S1 = U.List.stands.prices[1] -- (More stands' first level: Config's, 8.3 economy)

-- ── Joining ────────────────────────────────────────────────────────────────
E.saves.Player_101 = save80(5000)
local mark = #E.sent
local A = E.join(101, "Ann")
local profileA = PlayerData.get(A) :: any
check("an 8.0 save loads without upgrades (its sandboxUpgrades without the flag is not read); 8.3: but with the warehouse at level 4, the building it had (no warehouseLevelKept)",
	profileA ~= nil and profileA.money == 5000 and same(profileA.sandboxUpgrades, { warehouse = 3 }))
E.flush()
local states = kinds(E.received(A, "Upgrades", mark), "state")
check("joining: the state goes out once (the levels: the warehouse's 3, the money)", #states == 1 and same(states[1].levels, { warehouse = 3 }) and states[1].money == 5000, #states)
check("… Danny's attribute: level 0; Collection.stands 12, boost 1; 8.3: the attribute WarehouseLevel 4", A:GetAttribute(U.Danny) == 0 and Collection.stands(A) == 12 and Collection.boost(A) == 1
	and A:GetAttribute(U.WarehouseAttribute) == 4)
local B = E.join(202, "Ben") -- a new player
check("a new player: none; 8.3: the garage (WarehouseLevel 1, 2 stands)", same((PlayerData.get(B) :: any).sandboxUpgrades, {}) and B:GetAttribute(U.WarehouseAttribute) == 1 and Collection.stands(B) == 2)

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
check(`More stands level 1: bought for {Rules.money(S1)} (the money taken)`, ok == true and why == nil and profileA.money == 5000 - S1 and same(profileA.sandboxUpgrades, { warehouse = 3, stands = 1 }), why)
local spent = money[moneyAt + 1]
check(`… PlayerData.spend: -{Rules.money(S1)}, the reason "Upgrade", the SKU its id`, spent ~= nil and spent.delta == -S1 and spent.reason == "Upgrade" and spent.sku == "stands" and #money == moneyAt + 1)
local bought = events[eventsAt + 1]
check("… analytics: UpgradeBought (the level, the id)", bought ~= nil and bought.name == "UpgradeBought" and bought.value == 1 and bought.a == "stands")
local msgs = E.received(A, "Upgrades", mark)
check("… the client: \"bought\" and one new state", #kinds(msgs, "bought") == 1 and kinds(msgs, "bought")[1].id == "stands" and kinds(msgs, "bought")[1].level == 1
	and #kinds(msgs, "state") == 1 and same(kinds(msgs, "state")[1].levels, { warehouse = 3, stands = 1 }) and kinds(msgs, "state")[1].money == 5000 - S1)
check("… 14 stands now: the collection's state says so, the listeners heard", Collection.stands(A) == 14 and #heard == heardAt + 1
	and kinds(E.received(A, "Collection", mark), "state")[1].stands == 14)
mark = #E.sent
ok = Upgrades.buy(A, "stands", 1)
E.flush()
check("a second click on the same card (the level it offered is bought): nothing bought, the state again", ok == false and profileA.money == 5000 - S1 and Rules.level(profileA.sandboxUpgrades, "stands") == 1
	and #kinds(E.received(A, "Upgrades", mark), "state") == 1 and lastNotice(A, mark) == "")
profileA.money = 100
mark = #E.sent
E.fire(A, "Upgrades", { kind = "buy", id = "engine", level = 1 })
check("not enough money: refused, the notice says the price and the money", profileA.money == 100 and Rules.level(profileA.sandboxUpgrades, "engine") == 0
	and lastNotice(A, mark) == `Van engine costs {Rules.money(U.List.engine.prices[1])}: you have $100.`, lastNotice(A, mark))

-- the remote: garbage and the rate limit
profileA.money = 250000 -- (enough for every upgrade below: 8.3 economy's prices)
E.advance(2)
local before = table.clone(profileA.sandboxUpgrades)
for _, message in { nil, "buy", 5, true, { kind = "buy" }, { kind = "buy", id = {} }, { kind = "buy", id = "stands", level = "x" }, { kind = "sell", id = "stands" }, { kind = 7 } } :: { any } do
	E.advance(1)
	E.fire(A, "Upgrades", message)
end
check("the remote: garbage buys nothing (no table, no id, a table id, a junk level, another kind)", same(profileA.sandboxUpgrades, before) and profileA.money == 250000)
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
check(`Showroom lights level 1 bought ({Rules.money(U.List.lights.prices[1])})`, Rules.level(profileA.sandboxUpgrades, "lights") == 1 and profileA.money == 250000 - U.List.lights.prices[1] + paid(A, "CollectionIncome", incomeAt), profileA.money)
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
check("leaving saves the levels with the flag (8.3: and warehouseLevelKept, its warehouse level its own from now on)", stored ~= nil and stored.sandboxUpgradesKept == true
	and same(stored.sandboxUpgrades, levels) and stored[Rules.Flag] == true and stored.warehouseLevelKept == true and stored[Rules.WarehouseFlag] == true)
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
check("⬆ MAX UPGRADES: every one at its top, said (8.3: warehouse level 5, the Logistics Center: 32 stands, ×1.61)", same(profileA.sandboxUpgrades, Rules.full())
	and string.find(said, "warehouse level 5, the Logistics Center", 1, true) ~= nil and string.find(said, "32 stands", 1, true) ~= nil and string.find(said, "1.61", 1, true) ~= nil
	and Collection.stands(A) == 32 and A:GetAttribute(U.WarehouseAttribute) == 5, said)
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
-- (8.3: RESET is back to the garage: what stands past its 2 stands goes back to the stock; the piano and the bed on 1
-- and 2 stay)
local shownHigh, lowBefore = 0, {}
for _, entry in Collection.stock(A) do
	shownHigh += if entry.stand and entry.stand > 2 then 1 else 0
	if entry.stand and entry.stand <= 2 then
		lowBefore[entry.uid] = entry.stand
	end
end
said = Upgrades.admin(A, "reset")
local stillHigh, lowKept = 0, next(lowBefore) ~= nil
for _, entry in Collection.stock(A) do
	stillHigh += if entry.stand and entry.stand > 2 then 1 else 0
	if lowBefore[entry.uid] then
		lowKept = lowKept and entry.stand == lowBefore[entry.uid]
	end
end
check("↺ RESET UPGRADES: none, 8.3: the garage (warehouse level 1: 2 stands); the pieces on 3 – 32 back to the stock, the ones on 1 and 2 kept, said",
	same(profileA.sandboxUpgrades, {}) and Collection.stands(A) == 2 and shownHigh >= 4 and stillHigh == 0 and lowKept
		and string.find(said, "warehouse level 1, the Garage: 2 stands", 1, true) ~= nil and string.find(said, `{shownHigh} pieces went back`, 1, true) ~= nil
		and A:GetAttribute(U.Danny) == 0 and A:GetAttribute(U.WarehouseAttribute) == 1, said)
check("… the admin on a player without a save: says so", string.find(Upgrades.admin(stranger, "max"), "no save", 1, true) ~= nil)

-- ── 8.3: the warehouse's levels ─────────────────────────────────────────────
local function standOf(player: any, uid: string): number?
	for _, entry in Collection.stock(player) do
		if entry.uid == uid then
			return entry.stand
		end
	end
	return nil
end
-- 8.3: 🏗 LV n, the admin's warehouse level for free (the other upgrades kept); a level down sends a piece too big for
-- its stand at the new level back to the stock (a bed on stand 13: a big stand at level 5, a small one at level 4)
said = Upgrades.admin(A, "max")
local bedA = Collection.add(A, { item = "bed", condition = 1 }) :: string
local onBig = Collection.display(A, bedA, 13)
said = Upgrades.admin(A, "level4")
check("8.3: 🏗 LV 4 from the top: the Big Warehouse (More stands kept: 20 stands); the bed on stand 13, a small one now, back to the stock, said",
	onBig and Rules.warehouseLevel(profileA.sandboxUpgrades) == 4 and Rules.level(profileA.sandboxUpgrades, "stands") == 4 and Collection.stands(A) == 20
		and standOf(A, bedA) == nil and A:GetAttribute(U.WarehouseAttribute) == 4
		and string.find(said, "warehouse level 4, the Big Warehouse", 1, true) ~= nil and string.find(said, "1 piece went back", 1, true) ~= nil, said)
said = Upgrades.admin(A, "level1")
check("… 🏗 LV 1: the garage (2 stands; the upgrade's level 0 is not kept), said", (profileA.sandboxUpgrades :: any).warehouse == nil and Collection.stands(A) == 2
	and A:GetAttribute(U.WarehouseAttribute) == 1 and string.find(said, "warehouse level 1, the Garage", 1, true) ~= nil, said)
Upgrades.admin(A, "reset")
local profileB = PlayerData.get(B) :: any
E.plotOf[B] = 2
profileB.money = 400000 -- (8.3 economy: every warehouse level and More stands' first)
E.advance(2)
mark = #E.sent
local cashB = profileB.money
E.fire(B, "Upgrades", { kind = "buy", id = "stands", level = 1 })
check("8.3: More stands in the garage: refused, the notice the lock's reason (\"Needs the Big Warehouse\"), nothing taken", lastNotice(B, mark) == "Needs the Big Warehouse"
	and lastNotice(B, mark) == Rules.locked(profileB.sandboxUpgrades, "stands") and profileB.money == cashB and Rules.level(profileB.sandboxUpgrades, "stands") == 0, lastNotice(B, mark))
local sofaB = Collection.add(B, { item = "sofa", condition = 1 }) :: string
local tvB = Collection.add(B, { item = "tv", condition = 1 }) :: string
local radioB = Collection.add(B, { item = "radio", condition = 1 }) :: string
check("8.3: (Ben's sofa and TV on the garage's stands 1 and 2; a third stand isn't his)", Collection.display(B, sofaB, 1) and Collection.display(B, tvB, 2) and not Collection.display(B, radioB, 3))
local prices = (Rules.def("warehouse") :: any).prices
local function buyWarehouse(k: number, stands: number)
	E.advance(1)
	local before, heardAt, at, moneyAt = profileB.money, #heard, #E.sent, #money
	E.fire(B, "Upgrades", { kind = "buy", id = "warehouse", level = k })
	E.flush()
	local level = k + 1
	local state = kinds(E.received(B, "Collection", at), "state")
	local spent = money[moneyAt + 1]
	check(`8.3: the Deliveros Warehouse level {level} bought ({Rules.money(prices[k])}, the reason Upgrade): {stands} stands, WarehouseLevel {level}, the listeners heard, "bought"; the sofa and the TV still on 1 and 2`,
		Rules.level(profileB.sandboxUpgrades, "warehouse") == k and profileB.money == before - prices[k] and spent ~= nil and spent.reason == "Upgrade" and spent.sku == "warehouse"
			and Collection.stands(B) == stands and B:GetAttribute(U.WarehouseAttribute) == level and #heard == heardAt + 1 and heard[#heard] == B
			and #kinds(E.received(B, "Upgrades", at), "bought") == 1 and state[#state] ~= nil and state[#state].stands == stands
			and standOf(B, sofaB) == 1 and standOf(B, tvB) == 2, `{Collection.stands(B)} {B:GetAttribute(U.WarehouseAttribute)}`)
end
buyWarehouse(1, 4)
buyWarehouse(2, 8)
buyWarehouse(3, 12)
E.advance(1)
local okStands = Upgrades.buy(B, "stands", 1)
check("8.3: in the Big Warehouse More stands is for sale: level 1, 14 stands; the radio on small stand 13", okStands and Collection.stands(B) == 14 and Collection.display(B, radioB, 13))
buyWarehouse(4, 26)
check("8.3: … the Logistics Center: 24 big stands + More stands' 2; the radio still on stand 13 (a big one now: a level up never makes a stand smaller)",
	standOf(B, radioB) == 13 and Collection.stands(B) == 26)
local cashTop = profileB.money
local okTop, whyTop = Upgrades.buy(B, "warehouse")
check("8.3: the Deliveros Warehouse at its top (level 5): refused, says so, nothing taken", okTop == false and whyTop == "Deliveros Warehouse is at its top level." and profileB.money == cashTop, whyTop)
local levelsB = table.clone(profileB.sandboxUpgrades)
E.leave(B)
check("8.3: Ben leaves: his levels saved with warehouseLevelKept", E.saves.Player_202.warehouseLevelKept == true and same(E.saves.Player_202.sandboxUpgrades, levelsB))
B = E.join(202, "Ben")
E.flush()
check("8.3: … back: the Logistics Center as he left it (the flag: no migration), 26 stands, his pieces on 1, 2 and 13", same((PlayerData.get(B) :: any).sandboxUpgrades, levelsB)
	and Collection.stands(B) == 26 and B:GetAttribute(U.WarehouseAttribute) == 5 and standOf(B, sofaB) == 1 and standOf(B, tvB) == 2 and standOf(B, radioB) == 13)
local cy = E.join(505, "Cy") -- a brand-new player
check("8.3: a brand-new player: the garage", same((PlayerData.get(cy) :: any).sandboxUpgrades, {}) and Collection.stands(cy) == 2 and cy:GetAttribute(U.WarehouseAttribute) == 1)
E.leave(cy)
cy = E.join(505, "Cy")
check("8.3: … after his first save (money in it, the flag with it) still the garage: never the migration's level 4", E.saves.Player_505.money ~= nil
	and E.saves.Player_505.warehouseLevelKept == true and same((PlayerData.get(cy) :: any).sandboxUpgrades, {}) and Collection.stands(cy) == 2)
-- an 8.1 / 8.2 save (the upgrades' flag, not the warehouse level's): More stands 2, pieces on its stands 1 and 13 – 16
E.saves.Player_606 = save80(900)
E.saves.Player_606.sandboxUpgradesKept = true
E.saves.Player_606.sandboxUpgrades = { stands = 2, lights = 1 }
E.saves.Player_606.collection = { entries = {}, nextUid = 10 }
for index, stand in { 1, 13, 14, 15, 16 } do
	table.insert(E.saves.Player_606.collection.entries, { uid = `606-{index}`, item = "radio", variant = 1, condition = 1, name = "Radio", stand = stand, got = 0 })
end
local fay = E.join(606, "Fay")
E.flush()
local keptOn = true
for index, stand in { 1, 13, 14, 15, 16 } do
	keptOn = keptOn and standOf(fay, `606-{index}`) == stand
end
check("8.3: a save from before 8.3 with More stands: the Big Warehouse (level 4) on top of its levels, its 16 stands, every piece on its stand (nothing lost)",
	same((PlayerData.get(fay) :: any).sandboxUpgrades, { warehouse = 3, stands = 2, lights = 1 }) and Collection.stands(fay) == 16 and keptOn and fay:GetAttribute(U.WarehouseAttribute) == 4)

-- ── The migration ───────────────────────────────────────────────────────────
E.saves.Player_404 = save80(50)
E.saves.Player_404.sandboxUpgradesKept = true
E.saves.Player_404.sandboxUpgrades = { stands = 99, lights = "x", engine = 2.5, junk = 3 }
local D = E.join(404, "Dee")
check("a garbled save with the flag: cleaned (the top for too much, a fraction down, junk dropped; 8.3: from before 8.3, so the warehouse at level 4)",
	same((PlayerData.get(D) :: any).sandboxUpgrades, { stands = 4, engine = 2, warehouse = 3 }))
check("no warnings", #E.warnings == 0, E.warnings[1])

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
