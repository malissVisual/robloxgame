--!strict
-- 6.14, the GOLDEN ORDERS and the REGULARS' ORDERS on the server (shared/SpecialOrders.luau has the rules,
-- Config.Jobs.Golden and Config.Regulars.Order the numbers; the offers are server/Jobs.luau's, made and placed through
-- Jobs.specialApi). One code path for both kinds: an ordinary board offer with a `specialOrder` (its Spec).
--   * Every second, for every player: a golden or a regular's order on their board whose clock ran out leaves it (the
--     board is sent again, "The GOLDEN ORDER left your board."). NEXT UP drops its own the same way
--     (server/JobQueue.luau), Jobs' accept refuses one a second late.
--   * Every Golden.Every s a courier from Golden.Level on (the tutorial done, not helping in somebody else's crew) rolls
--     Golden.Chance, unless one is going already (on the board, open on the run, waiting in NEXT UP): a GOLDEN ORDER
--     comes (SpecialOrders.goldenPlan: the transport they use, one of their hardest car tiers; a walk when nothing of
--     that kind fits now) at Golden.Pay × its pay, its danger in its Spec (a car run's waves and bandits, a light run's
--     strays: Jobs.dangerOf, only while it is open), placed on the board and sent: the client sees it in the board and
--     says it (client/SpecialOrderUi.luau: a toast and a sting).
--   * Every Order.Every s a courier who is a regular at Order.Tier or better somewhere (shared/Regulars.luau orderable)
--     rolls Order.Chance, one at a time too: a REGULAR'S ORDER from one of those businesses, in turn at random
--     (SpecialOrders.regularPlans: their transport first, the hardest car tier the business serves), Order.Pay × its pay.
--   * Analytics (shared/AnalyticsPlan.luau): GoldenOffered and GoldenExpired here; GoldenTaken and GoldenDone come from
--     the order's funnel (server/Analytics.luau).
--   * SpecialOrders.force (the admin panel, server/Admin.luau): one now, whatever the roll and the level (the one of that
--     kind on the board goes first).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.SpecialOrders)
local RegularRules = require(Shared.Regulars)
local Jobs = require(script.Parent.Jobs)
local JobQueue = require(script.Parent.JobQueue)
local PlayerData = require(script.Parent.PlayerData)
local Crew = require(script.Parent.Crew)

local SpecialOrders = {}

local api: any = Jobs.specialApi
local notice = Net.get("Notice")
local rng = Random.new()
local KINDS = { "golden", "regular" }
local PEOPLE = { kid = true, patient = true, survivor = true, horse = true } -- (never on foot or by bike)
local nextRoll: { [Player]: { [string]: number } } = {}
local lastWarn = -math.huge

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function nameOf(kind: string, spec: any): string
	if kind == "golden" then
		return "The GOLDEN ORDER"
	end
	return `The REGULAR'S ORDER from {RegularRules.nameOf(tostring(spec.business))}`
end

-- Is one of this kind going for the player: on their board (its clock running), open on their run, in NEXT UP?
local function going(player: Player, kind: string): boolean
	local now = serverNow()
	local board = api.board(player)
	for _, offer in (if board then board.list else {}) :: { any } do
		local spec = offer.specialOrder
		if spec and spec.kind == kind and not Rules.expired(spec, now) then
			return true
		end
	end
	local job = api.job(player)
	for _, order in (if job then job.orders else {}) :: { any } do
		local spec = order.offer.specialOrder
		if order.state == "open" and spec and spec.kind == kind then
			return true
		end
	end
	return JobQueue.holds(player, kind)
end

