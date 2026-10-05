--!strict
-- Every number of the game in one place: the cars, the guns, the upgrades, the items, the paints, the zombies and
-- the jobs. Pure data (colours are { r, g, b }), so the logic tests can load it outside Roblox.
-- The layout of the world (districts, roads, bridges, places) is in shared/Map.luau.

local Config = {}

-- Shown on the start screen: tells which version Studio really runs (bump it with every update).
Config.Version = "3.4"

Config.DataStoreName = "ZombieDelivery_v1"
Config.StartMoney = 150
Config.StudioStartMoney = 150 -- a Play test in Studio (no saves) starts like a new player; the admin panel (P) gives money for testing
Config.AutosaveSeconds = 60
Config.SpawnCarCooldown = 4

-- Who may open the admin panel (P / the ADMIN button, server/Admin.luau): everybody in a Studio Play test, the
-- game's owner (game.CreatorId) and these user ids.
Config.Admin = {
	InStudio = true,
	UserIds = {} :: { number },
}

Config.City = {
	BlockSize = 110,
	RoadWidth = 34,
	HighwayWidth = 40,
	Seed = 7331,
	SafeHalf = 235, -- the safe zone around the depot: a square, |x| and |z| below this
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
	level: number?, -- the driver level (Config.Levels) needed to buy it
	employer: string?, -- who (Config.Employers)
	mount: boolean?, -- a car gun (Config.CarGuns) fits on its roof; the company / work vehicles carry none
	capacity: number, -- 3.4: cargo slots (the pieces carried or led by hand it takes at once), = its body's slots
	-- (server/Vehicles.luau STYLES cargo; tests/run_tests.py checks they match). The Cargo Rack adds to it.
}

