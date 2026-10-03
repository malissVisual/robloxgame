--!strict
-- The maths of money and stats: what an upgrade costs, what a car / gun does with the upgrades,
-- what a job pays. Pure functions (no Roblox API), shared by the server, the client UI and the tests.

local Config = require(script.Parent.Config)

local Economy = {}

export type Upgrades = { [string]: number }

export type CarStats = {
	maxSpeed: number,
	accel: number,
	turn: number,
	health: number,
	ramPower: number,
}

export type WeaponStats = {
	damage: number,
	interval: number, -- seconds between shots
	range: number,
	pellets: number,
	spread: number,
}

export type Payout = {
	base: number,
	conditionPay: number,
	fastBonus: number,
	killBonus: number,
	total: number,
}

function Economy.findCar(id: string): Config.CarDef?
	for _, car in Config.Cars do
		if car.id == id then
			return car
		end
	end
	return nil
end

function Economy.findWeapon(id: string): Config.WeaponDef?
	for _, weapon in Config.Weapons do
		if weapon.id == id then
			return weapon
		end
	end
	return nil
end

function Economy.findUpgrade(id: string): Config.UpgradeDef?
	for _, upgrade in Config.Upgrades do
		if upgrade.id == id then
			return upgrade
		end
	end
	return nil
end

function Economy.level(upgrades: Upgrades, id: string): number
	return upgrades[id] or 0
end

-- The price of the next level, or nil when the track is maxed (or unknown).
function Economy.upgradeCost(id: string, currentLevel: number): number?
	local def = Economy.findUpgrade(id)
	if not def or currentLevel >= def.maxLevel then
		return nil
	end
	return math.floor(def.baseCost * def.costGrowth ^ currentLevel / 10 + 0.5) * 10
end

-- 1 + level × perLevel.
function Economy.multiplier(upgrades: Upgrades, id: string): number
	local def = Economy.findUpgrade(id)
	if not def then
		return 1
	end
	return 1 + math.min(Economy.level(upgrades, id), def.maxLevel) * def.perLevel
end

function Economy.carStats(carId: string, upgrades: Upgrades): CarStats
	local def = Economy.findCar(carId) or Config.Cars[1]
	local engine = Economy.multiplier(upgrades, "engine")
	return {
		maxSpeed = def.maxSpeed * engine,
		accel = def.accel * engine,
		turn = def.turn,
		health = math.floor(def.health * Economy.multiplier(upgrades, "armor")),
		ramPower = def.ramPower * Economy.multiplier(upgrades, "plow"),
	}
end

function Economy.weaponStats(weaponId: string, upgrades: Upgrades): WeaponStats
	local def = Economy.findWeapon(weaponId) or Config.Weapons[1]
	return {
		damage = def.damage * Economy.multiplier(upgrades, "damage"),
		interval = 1 / (def.fireRate * Economy.multiplier(upgrades, "firerate")),
		range = def.range,
		pellets = def.pellets,
		spread = def.spread,
	}
end

-- Damage of running a zombie over at this speed.
function Economy.ramDamage(speed: number, ramPower: number): number
	if speed < Config.Horde.RamMinSpeed then
		return 0
	end
	return speed * Config.Horde.RamDamagePerSpeed * ramPower
end

function Economy.jobPay(tier: Config.TierDef, distance: number): number
	return math.floor((tier.basePay + distance * tier.payPerStud) / 5 + 0.5) * 5
end

function Economy.timeLimit(distance: number): number
	return math.floor(Config.Jobs.TimeBase + distance * Config.Jobs.TimePerStud + 0.5)
end

-- condition 0 … 1 (cargo health), timeLeft and timeLimit in seconds.
function Economy.payout(pay: number, condition: number, timeLeft: number, timeLimit: number, kills: number): Payout
	local jobs = Config.Jobs
	local share = jobs.MinCondition + (1 - jobs.MinCondition) * math.clamp(condition, 0, 1)
	local conditionPay = math.floor(pay * share + 0.5)
	local fastBonus = 0
	if timeLimit > 0 and timeLeft / timeLimit >= jobs.FastShare then
		fastBonus = math.floor(pay * jobs.FastBonus + 0.5)
	end
	local killBonus = math.max(0, kills) * jobs.KillBonus
	return {
		base = pay,
		conditionPay = conditionPay,
		fastBonus = fastBonus,
		killBonus = killBonus,
		total = conditionPay + fastBonus + killBonus,
	}
end

-- Weighted pick from { kind = weight }, r in [0, 1).
function Economy.pickKind(kinds: { [string]: number }, r: number): string
	local total = 0
	local names = {}
	for name, weight in kinds do
		total += weight
		table.insert(names, name)
	end
	table.sort(names) -- pairs order is not stable, the pick must be
	local roll = r * total
	for _, name in names do
		roll -= kinds[name]
		if roll < 0 then
			return name
		end
	end
	return names[#names] or "walker"
end

return Economy
