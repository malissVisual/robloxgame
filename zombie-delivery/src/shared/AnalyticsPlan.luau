--!strict
-- 6.13, analytics: the plan, pure (tests/analytics_test.luau). server/Analytics.luau sends what this says to Roblox's
-- AnalyticsService (Config.Analytics holds its numbers; the owner's guide is design/analytics/NAVOD.md):
--   * the onboarding funnel (Steps): nine steps of a new courier's first days, each logged once for life, in order.
--     The steps are one number, a bit a step (reach: reached this session, with the ones waiting; mark: the save's,
--     profile.onboarding, only the steps Roblox took). A step reached before the ones above it waits for them (they
--     are logged together), and the first three (joined, PLAY, the welcome) are implied by any later one, so the
--     funnel never shows a later step above an earlier one. A save from before 6.13 (onboardingFrom) counts as past
--     all of them: only new couriers walk the funnel.
--   * the funnels (Funnels): Delivery (an order taken, picked up, delivered) and Mission (started, completed); a
--     funnel cannot branch, so a failed order is a custom event (failEvent) and a failed mission a progression Fail.
--   * the custom events (Events): a short fixed list of names (validName), never a player's data in a name; their
--     custom fields (fields) are a few short values from small fixed sets (a mode, the stars, a chapter, a script).
--   * the economy (money): every money change's reason (PlayerData.addMoney / spend, `reason`) → a Source or a Sink,
--     a transaction type (the AnalyticsEconomyTransactionType names where one fits, a plain word otherwise) and
--     whether it is batched (the frequent small ones: kill rewards, fuel at the pump, tips). An unknown reason is
--     "Other", never dropped.
--   * the progression (Paths, levelUps): the driver levels and the missions (by their order in the story).
--   * the errors (errorWhere): a script error's script name and line from its message.
--   * 8.2 SANDBOX (the blocks marked so; server/SandboxAnalytics.luau): Roblox keeps one onboarding funnel an
--     experience, so a sandbox server walks the sandbox's own (SandboxSteps: ten steps from joining to the first
--     upgrade, by the same rules, in its own save field profile.sandboxOnboarding: sandboxFrom reads it, only with its
--     flag SandboxFlag); the funnel's functions take the steps (nil: the city's Steps). The moves' events (moveHow,
--     band), the grip checks' sampling (sampler, sample) and the collectibles' event.

local AnalyticsPlan = {}

export type Step = { name: string, implied: boolean? }

