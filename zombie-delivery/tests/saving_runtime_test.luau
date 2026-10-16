-- 8.3 SAVES: the save pipeline on the server (the real server/PlayerData.luau with the real Collection, CollectionBook,
-- Upgrades and VanPaint: PlayerDataServer.luau … through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's
-- players, clock and a DataStore that fails, throttles and is slow on cue (Runtime.storeFault, budget, storeLatency).
--   * A load that fails never overwrites: tried LoadTries times with a backoff, then kicked (no profile, nothing
--     written by the leave or the autosave); twice and then fine: played as usual; Studio: a fresh profile, never
--     written; a save that errors while it is read (a migration's bug): kicked, its data untouched.
--   * Retries: a leave save failing twice is written on its third try (1 + 2 s); a rejoin to this server waits for its
--     own leave save and reads what it wrote; a save that can wait, failing once, is written a second later.
--   * Saves soon: a purchase (the warehouse's level, the lights, the paint) is saved Soon s later, one save for a burst;
--     right after a write, not before Gap s; a book milestone and pieces brought home the same; the autosave skips a
--     player written a moment ago; under the request budget's reserve the saves that can wait wait (the leave save
--     never). The warehouse level's "warehouse:<k>" key goes along (UpgradeRules.warehouseKey: one key, the level after
--     a purchase; an older server keeps it while it drops the level).
--   * The lock: another server's fresh lock is waited for; a save taken over (another server, a newer session here)
--     is never written again from here; an older snapshot never lands over a newer one.
--   * Garbage in a save is cleaned on load (every sandbox field: wrong types, negatives, huge counts, 5000 pieces) and
--     the cleaned save loads the same again; a NaN or ±inf in a live profile is mended on its way (the money: the
--     stored one); the money never goes negative or NaN through the API.
--   * Unknown keys: a newer server's top-level keys are written back as they were (the leave save, a rejoin, again);
--     the keys this version knows are its own (an old optional value is never brought back); RESET MY SAVE drops them.
--   * 8.4: the house the moving card shows (sandboxHouseSeed): written with its flag, read back on another server's
--     join (the same house), dropped once a trip spent it; only a whole number in Config.Moving.Sandbox.Seeds' range,
--     only from a real save written with its flag (junk, an older save, a lock-only record, a new player: none).
--     8.9: which house it is (sandboxHouse) the same way, only an id shared/SandboxMap.luau knows; a real 8.4 save
--     with a seed and no house's flag: the farmstead's (its seed was rolled for the one house there was).
--   * Size: the biggest realistic sandbox save, measured.
--   * The shutdown (BindToClose): every player saved at once, in parallel, waited for (a failed try too); a store that
--     never answers is given up on at CloseWait.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local P = require("./VanPaintRuntime")
local Config = require("./Config")
local SaveGuard = require("./SaveGuard")
local Market = require("./Market")
local FurnitureLooks = require("./FurnitureLooks")
local BookRules = require("./CollectionBookRules")
local PaintRules = require("./VanPaintRules")
local TaskRules = require("./SandboxTasks")
local UpgradeRules = require("./UpgradeRules")
local SandboxMap = require("./SandboxMap")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Book = require("./CollectionBookServer")
local Upgrades = require("./UpgradesServer")
local VanPaint = require("./VanPaintServer")
local S = Config.Saving
local task = E.task -- (the runtime's: its threads wait for the test's clock)
local _ = P

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
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
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end
-- The player in the game with this UserId whose save has loaded (a join that waited: E.join returns it later).
local function Players_byId(userId: number): any
	for _, player in E.Players:GetPlayers() do
		if player.UserId == userId and PlayerData.get(player) then
			return player
		end
	end
	return nil
end
local function without(t: any, key: string): any
	local out = table.clone(t)
	out[key] = nil
	return out
end
-- The DataStore calls (all, or only the ones that wrote) for a key since the index `from` of E.storeCalls.
local function callsOf(key: string, from: number): number
	local n = 0
	for index = from + 1, #E.storeCalls do
		if E.storeCalls[index].key == key then
			n += 1
		end
	end
	return n
end
local function writesOf(key: string, from: number): number
	local n = 0
	for index = from + 1, #E.storeCalls do
		local call = E.storeCalls[index]
		if call.key == key and call.wrote then
			n += 1
		end
	end
	return n
end
local function warned(text: string, from: number): boolean
	for index = from + 1, #E.warnings do
		if string.find(E.warnings[index], text, 1, true) then
			return true
		end
	end
	return false
end
-- A fault for one key: its next `times` calls fail.
local function failing(key: string, times: number): (string, number) -> string?
	local left = times
	return function(name: string): string?
		if name == key and left > 0 then
			left -= 1
			return "503: DataStore request failed (test)"
		end
		return nil
	end
end
-- An 8.3 save (every flag of its day): a sandbox player's.
local function save83(cash: number): any
	return {
		money = cash, xp = 0, deliveries = 3, tutorial = true, phone = true, starterKit = true, vestKit = true,
		noPacks = true, noJacket = true, noShoes = true, perGameBags = true, vanOnly = true, carStages = true,
		vanStages = true, xpCurve = Config.Levels.Curve, cars = { [Config.CompanyVan.Car] = true }, car = Config.CompanyVan.Car,
		collectionKept = true, collection = { entries = { { uid = "1-1", item = "sofa", variant = 1, condition = 0.9, name = "Sofa", stand = 1, got = 1 } }, nextUid = 2 },
		collectionBookKept = true, collectionBook = { sofa = { n = 1, best = 0.9 } }, collectionBookPaid = {},
		sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = { warehouse = 1, lights = 1 }, -- (level 2: the Workshop)
		marketKept = true, market = { day = 0, kinds = {} },
		vanPaintKept = true, vanPaint = { owned = { red = true }, worn = { paint = "red", livery = "zdc" } },
		sandboxOnboardingKept = true, sandboxOnboarding = 0,
	}
end

PlayerData.onMoney = function() end
PlayerData.analytics.event = function() end
local started = E.clock
PlayerData.start()
Collection.start()
Book.start()
Upgrades.start()
VanPaint.start()
check("the keys this version writes are listed (a save built from the stand-in: no warning)", not warned("could not be listed", 0))

-- A join whose load may wait (in a thread: its waits wait for the clock; the CLI's main thread must not yield), the
-- clock moved `seconds` on: the player (nil while the load still runs).
local function joinWaiting(userId: number, name: string, seconds: number): any
	local player: any = nil
	task.spawn(function()
		player = E.join(userId, name)
	end)
	E.advance(seconds)
	return player
end

-- Moves the clock to `after` s past the autosave's next round (every AutosaveSeconds from PlayerData.start).
local function pastAutosave(after: number)
	local every = Config.AutosaveSeconds
	local nextRound = started + every * (math.floor((E.clock - started) / every + 1e-9) + 1)
	E.advance(nextRound - E.clock + after)
end

-- ── A load that fails never overwrites ─────────────────────────────────────
E.saves.Player_201 = save83(7777)
local before201 = deepCopy(E.saves.Player_201)
local from = #E.storeCalls
E.storeFault = function(key: string): string?
	return if key == "Player_201" then "502: API Services rejected request (test)" else nil
end
local A = joinWaiting(201, "Ann", 8)
local span = E.storeCalls[#E.storeCalls].at - E.storeCalls[from + 1].at
check("a load that fails every try: LoadTries tries, 1 + 2 + 4 s apart, then kicked", A ~= nil and callsOf("Player_201", from) == S.LoadTries and A.kicked ~= nil
	and math.abs(span - 7) < 1e-6, `{callsOf("Player_201", from)} tries over {span} s`)
check("… no profile: nothing to play on (loaded false)", PlayerData.get(A) == nil and not PlayerData.loaded(A))
E.leave(A)
E.storeFault = nil
E.advance(Config.AutosaveSeconds + 1)
check("… the real save untouched (the load, the leave, an autosave)", same(E.saves.Player_201, before201))

E.saves.Player_202 = save83(2020)
E.storeFault = failing("Player_202", 2)
local B = joinWaiting(202, "Bea", 3.1)
E.storeFault = nil
check("a load that fails twice: the third try reads it, played as usual", PlayerData.loaded(B) and (PlayerData.get(B) :: any).money == 2020 and B.kicked == nil)

E.studio = true
E.saves.Player_203 = save83(3030)
local before203 = deepCopy(E.saves.Player_203)
E.storeFault = function(key: string): string?
	return if key == "Player_203" then "no API access (test)" else nil
end
local C = E.join(203, "Cid")
E.storeFault = nil
local pc = PlayerData.get(C) :: any
check("Studio without API access: played at once on a fresh profile (the start money), not loaded, never kicked", pc ~= nil and pc.money == Config.Sandbox.StartMoney
	and not PlayerData.loaded(C) and C.kicked == nil)
PlayerData.spend(C, 100, "Upgrade")
check("… PlayerData.save says it wrote nothing", PlayerData.save(C) == false)
E.advance(Config.AutosaveSeconds + 1)
E.leave(C)
check("… a purchase, a save, an autosave and the leave: never written over the real save", same(E.saves.Player_203, before203))
E.studio = false

E.saves.Player_204 = save83(4040)
local before204 = deepCopy(E.saves.Player_204)
local fromSave = Market.fromSave
Market.fromSave = function(_saved: any): any
	error("a migration's bug (test)")
end
local wmark = #E.warnings
local D = E.join(204, "Dot")
Market.fromSave = fromSave
check("a save that errors while it is read (a migration's bug): kicked, no profile, the warning names it", D.kicked ~= nil and PlayerData.get(D) == nil
	and warned("Dot's save could not be read", wmark))
E.leave(D)
E.advance(Config.AutosaveSeconds + 1)
check("… its data untouched (the try's lock only)", same(without(E.saves.Player_204, "lock"), without(before204, "lock")))

-- ── Retries ────────────────────────────────────────────────────────────────
E.saves.Player_205 = save83(1000)
local F = E.join(205, "Fay")
PlayerData.addMoney(F, 234, "Admin")
E.storeFault = failing("Player_205", 2)
from = #E.storeCalls
E.leave(F)
check("a leave save that fails: not written yet, tried again after a backoff", E.saves.Player_205.money == 1000 and callsOf("Player_205", from) == 1)
E.advance(1)
check("… the second try (1 s later) fails too", E.saves.Player_205.money == 1000 and callsOf("Player_205", from) == 2)
E.advance(2)
check("… the third (2 s later) writes it, the lock released", E.saves.Player_205.money == 1234 and E.saves.Player_205.lock == nil
	and callsOf("Player_205", from) == 3 and writesOf("Player_205", from) == 1)
E.storeFault = nil

E.saves.Player_206 = save83(600)
local G = E.join(206, "Gus")
PlayerData.addMoney(G, 100, "Admin")
E.storeFault = failing("Player_206", 1)
E.leave(G) -- (its leave save fails once: tried again in 1 s)
local G2 = joinWaiting(206, "Gus", 0.5) -- the same player back on this server at once
check("a rejoin to this server while its leave save still runs: the join waits for it", G2 == nil)
E.advance(1)
G2 = Players_byId(206)
check("… then reads what the leave save wrote, not the save from before it", G2 ~= nil and (PlayerData.get(G2) :: any).money == 700, G2 and (PlayerData.get(G2) :: any).money)
E.storeFault = failing("Player_206", 1)
PlayerData.addMoney(G2, 11, "Admin")
from = #E.storeCalls
task.spawn(PlayerData.save, G2)
check("a save that can wait, failing once: not written yet", writesOf("Player_206", from) == 0)
E.advance(1)
check("… written on its second try a second later", writesOf("Player_206", from) == 1 and E.saves.Player_206.money == 711)
E.storeFault = function(key: string): string?
	return if key == "Player_206" then "503 (test)" else nil
end
from, wmark = #E.storeCalls, #E.warnings
task.spawn(PlayerData.save, G2)
E.advance(1 + 2 + 0.1)
check("a store down for good: Tries tries, then it waits for the next save (each failure warned)", callsOf("Player_206", from) == S.Tries
	and warned(`save failed ({S.Tries}/{S.Tries})`, wmark))
E.storeFault = nil

-- 8.4 review: a leave save in an outage (every try 3 s, the first FinalTries − 1 failing: 26 s) outlasts the old fixed
-- 20 s wait; the rejoin keeps waiting while it runs, at most its worst case (Call s a try) and LeaveWait s more
local backoffs = 0
for try = 1, S.FinalTries - 1 do
	backoffs += SaveGuard.backoff(try, S.Backoff)
end
E.saves.Player_215 = save83(500)
local W = E.join(215, "Wes")
PlayerData.addMoney(W, 77, "Admin")
E.storeFault = failing("Player_215", S.FinalTries - 1)
E.storeLatency = 3
from = #E.storeCalls
E.leave(W)
local slow = S.FinalTries * 3 + backoffs
local W2 = joinWaiting(215, "Wes", slow - 1)
check(`a leave save slower than 20 s ({slow} s: FinalTries tries of 3 s, the backoffs): the rejoin still waits for it`, W2 == nil and Players_byId(215) == nil
	and E.saves.Player_215.money == 500, Players_byId(215) and (PlayerData.get(Players_byId(215)) :: any).money)
E.storeLatency = 0
E.advance(1.5)
W2 = Players_byId(215)
check("… then reads what its last try wrote", W2 ~= nil and (PlayerData.get(W2) :: any).money == 577 and writesOf("Player_215", from) >= 2, W2 and (PlayerData.get(W2) :: any).money)
E.storeFault = nil
E.leave(W2)
E.saves.Player_216 = save83(300)
local Y = E.join(216, "Yan")
PlayerData.addMoney(Y, 5, "Admin")
local most = S.LeaveWait + S.FinalTries * S.Call + backoffs
E.storeLatency = most + 30 -- (a store that never answers the leave save)
E.leave(Y)
E.storeLatency = 0
local Y2 = joinWaiting(216, "Yan", most - 1)
check(`a leave save that hangs: the rejoin waits up to the leave save's worst case and LeaveWait s more ({most} s)`, Y2 == nil and Players_byId(216) == nil)
E.advance(1.5)
Y2 = Players_byId(216)
check("… then plays the save from before it", Y2 ~= nil and (PlayerData.get(Y2) :: any).money == 300)
wmark = #E.warnings
E.advance(31)
local y2Money = (PlayerData.get(Y2) :: any).money -- (300 and what its stand earned meanwhile; the hung save holds 305)
check("… the hung leave save, answered at last, never lands over the new session's save (refused: \"held by another server\")", warned("held by another server", wmark)
	and E.saves.Player_216.money <= y2Money and y2Money < 305 and type(E.saves.Player_216.lock) == "table" and PlayerData.loaded(Y2), E.saves.Player_216.money)
E.leave(Y2)

-- ── Saves soon: purchases, milestones, pieces home ────────────────────────
E.saves.Player_207 = save83(100000)
local H = E.join(207, "Hal")
E.plotOf[H] = SandboxMap.Plots[1]
local ph = PlayerData.get(H) :: any
pastAutosave(S.Gap + 1) -- (the autosave just wrote Hal: a purchase now waits only Soon s)
from = #E.storeCalls
local bought = Upgrades.buy(H, "warehouse")
check("a purchase: the warehouse's level 3", bought and UpgradeRules.warehouseLevel(ph.sandboxUpgrades) == 3)
E.advance(S.Soon - 0.2)
check("… not saved at once", writesOf("Player_207", from) == 0)
Upgrades.buy(H, "lights")
VanPaint.buy(H, "black")
E.advance(0.4)
local saved = E.saves.Player_207
check("… one save Soon s after the first purchase, the burst's three in it (the level, the lights, the paint)", writesOf("Player_207", from) == 1
	and saved.sandboxUpgrades.warehouse == 2 and saved.sandboxUpgrades.lights == 2 and saved.vanPaint.owned.black == true and saved.money == ph.money, writesOf("Player_207", from))
check("… the warehouse's level in `rewards` too: one \"warehouse:\" key, the new level's", saved.rewards["warehouse:2"] == true and saved.rewards["warehouse:1"] == nil)
from = #E.storeCalls
Upgrades.buy(H, "danny")
E.advance(S.Soon + 0.1)
check("a purchase right after a save: not before Gap s after that write", writesOf("Player_207", from) == 0)
E.advance(S.Gap - S.Soon)
check("… then written", writesOf("Player_207", from) == 1 and E.saves.Player_207.sandboxUpgrades.danny == 1)

pastAutosave(S.Gap + 1)
from = #E.storeCalls
Book.admin(H, "fill")
E.flush()
check("the book filled: its milestones paid", ph.collectionBookPaid.found10 == true and ph.collectionBookPaid.collectibles24 == true)
E.advance(S.Soon + 0.1)
saved = E.saves.Player_207
check("… saved Soon s later (the milestones and their \"book:\" keys)", writesOf("Player_207", from) == 1 and saved.collectionBookPaid.found10 == true
	and saved.rewards["book:found10"] == true and saved.rewards["book:collectibles24"] == true and saved.rewards["book:collectibles"] == true)

pastAutosave(S.Gap + 1)
from = #E.storeCalls
local count = #ph.collection.entries
for _ = 1, 6 do
	Collection.add(H, { item = "sofa", condition = 0.8 })
end
E.advance(S.Soon + 0.1)
check("pieces brought home (a van's load): one save Soon s later with all of them", writesOf("Player_207", from) == 1
	and #E.saves.Player_207.collection.entries == count + 6)

do -- a purchase whose save lands 2 s before the autosave's round: that round skips Hal
	local every = Config.AutosaveSeconds
	local nextRound = started + every * (math.floor((E.clock - started) / every + 1e-9) + 1)
	E.advance(nextRound - E.clock - S.Soon - 2)
	from = #E.storeCalls
	Upgrades.buy(H, "lights")
	E.advance(S.Soon + 2.5)
	check("the autosave skips a player written less than Gap s ago (one write: the purchase's)", writesOf("Player_207", from) == 1)
	pastAutosave(0.5)
	check("… the next round writes them", writesOf("Player_207", from) == 2)
end

-- the request budget under its reserve
wmark, from = #E.warnings, #E.storeCalls
E.budget = S.Reserve - 1
pastAutosave(0.5)
check("the request budget under its reserve: the autosave waits (a warning)", writesOf("Player_207", from) == 0 and warned("request budget is low", wmark))
Upgrades.buy(H, "engine")
E.advance(S.Gap + S.Soon)
check("… and so does a purchase's save", writesOf("Player_207", from) == 0)
E.budget = 100
pastAutosave(0.5)
check("… the budget back: the next round writes it", writesOf("Player_207", from) == 1 and E.saves.Player_207.sandboxUpgrades.engine == 1)
E.budget = S.Reserve - 1
Upgrades.buy(H, "engine")
from = #E.storeCalls
E.leave(H)
check("… the leave save never waits for the budget", writesOf("Player_207", from) == 1 and E.saves.Player_207.sandboxUpgrades.engine == 2 and E.saves.Player_207.lock == nil)
E.budget = 100

-- ── The lock ───────────────────────────────────────────────────────────────
E.saves.Player_208 = save83(1300)
E.saves.Player_208.lock = { job = "another-server", at = E.now, session = "theirs", seq = 4 }
local I = joinWaiting(208, "Ike", 3)
check("another server holds the save (its lock fresh): the join waits", I == nil)
E.saves.Player_208.money = 1350 -- (its leave save lands: the last money, the lock released)
E.saves.Player_208.lock = nil
E.advance(2.1)
I = Players_byId(208)
check("… once released: loaded, with that server's last money", I ~= nil and (PlayerData.get(I) :: any).money == 1350)
local lockI = E.saves.Player_208.lock
check("… locked to this server and this session", type(lockI) == "table" and lockI.job == "test-server" and type(lockI.session) == "string" and lockI.seq == 0)
-- another server takes it over (it waited SaveLockWait and forced it): this one never writes it again
E.saves.Player_208.lock = { job = "another-server", at = E.now, session = "theirs", seq = 0 }
E.saves.Player_208.money = 99999
PlayerData.addMoney(I, 5, "Admin")
wmark = #E.warnings
check("a save taken over by another server: never written from here", PlayerData.save(I) == false and E.saves.Player_208.money == 99999
	and not PlayerData.loaded(I) and warned("held by another server", wmark))
E.leave(I)
check("… nor by the leave save", E.saves.Player_208.money == 99999)

E.saves.Player_209 = save83(900)
local J = E.join(209, "Jo")
E.saves.Player_209.lock.session = "a-newer-session" -- (the same player in a newer session on this same server)
PlayerData.addMoney(J, 1, "Admin")
check("a newer session of the player on this server holds it: the older one writes nothing", PlayerData.save(J) == false and E.saves.Player_209.money == 900)
E.leave(J)

E.saves.Player_210 = save83(100)
local K = E.join(210, "Kit")
E.storeLatency = 3
PlayerData.addMoney(K, 1, "Admin") -- 101: the older snapshot
task.spawn(PlayerData.save, K)
E.storeLatency = 1
PlayerData.addMoney(K, 1, "Admin") -- 102: the newer one, landing first
task.spawn(PlayerData.save, K)
E.storeLatency = 0
E.advance(1.1)
check("two saves in flight: the newer lands first", E.saves.Player_210.money == 102)
E.advance(2)
check("… the older one, landing after it, writes nothing", E.saves.Player_210.money == 102)
E.leave(K)

-- ── Garbage in a save is cleaned ───────────────────────────────────────────
local junk: { any } = {}
for i = 1, 5000 do
	junk[i] = if i % 2 == 0 then { uid = `x-{i}`, item = "sofa", variant = 1e9, condition = "mint", stand = -1, got = -5, name = string.rep("n", 500) } else "junk"
end
E.saves.Player_211 = {
	money = -500, xp = "lots", deliveries = 1e300, tutorial = "yes",
	collectionKept = true, collection = { entries = junk, nextUid = "z" },
	collectionBookKept = true, collectionBook = { sofa = { n = -3, best = 5 }, tv = { n = 1e12, best = -1 }, nope = { n = 1 }, bed = "x" },
	collectionBookPaid = { found10 = "yes", nope = true, legendary = true },
	sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = { warehouse = 99, lights = -4, engine = "max", danny = 2.7, junk = 5 },
	sandboxTasksKept = true, sandboxTasks = { day = -1, week = "x", daily = "y" },
	marketKept = true, market = { day = 1e12, kinds = { sofa = { n = -5, sold = 1e15, at = -1 }, nope = { n = 3 } } },
	vanPaintKept = true, vanPaint = { owned = { red = true, gold = "yes", nope = true }, worn = { paint = "black", livery = 5 } },
	sandboxOnboardingKept = true, sandboxOnboarding = -7,
	rewards = { ["book:found20"] = true, ["book:nope"] = true, x = "y" },
}
local L = E.join(211, "Lou")
local pl = PlayerData.get(L) :: any
check("garbage: loaded, not kicked", pl ~= nil and PlayerData.loaded(L) and L.kicked == nil)
check("… the money never negative ($0), the counters whole and capped", pl.money == 0 and pl.xp == 0 and pl.deliveries == 2 ^ 50)
local fine = #pl.collection.entries <= Config.Collection.MaxStock
for _, entry in pl.collection.entries do
	fine = fine and entry.condition >= 0 and entry.condition <= 1 and entry.variant >= 1 and entry.variant <= 99 and entry.stand == nil and entry.got >= 0 and #entry.name <= 60
end
check("… 5000 pieces: MaxStock at most, each mended (condition 0 … 1, variant, no stand -1, got, name)", fine and #pl.collection.entries == Config.Collection.MaxStock and pl.collection.nextUid >= 1)
check("… the book: only its pieces, counts 1 … MaxCount, best 0 … 1 (the sofa: its -3 dropped, then filled from the 300 sofas in stock)", pl.collectionBook.nope == nil
	and pl.collectionBook.bed == nil and pl.collectionBook.tv.n == Config.CollectionBook.MaxCount and pl.collectionBook.tv.best == 0
	and pl.collectionBook.sofa.n == Config.Collection.MaxStock and pl.collectionBook.sofa.best == 0)
check("… the milestones: only `true` and known (+ the \"book:\" keys of rewards)", same(pl.collectionBookPaid, { legendary = true, found20 = true }))
check("… the upgrades clamped (the warehouse at its top, junk dropped)", UpgradeRules.warehouseLevel(pl.sandboxUpgrades) == #Config.Warehouse.Levels
	and pl.sandboxUpgrades.lights == nil and pl.sandboxUpgrades.engine == nil and pl.sandboxUpgrades.danny == 2 and pl.sandboxUpgrades.junk == nil)
check("… the tasks: none (started fresh), the onboarding 0", pl.sandboxTasks == nil and pl.sandboxOnboarding == 0)
check("… the market: whole, capped, known kinds only", pl.market.kinds.nope == nil and (pl.market.kinds.sofa == nil or (pl.market.kinds.sofa.n >= 0 and pl.market.kinds.sofa.at >= 0)))
check("… the paint: only real purchases, the worn ones owned", same(pl.vanPaint.owned, { red = true }) and pl.vanPaint.worn.paint == PaintRules.empty().worn.paint)
local first = deepCopy(pl)
E.leave(L)
local L2 = E.join(211, "Lou")
local pl2 = PlayerData.get(L2) :: any
local stable = true
for _, field in { "money", "collection", "collectionBook", "collectionBookPaid", "sandboxUpgrades", "sandboxTasks", "market", "vanPaint", "sandboxOnboarding" } do
	stable = stable and same(pl2[field], first[field])
end
check("… saved and loaded again: the same money and sandbox fields (cleaning is stable)", stable)

-- NaN and ±inf in a live profile (a bug elsewhere): mended on the way, the money the stored one
PlayerData.addMoney(L2, 300, "Admin")
PlayerData.save(L2)
local stored = E.saves.Player_211.money
pl2.money = 0 / 0
pl2.collection.entries[1].condition = 0 / 0
pl2.market.kinds.sofa = { n = 1, at = math.huge, sold = 1 }
wmark, from = #E.warnings, #E.storeCalls
check("a NaN money, a NaN condition, an ∞ time: the save still written (no value a DataStore refuses)", PlayerData.save(L2) and writesOf("Player_211", from) == 1)
check("… the warning names them", warned("save.money: NaN", wmark) and warned("save.collection.entries[1].condition: NaN", wmark) and warned("save.market.kinds.sofa.at", wmark))
check("… the money: the stored one, in the save and in the game (never NaN)", E.saves.Player_211.money == stored and pl2.money == stored)
check("… the condition 0, the time 2^53 (the next load clamps it)", E.saves.Player_211.collection.entries[1].condition == 0 and E.saves.Player_211.market.kinds.sofa.at == 2 ^ 53)
pl2.money = -50
PlayerData.save(L2)
check("a negative money: the stored one again", E.saves.Player_211.money == stored and pl2.money == stored)
local moneyNow = pl2.money
check("the API never makes the money negative or NaN (spend NaN, -5, ∞, too much; add ∞, -5)", not PlayerData.spend(L2, 0 / 0) and not PlayerData.spend(L2, -5)
	and not PlayerData.spend(L2, math.huge) and not PlayerData.spend(L2, moneyNow + 1) and pl2.money == moneyNow)
PlayerData.addMoney(L2, math.huge)
PlayerData.addMoney(L2, -5)
check("… the money unchanged", pl2.money == moneyNow)
E.leave(L2)

-- ── Unknown keys ───────────────────────────────────────────────────────────
local future = save83(5000)
future.dannyHire = { hired = true, at = 77 } -- (fields a newer server writes)
future.dannyHireKept = true
future.badges = { first = 3 }
future.bike = "old-bike" -- (keys this version knows: its own value, never the old one)
future.title = "Boss"
future.rewards = { ["visit:sofa"] = true, ["warehouse:1"] = true }
future.sandboxMoves, future.sandboxMovesKept = 4, true -- (a field this version knows: the badges' moves)
E.saves.Player_212 = future
local M = E.join(212, "Max")
E.plotOf[M] = SandboxMap.Plots[2]
PlayerData.addMoney(M, 1, "Admin")
PlayerData.save(M)
local m1 = E.saves.Player_212
check("a newer server's keys: written back as they were", same(m1.dannyHire, future.dannyHire) and m1.dannyHireKept == true and same(m1.badges, future.badges))
check("… the keys this version knows are its own (bike, title: the profile's nil, not the old save's; the badges' moves read and written)", m1.bike == nil and m1.title == nil
	and m1.money == 5001 and m1.sandboxMoves == 4 and m1.sandboxMovesKept == true)
check("… the newer server's `rewards` keys kept too, the level's \"warehouse:\" key this one's", m1.rewards["visit:sofa"] == true and m1.rewards["warehouse:1"] == true)
PlayerData.addMoney(M, Config.SandboxUpgrades.List.warehouse.prices[2], "Admin") -- (8.3 economy: the Storehouse's price)
from = #E.storeCalls
Upgrades.buy(M, "warehouse")
E.advance(S.Gap + 1)
local m2 = E.saves.Player_212
check("… a purchase's save soon: the unknown keys still there, one \"warehouse:\" key (the new level)", writesOf("Player_212", from) == 1 and same(m2.dannyHire, future.dannyHire)
	and m2.rewards["warehouse:2"] == true and m2.rewards["warehouse:1"] == nil and m2.rewards["visit:sofa"] == true)
E.leave(M)
check("… the leave save keeps them, the lock released (never kept from the loaded save)", same(E.saves.Player_212.badges, future.badges) and E.saves.Player_212.lock == nil)
local M2 = E.join(212, "Max")
E.leave(M2)
check("… a second round trip: still there", same(E.saves.Player_212.dannyHire, future.dannyHire) and E.saves.Player_212.dannyHireKept == true)
-- a save that went through an older (8.2) server written without these keys: the level comes back from "warehouse:"
local old = deepCopy(E.saves.Player_212)
old.warehouseLevelKept, old.vanPaint, old.vanPaintKept, old.market, old.marketKept = nil, nil, nil, nil, nil
old.sandboxUpgrades.warehouse = nil
E.saves.Player_212 = old
local M3 = E.join(212, "Max")
check("… through an older server (its level dropped, \"warehouse:2\" kept): the level back (3)", UpgradeRules.warehouseLevel((PlayerData.get(M3) :: any).sandboxUpgrades) == 3)
PlayerData.resetSave(M3)
check("RESET MY SAVE: a fresh start drops the newer server's keys too", E.saves.Player_212.dannyHire == nil and E.saves.Player_212.badges == nil)
E.leave(M3)
E.saves.Player_213 = { lock = { job = "another-server", at = 0 } } -- (a lock-only record of a new player, its lock stale)
local N = E.join(213, "Ned")
E.leave(N)
check("a lock-only record: no key kept from it but its own (a new player's save)", E.saves.Player_213.money == Config.Sandbox.StartMoney and E.saves.Player_213.lock == nil)

-- ── 8.4 review: through an older (8.2) server, the paint and the moves come back from `rewards` ───────────
local paintSave = save83(2000)
paintSave.vanPaint = { owned = { red = true, racing = true }, worn = { paint = "red", livery = "racing" } }
paintSave.sandboxMovesKept, paintSave.sandboxMoves = true, 12
E.saves.Player_217 = paintSave
local T = E.join(217, "Tia")
VanPaint.buy(T, "black") -- (bought and worn here: the red one stays owned)
E.leave(T)
local wrote217 = deepCopy(E.saves.Player_217)
local r = wrote217.rewards or {}
check("the save: the paint bought and worn in `rewards` too (\"paint:\", \"paintOn:\"; the stale worn one gone)", r["paint:red"] == true and r["paint:racing"] == true
	and r["paint:black"] == true and r["paintOn:black"] == true and r["paintOn:racing"] == true and r["paintOn:red"] == nil)
check("… and the moves, capped at the badges' count (\"mv:<n>\")", r[`mv:{Config.SandboxBadges.Moves}`] == true and r["mv:12"] == nil)
local through = deepCopy(wrote217) -- an 8.2 server writes it again: the fields it does not know dropped, `rewards` kept
for _, field in { "vanPaint", "vanPaintKept", "sandboxMoves", "sandboxMovesKept", "market", "marketKept" } do
	through[field] = nil
end
E.saves.Player_217 = through
local T2 = E.join(217, "Tia")
local pt = PlayerData.get(T2) :: any
check("back here: the paint rebuilt from `rewards` (owned and worn)", pt ~= nil and same(pt.vanPaint, { owned = { red = true, racing = true, black = true }, worn = { paint = "black", livery = "racing" } }))
check("… the moves: the badges' count (tenMoves holds)", pt.sandboxMoves == Config.SandboxBadges.Moves)
check("… the market's demand: lost, the empty one (not mirrored: a day's worth at most)", same(pt.market, Market.empty()))
E.leave(T2)
local again = E.saves.Player_217
check("… written again with the flags, the same paint and the same keys", again.vanPaintKept == true and same(again.vanPaint, pt.vanPaint) and again.sandboxMovesKept == true
	and again.sandboxMoves == Config.SandboxBadges.Moves and again.rewards["paint:black"] == true and again.rewards[`mv:{Config.SandboxBadges.Moves}`] == true)
local fresh = E.join(218, "Uma") -- (a new player: nothing bought, no move yet: no key)
E.leave(fresh)
local none = true
for key in E.saves.Player_218.rewards or {} do
	none = none and string.sub(key, 1, 6) ~= "paint:" and string.sub(key, 1, 8) ~= "paintOn:" and string.sub(key, 1, 3) ~= "mv:"
end
check("a new player's save: no paint key, no \"mv:\" key", none)

-- ── 8.4: the house the moving card shows, kept across servers ──────────────
-- (server/Moving.luau sets and drops profile.sandboxHouseSeed with its SB.seeds: tests/sandboxmove_runtime_test.luau)
do
	local Seeds = Config.Moving.Sandbox.Seeds
	local houseSave = save83(900)
	houseSave.sandboxHouseSeed, houseSave.sandboxHouseSeedKept = 424242, true
	E.saves.Player_219 = houseSave
	local H1 = E.join(219, "Hal")
	check("8.4 a save with the house's seed and its flag: read into the profile", (PlayerData.get(H1) :: any).sandboxHouseSeed == 424242)
	E.leave(H1)
	check("… the leave save writes it back with its flag", E.saves.Player_219.sandboxHouseSeed == 424242 and E.saves.Player_219.sandboxHouseSeedKept == true)
	local H2 = E.join(219, "Hal") -- (another server: a fresh profile from the stored save)
	local ph = PlayerData.get(H2) :: any
	check("… joining another server: the same seed (the same house)", ph.sandboxHouseSeed == 424242)
	ph.sandboxHouseSeed = nil -- (a trip home spent it: Moving drops it)
	E.leave(H2)
	check("… dropped: the save written without it (its flag still on)", E.saves.Player_219.sandboxHouseSeed == nil and E.saves.Player_219.sandboxHouseSeedKept == true)
	local H3 = E.join(219, "Hal")
	check("… the next server: none (its card rolls a new house)", (PlayerData.get(H3) :: any).sandboxHouseSeed == nil)
	local ph3 = PlayerData.get(H3) :: any
	ph3.sandboxHouseSeed = Seeds -- (a new one rolled: the top of the range)
	PlayerData.save(H3)
	check("… a new one rolled is written by the next save", E.saves.Player_219.sandboxHouseSeed == Seeds)
	E.leave(H3)
	-- only a whole number in the seeds' range, only from a real save written with its flag
	-- (±∞ and NaN: no DataStore keeps them, SaveGuard writes ±2^53 and 0: too big, and 0, both caught here)
	local bad = { 0, -5, 1.5, Seeds + 1, 2 ^ 53, -(2 ^ 53), "424242", true, { 424242 } }
	local kept = {}
	for index, value in bad do
		local junkSave = save83(100)
		junkSave.sandboxHouseSeed, junkSave.sandboxHouseSeedKept = value, true
		E.saves.Player_220 = junkSave
		local J = E.join(220, "Jo")
		local pj = PlayerData.get(J) :: any
		if pj == nil or pj.sandboxHouseSeed ~= nil then
			table.insert(kept, `{index}: {tostring(value)}`)
		end
		E.leave(J)
	end
	check("8.4 a seed that is no whole number 1 … Config.Moving.Sandbox.Seeds (0, negative, a fraction, too big, ±2^53, a string, a boolean, a table): none, loaded and not kicked",
		#kept == 0, table.concat(kept, "; "))
	local old = save83(100)
	old.sandboxHouseSeed = 424242 -- (no flag: written before 8.4)
	E.saves.Player_220 = old
	local J2 = E.join(220, "Jo")
	check("… without its flag: none", (PlayerData.get(J2) :: any).sandboxHouseSeed == nil)
	E.leave(J2)
	E.saves.Player_220 = { sandboxHouseSeed = 424242, sandboxHouseSeedKept = true, lock = { job = "another-server", at = 0 } } -- (no money: no real save)
	local J3 = E.join(220, "Jo")
	check("… a lock-only record (no money: a new player's): none", (PlayerData.get(J3) :: any).sandboxHouseSeed == nil)
	E.leave(J3)
	local fresh = E.join(221, "Kim")
	check("… a new player: none", (PlayerData.get(fresh) :: any).sandboxHouseSeed == nil)
	E.leave(fresh)
	check("… a new player's save: the flag, no seed", E.saves.Player_221.sandboxHouseSeedKept == true and E.saves.Player_221.sandboxHouseSeed == nil)
end

-- ── 8.9: which house it is (sandboxHouse) ────────────────────────────
-- (server/Moving.luau keeps it with the seed in SB.houses: tests/sandboxhouses_runtime_test.luau)
do
	local SandboxMap = require("./SandboxMap")
	local linden = SandboxMap.Houses[2].id
	local houseSave = save83(900)
	houseSave.sandboxHouseSeed, houseSave.sandboxHouseSeedKept = 424242, true
	houseSave.sandboxHouse, houseSave.sandboxHouseKept = linden, true
	E.saves.Player_232 = houseSave
	local H1 = E.join(232, "Hana")
	local p1 = PlayerData.get(H1) :: any
	check("8.9: a save with its house and the flag: read into the profile with its seed", p1.sandboxHouse == linden and p1.sandboxHouseSeed == 424242)
	E.leave(H1)
	check("… the leave save writes it back with its flag", E.saves.Player_232.sandboxHouse == linden and E.saves.Player_232.sandboxHouseKept == true)
	local H2 = E.join(232, "Hana")
	local p2 = PlayerData.get(H2) :: any
	check("… joining another server: the same house and seed", p2.sandboxHouse == linden and p2.sandboxHouseSeed == 424242)
	p2.sandboxHouseSeed = nil -- (a trip home spent it: Moving keeps the house, the one emptied last)
	E.leave(H2)
	check("… spent: the house written alone (the next card the house after it)", E.saves.Player_232.sandboxHouse == linden
		and E.saves.Player_232.sandboxHouseSeed == nil)
	local H3 = E.join(232, "Hana")
	check("… read back alone", (PlayerData.get(H3) :: any).sandboxHouse == linden and (PlayerData.get(H3) :: any).sandboxHouseSeed == nil)
	E.leave(H3)
	-- only an id SandboxMap knows, only from a real save written with its flag
	local kept = {}
	for index, value in { "nowhere", "", 5, true, { linden }, string.upper(linden), "Hlavní_n_5", "Školní_e_20" } :: { any } do
		local junkSave = save83(100)
		junkSave.sandboxHouseSeed, junkSave.sandboxHouseSeedKept = 424242, true
		junkSave.sandboxHouse, junkSave.sandboxHouseKept = value, true
		E.saves.Player_233 = junkSave
		local J = E.join(233, "Jan")
		local pj = PlayerData.get(J) :: any
		if pj == nil or pj.sandboxHouse ~= nil then
			table.insert(kept, `{index}: {tostring(value)}`)
		end
		E.leave(J)
	end
	check("8.9: a house that is no SandboxMap.Houses id (unknown, empty, a number, a boolean, a table, another spelling, 9.4: an old village house's): none, loaded and not kicked",
		#kept == 0, table.concat(kept, "; "))
	-- 9.4: an 8.9 save of a village house (gone with the countryside): no house, its seed kept (the next card takes the
	-- next free place from the farmstead on: server/Moving.luau's SB.pick)
	local village = save83(100)
	village.sandboxHouseSeed, village.sandboxHouseSeedKept = 4343, true
	village.sandboxHouse, village.sandboxHouseKept = "Hlavní_n_5", true
	E.saves.Player_233 = village
	local JV = E.join(233, "Jan")
	local pv = PlayerData.get(JV) :: any
	check("9.4: an 8.9 save of a village house (Hlavní_n_5, gone): no house, its seed kept, loaded and not kicked", pv ~= nil and pv.sandboxHouse == nil
		and pv.sandboxHouseSeed == 4343)
	E.leave(JV)
	-- the migration: a real 8.4 save (a seed with its flag, no house's flag): the farmstead's, the one house there was
	local old = save83(100)
	old.sandboxHouseSeed, old.sandboxHouseSeedKept = 4242, true
	old.sandboxHouse = linden -- (no flag: not read)
	E.saves.Player_233 = old
	local J2 = E.join(233, "Jan")
	local pj2 = PlayerData.get(J2) :: any
	check("8.9: an 8.4 save (a seed, no house's flag): the farmstead with that seed (its seed was rolled for it)", pj2.sandboxHouse == SandboxMap.House.id
		and pj2.sandboxHouseSeed == 4242)
	E.leave(J2)
	local older = save83(100) -- (no seed either: none)
	E.saves.Player_233 = older
	local J3 = E.join(233, "Jan")
	check("… an older save without a seed: none", (PlayerData.get(J3) :: any).sandboxHouse == nil)
	E.leave(J3)
	E.saves.Player_233 = { sandboxHouse = linden, sandboxHouseKept = true, sandboxHouseSeed = 7, sandboxHouseSeedKept = true, lock = { job = "another-server", at = 0 } }
	local J4 = E.join(233, "Jan")
	check("… a lock-only record (no money: a new player's): none", (PlayerData.get(J4) :: any).sandboxHouse == nil)
	E.leave(J4)
	local fresh = E.join(234, "Kai")
	check("… a new player: none; the save the flag, no house", (PlayerData.get(fresh) :: any).sandboxHouse == nil)
	E.leave(fresh)
	check("… a new player's save: the flag, no house", E.saves.Player_234.sandboxHouseKept == true and E.saves.Player_234.sandboxHouse == nil)
end

-- ── Size: the biggest realistic sandbox save ───────────────────────────────
local O = E.join(214, "Oz")
local po = PlayerData.get(O) :: any
local longest = "sofa"
for _, id in BookRules.Pieces do
	if #id > #longest then
		longest = id
	end
end
po.collection.entries = {}
for i = 1, Config.Collection.MaxStock do
	table.insert(po.collection.entries, { uid = `9876543210-{100000 + i}`, item = longest, variant = 99, condition = 0.123, name = string.rep("W", 60),
		stand = if i <= 20 then i else nil, got = 1760000000 + i })
end
po.collection.nextUid = 100000 + Config.Collection.MaxStock + 1
for _, id in BookRules.Pieces do
	po.collectionBook[id] = { n = Config.CollectionBook.MaxCount, best = 0.123 }
end
for _, milestone in Config.CollectionBook.Milestones do
	po.collectionBookPaid[milestone.id] = true
end
po.sandboxUpgrades = UpgradeRules.full()
for _, list in { PaintRules.Paints, PaintRules.Liveries } do
	for _, item in list do
		po.vanPaint.owned[item.id] = true
	end
end
local plain, rare = Market.pool()
for _, id in plain do
	po.market.kinds[id] = { n = 8, at = 1760000000, sold = 1_000_000 }
end
for _, id in rare do
	po.market.kinds[id] = { n = 8, at = 1760000000, sold = 1_000_000 }
end
po.sandboxTasks = TaskRules.fresh(O.UserId, E.now)
po.money = 2 ^ 50
PlayerData.save(O)
local _, _, bytes = SaveGuard.clean(E.saves.Player_214)
print(`(the biggest realistic sandbox save: about {bytes} bytes, {string.format("%.1f", bytes / (4 * 1024 * 1024) * 100)} % of a DataStore key's 4 MB)`)
check("the biggest realistic sandbox save (300 pieces, the whole book, every upgrade, paint and kind): far under 4 MB (< 200 kB)", bytes > 50000 and bytes < 200000, bytes)
E.leave(O)

-- ── The shutdown (BindToClose) ─────────────────────────────────────────────
local players = { E.join(221, "Pia"), E.join(222, "Quin"), E.join(223, "Rae") }
for index, player in players do
	PlayerData.addMoney(player, index * 10, "Admin")
end
E.storeLatency = 2
E.storeFault = failing("Player_222", 1)
from = #E.storeCalls
local at = E.clock
local closed: number? = nil
task.spawn(function()
	E.onClose()
	closed = E.clock
end)
check("the shutdown: every player's save started at once (in parallel)", callsOf("Player_221", from) == 1 and callsOf("Player_222", from) == 1 and callsOf("Player_223", from) == 1)
E.leave(players[1]) -- (a player removed meanwhile: its save already runs, nothing twice)
E.advance(2.1)
check("… two written 2 s later (not one after the other); the shutdown still waits for the third (its try failed)", closed == nil
	and E.saves.Player_221.money == Config.Sandbox.StartMoney + 10 and E.saves.Player_223.money == Config.Sandbox.StartMoney + 30 and E.saves.Player_221.lock == nil)
E.advance(3.5)
E.storeLatency = 0
check("… the third written on its second try; the shutdown returns once all are in", closed ~= nil and E.saves.Player_222.money == Config.Sandbox.StartMoney + 20
	and (closed :: number) - at < 6, closed and (closed :: number) - at)
check("… one write each (the leave of a player saved by the shutdown writes nothing more)", writesOf("Player_221", from) == 1 and writesOf("Player_222", from) == 1 and writesOf("Player_223", from) == 1)
E.storeFault = nil

-- a store that never answers in time: the shutdown gives up at CloseWait
local last = E.join(224, "Sol")
PlayerData.addMoney(last, 1, "Admin")
E.storeLatency = 60
at, closed = E.clock, nil
task.spawn(function()
	E.onClose()
	closed = E.clock
end)
E.advance(S.CloseWait + 1)
check("a store that never answers: the shutdown gives up at CloseWait s (Roblox gives 30)", closed ~= nil and math.abs((closed :: number) - at - S.CloseWait) <= 0.3, closed and (closed :: number) - at)
E.storeLatency = 0

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
