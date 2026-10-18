--!strict
-- 6.13, analytics: Roblox's AnalyticsService (Creator Dashboard → the experience → Analytics) with what the owner wants
-- to see now that the game is public: where new players drop off, what the economy does, and the errors. Every call
-- runs in a pcall (analytics never breaks the game); in Studio nothing is sent (one line in the Output says so, and the
-- admin panel counts what would have gone: Analytics.summary). The plan (the steps, the names, the money's reasons) is
-- shared/AnalyticsPlan.luau, the numbers Config.Analytics, the owner's guide design/analytics/NAVOD.md.
-- The game never requires this module where it plays: Analytics.start puts its hooks in PlayerData.analytics (called
-- through PlayerData.track) and PlayerData.onMoney, so a module that failed to load or start only means no analytics.
--   onboarding   8.2: AnalyticsPlan.SandboxSteps (Roblox keeps one onboarding funnel an experience; 10.6: the city's
--                Steps went with it), each once for life: Joined (the save loaded), PressedPlay (SandboxBoot's Play),
--                the rest through the "step" hook from server/SandboxAnalytics.luau. A step goes into the save
--                (profile.sandboxOnboarding, server/PlayerData.luau) only once Roblox took it: in Studio, switched off
--                or over the budget it is not marked and goes later. SessionLength's New / Veteran is by those steps.
--   economy      "Cash": every PlayerData.addMoney / spend with its reason (PlayerData.onMoney; the SKU is the item's
--                id), and the money that moves past them (the "money" hook). Kill rewards and the like are summed a
--                player and sent every BatchSeconds and when they leave.
--   custom       AnalyticsPlan.Events: DeathOnJob (SandboxBoot: the "died" hook, on a run), SessionLength (on leave),
--                ServerError and ClientError; 8.2: the moves, the grip checks and the collectibles
--                (server/SandboxAnalytics.luau: the "event" hook, with up to three fields).
--   errors       ScriptContext.Error on the server, and the ClientError remote (client/Unstuck.luau sends a script
--                error's script name and line, one every 1 / Config.Robust.Limits.ClientError s at most, which the
--                server's Net.limit checks again): a warning with the context and a count by script, ErrorsPerMinute
--                of each kind a minute. Roblox's Error Report keeps the messages.
-- A budget for the whole server (Config.Analytics.Budget) keeps it under Roblox's throttle: past it an event is
-- dropped and counted. Nothing is kept for a player who left.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
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

-- This session's onboarding: the steps reached (with the ones waiting for an earlier one) and the ones done (sent, or
-- counted where nothing is sent; one Roblox refused is done for this session and tried again in the next).
type Onboarding = { reached: number, done: number }

local joined: { [Player]: number } = {} -- os.clock() of the join (SessionLength); only players in the game
local left: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- who left: nothing is kept for them again
local seen: { [Player]: boolean } = {} -- the loaded save seen (its first PlayerData.Changed: Joined)
local onboarding: { [Player]: Onboarding } = {}
local early: { [Player]: { number } } = {} -- onboarding steps reached before the save loaded
local batches: { [Player]: { [string]: number } } = {} -- reason → the money summed (signed) since the last flush
local clientErrors: { [Player]: number } = {} -- ClientError reports this session
local Steps = Plan.SandboxSteps -- (8.2: the sandbox's funnel, in its own save field)

-- The funnel's steps reached as the save holds them (profile.sandboxOnboarding).
local function savedSteps(profile: PlayerData.Profile): number
	return profile.sandboxOnboarding
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
		local saved = savedSteps(profile)
		state = { reached = saved, done = saved }
		onboarding[player] = state
	end
	return state
end

-- The steps reached and not done yet, in order: each one sent (a step Roblox took is marked in the save); one over the
-- budget stops it (it and the ones after it go the next time).
local function logSteps(player: Player, profile: PlayerData.Profile, state: Onboarding)
	for n = 1, Plan.logged(state.reached, Steps) do
		if Plan.has(state.done, n, Steps) then
			continue
		end
		local stepName = Steps[n].name
		local result = send("onboarding", `Onboarding {n} {stepName}`, function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, n, stepName)
		end)
		if result == "dropped" then
			return
		end
		state.done = Plan.mark(state.done, n, Steps)
		if result == "sent" then
			profile.sandboxOnboarding = Plan.mark(profile.sandboxOnboarding, n, Steps) -- (8.2)
		end
	end
end

-- A step reached (by its name in AnalyticsPlan.SandboxSteps): logged with the ones that waited for it, once for life.
local function onboard(player: Player, name: string)
	local step = Plan.stepOf(name, Steps)
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
	state.reached = (Plan.reach(state.reached, step, Steps))
	logSteps(player, profile, state)
end

-- PlayerData.Changed: the save loaded (Joined, and the steps that waited), and a step that was over the budget before.
local function onChanged(player: Player)
	local profile = PlayerData.get(player)
	if not profile or not live(player) then
		return
	end
	if not joined[player] then
		joined[player] = os.clock() -- (the save loaded before this module heard of the join)
	end
	if not seen[player] then
		seen[player] = true
		onboard(player, "Joined")
		local waiting = early[player]
		early[player] = nil
		if waiting then
			for _, step in waiting do
				onboard(player, Steps[step].name)
			end
		end
	end
	local state = onboardingOf(player, profile)
	local logged = Plan.logged(state.reached, Steps)
	if logged > 0 and not Plan.has(state.done, logged, Steps) then
		logSteps(player, profile, state) -- (a step over the budget earlier)
	end
end

-- SandboxBoot's Play (a step of PLAY).
Analytics.onPlay = guard("onPlay", function(player: Player)
	onboard(player, "PressedPlay")
end)

-- A step reached elsewhere (server/SandboxAnalytics.luau's).
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

-- Money that moved (PlayerData.onMoney, or the "money" hook of a module that changed profile.money itself): `delta`
-- > 0 in, < 0 out,
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

-- ── Custom events ──────────────────────────────────────────────────────────

-- SandboxBoot: a player died (`involved`: on a run, its host or its party; the event's field "Job", as ever).
Analytics.died = guard("died", function(player: Player, involved: boolean)
	if involved then
		custom(player, "DeathOnJob", 1, Plan.fields("Job"))
	end
end)

-- One of AnalyticsPlan.Events from another module, with up to two short field values (8.2: three).
Analytics.event = guard("event", function(player: Player, name: string, value: number?, a: any?, b: any?, c: any?)
	custom(player, name, value, Plan.fields(a, b, c))
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
		local new = Plan.logged(if state then state.reached else savedSteps(profile), Steps) < #Steps -- (8.2: the sandbox's there)
		custom(player, "SessionLength", Plan.minutes(os.clock() - since), Plan.fields(if new then "New" else "Veteran"))
	end
end)

local function forget(player: Player)
	left[player] = true
	joined[player] = nil
	seen[player] = nil
	onboarding[player] = nil
	early[player] = nil
	batches[player] = nil
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
