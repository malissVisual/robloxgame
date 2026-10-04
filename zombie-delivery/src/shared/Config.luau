--!strict
-- Every number of the game in one place: the cars, the guns, the upgrades, the items, the paints, the zombies and
-- the jobs. Pure data (colours are { r, g, b }), so the logic tests can load it outside Roblox.
-- The layout of the world (districts, roads, bridges, places) is in shared/Map.luau.

local Config = {}

-- Shown on the start screen: tells which version Studio really runs (bump it with every update).
Config.Version = "1.1"

Config.DataStoreName = "ZombieDelivery_v1"
Config.StartMoney = 150
Config.StudioStartMoney = 25000 -- a Play test in Studio (no saves) starts rich, to try the shops
Config.AutosaveSeconds = 60
Config.SpawnCarCooldown = 4

Config.City = {
	BlockSize = 110,
	RoadWidth = 34,
	HighwayWidth = 40,
	Seed = 7331,
	SafeHalf = 235, -- the safe zone around the depot: a square, |x| and |z| below this
	RepairRadius = 55, -- the car is repaired this close to the depot or inside the mechanic's garage
}

export type CarDef = {
	id: string,
	name: string,
	price: number,
	style: string, -- the body the builder makes (server/Vehicles.luau)
	maxSpeed: number, -- studs / s
	accel: number, -- studs / s²
	turn: number, -- rad / s at full lock
	health: number,
	ramPower: number, -- multiplies the damage of running a zombie over
	color: { number },
	description: string,
	company: boolean?, -- not for sale: an employer lends it for their jobs and gives it to you after a few of them
	employer: string?, -- who (Config.Employers)
}

Config.Cars = {
	{
		id = "van",
		name = "Old Van",
		price = 0,
		style = "van",
		maxSpeed = 60,
		accel = 26,
		turn = 1.8,
		health = 300,
		ramPower = 1.0,
		color = { 214, 196, 160 },
		description = "Slow and rusty, but it is yours. 1 passenger.",
	},
	{
		id = "pickup",
		name = "Pickup",
		price = 1500,
		style = "pickup",
		maxSpeed = 72,
		accel = 32,
		turn = 2.0,
		health = 420,
		ramPower = 1.15,
		color = { 196, 60, 50 },
		description = "Two friends ride in the bed and shoot. 3 passengers.",
	},
	{
		id = "muscle",
		name = "Muscle Car",
		price = 4000,
		style = "muscle",
		maxSpeed = 95,
		accel = 46,
		turn = 2.3,
		health = 340,
		ramPower = 1.0,
		color = { 30, 30, 36 },
		description = "Outruns every zombie. Do not crash. 1 passenger.",
	},
	{
		id = "armored",
		name = "Armored Truck",
		price = 0,
		style = "armored",
		maxSpeed = 66,
		accel = 26,
		turn = 1.6,
		health = 1000,
		ramPower = 1.8,
		color = { 80, 96, 70 },
		description = "The army's truck. Two gunners on the roof. 3 passengers.",
		company = true,
		employer = "army",
	},
	{
		id = "bus",
		name = "School Bus",
		price = 0,
		style = "bus",
		maxSpeed = 62,
		accel = 22,
		turn = 1.4,
		health = 1300,
		ramPower = 2.0,
		color = { 245, 190, 30 },
		description = "The school's bus. Bring the whole crew. 5 passengers.",
		company = true,
		employer = "school",
	},
	{
		id = "monster",
		name = "Monster Truck",
		price = 0,
		style = "monster",
		maxSpeed = 86,
		accel = 40,
		turn = 1.9,
		health = 1400,
		ramPower = 2.5,
		color = { 60, 130, 220 },
		description = "The farmer's pride. Zombies are just speed bumps. 3 passengers.",
		company = true,
		employer = "farm",
	},
	-- Company vehicles (the special jobs lend them, Config.JobTypes).
	{
		id = "icecream",
		name = "Ice Cream Truck",
		price = 0,
		style = "icecream",
		maxSpeed = 64,
		accel = 28,
		turn = 1.9,
		health = 650,
		ramPower = 1.3,
		color = { 250, 240, 245 },
		description = "Frosty's ice cream truck. 1 passenger.",
		company = true,
		employer = "icecream",
	},
	{
		id = "movingtruck",
		name = "Moving Truck",
		price = 0,
		style = "movingtruck",
		maxSpeed = 58,
		accel = 22,
		turn = 1.5,
		health = 900,
		ramPower = 1.6,
		color = { 230, 120, 40 },
		description = "Big Move's moving truck. 1 passenger.",
		company = true,
		employer = "movers",
	},
} :: { CarDef }

