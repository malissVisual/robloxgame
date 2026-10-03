--!strict
-- Every number of the game in one place: the cars, the guns, the upgrades, the items, the paints, the zombies and
-- the jobs. Pure data (colours are { r, g, b }), so the logic tests can load it outside Roblox.
-- The layout of the world (districts, roads, bridges, places) is in shared/Map.luau.

local Config = {}

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
		id = "icecream",
		name = "Ice Cream Truck",
		price = 6000,
		style = "icecream",
		maxSpeed = 68,
		accel = 30,
		turn = 1.9,
		health = 600,
		ramPower = 1.3,
		color = { 250, 240, 245 },
		description = "Zombies love ice cream. Sturdy and sweet. 1 passenger.",
	},
	{
		id = "armored",
		name = "Armored Truck",
		price = 9000,
		style = "armored",
		maxSpeed = 66,
		accel = 26,
		turn = 1.6,
		health = 1000,
		ramPower = 1.8,
		color = { 80, 96, 70 },
		description = "A tank with a cargo bay. Two gunners on the roof. 3 passengers.",
	},
	{
		id = "bus",
		name = "School Bus",
		price = 14000,
		style = "bus",
		maxSpeed = 62,
		accel = 22,
		turn = 1.4,
		health = 1300,
		ramPower = 2.0,
		color = { 245, 190, 30 },
		description = "Bring the whole crew. 5 passengers.",
	},
	{
		id = "monster",
		name = "Monster Truck",
		price = 22000,
		style = "monster",
		maxSpeed = 86,
		accel = 40,
		turn = 1.9,
		health = 1400,
		ramPower = 2.5,
		color = { 60, 130, 220 },
		description = "Huge wheels. Zombies are just speed bumps. 3 passengers.",
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
	Ambient = { every = 6, count = 1, max = 6, kinds = { walker = 0.85, runner = 0.15 } },
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
			spawnEvery = 5,
			spawnCount = 2,
			maxZombies = 10,
			kinds = { walker = 0.85, runner = 0.15 },
			guardHorde = 0,
			modifierChance = 0,
		},
		{
			stars = 2,
			name = "Risky",
			minDistance = 550,
			maxDistance = 1200,
			basePay = 140,
			payPerStud = 0.3,
			spawnEvery = 3.5,
			spawnCount = 3,
			maxZombies = 16,
			kinds = { walker = 0.6, runner = 0.4 },
			guardHorde = 4,
			modifierChance = 0.25,
		},
		{
			stars = 3,
			name = "Deadly",
			minDistance = 1000,
			maxDistance = 2000,
			basePay = 260,
			payPerStud = 0.45,
			spawnEvery = 2.6,
			spawnCount = 4,
			maxZombies = 22,
			kinds = { walker = 0.5, runner = 0.38, brute = 0.12 },
			guardHorde = 7,
			modifierChance = 0.5,
		},
		{
			stars = 4,
			name = "INSANE",
			minDistance = 1800,
			maxDistance = 99999,
			basePay = 500,
			payPerStud = 0.6,
			spawnEvery = 2.2,
			spawnCount = 4,
			maxZombies = 26,
			kinds = { walker = 0.35, runner = 0.35, soldier = 0.18, brute = 0.12 },
			guardHorde = 10,
			modifierChance = 1,
		},
	} :: { TierDef },
	Modifiers = {
		{ id = "rush", name = "RUSH", description = "30% less time", payMultiplier = 1.4, timeMultiplier = 0.7, spawnMultiplier = 1, conditionMultiplier = 1, speedMultiplier = 1 },
		{ id = "fragile", name = "FRAGILE", description = "Every hit costs double cargo condition", payMultiplier = 1.35, timeMultiplier = 1, spawnMultiplier = 1, conditionMultiplier = 2, speedMultiplier = 1 },
		{ id = "heavy", name = "HEAVY LOAD", description = "Your car is 20% slower", payMultiplier = 1.3, timeMultiplier = 1.15, spawnMultiplier = 1, conditionMultiplier = 1, speedMultiplier = 0.8 },
		{ id = "horde", name = "HORDE", description = "Twice the zombies", payMultiplier = 1.5, timeMultiplier = 1, spawnMultiplier = 2, conditionMultiplier = 1, speedMultiplier = 1 },
	} :: { ModifierDef },
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

return Config