-- 3.2, the progression (Config.Levels): the van is where you start, the pickup opens at level 4, the muscle car at 8
-- (a fourth car needs a slot: a garage from level 5, Config.Estate). The guns and the car guns open the same way.
-- 3.3: five more vans in between, each with its own body (server/Vehicles.luau STYLES): the Courier Van at 2, the
-- High-Roof Van at 3, the Box Truck at 6, the Armored Van at 10 and the Rally Van at 12. The dealer's cars stay in
-- the order of their level (and price): the showroom and the dealer window list them this way.
-- 3.4: every car has a capacity (cargo slots): the vans 4, the High-Roof Van and the Box Truck 6, the Muscle Car 2;
-- a job or a mission with more pieces than your car holds waits until you have a bigger car or a Cargo Rack
-- (Config.Upgrades "rack": +1 slot per level). The employers' vehicles hold what their jobs need.
Config.Cars = {
	{
		id = "van",
		mount = true,
		name = "Old Van",
		price = 0,
		style = "van",
		maxSpeed = 60,
		accel = 26,
		turn = 1.8,
		health = 300,
		capacity = 4,
		ramPower = 1.0,
		color = { 214, 196, 160 },
		description = "Slow and rusty, but it is yours. 1 passenger.",
	},
	{
		id = "courier",
		level = 2,
		mount = true,
		name = "Courier Van",
		price = 3500,
		style = "courier",
		maxSpeed = 68,
		accel = 30,
		turn = 1.95,
		health = 340,
		capacity = 4,
		ramPower = 1.0,
		color = { 232, 170, 40 },
		description = "Small, low and quick off the line, an amber light bar on the roof. 1 passenger.",
	},
	{
		id = "highroof",
		level = 3,
		mount = true,
		name = "High-Roof Van",
		price = 7000,
		style = "highroof",
		maxSpeed = 62,
		accel = 27,
		turn = 1.75,
		health = 450,
		capacity = 6,
		ramPower = 1.1,
		color = { 168, 186, 200 },
		description = "Stand up inside. A tall roof, thicker walls and a jump seat for a friend. 2 passengers.",
	},
	{
		id = "pickup",
		level = 4,
		mount = true,
		name = "Pickup",
		price = 12000,
		style = "pickup",
		maxSpeed = 72,
		accel = 32,
		turn = 2.0,
		health = 420,
		capacity = 4,
		ramPower = 1.15,
		color = { 196, 60, 50 },
		description = "Two friends ride in the bed and shoot. 3 passengers.",
	},
	{
		id = "boxtruck",
		level = 6,
		mount = true,
		name = "Box Truck",
		price = 22000,
		style = "boxtruck",
		maxSpeed = 64,
		accel = 26,
		turn = 1.6,
		health = 650,
		capacity = 6,
		ramPower = 1.4,
		color = { 238, 238, 232 },
		description = "A cab and a big box behind it. Slow to stop, hard to kill, room for six. 2 passengers.",
	},
	{
		id = "muscle",
		level = 8,
		mount = true,
		name = "Muscle Car",
		price = 40000,
		style = "muscle",
		maxSpeed = 95,
		accel = 46,
		turn = 2.3,
		health = 340,
		capacity = 2,
		ramPower = 1.0,
		color = { 30, 30, 36 },
		description = "Outruns every zombie. Do not crash. 1 passenger.",
	},
	{
		id = "armorvan",
		level = 10,
		mount = true,
		name = "Armored Van",
		price = 55000,
		style = "armorvan",
		maxSpeed = 74,
		accel = 34,
		turn = 1.8,
		health = 900,
		capacity = 4,
		ramPower = 1.6,
		color = { 72, 78, 84 },
		description = "Steel plates, grilles on the windows. The bullets knock, nobody answers. 2 passengers.",
	},
	{
		id = "rallyvan",
		level = 12,
		mount = true,
		name = "Rally Van",
		price = 80000,
		style = "rallyvan",
		maxSpeed = 92,
		accel = 44,
		turn = 2.2,
		health = 420,
		capacity = 4,
		ramPower = 1.1,
		color = { 30, 90, 200 },
		description = "Lowered, striped, a spoiler and big wheels: a van that thinks it is a race car. 1 passenger.",
	},
	{
		id = "armored",
		mount = true,
		name = "Armored Truck",
		price = 0,
		style = "armored",
		maxSpeed = 66,
		accel = 26,
		turn = 1.6,
		health = 1000,
		capacity = 8,
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
		capacity = 8,
		ramPower = 2.0,
		color = { 245, 190, 30 },
		description = "The school's bus. Bring the whole crew. 5 passengers.",
		company = true,
		employer = "school",
	},
	{
		id = "monster",
		mount = true,
		name = "Monster Truck",
		price = 0,
		style = "monster",
		maxSpeed = 86,
		accel = 40,
		turn = 1.9,
		health = 1400,
		capacity = 6,
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
		capacity = 6,
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
		capacity = 10,
		ramPower = 1.6,
		color = { 230, 120, 40 },
		description = "Big Move's moving truck. 1 passenger.",
		company = true,
		employer = "movers",
	},
	{
		id = "livestock",
		name = "Livestock Truck",
		price = 0,
		style = "livestock",
		maxSpeed = 56,
		accel = 22,
		turn = 1.5,
		health = 1000,
		capacity = 2,
		ramPower = 1.7,
		color = { 150, 90, 50 },
		description = "Silver Spur Ranch's horse truck, a stall box on the back. 1 passenger.",
		company = true,
		employer = "ranch",
	},
	{
		id = "ambulance",
		name = "Ambulance",
		price = 0,
		style = "ambulance",
		maxSpeed = 70,
		accel = 30,
		turn = 1.8,
		health = 800,
		capacity = 1,
		ramPower = 1.4,
		color = { 245, 245, 245 },
		description = "City Clinic's ambulance: a stretcher in the back, sirens on the roof. 1 passenger.",
		company = true,
		employer = "clinic",
	},
	{
		id = "fueltruck",
		name = "Fuel Truck",
		price = 0,
		style = "fueltruck",
		maxSpeed = 60,
		accel = 24,
		turn = 1.6,
		health = 950,
		capacity = 6,
		ramPower = 1.6,
		color = { 220, 60, 50 },
		description = "A flatbed with a barrel rack, from the gas station. 1 passenger.",
		company = true,
		employer = "gas",
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
	earned: string?, -- not sold: this employer (Config.Employers) gives it to you after some jobs
	level: number?, -- the driver level (Config.Levels) needed to buy it
	oneHanded: boolean?, -- fires out of a car window too (any seat); the two-handed guns only on foot
	exclusive: string?, -- 3.1: not sold, a reward nobody can buy (Config.Rewards: a campaign id, "secrets" or "challenges")
	pierce: number?, -- 3.1: the bullet goes on through this many more enemies
}

Config.Weapons = {
	{
		id = "pistol",
		oneHanded = true,
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
		level = 3,
		oneHanded = true,
		name = "SMG",
		price = 4000,
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
		level = 4,
		name = "Shotgun",
		price = 7500,
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
		level = 6,
		name = "Hunting Rifle",
		price = 15000,
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
		level = 10,
		name = "Minigun",
		price = 40000,
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
		level = 12,
		name = "Grenade Launcher",
		price = 60000,
		damage = 90,
		fireRate = 1.1,
		range = 150,
		pellets = 1,
		spread = 1,
		splash = 14,
		color = { 255, 110, 60 },
		description = "Every shot is a small explosion.",
	},
	-- Earned, not sold (Config.Employers weapon rewards).
	{
		id = "revolver",
		oneHanded = true,
		name = "Ranch Revolver",
		price = 0,
		damage = 42,
		fireRate = 1.6,
		range = 170,
		pellets = 1,
		spread = 0.3,
		splash = 0,
		color = { 255, 220, 160 },
		description = "Six shots of frontier justice. A gift from Silver Spur Ranch.",
		earned = "ranch",
	},
	{
		id = "carbine",
		name = "Army Carbine",
		price = 0,
		damage = 22,
		fireRate = 7,
		range = 200,
		pellets = 1,
		spread = 1,
		splash = 0,
		color = { 255, 235, 150 },
		description = "Army issue, steady full auto. The base gives it to the couriers it trusts.",
		earned = "army",
	},
	-- 3.1, exclusive: rewards nobody can buy (Config.Rewards). Finish a campaign, or every challenge.
	{
		id = "reyes",
		name = "Reyes' Carbine",
		price = 0,
		damage = 28,
		fireRate = 8,
		range = 220,
		pellets = 1,
		spread = 0.7,
		splash = 0,
		color = { 170, 210, 110 },
		description = "Captain Reyes' own rifle, given to the courier who kept the base alive.",
		exclusive = "army",
	},
	{
		id = "lever",
		name = "Walt's Lever Rifle",
		price = 0,
		damage = 72,
		fireRate = 1.5,
		range = 260,
		pellets = 1,
		spread = 0.15,
		splash = 0,
		color = { 240, 190, 120 },
		description = "Walt's grandfather's rifle. One shot goes through two of them.",
		exclusive = "ranch",
		pierce = 1,
	},
	{
		id = "goldpistol",
		oneHanded = true,
		name = "Vinnie's Golden Pistol",
		price = 0,
		damage = 38,
		fireRate = 4,
		range = 175,
		pellets = 1,
		spread = 0.4,
		splash = 0,
		color = { 255, 215, 60 },
		description = "Solid gold, solid stopping power. Vinnie only gives it to family.",
		exclusive = "underworld",
	},
	{
		id = "deadend",
		name = "Dead End",
		price = 0,
		damage = 64,
		fireRate = 5,
		range = 290,
		pellets = 1,
		spread = 0.25,
		splash = 0,
		color = { 190, 80, 255 },
		description = "The last courier's gun. Its rounds go through three of them. Nobody else has one.",
		exclusive = "challenges",
		pierce = 3,
	},
} :: { WeaponDef }

-- Car guns: bolted on the roof at Wrench Garage (one per car, on the cars with CarDef.mount), fired by the driver.
-- A car starts without one. The Gun Damage / Fire Rate upgrades work for them too (Economy.carGunStats).
export type CarGunDef = {
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
	level: number?, -- the driver level (Config.Levels) needed to buy it
}

Config.CarGuns = {
	{
		id = "roofmg",
		level = 5,
		name = "Roof Machine Gun",
		price = 9000,
		damage = 14,
		fireRate = 8,
		range = 180,
		pellets = 1,
		spread = 1.5,
		splash = 0,
		color = { 255, 210, 110 },
		description = "A belt-fed gun on a ring mount, an ammo box on the side.",
	},
	{
		id = "roofminigun",
		level = 10,
		name = "Roof Minigun",
		price = 45000,
		damage = 16,
		fireRate = 16,
		range = 180,
		pellets = 1,
		spread = 2.5,
		splash = 0,
		color = { 120, 220, 255 },
		description = "Six spinning barrels. Nothing on the road survives it.",
	},
	{
		id = "rooflauncher",
		level = 12,
		name = "Roof Grenade Launcher",
		price = 55000,
		damage = 80,
		fireRate = 1,
		range = 160,
		pellets = 1,
		spread = 1,
		splash = 14,
		color = { 255, 110, 60 },
		description = "A fat tube that lobs grenades. Clears a roadblock in one shot.",
	},
} :: { CarGunDef }

export type UpgradeDef = {
	id: string,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: number,
	costGrowth: number,
	perLevel: number, -- +x of the base value per level (loading: -x of the hold time)
	car: boolean?, -- 3.3: a car track: bought for one car (profile.carUpgrades[carId]); else for all your guns (profile.upgrades)
}

-- Wrench Garage. 3.3: the car tracks (car = true) belong to ONE car, the equipped one when you buy (the price grows
-- with that car's level; the company vehicles take none); the gun tracks count for all your guns and car guns. The
-- car tracks show on the car (server/Vehicles.luau): Ram Plow a bull bar (bigger with the level), Armor side plates
-- (and window grilles from level 3), Engine a hood scoop and twin exhaust pipes from level 3. Quick Hands makes the
-- holds of the back and the cargo shorter (Economy.loadHold).
-- 3.4: you keep your first car and upgrade it, so the first levels of the car tracks are cheap (a few deliveries)
-- and the last ones dear; the Cargo Rack adds a cargo slot per level (a roof rack with the extra slots on it,
-- Economy.capacity) for $300 · $750 · $1,880.
Config.Upgrades = {
	{ id = "engine", car = true, name = "Engine", description = "+8% top speed and acceleration · Lv 3: a hood scoop and twin pipes", maxLevel = 5, baseCost = 400, costGrowth = 2.0, perLevel = 0.08 },
	{ id = "handling", car = true, name = "Handling", description = "+8% steering", maxLevel = 5, baseCost = 300, costGrowth = 1.95, perLevel = 0.08 },
	{ id = "armor", car = true, name = "Armor", description = "+15% car health · side plates, Lv 3: window grilles", maxLevel = 5, baseCost = 350, costGrowth = 2.0, perLevel = 0.15 },
	{ id = "plow", car = true, name = "Ram Plow", description = "+30% ram damage · a bull bar on the front", maxLevel = 5, baseCost = 300, costGrowth = 1.95, perLevel = 0.30 },
	{ id = "loading", car = true, name = "Quick Hands", description = "−15% time to open the back, load and unload", maxLevel = 3, baseCost = 400, costGrowth = 2.0, perLevel = 0.15 },
	{ id = "rack", car = true, name = "Cargo Rack", description = "+1 cargo slot per level · a roof rack", maxLevel = 3, baseCost = 300, costGrowth = 2.5, perLevel = 1 },
	{ id = "damage", name = "Gun Damage", description = "+20% gun damage (car guns too)", maxLevel = 5, baseCost = 800, costGrowth = 1.85, perLevel = 0.20 },
	{ id = "firerate", name = "Fire Rate", description = "+12% shots per second (car guns too)", maxLevel = 5, baseCost = 800, costGrowth = 1.85, perLevel = 0.12 },
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

export type PaintDef = {
	id: string,
	name: string,
	price: number,
	color: { number }?,
	material: string?, -- 3.1: an Enum.Material name for the body (Neon, Foil, Glass, Metal …), else the car's own
	exclusive: string?, -- 3.1: not sold, a reward (Config.Rewards: a campaign id or "secrets")
}

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
	-- 3.1, exclusive: rewards (Config.Rewards), never sold.
	{ id = "dispatchyellow", name = "Dispatch Yellow", price = 0, color = { 255, 196, 30 }, material = "Metal", exclusive = "dispatch" },
	{ id = "medicmint", name = "Medic Mint", price = 0, color = { 150, 230, 205 }, exclusive = "clinic" },
	{ id = "freshlime", name = "Fresh Lime", price = 0, color = { 150, 220, 60 }, exclusive = "market" },
	{ id = "fireengine", name = "Fire Engine", price = 0, color = { 205, 25, 20 }, material = "Metal", exclusive = "firehouse" },
	{ id = "volt", name = "Volt Neon", price = 0, color = { 60, 170, 255 }, material = "Neon", exclusive = "power" },
	{ id = "toxicglow", name = "Toxic Glow", price = 0, color = { 120, 255, 80 }, material = "Neon", exclusive = "lab" },
	{ id = "sunrise", name = "Sunrise Chrome", price = 0, color = { 255, 170, 90 }, material = "Foil", exclusive = "exodus" },
	{ id = "phantom", name = "Phantom", price = 0, color = { 46, 44, 70 }, material = "Glass", exclusive = "secrets" },
	{ id = "tandem", name = "Tandem Twin", price = 0, color = { 236, 92, 60 }, material = "Metal", exclusive = "duo" },
} :: { PaintDef }

-- 3.1: what you get for finishing things (server/Challenges.luau gives it, client/MissionsUi.luau shows it). Every
-- campaign gives a title and an exclusive gun or paint; finding every secret package and finishing every challenge
-- (shared/Challenges.luau) give the rarest ones. Nothing here can be bought.
Config.Rewards = {
	Campaigns = {
		dispatch = { paint = "dispatchyellow", title = "Dispatcher's Favourite" },
		clinic = { paint = "medicmint", title = "Field Medic" },
		market = { paint = "freshlime", title = "Grocery Hero" },
		firehouse = { paint = "fireengine", title = "Smoke Eater" },
		army = { weapon = "reyes", title = "Quartermaster" },
		power = { paint = "volt", title = "Live Wire" },
		ranch = { weapon = "lever", title = "Outlaw Tamer" },
		lab = { paint = "toxicglow", title = "Cure Runner" },
		underworld = { weapon = "goldpistol", title = "Made Man" },
		exodus = { paint = "sunrise", title = "Last Convoy Captain" },
		duo = { paint = "tandem", title = "Partners in Crime" }, -- 3.2: the DUO campaign (only with a crew)
	} :: { [string]: { weapon: string?, paint: string?, title: string } },
	-- The lost packages hidden at every place (Map.Secrets): money for each, and for all of them …
	SecretMoney = 300,
	Secrets = { paint = "phantom", title = "Treasure Hunter", money = 25000 },
	-- … and for every challenge done: the gun nobody else has.
	Challenges = { weapon = "deadend", title = "The Last Courier", money = 50000 },
}

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
	-- People (bandits, gunners, the base's soldiers): they only go after players on a job (Zombies.hunts). Without
	-- one they stand guard; they never roam (Config.Horde.Roam).
	jobOnly: boolean?,
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
		jobOnly = true,
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
		jobOnly = true,
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
		jobOnly = true,
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
	-- Free roam: zombies (never bandits) shamble around every player who has no job and is out of the safe zone. They
	-- wander slowly around their spot and start hunting a player who comes close (a fast car is heard from further)
	-- or fires a gun nearby; out of reach for `giveUp` s they calm down again. Kills pay as always.
	Roam = {
		min = 6, -- keep min … max roamers around each player (a new number every `rethink` s)
		max = 10,
		rethink = 30,
		near = 150, -- they appear this far from the player …
		far = 320, -- … and no further; they count as "around" the player within far + 40
		every = 1, -- seconds between the checks, `batch` appear at a time
		batch = 2,
		reserve = 25, -- of Horde.MaxTotal, kept free for the jobs' waves
		despawn = 420, -- a roamer this far from every player goes (Horde.DespawnDistance for the others)
		kinds = { walker = 0.72, runner = 0.23, brute = 0.05 },
		wander = 18, -- studs around its spot
		wanderSpeed = 5, -- the shamble (it runs at its full speed once it hunts)
		idleChance = 0.4, -- how often it just stands for a while instead of a few steps
		think = 0.4, -- seconds between its looks around while calm
		aggro = 55, -- hunts a player on foot this close
		aggroCar = 45, -- a car: aggroCar + speed × aggroPerSpeed, at most aggroCarMax (a fast car is loud)
		aggroPerSpeed = 1,
		aggroCarMax = 110,
		gunHearing = 120, -- a shot this close wakes it
		chase = 200, -- keeps hunting while a target is this close …
		giveUp = 8, -- … and calms down after this many seconds without one
	},
	-- Zombies that live in the world all the time (they never despawn, the dead come back).
	Residents = { count = 36, respawn = 25 },
}

export type TierDef = {
	stars: number,
	name: string,
	level: number, -- the driver level (Config.Levels) that unlocks this danger level on the job board
	minDistance: number,
	maxDistance: number,
	basePay: number,
	payPerStud: number,
	-- The zombie waves of a job (server/Jobs.luau): the first one Config.Jobs.FirstWave s after you accept, then one
	-- every waveEvery s while you drive (not in the safe zone, not while you handle cargo on foot). Wave n has
	-- waveBase + waveGrow × (n − 1) zombies, at most waveMax, and never more than waveAlive of yours alive
	-- (Economy.waveSize / waveEvery / waveAlive; WANTED makes them bigger and faster).
	waveEvery: number,
	waveBase: number,
	waveGrow: number,
	waveMax: number,
	waveAlive: number,
	waveKinds: { [string]: number }, -- zombies only: the bandits come with roadblocks, chases and at the stops
	kinds: { [string]: number }, -- the ones that come on foot at the stops (Config.Cargo.FootWaves) and the guards
	guardHorde: number, -- enemies waiting at the destination
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

-- A person at a pick-up or a drop (an R15 NPC, server/Npcs.luau): role = the look (Npcs.look).
export type PersonDef = { name: string, title: string?, role: string }

-- A business on the job board: what it sends (pieces you carry by hand) and who would want it.
export type BusinessDef = {
	id: string,
	place: string, -- shown in the pick-up label ("PICK UP at the Pharmacy, ...")
	cargo: string, -- the job's cargo name
	piece: string, -- one piece ("medicine box")
	plural: string,
	kind: string, -- the Carrying kind (the carry pose): crate | ammo | sack | barrel | icebox | furniture | soup
	look: string, -- the model of a piece (server/Cargo.luau)
	pieces: { number }, -- min, max
	tiers: { number }, -- the danger levels it shows up in
	giver: PersonDef,
	receivers: { PersonDef },
}

-- Day and night (server/DayNight.luau): the clock runs, the night is dark, the street lamps and the headlights come
-- on, more zombies roam and the waves are bigger, and every delivery pays more.
Config.DayNight = {
	DayLength = 960, -- seconds for a whole day (24 h of game time)
	StartHour = 9, -- the clock when the server starts
	NightFrom = 18.25, -- the night: from this hour (the default Roblox sun sets at about 18:00) …
	NightTo = 6.25, -- … until this one (sunrise at about 6:00-6:15)
	NightPay = 1.4, -- pay multiplier for a job finished at night
	NightWaves = 1.5, -- wave size multiplier at night
	NightRoam = 1.6, -- roaming zombies multiplier at night
}

-- Driver levels (shared/Levels.luau): XP for every delivery, a rank for every level; levels unlock the danger levels
-- on the job board (Jobs.Tiers level), cars, guns and car guns (their level field), some special jobs, the
-- campaigns (shared/Missions.luau) and the real estate.
-- 3.2, the progression: the first clears of the whole story path (the 100 non-DUO missions' job XP × FirstClearXp,
-- no kills) give about 32 000 XP; level 15 needs 34 037 (XpBase 575 × 1.2^n). Played in order with about 10 kills a
-- mission (+40 XP) no mission is ever above your level: level 4 after First Shift (the pickup), 8 after Empty Shelves
-- (the muscle car), 13 after Wild West End, 14 by the end of Dirty Money and 15 inside Last Convoy. Without the kills
-- you come short around Patient Zero (a few hundred XP: a couple of board jobs). The DUO campaign, the job board
-- and the replays for stars come on top. 3.1 saves (the old curve, Legacy) keep their level (PlayerData, Curve).
Config.Levels = {
	MaxLevel = 15,
	XpBase = 575, -- XP needed for level 2; every next level needs XpGrowth times more (shared/Levels.luau xpFor)
	XpGrowth = 1.2,
	Curve = 2, -- 3.2: the version of the curve a save's XP is on (PlayerData saves it as xpCurve; older: Legacy)
	Legacy = { XpBase = 120, XpGrowth = 1.35 }, -- the 3.1 curve: such saves move to the same level here (Levels.fromLegacy)
	XpPerStar = 60, -- a finished delivery: stars × this …
	XpPerPiece = 10, -- … + per piece delivered …
	XpPerKill = 4, -- … + per enemy killed during the job
	XpNightBonus = 1.25, -- … × this at night
	XpFailed = 0.25, -- a failed job still gives this share
	Ranks = { -- the rank name from this level on
		{ level = 1, name = "Rookie Courier" },
		{ level = 2, name = "Courier" },
		{ level = 3, name = "Runner" },
		{ level = 4, name = "Road Rat" },
		{ level = 5, name = "Road Warrior" },
		{ level = 6, name = "Veteran Driver" },
		{ level = 8, name = "Wasteland Trucker" },
		{ level = 10, name = "Convoy Captain" },
		{ level = 12, name = "Dead End Legend" },
		{ level = 15, name = "King of the Road" },
	} :: { { level: number, name: string } },
}

-- Traffic (server/Traffic.luau): civilian cars driving the roads and people walking the sidewalks, near the players
-- only (they appear out of sight and disappear far away).
Config.Traffic = {
	CarsPerPlayer = 6,
	MaxCars = 24,
	PedestriansPerPlayer = 8,
	MaxPedestrians = 30,
	SpawnMin = 120,
	SpawnMax = 260,
	Despawn = 340,
	CarSpeed = 34,
}

-- Crews (server/Crew.luau): invite another player into your job (they ride along or follow, share the pay).
Config.Crew = {
	MaxMembers = 3,
	InviteRange = 60, -- studs to the player you invite (or use the crew button from anywhere)
	InviteTimeout = 30,
	RiderRange = 250, -- a rider who got out stays on the owner's job (paid, credited) within this of the owner
}

-- Real estate (server/Estate.luau): homes, garages and offices you buy with the money you made. A home is where you
-- spawn and its garage keeps cars; garages add car slots; an office runs your own delivery company
-- (Config.Business). Every player owns their own copy (saved in the profile): two owners of the same mansion on one
-- server both use it. Where each one stands is in shared/Map.luau (Map.EstatePlots, same ids).
-- 3.2: mostly the endgame. A house from 6, the villas at 10 – 11, the mansions at 13 – 15; the offices (your
-- company, Config.Business) at 12 – 15 and only after a campaign's finale (requires): the first one after Iron
-- Supply, the penthouse after the Last Convoy.
-- 3.4, cars are earned and kept in garages: the depot's lot holds only your starting van (BaseCarSlots = 1), every
-- further car needs a slot of a garage or a home. The first garages come early: the Rented Lockup (level 2, one
-- slot: the Courier Van needs it) and the Southside Garage (level 4, two slots), then the bigger ones. Your cars wait
-- in your garages: you switch cars only at one of them (server/Garages.luau; the depot lot for the starting van).
export type EstateDef = {
	id: string,
	name: string,
	kind: string, -- mansion | villa | house | garage | office
	price: number,
	garageSlots: number, -- car slots it adds (homes and garages)
	couriers: number?, -- offices: how many couriers your company can employ from there
	level: number?, -- the driver level (Config.Levels) needed to buy it
	requires: { string }?, -- 3.2: campaigns (shared/Missions.luau ids) whose finale must be done before you can buy it
	description: string,
}

Config.Estate = {
	BaseCarSlots = 1, -- the depot's lot: cars you can own without any garage (more need a home or a garage); 3.4: 1 (the starting van)
	SellBack = 0.6, -- selling returns this share of the price
	Properties = {
		{ id = "hilltop", name = "Hilltop Mansion", kind = "mansion", price = 6000000, garageSlots = 8, level = 15, description = "The top of Sunset Hills: the whole city at your feet, an infinity pool and a garage for eight." },
		{ id = "oceanview", name = "Ocean View Mansion", kind = "mansion", price = 4500000, garageSlots = 8, level = 14, description = "On the cliffs over the sea, glass all around, a private pier and a garage for eight." },
		{ id = "pinecrest", name = "Pinecrest Mansion", kind = "mansion", price = 3000000, garageSlots = 6, level = 13, description = "A stone mansion among the pines, a pool and a garage for six." },
		{ id = "lakeside", name = "Lakeside Villa", kind = "villa", price = 1500000, garageSlots = 4, level = 11, description = "A modern villa by the water with a garage for four." },
		{ id = "sunset", name = "Sunset Villa", kind = "villa", price = 1000000, garageSlots = 4, level = 10, description = "A white villa on the hill road, sunsets included. Garage for four." },
		{ id = "maple", name = "12 Maple Street", kind = "house", price = 300000, garageSlots = 2, level = 9, description = "A two-storey family house in the Suburbs with a double garage." },
		{ id = "oak", name = "7 Oak Lane", kind = "house", price = 220000, garageSlots = 2, level = 8, description = "A brick house with a porch and a double garage." },
		{ id = "birch", name = "Birch Cottage", kind = "house", price = 150000, garageSlots = 2, level = 7, description = "A cosy cottage at the edge of town, garage for two." },
		{ id = "elm", name = "Elm Bungalow", kind = "house", price = 90000, garageSlots = 1, level = 6, description = "A small bungalow: your first home, one car fits in the garage." },
		{ id = "garage_rented", name = "Rented Lockup", kind = "garage", price = 2500, garageSlots = 1, level = 2, description = "A rented lock-up between Downtown and the Suburbs: one car slot, your first garage." },
		{ id = "garage_south", name = "Southside Garage", kind = "garage", price = 12000, garageSlots = 2, level = 4, description = "A two-bay garage south of Downtown, on the road to the Suburbs: two more car slots." },
		{ id = "garage_harbor", name = "Harbor Lockup", kind = "garage", price = 25000, garageSlots = 4, level = 5, description = "A rented lock-up at the harbor: four more car slots." },
		{ id = "garage_north", name = "Highway Garage", kind = "garage", price = 45000, garageSlots = 4, level = 6, description = "A garage on the North Highway: four more car slots." },
		{ id = "garage_downtown", name = "Downtown Parking", kind = "garage", price = 70000, garageSlots = 6, level = 7, description = "A floor of the downtown parking house: six more car slots." },
		{ id = "office_harbor", name = "Harbor Point Office", kind = "office", price = 500000, garageSlots = 0, couriers = 3, level = 12, requires = { "army" }, description = "A room in the Harbor Point tower: start your own delivery company with up to 3 couriers." },
		{ id = "office_tower", name = "Dispatch Tower, 8th floor", kind = "office", price = 900000, garageSlots = 0, couriers = 6, level = 14, requires = { "underworld" }, description = "A corner office high in the Dispatch Tower: up to 6 couriers." },
		{ id = "office_penthouse", name = "Dispatch Tower Penthouse", kind = "office", price = 2500000, garageSlots = 0, couriers = 12, level = 15, requires = { "exodus" }, description = "The top floor of the Dispatch Tower: an empire of up to 12 couriers." },
	} :: { EstateDef },
}

-- Calling your car (server/CarCall.luau): it does not appear out of thin air: a chauffeur drives it to you along
-- the roads from out of sight, parks next to you, gets out, walks away and fades.
Config.CarCall = {
	ArriveWithin = 15, -- seconds; a car that is stuck is placed next to you at this point
	SpawnMin = 110, -- studs from you, along the roads
	SpawnMax = 200,
	Speed = 55,
	DriverFade = 2.5,
}

-- 3.4, the repair shops (server/Repair.luau, the bays: Map.RepairShops, built by server/World.luau): drive into a
-- bay, stop and get out; the mechanics take the car (it cannot be driven), and after the time it is as good as new.
-- The time and the fee grow with the damage (Economy.repairTime / repairFee); the fee is paid at the end, getting
-- back in (or calling the car away) cancels it for free. There is no free repair anywhere any more: the Repair Kit
-- (Config.Items) is the emergency fix on the road. A car keeps its damage when it is parked (profile.carHealth) and a
-- wrecked one comes back with WreckedHealth.
Config.Repair = {
	Seconds = 60, -- a car from (almost) nothing to full health
	MinSeconds = 20, -- the lightest damage
	FeeMin = 20, -- the lightest damage
	FeeFull = 300, -- a car from nothing to full health
	MinMissing = 0.02, -- less damage than this share: nothing to repair
	StandStill = 1.5, -- seconds the empty car stands in the bay before the mechanics start
	MaxSpeed = 2, -- studs / s: the car stands
	WreckedHealth = 0.2, -- a wrecked car comes back with this share of its health
}

-- Your delivery company (server/Business.luau), run from an office computer: hire couriers who make deliveries for
-- you while you play (and, less, while you are away), buy them vans, grow the company. 3.2: the endgame (the first
-- office is level 12 and after Iron Supply), priced like it.
Config.Business = {
	CourierCost = 40000, -- hiring one courier
	CourierPerMinute = 120, -- what one courier earns per minute while you are on the server
	OfflineShare = 0.4, -- while you are away they earn this share …
	OfflineHours = 8, -- … for at most this long
	SafeCap = 500000, -- the company's safe: earnings wait here until you collect them at the office
	Upgrades = { -- levels multiply the couriers' earnings
		{ id = "vans", name = "Better vans", description = "+15% per level: faster, safer deliveries", maxLevel = 5, baseCost = 60000, costGrowth = 1.9, perLevel = 0.15 },
		{ id = "dispatch", name = "Dispatch software", description = "+10% per level: smarter routes", maxLevel = 5, baseCost = 40000, costGrowth = 1.8, perLevel = 0.10 },
		{ id = "security", name = "Armed escorts", description = "+12% per level: fewer lost loads", maxLevel = 5, baseCost = 80000, costGrowth = 2.0, perLevel = 0.12 },
	} :: { { id: string, name: string, description: string, maxLevel: number, baseCost: number, costGrowth: number, perLevel: number } },
}

-- The game's own sounds and music (client/Sounds.luau; the sounds themselves: art/audio/make_audio.py, regions in
-- shared/SoundSheet.luau). Volumes 0..1; the SOUND button / N key cycles: everything on, music off, all off.
Config.Audio = {
	MusicVolume = 0.32,
	EffectsVolume = 0.7,
	MusicFade = 2.5, -- seconds of crossfade between two music loops
	TensionHold = 14, -- the tense loop keeps playing at least this long once it starts
	TensionAfterWave = 40, -- seconds of tense music after a zombie wave arrives
	TensionZombies = 3, -- … or while this many zombies are within TensionRange of you on a job
	TensionRange = 45,
	GroanEvery = 2.6, -- seconds between zombie groans (a random zombie near you; none when none is near)
	GroanRange = 70,
	HearRange = 260, -- other players' shots and explosions further away are not played
	MaxVoices = 24, -- 3D one-shot sounds at once
	-- The shot sound of every gun (hand guns and car guns; others fall back to gun_light).
	WeaponSounds = {
		pistol = "gun_light",
		smg = "gun_light",
		carbine = "gun_light",
		revolver = "gun_crack",
		rifle = "gun_crack",
		shotgun = "gun_heavy",
		minigun = "gun_rapid",
		launcher = "gun_launch",
		roofmg = "gun_light",
		roofminigun = "gun_rapid",
		rooflauncher = "gun_launch",
		reyes = "gun_light",
		lever = "gun_crack",
		goldpistol = "gun_crack",
		deadend = "gun_crack",
	} :: { [string]: string },
}

-- The missions (3.0): 10 campaigns of 10 story missions each (shared/Missions.luau), taken from the MISSIONS window
-- (U) anywhere, server checked (server/Missions.luau), played as jobs (server/Jobs.luau startMission) with twists.
-- Every mission is rated 1 – 3 stars; the best rating is saved (profile.missions).
Config.Missions = {
	-- The rating: done = 1 star; the cargo at least TwoStarCondition = 2; and with at least ThreeStarTime of the
	-- clock left = 3.
	TwoStarCondition = 0.75,
	ThreeStarTime = 0.3,
	StarBonus = 150, -- paid once for every new star (best rating goes up)
	FirstClearXp = 1.5, -- the XP of the first clear × this
	-- Co-op missions (MissionDef.coop): every crew member besides the owner adds this share of the pay (for everyone)
	-- and this share of enemies (waves, foot waves, hordes).
	CoopPayPerMember = 0.25,
	CoopEnemyPerMember = 0.35,
	CrewCredit = true, -- crew members who helped get the stars too (friends progress together)
	-- The twists (JobTypeDef.twists): what the card says and how much more they pay.
	Twists = {
		defend = { name = "HOLD OUT", icon = "🛡", description = "At the last drop, hold the area until the receiver is done, the dead come in waves", pay = 1.3 },
		lift = { name = "TWO-MAN LIFT", icon = "🏋", description = "Heavy pieces: alone you carry them slowly, with a crew mate beside you at full speed", pay = 1.25 },
		quiet = { name = "NO SHOOTING", icon = "🤫", description = "Explosive cargo: every shot from your crew costs cargo condition", pay = 1.35 },
		guarded = { name = "HOT ZONE", icon = "☣", description = "A horde waits at every stop", pay = 1.3 },
		night = { name = "NIGHT ONLY", icon = "🌙", description = "Only after dark", pay = 1.2 },
		gunner = { name = "SHOTGUN SEAT", icon = "🎯", description = "Kills from the passenger seats pay triple", pay = 1.1 },
		spotless = { name = "SPOTLESS", icon = "💎", description = "The cargo must arrive in good shape: below 60 % the mission fails", pay = 1.4 },
		hunted = { name = "HUNTED", icon = "🏴", description = "Bandit cars hunt you the whole way", pay = 1.35 },
		pair = { name = "PAIR LIFT", icon = "🤝", description = "These pieces only move with two of you carrying together", pay = 1.3 },
		switches = { name = "TWIN SWITCHES", icon = "🎛", description = "Two levers far apart must be pulled at the same moment to open the gate", pay = 1.25 },
	} :: { [string]: { name: string, icon: string, description: string, pay: number } },
	SpotlessFail = 0.6, -- spotless: the mission fails below this condition
	QuietCost = 0.06, -- quiet: condition lost per shot
	LiftSlowSpeed = 4.5, -- lift: walking speed carrying alone (with a crew mate within LiftHelpRange: normal)
	LiftHelpRange = 10,
	GunnerKillBonus = 3, -- gunner: a passenger's kill pays KillBonus × this
	HuntedBoost = 2.5, -- hunted: roadblocks and chases this many times as often
	DefendRadius = 45, -- defend: stay within this of the receiver
	DefendWaveEvery = 9, -- defend: a wave around the stop every … s
	GuardedHorde = 5, -- guarded: zombies waiting at every stop (× the tier's stars / 2, at least this)
	-- 3.2, DUO missions (MissionDef.duo, the "duo" campaign): only with a crew. START needs at least MinCrew crew
	-- members within StartRange of you; the twists made for two:
	--   pair      heavy pieces only move with two: nobody of the job within PairRange of the carrier, no pick-up
	--   switches  the stop's gate opens only when two levers are pulled within LeverWindow seconds of each other
	Duo = {
		MinCrew = 1,
		StartRange = 120,
		PairRange = 10,
		LeverWindow = 1.5,
		LeverApart = 22, -- studs between the two levers (one player cannot pull both in time)
	},
}

Config.Jobs = {
	DeliverRadius = 18,
	-- Every job is a list of stops. At a pick-up you park in the circle, get out, carry the pieces from the giver to
	-- the back of the vehicle and load them; at a drop you take them out and carry them to the receiver (Config.Cargo).
	-- The serve stops (ice cream) are the old way: hold still in the circle for the job type's unloadTime.
	HoldMaxSpeed = 8, -- the car must (almost) stand still in the circle
	PickupMinDistance = 120,
	PickupMaxDistance = 520,
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
	FirstWave = 15, -- seconds from accepting a job to its first zombie wave (see the tiers)
	WavePostpone = 5, -- a wave with no room (too many of yours alive) waits this long and tries again
	Tiers = {
		{
			stars = 1,
			level = 1,
			name = "Easy",
			minDistance = 150,
			maxDistance = 650,
			basePay = 80,
			payPerStud = 0.2,
			waveEvery = 40,
			waveBase = 2,
			waveGrow = 1,
			waveMax = 5,
			waveAlive = 7,
			waveKinds = { walker = 0.85, runner = 0.15 },
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
			level = 2,
			name = "Risky",
			minDistance = 550,
			maxDistance = 1200,
			basePay = 140,
			payPerStud = 0.3,
			waveEvery = 32,
			waveBase = 3,
			waveGrow = 1,
			waveMax = 7,
			waveAlive = 11,
			waveKinds = { walker = 0.65, runner = 0.3, brute = 0.05 },
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
			level = 4,
			name = "Deadly",
			minDistance = 1000,
			maxDistance = 2000,
			basePay = 260,
			payPerStud = 0.45,
			waveEvery = 26,
			waveBase = 4,
			waveGrow = 2,
			waveMax = 10,
			waveAlive = 16,
			waveKinds = { walker = 0.45, runner = 0.33, brute = 0.12, soldier = 0.1 },
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
			level = 7,
			name = "INSANE",
			minDistance = 1800,
			maxDistance = 99999,
			basePay = 500,
			payPerStud = 0.6,
			waveEvery = 20,
			waveBase = 6,
			waveGrow = 2,
			waveMax = 14,
			waveAlive = 22,
			waveKinds = { walker = 0.3, runner = 0.35, brute = 0.15, soldier = 0.2 },
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
		{ id = "horde", name = "WANTED", description = "Bigger, faster zombie waves, bandits want your cargo", payMultiplier = 1.5, timeMultiplier = 1, spawnMultiplier = 2, conditionMultiplier = 1, speedMultiplier = 1 },
	} :: { ModifierDef },
	-- How often (and how many) the bandits set up a roadblock ahead of you, see the tiers. A roadblock is a car across
	-- the road with bandits around it.
	AmbushDistance = 170,
	-- 3.4: bigger loads on the dangerous jobs (cargo capacity, Config.Cars capacity): an ordinary delivery of danger
	-- level n is a bulk order with BulkChance[n], its pieces + BulkExtra[n] (min, max). ★ never (3 pieces at most:
	-- every car takes them), ★★ rarely (5 at most), ★★★ up to 6, ★★★★ up to 8 (a big van or a Cargo Rack).
	BulkChance = { 0, 0.2, 0.45, 0.6 } :: { number },
	BulkExtra = { { 0, 0 }, { 1, 2 }, { 2, 3 }, { 3, 5 } } :: { { number } },
	-- The ordinary deliveries: every business sends what it makes or sells, to somebody who needs it.
	Businesses = {
		{
			id = "pizzeria",
			place = "Pizza Place",
			cargo = "Pizzas",
			piece = "pizza stack",
			plural = "pizza stacks",
			kind = "crate",
			look = "pizza",
			pieces = { 1, 2 },
			tiers = { 1, 2 },
			giver = { name = "Luigi", title = "Pizza chef", role = "cook" },
			receivers = {
				{ name = "Mrs. Hungry", title = "Ordered extra cheese", role = "townsperson" },
				{ name = "The Twins", title = "Night shift", role = "townsperson" },
				{ name = "Chief Brody", title = "Fire station", role = "worker" },
			},
		},
		{
			id = "bakery",
			place = "Bakery",
			cargo = "Fresh Bread",
			piece = "bread sack",
			plural = "bread sacks",
			kind = "sack",
			look = "bread",
			pieces = { 2, 3 },
			tiers = { 1, 2 },
			giver = { name = "Anna", title = "Baker", role = "cook" },
			receivers = {
				{ name = "Big Mike", title = "Survivor camp cook", role = "cook" },
				{ name = "Mr. Kowalski", title = "Corner shop", role = "shopkeeper" },
				{ name = "Grandma Rose", title = "Feeds the street", role = "townsperson" },
			},
		},
		{
			id = "post",
			place = "Post Office",
			cargo = "Parcels",
			piece = "parcel",
			plural = "parcels",
			kind = "crate",
			look = "parcel",
			pieces = { 1, 3 },
			tiers = { 1, 2, 3 },
			giver = { name = "Mr. Grant", title = "Postmaster", role = "clerk" },
			receivers = {
				{ name = "Grandma Rose", title = "Waiting for letters", role = "townsperson" },
				{ name = "The Mayor", title = "City hall", role = "clerk" },
				{ name = "Sal", title = "The last barber", role = "shopkeeper" },
			},
		},
		{
			id = "pharmacy",
			place = "Pharmacy",
			cargo = "Medicine",
			piece = "medicine box",
			plural = "medicine boxes",
			kind = "crate",
			look = "medicine",
			pieces = { 1, 3 },
			tiers = { 1, 2, 3 },
			giver = { name = "Mr. Patel", title = "Pharmacist", role = "clerk" },
			receivers = {
				{ name = "Dr. Novak", title = "Doctor", role = "clerk" },
				{ name = "Nurse Kim", title = "Rooftop clinic", role = "clerk" },
				{ name = "Grandma Rose", title = "Needs her pills", role = "townsperson" },
			},
		},
		{
			id = "supermarket",
			place = "Supermarket",
			cargo = "Groceries",
			piece = "grocery box",
			plural = "grocery boxes",
			kind = "crate",
			look = "groceries",
			pieces = { 2, 3 },
			tiers = { 1, 2 },
			giver = { name = "Carla", title = "Store manager", role = "shopkeeper" },
			receivers = {
				{ name = "Big Mike", title = "Survivor camp cook", role = "cook" },
				{ name = "Mrs. Hungry", title = "Empty fridge", role = "townsperson" },
				{ name = "Mr. Kowalski", title = "Corner shop", role = "shopkeeper" },
			},
		},
		{
			id = "hardware",
			place = "Hardware Store",
			cargo = "Tools",
			piece = "tool crate",
			plural = "tool crates",
			kind = "crate",
			look = "tools",
			pieces = { 1, 3 },
			tiers = { 2, 3 },
			giver = { name = "Bob", title = "Hardware store", role = "worker" },
			receivers = {
				{ name = "Chief Brody", title = "Fire station", role = "worker" },
				{ name = "Old Pete", title = "Fixing his roof", role = "townsperson" },
				{ name = "Officer Diaz", title = "Police bunker", role = "soldier" },
			},
		},
		{
			id = "electronics",
			place = "Electronics Store",
			cargo = "Radio Parts",
			piece = "parts box",
			plural = "parts boxes",
			kind = "crate",
			look = "parcel",
			pieces = { 1, 2 },
			tiers = { 2, 3 },
			giver = { name = "Kenji", title = "Electronics store", role = "clerk" },
			receivers = {
				{ name = "Sparks", title = "Ham radio operator", role = "worker" },
				{ name = "Officer Diaz", title = "Police bunker", role = "soldier" },
				{ name = "The Mayor", title = "City hall", role = "clerk" },
			},
		},
		{
			id = "pawnshop",
			place = "Pawn Shop",
			cargo = "Ammo",
			piece = "ammo crate",
			plural = "ammo crates",
			kind = "ammo",
			look = "ammo",
			pieces = { 1, 2 },
			tiers = { 2, 3, 4 },
			giver = { name = "Vinnie", title = "Pawn broker", role = "shopkeeper" },
			receivers = {
				{ name = "Officer Diaz", title = "Police bunker", role = "soldier" },
				{ name = "Jax", title = "Survivor camp guard", role = "worker" },
			},
		},
		{
			id = "warehouse",
			place = "Warehouse",
			cargo = "Generator Fuel",
			piece = "fuel barrel",
			plural = "fuel barrels",
			kind = "barrel",
			look = "barrel",
			pieces = { 1, 2 },
			tiers = { 2, 3, 4 },
			giver = { name = "Gus", title = "Warehouse keeper", role = "worker" },
			receivers = {
				{ name = "Nurse Kim", title = "The clinic's generator", role = "clerk" },
				{ name = "Sparks", title = "Ham radio operator", role = "worker" },
				{ name = "Old Pete", title = "Cold house", role = "townsperson" },
			},
		},
		{
			id = "lab",
			place = "Research Lab",
			cargo = "Vaccine",
			piece = "vaccine cooler",
			plural = "vaccine coolers",
			kind = "icebox",
			look = "vaccine",
			pieces = { 1, 2 },
			tiers = { 3, 4 },
			giver = { name = "Dr. Ito", title = "Lab scientist", role = "clerk" },
			receivers = {
				{ name = "Dr. Novak", title = "Doctor", role = "clerk" },
				{ name = "Nurse Kim", title = "Rooftop clinic", role = "clerk" },
			},
		},
		{
			id = "samples",
			place = "Research Lab",
			cargo = "Zombie Samples",
			piece = "sample case",
			plural = "sample cases",
			kind = "icebox",
			look = "sample",
			pieces = { 1, 2 },
			tiers = { 4 },
			giver = { name = "Dr. Ito", title = "Lab scientist", role = "clerk" },
			receivers = {
				{ name = "Dr. Novak", title = "Working on a cure", role = "clerk" },
			},
		},
		{
			id = "bank",
			place = "Bank",
			cargo = "Gold Bars",
			piece = "strongbox",
			plural = "strongboxes",
			kind = "crate",
			look = "gold",
			pieces = { 1, 2 },
			tiers = { 3, 4 },
			giver = { name = "Mr. Sterling", title = "Bank manager", role = "clerk" },
			receivers = {
				{ name = "The Mayor", title = "City hall", role = "clerk" },
				{ name = "Officer Diaz", title = "Police bunker", role = "soldier" },
			},
		},
		{
			id = "cake",
			place = "Bakery",
			cargo = "Wedding Cake",
			piece = "cake box",
			plural = "cake boxes",
			kind = "crate",
			look = "cake",
			pieces = { 1, 1 },
			tiers = { 3, 4 },
			giver = { name = "Anna", title = "Baker", role = "cook" },
			receivers = {
				{ name = "Lucy and Tom", title = "Getting married", role = "townsperson" },
			},
		},
	} :: { BusinessDef },
	-- At a far place the place's own person takes the ordinary deliveries.
	PlacePeople = {
		base = { name = "Sergeant Hayes", title = "Quartermaster", role = "soldier" },
		lodge = { name = "Ingrid", title = "Lodge keeper", role = "shopkeeper" },
		radio = { name = "Sparks", title = "Radio operator", role = "worker" },
		farm = { name = "Lucy", title = "Farm hand", role = "farmer" },
		docks = { name = "Rocco", title = "Dock foreman", role = "worker" },
		gas = { name = "Tony", title = "Pump attendant", role = "clerk" },
		school = { name = "Ms. Parker", title = "Teacher", role = "teacher" },
		frosty = { name = "Molly", title = "At the counter", role = "cook" },
		movers = { name = "Kofi", title = "Big Move Movers", role = "mover" },
		ranch = { name = "Jesse", title = "Ranch hand", role = "rancher" },
		stables = { name = "Emma", title = "Riding instructor", role = "rancher" },
		fueldepot = { name = "Hank", title = "Depot worker", role = "worker" },
	} :: { [string]: PersonDef },
	-- The look of the giver and the receiver of every special job (Config.JobTypes giver / receiver are the names).
	People = {
		schoolrun = { giver = "townsperson", receiver = "teacher" },
		armysupply = { giver = "worker", receiver = "soldier" },
		icecream = { giver = "cook", receiver = "kid" },
		moving = { giver = "townsperson", receiver = "townsperson" },
		farmrun = { giver = "farmer", receiver = "shopkeeper" },
		winter = { giver = "cook", receiver = "shopkeeper" },
		horses = { giver = "rancher", receiver = "rancher" },
		fuelrun = { giver = "worker", receiver = "shopkeeper" },
		cashrun = { giver = "banker", receiver = "soldier" }, -- Mr. Gold, the bank manager; Sergeant Hayes as at the base
		ambulance = { giver = "townsperson", receiver = "nurse" }, -- Nurse Ada; the patient walks in by themselves (board)
		pizzarush = { giver = "cook", receiver = "townsperson" },
	} :: { [string]: { giver: string, receiver: string } },
	-- The special jobs on the job board (JobTypeDef.board, or no employer): the chance of a first and of a second
	-- special card next to the ordinary deliveries every time the board is filled.
	BoardSpecials = { 0.65, 0.3 },
}

-- Cargo on foot (server/Cargo.luau): pick a piece up (E), carry it in your hands, load it into the back of the vehicle
-- (E); at the drop take it out and carry it to the receiver. Horses are led on a rope, kids and patients walk by
-- themselves (the patients slowly).
Config.Cargo = {
	-- The pieces of the special jobs (Config.JobTypes itemKind): the name and the model.
	Kinds = {
		crate = { piece = "crate", plural = "crates", look = "crate" },
		ammo = { piece = "ammo crate", plural = "ammo crates", look = "ammo" },
		sack = { piece = "sack of food", plural = "sacks of food", look = "sack" },
		barrel = { piece = "fuel barrel", plural = "fuel barrels", look = "barrel" },
		icebox = { piece = "ice box", plural = "ice boxes", look = "icebox" },
		furniture = { piece = "piece of furniture", plural = "pieces of furniture", look = "furniture" },
		soup = { piece = "soup box", plural = "soup boxes", look = "soup" },
		horse = { piece = "horse", plural = "horses", look = "horse" },
		kid = { piece = "kid", plural = "kids", look = "kid" },
		cash = { piece = "sack of cash", plural = "sacks of cash", look = "gold" },
		patient = { piece = "patient", plural = "patients", look = "patient" },
		pizza = { piece = "pizza stack", plural = "pizza stacks", look = "pizza" },
		-- 3.0 (the missions, shared/Missions.luau): looks the ordinary deliveries already had …
		medicine = { piece = "medicine box", plural = "medicine boxes", look = "medicine" },
		vaccine = { piece = "vaccine cooler", plural = "vaccine coolers", look = "vaccine" },
		sample = { piece = "sample case", plural = "sample cases", look = "sample" },
		groceries = { piece = "grocery bag", plural = "grocery bags", look = "groceries" },
		parcel = { piece = "parcel", plural = "parcels", look = "parcel" },
		tools = { piece = "toolbox", plural = "toolboxes", look = "tools" },
		bread = { piece = "bread sack", plural = "bread sacks", look = "bread" },
		cake = { piece = "cake box", plural = "cake boxes", look = "cake" },
		-- … and new ones (server/Cargo.luau builds them)
		water = { piece = "water jug", plural = "water jugs", look = "water" },
		generator = { piece = "generator", plural = "generators", look = "generator" },
		battery = { piece = "battery pack", plural = "battery packs", look = "battery" },
		tnt = { piece = "dynamite crate", plural = "dynamite crates", look = "tnt" },
		documents = { piece = "briefcase", plural = "briefcases", look = "documents" },
		electronics = { piece = "radio parts crate", plural = "radio parts crates", look = "electronics" },
		weapons = { piece = "weapons case", plural = "weapons cases", look = "weapons" },
		painting = { piece = "painting", plural = "paintings", look = "painting" },
		mail = { piece = "mail sack", plural = "mail sacks", look = "mail" },
		tires = { piece = "tire stack", plural = "tire stacks", look = "tires" },
		plants = { piece = "seedling tray", plural = "seedling trays", look = "plants" },
		survivor = { piece = "survivor", plural = "survivors", look = "survivor" }, -- board: they walk in themselves
	} :: { [string]: { piece: string, plural: string, look: string } },
	-- Extra seconds on the clock for every piece handled at a stop (loading and unloading each count).
	TimePerPiece = { carry = 9, lead = 14, board = 4, serve = 0 } :: { [string]: number },
	PayPerPiece = 15, -- an ordinary delivery pays this per piece on top of the tier's pay
	SpawnDistance = 300, -- the people and the cargo appear when the job's owner is this close to the stop
	ApproachDistance = 80, -- closer than this the HUD says what to do on foot and the enemies come on foot
	PileOffset = 12, -- an address without a cargo spot: the pile is this far from the road toward the building
	PromptDistance = 10,
	HoldDuration = 0.25, -- hold E this long to pick up / load / hand over
	MaxCarSpeed = 6, -- the vehicle must stand to load or unload it
	StealPieceRate = 3, -- bandits at the car: their steal share x this fills a meter, every full one = a piece gone
	KidGap = 0.9, -- seconds between the kids (or patients) getting on / off
	WalkTimeout = 14, -- a kid walking longer than this counts as arrived
	PatientWalkSpeed = 4.5, -- a patient shuffles slowly to the ambulance (the kids walk at 9)
	PatientWalkTimeout = 20, -- … and gets longer before it counts as arrived anyway
	Linger = 5, -- the people of a finished stop stay this long
	-- Enemies on foot while you handle the cargo at a stop (per danger tier): the first ones come FootGrace s after
	-- you get there, then `count` every `every` s while fewer than `max` of yours are alive.
	FootGrace = 8,
	FootWaves = {
		{ every = 0, count = 0, max = 0 },
		{ every = 16, count = 1, max = 5 },
		{ every = 13, count = 2, max = 7 },
		{ every = 10, count = 2, max = 9 },
	} :: { { every: number, count: number, max: number } },
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
	-- How the cargo gets in and out (server/Cargo.luau):
	--   carry  get out, pick one piece up (E), carry it in your hands to the car's back and load it (E); at the
	--          drop take it out of the car and carry it to the receiver
	--   lead   animals: lead one at a time on a rope (E) into the vehicle; at the drop lead them out to the receiver
	--   board  passengers walk in and out by themselves while you wait parked in the circle
	--   serve  park in the circle and hold still while the customers come (the old way)
	load: string,
	unload: string,
	items: number, -- pieces of cargo for the whole job (split over the drops)
	itemKind: string, -- the look of one piece: crate | ammo | sack | barrel | icebox | furniture | soup | horse | kid
	giver: string, -- the person (an R15 NPC) who hands the cargo over at the pick-up
	receiver: string, -- the person who takes it at the drop
	timeLimit: number?, -- a fixed time limit in seconds (a rush), instead of the distance-based one
	banditBoost: number?, -- bandits want this cargo: roadblocks and chases come this many times as often
	level: number?, -- the driver level (Config.Levels) needed to take it
	board: boolean?, -- on the job board (not taken at an employer's place)
	-- 3.0, the missions (shared/Missions.luau builds JobTypeDefs with these; Config.Missions.Twists):
	twists: { string }?, -- the mission's twists: defend | lift | quiet | guarded | night | gunner | spotless | hunted | pair | switches
	duo: boolean?, -- 3.2: only with a crew (Config.Missions.Duo)
	defendTime: number?, -- defend: seconds to hold out at the last drop
	coop: boolean?, -- made for a crew: pays more and gets harder with every member (Config.Missions)
	giverRole: string?, -- the look of the giver (server/Npcs.luau roles), else Config.Jobs.People / "townsperson"
	receiverRole: string?, -- the look of the receiver
	mission: string?, -- the mission id (shared/Missions.luau) when this job is a mission
}

-- Special jobs. The ones with an employer are taken at the employer's place; the others show up on the job board.
Config.JobTypes = {
	{
		id = "schoolrun",
		name = "School Run",
		description = "Pick the kids up at three homes and bring them to Sunny Hill School in the school bus.",
		vehicle = "bus",
		employer = "school",
		level = 2,
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
		load = "board",
		unload = "board",
		items = 6,
		itemKind = "kid",
		giver = "A parent",
		receiver = "Ms. Parker, the teacher",
	},
	{
		id = "armysupply",
		name = "Army Supply",
		description = "Load ammo at the Harbor Docks and drive it in the army's armored truck through the tunnel to the base.",
		vehicle = "armored",
		level = 7, -- 3.2: the armored truck it earns can carry a car gun
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
		load = "carry",
		unload = "carry",
		items = 4,
		itemKind = "ammo",
		giver = "Rocco, the dock foreman",
		receiver = "Sergeant Hayes",
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
		level = 2, -- 3.2: Risky, like the board's tier 2
		cargo = "Ice Cream",
		pickupLabel = "LOAD THE ICE CREAM",
		dropLabel = "SELL ICE CREAM AT",
		load = "carry",
		unload = "serve",
		items = 3,
		itemKind = "icebox",
		giver = "Molly, at the counter",
		receiver = "Kids with pocket money",
	},
	{
		id = "moving",
		name = "Moving Day",
		description = "Load a family's furniture at their house and unload it at their new home.",
		vehicle = "movingtruck",
		employer = "movers",
		level = 3,
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
		load = "carry",
		unload = "carry",
		items = 4,
		itemKind = "furniture",
		giver = "The Novak family",
		receiver = "The Novak family",
	},
	{
		id = "farmrun",
		name = "Farm Run",
		description = "Load fresh food at the Old Farm and bring it to two markets in the city.",
		vehicle = "monster",
		employer = "farm",
		level = 8,
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
		load = "carry",
		unload = "carry",
		items = 4,
		itemKind = "sack",
		giver = "Lucy, the farm hand",
		receiver = "The market grocer",
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
		load = "carry",
		unload = "carry",
		items = 2,
		itemKind = "soup",
		giver = "The diner cook",
		receiver = "Ingrid, the lodge keeper",
	},
	{
		id = "horses",
		name = "Horse Transport",
		description = "Lead two horses from Silver Spur Ranch into the livestock truck and bring them to the Riverside Riding School.",
		vehicle = "livestock",
		employer = "ranch",
		level = 5,
		pickups = 1,
		pickupAt = "ranch",
		drops = 1,
		dropAt = "stables",
		loadTime = 3,
		unloadTime = 3,
		payPerStop = 180,
		tier = 2,
		cargo = "Horses",
		pickupLabel = "LEAD THE HORSES IN AT",
		dropLabel = "LEAD THE HORSES OUT AT",
		load = "lead",
		unload = "lead",
		items = 2,
		itemKind = "horse",
		giver = "Jesse, the ranch hand",
		receiver = "Emma, the riding instructor",
	},
	{
		id = "fuelrun",
		name = "Fuel Run",
		description = "Load fuel barrels at the Harbor Fuel Depot and refill the Gas Station on the North Highway.",
		vehicle = "fueltruck",
		employer = "gas",
		level = 4,
		pickups = 1,
		pickupAt = "fueldepot",
		drops = 1,
		dropAt = "gas",
		loadTime = 3,
		unloadTime = 3,
		payPerStop = 160,
		tier = 3,
		cargo = "Fuel Barrels",
		pickupLabel = "LOAD THE BARRELS AT",
		dropLabel = "REFILL THE PUMPS AT",
		load = "carry",
		unload = "carry",
		items = 4,
		itemKind = "barrel",
		giver = "Hank, the depot worker",
		receiver = "Tony, the pump attendant",
	},
	{
		id = "cashrun",
		name = "Cash Transport",
		description = "Load sacks of cash at the First Zombie Bank into the army's armored truck and bring them to the Military Base vault. Every bandit in town wants this cargo.",
		vehicle = "armored",
		employer = nil,
		board = true,
		level = 5,
		pickups = 1,
		pickupAt = "bank",
		drops = 1,
		dropAt = "base",
		loadTime = 3,
		unloadTime = 3,
		payPerStop = 400,
		tier = 4,
		cargo = "Cash",
		pickupLabel = "LOAD THE CASH AT",
		dropLabel = "DELIVER THE CASH TO",
		load = "carry",
		unload = "carry",
		items = 3,
		itemKind = "cash",
		giver = "Mr. Gold, the bank manager",
		receiver = "Sergeant Hayes",
		banditBoost = 2,
	},
	{
		id = "ambulance",
		name = "Ambulance Run",
		description = "A patient is waiting at their home. Pick them up in the clinic's ambulance and rush them to the City Clinic before it is too late.",
		vehicle = "ambulance",
		employer = "clinic",
		level = 3,
		pickups = 1,
		pickupAt = nil,
		drops = 1,
		dropAt = "clinic",
		loadTime = 3,
		unloadTime = 3,
		payPerStop = 220,
		tier = 2,
		cargo = "Patient",
		pickupLabel = "PICK UP THE PATIENT AT",
		dropLabel = "RUSH THE PATIENT TO",
		load = "board",
		unload = "board",
		items = 1,
		itemKind = "patient",
		giver = "The patient's family",
		receiver = "Nurse Ada",
		timeLimit = 150,
	},
	{
		id = "pizzarush",
		name = "Pizza Rush",
		description = "Hot pizza, three minutes, no excuses. Pick up the order at Luigi's and deliver it before it gets cold.",
		vehicle = nil,
		employer = nil,
		board = true,
		level = 1,
		pickups = 1,
		pickupAt = nil,
		drops = 1,
		dropAt = nil,
		loadTime = 2,
		unloadTime = 2,
		payPerStop = 120,
		tier = 1,
		cargo = "Pizza",
		pickupLabel = "PICK UP THE PIZZA AT",
		dropLabel = "DELIVER THE PIZZA TO",
		load = "carry",
		unload = "carry",
		items = 1,
		itemKind = "pizza",
		giver = "Luigi, the pizza chef",
		receiver = "A hungry customer",
		timeLimit = 180,
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
	weapon: string?, -- a gun they give you (Config.Weapons, earned = this employer) …
	weaponAt: number?, -- … after this many jobs
	person: string, -- who runs it (the R15 NPC at their board)
}

-- People who run something in the world. Work for them: after a few jobs their vehicle is yours.
Config.Employers = {
	{ id = "school", name = "Sunny Hill School", icon = "🏫", jobType = "schoolrun", reward = "bus", needed = 3, person = "Principal Moore", pitch = "Our bus driver ran away. Drive the kids to school!" },
	{ id = "army", name = "Military Base", icon = "🪖", jobType = "armysupply", reward = "armored", needed = 4, weapon = "carbine", weaponAt = 2, person = "Captain Reyes", pitch = "We need ammo from the docks. Bring it through the tunnel." },
	{ id = "icecream", name = "Frosty's Ice Cream", icon = "🍦", jobType = "icecream", reward = "icecream", needed = 3, person = "Frosty", pitch = "People still want ice cream. Sell it for us!" },
	{ id = "movers", name = "Big Move Movers", icon = "🚚", jobType = "moving", reward = "movingtruck", needed = 3, person = "Dana, the boss", pitch = "Families are getting out of town. Move their things." },
	{ id = "farm", name = "Old Farm", icon = "🌽", jobType = "farmrun", reward = "monster", needed = 3, person = "Old Man Jenkins", pitch = "The city is hungry. Take my monster truck to the markets." },
	{ id = "ranch", name = "Silver Spur Ranch", icon = "🐴", jobType = "horses", reward = "livestock", needed = 4, weapon = "revolver", weaponAt = 2, person = "Walt, the rancher", pitch = "My horses are sold to the riding school. Lead them into the truck gently, and keep the bandits off them." },
	{ id = "clinic", name = "City Clinic", icon = "🏥", jobType = "ambulance", reward = "ambulance", needed = 3, person = "Dr. Novak", pitch = "The phones never stop ringing. Take the ambulance, bring the patients in alive." },
	{ id = "gas", name = "Gas Station", icon = "⛽", jobType = "fuelrun", reward = "fueltruck", needed = 3, person = "Rosa, the owner", pitch = "My pumps are dry. Bring fuel barrels from the harbor depot." },
} :: { EmployerDef }

return Config
