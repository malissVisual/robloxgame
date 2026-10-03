--!strict
-- Every number of the game in one place: the city, the cars, the guns, the upgrades, the zombies and the jobs.
-- Pure data (colours are { r, g, b }), so the logic tests can load it outside Roblox.

local Config = {}

Config.DataStoreName = "ZombieDelivery_v1"
Config.StartMoney = 150
Config.StudioStartMoney = 25000 -- a Play test in Studio (no saves) starts rich, to try the shop
Config.AutosaveSeconds = 60
Config.SpawnCarCooldown = 4

-- The city: a grid of square blocks with roads between them. Blocks = 4 means -4 … 4, so 9 x 9 blocks.
Config.City = {
	Blocks = 4,
	BlockSize = 110,
	RoadWidth = 34,
	Seed = 7331,
	SafeRadius = 62, -- the depot: no zombies, repairs, the shop
}

export type CarDef = {
	id: string,
	name: string,
	price: number,
	style: string, -- the body the builder makes: van | pickup | muscle | armored | monster
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
		description = "Slow and rusty, but it is yours.",
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
		description = "Faster, tougher, and a good bumper.",
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
		description = "Outruns every zombie. Do not crash.",
	},
	{
		id = "armored",
		name = "Armored Truck",
		price = 8000,
		style = "armored",
		maxSpeed = 66,
		accel = 26,
		turn = 1.6,
		health = 1000,
		ramPower = 1.8,
		color = { 80, 96, 70 },
		description = "A tank with a cargo bay. Rams like a train.",
	},
	{
		id = "monster",
		name = "Monster Truck",
		price = 20000,
		style = "monster",
		maxSpeed = 86,
		accel = 40,
		turn = 1.9,
		health = 1400,
		ramPower = 2.5,
		color = { 60, 130, 220 },
		description = "Huge wheels. Zombies are just speed bumps.",
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
	color: { number }, -- tracer colour
	description: string,
}

Config.Weapons = {
	{
		id = "pistol",
		name = "Roof Pistol",
		price = 0,
		damage = 20,
		fireRate = 3,
		range = 140,
		pellets = 1,
		spread = 0.5,
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
		color = { 255, 150, 70 },
		description = "Point blank, everything falls apart.",
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
		color = { 120, 220, 255 },
		description = "The delivery always arrives.",
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
	{ id = "armor", name = "Armor", description = "+15% car health", maxLevel = 5, baseCost = 300, costGrowth = 1.8, perLevel = 0.15 },
	{ id = "plow", name = "Ram Plow", description = "+30% ram damage", maxLevel = 5, baseCost = 250, costGrowth = 1.75, perLevel = 0.30 },
	{ id = "damage", name = "Gun Damage", description = "+20% gun damage", maxLevel = 5, baseCost = 400, costGrowth = 1.85, perLevel = 0.20 },
	{ id = "firerate", name = "Fire Rate", description = "+12% shots per second", maxLevel = 5, baseCost = 400, costGrowth = 1.85, perLevel = 0.12 },
} :: { UpgradeDef }

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
	MaxTotal = 70, -- in the whole server
	SpawnMin = 70, -- studs from the target
	SpawnMax = 130,
	SpawnAheadChance = 0.7, -- how often a zombie is placed in front of a moving car
	DespawnDistance = 280,
	RepathEvery = 0.25,
	LatchSlots = 4, -- zombies hanging on one car
	LatchReach = 2.5, -- studs from the car's sides
	BiteReach = 4, -- studs from a player on foot
	RamMinSpeed = 18, -- below this a zombie grabs the car instead of being run over
	RamDamagePerSpeed = 2.4, -- damage = speed × this × ramPower × plow
	RamSlowdown = 0.35, -- the car keeps this much speed after hitting a zombie that survives
	RamSelfDamage = 0.12, -- the car takes this share of a survivor's health as damage
	HeadshotMultiplier = 2,
	-- When nobody has a job a few zombies still wander around (and pay for kills).
	Ambient = { every = 6, count = 1, max = 6, kinds = { walker = 0.85, runner = 0.15 } },
}

export type TierDef = {
	stars: number,
	minDistance: number,
	maxDistance: number,
	basePay: number,
	payPerStud: number,
	spawnEvery: number,
	spawnCount: number,
	maxZombies: number,
	kinds: { [string]: number },
	guardHorde: number, -- zombies waiting at the destination
}

Config.Jobs = {
	OfferCount = 3,
	DeliverRadius = 18,
	DeliverMaxSpeed = 30,
	TimeBase = 30,
	TimePerStud = 1 / 22,
	FastShare = 0.5, -- deliver with at least this share of the time left for the speed bonus
	FastBonus = 0.25, -- share of the base pay
	KillBonus = 3, -- per zombie killed during the job (on top of the kill reward)
	MinCondition = 0.5, -- a wrecked cargo still pays this share
	ConditionPerDamage = 0.6, -- losing the whole car health costs this much cargo condition
	GuardTriggerDistance = 220,
	Tiers = {
		{
			stars = 1,
			minDistance = 150,
			maxDistance = 550,
			basePay = 80,
			payPerStud = 0.2,
			spawnEvery = 5,
			spawnCount = 2,
			maxZombies = 10,
			kinds = { walker = 0.85, runner = 0.15 },
			guardHorde = 0,
		},
		{
			stars = 2,
			minDistance = 450,
			maxDistance = 950,
			basePay = 140,
			payPerStud = 0.3,
			spawnEvery = 3.5,
			spawnCount = 3,
			maxZombies = 16,
			kinds = { walker = 0.6, runner = 0.4 },
			guardHorde = 4,
		},
		{
			stars = 3,
			minDistance = 800,
			maxDistance = 99999,
			basePay = 260,
			payPerStud = 0.45,
			spawnEvery = 2.6,
			spawnCount = 4,
			maxZombies = 22,
			kinds = { walker = 0.5, runner = 0.38, brute = 0.12 },
			guardHorde = 7,
		},
	} :: { TierDef },
	Cargo = {
		{ "Pizza", "Canned Food", "Batteries", "Water Bottles", "Mail" },
		{ "Medkit Box", "Fuel Can", "Radio Parts", "Ammo Crate" },
		{ "Antidote", "Vaccine Case", "Generator Core", "Secret Documents" },
	},
	Customers = {
		"Grandma Rose",
		"Survivor Camp",
		"Dr. Novak",
		"Pizza Lover",
		"The Mayor",
		"Fire Station",
		"Old Pete",
		"Radio Tower",
		"Police Bunker",
		"The Twins",
		"Hospital Roof",
		"Mrs. Hungry",
	},
	Streets = { "Maple", "Oak", "Grave", "Elm", "Bone", "Main", "Cedar", "Ash", "Hollow", "Pine" },
	Avenues = { "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th" },
}

return Config
