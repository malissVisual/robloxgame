--!strict
-- 6.14, the GOLDEN ORDERS and the REGULARS' ORDERS (Config.Jobs.Golden, Config.Regulars.Order): an offer that comes
-- onto your board now and then, pays more and stays only a few minutes. One code path for both: the offer carries a
-- `specialOrder` (its Spec: kind "golden" | "regular", when it leaves the board, its pay and XP multipliers, a golden
-- run's danger). server/SpecialOrders.luau rolls and places them, server/Jobs.luau carries them (the board, the pay,
-- the danger), server/JobQueue.luau lets them expire out of NEXT UP, client/SpecialOrderUi.luau draws them. Pure (no
-- Roblox): tests/specialorders_test.luau.
--
--   SpecialOrders.tuning(kind)                 a kind's numbers: { every, chance, seconds, pay, xp, level }
--   SpecialOrders.roll(kind, r)                does a roll (r: 0 … 1) bring one
--   SpecialOrders.goldenPlan(reach, r)         a golden order's transport and tier for what the courier has (Reach):
--                                              riding your bike a bike run; a car of your own one of your two hardest
--                                              open car tiers (the hardest Golden.TopTier of the time); a bike; else on foot
--   SpecialOrders.regularPlans(reach, defs)    a regular's order's tries in order ({ mode, tier }) for the business's
--                                              ordinary deliveries (BusinessInfo: its tiers, light or not)
--   SpecialOrders.make(kind, now, tier, mode, business?)   an offer's Spec
--   SpecialOrders.pay(pay, spec)               the offer's pay × the Spec's, rounded to $5 (never less)
--   SpecialOrders.expired(spec, now), left(spec, now)      its time on the board is up / the seconds left
--   SpecialOrders.label(spec), perks(spec)     "★ GOLDEN ORDER", "×3 PAY · ×2 XP"
--   SpecialOrders.appearText(spec, name?, left?)   the toast when one comes onto the board (`left`: its seconds left)
--   SpecialOrders.strays(every, chance, max, golden)   a light run's stray walkers (Golden.Light on a golden one):
--                                              every, chance, max alive and the share of runners
--   SpecialOrders.resultLines(r)               a DeliveryResult's lines: { { text, money?, gold } } (golden, a regular's
--                                              order, the regular's bonus: r.special, server/Regulars.luau)
-- A Spec is descriptive on the client: the server decides the pay, the danger and the expiry.

local Config = require(script.Parent.Config)

local SpecialOrders = {}

export type Spec = {
	kind: string, -- "golden" | "regular"
	expiresAt: number, -- server time (workspace:GetServerTimeNow()): it leaves the board (and NEXT UP) then
	seconds: number, -- its whole time on the board
	pay: number, -- × the offer's pay (already in it)
	xp: number, -- × the XP when it is paid
	waves: number, -- a golden car run: × the waves' spawn multiplier (1 otherwise)
	boost: number, -- a golden car run: the bandits this many times as often (1 otherwise)
	light: boolean, -- a golden run on foot or by bike: its own stray walkers (Golden.Light)
	business: string?, -- a regular's order: its business (shared/Regulars.luau id)
}

-- What a courier can take now (server/Jobs.luau specialApi.reach): their level, the car tiers open to them (the level
-- and the licence), a car of their own, a bike of their own (at its level), riding the bike now.
export type Reach = { level: number, tiers: { number }, car: boolean, bike: boolean, riding: boolean }

-- One ordinary delivery of a business (Config.Jobs.Businesses): its tiers, and whether its look goes on foot / by bike.
export type BusinessInfo = { tiers: { number }, light: boolean }

export type Plan = { mode: string, tier: number }
export type Line = { text: string, money: number?, gold: boolean }

type Tuning = { every: number, chance: number, seconds: number, pay: number, xp: number, level: number }

function SpecialOrders.tuning(kind: string): Tuning
	if kind == "golden" then
		local golden = Config.Jobs.Golden
		return { every = golden.Every, chance = golden.Chance, seconds = golden.Seconds, pay = golden.Pay, xp = golden.Xp, level = golden.Level }
	end
	local order = Config.Regulars.Order
	return { every = order.Every, chance = order.Chance, seconds = order.Seconds, pay = order.Pay, xp = order.Xp, level = 1 }
end

function SpecialOrders.roll(kind: string, r: number): boolean
	return r < SpecialOrders.tuning(kind).chance
end