export type WeaponDef = {
	id: string,
	name: string,
	price: number,
	damage: number, -- per pellet
	fireRate: number, -- shots / s
	range: number,
	pellets: number,
	spread: number, -- degrees
	splash: number, -- radius of the blast (0 = none)
	color: { number }, -- tracer colour
	description: string,
}

Config.Weapons = {
	{
		id = "pistol",
		name = "Pistol",
		price = 0,
		damage = 20,
		fireRate = 3,
		range = 140,
		pellets = 1,
		spread = 0.5,
		splash = 0,
		color = { 255, 230, 140 },
		description = "Better than throwing the pizza at them.",
	},
	{
		id = "smg",
		name = "SMG",
		price = 2000,
		damage = 13,
		fireRate = 9,
		range = 130,
		pellets = 1,
		spread = 2,
		splash = 0,
		color = { 255, 200, 90 },
		description = "Sprays a lot of lead.",
	},
	{
		id = "shotgun",
		name = "Shotgun",
		price = 3500,
		damage = 15,
		fireRate = 1.4,
		range = 85,
		pellets = 7,
		spread = 6,
		splash = 0,
		color = { 255, 150, 70 },
		description = "Point blank, everything falls apart.",
	},
	{
		id = "rifle",
		name = "Hunting Rifle",
		price = 6000,
		damage = 48,
		fireRate = 2.2,
		range = 240,
		pellets = 1,
		spread = 0.2,
		splash = 0,
		color = { 200, 255, 200 },
		description = "Long range, one head at a time.",
	},
	{
		id = "minigun",
		name = "Minigun",
		price = 12000,
		damage = 15,
		fireRate = 16,
		range = 160,
		pellets = 1,
		spread = 2.5,
		splash = 0,
		color = { 120, 220, 255 },
		description = "The delivery always arrives.",
	},
	{
		id = "launcher",
		name = "Grenade Launcher",
		price = 18000,
		damage = 90,
		fireRate = 1.1,
		range = 150,
		pellets = 1,
		spread = 1,
		splash = 14,
		color = { 255, 110, 60 },
		description = "Every shot is a small explosion.",
	},
} :: { WeaponDef }

export type UpgradeDef = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number,
	perLevel: number, -- +x of the base value per level
}

Config.Upgrades = {
	{ id = "engine", name = "Engine", description = "+8% top speed and acceleration", maxLevel = 5, baseCost = 350, costGrowth = 1.8, perLevel = 0.08 },
	{ id = "handling", name = "Handling", description = "+8% steering", maxLevel = 5, baseCost = 250, costGrowth = 1.7, perLevel = 0.08 },
	{ id = "armor", name = "Armor", description = "+15% car health", maxLevel = 5, baseCost = 300, costGrowth = 1.8, perLevel = 0.15 },
	{ id = "plow", name = "Ram Plow", description = "+30% ram damage", maxLevel = 5, baseCost = 250, costGrowth = 1.75, perLevel = 0.30 },
	{ id = "damage", name = "Gun Damage", description = "+20% gun damage", maxLevel = 5, baseCost = 400, costGrowth = 1.85, perLevel = 0.20 },
	{ id = "firerate", name = "Fire Rate", description = "+12% shots per second", maxLevel = 5, baseCost = 400, costGrowth = 1.85, perLevel = 0.12 },
} :: { UpgradeDef }