-- The special orders whose clock ran out leave the board (`kind` and `all`: every one of that kind, said nothing:
-- the admin's new one takes its place). The board is sent again when one went. How many went.
local function takeOff(player: Player, kind: string?, all: boolean): number
	local board = api.board(player)
	if not board then
		return 0
	end
	local now = serverNow()
	local gone = 0
	for index = #board.list, 1, -1 do
		local offer = board.list[index]
		local spec = offer.specialOrder
		if spec and (kind == nil or spec.kind == kind) and (all or Rules.expired(spec, now)) then
			table.remove(board.list, index)
			gone += 1
			if not all then
				notice:FireClient(player, `{nameOf(spec.kind, spec)} left your board.`)
				if spec.kind == "golden" then
					PlayerData.track("event", player, "GoldenExpired", offer.tier, offer.mode, "board") -- 6.14
				end
			end
		end
	end
	if gone > 0 then
		api.sendBoard(player, board)
	end
	return gone
end

-- A regular's order's businesses' ordinary deliveries as the plan sees them (their tiers, light or not).
local function infoOf(only: { [string]: boolean }): { Rules.BusinessInfo }
	local out: { Rules.BusinessInfo } = {}
	for _, def in Config.Jobs.Businesses do
		if only[def.id] then
			table.insert(out, { tiers = def.tiers, light = Config.Cargo.LightLooks[def.look] == true and not PEOPLE[def.kind] })
		end
	end
	return out
end

-- A golden or a regular's order made and placed on the player's board: true and what it is, or false and why not.
local function offer(player: Player, kind: string): (boolean, string)
	local reach = api.reach(player)
	local made: any = nil
	local business: string? = nil
	if kind == "golden" then
		local mode, tier = Rules.goldenPlan(reach, rng:NextNumber())
		made = api.make(player, mode, tier, nil)
		if not made and mode ~= "foot" then
			made = api.make(player, "foot", 1, nil) -- (nothing of that kind near you now: a walk)
		end
	else
		local profile = PlayerData.get(player)
		local choices = RegularRules.orderable(if profile then profile.regulars else nil)
		if #choices == 0 then
			return false, `nowhere a {Config.Regulars.Tiers[Config.Regulars.Order.Tier].name} regular yet`
		end
		for index = #choices, 2, -1 do
			local other = rng:NextInteger(1, index)
			choices[index], choices[other] = choices[other], choices[index]
		end
		for _, id in choices do
			local only = RegularRules.ordinaryOf(id)
			for _, plan in Rules.regularPlans(reach, infoOf(only)) do
				made = api.make(player, plan.mode, plan.tier, only)
				if made then
					break
				end
			end
			if made then
				business = id
				break
			end
		end
	end
	if not made then
		return false, "no delivery of that kind fits you right now"
	end
	local spec = Rules.make(kind, serverNow(), made.tier, made.mode, business)
	made.specialOrder = spec
	made.pay = Rules.pay(made.pay, spec)
	made.role = nil -- (its own look on the board instead of a trade-off)
	api.place(player, made)
	if kind == "golden" then
		PlayerData.track("event", player, "GoldenOffered", made.tier, made.mode) -- 6.14
	end
	local what = if made.mode == "car" then string.rep("★", made.tier) else made.mode
	return true, `{Rules.label(spec)} ({what}, ${made.pay}) on the board for {math.floor(Rules.left(spec, serverNow()) + 0.5)} s`
end

-- May a roll of this kind bring one now? (Not while you help in somebody else's crew: you could not take it.)
local function eligible(player: Player, kind: string): boolean
	local profile = PlayerData.get(player)
	local leader = Crew.ownerOf(player)
	if not profile or not profile.tutorial or (leader ~= nil and leader ~= player) or going(player, kind) then
		return false
	end
	if kind == "golden" then
		return PlayerData.level(player) >= Rules.tuning("golden").level
	end
	return #RegularRules.orderable(profile.regulars) > 0
end

-- One player's second: the expired ones off the board, the rolls that are due.
local function step(player: Player, now: number)
	takeOff(player, nil, false)
	local rolls: { [string]: number } = nextRoll[player] or {}
	if nextRoll[player] == nil then
		for _, kind in KINDS do
			rolls[kind] = now + Rules.tuning(kind).every -- (never the moment you join)
		end
		nextRoll[player] = rolls
	end
	for _, kind in KINDS do
		if now >= rolls[kind] then
			rolls[kind] = now + math.max(10, Rules.tuning(kind).every)
			if eligible(player, kind) and Rules.roll(kind, rng:NextNumber()) then
				offer(player, kind)
			end
		end
	end
end

-- The admin's "goldenOrder" / "regularOrder" (server/Admin.luau): one now, whatever the roll and the level; the one
-- of that kind on the board goes first. What happened, in words.
function SpecialOrders.force(player: Player, kind: string): string
	if kind ~= "golden" and kind ~= "regular" then
		return "ADMIN: unknown kind of order."
	end
	takeOff(player, kind, true)
	local ok, what = offer(player, kind)
	return if ok then `ADMIN: {what}.` else `ADMIN: no {if kind == "golden" then "golden" else "regular's"} order: {what}.`
end

function SpecialOrders.start()
	Players.PlayerRemoving:Connect(function(player)
		nextRoll[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = serverNow()
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function()
					step(player, now)
				end)
				if not ok and os.clock() - lastWarn > 60 then
					lastWarn = os.clock()
					warn(`[SpecialOrders] {player.Name}: {err}`)
				end
			end
		end
	end)
end

return SpecialOrders
