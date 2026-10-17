-- 8.2 SANDBOX, analytics on the server: the real server/Analytics.luau and server/SandboxAnalytics.luau with the real
-- server/PlayerData.luau and server/Collection.luau (AnalyticsServer.luau, SandboxAnalyticsServer.luau, PlayerDataServer.luau,
-- CollectionServer.luau through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's players, DataStore, clock
-- and Net; Roblox's AnalyticsService a recorder, server/Moving.luau a fake whose listeners the test tells (their facts as
-- Moving's SB.facts makes them; tests/sandboxmove_runtime_test.luau checks the real Moving tells them so).
--   * The sandbox's onboarding funnel (AnalyticsPlan.SandboxSteps) in place of the city's: joined and PLAY as before,
--     then the contract, the house, a piece in the van (Danny's for the owner too), the trip home, a piece on show, the
--     stands' income, a sale and an upgrade; an upgrade bought first and a sale before the show wait for the steps
--     before them; every step logged once, in order; none of the city's steps; the save keeps them (its flag) and a
--     rejoin logs nothing again, a half-way player goes on from where they were; an old sandbox save (no flag) is past
--     every step; SessionLength's New / Veteran by them; the money still reaches the economy through the wrapped hook.
--   * The moves' events: MoveStarted (the session's count, solo / crew); MoveFinished (the minutes; how, the trips, the
--     pieces' band) with MoveFinishedValue (the worth; how, the pieces, solo / crew) when pieces came home; MoveGaveUp
--     (how, how far it got) when none did; CollectibleFound for a collectible coming home during a move (its rarity, its
--     id, its worth), never an ordinary piece or one outside a move; 8.7 review: never one bought from another player
--     during the move (Collection.transfer: no move brought it).
--   * GripCheck: one check in Config.Analytics.GripEvery a player (100 checks: 10 events, one a window, each standing
--     for GripEvery), each player their own window.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before the modules load: Analytics and PlayerData read it there)
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

-- ── Roblox's AnalyticsService: a recorder ──────────────────────────────────
type Logged = { player: any, step: number?, name: string, value: any, fields: any }
local onboarding: { Logged } = {}
local custom: { Logged } = {}
local economy: { Logged } = {}
local AnalyticsService: any = {}
function AnalyticsService.LogOnboardingFunnelStepEvent(_self: any, player: any, step: number, name: string)
	table.insert(onboarding, { player = player, step = step, name = name })
end
function AnalyticsService.LogCustomEvent(_self: any, player: any, name: string, value: any, fields: any)
	table.insert(custom, { player = player, name = name, value = value, fields = fields or {} })
end
function AnalyticsService.LogEconomyEvent(_self: any, player: any, flow: any, _currency: any, amount: number, _balance: any, kind: string, sku: string, fields: any)
	table.insert(economy, { player = player, name = `{flow} {kind} {sku}`, value = amount, fields = fields })
end
function AnalyticsService.LogProgressionEvent() end
function AnalyticsService.LogFunnelStepEvent() end
local baseService = E.game.GetService
E.game.GetService = function(self: any, name: string): any
	if name == "AnalyticsService" then
		return AnalyticsService
	elseif name == "ScriptContext" then
		return { Error = E.signal() }
	elseif name == "HttpService" then
		return { GenerateGUID = function() return "guid" end }
	end
	return baseService(self, name)
end

-- ── server/Moving.luau: its listeners, told by the test ─────────────────────
local listeners: { [string]: { (any, any) -> () } } = { start = {}, enter = {}, load = {}, trip = {}, finish = {}, grip = {} }
local function register(kind: string): (fn: (any, any) -> ()) -> ()
	return function(fn)
		table.insert(listeners[kind], fn)
	end
end
E.Moving = {
	onStart = register("start"),
	onEnterHouse = register("enter"),
	onLoad = register("load"),
	onTrip = register("trip"),
	onFinish = register("finish"),
	onGrip = register("grip"),
}
local function tell(kind: string, player: any, facts: { [string]: any })
	for _, fn in listeners[kind] do
		fn(player, facts)
	end
end
-- A move's facts (Moving's SB.facts) for `owner`, with `extra` on top.
local function facts(owner: any, extra: { [string]: any }?): { [string]: any }
	local f: { [string]: any } = { owner = owner, contract = "sandbox_house", crew = 1, trips = 0, home = 0, value = 0, total = 8, out = 0, lost = 0,
		minutes = 0, left = 1200, phase = "running" }
	for key, value in extra or {} do
		f[key] = value
	end
	return f
