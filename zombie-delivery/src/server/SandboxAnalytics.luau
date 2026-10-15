--!strict
-- 8.2 SANDBOX, analytics (the owner: the sandbox goes public, so he needs to see where players drop off; the plan is
-- shared/AnalyticsPlan.luau, the owner's guide design/analytics/NAVOD.md). On a sandbox server server/Analytics.luau
-- walks the sandbox's own onboarding funnel (AnalyticsPlan.SandboxSteps in profile.sandboxOnboarding: each step once
-- for life, in order, kept in the save once Roblox took it); this module says when its steps are reached and sends the
-- sandbox's custom events. It never requires server/Analytics.luau: everything goes through PlayerData.track (its
-- "step" and "event" hooks), so without Analytics it does nothing. It only listens:
--   the steps   1 Joined and 2 PressedPlay are Analytics' own (the save loaded; SandboxBoot's Play → "onPlay");
--               3 FirstContract (Moving.onStart: the move's owner), 4 EnteredHouse (Moving.onEnterHouse: whoever came
--               in), 5 FirstPieceInVan (Moving.onLoad: the loader and the move's owner, also for Danny's), 6 FirstTripHome
--               (Moving.onTrip: the owner), 7 FirstPieceOnShow (Collection.onChanged: a piece of theirs on a stand),
--               8 FirstIncome, 9 FirstSale and 10 FirstUpgrade (the money's reasons "CollectionIncome", "CollectionSale"
--               and "Upgrade": PlayerData.onMoney, wrapped after Analytics set it). A step is told once a session.
--   the events  MoveStarted (value: the owner's moves this session; "solo" / "crew"); at the end MoveFinished (value:
--               the minutes; how it ended: AnalyticsPlan.moveHow, the trips, the pieces home: AnalyticsPlan.band) with
--               MoveFinishedValue (value: what came home is worth, $; how, the pieces, solo / crew) when pieces came
--               home, else MoveGaveUp (value: the minutes; how, how far it got: started / house / van / home, solo /
--               crew); GripCheck (Moving.onGrip: one check in Config.Analytics.GripEvery a player, a random one of each
--               window: AnalyticsPlan.sample; value: GripEvery, the outcome, lift / wobble, fragile / sturdy);
--               CollectibleFound (Collection.onChanged: a collectible, a FurnitureLooks piece with its own rarity, came
--               home into the owner's stock during their move; value: its worth at its condition, $; its rarity, its id;
--               8.7 review: not one bought from another player meanwhile: Collection.onTransferred makes its uid known).
--               UpgradeBought (server/Upgrades.luau), CollectionAdded / Displayed / Sold (server/Collection.luau) and
--               MoveDone (server/Moving.luau) stay their modules' own.
--
--   SandboxAnalytics.start()   the listeners (server/SandboxBoot.luau, right after Analytics: before any move or money)
--   SandboxAnalytics.roll      the sampling's random numbers, 0 ≤ n < 1 (math.random; a test sets its own)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Plan = require(Shared.AnalyticsPlan)
local CollectionRules = require(Shared.CollectionRules)
local PlayerData = require(script.Parent.PlayerData)

local SandboxAnalytics = {}

SandboxAnalytics.roll = math.random :: () -> number

