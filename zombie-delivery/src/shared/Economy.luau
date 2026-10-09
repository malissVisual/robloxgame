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
	ramGuard: number, -- 6.7: × the dent a ram survivor leaves on the car (the Ram Plow's bull bar: Economy.ramGuard)
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

-- (6.0: nil = no gun, a new courier's fists: nil)
function Economy.findWeapon(id: string?): Config.WeaponDef?
	if id == nil then
		return nil
	end
	for _, weapon in Config.Weapons do
		if weapon.id == id then
			return weapon
		end
	end
	return nil
end

-- 6.0: the first gun owned in Config.Weapons' order (weapons: profile.weapons), or nil: fists only. The gun put in
-- your hand when the one there went away (an exclusive taken back) or a save names none.
function Economy.firstWeapon(weapons: { [string]: boolean }): string?
	for _, weapon in Config.Weapons do
		if weapons[weapon.id] == true then
			return weapon.id
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
function Economy.oneHanded(weaponId: string?): boolean
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
--   nil       a two-handed gun in a seat: it does not fire; 6.0: no gun at all (weaponId nil: fists only) on foot or
--             in a seat without a car gun
function Economy.fireMode(seated: boolean, driving: boolean, weaponId: string?, carGunId: string?): string?
	if not seated then
		return if Economy.findWeapon(weaponId) ~= nil then "hand" else nil
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

-- 3.3: is this a car track (Config.Upgrades car: bought for one car, profile.carUpgrades) or a gun track (for all
-- your guns, profile.upgrades)?
function Economy.isCarUpgrade(id: string): boolean
	local def = Economy.findUpgrade(id)
	return def ~= nil and def.car == true
end

-- 3.3: the car tracks' levels of one car out of profile.carUpgrades (car id → track id → level); {} for none.
function Economy.carLevels(carUpgrades: { [string]: Upgrades }?, carId: string): Upgrades
	local levels = carUpgrades and carUpgrades[carId]
	return if type(levels) == "table" then levels else {}
end

-- 3.3: can this car take the car tracks? Every car you buy; not the employers' company vehicles.
function Economy.canUpgrade(carId: string): boolean
	local def = Economy.findCar(carId)
	return def ~= nil and not def.company
end

-- 3.3: an old save's global car-track levels (profile.upgrades before the car tracks were per car) go to every car
-- it owns that can take them (the higher level wins), and leave `upgrades` (only the gun tracks stay there).
-- Returns whether anything was moved.
function Economy.migrateCarUpgrades(upgrades: Upgrades, cars: { [string]: boolean }, carUpgrades: { [string]: Upgrades }): boolean
	local moved = false
	for _, def in Config.Upgrades do
		local level = upgrades[def.id]
		if def.car and level ~= nil then
			upgrades[def.id] = nil
			if level > 0 then
				for carId, owned in cars do
					if owned and Economy.canUpgrade(carId) then
						local levels = carUpgrades[carId] or {}
						carUpgrades[carId] = levels
						levels[def.id] = math.max(levels[def.id] or 0, math.min(level, def.maxLevel))
						moved = true
					end
				end
			end
		end
	end
	return moved
end

-- ── 3.5, the stages (Config.Cars stages) ─────────────────────────────────────
-- A car's stages are bought at Wrench Garage one after the other; stages[1] is stage 0 (the car as it is sold). The
-- stage is saved with the car's own levels: profile.carUpgrades[carId].stage.

local NO_STAGES: { Config.StageDef } = {}

-- The stages of a car, stage 0 first ({} for a car without them: the company vehicles).
function Economy.stages(carId: string): { Config.StageDef }
	local def = Economy.findCar(carId)
	return if def and def.stages and not def.company then def.stages else NO_STAGES
end

-- The last stage a car can reach (0: none to buy).
function Economy.maxStage(carId: string): number
	return math.max(0, #Economy.stages(carId) - 1)
end

-- The stage a car is at, out of its own levels (clamped to the stages it has).
function Economy.stageOf(carId: string, levels: Upgrades?): number
	local stage = if levels then Economy.level(levels, "stage") else 0
	return math.clamp(math.floor(stage), 0, Economy.maxStage(carId))
end

-- A stage of a car (0 = the car as it is sold), or nil.
function Economy.stageDef(carId: string, stage: number): Config.StageDef?
	return Economy.stages(carId)[stage + 1]
end

-- The price of the stage after `stage`, or nil when there is none.
function Economy.stageCost(carId: string, stage: number): number?
	local nextStage = Economy.stageDef(carId, stage + 1)
	return if nextStage then nextStage.price else nil
end

-- The cargo slots of a car at a stage (its own capacity without stages).
function Economy.stageCapacity(carId: string, stage: number): number
	local def = Economy.findCar(carId)
	if not def then
		return 0
	end
	local stageDef = Economy.stageDef(carId, stage)
	return if stageDef then stageDef.capacity else def.capacity
end

-- The most a car can ever hold (its last stage).
function Economy.maxCapacity(carId: string): number
	return Economy.stageCapacity(carId, Economy.maxStage(carId))
end

-- What the car is called at its stage: "Old Van · Work Van" ("Courier Van" while the stage has the car's name).
function Economy.carTitle(carId: string, levels: Upgrades?): string
	local def = Economy.findCar(carId)
	if not def then
		return carId
	end
	local stageDef = Economy.stageDef(carId, Economy.stageOf(carId, levels))
	return if stageDef and stageDef.name ~= def.name then `{def.name} · {stageDef.name}` else def.name
end

-- 3.4's cargo slots of the cars you could buy (their capacity before the stages): what a 3.4 save's car held.
local LEGACY_CAPACITY: { [string]: number } = {
	van = 4,
	courier = 4,
	highroof = 6,
	pickup = 4,
	boxtruck = 6,
	muscle = 2,
	armorvan = 4,
	rallyvan = 4,
}

-- A 3.4 save's car becomes a stage: the first one that holds at least the slots it had then (its 3.4 capacity plus
-- its Cargo Rack, `rack` levels, +1 slot each, bought: never fewer than were paid for); when no stage holds that many,
-- the first one with the car's most room (0 when no stage adds any, as on the Rally Van).
function Economy.legacyStage(carId: string, rack: number): number
	local last = Economy.maxStage(carId)
	local had = (LEGACY_CAPACITY[carId] or Economy.stageCapacity(carId, 0)) + math.max(0, rack)
	local best = 0
	for stage = 0, last do
		local capacity = Economy.stageCapacity(carId, stage)
		if capacity >= had then
			return stage
		end
		if capacity > Economy.stageCapacity(carId, best) then
			best = stage
		end
	end
	return best
end

-- 4.0: the Old Van got two more stages (Rusty → Patched → Work → Long Cargo). A save from 3.5 – 3.10 (before the
-- profile's vanStages mark) keeps the room it had: its stage then becomes the first stage now that holds as many slots
-- (the old stages' capacities below: Work 3 → the Work Van, Cargo 4 → the Long Cargo Van). Cars not listed keep their
-- stage. (A 3.4 save goes through legacyStage instead, already on the new stages.)
local STAGES_39: { [string]: { number } } = {
	van = { 2, 3, 4 },
}

function Economy.migrateStage40(carId: string, stage: number): number
	local old = STAGES_39[carId]
	if not old or stage <= 0 then
		return stage
	end
	local had = old[math.min(math.floor(stage), #old - 1) + 1]
	for next = 0, Economy.maxStage(carId) do
		if Economy.stageCapacity(carId, next) >= had then
			return math.max(next, math.min(math.floor(stage), Economy.maxStage(carId)))
		end
	end
	return Economy.maxStage(carId)
end

-- 4.0, freight: the pallets a car takes at a stage (StageDef.pallets wins over CarDef.pallets; 0: none).
function Economy.palletsOf(carId: string, stage: number?): number
	local def = Economy.findCar(carId)
	if not def then
		return 0
	end
	local stageDef = Economy.stageDef(carId, math.clamp(math.floor(stage or 0), 0, Economy.maxStage(carId)))
	if stageDef and stageDef.pallets ~= nil then
		return stageDef.pallets
	end
	return def.pallets or 0
end

-- 4.0: may this car take this car track? Every car you own takes them (Economy.canUpgrade). (4.6: the Hand Trolley
-- is gear now: Economy.gearFits.)
function Economy.upgradeFits(carId: string, upgradeId: string): boolean
	local _ = upgradeId
	return Economy.findCar(carId) ~= nil and Economy.canUpgrade(carId)
end

-- 4.0's question (a car-track level "trolley" ≥ 1 on a car that takes one). 4.6: the game asks the installed gear
-- (Economy.installedGear, Vehicles.hasGear); kept for older code reading old levels (tools/vehicle-preview's baseline).
function Economy.hasTrolley(carId: string, levels: Upgrades?): boolean
	return levels ~= nil and Economy.level(levels, "trolley") >= 1 and Economy.gearFits(carId, "trolley")
end

-- ── 4.6, gear (Config.Gear): bought per car, installed in its gear slots ──────────────────────────────────────
-- profile.carGear[carId][gearId] = "owned" (bought, in the garage's store) | "installed" (in one of the car's slots,
-- on the car). Installing and removing are free at Wrench Garage (server/Shops.luau); the live car shows what is
-- installed (server/Vehicles.luau Car.gear, Vehicles.hasGear).

export type CarGear = { [string]: { [string]: string } }

function Economy.findGear(id: string): Config.GearDef?
	for _, gear in Config.Gear do
		if gear.id == id then
			return gear
		end
	end
	return nil
end

-- The gear slots of a car at a stage: the stage's own gearSlots, else the car's, else 0 (the company vehicles).
function Economy.gearSlots(carId: string, stage: number): number
	local def = Economy.findCar(carId)
	if not def or def.company then
		return 0
	end
	local stageDef = Economy.stageDef(carId, math.clamp(math.floor(stage or 0), 0, Economy.maxStage(carId)))
	if stageDef and stageDef.gearSlots ~= nil then
		return stageDef.gearSlots
	end
	return def.gearSlots or 0
end

-- Does this piece of gear fit this car (one of yours with a gear slot, the CarDef flag it needs, not a car it is
-- not made for)? 5.1: bike gear (GearDef.bikeOnly) only on a bike (CarDef.bike), the car gear never on one.
function Economy.gearFits(carId: string, gearId: string): boolean
	local def = Economy.findCar(carId)
	local gear = Economy.findGear(gearId)
	if not def or not gear or def.company or Economy.gearSlots(carId, Economy.maxStage(carId)) <= 0 then
		return false
	end
	if (def.bike == true) ~= (gear.bikeOnly == true) then
		return false
	end
	local needs = gear.needs
	if needs and (def :: any)[needs] ~= true then
		return false
	end
	if gear.notOn and table.find(gear.notOn, carId) then
		return false
	end
	return true
end

-- What one car has of a piece: "installed", "owned" or nil (not bought; nil for gear that does not fit it).
function Economy.gearState(carGear: CarGear?, carId: string, gearId: string): string?
	local list = carGear and carGear[carId]
	local value = if type(list) == "table" then list[gearId] else nil
	if (value == "installed" or value == "owned") and Economy.gearFits(carId, gearId) then
		return value
	end
	return nil
end

-- The gear installed on one car (gear id → true), from profile.carGear.
function Economy.installedGear(carGear: CarGear?, carId: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, gear in Config.Gear do
		if Economy.gearState(carGear, carId, gear.id) == "installed" then
			out[gear.id] = true
		end
	end
	return out
end

-- How many of a car's gear slots are taken.
function Economy.gearUsed(carGear: CarGear?, carId: string): number
	local used = 0
	for _ in Economy.installedGear(carGear, carId) do
		used += 1
	end
	return used
end

-- 4.6, the Roof Rack: the extra cargo slots it gives a car with this gear installed for a piece of this look (only a
-- light one, Config.Cargo.LightLooks; 0 without a look).
function Economy.rackSlots(carId: string, installed: { [string]: boolean }?, look: string?): number
	if not installed or not installed.roofrack or not look or not Config.Cargo.LightLooks[look] then
		return 0
	end
	return if Economy.gearFits(carId, "roofrack") then Config.GearTuning.RoofRackSlots else 0
end

-- 5.1, bike gear: the extra light pieces its installed bike gear (GearDef.room: the basket, the panniers, the trailer)
-- gives a bike, for a light look or none (a bike takes nothing else); 0 for a car.
function Economy.bikeRoom(carId: string, installed: { [string]: boolean }?, look: string?): number
	local def = Economy.findCar(carId)
	if not def or def.bike ~= true or not installed or (look ~= nil and not Config.Cargo.LightLooks[look]) then
		return 0
	end
	local room = 0
	for _, gear in Config.Gear do
		if installed[gear.id] and gear.bikeOnly and Economy.gearFits(carId, gear.id) then
			room += math.max(0, math.floor(gear.room or 0))
		end
	end
	return room
end

-- 4.6: a save from 4.0 – 4.5 bought the Hand Trolley as an upgrade track (carUpgrades[carId].trolley = 1): every car
-- it owns with that level ≥ 1 that takes a trolley gets it installed. `saved` is the save's carUpgrades as stored.
function Economy.migrateGear(saved: any, cars: { [string]: boolean }): CarGear
	local out: CarGear = {}
	if type(saved) ~= "table" then
		return out
	end
	for carId, levels in saved do
		if type(carId) == "string" and cars[carId] and type(levels) == "table" then
			local level = levels.trolley
			if type(level) == "number" and level == level and level >= 1 and Economy.gearFits(carId, "trolley") then
				out[carId] = { trolley = "installed" }
			end
		end
	end
	return out
end

-- 4.0, the torque curve of a car pulling away (client/Drive.luau): how much of its accel it has at `share` (0 … 1) of
-- its top speed. A heavy van pulls away slowly from a standstill, is strongest in the mid-range and creeps up to its
-- top speed: 0.55 at rest, up to 1.35 by a third of the top speed, flat to 70 %, down to 0.4 at the top.
function Economy.torque(share: number): number
	local s = math.clamp(share, 0, 1)
	if s < 0.3 then
		return 0.55 + (1.35 - 0.55) * s / 0.3
	elseif s < 0.7 then
		return 1.35
	end
	return 1.35 - (1.35 - 0.4) * (s - 0.7) / 0.3
end

-- 4.0: the seconds from a standstill to `share` (default 0.97) of the top speed on that curve (stepped like the
-- client does, 60 times a second).
function Economy.timeToTop(maxSpeed: number, accel: number, share: number?): number
	if maxSpeed <= 0 or accel <= 0 then
		return 0
	end
	local goal = maxSpeed * (share or 0.97)
	local speed, t, dt = 0, 0, 1 / 60
	while speed < goal and t < 120 do
		speed = math.min(maxSpeed, speed + accel * Economy.torque(speed / maxSpeed) * dt)
		t += dt
	end
	return t
end

-- What would make room for `need` pieces when this car (at `stage`) holds fewer: its first stage that holds them (built
-- at Wrench Garage), else the dealer's cars that can (at some stage of theirs). For the "too big for your car" texts.
function Economy.roomAdvice(carId: string, stage: number, need: number): string
	for next = stage + 1, Economy.maxStage(carId) do
		local stageDef = Economy.stageDef(carId, next)
		if stageDef and stageDef.capacity >= need then
			return `Build it up at Wrench Garage: as a {stageDef.name} it holds {stageDef.capacity}.`
		end
	end
	local names: { string } = {}
	for _, def in Config.Cars do
		if not def.company and not def.bike and def.id ~= carId and Economy.maxCapacity(def.id) >= need then -- (5.1: no bike)
			table.insert(names, def.name)
		end
	end
	if #names == 0 then
		return "None of the dealer's cars holds that much."
	end
	return `That needs a bigger vehicle: the {table.concat(names, " or the ")} (your garage, or Dead End Motors).`
end

-- 3.4, cargo capacity: how many pieces carried or led by hand the car takes at once: its cargo slots (CarDef
-- capacity; 3.5: its stage's, out of `levels`.stage). 4.6: with its installed gear (Economy.installedGear) and the
-- look of the cargo, the Roof Rack's slot for a light piece too (Economy.rackSlots). 5.1: a bike's bike gear adds its
-- room (Economy.bikeRoom: with a light look or none).
function Economy.capacity(carId: string, levels: Upgrades?, installed: { [string]: boolean }?, look: string?): number
	local def = Economy.findCar(carId)
	if not def then
		return 0
	end
	return Economy.stageCapacity(carId, Economy.stageOf(carId, levels)) + Economy.rackSlots(carId, installed, look) + Economy.bikeRoom(carId, installed, look)
end

-- 3.4: the cargo slots a job needs: its pieces when they are carried or led in by hand (all of them ride at once:
-- every pick-up comes before the drops); passengers (board) and a truck that only sells (serve) need none.
function Economy.cargoNeed(load: string, items: number): number
	return if load == "carry" or load == "lead" then math.max(0, items) else 0
end

-- 3.4, the repair shop (Config.Repair): the seconds and the fee for a car missing this share (0 … 1) of its health.
function Economy.repairTime(missing: number): number
	local r = Config.Repair
	local share = math.clamp(missing, 0, 1)
	return math.floor(r.MinSeconds + (r.Seconds - r.MinSeconds) * share + 0.5)
end

function Economy.repairFee(missing: number): number
	local r = Config.Repair
	local share = math.clamp(missing, 0, 1)
	return math.floor((r.FeeMin + (r.FeeFull - r.FeeMin) * share) / 5 + 0.5) * 5
end

-- The car's stats with ITS car-track levels (3.3: Economy.carLevels of profile.carUpgrades).
-- 3.5: with its stage's small bonus (StageDef health, speed) before the upgrades multiply; 4.0: and its accel.
function Economy.carStats(carId: string, upgrades: Upgrades): CarStats
	local def = Economy.findCar(carId) or Config.Cars[1]
	local engine = Economy.multiplier(upgrades, "engine")
	local stage = Economy.stageDef(def.id, Economy.stageOf(def.id, upgrades))
	local speed = def.maxSpeed + (if stage then stage.speed or 0 else 0)
	local accel = def.accel + (if stage then stage.accel or 0 else 0)
	local health = def.health + (if stage then stage.health or 0 else 0)
	return {
		maxSpeed = speed * engine,
		accel = accel * engine,
		turn = def.turn * Economy.multiplier(upgrades, "handling"),
		health = math.floor(health * Economy.multiplier(upgrades, "armor")),
		ramPower = def.ramPower * Economy.multiplier(upgrades, "plow"),
		ramGuard = Economy.ramGuard(upgrades), -- 6.7
	}
end

-- 6.7, the Ram Plow's other half: the share of a ram's dent (Config.Horde.RamSelfDamage of a survivor's health) the car
-- still takes: 1 − guard × the plow's level (UpgradeDef guard), never under Config.Horde.RamGuardMin.
function Economy.ramGuard(upgrades: Upgrades): number
	local def = Economy.findUpgrade("plow")
	local guard = if def and def.guard then def.guard else 0
	return math.max(Config.Horde.RamGuardMin, 1 - guard * Economy.level(upgrades, "plow"))
end

-- 6.7: do you own a car (any vehicle in `cars` that is not a bike: your own or an employer's)? The car-only items
-- (Config.Items car) need one.
function Economy.ownsCar(cars: { [string]: boolean }?): boolean
	if type(cars) ~= "table" then
		return false
	end
	for id, owned in cars do
		local def = if owned == true and type(id) == "string" then Economy.findCar(id) else nil
		if def and not def.bike then
			return true
		end
	end
	return false
end

-- 6.7: is this item for you now: on foot always, a car-only one (ItemDef car) once you own a car (ownsCar)?
function Economy.itemShown(def: Config.ItemDef, cars: { [string]: boolean }?): boolean
	return def.car ~= true or Economy.ownsCar(cars)
end

-- 6.7: the items that are for you now (itemShown), in Config.Items' order.
function Economy.itemsFor(cars: { [string]: boolean }?): { Config.ItemDef }
	local list: { Config.ItemDef } = {}
	for _, def in Config.Items do
		if Economy.itemShown(def, cars) then
			table.insert(list, def)
		end
	end
	return list
end

-- 6.7: is a Config.Weapons gun a reward only (an employer's, a campaign's, the secrets' or the challenges'), never sold?
function Economy.rewardOnly(def: Config.WeaponDef): boolean
	return def.earned ~= nil or def.exclusive ~= nil
end

-- (6.0: no gun, weaponId nil, reads as the pistol's numbers; nothing fires then: Economy.fireMode)
function Economy.weaponStats(weaponId: string?, upgrades: Upgrades): WeaponStats
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

-- 3.2: the first campaign of `requires` (EstateDef.requires: campaign ids) whose finale is not in `finished` yet, or
-- nil when every one is done (or nothing is required). The server (Estate.buy) and the window (EstateUi) both ask.
function Economy.missingCampaign(requires: { string }?, finished: { [string]: boolean }): string?
	local list: { string } = requires or {}
	for _, id in list do
		if not finished[id] then
			return id
		end
	end
	return nil
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

-- … and its enemies' health × this (6.15: a mission's enemies are always the same number, Config.Missions.Fixed:
-- a crew makes them tougher, server/MissionEnemies.luau).
function Economy.coopEnemies(members: number): number
	return 1 + Config.Missions.CoopEnemyPerMember * math.max(0, members)
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