function SpecialOrders.goldenPlan(reach: Reach, r: number): (string, number)
	if reach.riding and reach.bike then
		return "bike", 1
	end
	local tiers = reach.tiers
	if reach.car and not reach.riding and #tiers > 0 then
		local top = tiers[#tiers]
		local below = tiers[#tiers - 1] or top
		return "car", if r < Config.Jobs.Golden.TopTier then top else below
	end
	if reach.bike then
		return "bike", 1
	end
	return "foot", 1
end

function SpecialOrders.regularPlans(reach: Reach, defs: { BusinessInfo }): { Plan }
	local out: { Plan } = {}
	local seen: { [string]: boolean } = {}
	local function add(mode: string, tier: number)
		local key = `{mode}{tier}`
		if not seen[key] then
			seen[key] = true
			table.insert(out, { mode = mode, tier = tier })
		end
	end
	local light = false
	local carTiers: { number } = {}
	for _, def in defs do
		light = light or def.light
		for _, tier in def.tiers do
			if table.find(reach.tiers, tier) and not table.find(carTiers, tier) then
				table.insert(carTiers, tier)
			end
		end
	end
	table.sort(carTiers, function(a: number, b: number): boolean
		return a > b
	end)
	if reach.riding and reach.bike and light then
		add("bike", 1)
	end
	if reach.car and not reach.riding then
		for _, tier in carTiers do
			add("car", tier)
		end
	end
	if reach.bike and light then
		add("bike", 1)
	end
	if light then
		add("foot", 1)
	end
	return out
end

-- Does danger level `tier` have bandits on the road (roadblocks, bandit cars)?
local function hasBandits(tier: number): boolean
	local def = Config.Jobs.Tiers[tier]
	return def ~= nil and (def.ambushEvery > 0 or def.chaseEvery > 0)
end

function SpecialOrders.make(kind: string, now: number, tier: number, mode: string, business: string?): Spec
	local tune = SpecialOrders.tuning(kind)
	local golden = Config.Jobs.Golden
	local car = mode == "car"
	local isGolden = kind == "golden"
	return {
		kind = if isGolden then "golden" else "regular",
		expiresAt = now + tune.seconds,
		seconds = tune.seconds,
		pay = tune.pay,
		xp = tune.xp,
		waves = if isGolden and car then golden.Waves[tier] or 1 else 1,
		boost = if isGolden and car and hasBandits(tier) then golden.Bandits[tier] or 1 else 1,
		light = isGolden and not car,
		business = business,
	}
end

function SpecialOrders.pay(pay: number, spec: Spec): number
	return math.max(pay, math.floor(pay * spec.pay / 5 + 0.5) * 5)
end

function SpecialOrders.expired(spec: any, now: number): boolean
	return type(spec) == "table" and (tonumber(spec.expiresAt) or 0) <= now
end

function SpecialOrders.left(spec: any, now: number): number
	return if type(spec) == "table" then math.max(0, (tonumber(spec.expiresAt) or 0) - now) else 0
end

local function times(value: number): string
	return if value == math.floor(value) then tostring(math.floor(value)) else string.format("%.1f", value)
end

function SpecialOrders.label(spec: any): string
	return if type(spec) == "table" and spec.kind == "golden" then "★ GOLDEN ORDER" else "★ REGULAR'S ORDER"
end

function SpecialOrders.perks(spec: any): string
	local pay = if type(spec) == "table" then tonumber(spec.pay) or 1 else 1
	local xp = if type(spec) == "table" then tonumber(spec.xp) or 1 else 1
	local parts = { `×{times(pay)} PAY` }
	if xp > 1 then
		table.insert(parts, `×{times(xp)} XP`)
	end
	if type(spec) == "table" and spec.kind == "golden" then
		table.insert(parts, "MORE DANGER")
	end
	return table.concat(parts, " · ")
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- The toast when one comes onto the board (`name`: a regular's order's business; `left`: its seconds left, else its
-- whole time).
function SpecialOrders.appearText(spec: any, name: string?, left: number?): string
	local seconds = left or (if type(spec) == "table" then tonumber(spec.seconds) or 0 else 0)
	if type(spec) == "table" and spec.kind == "golden" then
		return `★ A GOLDEN ORDER is on your board · {clock(seconds)} · {SpecialOrders.perks(spec)} · JOBS`
	end
	return `★ A REGULAR'S ORDER from {name or "a business you know"} is on your board · {clock(seconds)} · {SpecialOrders.perks(spec)}`
end

function SpecialOrders.strays(every: number, chance: number, max: number, golden: boolean): (number, number, number, number)
	if not golden then
		return every, chance, max, 0
	end
	local light = Config.Jobs.Golden.Light
	return every * light.Every, math.min(0.95, chance + light.Chance), max + light.Max, light.Runner
end

function SpecialOrders.resultLines(r: any): { Line }
	local out: { Line } = {}
	local special = if type(r) == "table" and r.success == true and type(r.special) == "table" then r.special else nil
	if not special then
		return out
	end
	local golden = special.golden
	if type(golden) == "table" then
		local xp = tonumber(golden.xp) or 1
		table.insert(out, { text = `★ GOLDEN ORDER ×{times(tonumber(golden.pay) or 1)}{if xp > 1 then ` · ×{times(xp)} XP` else ""}`, gold = true })
	end
	local order = special.regularOrder
	if type(order) == "table" then
		table.insert(out, { text = `★ REGULAR'S ORDER · {tostring(order.name or "a regular")} ×{times(tonumber(order.pay) or 1)}`, gold = true })
	end
	local regular = special.regular
	local money = if type(regular) == "table" then tonumber(regular.money) or 0 else 0
	if type(regular) == "table" and money > 0 then
		table.insert(out, { text = `Regular · {tostring(regular.name or "?")} ({tostring(regular.tier or "?")})`, money = money, gold = false })
	end
	return out
end

return SpecialOrders
