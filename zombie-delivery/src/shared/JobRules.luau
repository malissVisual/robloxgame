--!strict
-- 4.7, real jobs: the rules of the job board's choice, the rating of a job, the streak and the licences. Pure Luau
-- (no Roblox API), shared by server/Jobs.luau, server/PlayerData.luau, the board (client/DispatchUi.luau), the result
-- card (client/Hud.luau) and the CAREER window (client/CareerUi.luau); tested in tests/jobrules_test.luau.
--
--   JobRules.roles(r)                     the trade-offs of one tier's ordinary offers: "short" first, then two of
--                                         "long" | "risky" | "bulk" (r: a random number 0 … 1 each call)
--   JobRules.window(role, low, high)      the drop's distance band of a role inside a tier's range
--   JobRules.roleInfo(role)               { name, icon, why } for the board's row
--   JobRules.rerollFee(stars)             what a REROLL of that tier costs
--   JobRules.rate(condition, timeShare, wrecked, lost)   { stars 1 … 3, misses, checks = { { text, ok } } }
--   JobRules.nextStreak(streak, stars)    the streak after a job rated `stars` (0 after a ★)
--   JobRules.streakBonus(streak)          the share of the pay the streak adds (StreakStep each, StreakMax at most)
--   JobRules.ratedPay(total, stars, streak)   (the pay, what the rating adds or takes, what the streak adds)
--   JobRules.ratedXp(xp, stars)           the XP × Config.Jobs.Rating.Xp[stars]
--   JobRules.licence(tier)                the licence a tier needs (Config.Jobs.Licences) or nil
--   JobRules.hasLicence(tier, level, held, counts)   may this driver take the tier's board deliveries?
--   JobRules.progress(tier, counts)       (jobs counted, jobs needed) toward the tier's licence
--   JobRules.countJob(counts, tier, stars)    a finished job counted toward every licence it is good for
--   JobRules.grandfather(level, deliveries)   the licences a save from before 4.7 keeps (see the function)
--   JobRules.stars(n)                     "★★☆"
--
-- 4.8, cargo with rules, multi-drop and road events (Config.Jobs CargoRules / MultiDrop / RoadEvents; tested in
-- tests/cargorules_test.luau):
--   JobRules.cargoRules(kind, look, business)   the rules of a cargo: { "fragile" | "food" | "heavy" | "cash" | "people" }
--   JobRules.hasRule(rules, rule)         is it one of them?
--   JobRules.ruleInfo(rule)               { name, icon, why } for the board and the HUD
--   JobRules.rulesText(rules)             the board's RULES line, nil without any
--   JobRules.ruleLine(rules, freshness, cooler)   the contract's line ("Fresh 82% · Fragile: brake gently"), or nil
--   JobRules.jolt(before, now, dt)        "bump" | "brake" | nil from the car's speed a tick ago and now
--   JobRules.joltLoss(rules, jolt, straps)        the condition a jolt costs this cargo (Ratchet Straps × StrapsLoss)
--   JobRules.damageLoss(rules, base, speed, straps)   the condition a hit of the car costs (base: the usual share)
--   JobRules.freshDrain(tier, seconds, cooler, warm)   the freshness food loses in that time (a Cooler Box × CoolerDrain;
--                                         5.0: a thermal jacket × its warm)
--   JobRules.freshPay(freshness)          the pay's multiplier for the food's freshness
--   JobRules.footKnock(fell, landed, lostHealth)   6.4: "fall" | "hit" | nil: what knocked a fragile piece on foot
--   JobRules.knockLoss(knock, padded)     6.4: the condition it costs (0 in the Padded Messenger Bag)
--   JobRules.dropCount(tier, pieces, receivers, r1, r2)   the drops of a board delivery (1 = an ordinary one)
--   JobRules.destinations(needs, first)   the stop every piece goes to, in the order they are made
--   JobRules.multiDropPay(drops)          what the extra drops pay
--   JobRules.pickEvent(r1, r2)            the road event of a job ("survivor" | "addon" | "roadblock") or nil
--   JobRules.eventAfter(r)                seconds of driving before it comes
--   JobRules.survivorBonus(stars)         a survivor dropped at the safe zone
--   JobRules.addOnFits(inCar, coming, capacity)   room for one more piece?
--
-- 5.0, the ON FOOT jobs (Config.Jobs.Foot; tested in tests/transport_test.luau):
--   JobRules.footPay(distance, pieces, multiplier)   what a foot job pays ($5 steps)
--   JobRules.footTime(distance, handling, timeMultiplier)   its clock
--   JobRules.footPieces(wanted, room)     its pieces: within Foot.Pieces and what you carry
-- 5.1, the BIKE jobs (Config.Jobs.Bike): the same three with Config.Jobs.Bike as their last argument (LightRules), and
--   JobRules.bikeXp(xp)                   a bike job's XP (+ Bike.XpBonus)
-- 5.7, the step up to a car (Config.Jobs.CarStep; tested in tests/footevents_test.luau):
--   JobRules.carStep(mode, tier, special) is it a ★ board delivery in your own car?
--   JobRules.carStepXp(xp)                its XP (+ CarStep.XpBonus)
--   JobRules.carStepPieces(role, r, room) its pieces: CarStep.Pieces, never more than the car holds now
--
-- 5.2, several orders at once (Config.Jobs.Orders; tested in tests/orders_test.luau):
--   JobRules.stackable(info)              may this offer run beside other orders (StackInfo)?
--   JobRules.ordersMax(mode)              orders open at once at most (Orders.Max)
--   JobRules.orderRoom(room, outstanding) the free room: room − the pieces the open orders still hold or pick up
--   JobRules.canAddOrder(mode, open, pieces, free)   (ok, "full" | "room")
--   JobRules.orderButton(why, used, room, open, max)   "NO ROOM (3/4 slots)" / "ORDERS FULL (2/2)"
--   JobRules.stopOpen(stops, index, withYou)          "done" | "open" | "wait" | "empty" (StopState)
--   JobRules.nextOpenStop(stops, withYou, position, pinned, current)   the stop the GPS shows
--
-- 5.3, the newspaper round (Config.Jobs.Round; tested in tests/deliveries_test.luau):
--   JobRules.roundPay(papers, distance, bike)   what a round pays ($5 steps; the no-miss tip comes on top)
--   JobRules.roundTime(distance, doors, bike)   its clock
--   JobRules.roundTip(misses)             the tip: Round.NoMissTip with no paper in the bushes, else 0
--   JobRules.tossMiss(distance)           the chance a paper tossed from `distance` studs lands in the bushes
--   JobRules.roundCheck(misses)           the result card's line for it ({ text, ok })
--
-- 6.7, the Courier Vest (Config.Kit tips; tested in tests/shop67_test.luau):
--   JobRules.kitTip(pay, share)           the customer's tip: `share` of the order's pay, rounded (0 without)
--   JobRules.kitTipCheck(tip)             the result card's line for it ({ text, ok })