type Facts = { [string]: any }
-- A move running, by its owner: how far it got (FAR's) and the stock's uids it has seen (a new one came home with it).
type Move = { far: string, known: { [string]: boolean } }

local FAR: { [string]: number } = { started = 0, house = 1, van = 2, home = 3 }

local moves: { [Player]: Move } = {}
local count: { [Player]: number } = {} -- moves started this session (MoveStarted's value)
local samplers: { [Player]: Plan.Sampler } = {} -- the grip checks' sampling
local told: { [Player]: { [string]: boolean } } = {} -- the funnel's steps told this session
local started = false

-- A step of AnalyticsPlan.SandboxSteps reached (once a session: Analytics keeps it once for life).
local function reach(player: Player?, name: string)
	if not player then
		return
	end
	local mine = told[player]
	if not mine then
		mine = {}
		told[player] = mine
	end
	if not mine[name] then
		mine[name] = true
		PlayerData.track("step", player, name)
	end
end

-- The owner's move got this far (never back).
local function further(owner: Player?, far: string)
	local move = if owner then moves[owner] else nil
	if move and FAR[far] > FAR[move.far] then
		move.far = far
	end
end

local function crewWord(facts: Facts): string
	return if (tonumber(facts.crew) or 1) > 1 then "crew" else "solo"
end

-- ── The moves (server/Moving.luau's listeners) ─────────────────────────────

-- The stock's uids now (what a move brings home is what is new after its start).
local function uidsOf(player: Player, Collection: any): { [string]: boolean }
	local known: { [string]: boolean } = {}
	if Collection then
		for _, entry in Collection.stock(player) do
			known[entry.uid] = true
		end
	end
	return known
end

local function onStart(owner: Player?, facts: Facts, Collection: any)
	if not owner then
		return
	end
	reach(owner, "FirstContract")
	local n = (count[owner] or 0) + 1
	count[owner] = n
	moves[owner] = { far = "started", known = uidsOf(owner, Collection) }
	PlayerData.track("event", owner, "MoveStarted", n, crewWord(facts))
end

local function onEnter(player: Player?, facts: Facts)
	reach(player, "EnteredHouse")
	further(facts.owner, "house")
end

local function onLoad(player: Player?, facts: Facts)
	reach(player, "FirstPieceInVan") -- (nil: Danny's)
	reach(facts.owner, "FirstPieceInVan")
	further(facts.owner, "van")
end

local function onTrip(owner: Player?, _facts: Facts)
	reach(owner, "FirstTripHome")
	further(owner, "home")
end

-- The end: MoveFinished and MoveFinishedValue when pieces came home, else MoveGaveUp.
local function onFinish(owner: Player?, facts: Facts)
	if not owner then
		return
	end
	local move = moves[owner]
	moves[owner] = nil
	local home = tonumber(facts.home) or 0
	local allDone = home + (tonumber(facts.lost) or 0) >= (tonumber(facts.total) or 0)
	local how = Plan.moveHow(tostring(facts.phase), facts.why, tonumber(facts.left) or 0, allDone)
	local minutes = Plan.minutes((tonumber(facts.minutes) or 0) * 60)
	if home > 0 then
		PlayerData.track("event", owner, "MoveFinished", minutes, how, Plan.band(facts.trips, 1, 6), Plan.band(home, 5, 30))
		PlayerData.track("event", owner, "MoveFinishedValue", tonumber(facts.value) or 0, how, Plan.band(home, 5, 30), crewWord(facts))
	else
		PlayerData.track("event", owner, "MoveGaveUp", minutes, how, if move then move.far else "started", crewWord(facts))
	end
end

-- A grip check's outcome: one in GripEvery a player is sent (a random one of each window).
local function onGrip(player: Player?, facts: Facts)
	if not player then
		return
	end
	local every = Config.Analytics.GripEvery
	local sampler = samplers[player]
	if not sampler then
		sampler = Plan.sampler(every, SandboxAnalytics.roll())
		samplers[player] = sampler
	end
	if Plan.sample(sampler, every, SandboxAnalytics.roll()) then
		PlayerData.track("event", player, "GripCheck", every, facts.outcome, facts.what, if facts.fragile then "fragile" else "sturdy")
	end
end

local function hookMoving()
	local Moving = require(script.Parent.Moving)
	local Collection = require(script.Parent.Collection)
	Moving.onStart(function(owner: Player?, facts: Facts)
		onStart(owner, facts, Collection)
	end)
	Moving.onEnterHouse(onEnter)
	Moving.onLoad(onLoad)
	Moving.onTrip(onTrip)
	Moving.onFinish(onFinish)
	Moving.onGrip(onGrip)
end

-- ── The warehouse (server/Collection.luau's listeners) ─────────────────────

-- A change to `player`'s collection: a piece on a stand (step 7); during their move, a new piece that is a collectible.
local function hookCollection()
	local Collection = require(script.Parent.Collection)
	Collection.onChanged(function(player: Player)
		local move = moves[player]
		local shown = false
		local housed = Collection.hasWarehouse -- (8.2 review: without a warehouse of their own nothing is on show)
		local has = housed == nil or housed(player)
		for _, entry in Collection.stock(player) do
			shown = shown or (has and entry.stand ~= nil)
			if move and not move.known[entry.uid] then
				move.known[entry.uid] = true
				local def = CollectionRules.defOf(entry.item)
				if def and def.rarity then
					local worth = math.floor(CollectionRules.valueOf(entry) * math.clamp(entry.condition, 0, 1) + 0.5)
					PlayerData.track("event", player, "CollectibleFound", worth, def.rarity, entry.item)
				end
			end
		end
		if shown then
			reach(player, "FirstPieceOnShow")
		end
	end)
	-- 8.7 review: a piece bought from another player during the buyer's move (Collection.transfer, before its
	-- onChanged) came home with no move: its uid is known already
	Collection.onTransferred(function(buyer: Player, _seller: Player, entry: any)
		local move = moves[buyer]
		if move then
			move.known[entry.uid] = true
		end
	end)
end

-- ── The money (PlayerData.onMoney, Analytics' first) ───────────────────────

local function onMoney(player: Player, delta: number, reason: string?)
	if reason == "CollectionIncome" and delta > 0 then
		reach(player, "FirstIncome")
	elseif (reason == "CollectionSale" or reason == "VisitorOffer" or reason == "PlayerSale") and delta > 0 then -- (8.3: a visitor's offer accepted too; 8.7: a piece sold to a player)
		reach(player, "FirstSale")
	elseif reason == "Upgrade" and delta < 0 then
		reach(player, "FirstUpgrade")
	end
end

local function hookMoney()
	local before = PlayerData.onMoney
	PlayerData.onMoney = function(player: Player, delta: number, reason: string?, sku: string?)
		if before then
			pcall(before, player, delta, reason, sku)
		end
		pcall(onMoney, player, delta, reason)
	end
end

-- ── Start ──────────────────────────────────────────────────────────────────

-- Each part on its own: one that fails (a module missing) leaves the others.
local function part(name: string, fn: () -> ())
	local ok, err = pcall(function()
		fn()
	end)
	if not ok then
		warn(`[SandboxAnalytics] {name}: {err}`)
	end
end

function SandboxAnalytics.start()
	if started then
		return
	end
	started = true
	part("money", hookMoney)
	part("collection", hookCollection)
	part("moves", hookMoving)
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(function() -- (after the move's own end: the owner leaving ends it)
			moves[player], count[player], samplers[player], told[player] = nil, nil, nil, nil
		end)
	end)
end

return SandboxAnalytics