end

local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Analytics = require("./AnalyticsServer")
local SandboxAnalytics = require("./SandboxAnalyticsServer")
local rolls = { 0.35 }
local rolled = 0
SandboxAnalytics.roll = function(): number
	rolled += 1
	return rolls[(rolled - 1) % #rolls + 1]
end
-- (server/SandboxBoot.luau's order: PlayerData, Analytics, SandboxAnalytics; the collection later)
PlayerData.start()
Analytics.start()
SandboxAnalytics.start()
Collection.start()

-- The steps logged for `player` (by number) since entry `from`.
local function steps(player: any, from: number?): { number }
	local out = {}
	for index = (from or 0) + 1, #onboarding do
		if onboarding[index].player == player then
			table.insert(out, onboarding[index].step :: number)
		end
	end
	return out
end
local function list(t: { any }): string
	local parts = {}
	for _, v in t do
		table.insert(parts, tostring(v))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end
local function same(a: { any }, b: { any }): boolean
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
-- The custom events named `name` for `player` since entry `from`.
local function events(player: any, name: string, from: number?): { Logged }
	local out = {}
	for index = (from or 0) + 1, #custom do
		local e = custom[index]
		if e.player == player and e.name == name then
			table.insert(out, e)
		end
	end
	return out
end
local function field(e: Logged?, n: number): string?
	return if e then e.fields[Plan.FieldKeys[n]] else nil
end

-- ── A new player's way through ─────────────────────────────────────────────
local ann = E.join(101, "Ann")
check("joined: the sandbox's step 1, by its name", same(steps(ann), { 1 }) and onboarding[1].name == "Joined", list(steps(ann)))
PlayerData.track("onPlay", ann)
check("PLAY: step 2 (PressedPlay)", same(steps(ann), { 1, 2 }) and onboarding[2].name == "PressedPlay")
PlayerData.track("step", ann, "WelcomeSeen")
PlayerData.track("step", ann, "FirstJob")
check("none of the city's steps on a sandbox server", same(steps(ann), { 1, 2 }))
local spent = PlayerData.spend(ann, 50, "Upgrade", "lights")
check("an upgrade bought right away: reached, it waits for the steps before it", spent and same(steps(ann), { 1, 2 }))
local sink = economy[#economy]
check("…the money still reaches the economy (Analytics' hook, wrapped)", sink ~= nil and sink.player == ann and sink.name == "Sink Shop lights" and sink.value == 50, sink and sink.name)

tell("start", ann, facts(ann))
check("the move started: step 3 (FirstContract)", same(steps(ann), { 1, 2, 3 }) and onboarding[#onboarding].name == "FirstContract")
local started = events(ann, "MoveStarted")
check("MoveStarted: the session's first, solo", #started == 1 and started[1].value == 1 and field(started[1], 1) == "solo", #started)
tell("enter", ann, facts(ann))
check("into the house: step 4 (EnteredHouse)", same(steps(ann), { 1, 2, 3, 4 }))
tell("load", nil, facts(ann, { item = "lamp", out = 1 }))
check("Danny loaded a piece into her van: step 5 for the owner (FirstPieceInVan)", same(steps(ann), { 1, 2, 3, 4, 5 }) and onboarding[#onboarding].name == "FirstPieceInVan")
tell("load", ann, facts(ann, { item = "tv", out = 2 }))
check("…her own load: nothing again", #steps(ann) == 5)

-- the trip home: the pieces into her stock (a collectible and an ordinary one)
local before = #custom
local record = Collection.add(ann, { item = "gold_record", condition = 0.9, name = "Gold Record" }) :: string
local tv = Collection.add(ann, { item = "tv", condition = 1 }) :: string
local found = events(ann, "CollectibleFound", before)
check("a collectible came home during the move: CollectibleFound (its rarity, its id, its worth at its condition)", #found == 1 and field(found[1], 1) == "rare"
	and field(found[1], 2) == "gold_record" and found[1].value == math.floor(1600 * 0.9 + 0.5), #found)
-- 8.7 review: a collectible bought from another player meanwhile (a deal: Collection.transfer) came home with no move
local seller = E.join(102, "Bob")
local jukebox = Collection.add(seller, { item = "jukebox", condition = 1 }) :: string
Collection.display(seller, jukebox, 1)
before = #custom
local bought = Collection.transfer(seller, ann, jukebox, 1, 1, 0)
E.flush()
check("8.7 review: a collectible bought from a player during her move: no CollectibleFound (it is in her stock all the same)", bought ~= nil and bought.item == "jukebox"
	and #events(ann, "CollectibleFound", before) == 0, #events(ann, "CollectibleFound", before))
tell("trip", ann, facts(ann, { trips = 1, pieces = 2, stored = 2, home = 2, value = 1740 }))
check("the trip home: step 6 (FirstTripHome)", same(steps(ann), { 1, 2, 3, 4, 5, 6 }))
before = #custom
tell("finish", ann, facts(ann, { phase = "done", event = "deliver", why = "Finished: what came home is in your warehouse", trips = 1, home = 2, value = 1740,
	minutes = 12.34, left = 460 }))
local finished = events(ann, "MoveFinished", before)
local haul = events(ann, "MoveFinishedValue", before)
check("FINISH: MoveFinished (12.3 minutes; finish, 1 trip, 0-4 pieces)", #finished == 1 and finished[1].value == 12.3 and field(finished[1], 1) == "finish"
	and field(finished[1], 2) == "1" and field(finished[1], 3) == "0-4", finished[1] and `{finished[1].value} {field(finished[1], 1)} {field(finished[1], 2)} {field(finished[1], 3)}`)
check("…MoveFinishedValue ($1740; finish, 0-4 pieces, solo), no MoveGaveUp", #haul == 1 and haul[1].value == 1740 and field(haul[1], 1) == "finish"
	and field(haul[1], 2) == "0-4" and field(haul[1], 3) == "solo" and #events(ann, "MoveGaveUp", before) == 0)
before = #custom
Collection.add(ann, { item = "antique_vase", condition = 1 })
check("a collectible outside a move (the admin's fill): no CollectibleFound", #events(ann, "CollectibleFound", before) == 0)

-- the warehouse: a sale before the show waits; on show; the income; the sale and the upgrade that waited
check("(not on show yet)", #steps(ann) == 6)
local sold = Collection.sell(ann, tv)
check("a sale before anything is on show: reached, it waits", sold ~= nil and #steps(ann) == 6)
local shown = Collection.display(ann, record, 1)
check("a piece on show: step 7 (FirstPieceOnShow)", shown and same(steps(ann), { 1, 2, 3, 4, 5, 6, 7 }) and onboarding[#onboarding].name == "FirstPieceOnShow")
E.advance(Config.Collection.Tick + 0.5)
check("the stands paid: step 8 with the sale and the upgrade that waited (9, 10), in order", same(steps(ann), { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
	and onboarding[#onboarding].name == "FirstUpgrade", list(steps(ann)))
local names = {}
for _, entry in onboarding do
	if entry.player == ann then
		table.insert(names, entry.name)
	end
end
local wanted = {}
for _, step in Plan.SandboxSteps do
	table.insert(wanted, step.name)
end
check("every step once, by the plan's names", same(names, wanted), table.concat(names, " "))
local logged = #onboarding
PlayerData.track("onPlay", ann)
tell("start", ann, facts(ann))
tell("enter", ann, facts(ann))
tell("load", ann, facts(ann))
tell("trip", ann, facts(ann, { trips = 1, home = 1 }))
tell("finish", ann, facts(ann, { phase = "cancelled", why = "You called it off" }))
Collection.sell(ann, record)
PlayerData.spend(ann, 10, "Upgrade", "stands")
E.advance(Config.Collection.Tick * 2)
check("everything again: no step logged twice", #onboarding == logged, #onboarding - logged)
check("MoveStarted counts the session's moves (the second: 2)", #events(ann, "MoveStarted") == 2 and events(ann, "MoveStarted")[2].value == 2)
local profile = PlayerData.get(ann) :: any
check("the profile holds every sandbox step (10.6: no city funnel field)", profile.sandboxOnboarding == Plan.allOf(Plan.SandboxSteps) and profile.onboarding == nil,
	`{profile.sandboxOnboarding} {profile.onboarding}`)

-- ── Leaving and coming back ────────────────────────────────────────────────
before = #custom
E.leave(ann)
local saved = E.saves.Player_101
check("the save keeps the steps with their flag", saved ~= nil and saved.sandboxOnboarding == 1023 and saved[Plan.SandboxFlag] == true, saved and saved.sandboxOnboarding)
local session = events(ann, "SessionLength", before)
check("SessionLength: Veteran (every sandbox step walked)", #session == 1 and field(session[1], 1) == "Veteran")
logged = #onboarding
local ann2 = E.join(101, "Ann")
PlayerData.track("onPlay", ann2)
tell("start", ann2, facts(ann2))
tell("enter", ann2, facts(ann2))
check("a rejoin: nothing logged again (not even joined or PLAY)", #onboarding == logged and #steps(ann2) == 0, #onboarding - logged)
check("…MoveStarted from 1 again (a new session)", #events(ann2, "MoveStarted") == 1 and events(ann2, "MoveStarted")[1].value == 1)

-- half-way: Ben leaves after the house and comes back
local ben = E.join(202, "Ben")
PlayerData.track("onPlay", ben)
tell("start", ben, facts(ben))
tell("enter", ben, facts(ben))
check("Ben: steps 1 – 4", same(steps(ben), { 1, 2, 3, 4 }))
before = #custom
tell("finish", ben, facts(ben, { phase = "cancelled", why = "You called it off", minutes = 3.04 }))
local gaveUp = events(ben, "MoveGaveUp", before)
check("GIVE UP with nothing home: MoveGaveUp (3 minutes; giveup, got as far as the house, solo), no MoveFinished", #gaveUp == 1 and gaveUp[1].value == 3
	and field(gaveUp[1], 1) == "giveup" and field(gaveUp[1], 2) == "house" and field(gaveUp[1], 3) == "solo" and #events(ben, "MoveFinished", before) == 0,
	gaveUp[1] and `{gaveUp[1].value} {field(gaveUp[1], 1)} {field(gaveUp[1], 2)}`)
before = #custom
E.leave(ben)
check("SessionLength: New (still on the way)", field(events(ben, "SessionLength", before)[1], 1) == "New")
check("…his save: steps 1 – 4 (15)", E.saves.Player_202.sandboxOnboarding == 15 and E.saves.Player_202[Plan.SandboxFlag] == true, E.saves.Player_202.sandboxOnboarding)
logged = #onboarding
local ben2 = E.join(202, "Ben")
PlayerData.track("onPlay", ben2)
tell("start", ben2, facts(ben2))
tell("enter", ben2, facts(ben2))
check("Ben back: steps 1 – 4 not again", #onboarding == logged)
tell("load", ben2, facts(ben2, { out = 1 }))
check("…his first piece in the van: step 5, only it", same(steps(ben2), { 5 }), list(steps(ben2)))
before = #custom
tell("finish", ben2, facts(ben2, { phase = "failed", event = "lose", why = "Time's up: nothing reached your warehouse", left = -1, minutes = 20 }))
local timeUp = events(ben2, "MoveGaveUp", before)
check("the clock ran out with nothing home: MoveGaveUp (time, got as far as the van)", #timeUp == 1 and field(timeUp[1], 1) == "time" and field(timeUp[1], 2) == "van")
-- a crew move ended by the owner leaving after the trips home
tell("start", ben2, facts(ben2, { crew = 2 }))
check("MoveStarted with a crew: crew", field(events(ben2, "MoveStarted")[2], 1) == "crew")
before = #custom
tell("finish", ben2, facts(ben2, { phase = "done", event = "deliver", why = "Ben left the game: what came home is in their warehouse", crew = 2, trips = 7,
	home = 31, total = 40, value = 9000, minutes = 18 }))
local leftEnd = events(ben2, "MoveFinished", before)
check("the owner left after 7 trips, 31 pieces: MoveFinished (left, 6plus, 30plus) and the value's crew", #leftEnd == 1 and field(leftEnd[1], 1) == "left"
	and field(leftEnd[1], 2) == "6plus" and field(leftEnd[1], 3) == "30plus" and field(events(ben2, "MoveFinishedValue", before)[1], 3) == "crew")

-- an old sandbox save (8.0 / 8.1: no flag) is past every step
E.saves.Player_303 = { money = 900, tutorial = true, vanOnly = true, collectionKept = true, collection = { entries = {}, nextUid = 1 } }
logged = #onboarding
local cid = E.join(303, "Cid")
PlayerData.track("onPlay", cid)
tell("start", cid, facts(cid))
tell("enter", cid, facts(cid))
check("an old sandbox save (no flag): no step at all (a player who knows the sandbox)", #onboarding == logged and (PlayerData.get(cid) :: any).sandboxOnboarding == 1023)

-- ── The grip checks: one in GripEvery a player ─────────────────────────────
local every = Config.Analytics.GripEvery
rolls = { 0.37, 0.05, 0.91, 0.5, 0.0, 0.999, 0.2 }
rolled = 0
before = #custom
local sentAt = {}
for n = 1, 100 do
	local had = #events(ann2, "GripCheck", before)
	tell("grip", ann2, { what = if n % 3 == 0 then "lift" else "wobble", outcome = if n % 3 == 0 then "balanced" else "steady", item = "lamp", fragile = n % 2 == 0 })
	if #events(ann2, "GripCheck", before) > had then
		table.insert(sentAt, n)
	end
end
local grips = events(ann2, "GripCheck", before)
local windows, oneEach = {}, true
for _, n in sentAt do
	local w = (n - 1) // every + 1
	windows[w] = (windows[w] or 0) + 1
end
for w = 1, 100 // every do
	oneEach = oneEach and windows[w] == 1
end
check("100 grip checks: 10 GripCheck events, one in each window of 10", #grips == 10 and oneEach, list(sentAt))
local fine = true
for index, e in grips do
	local n = sentAt[index]
	local lift = n % 3 == 0
	fine = fine and e.value == every and field(e, 1) == (if lift then "balanced" else "steady") and field(e, 2) == (if lift then "lift" else "wobble")
		and field(e, 3) == (if n % 2 == 0 then "fragile" else "sturdy")
end
check("…each the check's own outcome, lift or wobble, fragile or sturdy; its value GripEvery (the checks it stands for)", fine)
rolls = { 0 }
before = #custom
tell("grip", ben2, { what = "wobble", outcome = "drop", item = "tv", fragile = true })
local first = events(ben2, "GripCheck", before)
check("another player's own window (a roll of 0: his first check)", #first == 1 and field(first[1], 1) == "drop")
check("no warnings", #E.warnings == 0, table.concat(E.warnings, " | "))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
