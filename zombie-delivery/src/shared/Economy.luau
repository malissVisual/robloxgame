--!strict
-- The maths of money and stats: what an upgrade costs, what a car / gun / car gun does with the upgrades, what
-- fires from a car seat, what a job pays, how big its zombie waves are. Pure functions (no Roblox API), shared by
-- the server, the client UI and the tests.

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
	splash: number,
	pierce: number, -- 3.1: how many more enemies a round goes through after the first (0: it stops at the first)
}

export type Payout = {
	base: number,
	conditionPay: number,
	fastBonus: number,
	killBonus: number,
	nightBonus: number, -- finished at night (Config.DayNight.NightPay)
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

function Economy.findCarGun(id: string): Config.CarGunDef?
	for _, gun in Config.CarGuns do
		if gun.id == id then
			return gun
		end
	end
	return nil
end

-- A pistol, the revolver, the SMG: fired with one hand, so also out of a car window.
function Economy.oneHanded(weaponId: string): boolean
	local def = Economy.findWeapon(weaponId)
	return def ~= nil and def.oneHanded == true
end

-- Does a car gun fit on this car's roof (CarDef.mount)?
function Economy.canMount(carId: string): boolean
	local def = Economy.findCar(carId)
	return def ~= nil and def.mount == true
end

-- What a shot is fired from:
--   "hand"    on foot, the gun in your hand
--   "cargun"  the driver of a car with a car gun installed (carGunId): the roof turret
--   "window"  any seat, a one-handed gun out of the side window (the driver too, when the car has no car gun)
--   nil       a two-handed gun in a seat: it does not fire
function Economy.fireMode(seated: boolean, driving: boolean, weaponId: string, carGunId: string?): string?
	if not seated then
		return "hand"
	end
	if driving and carGunId ~= nil and Economy.findCarGun(carGunId) ~= nil then
		return "cargun"
	end
	if Economy.oneHanded(weaponId) then
		return "window"
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

function Economy.findItem(id: string): Config.ItemDef?
	for _, item in Config.Items do
		if item.id == id then
			return item
		end
	end
	return nil
end

function Economy.findPaint(id: string): Config.PaintDef?
	for _, paint in Config.Paints do
		if paint.id == id then
			return paint
		end
	end
	return nil
end

function Economy.findModifier(id: string): Config.ModifierDef?
	for _, modifier in Config.Jobs.Modifiers do
		if modifier.id == id then
			return modifier
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
		turn = def.turn * Economy.multiplier(upgrades, "handling"),
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
		splash = def.splash,
		pierce = def.pierce or 0,
	}
end

-- A car gun with the Gun Damage / Fire Rate upgrades, like weaponStats.
function Economy.carGunStats(gunId: string, upgrades: Upgrades): WeaponStats
	local def = Economy.findCarGun(gunId) or Config.CarGuns[1]
	return {
		damage = def.damage * Economy.multiplier(upgrades, "damage"),
		interval = 1 / (def.fireRate * Economy.multiplier(upgrades, "firerate")),
		range = def.range,
		pellets = def.pellets,
		spread = def.spread,
		splash = def.splash,
		pierce = 0,
	}
end

-- Damage of running a zombie over at this speed.
function Economy.ramDamage(speed: number, ramPower: number): number
	if speed < Config.Horde.RamMinSpeed then
		return 0
	end
	return speed * Config.Horde.RamDamagePerSpeed * ramPower
end

-- A job's zombie waves (Config TierDef wave*). multiplier = the modifier's spawnMultiplier (WANTED: 2, else 1):
-- the waves get √multiplier bigger and come √multiplier as often (about multiplier × the zombies), and the cap of
-- the alive ones grows by multiplier.
function Economy.waveSize(tier: Config.TierDef, wave: number, multiplier: number?): number
	local size = math.min(tier.waveBase + tier.waveGrow * (math.max(1, math.floor(wave)) - 1), tier.waveMax)
	return math.max(1, math.floor(size * math.sqrt(multiplier or 1) + 0.5))
end

function Economy.waveEvery(tier: Config.TierDef, multiplier: number?): number
	return tier.waveEvery / math.sqrt(multiplier or 1)
end

function Economy.waveAlive(tier: Config.TierDef, multiplier: number?): number
	return math.floor(tier.waveAlive * (multiplier or 1) + 0.5)
end

-- payMultiplier / timeMultiplier come from the job's modifier (1 without one).
function Economy.jobPay(tier: Config.TierDef, distance: number, payMultiplier: number?): number
	return math.floor((tier.basePay + distance * tier.payPerStud) * (payMultiplier or 1) / 5 + 0.5) * 5
end

function Economy.timeLimit(distance: number, timeMultiplier: number?): number
	return math.floor((Config.Jobs.TimeBase + distance * Config.Jobs.TimePerStud) * (timeMultiplier or 1) + 0.5)
end

-- What every member of a delivery crew gets: (the driver's total, each passenger's share).
function Economy.crewSplit(total: number, passengers: number): (number, number)
	local jobs = Config.Jobs
	local driver = math.floor(total * (1 + jobs.CrewDriverBonus * passengers) + 0.5)
	local share = if passengers > 0 then math.floor(total * jobs.CrewShare + 0.5) else 0
	return driver, share
end

function Economy.findJobType(id: string): Config.JobTypeDef?
	for _, jobType in Config.JobTypes do
		if jobType.id == id then
			return jobType
		end
	end
	return nil
end