export type ItemDef = {
	id: string,
	name: string,
	icon: string,
	price: number,
	max: number,
	description: string,
}

-- Consumables, bought at Last Stop Supplies, used from the hotbar (keys 1 … 5).
Config.Items = {
	{ id = "repair", name = "Repair Kit", icon = "🔧", price = 150, max = 10, description = "Fixes 40% of your car." },
	{ id = "medkit", name = "Medkit", icon = "➕", price = 80, max = 10, description = "Heals you fully." },
	{ id = "nitro", name = "Nitro", icon = "⚡", price = 120, max = 10, description = "4 seconds of +60% speed." },
	{ id = "molotov", name = "Molotov", icon = "🔥", price = 60, max = 20, description = "Throw it where you aim: burns zombies for 8 s." },
	{ id = "mine", name = "Landmine", icon = "💣", price = 100, max = 10, description = "Drops behind your car. Boom." },
} :: { ItemDef }

Config.ItemTuning = {
	RepairShare = 0.4,
	NitroTime = 4,
	NitroMultiplier = 1.6,
	MolotovRange = 90,
	MolotovRadius = 13,
	MolotovTime = 8,
	MolotovDps = 35,
	MineTrigger = 9,
	MineRadius = 18,
	MineDamage = 320,
	MineLife = 120,
	MineMax = 5,
	UseCooldown = 0.4,
}

export type PaintDef = { id: string, name: string, price: number, color: { number }? }

-- Paint jobs at Wrench Garage (per car). "factory" = the car's own colour.
Config.Paints = {
	{ id = "factory", name = "Factory", price = 0, color = nil },
	{ id = "black", name = "Midnight Black", price = 300, color = { 24, 24, 28 } },
	{ id = "white", name = "Snow White", price = 300, color = { 235, 235, 235 } },
	{ id = "red", name = "Blood Red", price = 500, color = { 150, 16, 20 } },
	{ id = "camo", name = "Army Green", price = 700, color = { 74, 92, 52 } },
	{ id = "toxic", name = "Toxic Green", price = 900, color = { 90, 230, 60 } },
	{ id = "pink", name = "Hot Pink", price = 1200, color = { 255, 80, 170 } },
	{ id = "gold", name = "Gold", price = 3000, color = { 230, 180, 50 } },
} :: { PaintDef }

-- Supply crates lying around the world: drive or walk into one.
Config.Loot = {
	Count = 16,
	Respawn = 40,
	MoneyMin = 25,
	MoneyMax = 90,
	ItemChance = 0.4,
	Reach = 9,
}

-- The bandits' pickup: chases you along the roads, two gunners in the bed shoot at your car.
Config.BanditCar = {
	car = {
		id = "banditpickup",
		name = "Bandit Pickup",
		price = 0,
		style = "pickup",
		maxSpeed = 70,
		accel = 38,
		turn = 2.1,
		health = 280,
		ramPower = 1,
		color = { 22, 22, 26 },
		description = "",
		company = true,
	} :: CarDef,
	CatchUpSpeed = 84, -- far behind they put the foot down
	Range = 95, -- the gunners shoot from this close
	FireEvery = 0.8,
	ShotDamage = 6,
	Accuracy = 0.55,
	SwipeDamage = 14, -- ramming you from the side
	Reward = 75,
	SpawnBehind = 190, -- studs behind you on the road
	Lifetime = 150,
	DespawnDistance = 520,
	RamDamagePerSpeed = 2, -- you ramming it
	StealPerSecond = 0.05, -- bandits next to your car carry off this share of the cargo every second
	WreckCargoLoss = 0.25, -- a wrecked car loses this share of the cargo (the job goes on: call a new car)
}

