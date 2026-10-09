--!strict
-- 5.4, the fuel model (Config.Fuel): pure numbers the server (server/Fuel.luau: the burn, the pumps, the jerry can, the
-- tow), the client (client/Drive.luau: the crawl; client/FuelGauge.luau: the gauge) and tests/fuel_test.luau share.
--
--   * A car's tank (CarDef.tank, litres) and its burn (CarDef.burn, litres per 1,000 studs). A bike has neither: no fuel.
--   * Driving `studs` burns burn × studs / 1000 litres (6.12.7: ÷ Config.Fuel.Lasts, a tank goes 5 times as far); an
--     empty tank caps the top speed at CrawlSpeed.
--   * A pump pours PourRate litres a second and charges PricePerLitre for each, in whole dollars as it pours
--     (FuelMath.pourStep: never more than you can pay), the cents left over at the end (FuelMath.settle).
--   * The check that a tank lasts: a typical job of a tier is the middle of its pick-up drive plus the middle of its
--     drop range (FuelMath.jobDistance); a car is meant for the highest tier its level opens (FuelMath.tierFor).

local Config = require(script.Parent.Config)

local FuelMath = {}

local Tuning = Config.Fuel

-- Does this car take fuel at all (a car with a tank, never a bike)?
function FuelMath.hasFuel(def: Config.CarDef?): boolean
	return def ~= nil and def.bike ~= true and (def.tank or 0) > 0
end

-- The tank in litres (0: no fuel).
function FuelMath.tank(def: Config.CarDef?): number
	return if def and FuelMath.hasFuel(def) then def.tank or 0 else 0
end

-- Litres burnt driving `studs` (flat distance).
function FuelMath.burn(def: Config.CarDef?, studs: number): number
	if not def or not FuelMath.hasFuel(def) or studs ~= studs or studs <= 0 then
		return 0
	end
	return (def.burn or 0) * studs / 1000 / math.max(Tuning.Lasts or 1, 0.1)
end

-- Studs on a full tank.
function FuelMath.range(def: Config.CarDef?): number
	local burn = if def then def.burn or 0 else 0
	return if burn > 0 then FuelMath.tank(def) * 1000 / burn * math.max(Tuning.Lasts or 1, 0.1) else math.huge
end

-- The price of `litres`, in dollars (with cents).
function FuelMath.cost(litres: number): number
	return math.max(0, litres) * Tuning.PricePerLitre
end

-- The whole dollars charged for `litres` (the cents rounded up).
function FuelMath.charge(litres: number): number
	return math.ceil(FuelMath.cost(litres) - 1e-6)
end

-- The share of the tank (0 … 1; 0 without a tank).
function FuelMath.share(fuel: number, tank: number): number
	return if tank > 0 then math.clamp(fuel / tank, 0, 1) else 0
end

function FuelMath.isEmpty(fuel: number): boolean
	return fuel <= 1e-3
end

-- Under Config.Fuel.Low of the tank (an empty one is low too).
function FuelMath.isLow(fuel: number, tank: number): boolean
	return tank > 0 and FuelMath.share(fuel, tank) < Tuning.Low
end

-- The top speed a car may drive at with this much fuel: CrawlSpeed at most when the tank is empty.
function FuelMath.topSpeed(maxSpeed: number, fuel: number, tank: number): number
	if tank > 0 and FuelMath.isEmpty(fuel) then
		return math.min(maxSpeed, Tuning.CrawlSpeed)
	end
	return maxSpeed
end

-- One step of pouring at a pump: `missing` litres to fill, `seconds` of pouring, `poured` litres and `charged` whole
-- dollars so far this time, `money` the driver has. Returns the litres to pour now and the whole dollars to charge now
-- (the dollars the litres poured so far have reached; never more than the money: then fewer litres).
function FuelMath.pourStep(missing: number, seconds: number, poured: number, charged: number, money: number): (number, number)
	local want = math.min(Tuning.PourRate * math.max(0, seconds), math.max(0, missing))
	if want <= 1e-6 then
		return 0, 0
	end
	local price = Tuning.PricePerLitre
	local due = math.floor((poured + want) * price + 1e-6) - charged
	local purse = math.floor(math.max(0, money))
	if due > purse then
		-- Just what the money pays for (the litres poured then cost whole dollars: nothing left to settle).
		want = math.max(0, (charged + purse) / price - poured)
		due = purse
		if want <= 1e-6 then
			return 0, 0
		end
	end
	return want, math.max(0, due)
end

-- The dollars still owed when the pouring stops (the cents of the last litre rounded up).
function FuelMath.settle(poured: number, charged: number): number
	return math.max(0, FuelMath.charge(poured) - charged)
end

-- The tier (Config.Jobs.Tiers index) a car is meant for: the highest one its level opens.
function FuelMath.tierFor(def: Config.CarDef): number
	local level = def.level or 1
	local best = 1
	for index, tier in Config.Jobs.Tiers do
		if tier.level <= level then
			best = index
		end
	end
	return best
end

-- The studs of a typical job of a tier: the drive to the pick-up (the middle of PickupMinDistance … PickupMaxDistance)
-- and the delivery (the middle of the tier's drop range, MaxSpan wide at most: shared/JobRules.luau).
function FuelMath.jobDistance(tierIndex: number): number
	local tier = Config.Jobs.Tiers[tierIndex] or Config.Jobs.Tiers[1]
	local jobs = Config.Jobs
	local high = math.min(tier.maxDistance, tier.minDistance + jobs.Choice.MaxSpan)
	return (jobs.PickupMinDistance + jobs.PickupMaxDistance) / 2 + (tier.minDistance + high) / 2
end

-- How many typical jobs of its tier (or `tierIndex`) a full tank lasts.
function FuelMath.jobsPerTank(def: Config.CarDef, tierIndex: number?): number
	return FuelMath.range(def) / FuelMath.jobDistance(tierIndex or FuelMath.tierFor(def))
end

return FuelMath