-- The onboarding funnel, in order (LogOnboardingFunnelStepEvent: the step's number and name).
AnalyticsPlan.Steps = {
	{ name = "Joined", implied = true }, -- 1: the save loaded (server/Analytics.luau)
	{ name = "PressedPlay", implied = true }, -- 2: PLAY on the start screen (Main.server's Play)
	{ name = "WelcomeSeen", implied = true }, -- 3: Marge's welcome showed (server/Tutorial.luau)
	{ name = "FirstJob" }, -- 4: a job of their own taken (server/Jobs.luau, an order)
	{ name = "FirstDelivery" }, -- 5: an order of their own delivered and paid
	{ name = "Level2" }, -- 6: driver level 2
	{ name = "FirstVehicle" }, -- 7: a bike or a car of their own (bought or given)
	{ name = "FirstMission" }, -- 8: a mission started (server/Missions.luau)
	{ name = "FirstChapter" }, -- 9: a mission chapter finished (its finale)
} :: { Step }

-- 8.2 SANDBOX: the sandbox's onboarding funnel, in order (server/Analytics.luau logs it in place of Steps on a sandbox
-- server; server/SandboxAnalytics.luau says when each is reached). Only joining and PLAY are implied by a later step:
-- the others wait for the ones before them (an upgrade bought before the first move waits for the move, the show, the
-- income and the sale).
AnalyticsPlan.SandboxSteps = {
	{ name = "Joined", implied = true }, -- 1: the save loaded (server/Analytics.luau)
	{ name = "PressedPlay", implied = true }, -- 2: PLAY on the start screen (server/SandboxBoot.luau's Play)
	{ name = "FirstContract" }, -- 3: a moving contract taken (their move started: LAUNCH at a plot's board)
	{ name = "EnteredHouse" }, -- 4: into the house of a move (the chalet's front door)
	{ name = "FirstPieceInVan" }, -- 5: a piece loaded into the van (by them, or into the van of their move)
	{ name = "FirstTripHome" }, -- 6: their van home at their warehouse with a load (a trip: the pieces into the stock)
	{ name = "FirstPieceOnShow" }, -- 7: a piece of their stock on a display stand
	{ name = "FirstIncome" }, -- 8: the stands paid them ("CollectionIncome")
	{ name = "FirstSale" }, -- 9: a piece sold ("CollectionSale")
	{ name = "FirstUpgrade" }, -- 10: an upgrade bought at the UPGRADES desk ("Upgrade")
} :: { Step }

-- Every step reached (an old save's number).
AnalyticsPlan.ALL = 2 ^ #AnalyticsPlan.Steps - 1

-- 8.2: every step of `steps` reached (an old sandbox save's number: allOf(SandboxSteps)).
function AnalyticsPlan.allOf(steps: { Step }): number
	return 2 ^ #steps - 1
end

local function bit(step: number): number
	return bit32.lshift(1, step - 1)
end

-- Was this step reached? (8.2: of `steps`; nil: the city's Steps. The same for the functions below.)
function AnalyticsPlan.has(mask: number, step: number, steps: { Step }?): boolean
	local list = steps or AnalyticsPlan.Steps
	return step >= 1 and step <= #list and bit32.btest(mask, bit(step))
end

-- A step's number by its name (nil for a name not in Steps).
function AnalyticsPlan.stepOf(name: string, steps: { Step }?): number?
	for index, step in steps or AnalyticsPlan.Steps do
		if step.name == name then
			return index
		end
	end
	return nil
end

-- The number with `step` marked (server/Analytics.luau marks the save's only once Roblox took the step).
function AnalyticsPlan.mark(mask: number, step: number, steps: { Step }?): number
	if step < 1 or step > #(steps or AnalyticsPlan.Steps) or step ~= math.floor(step) then
		return mask
	end
	return bit32.bor(mask, bit(step))
end

-- How many steps from the first were reached one after the other: the ones logged.
function AnalyticsPlan.logged(mask: number, steps: { Step }?): number
	local list = steps or AnalyticsPlan.Steps
	local n = 0
	while n < #list and AnalyticsPlan.has(mask, n + 1, list) do
		n += 1
	end
	return n
end

-- `step` reached: the new number and the steps to log now (none, it, or it with the ones that waited for it).
function AnalyticsPlan.reach(mask: number, step: number, steps: { Step }?): (number, { number })
	local all = steps or AnalyticsPlan.Steps
	if step < 1 or step > #all or step ~= math.floor(step) then
		return mask, {}
	end
	local before = AnalyticsPlan.logged(mask, all)
	local after = bit32.bor(mask, bit(step))
	for earlier = 1, step - 1 do
		if all[earlier].implied then
			after = bit32.bor(after, bit(earlier))
		end
	end
	local list: { number } = {}
	for n = before + 1, AnalyticsPlan.logged(after, all) do
		table.insert(list, n)
	end
	return after, list
end

-- The steps reached as the save says (PlayerData's applySaved): no real save (a new courier, or a lock-only record:
-- no money in it) starts at 0; a real save keeps its number (checked); a real save without one is from before 6.13,
-- a courier past their first days: every step (nothing is logged for them).
function AnalyticsPlan.onboardingFrom(saved: any): number
	if type(saved) ~= "table" or saved.money == nil then
		return 0
	end
	local value = saved.onboarding
	if type(value) ~= "number" or value ~= value then
		return AnalyticsPlan.ALL
	end
	return math.clamp(math.floor(value), 0, AnalyticsPlan.ALL)
end

-- 8.2 SANDBOX: the save's flag of the sandbox's funnel (server/PlayerData.luau writes it with profile.sandboxOnboarding).
AnalyticsPlan.SandboxFlag = "sandboxOnboardingKept"

-- 8.2 SANDBOX: the sandbox's steps reached as the save says (PlayerData's applySaved): no real save (a new player, or a
-- lock-only record: no money in it) starts at 0; a real save written with the flag keeps its number (checked); a real
-- save without it is from before 8.2, a player who knows the sandbox already: every step (nothing is logged for them).
function AnalyticsPlan.sandboxFrom(saved: any): number
	if type(saved) ~= "table" or saved.money == nil then
		return 0
	end
	local all = AnalyticsPlan.allOf(AnalyticsPlan.SandboxSteps)
	local value = saved.sandboxOnboarding
	if saved[AnalyticsPlan.SandboxFlag] ~= true or type(value) ~= "number" or value ~= value then
		return all
	end
	return math.clamp(math.floor(value), 0, all)
end

-- ── The funnels ────────────────────────────────────────────────────────────

AnalyticsPlan.Funnels = {
	Delivery = { "Taken", "PickedUp", "Delivered" },
	Mission = { "Started", "Completed" },
}

-- The funnel steps to log to get from `last` (logged so far) to `step`: the skipped ones too (an order delivered was
-- picked up), none when it is not ahead.
function AnalyticsPlan.funnelSteps(last: number, step: number, size: number): { number }
	local list: { number } = {}
	for n = math.max(1, last + 1), math.min(step, size) do
		table.insert(list, n)
	end
	return list
end

-- ── The custom events ──────────────────────────────────────────────────────

-- The whole list (LogCustomEvent's names). Never more, never built from a player's data.
AnalyticsPlan.Events = {
	"DeathOnJob", -- died on a job or a mission (or in its crew)
	"JobFailedTime", -- an order's clock ran out
	"JobFailedCargo", -- an order's cargo was lost (stolen, wrecked, ruined)
	"JobGaveUp", -- GIVE UP (the player cancelled)
	"JobFailedOther", -- any other end (a partner left, NO SHOOTING broken, an admin)
	"QueueAddAll", -- ADD ALL on the job board (value: the jobs taken or queued)
	"ZipRide", -- a zip line ridden
	"BusRide", -- a city bus boarded
	"ScooterRental", -- a ZDC RIDE scooter taken
	"StylePurchase", -- a cosmetic bought (value: its price)
	"ShiftDone", -- 6.14: a shift finished (value: the shifts this session; field: the driver level)
	"SessionLength", -- a player left (value: the minutes played)
	"ServerError", -- a script error on the server
	"ClientError", -- a script error on a player's device
	-- 6.14, the golden orders (server/SpecialOrders.luau; value: its danger level, fields: its transport, where) and
	-- the regulars (server/Regulars.luau; value: the tier's number, fields: the tier, the business)
	"GoldenOffered", -- a golden order came onto a board
	"GoldenTaken", -- a golden order taken (started, or added to a run)
	"GoldenDone", -- a golden order delivered and paid
	"GoldenExpired", -- a golden order's clock ran out (on the board or in NEXT UP)
	"RegularTierUp", -- a courier became a business's Bronze / Silver / Gold / Platinum regular
	-- 6.15, the fixed missions (server/Jobs.luau): a mission done with every enemy of its plan killed (value: how many;
	-- fields: the chapter, "solo" or "crew")
	"MissionCleared",
	-- 6.15, the live events (server/LiveEvents.luau)
	"EventStarted", -- a live event started (value: the players in the server; field: its id); logged with one of them
	"SupplyDelivered", -- a supply drop brought to the depot (value: seconds since it landed; field: the driver level)
	"HordeBeaten", -- a share of the horde's reward paid (value: the player's kills; field: "beaten" or "time")
	-- 7.0, MOVES (server/Moving.luau)
	"MoveDone", -- a house move ended and paid (value: its stars; fields: the contract, "solo" or "crew")
	-- 8.0 SANDBOX, the collection (server/Collection.luau; field: the rarity)
	"CollectionAdded", -- pieces came home into the warehouse's stock (value: how many at once; field: the rarest)
	"CollectionDisplayed", -- a piece put on show on a display stand (value: its $ a minute)
	"CollectionSold", -- a piece sold (value: its price; 8.3: a second field, the market: "hot", "cold" or none)
	-- 8.1 SANDBOX, the upgrades (server/Upgrades.luau; value: the level bought, field: the upgrade's id)
	"UpgradeBought",
	-- 8.2 SANDBOX, the moves, the grip and the finds (server/SandboxAnalytics.luau; the fields' words: moveHow, band)
	"MoveStarted", -- a move started (value: the owner's moves this session; field: "solo" or "crew")
	"MoveFinished", -- a move ended with pieces home (value: its minutes; fields: how, the trips, the pieces home)
	"MoveFinishedValue", -- that move's haul (value: what came home is worth, $; fields: how, the pieces, "solo" / "crew")
	"MoveGaveUp", -- a move ended with nothing home (value: its minutes; fields: how, how far it got, "solo" / "crew")
	"GripCheck", -- a grip check's outcome, one in GripEvery a player (value: GripEvery; fields: outcome, lift / wobble, fragile)
	"CollectibleFound", -- a collectible came home into the stock (value: its worth, $; fields: the rarity, its id)
}

-- A name Roblox takes and a dashboard shows well: a capital letter, then letters and digits, 32 at most.
function AnalyticsPlan.validName(name: any): boolean
	return type(name) == "string" and #name <= 32 and string.match(name, "^%u[%w]*$") ~= nil
end

function AnalyticsPlan.isEvent(name: string): boolean
	return table.find(AnalyticsPlan.Events, name) ~= nil
end

-- A failed order's event by why it failed (server/Jobs.luau passes "time", "cargo" or "gaveup"; nil: other).
function AnalyticsPlan.failEvent(why: string?): string
	return if why == "time" then "JobFailedTime"
		elseif why == "cargo" then "JobFailedCargo"
		elseif why == "gaveup" then "JobGaveUp"
		else "JobFailedOther"
end

-- Enum.AnalyticsCustomFieldKeys' names: the keys of an event's custom fields.
AnalyticsPlan.FieldKeys = { "CustomField01", "CustomField02", "CustomField03" }

-- A custom field's value: a short word from a small set (letters, digits, _ and -; 32 at most), "" for nothing.
function AnalyticsPlan.fieldValue(value: any): string
	local text = if type(value) == "string" then value elseif type(value) == "number" then tostring(value) else ""
	text = string.gsub(text, "[^%w_%-]", "")
	return string.sub(text, 1, 32)
end

-- The custom fields table (nil when every value is empty).
function AnalyticsPlan.fields(a: any?, b: any?, c: any?): { [string]: string }?
	local out: { [string]: string } = {}
	local any = false
	local values: { any } = { a, b, c }
	for index = 1, #AnalyticsPlan.FieldKeys do
		local text = AnalyticsPlan.fieldValue(values[index])
		if text ~= "" then
			out[AnalyticsPlan.FieldKeys[index]] = text
			any = true
		end
	end
	return if any then out else nil
end

-- ── The economy ────────────────────────────────────────────────────────────

-- Enum.AnalyticsEconomyTransactionType's names (the ones used where they fit).
AnalyticsPlan.EnumTypes = { "ContextualPurchase", "Gameplay", "IAP", "Onboarding", "Shop", "TimedReward" }

-- Where money comes from: reason → transaction type.
AnalyticsPlan.Sources = {
	DeliveryPay = "Gameplay", -- an order's pay (the owner)
	CrewPay = "Gameplay", -- a crew member's share of it
	Tip = "Gameplay", -- trickshot and PERFECT tips, a survivor's tip, a lift to the depot
	KillReward = "Gameplay", -- a zombie or a bandit car
	CrateLoot = "Gameplay", -- a supply crate's cash
	MissionReward = "Gameplay", -- a mission's first clear, new stars, a chapter's reward
	ChallengeReward = "Gameplay", -- challenges and lost packages
	LevelReward = "Gameplay", -- a driver level's reward
	CompanySafe = "Gameplay", -- your company's safe emptied
	TaskReward = "TimedReward", -- the daily and weekly tasks
	SandboxTask = "TimedReward", -- 8.2 SANDBOX: a daily or weekly task's reward, the all-dailies bonus (server/SandboxTasks.luau; the SKU the task's id)
	ShiftBonus = "Gameplay", -- 6.14: a shift's pay (Config.Jobs.Shift: its deliveries in one go, server/Shift.luau)
	SupplyDrop = "Gameplay", -- 6.15: a live event's supply drop brought to the depot (server/LiveEvents.luau)
	HordeReward = "Gameplay", -- 6.15: a share of the horde at the gates' reward (server/LiveEvents.luau)
	MovePay = "Gameplay", -- 7.0: a house move's pay (the owner's and each crew mate's share: server/Moving.luau)
	CollectionIncome = "Gameplay", -- 8.0: the warehouse's display stands earn every minute you play (server/Collection.luau)
	CollectionSale = "Sale", -- 8.0: a piece of your collection sold (server/Collection.luau; the item SKU its furniture id)
	BookMilestone = "Gameplay", -- 8.2: a collection book milestone, paid once (server/CollectionBook.luau; the SKU its id)
	TutorialReward = "Onboarding", -- Marge's first-delivery reward
	Refund = "Refund", -- money back (a tow that did not come, a scooter that did not, retired kit)
	BagRefund = "Refund", -- 6.23: an old save's bags, owned for good before, paid back once (bags are bought each game now)
	CarRefund = "Refund", -- 7.x: an old save's cars (all but the ZDC Van left the game), paid back once (Config.CompanyVan); 7.2 review: with what the van could not take over and the employers' bonuses for vehicles it had earned
	EmployerBonus = "Gameplay", -- 7.x: an employer's bonus after their jobs (Config.Employers bonus: their vehicle before)
	PropertySale = "Sale", -- real estate sold
	Admin = "Admin", -- the admin panel
}

-- Where money goes: reason → transaction type (the item SKU is the item's id).
AnalyticsPlan.Sinks = {
	Car = "Shop",
	Bike = "Shop",
	Gun = "Shop",
	CarGun = "Shop",
	Item = "Shop",
	Kit = "Shop",
	Bag = "Shop", -- 6.23: a bag for this game at ZDC Bags (Config.BagShop.PerGame)
	Gear = "Shop",
	Paint = "Shop",
	Stage = "Shop",
	Upgrade = "Shop", -- a city upgrade track; 8.1 SANDBOX: a warehouse upgrade at the UPGRADES desk (server/Upgrades.luau; the SKU its id)
	VanPaint = "Shop", -- 8.3 SANDBOX: a paint or a livery for your van at the PAINT shop (server/VanPaint.luau; the SKU its id)
	Style = "Shop",
	RealEstate = "Shop",
	Company = "Shop", -- a courier hired, an upgrade of your company
	Fuel = "ContextualPurchase",
	Tow = "ContextualPurchase",
	Repair = "ContextualPurchase",
	Reroll = "ContextualPurchase",
	Rental = "ContextualPurchase",
}

-- The frequent small ones: summed a player and sent every Config.Analytics.BatchSeconds (and when they leave).
AnalyticsPlan.Batched = { KillReward = true, Fuel = true, Tip = true, CollectionIncome = true } -- (8.0: the stands pay every Config.Collection.Tick s)

export type MoneyRule = { reason: string, flow: string, kind: string, batch: boolean }

-- A money change: `delta` > 0 came in, < 0 went out, for `reason` (nil or unknown, or a reason of the other side:
-- "Other").
function AnalyticsPlan.money(reason: string?, delta: number): MoneyRule
	local source = delta > 0
	local list: { [string]: string } = if source then AnalyticsPlan.Sources else AnalyticsPlan.Sinks
	local kind = if reason then list[reason] else nil
	if not reason or not kind then
		return { reason = "Other", flow = if source then "Source" else "Sink", kind = "Other", batch = false }
	end
	return { reason = reason, flow = if source then "Source" else "Sink", kind = kind, batch = AnalyticsPlan.Batched[reason] == true }
end

-- ── The progression ────────────────────────────────────────────────────────

AnalyticsPlan.Paths = { Level = "DriverLevel", Missions = "Missions" }

-- The levels completed by going from `before` to `after` (a level-up from 3 to 5 completes 3 and 4; 20 at most).
function AnalyticsPlan.levelUps(before: number, after: number): { number }
	local list: { number } = {}
	for level = math.max(1, before), math.min(after - 1, before + 19) do
		table.insert(list, level)
	end
	return list
end

-- ── The errors ─────────────────────────────────────────────────────────────

-- A script's name as a field (its own name: letters, digits, _; "Unknown" for anything else).
function AnalyticsPlan.scriptName(name: any): string
	if type(name) ~= "string" or #name < 1 or #name > 40 or string.match(name, "^[%w_]+$") == nil then
		return "Unknown"
	end
	return name
end

-- Where an error happened: "ServerScriptService.Server.Jobs:123: attempt to …" → "Jobs", 123. A message without
-- its place: the script's own name (or "Unknown") and line 0.
function AnalyticsPlan.errorWhere(message: any, scriptName: string?): (string, number)
	if type(message) == "string" then
		local path, line = string.match(message, "^([%w_%.]+):(%d+):")
		if path and line then
			return AnalyticsPlan.scriptName(string.match(path, "([^%.]+)$")), math.clamp(tonumber(line) or 0, 0, 1000000)
		end
	end
	return AnalyticsPlan.scriptName(scriptName), 0
end

-- ── 8.2 SANDBOX: the moves and the grip checks ────────────────────────────

-- How a move ended, a word (MoveFinished's and MoveGaveUp's field 01), from server/Moving.luau's end (its onFinish
-- listeners' facts): the phase (done | late | cancelled | failed), the words it said (why: the result card's; nil for
-- the admin's end), the clock's seconds left and whether every piece is home or lost:
--   "time"    the clock ran out (also FINISH or GIVE UP in the grace after 0:00, a late trip, nothing home by then)
--   "all"     everything home (or lost on the way)
--   "left"    the owner left the game
--   "admin"   the admin panel's end
--   "giveup"  GIVE UP
--   "finish"  FINISH
function AnalyticsPlan.moveHow(phase: string, why: string?, secondsLeft: number, allDone: boolean): string
	if phase == "failed" or phase == "late" or secondsLeft <= 0 then
		return "time"
	elseif allDone and phase == "done" then
		return "all"
	end
	local text = string.lower(why or "")
	if string.find(text, "left the game", 1, true) then
		return "left"
	elseif why == nil or string.find(text, "admin", 1, true) then
		return "admin"
	elseif phase == "cancelled" or string.find(text, "called it off", 1, true) then
		return "giveup"
	end
	return "finish"
end

-- A count as a field's word: in bands of `size` from 0 ("0-4", "5-9" …; size 1: the number itself), `top` and over
-- "<top>plus" (a field keeps letters, digits, _ and - only). Not a number: as 0.
function AnalyticsPlan.band(n: any, size: number, top: number): string
	local count = if type(n) == "number" and n == n then math.max(0, math.floor(n)) else 0
	if count >= top then
		return `{top}plus`
	end
	local width = math.max(1, math.floor(size))
	local low = count - count % width
	return if width == 1 then tostring(low) else `{low}-{low + width - 1}`
end

-- One check in `every` (a player's grip checks: Config.Analytics.GripEvery): a window of `every` checks, the ones seen
-- in it and the one of them that is sent (pick: 1 … every, drawn from a roll, 0 ≤ roll < 1), so what is sent is a fair
-- sample and never more than one a window.
export type Sampler = { seen: number, pick: number }

local function pickOf(every: number, roll: number): number
	local size = math.max(1, math.floor(every))
	return 1 + math.clamp(math.floor((if roll == roll then roll else 0) * size), 0, size - 1)
end

function AnalyticsPlan.sampler(every: number, roll: number): Sampler
	return { seen = 0, pick = pickOf(every, roll) }
end

-- One more check: true when it is the window's pick (send it); a full window draws the next one's pick from `roll`.
function AnalyticsPlan.sample(sampler: Sampler, every: number, roll: number): boolean
	sampler.seen += 1
	local hit = sampler.seen == sampler.pick
	if sampler.seen >= math.max(1, math.floor(every)) then
		sampler.seen = 0
		sampler.pick = pickOf(every, roll)
	end
	return hit
end

-- ── The rest ───────────────────────────────────────────────────────────────

-- Events a minute the server may send with `players` in it.
function AnalyticsPlan.budget(players: number, budget: { Base: number, PerPlayer: number }): number
	return budget.Base + budget.PerPlayer * math.max(0, players)
end

-- A session's length in minutes (a tenth at most).
function AnalyticsPlan.minutes(seconds: number): number
	return math.floor(math.max(0, seconds) / 6 + 0.5) / 10
end

-- The admin panel's line: "on" (sending), "studio" (counted, not sent) or "off" (Config.Analytics.Enabled), the counts
-- of this server's session by kind and the last event.
AnalyticsPlan.Kinds = { "onboarding", "funnel", "economy", "progression", "custom", "error" }

function AnalyticsPlan.summary(mode: string, counts: { [string]: number }, last: string?): string
	local head = if mode == "on" then "ON, sending" elseif mode == "studio" then "OFF in Studio (counted, not sent)" else "OFF (Config.Analytics.Enabled)"
	local parts = { head }
	for _, kind in AnalyticsPlan.Kinds do
		table.insert(parts, `{kind} {counts[kind] or 0}`)
	end
	if (counts.dropped or 0) > 0 then
		table.insert(parts, `dropped {counts.dropped}`)
	end
	if (counts.failed or 0) > 0 then
		table.insert(parts, `failed {counts.failed}`)
	end
	local text = table.concat(parts, " · ")
	return if last and last ~= "" then `{text} · last: {last}` else text
end

return AnalyticsPlan