export type ZombieDef = {
	name: string,
	health: number,
	speed: number,
	damage: number, -- per bite
	attackEvery: number,
	reward: number, -- money per kill
	scale: number,
	skin: { number },
	shirt: { number },
	pants: { number },
	-- Bandits: they shoot instead of biting.
	ranged: boolean?,
	range: number?, -- they shoot from this far
	shotDamage: number?,
	fireEvery: number?,
	accuracy: number?, -- hit chance at a standing target (less at speed)
}

Config.Zombies = {
	walker = {
		name = "Walker",
		health = 60,
		speed = 12,
		damage = 6,
		attackEvery = 1.0,
		reward = 4,
		scale = 1,
		skin = { 120, 150, 100 },
		shirt = { 90, 80, 70 },
		pants = { 50, 55, 75 },
	},
	runner = {
		name = "Runner",
		health = 35,
		speed = 27,
		damage = 4,
		attackEvery = 0.7,
		reward = 7,
		scale = 0.9,
		skin = { 150, 160, 110 },
		shirt = { 150, 40, 40 },
		pants = { 40, 40, 40 },
	},
	soldier = {
		name = "Soldier",
		health = 140,
		speed = 16,
		damage = 10,
		attackEvery = 0.9,
		reward = 14,
		scale = 1.05,
		skin = { 110, 140, 95 },
		shirt = { 72, 88, 50 },
		pants = { 60, 70, 44 },
	},
	bandit = {
		name = "Bandit",
		health = 80,
		speed = 18,
		damage = 6,
		attackEvery = 1,
		reward = 15,
		scale = 1,
		skin = { 205, 160, 120 },
		shirt = { 30, 30, 34 },
		pants = { 50, 60, 90 },
		ranged = true,
		range = 95,
		shotDamage = 7,
		fireEvery = 1.3,
		accuracy = 0.7,
	},
	gunner = {
		name = "Gunner",
		health = 120,
		speed = 15,
		damage = 8,
		attackEvery = 1,
		reward = 25,
		scale = 1.05,
		skin = { 150, 110, 80 },
		shirt = { 120, 30, 30 },
		pants = { 40, 40, 40 },
		ranged = true,
		range = 150,
		shotDamage = 12,
		fireEvery = 1.8,
		accuracy = 0.6,
	},
	brute = {
		name = "Brute",
		health = 420,
		speed = 10,
		damage = 22,
		attackEvery = 1.4,
		reward = 40,
		scale = 1.8,
		skin = { 100, 120, 80 },
		shirt = { 60, 60, 60 },
		pants = { 70, 50, 40 },
	},
} :: { [string]: ZombieDef }

-- Zombies around the cars.
Config.Horde = {
	MaxTotal = 95, -- in the whole server
	SpawnMin = 70, -- studs from the target
	SpawnMax = 130,
	SpawnAheadChance = 0.7, -- how often a zombie is placed in front of a moving car
	DespawnDistance = 300,
	RepathEvery = 0.25,
	LatchSlots = 4, -- zombies hanging on one car
	LatchReach = 2.5, -- studs from the car's sides
	BiteReach = 4, -- studs from a player on foot
	RamMinSpeed = 18, -- below this a zombie grabs the car instead of being run over
	RamDamagePerSpeed = 2.4, -- damage = speed × this × ramPower × plow
	RamSlowdown = 0.35, -- the car keeps this much speed after hitting a zombie that survives
	RamSelfDamage = 0.12, -- the car takes this share of a survivor's health as damage
	HeadshotMultiplier = 2,
	-- When nobody has a job a few zombies still wander around a player (and pay for kills).
	Ambient = { every = 7, count = 1, max = 5, kinds = { walker = 0.6, runner = 0.1, bandit = 0.3 } },
	-- Zombies that live in the world all the time (they never despawn, the dead come back).
	Residents = { count = 36, respawn = 25 },
}

