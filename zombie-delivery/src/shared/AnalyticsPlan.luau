--!strict
-- 6.13, analytics: the plan, pure (tests/analytics_test.luau). server/Analytics.luau sends what this says to Roblox's
-- AnalyticsService (Config.Analytics holds its numbers; the owner's guide is design/analytics/NAVOD.md). 10.6: the
-- game's plan only (the city's funnel, its order and mission funnels, its events, its money's reasons and the driver
-- levels went with it):
--   * the onboarding funnel (SandboxSteps: ten steps from joining to the first upgrade), each logged once for life, in
--     order. The steps are one number, a bit a step (reach: reached this session, with the ones waiting; mark: the
--     save's, profile.sandboxOnboarding, only the steps Roblox took; sandboxFrom reads it, only with its flag
--     SandboxFlag). A step reached before the ones above it waits for them (they are logged together), and the first
--     two (joined, PLAY) are implied by any later one, so the funnel never shows a later step above an earlier one. A
--     save from before 8.2 counts as past all of them: only new players walk the funnel.
--   * the custom events (Events): a short fixed list of names (validName), never a player's data in a name; their
--     custom fields (fields) are a few short values from small fixed sets (how a move ended, a rarity, a script).
--   * the economy (money): every money change's reason (PlayerData.addMoney / spend, `reason`) → a Source or a Sink,
--     a transaction type (the AnalyticsEconomyTransactionType names where one fits, a plain word otherwise) and
--     whether it is batched (the frequent small ones: kill rewards, the stands' income). An unknown reason is "Other",
--     never dropped.
--   * the errors (errorWhere): a script error's script name and line from its message.
--   * 8.2: the moves' events (moveHow, band), the grip checks' sampling (sampler, sample).

local AnalyticsPlan = {}

export type Step = { name: string, implied: boolean? }

-- 8.2: the onboarding funnel, in order (server/Analytics.luau logs it, LogOnboardingFunnelStepEvent: the step's number
-- and name; server/SandboxAnalytics.luau says when each is reached). Only joining and PLAY are implied by a later step:
-- the others wait for the ones before them (an upgrade bought before the first move waits for the move, the show, the
-- income and the sale).
AnalyticsPlan.SandboxSteps = {
	{ name = "Joined", implied = true }, -- 1: the save loaded (server/Analytics.luau)
	{ name = "PressedPlay", implied = true }, -- 2: PLAY on the start screen (server/SandboxBoot.luau's Play)
	{ name = "FirstContract" }, -- 3: a run started (their move: a portal's run, a round)
	{ name = "EnteredHouse" }, -- 4: into the house of a run (its front door)
	{ name = "FirstPieceInVan" }, -- 5: a piece loaded into the van (by them, or into the van of their run)
	{ name = "FirstTripHome" }, -- 6: pieces home at their warehouse (into the stock)
	{ name = "FirstPieceOnShow" }, -- 7: a piece of their stock on a display stand
	{ name = "FirstIncome" }, -- 8: the stands paid them ("CollectionIncome")
	{ name = "FirstSale" }, -- 9: a piece sold ("CollectionSale")
	{ name = "FirstUpgrade" }, -- 10: an upgrade bought at the UPGRADES desk ("Upgrade")
} :: { Step }

-- Every step of `steps` reached (an old save's number: allOf(SandboxSteps)).
function AnalyticsPlan.allOf(steps: { Step }): number
	return 2 ^ #steps - 1
end

local function bit(step: number): number
	return bit32.lshift(1, step - 1)
end

-- Was this step reached? (`steps`: the funnel's, nil: SandboxSteps. The same for the functions below.)
function AnalyticsPlan.has(mask: number, step: number, steps: { Step }?): boolean
	local list = steps or AnalyticsPlan.SandboxSteps
	return step >= 1 and step <= #list and bit32.btest(mask, bit(step))
end

-- A step's number by its name (nil for a name not in the steps).
function AnalyticsPlan.stepOf(name: string, steps: { Step }?): number?
	for index, step in steps or AnalyticsPlan.SandboxSteps do
		if step.name == name then
			return index
		end
	end
	return nil
end

-- The number with `step` marked (server/Analytics.luau marks the save's only once Roblox took the step).
function AnalyticsPlan.mark(mask: number, step: number, steps: { Step }?): number
	if step < 1 or step > #(steps or AnalyticsPlan.SandboxSteps) or step ~= math.floor(step) then
		return mask
	end
	return bit32.bor(mask, bit(step))
end

-- How many steps from the first were reached one after the other: the ones logged.
function AnalyticsPlan.logged(mask: number, steps: { Step }?): number
	local list = steps or AnalyticsPlan.SandboxSteps
	local n = 0
	while n < #list and AnalyticsPlan.has(mask, n + 1, list) do
		n += 1
	end
	return n
end

-- `step` reached: the new number and the steps to log now (none, it, or it with the ones that waited for it).
function AnalyticsPlan.reach(mask: number, step: number, steps: { Step }?): (number, { number })
	local all = steps or AnalyticsPlan.SandboxSteps
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

-- 8.2: the save's flag of the funnel (server/PlayerData.luau writes it with profile.sandboxOnboarding).
AnalyticsPlan.SandboxFlag = "sandboxOnboardingKept"

-- 8.2: the steps reached as the save says (PlayerData's applySaved): no real save (a new player, or a lock-only
-- record: no money in it) starts at 0; a real save written with the flag keeps its number (checked); a real save
-- without it is from before 8.2, a player who knows the game already: every step (nothing is logged for them).
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

-- ── The custom events ──────────────────────────────────────────────────────

-- The whole list (LogCustomEvent's names). Never more, never built from a player's data.
AnalyticsPlan.Events = {
	"DeathOnJob", -- died on a run (its host or its party; the name as ever)
	"SessionLength", -- a player left (value: the minutes played)
	"ServerError", -- a script error on the server
	"ClientError", -- a script error on a player's device
	"MoveDone", -- a run ended (value: its stars; fields: the house, "solo" or "crew"; server/Moving.luau)
	-- 8.0, the collection (server/Collection.luau; field: the rarity)
	"CollectionAdded", -- pieces came home into the warehouse's stock (value: how many at once; field: the rarest)
	"CollectionDisplayed", -- a piece put on show on a display stand (value: its $ a minute)
	"CollectionSold", -- a piece sold (value: its price; 8.3: a second field, the market: "hot", "cold" or none)
	-- 8.1, the upgrades (server/Upgrades.luau; value: the level bought, field: the upgrade's id)
	"UpgradeBought",
	-- 8.2, the moves, the grip and the finds (server/SandboxAnalytics.luau; the fields' words: moveHow, band)
	"MoveStarted", -- a move started (value: the owner's moves this session; field: "solo" or "crew")
	"MoveFinished", -- a move ended with pieces home (value: its minutes; fields: how, the trips, the pieces home)
	"MoveFinishedValue", -- that move's haul (value: what came home is worth, $; fields: how, the pieces, "solo" / "crew")
	"MoveGaveUp", -- a move ended with nothing home (value: its minutes; fields: how, how far it got, "solo" / "crew")
	"GripCheck", -- a grip check's outcome, one in GripEvery a player (value: GripEvery; fields: outcome, lift / wobble, fragile)
	"CollectibleFound", -- a collectible came home into the stock (value: its worth, $; fields: the rarity, its id)
	"VisitorOffer", -- 8.3: a showroom visitor's offer (server/VisitorOffers.luau; value: its $; fields: "made", "sold", "declined", "expired", "gone" or "left", the piece's rarity)
	"PlayerTrade", -- 8.7: a trade between players (server/PlayerTrade.luau; value: its $; fields: "made", "sold", "declined", "expired", "gone", "left", "failed" (the deal refused at ACCEPT) or "bought" (its buyer bought the piece by its sign) for an offer, "sign" for a FOR SALE sign bought; the piece's rarity)
}

-- A name Roblox takes and a dashboard shows well: a capital letter, then letters and digits, 32 at most.
function AnalyticsPlan.validName(name: any): boolean
	return type(name) == "string" and #name <= 32 and string.match(name, "^%u[%w]*$") ~= nil
end

function AnalyticsPlan.isEvent(name: string): boolean
	return table.find(AnalyticsPlan.Events, name) ~= nil
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
	KillReward = "Gameplay", -- a zombie of a run's (server/Zombies.luau; Config.Runs.Danger has them off since 10.5)
	SandboxTask = "TimedReward", -- 8.2: a daily or weekly task's reward, the all-dailies bonus (server/SandboxTasks.luau; the SKU the task's id)
	CollectionIncome = "Gameplay", -- 8.0: the warehouse's display stands earn every minute you play (server/Collection.luau)
	CollectionSale = "Sale", -- 8.0: a piece of your collection sold (server/Collection.luau; the item SKU its furniture id)
	VisitorOffer = "Sale", -- 8.3: a showroom visitor's offer accepted: the piece sold at it (server/VisitorOffers.luau → Collection.sellAt; the SKU its furniture id)
	PlayerSale = "Sale", -- 8.7: a piece sold to another player: the whole price (server/PlayerTrade.luau → Collection.transfer; the SKU its furniture id; the fee goes out as TradeFee)
	CrewRescue = "Gameplay", -- 10.1: a run's trapped helper freed who is in your crew already: the bonus instead (server/HelperCrew.luau; the SKU his kind)
	BookMilestone = "Gameplay", -- 8.2: a collection book milestone, paid once (server/CollectionBook.luau; the SKU its id)
	AuctionSale = "Sale", -- 8.8: your piece sold at the Auction House, the whole price (shared/AuctionRules.luau payments; the fee goes out as AuctionFee; the SKU its furniture id)
	Admin = "Admin", -- the admin panel
}

-- Where money goes: reason → transaction type (the item SKU is the item's id).
AnalyticsPlan.Sinks = {
	Upgrade = "Shop", -- 8.1: a warehouse upgrade at the UPGRADES desk (server/Upgrades.luau; the SKU its id)
	VanPaint = "Shop", -- 8.3: a paint or a livery for your van at the PAINT shop (server/VanPaint.luau; the SKU its id)
	AuctionBuy = "Shop", -- 8.8: a lot bought at the Auction House (shared/AuctionRules.luau payments; the SKU its furniture id)
	AuctionFee = "ContextualPurchase", -- 8.8: the house's fee on your piece sold there (Config.PlayerTrade.Fee, the trades' own: it disappears, a money sink)
	CrewDischarge = "ContextualPurchase", -- 10.1: a helper of your crew discharged from hospital early (server/HelperCrew.luau; the SKU his kind)
	PlayerBuy = "Shop", -- 8.7: a piece bought from another player (server/PlayerTrade.luau → Collection.transfer; the SKU its furniture id)
	TradeFee = "ContextualPurchase", -- 8.7: the ZDC fee on a sale between players, from the seller's side (Config.PlayerTrade.Fee: it disappears, a money sink)
}

-- The frequent small ones: summed a player and sent every Config.Analytics.BatchSeconds (and when they leave).
AnalyticsPlan.Batched = { KillReward = true, CollectionIncome = true } -- (8.0: the stands pay every Config.Collection.Tick s)

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

-- ── The errors ─────────────────────────────────────────────────────────────

-- A script's name as a field (its own name: letters, digits, _; "Unknown" for anything else).
function AnalyticsPlan.scriptName(name: any): string
	if type(name) ~= "string" or #name < 1 or #name > 40 or string.match(name, "^[%w_]+$") == nil then
		return "Unknown"
	end
	return name
end

-- Where an error happened: "ServerScriptService.Server.Moving:123: attempt to …" → "Moving", 123. A message without
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

-- ── 8.2: the moves and the grip checks ─────────────────────────────────────

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
AnalyticsPlan.Kinds = { "onboarding", "economy", "custom", "error" }

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
