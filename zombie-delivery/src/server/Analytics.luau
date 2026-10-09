--!strict
-- 6.13, analytics: Roblox's AnalyticsService (Creator Dashboard → the experience → Analytics) with what the owner wants
-- to see now that the game is public: where new couriers drop off, what the economy does, and the errors. Every call
-- runs in a pcall (analytics never breaks the game); in Studio nothing is sent (one line in the Output says so, and the
-- admin panel's WORLD tab counts what would have gone: Analytics.summary). The plan (the steps, the names, the money's
-- reasons) is shared/AnalyticsPlan.luau, the numbers Config.Analytics, the owner's guide design/analytics/NAVOD.md.
-- The game never requires this module where it plays: Analytics.start puts its hooks in PlayerData.analytics (called
-- through PlayerData.track) and PlayerData.onMoney, so a module that failed to load or start only means no analytics.
--   onboarding   AnalyticsPlan.Steps, each once for life: Joined (the save loaded), PressedPlay (Main.server's Play),
--                WelcomeSeen (server/Tutorial.luau), FirstJob and FirstDelivery (server/Jobs.luau: the "order" hook),
--                Level2 and FirstVehicle (seen on PlayerData.Changed), FirstMission and FirstChapter
--                (server/Missions.luau). A step goes into the save (profile.onboarding, server/PlayerData.luau) only
--                once Roblox took it: in Studio, switched off or over the budget it is not marked and goes later.
--   funnels      "Delivery", one session an order: Taken (Jobs' newOrder), PickedUp (a pick-up stop of it done: the
--                "stopDone" hook; an order loaded from the start at once), Delivered (Jobs' payOrder). A failed order
--                (failOrder, Jobs.fail) is a custom event instead: JobFailedTime / JobFailedCargo / JobGaveUp /
--                JobFailedOther, with how far it got. "Mission", one session a start: Started, Completed.
--   economy      "Cash": every PlayerData.addMoney / spend with its reason (PlayerData.onMoney; the SKU is the item's
--                id), and the money that moves past them (a property sold, a tow paid back: the "money" hook). Kill
--                rewards, fuel and tips are summed a player and sent every BatchSeconds and when they leave.
--   progression  "DriverLevel": every level completed (a level-up from 3 to 4 completes 3). "Missions": the mission's
--                place in the story is the level, its id the name: Start and Fail for the owner who started it,
--                Complete for the owner at the finish.
--   custom       AnalyticsPlan.Events: DeathOnJob (Main.server: the "died" hook), the failed orders, QueueAddAll
--                (server/JobQueue.luau), ZipRide (server/ZipLines.luau), BusRide (server/Buses.luau), ScooterRental
--                (server/Rental.luau), StylePurchase (server/StyleWear.luau), SessionLength (on leave), ServerError
--                and ClientError.
--   errors       ScriptContext.Error on the server, and the ClientError remote (client/Unstuck.luau sends a script
--                error's script name and line, one every 1 / Config.Robust.Limits.ClientError s at most, which the
--                server's Net.limit checks again): a warning with the context and a count by script, ErrorsPerMinute
--                of each kind a minute. Roblox's Error Report keeps the messages.
-- A budget for the whole server (Config.Analytics.Budget) keeps it under Roblox's throttle: past it an event is
-- dropped and counted. Nothing is kept for a player who left.

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local MissionData = require(Shared.Missions)
local Net = require(Shared.Net)
local Plan = require(Shared.AnalyticsPlan)
local PlayerData = require(script.Parent.PlayerData)

local Tuning = Config.Analytics
local Analytics = {}

-- "on" sends; "studio" and "off" only count (the admin line says which).
local mode = if not Tuning.Enabled then "off" elseif RunService:IsStudio() then "studio" else "on"
local counts: { [string]: number } = {}
local last = "" -- the last event (the admin line)
local budget = { start = -math.huge, used = 0 } -- this minute's events (the whole server)
type Window = { start: number, used: number, quiet: number }
local errorWindows: { [string]: Window } = {} -- ServerError / ClientError: this minute's warnings, each its own
local started = false
local warned = 0

type OrderState = { player: Player, session: string, step: number, mode: string, stars: string, kind: string }
type MissionState = { id: string, session: string, campaign: string }
-- This session's onboarding: the steps reached (with the ones waiting for an earlier one) and the ones done (sent, or
-- counted where nothing is sent; one Roblox refused is done for this session and tried again in the next).
type Onboarding = { reached: number, done: number }

local joined: { [Player]: number } = {} -- os.clock() of the join (SessionLength); only players in the game
local left: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- who left: nothing is kept for them again
local levels: { [Player]: number } = {} -- the driver level last seen (nil until the save loaded)
local onboarding: { [Player]: Onboarding } = {}
local early: { [Player]: { number } } = {} -- onboarding steps reached before the save loaded
local batches: { [Player]: { [string]: number } } = {} -- reason → the money summed (signed) since the last flush
local missions: { [Player]: MissionState } = {} -- the mission a player started, until it ends
local clientErrors: { [Player]: number } = {} -- ClientError reports this session
local orders: { [any]: OrderState } = setmetatable({}, { __mode = "k" }) :: any -- Jobs' Order → its funnel
local LEVEL2 = Plan.stepOf("Level2") or 0
local VEHICLE = Plan.stepOf("FirstVehicle") or 0

-- A mission's place in the story (the Missions path's level).
local storyIndex: { [string]: number } = {}
for index, def in MissionData.List do
	storyIndex[def.id] = index
end

-- Is the player still in the game (not left: their tables are gone)?
local function live(player: Player): boolean
	return player.Parent ~= nil and not left[player]
end

-- fn in a pcall: a mistake here never reaches the game (a warning, the first few).
local function guard<A...>(name: string, fn: (A...) -> ()): (A...) -> ()
	return function(...: A...)
		local ok, err = pcall(fn :: (...any) -> ...any, ...)
		if not ok and warned < 5 then
			warned += 1
			warn(`[Analytics] {name} failed: {err}`)
		end
	end
end

-- One event within the server's budget: "sent" (Roblox took it), "counted" (Studio or switched off: counted only),
-- "dropped" (over the budget) or "failed" (the call errored).
local function send(kind: string, label: string, call: () -> ()): string
	local now = os.clock()
	if now - budget.start >= 60 then
		budget.start, budget.used = now, 0
	end
	if budget.used >= Plan.budget(#Players:GetPlayers(), Tuning.Budget) then
		counts.dropped = (counts.dropped or 0) + 1
		return "dropped"
	end
	budget.used += 1
	if mode == "on" then
		local ok, err = pcall(function()
			call()
		end)
		if not ok then
			counts.failed = (counts.failed or 0) + 1
			if counts.failed <= 3 then
				warn(`[Analytics] {label} was not sent: {err}`)
			end
			return "failed"
		end
	end
	counts[kind] = (counts[kind] or 0) + 1
	last = label
	return if mode == "on" then "sent" else "counted"
end

-- A custom event of the fixed list (AnalyticsPlan.Events), never another name.
local function custom(player: Player, name: string, value: number?, fields: { [string]: string }?, kind: string?)
	if not Plan.isEvent(name) then
		warn(`[Analytics] {name} is not in AnalyticsPlan.Events: not sent`)
		return
	end
	send(kind or "custom", name, function()
		AnalyticsService:LogCustomEvent(player, name, value, fields)
	end)
end

-- ── The onboarding funnel ──────────────────────────────────────────────────

local function onboardingOf(player: Player, profile: PlayerData.Profile): Onboarding
	local state = onboarding[player]
	if not state then
		state = { reached = profile.onboarding, done = profile.onboarding }
		onboarding[player] = state
	end
	return state
end

-- The steps reached and not done yet, in order: each one sent (a step Roblox took is marked in the save); one over the
-- budget stops it (it and the ones after it go the next time).
local function logSteps(player: Player, profile: PlayerData.Profile, state: Onboarding)
	for n = 1, Plan.logged(state.reached) do
		if Plan.has(state.done, n) then
			continue
		end
		local stepName = Plan.Steps[n].name
		local result = send("onboarding", `Onboarding {n} {stepName}`, function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, n, stepName)
		end)
		if result == "dropped" then
			return
		end
		state.done = Plan.mark(state.done, n)
		if result == "sent" then
			profile.onboarding = Plan.mark(profile.onboarding, n)
		end
	end
end

-- A step reached (by its name in AnalyticsPlan.Steps): logged with the ones that waited for it, once for life.
local function onboard(player: Player, name: string)
	local step = Plan.stepOf(name)
	if not step or not live(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		local list = early[player] or {} -- (the save is still loading: the step waits for it)
		table.insert(list, step)
		early[player] = list
		return
	end
	local state = onboardingOf(player, profile)
	state.reached = (Plan.reach(state.reached, step))
	logSteps(player, profile, state)
end

-- A bike or a car of your own (an employer's lent vehicle is not).
local function ownsVehicle(profile: PlayerData.Profile): boolean
	for id, owned in profile.cars do
		local def = if owned then Economy.findCar(id) else nil
		if def and not def.company then
			return true
		end
	end
	return false
end

-- PlayerData.Changed: the save loaded (Joined, and the steps that waited), a level-up (DriverLevel), level 2 and the
-- first vehicle, and a step that was over the budget before.
local function onChanged(player: Player)
	local profile = PlayerData.get(player)
	if not profile or not live(player) then
		return
	end
	if not joined[player] then
		joined[player] = os.clock() -- (the save loaded before this module heard of the join)
	end
	local level = Levels.levelFor(profile.xp)
	local before = levels[player]
	levels[player] = level
	if before == nil then
		onboard(player, "Joined")
		local waiting = early[player]
		early[player] = nil
		if waiting then
			for _, step in waiting do
				onboard(player, Plan.Steps[step].name)
			end
		end
	elseif level > before then
		for _, done in Plan.levelUps(before, level) do
			send("progression", `DriverLevel {done} Complete`, function()
				AnalyticsService:LogProgressionEvent(player, Plan.Paths.Level, Enum.AnalyticsProgressionType.Complete, done, `Level {done}`)
			end)
		end
	end
	local state = onboardingOf(player, profile)
	if level >= 2 and not Plan.has(state.reached, LEVEL2) then
		onboard(player, "Level2")
	end
	if not Plan.has(state.reached, VEHICLE) and ownsVehicle(profile) then
		onboard(player, "FirstVehicle")
	end
	if Plan.logged(state.reached) > 0 and not Plan.has(state.done, Plan.logged(state.reached)) then
		logSteps(player, profile, state) -- (a step over the budget earlier)
	end
end

-- Main.server's Play (a step of PLAY).
Analytics.onPlay = guard("onPlay", function(player: Player)
	onboard(player, "PressedPlay")
end)

-- A step reached elsewhere (server/Tutorial.luau: "WelcomeSeen").
Analytics.step = guard("step", function(player: Player, name: string)
	onboard(player, name)
end)

-- ── The economy ────────────────────────────────────────────────────────────

local function economy(player: Player, rule: Plan.MoneyRule, amount: number, sku: string)
	local profile = PlayerData.get(player)
	local balance = if profile then math.floor(profile.money) else 0 -- (the pump's spending can leave cents)
	local flow = if rule.flow == "Source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
	send("economy", `Economy {rule.flow} {rule.reason} {amount}`, function()
		AnalyticsService:LogEconomyEvent(player, flow, Tuning.Currency, amount, balance, rule.kind, sku, Plan.fields(rule.reason))
	end)
end

-- Money that moved (PlayerData.onMoney, or a module that changed profile.money itself): `delta` > 0 in, < 0 out,
-- the reason (AnalyticsPlan.Sources / Sinks) and the item's id. The batched reasons wait for the flush. Only for a
-- player in the game (joined, not left).
Analytics.money = guard("money", function(player: Player, delta: number, reason: string?, sku: string?)
	if not joined[player] or not live(player) then
		return
	end
	if type(delta) ~= "number" or delta ~= delta or delta == 0 or math.abs(delta) == math.huge then
		return
	end
	local rule = Plan.money(reason, delta)
	if rule.batch then
		local mine = batches[player] or {}
		batches[player] = mine
		mine[rule.reason] = (mine[rule.reason] or 0) + delta
		return
	end
	local amount = math.floor(math.abs(delta) + 0.5)
	if amount > 0 then
		economy(player, rule, amount, Plan.fieldValue(sku or rule.reason))
	end
end)

-- The batched money of a player as one event a reason (every BatchSeconds, and when they leave).
local function flush(player: Player)
	local mine = batches[player]
	if not mine then
		return
	end
	batches[player] = nil
	for reason, sum in mine do
		local amount = math.floor(math.abs(sum) + 0.5)
		if amount > 0 then
			economy(player, Plan.money(reason, sum), amount, reason)
		end
	end
end

-- ── The Delivery funnel (server/Jobs.luau) ─────────────────────────────────

local function orderStep(state: OrderState, step: number)
	local steps = Plan.Funnels.Delivery
	local fields = Plan.fields(state.mode, state.stars, state.kind)
	for _, n in Plan.funnelSteps(state.step, step, #steps) do
		state.step = n
		local player, session, name = state.player, state.session, steps[n]
		send("funnel", `Delivery {n} {name}`, function()
			AnalyticsService:LogFunnelStepEvent(player, "Delivery", session, n, name, fields)
		end)
	end
end

-- An order's kind (a field): the tutorial's, an employer's, a special job, an ordinary one from the board.
local function kindOf(offer: any): string
	local jobType = offer.jobType
	return if offer.tutorial then "Tutorial"
		elseif jobType and jobType.employer and not jobType.board then "Employer"
		elseif jobType then "Special"
		else "Board"
end

-- An order of `player`'s job (Jobs' Order: its offer, stops, state): "taken" (newOrder), "delivered" (payOrder) or
-- "failed" (failOrder; why: "time" | "cargo" | "gaveup" | nil). A mission's order has the Mission funnel instead.
Analytics.order = guard("order", function(player: Player, order: any, what: string, why: string?)
	if not live(player) then
		return
	end
	local offer = order.offer
	if what == "taken" then
		onboard(player, "FirstJob")
		if offer.mission then
			return
		end
		local state: OrderState = {
			player = player,
			session = HttpService:GenerateGUID(false),
			step = 0,
			mode = tostring(offer.mode),
			stars = tostring(offer.tier),
			kind = kindOf(offer),
		}
		orders[order] = state
		orderStep(state, 1)
		local first = offer.stops[1]
		if first and first.kind ~= "pickup" then
			orderStep(state, 2) -- (no pick-up: the vehicle starts loaded)
		end
		return
	end
	local state = orders[order]
	if what == "delivered" then
		onboard(player, "FirstDelivery")
		if state then
			orders[order] = nil
			orderStep(state, 3)
		end
	elseif what == "failed" and state then
		orders[order] = nil
		custom(player, Plan.failEvent(why), 1, Plan.fields(state.mode, state.stars, Plan.Funnels.Delivery[math.max(1, state.step)]))
	end
end)

-- A stop of the job done (Jobs' advance / freeStep: `index` into `stops`): a pick-up's orders are picked up.
Analytics.stopDone = guard("stopDone", function(_player: Player, list: { any }, stops: { any }, index: number)
	local stop = stops[index]
	if not stop or stop.kind ~= "pickup" then
		return
	end
	for _, order in list do
		local state = orders[order]
		if state and state.step < 2 and table.find(order.stops, index) then
			orderStep(state, 2)
		end
	end
end)

-- ── The missions (server/Missions.luau, server/Jobs.luau) ──────────────────

local function missionProgress(player: Player, status: Enum.AnalyticsProgressionType, label: string, id: string)
	local level = storyIndex[id]
	if level then
		send("progression", `Missions {level} {label}`, function()
			AnalyticsService:LogProgressionEvent(player, Plan.Paths.Missions, status, level, id)
		end)
	end
end

-- A mission started by `player` (its owner).
Analytics.missionStarted = guard("missionStarted", function(player: Player, id: string)
	local def = MissionData.find(id)
	if not def or not live(player) then
		return
	end
	onboard(player, "FirstMission")
	local profile = PlayerData.get(player)
	local replay = profile ~= nil and MissionData.cleared(profile.missions, id)
	local state: MissionState = { id = id, session = HttpService:GenerateGUID(false), campaign = def.campaign }
	missions[player] = state
	local fields = Plan.fields(def.campaign, if replay then "Replay" else "First")
	send("funnel", "Mission 1 Started", function()
		AnalyticsService:LogFunnelStepEvent(player, "Mission", state.session, 1, "Started", fields)
	end)
	missionProgress(player, Enum.AnalyticsProgressionType.Start, "Start", id)
end)

-- A mission done, for every player credited with it (`owner`: the one who started it; `chapterDone`: its finale
-- finished the chapter for this player).
Analytics.missionDone = guard("missionDone", function(player: Player, id: string, owner: boolean, chapterDone: boolean)
	if chapterDone then
		onboard(player, "FirstChapter")
	end
	if not owner then
		return
	end
	local state = missions[player]
	missions[player] = nil
	if state and state.id == id then
		local fields = Plan.fields(state.campaign)
		send("funnel", "Mission 2 Completed", function()
			AnalyticsService:LogFunnelStepEvent(player, "Mission", state.session, 2, "Completed", fields)
		end)
	end
	missionProgress(player, Enum.AnalyticsProgressionType.Complete, "Complete", id)
end)

-- Jobs.fail: every order still open fails with the job (a mission's: the progression's Fail).
Analytics.jobFailed = guard("jobFailed", function(player: Player, list: { any }, why: string?)
	for _, order in list do
		if order.state ~= "open" then
			continue
		end
		local id = order.offer.mission
		if type(id) == "string" then
			missions[player] = nil
			missionProgress(player, Enum.AnalyticsProgressionType.Fail, "Fail", id)
		else
			Analytics.order(player, order, "failed", why)
		end
	end
end)

-- ── Custom events ──────────────────────────────────────────────────────────

-- Main.server: a player died (`involved`: on a job or a mission, or in its crew).
Analytics.died = guard("died", function(player: Player, involved: boolean)
	if involved then
		custom(player, "DeathOnJob", 1, Plan.fields(if missions[player] then "Mission" else "Job"))
	end
end)

-- One of AnalyticsPlan.Events from another module, with up to two short field values.
Analytics.event = guard("event", function(player: Player, name: string, value: number?, a: any?, b: any?)
	custom(player, name, value, Plan.fields(a, b))
end)

-- ── Errors ─────────────────────────────────────────────────────────────────

-- A script error (ServerError, or ClientError from `who`'s device): a warning with the context and the count by script,
-- ErrorsPerMinute of each kind a minute (the rest are counted and said with the next one of that kind).
local function noteError(event: string, who: Player?, where: string, line: number, detail: string)
	local now = os.clock()
	local window = errorWindows[event]
	if not window then
		window = { start = -math.huge, used = 0, quiet = 0 }
		errorWindows[event] = window
	end
	if now - window.start >= 60 then
		if window.quiet > 0 then
			warn(`[Analytics] {window.quiet} more {event}s in the last minute were not reported`)
		end
		window.start, window.used, window.quiet = now, 0, 0
	end
	if window.used >= Tuning.ErrorsPerMinute then
		window.quiet += 1
		return
	end
	window.used += 1
	warn(`[Analytics] {event} in {where}:{line} ({detail}; {#Players:GetPlayers()} players, the server up {math.floor(time() / 60)} min)`)
	-- (a custom event belongs to a player: a server error counts on one of the players in the server)
	local player = who or Players:GetPlayers()[1]
	if player then
		custom(player, event, 1, Plan.fields(where), "error")
	end
end

local onServerError = guard("ServerError", function(message: string, source: Instance?)
	local where, line = Plan.errorWhere(message, if source then source.Name else nil)
	noteError("ServerError", nil, where, line, string.sub(tostring(message), 1, 160))
end)

-- A client script's name as the client sent it: one of the game's client or shared modules, else "Other".
local function clientScript(name: any): string
	local clean = Plan.scriptName(name)
	local scripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local client = scripts and scripts:FindFirstChild("Client")
	return if clean ~= "Unknown" and ((client and client:FindFirstChild(clean)) or Shared:FindFirstChild(clean)) then clean else "Other"
end

local onClientError = guard("ClientError", function(player: Player, name: any, line: any)
	if not live(player) or not Net.limit(player, "ClientError", Config.Robust.Limits.ClientError) then
		return
	end
	local count = (clientErrors[player] or 0) + 1
	clientErrors[player] = count
	if count > Tuning.ClientErrorsMax then
		return
	end
	local at = if type(line) == "number" and line == line then math.clamp(math.floor(line), 0, 1000000) else 0
	noteError("ClientError", player, clientScript(name), at, `{player.Name}'s device`)
end)

-- ── The session ────────────────────────────────────────────────────────────

local onLeave = guard("leave", function(player: Player)
	flush(player)
	local since = joined[player]
	local profile = PlayerData.get(player)
	if since and profile then
		local state = onboarding[player]
		local new = Plan.logged(if state then state.reached else profile.onboarding) < #Plan.Steps
		custom(player, "SessionLength", Plan.minutes(os.clock() - since), Plan.fields(if new then "New" else "Veteran"))
	end
end)

local function forget(player: Player)
	left[player] = true
	joined[player] = nil
	levels[player] = nil
	onboarding[player] = nil
	early[player] = nil
	batches[player] = nil
	missions[player] = nil
	clientErrors[player] = nil
end

-- The admin panel's line (server/Admin.luau puts it on the admins).
function Analytics.summary(): string
	return Plan.summary(mode, counts, last)
end

function Analytics.start()
	if started then
		return
	end
	started = true
	-- The hooks the game calls (PlayerData.track by name; the money's own hook): nothing else reaches this module.
	PlayerData.onMoney = Analytics.money
	PlayerData.analytics = {
		order = Analytics.order,
		stopDone = Analytics.stopDone,
		jobFailed = Analytics.jobFailed,
		missionStarted = Analytics.missionStarted,
		missionDone = Analytics.missionDone,
		onPlay = Analytics.onPlay,
		step = Analytics.step,
		died = Analytics.died,
		event = Analytics.event,
		money = Analytics.money,
	} :: any
	local changed = guard("changed", onChanged)
	PlayerData.Changed:Connect(changed)
	Players.PlayerAdded:Connect(function(player)
		joined[player] = joined[player] or os.clock()
	end)
	for _, player in Players:GetPlayers() do
		joined[player] = joined[player] or os.clock()
		changed(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		onLeave(player) -- (before PlayerData's deferred leave save: the profile is still there)
		forget(player)
	end)
	ScriptContext.Error:Connect(function(message: string, _trace: string, source: Instance?)
		onServerError(message, source)
	end)
	Net.get("ClientError").OnServerEvent:Connect(onClientError)
	task.spawn(function()
		while true do
			task.wait(Tuning.BatchSeconds)
			for player in batches do
				if player.Parent then
					pcall(flush, player)
				else
					batches[player] = nil
				end
			end
		end
	end)
	if mode == "studio" then
		print("[Analytics] off in Studio: nothing is sent. The admin panel (P → WORLD) counts what would go.")
	elseif mode == "off" then
		print("[Analytics] off (Config.Analytics.Enabled): nothing is sent.")
	end
end

return Analytics