export type TierDef = {
	stars: number,
	name: string,
	minDistance: number,
	maxDistance: number,
	basePay: number,
	payPerStud: number,
	spawnEvery: number,
	spawnCount: number,
	maxZombies: number,
	kinds: { [string]: number },
	guardHorde: number, -- zombies waiting at the destination
	modifierChance: number,
	ambushEvery: number, -- seconds between bandit roadblocks ahead of you (0 = none)
	ambushSize: number,
	chaseEvery: number, -- seconds between bandit cars coming after you (0 = none)
	chaseMax: number, -- bandit cars chasing you at once
}

export type ModifierDef = {
	id: string,
	name: string,
	description: string,
	payMultiplier: number,
	timeMultiplier: number,
	spawnMultiplier: number,
	conditionMultiplier: number,
	speedMultiplier: number,
}

Config.Jobs = {
	DeliverRadius = 18,
	-- Every job has two stops: pick the cargo up (stand still while it is loaded), then deliver it (stand still while
	-- it is unloaded, the zombies keep coming).
	LoadTime = 3,
	UnloadTime = 4,
	HoldMaxSpeed = 8, -- the car must (almost) stand still in the circle
	PickupMinDistance = 120,
	PickupMaxDistance = 520,
	PickupPlaces = { "Supermarket", "Pharmacy", "Warehouse", "Pizza Place", "Hardware Store", "Bakery", "Post Office", "Pawn Shop", "Gas Station" },
	TimeBase = 30,
	TimePerStud = 1 / 22,
	FastShare = 0.5, -- deliver with at least this share of the time left for the speed bonus
	FastBonus = 0.25, -- share of the base pay
	KillBonus = 3, -- per zombie killed during the job (on top of the kill reward)
	MinCondition = 0.5, -- a wrecked cargo still pays this share
	ConditionPerDamage = 0.6, -- losing the whole car health costs this much cargo condition
	GuardTriggerDistance = 230,
	CrewDriverBonus = 0.15, -- the driver gets +15 % of the payout for every passenger
	CrewShare = 0.5, -- every passenger gets half of the payout (on top, nobody loses money)
	Tiers = {
		{
			stars = 1,
			name = "Easy",
			minDistance = 150,
			maxDistance = 650,
			basePay = 80,
			payPerStud = 0.2,
			spawnEvery = 8,
			spawnCount = 1,
			maxZombies = 6,
			kinds = { walker = 0.75, runner = 0.1, bandit = 0.15 },
			guardHorde = 0,
			modifierChance = 0,
			ambushEvery = 0,
			ambushSize = 0,
			chaseEvery = 0,
			chaseMax = 0,
		},
		{
			stars = 2,
			name = "Risky",
			minDistance = 550,
			maxDistance = 1200,
			basePay = 140,
			payPerStud = 0.3,
			spawnEvery = 6,
			spawnCount = 2,
			maxZombies = 10,
			kinds = { walker = 0.4, runner = 0.2, bandit = 0.4 },
			guardHorde = 4,
			modifierChance = 0.25,
			ambushEvery = 45,
			ambushSize = 3,
			chaseEvery = 55,
			chaseMax = 1,
		},
		{
			stars = 3,
			name = "Deadly",
			minDistance = 1000,
			maxDistance = 2000,
			basePay = 260,
			payPerStud = 0.45,
			spawnEvery = 5,
			spawnCount = 2,
			maxZombies = 14,
			kinds = { walker = 0.25, runner = 0.2, bandit = 0.35, gunner = 0.1, brute = 0.1 },
			guardHorde = 7,
			modifierChance = 0.5,
			ambushEvery = 30,
			ambushSize = 4,
			chaseEvery = 38,
			chaseMax = 1,
		},
		{
			stars = 4,
			name = "INSANE",
			minDistance = 1800,
			maxDistance = 99999,
			basePay = 500,
			payPerStud = 0.6,
			spawnEvery = 4,
			spawnCount = 3,
			maxZombies = 18,
			kinds = { walker = 0.15, runner = 0.15, soldier = 0.15, bandit = 0.3, gunner = 0.15, brute = 0.1 },
			guardHorde = 10,
			modifierChance = 1,
			ambushEvery = 22,
			ambushSize = 5,
			chaseEvery = 26,
			chaseMax = 2,
		},
	} :: { TierDef },
	Modifiers = {
		{ id = "rush", name = "RUSH", description = "30% less time", payMultiplier = 1.4, timeMultiplier = 0.7, spawnMultiplier = 1, conditionMultiplier = 1, speedMultiplier = 1 },
		{ id = "fragile", name = "FRAGILE", description = "Every hit costs double cargo condition", payMultiplier = 1.35, timeMultiplier = 1, spawnMultiplier = 1, conditionMultiplier = 2, speedMultiplier = 1 },
		{ id = "heavy", name = "HEAVY LOAD", description = "Your car is 20% slower", payMultiplier = 1.3, timeMultiplier = 1.15, spawnMultiplier = 1, conditionMultiplier = 1, speedMultiplier = 0.8 },
		{ id = "horde", name = "WANTED", description = "Twice the enemies, bandits want your cargo", payMultiplier = 1.5, timeMultiplier = 1, spawnMultiplier = 2, conditionMultiplier = 1, speedMultiplier = 1 },
	} :: { ModifierDef },
	-- How often (and how many) the bandits set up a roadblock ahead of you, see the tiers. A roadblock is a car across
	-- the road with bandits around it.
	AmbushDistance = 170,
	Cargo = {
		{ "Pizza", "Canned Food", "Batteries", "Water Bottles", "Mail" },
		{ "Medkit Box", "Fuel Can", "Radio Parts", "Ammo Crate" },
		{ "Antidote", "Vaccine Case", "Generator Core", "Secret Documents" },
		{ "Nuclear Battery", "Live Zombie Sample", "The General's Wedding Cake", "Prototype Cure", "Gold Bars" },
	},
	Customers = {
		"Grandma Rose",
		"Survivor Camp",
		"Dr. Novak",
		"Pizza Lover",
		"The Mayor",
		"Fire Station",
		"Old Pete",
		"Police Bunker",
		"The Twins",
		"Hospital Roof",
		"Mrs. Hungry",
		"Last Barber",
	},
}

