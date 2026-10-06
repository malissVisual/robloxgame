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
	end
	return nil
end

function JobRules.rerollFee(stars: number): number
	return Config.Jobs.Choice.RerollFee * math.max(1, math.floor(stars))
end

-- ── The rating ─────────────────────────────────────────────────────────────

-- condition 0 … 1 (the cargo), timeShare 0 … 1 (the clock left / the clock), wrecked (the car on the way), lost (the
-- pieces stolen or ruined).
function JobRules.rate(condition: number, timeShare: number, wrecked: boolean, lost: number): Rating
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

return JobRules