local Config = require(script.Parent.Config)

local JobRules = {}

export type RoleInfo = { name: string, icon: string, why: string }
export type Check = { text: string, ok: boolean }
export type Rating = { stars: number, misses: number, checks: { Check } }
export type LicenceDef = { tier: number, level: number, jobs: number, atTier: number }

local OTHER_ROLES = { "long", "risky", "bulk" }

-- ── The board's choice ─────────────────────────────────────────────────────

function JobRules.roles(r: () -> number): { string }
	local count = math.clamp(math.floor(Config.Jobs.Choice.Offers), 1, 1 + #OTHER_ROLES)
	local out = { "short" }
	local pool = table.clone(OTHER_ROLES)
	while #out < count and #pool > 0 do
		local index = math.clamp(math.floor(r() * #pool) + 1, 1, #pool)
		table.insert(out, table.remove(pool, index) :: string)
	end
	-- (shown in this order: short, long, risky, bulk)
	local order: { [string]: number } = { short = 1, long = 2, risky = 3, bulk = 4 }
	table.sort(out, function(a: string, b: string): boolean
		return (order[a] or 9) < (order[b] or 9)
	end)
	return out
end

-- The drop's band (manhattan from the pick-up) for a role inside a tier's range low … high (MaxSpan wide at most).
function JobRules.window(role: string?, low: number, high: number): (number, number)
	local choice = Config.Jobs.Choice
	local top = math.min(high, low + choice.MaxSpan)
	local span = math.max(0, top - low)
	local band = if role == "short" then choice.Short elseif role == "long" then choice.Long else nil
	if not band then
		return low, high
	end
	return low + span * band[1], low + span * band[2]
end

local function percent(multiplier: number): string
	return `{math.floor((multiplier - 1) * 100 + 0.5)}%`
end

function JobRules.roleInfo(role: string?): RoleInfo?
	local choice = Config.Jobs.Choice
	if role == "short" then
		return { name = "Short & safe", icon = "🛡", why = "A short drive, the fewest pieces, no surprises: the safe pick." }
	elseif role == "long" then
		return { name = "Long haul", icon = "🛣", why = `A long drive across town: +{percent(choice.LongPay)} pay for the distance.` }
	elseif role == "risky" then
		return { name = "Risky", icon = "☠", why = `Trouble on the way, +{percent(choice.RiskyPay)} pay on top of it.` }
	elseif role == "bulk" then
		return { name = "Bulk order", icon = "📦", why = "The most pieces: a bigger car and more carrying, more pay." }
	elseif role == "round" then
		-- 5.3, the newspaper round (Config.Jobs.Round)
		return { name = "Paper round", icon = "📰", why = `The morning paper: pick up the bundle, toss one onto every porch on the street. No paper in the bushes: +${Config.Jobs.Round.NoMissTip} tip.` }
	end
	return nil
end

function JobRules.rerollFee(stars: number): number
	return Config.Jobs.Choice.RerollFee * math.max(1, math.floor(stars))
end

-- ── The rating ─────────────────────────────────────────────────────────────

-- condition 0 … 1 (the cargo), timeShare 0 … 1 (the clock left / the clock), wrecked (the car on the way), lost (the
-- pieces stolen or ruined). 4.8: freshness 0 … 1 for food (nil: not food), a miss below CargoRules.GoodFresh, two
-- below PoorFresh.
function JobRules.rate(condition: number, timeShare: number, wrecked: boolean, lost: number, freshness: number?): Rating
	local tuning = Config.Jobs.Rating
	local checks: { Check } = {}
	local misses = 0
	local clock = math.floor(math.clamp(timeShare, 0, 1) * 100 + 0.5)
	local onTime = timeShare >= tuning.OnTime
	table.insert(checks, { text = if onTime then `On time ({clock}% of the clock left)` else `Late: {clock}% of the clock left`, ok = onTime })
	if not onTime then
		misses += 1
	end
	local cargo = math.floor(math.clamp(condition, 0, 1) * 100 + 0.5)
	if condition >= tuning.GoodCondition then
		table.insert(checks, { text = `Cargo {cargo}%`, ok = true })
	elseif condition >= tuning.PoorCondition then
		misses += 1
		table.insert(checks, { text = `Cargo knocked about ({cargo}%)`, ok = false })
	else
		misses += 2
		table.insert(checks, { text = `Cargo badly damaged ({cargo}%)`, ok = false })
	end
	if freshness then
		local rules = Config.Jobs.CargoRules
		local fresh = math.floor(math.clamp(freshness, 0, 1) * 100 + 0.5)
		if freshness >= rules.GoodFresh then
			table.insert(checks, { text = `Fresh {fresh}%`, ok = true })
		elseif freshness >= rules.PoorFresh then
			misses += 1
			table.insert(checks, { text = `Going stale ({fresh}% fresh)`, ok = false })
		else
			misses += 2
			table.insert(checks, { text = `Stale ({fresh}% fresh)`, ok = false })
		end
	end
	table.insert(checks, { text = if wrecked then "The car was wrecked" else "No wreck", ok = not wrecked })
	if wrecked then
		misses += 1
	end
	if lost > 0 then
		misses += 1
		table.insert(checks, { text = `{lost} {if lost == 1 then "piece" else "pieces"} lost`, ok = false })
	end
	return { stars = math.clamp(3 - misses, 1, 3), misses = misses, checks = checks }
end

function JobRules.nextStreak(streak: number, stars: number): number
	if stars < 2 then
		return 0
	end
	return math.clamp(math.floor(streak), 0, 9998) + 1
end

function JobRules.streakBonus(streak: number): number
	local tuning = Config.Jobs.Rating
	return math.min(tuning.StreakMax, tuning.StreakStep * math.max(0, math.floor(streak)))
end

-- The pay of a job rated `stars` with the streak as it is after it: (the new total, the rating's part, the streak's
-- part). A ★ job gets no streak bonus (it ended the streak).
function JobRules.ratedPay(total: number, stars: number, streak: number): (number, number, number)
	local tuning = Config.Jobs.Rating
	local rate = tuning.Pay[math.clamp(stars, 1, 3)] or 1
	local ratingPart = math.floor(total * (rate - 1) + 0.5)
	local streakPart = if stars >= 2 then math.floor(total * JobRules.streakBonus(streak) + 0.5) else 0
	return math.max(0, total + ratingPart + streakPart), ratingPart, streakPart
end

function JobRules.ratedXp(xp: number, stars: number): number
	return math.floor(xp * (Config.Jobs.Rating.Xp[math.clamp(stars, 1, 3)] or 1) + 0.5)
end

function JobRules.stars(n: number): string
	local count = math.clamp(math.floor(n), 0, 3)
	return string.rep("★", count) .. string.rep("☆", 3 - count)
end

-- ── The licences ───────────────────────────────────────────────────────────

function JobRules.licence(tier: number): LicenceDef?
	for _, def in Config.Jobs.Licences do
		if def.tier == tier then
			return def
		end
	end
	return nil
end

-- (jobs counted, jobs needed) toward the tier's licence; (0, 0) for a tier without one.
function JobRules.progress(tier: number, counts: { [string]: number }): (number, number)
	local def = JobRules.licence(tier)
	if not def then
		return 0, 0
	end
	return math.min(def.jobs, counts[tostring(tier)] or 0), def.jobs
end

-- A tier without a licence is open (its level is checked on its own); with one: held already, or the level and the
-- jobs are there (the server marks it held then).
function JobRules.hasLicence(tier: number, level: number, held: { [string]: boolean }, counts: { [string]: number }): boolean
	local def = JobRules.licence(tier)
	if not def or held[tostring(tier)] then
		return true
	end
	local have, need = JobRules.progress(tier, counts)
	return level >= def.level and have >= need
end

-- A job rated `stars` at danger `tier` counts toward every licence it is good for (★★ or better, at its atTier or
-- higher), up to the jobs it needs. Returns the tiers whose count grew.
function JobRules.countJob(counts: { [string]: number }, tier: number, stars: number): { number }
	local grew: { number } = {}
	if stars < 2 then
		return grew
	end
	for _, def in Config.Jobs.Licences do
		local key = tostring(def.tier)
		local have = counts[key] or 0
		if tier >= def.atTier and have < def.jobs then
			counts[key] = have + 1
			table.insert(grew, def.tier)
		end
	end
	return grew
end

-- The grandfather rule (a save from before 4.7, which has no licences saved): a driver who has delivered at least
-- once (deliveries > 0) and whose level already opens a licensed tier (level >= the licence's level) holds that
-- licence. A fresh driver (no deliveries) earns them like everybody.
function JobRules.grandfather(level: number, deliveries: number): { [string]: boolean }
	local held: { [string]: boolean } = {}
	if deliveries <= 0 then
		return held
	end
	for _, def in Config.Jobs.Licences do
		if level >= def.level then
			held[tostring(def.tier)] = true
		end
	end
	return held
end

-- ── 4.8: cargo with rules ──────────────────────────────────────────────────

local RULE_ORDER = { "fragile", "food", "heavy", "cash", "people" }

function JobRules.cargoRules(kind: string?, look: string?, business: string?): { string }
	local tuning = Config.Jobs.CargoRules
	local set: { [string]: boolean } = {}
	local empty: { string } = {}
	local lists: { { string } } = {
		(if look then tuning.Looks[look] else nil) or empty,
		(if kind then tuning.Kinds[kind] else nil) or empty,
		(if business then tuning.Businesses[business] else nil) or empty,
	}
	for _, list in lists do
		for _, rule in list do
			set[rule] = true
		end
	end
	local out: { string } = {}
	for _, rule in RULE_ORDER do
		if set[rule] then
			table.insert(out, rule)
		end
	end
	return out
end

function JobRules.hasRule(rules: { string }?, rule: string): boolean
	return rules ~= nil and table.find(rules, rule) ~= nil
end

function JobRules.ruleInfo(rule: string): RoleInfo?
	if rule == "fragile" then
		return { name = "Fragile", icon = "🥚", why = "Brake gently, no bumps: hard braking and knocks cost condition." }
	elseif rule == "food" then
		return { name = "Food", icon = "🍕", why = "It goes stale on the way: the freshness counts in the rating and the pay. A Cooler Box keeps it fresh longer." }
	elseif rule == "heavy" then
		return { name = "Heavy", icon = "🏋", why = "Carried by hand alone you barely walk: take the hand trolley, or lift it with a crew mate." }
	elseif rule == "cash" then
		return { name = "Cash", icon = "💰", why = "Bandits want it: more chases and roadblocks, and sooner." }
	elseif rule == "people" then
		return { name = "Passengers", icon = "👥", why = "Bumps make them complain: every bump costs condition." }
	end
	return nil
end

function JobRules.rulesText(rules: { string }?): string?
	if not rules or #rules == 0 then
		return nil
	end
	local parts: { string } = {}
	for _, rule in rules do
		local info = JobRules.ruleInfo(rule)
		if info then
			table.insert(parts, `{info.icon} {string.upper(info.name)}: {info.why}`)
		end
	end
	return if #parts > 0 then table.concat(parts, "  ") else nil
end

function JobRules.ruleLine(rules: { string }?, freshness: number?, cooler: boolean?): string?
	if not rules or #rules == 0 then
		return nil
	end
	local parts: { string } = {}
	for _, rule in rules do
		if rule == "food" then
			local fresh = math.floor(math.clamp(freshness or 1, 0, 1) * 100 + 0.5)
			table.insert(parts, `Fresh {fresh}%{if cooler then " (cooler)" else ""}`)
		elseif rule == "fragile" then
			table.insert(parts, "Fragile: brake gently")
		elseif rule == "heavy" then
			table.insert(parts, "Heavy: trolley or two to lift")
		elseif rule == "cash" then
			table.insert(parts, "Cash: bandits want it")
		elseif rule == "people" then
			table.insert(parts, "Passengers: no bumps")
		end
	end
	return if #parts > 0 then table.concat(parts, " · ") else nil
end

-- The car's speed (studs / s, flat) a tick ago and now, `dt` apart: a bump (the speed gone faster than any brake), hard
-- braking (from BrakeSpeed or faster), or nil.
function JobRules.jolt(before: number, now: number, dt: number): string?
	local tuning = Config.Jobs.CargoRules
	if dt <= 0 then
		return nil
	end
	local drop = (before - now) / dt
	if drop >= tuning.BumpDecel then
		return "bump"
	elseif drop >= tuning.BrakeDecel and before >= tuning.BrakeSpeed then
		return "brake"
	end
	return nil
end

local function strapped(loss: number, straps: boolean?): number
	return if straps then loss * Config.GearTuning.StrapsLoss else loss
end

function JobRules.joltLoss(rules: { string }?, jolt: string?, straps: boolean?): number
	local tuning = Config.Jobs.CargoRules
	if not jolt then
		return 0
	end
	local loss = 0
	if JobRules.hasRule(rules, "fragile") then
		loss += if jolt == "bump" then tuning.FragileBump else tuning.FragileBrake
	end
	if JobRules.hasRule(rules, "people") and jolt == "bump" then
		loss += tuning.PeopleBump
	end
	return strapped(loss, straps)
end

function JobRules.damageLoss(rules: { string }?, base: number, speed: number, straps: boolean?): number
	local tuning = Config.Jobs.CargoRules
	local loss = math.max(0, base)
	if JobRules.hasRule(rules, "fragile") and speed >= tuning.HitSpeed then
		loss += tuning.FragileHit
	end
	return strapped(loss, straps)
end

-- 5.0: `warm` multiplies it too (6.4: the thermal bag, Transport.mixWarm; 6.7: the jacket is gone).
function JobRules.freshDrain(tier: number, seconds: number, cooler: boolean?, warm: number?): number
	local drain = Config.Jobs.CargoRules.FoodDrain
	local perMinute = drain[math.clamp(math.floor(tier), 1, #drain)] or 0
	local loss = perMinute * math.max(0, seconds) / 60 * math.clamp(warm or 1, 0, 1)
	return if cooler then loss * Config.GearTuning.CoolerDrain else loss
end

function JobRules.freshPay(freshness: number): number
	local low = Config.Jobs.CargoRules.FreshPayMin
	return low + (1 - low) * math.clamp(freshness, 0, 1)
end

-- 6.4, fragile pieces on foot: what knocked them this tick. `fell` the fastest the courier fell (studs / s down) since
-- they left the ground, `landed` the feet are on the ground again, `lostHealth` the health lost since the last tick.
-- "fall" (a landing faster than FootFallSpeed), "hit" (FootHitMin or more at once) or nil.
function JobRules.footKnock(fell: number, landed: boolean, lostHealth: number): string?
	local tuning = Config.Jobs.CargoRules
	if landed and fell >= tuning.FootFallSpeed then
		return "fall"
	elseif lostHealth >= tuning.FootHitMin then
		return "hit"
	end
	return nil
end

-- 6.4: the condition such a knock costs each order with an unpadded fragile piece with you (padded: none).
function JobRules.knockLoss(knock: string?, padded: boolean?): number
	if padded or knock == nil then
		return 0
	end
	local tuning = Config.Jobs.CargoRules
	return if knock == "fall" then tuning.FootFall elseif knock == "hit" then tuning.FootHit else 0
end

-- ── 4.8: multi-drop ────────────────────────────────────────────────────────

-- How many drops a board delivery of danger `tier` with `pieces` pieces and `receivers` different people to take them
-- gets: 1 (an ordinary one) unless r1 < MultiDrop.Chance[tier]; then 2 … Max[tier] (by r2), never more than the
-- pieces or the receivers.
function JobRules.dropCount(tier: number, pieces: number, receivers: number, r1: number, r2: number): number
	local tuning = Config.Jobs.MultiDrop
	local chance = tuning.Chance[tier] or 0
	local most = math.min(tuning.Max[tier] or 1, math.floor(pieces), math.floor(receivers))
	if r1 >= chance or most < 2 then
		return 1
	end
	return math.clamp(2 + math.floor(math.clamp(r2, 0, 0.999) * (most - 1)), 2, most)
end

-- The stop every piece goes to, in the order the pieces are made: needs[i] pieces to the stop first + i − 1.
function JobRules.destinations(needs: { number }, first: number): { number }
	local out: { number } = {}
	for index, need in needs do
		for _ = 1, math.max(0, math.floor(need)) do
			table.insert(out, first + index - 1)
		end
	end
	return out
end

function JobRules.multiDropPay(drops: number): number
	return Config.Jobs.MultiDrop.PayPerStop * math.max(0, math.floor(drops) - 1)
end

-- ── 4.8: road events ───────────────────────────────────────────────────────

local EVENT_ORDER = { "survivor", "addon", "roadblock" }

function JobRules.pickEvent(r1: number, r2: number): string?
	local tuning = Config.Jobs.RoadEvents
	if r1 >= tuning.Chance then
		return nil
	end
	local total = 0
	for _, id in EVENT_ORDER do
		total += math.max(0, tuning.Weights[id] or 0)
	end
	if total <= 0 then
		return nil
	end
	local at = math.clamp(r2, 0, 0.999999) * total
	for _, id in EVENT_ORDER do
		local weight = math.max(0, tuning.Weights[id] or 0)
		if at < weight then
			return id
		end
		at -= weight
	end
	return nil
end

function JobRules.eventAfter(r: number): number
	local after = Config.Jobs.RoadEvents.After
	return after[1] + (after[2] - after[1]) * math.clamp(r, 0, 1)
end

function JobRules.survivorBonus(stars: number): number
	return Config.Jobs.RoadEvents.SurvivorBonus * math.max(1, math.floor(stars))
end

function JobRules.addOnFits(inCar: number, coming: number, capacity: number): boolean
	return inCar + coming + 1 <= capacity
end

-- ── 5.0: the ON FOOT jobs (Config.Jobs.Foot) ────────────────────────────────

-- 5.1: the numbers of a light job (Config.Jobs.Foot, or Config.Jobs.Bike for a BIKE job: the same fields). Each
-- function below takes one as its last argument; without it, Foot.
export type LightRules = {
	Pieces: { number },
	BasePay: number,
	PayPerStud: number,
	PayPerPiece: number,
	PayMin: number,
	PayMax: number,
	PayTop: number,
	TimeBase: number,
	Speed: number,
}

-- What a foot job pays: BasePay + PayPerStud × the walk (the route, manhattan) + PayPerPiece a piece, kept within
-- PayMin … PayMax, then × `multiplier` (the role's, the modifier's) but never over PayMax × PayTop, rounded to $5.
function JobRules.footPay(distance: number, pieces: number, multiplier: number?, rules: LightRules?): number
	local foot: LightRules = rules or Config.Jobs.Foot
	local base = foot.BasePay + foot.PayPerStud * math.max(0, distance) + foot.PayPerPiece * math.max(0, math.floor(pieces))
	local pay = math.clamp(base, foot.PayMin, foot.PayMax) * math.max(0, multiplier or 1)
	return math.min(math.floor(pay / 5 + 0.5) * 5, math.floor(foot.PayMax * foot.PayTop / 5) * 5)
end

-- A foot job's clock: TimeBase + the walk at Speed studs / s (× the modifier's timeMultiplier) + the handling, whole
-- seconds.
function JobRules.footTime(distance: number, handling: number, timeMultiplier: number?, rules: LightRules?): number
	local foot: LightRules = rules or Config.Jobs.Foot
	local walk = math.max(0, distance) / math.max(1, foot.Speed) * (timeMultiplier or 1)
	return math.floor(foot.TimeBase + walk + math.max(0, handling) + 0.5)
end

-- The pieces of a foot job: `wanted` (the business's pick) within Foot.Pieces and never more than `room` (what you
-- carry: Transport.handsRoom), at least 1. (5.1, a bike job: within Bike.Pieces and what the bike holds.)
function JobRules.footPieces(wanted: number, room: number, rules: LightRules?): number
	local band = (rules or Config.Jobs.Foot).Pieces
	return math.max(1, math.min(math.clamp(math.floor(wanted), band[1], band[2]), math.floor(room)))
end

-- 5.1: a bike job's XP: a ★ job's (Levels.jobXp of its tier) + Config.Jobs.Bike.XpBonus.
function JobRules.bikeXp(xp: number): number
	return xp + Config.Jobs.Bike.XpBonus
end

-- 5.7, the step up to a car (Config.Jobs.CarStep): is this a ★ board delivery in your own car (mode "car", tier 1, no
-- job type of its own: not a special, an employer's or a mission)?
function JobRules.carStep(mode: string, tier: number, special: boolean): boolean
	return mode == "car" and tier == 1 and not special
end

-- 5.7: such a delivery's XP: + CarStep.XpBonus.
function JobRules.carStepXp(xp: number): number
	return xp + Config.Jobs.CarStep.XpBonus
end

-- 5.7: such a delivery's pieces: CarStep.Pieces (SHORT & SAFE the fewest, else r: 0 … 1 picks), never more than `room`
-- (what the player's car holds now; at least EasyMaxPieces: a player without a car sees the Rusty Van's load).
function JobRules.carStepPieces(role: string?, r: number, room: number?): number
	local band = Config.Jobs.CarStep.Pieces
	local wanted = if role == "short" then band[1] else band[1] + math.floor(math.clamp(r, 0, 0.999999) * (band[2] - band[1] + 1))
	return math.min(wanted, math.max(Config.Jobs.EasyMaxPieces, math.floor(room or 0)))
end

-- ── 5.2: several orders at once (Config.Jobs.Orders) ───────────────────────

-- What makes an offer stackable (server/Jobs.luau fills it from the offer): its mode, its tier, and whether it is a
-- special (a job type of its own: a board special, an employer's, the Freight Run), a mission, the tutorial's, DUO,
-- and whether every stop is carried by hand (no horses, people or pallets).
export type StackInfo = {
	mode: string,
	tier: number,
	special: boolean,
	mission: boolean,
	tutorial: boolean,
	duo: boolean,
	carried: boolean,
	round: boolean?, -- 5.3: a newspaper round (one order on its own)
}

-- One stop of a running job as the GPS sees it: a pick-up or a drop of an order, done (or skipped), where it is.
export type StopState = { kind: string, order: number, done: boolean, x: number, z: number }

-- May an offer like this run beside other orders (and let others run beside it)? Ordinary board deliveries on foot, on
-- a bike, or in a car of the ★ … Orders.CarTiers tiers, carried by hand.
function JobRules.stackable(info: StackInfo): boolean
	if info.special or info.mission or info.tutorial or info.duo or info.round or not info.carried then
		return false
	end
	if info.mode == "foot" or info.mode == "bike" then
		return true
	end
	return info.mode == "car" and info.tier >= 1 and info.tier <= Config.Jobs.Orders.CarTiers
end

-- How many orders of this mode may be open at once (Orders.Max; 1 for a mode it does not know).
function JobRules.ordersMax(mode: string): number
	return math.max(1, math.floor(Config.Jobs.Orders.Max[mode] or 1))
end

-- The free room: what you can take (`room`) minus the pieces every open order still holds or will pick up.
function JobRules.orderRoom(room: number, outstanding: { number }): number
	local used = 0
	for _, pieces in outstanding do
		used += math.max(0, math.floor(pieces))
	end
	return math.max(0, math.floor(room) - used)
end

-- May an order of `pieces` pieces be added to `open` open orders of this mode with `free` room left? Else why:
-- "full" (Orders.Max reached) or "room" (it does not fit).
function JobRules.canAddOrder(mode: string, open: number, pieces: number, free: number): (boolean, string?)
	if open >= JobRules.ordersMax(mode) then
		return false, "full"
	end
	if pieces > free then
		return false, "room"
	end
	return true, nil
end

-- The board's button of an order that does not fit: "NO ROOM (3/4 slots)" (used of room) or "ORDERS FULL (2/2)".
function JobRules.orderButton(why: string?, used: number, room: number, open: number, max: number): string
	if why == "full" then
		return `ORDERS FULL ({open}/{max})`
	end
	return `NO ROOM ({used}/{room} slots)`
end

-- Where a stop of a running job stands: "done" (or skipped), "open" (a pick-up; a drop whose order picked everything
-- up and some of its pieces are with you), "wait" (a drop whose order still has a pick-up to do) or "empty" (a drop
-- with every pick-up done and none of its pieces left: nothing to bring there). `withYou[index]`: the pieces for that
-- stop in hands, the pack, the vehicle or put down.
function JobRules.stopOpen(stops: { StopState }, index: number, withYou: { [number]: number }): string
	local stop = stops[index]
	if not stop or stop.done then
		return "done"
	end
	if stop.kind ~= "drop" then
		return "open"
	end
	for _, other in stops do
		if other.order == stop.order and other.kind ~= "drop" and not other.done then
			return "wait"
		end
	end
	return if (withYou[index] or 0) > 0 then "open" else "empty"
end

local function gap(stop: StopState, position: { x: number, z: number }): number
	local dx, dz = stop.x - position.x, stop.z - position.z
	return math.sqrt(dx * dx + dz * dz)
end

-- The stop the GPS shows: the open stop whose circle you are at (Orders.AtStop studs, the nearest), else the nearest
-- open stop of the `pinned` order, else the nearest open stop; `current` (the one shown now) stays unless another is
-- Orders.Hysteresis studs nearer. Nil when nothing is open.
function JobRules.nextOpenStop(stops: { StopState }, withYou: { [number]: number }, position: { x: number, z: number }, pinned: number?, current: number?): number?
	local tuning = Config.Jobs.Orders
	local open: { number } = {}
	for index in stops do
		if JobRules.stopOpen(stops, index, withYou) == "open" then
			table.insert(open, index)
		end
	end
	table.sort(open)
	if #open == 0 then
		return nil
	end
	local function nearest(list: { number }): (number?, number)
		local best: number?, bestGap = nil, math.huge
		for _, index in list do
			local d = gap(stops[index], position)
			if d < bestGap then
				best, bestGap = index, d
			end
		end
		return best, bestGap
	end
	-- At a circle: that stop.
	local here, hereGap = nearest(open)
	if here and hereGap <= tuning.AtStop then
		return here
	end
	-- The pinned order's stops, if it has an open one.
	local pool = open
	if pinned then
		local mine: { number } = {}
		for _, index in open do
			if stops[index].order == pinned then
				table.insert(mine, index)
			end
		end
		if #mine > 0 then
			pool = mine
		end
	end
	local best, bestGap = nearest(pool)
	if current and table.find(pool, current) and current ~= best then
		if gap(stops[current], position) <= bestGap + tuning.Hysteresis then
			return current
		end
	end
	return best
end

-- ── 5.3: the newspaper round (Config.Jobs.Round) ───────────────────────────

-- PayBase + PayPerPaper a paper + PayPerStud × the route (manhattan), × BikePay by bike, in $5 steps.
function JobRules.roundPay(papers: number, distance: number, bike: boolean?): number
	local round = Config.Jobs.Round
	local pay = round.PayBase + round.PayPerPaper * math.max(0, math.floor(papers)) + round.PayPerStud * math.max(0, distance)
	if bike then
		pay *= round.BikePay
	end
	return math.floor(pay / 5 + 0.5) * 5
end

-- TimeBase + the route at the light job's Speed (Foot or Bike) + TimePerDoor a door, whole seconds.
function JobRules.roundTime(distance: number, doors: number, bike: boolean?): number
	local round = Config.Jobs.Round
	local speed = if bike then Config.Jobs.Bike.Speed else Config.Jobs.Foot.Speed
	return math.floor(round.TimeBase + math.max(0, distance) / math.max(1, speed) + round.TimePerDoor * math.max(0, doors) + 0.5)
end

function JobRules.roundTip(misses: number): number
	return if misses <= 0 then Config.Jobs.Round.NoMissTip else 0
end

function JobRules.roundCheck(misses: number): Check
	if misses <= 0 then
		return { text = `Every paper on its porch: +${Config.Jobs.Round.NoMissTip} tip`, ok = true }
	end
	return { text = `{misses} {if misses == 1 then "paper" else "papers"} in the bushes: no tip`, ok = false }
end

-- 6.7, the Courier Vest's tip (Config.Kit tips, Transport.tipShare): `share` of an order's pay (after its rating and
-- streak), rounded; 0 without a share or a pay. server/Jobs.luau payOrder adds it and a line in the rating's checks.
function JobRules.kitTip(pay: number, share: number): number
	if pay ~= pay or share ~= share or pay <= 0 or share <= 0 then
		return 0
	end
	return math.floor(pay * math.min(share, 1) + 0.5)
end

function JobRules.kitTipCheck(tip: number): Check
	return { text = `Courier Vest: the customer tips +${math.max(0, math.floor(tip))}`, ok = true }
end

-- Within SureToss every paper lands on the porch; from there to TossRange the chance of the bushes grows to
-- MissAtRange (and stays there beyond).
function JobRules.tossMiss(distance: number): number
	local round = Config.Jobs.Round
	if distance <= round.SureToss then
		return 0
	end
	local share = math.clamp((distance - round.SureToss) / math.max(1, round.TossRange - round.SureToss), 0, 1)
	return share * round.MissAtRange
end

-- 5.2 review: an order as a crash, a hit or a failed job sees it: its id, still open, its pieces handed over, and
-- whether something was done for it (a stop done, a piece with you).
export type OrderWork = { id: number, open: boolean, delivered: number, progress: boolean }

-- The open orders a condition loss or a wreck reaches. On a run of stops in any order (`free`) only the ones with
-- pieces in the vehicle (`inside[id]` > 0): an order not picked up yet (or all handed over) keeps its own; a job of
-- stops one after the other: every open order (its only one, as before).
function JobRules.ordersHit(orders: { OrderWork }, inside: { [number]: number }, free: boolean): { number }
	local out: { number } = {}
	for _, order in orders do
		if order.open and (not free or (inside[order.id] or 0) > 0) then
			table.insert(out, order.id)
		end
	end
	return out
end

-- What a failed job's XP counts: the pieces of the orders still open (the ones paid were counted with their pay) and
-- the kills no order paid; worked = one of those, or something done for an open order (a job cancelled right after
-- accepting gives none).
function JobRules.failedWork(orders: { OrderWork }, unpaidKills: number): (number, boolean)
	local delivered, worked = 0, unpaidKills > 0
	for _, order in orders do
		if order.open then
			delivered += math.max(0, order.delivered)
			worked = worked or order.delivered > 0 or order.progress
		end
	end
	return delivered, worked
end

return JobRules