export type JobTypeDef = {
	id: string,
	name: string,
	description: string,
	vehicle: string?, -- the employer lends this car for the job
	employer: string?, -- taken at the employer's place (Config.Employers), not on the job board
	pickups: number, -- pick-up stops (0 = the vehicle starts loaded)
	pickupAt: string?, -- the pick-up is at this place (shared/Map.luau Places), else around you
	drops: number, -- delivery stops
	dropAt: string?, -- the last delivery is at this place, else an address
	loadTime: number,
	unloadTime: number,
	payPerStop: number, -- on top of the tier's pay
	tier: number, -- the danger level (enemies)
	cargo: string,
	pickupLabel: string,
	dropLabel: string,
}

-- Special jobs. The ones with an employer are taken at the employer's place; the others show up on the job board.
Config.JobTypes = {
	{
		id = "schoolrun",
		name = "School Run",
		description = "Pick the kids up at three homes and bring them to Sunny Hill School in the school bus.",
		vehicle = "bus",
		employer = "school",
		pickups = 3,
		pickupAt = nil,
		drops = 1,
		dropAt = "school",
		loadTime = 3,
		unloadTime = 5,
		payPerStop = 60,
		tier = 2,
		cargo = "Kids",
		pickupLabel = "PICK UP THE KIDS",
		dropLabel = "DROP THE KIDS AT",
	},
	{
		id = "armysupply",
		name = "Army Supply",
		description = "Load ammo at the Harbor Docks and drive it in the army's armored truck through the tunnel to the base.",
		vehicle = "armored",
		employer = "army",
		pickups = 1,
		pickupAt = "docks",
		drops = 1,
		dropAt = "base",
		loadTime = 5,
		unloadTime = 6,
		payPerStop = 250,
		tier = 4,
		cargo = "Ammo Crates",
		pickupLabel = "LOAD THE AMMO",
		dropLabel = "DELIVER THE AMMO TO",
	},
	{
		id = "icecream",
		name = "Ice Cream Route",
		description = "Load up at Frosty's and sell ice cream at 4 stops. Hold still while the kids buy.",
		vehicle = "icecream",
		employer = "icecream",
		pickups = 1,
		pickupAt = "frosty",
		drops = 4,
		dropAt = nil,
		loadTime = 3,
		unloadTime = 3,
		payPerStop = 60,
		tier = 2,
		cargo = "Ice Cream",
		pickupLabel = "LOAD THE ICE CREAM",
		dropLabel = "SELL ICE CREAM AT",
	},
	{
		id = "moving",
		name = "Moving Day",
		description = "Load a family's furniture at their house and unload it at their new home.",
		vehicle = "movingtruck",
		employer = "movers",
		pickups = 1,
		pickupAt = nil,
		drops = 1,
		dropAt = nil,
		loadTime = 8,
		unloadTime = 8,
		payPerStop = 120,
		tier = 2,
		cargo = "Furniture",
		pickupLabel = "LOAD THE FURNITURE",
		dropLabel = "UNLOAD AT THE NEW HOME,",
	},
	{
		id = "farmrun",
		name = "Farm Run",
		description = "Load fresh food at the Old Farm and bring it to two markets in the city.",
		vehicle = "monster",
		employer = "farm",
		pickups = 1,
		pickupAt = "farm",
		drops = 2,
		dropAt = nil,
		loadTime = 5,
		unloadTime = 4,
		payPerStop = 150,
		tier = 3,
		cargo = "Fresh Food",
		pickupLabel = "LOAD THE FOOD",
		dropLabel = "DELIVER TO THE MARKET AT",
	},
	{
		id = "winter",
		name = "Winter Run",
		description = "Through the tunnel to the Ski Lodge, over the frozen lake. The ice is slippery!",
		vehicle = nil,
		employer = nil,
		pickups = 1,
		pickupAt = nil,
		drops = 1,
		dropAt = "lodge",
		loadTime = 3,
		unloadTime = 4,
		payPerStop = 200,
		tier = 4,
		cargo = "Hot Soup",
		pickupLabel = "PICK UP THE SOUP",
		dropLabel = "DELIVER TO",
	},
} :: { JobTypeDef }