function Economy.findEmployer(id: string): Config.EmployerDef?
	for _, employer in Config.Employers do
		if employer.id == id then
			return employer
		end
	end
	return nil
end

-- A job's pieces split over its stops, the first stops take the odd ones: 4 over 3 = { 2, 1, 1 }.
function Economy.splitPieces(total: number, parts: number): { number }
	local list = {}
	if parts <= 0 then
		return list
	end
	local each = math.floor(total / parts)
	local extra = total - each * parts
	for n = 1, parts do
		table.insert(list, each + (if n <= extra then 1 else 0))
	end
	return list
end

-- What a job pays when `delivered` of its `total` pieces arrived (stolen and wrecked ones are missing).
function Economy.cargoPay(pay: number, delivered: number, total: number): number
	if total <= 0 then
		return pay
	end
	return math.floor(pay * math.clamp(delivered / total, 0, 1) / 5 + 0.5) * 5
end

-- Extra seconds on the clock for handling `pieces` at a stop that way (carry | lead | board | serve).
function Economy.handlingTime(mode: string, pieces: number): number
	return (Config.Cargo.TimePerPiece[mode] or 0) * math.max(0, pieces)
end

-- Pieces still in the ice cream truck after `served` of its `stops` serve stops (it empties evenly).
function Economy.serveLeft(total: number, stops: number, served: number): number
	if stops <= 0 then
		return 0
	end
	return math.ceil(total * math.max(0, stops - served) / stops - 1e-9)
end

-- condition 0 … 1 (cargo health), timeLeft and timeLimit in seconds. nightMultiplier (Economy.nightScale of
-- Config.DayNight.NightPay, 1 by day) adds the night bonus on top of everything else.
function Economy.payout(pay: number, condition: number, timeLeft: number, timeLimit: number, kills: number, nightMultiplier: number?): Payout
	local jobs = Config.Jobs
	local share = jobs.MinCondition + (1 - jobs.MinCondition) * math.clamp(condition, 0, 1)
	local conditionPay = math.floor(pay * share + 0.5)
	local fastBonus = 0
	if timeLimit > 0 and timeLeft / timeLimit >= jobs.FastShare then
		fastBonus = math.floor(pay * jobs.FastBonus + 0.5)
	end
	local killBonus = math.max(0, kills) * jobs.KillBonus
	local subtotal = conditionPay + fastBonus + killBonus
	local nightBonus = math.max(0, math.floor(subtotal * ((nightMultiplier or 1) - 1) + 0.5))
	return {
		base = pay,
		conditionPay = conditionPay,
		fastBonus = fastBonus,
		killBonus = killBonus,
		nightBonus = nightBonus,
		total = subtotal + nightBonus,
	}
end

-- A night multiplier (Config.DayNight NightPay / NightWaves / NightRoam) at this much night: factor 0 (day) = 1,
-- factor 1 (deep night) = the full multiplier, smoothly in between at dusk and dawn (DayNight.nightFactor).
function Economy.nightScale(multiplier: number, factor: number): number
	return 1 + (multiplier - 1) * math.clamp(factor, 0, 1)
end

-- The driver level a job needs: the job type's own level; a board special without one (the Winter Run) needs its
-- danger tier's level, like an ordinary delivery of that tier; an employer's job without one is open to everybody
-- who walks up to their board.
function Economy.jobLevel(jobType: Config.JobTypeDef?, tierIndex: number): number
	local tier = Config.Jobs.Tiers[tierIndex]
	local tierLevel = if tier then tier.level else 1
	if not jobType then
		return tierLevel
	end
	if jobType.level then
		return jobType.level
	end
	return if jobType.employer and not jobType.board then 1 else tierLevel
end

-- Is this job type on the job board (a special without an employer, or one marked board)?
function Economy.onBoard(jobType: Config.JobTypeDef): boolean
	return jobType.board == true or jobType.employer == nil
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

-- ── Missions (3.0, Config.Missions; server/Jobs.luau) ─────────────────────

-- A co-op mission (MissionDef.coop) with `members` crew members besides the owner: the pay × this (for everybody).
function Economy.coopPay(members: number): number
	return 1 + Config.Missions.CoopPayPerMember * math.max(0, members)
end

-- … and the enemies (wave sizes, foot waves, hordes) × this.
function Economy.coopEnemies(members: number): number
	return 1 + Config.Missions.CoopEnemyPerMember * math.max(0, members)
end

-- The guarded twist: the horde waiting at every stop of a mission of this danger level (GuardedHorde × the tier's
-- stars / 2, at least GuardedHorde), × the co-op enemy multiplier.
function Economy.guardedHorde(tier: Config.TierDef, multiplier: number?): number
	local base = Config.Missions.GuardedHorde
	local count = math.max(base, math.floor(base * tier.stars / 2 + 0.5))
	return math.max(1, math.floor(count * (multiplier or 1) + 0.5))
end

-- The kills a payout counts (Economy.payout's kills × KillBonus): the gunner twist makes every kill from a passenger
-- seat of the owner's car worth GunnerKillBonus kills.
function Economy.paidKills(kills: number, gunnerKills: number): number
	local extra = math.max(0, Config.Missions.GunnerKillBonus - 1) * math.clamp(gunnerKills, 0, math.max(0, kills))
	return math.max(0, kills) + extra
end

-- "0:23": a countdown on the HUD (the defend twist's HOLD OUT).
function Economy.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return `{s // 60}:{string.format("%02d", s % 60)}`
end

return Economy