export type EmployerDef = {
	id: string,
	name: string,
	icon: string,
	jobType: string,
	reward: string, -- the car you get to keep
	needed: number, -- jobs done for them before they give it to you
	pitch: string,
}

-- People who run something in the world. Work for them: after a few jobs their vehicle is yours.
Config.Employers = {
	{ id = "school", name = "Sunny Hill School", icon = "🏫", jobType = "schoolrun", reward = "bus", needed = 3, pitch = "Our bus driver ran away. Drive the kids to school!" },
	{ id = "army", name = "Military Base", icon = "🪖", jobType = "armysupply", reward = "armored", needed = 3, pitch = "We need ammo from the docks. Bring it through the tunnel." },
	{ id = "icecream", name = "Frosty's Ice Cream", icon = "🍦", jobType = "icecream", reward = "icecream", needed = 3, pitch = "People still want ice cream. Sell it for us!" },
	{ id = "movers", name = "Big Move Movers", icon = "🚚", jobType = "moving", reward = "movingtruck", needed = 3, pitch = "Families are getting out of town. Move their things." },
	{ id = "farm", name = "Old Farm", icon = "🌽", jobType = "farmrun", reward = "monster", needed = 3, pitch = "The city is hungry. Take my monster truck to the markets." },
} :: { EmployerDef }

return Config
