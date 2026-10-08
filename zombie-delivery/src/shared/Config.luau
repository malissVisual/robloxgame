--!strict
-- Every number of the game in one place: the cars, the guns, the upgrades, the items, the paints, the zombies and
-- the jobs. Pure data (colours are { r, g, b }), so the logic tests can load it outside Roblox.
-- The layout of the world (districts, roads, bridges, places) is in shared/Map.luau.

local Config = {}

-- Shown on the start screen: tells which version Studio really runs (bump it with every update).
Config.Version = "6.12.2"

-- 5.0 "From the bottom": everybody starts again on foot (a new store; the v1 saves stay stored and unread, so a
-- rollback is possible). A new player has no vehicle, $40 and a medkit (server/PlayerData.luau); 6.0: no gun either
-- (fists only: the pistol is bought at Lead & Co., Config.Arms).
Config.DataStoreName = "ZombieDelivery_v2"
Config.StartMoney = 40
Config.StudioStartMoney = 40 -- a Play test in Studio (no saves) starts like a new player; the admin panel (P) gives money for testing
Config.AutosaveSeconds = 60
-- 4.2: a save is locked to the server that plays it (UpdateAsync). A join waits this long for the last server's
-- leave save before it takes the save over; a lock not refreshed for SaveLockStale seconds is a crashed server's.
Config.SaveLockWait = 15
Config.SaveLockStale = 150
Config.SpawnCarCooldown = 4

-- 3.7: walking, the sprint and its breath (client/CameraRig.luau, client/Stamina.luau).
Config.Movement = {
	Walk = 14, -- studs per second (3.2.4: 12)
	Sprint = 28, -- with Shift (3.2.4: 25)
	Stamina = 6, -- seconds of sprint on a full breath
	Recover = 4, -- seconds to get the whole breath back (standing or walking)
	RecoverDelay = 0.8, -- the breath starts coming back this long after the sprint stops
	MinToSprint = 0.25, -- an empty breath: Shift sprints again only once this share is back (no stutter)
	Low = 0.2, -- the breath bar turns red at this share or less (and while out of breath)
	HideAfter = 1.5, -- seconds the bar stays after the breath is full again, then it fades out
}

-- 6.7, the body in motion (the owner: "the character isn't realistic at all, no animations"): the procedural layers
-- over the stock R15 tracks, as numbers. shared/BodyMotion.luau is the maths (tests/bodymotion_test.luau);
-- client/BodyLife.luau lays the idle life, the landing, the flinch and the walk's weight on every character and person
-- near the camera; client/ArmPose.luau the carry's reach to the box and the gestures with the legs ("pickup", "land").
-- Angles in degrees, distances in studs, times in seconds.
Config.Body = {
	Range = 120, -- studs from the camera: the characters and people posed (yours always) …
	MaxPosed = 40, -- … at most this many, the nearest
	Detail = 50, -- … the small motions (the breath, the weight shift, the head, the blinks) only this close
	Retarget = 0.4, -- seconds between the looks for whom to pose and where each head looks
	-- Breathing: the chest rises and falls; quicker and deeper after a sprint (Recover seconds to calm down).
	Breath = 3.6,
	BreathRun = 1.5,
	BreathTilt = 1.1, -- degrees the chest tips back on a breath in (twice that out of breath)
	BreathLift = 0.025, -- studs the shoulders rise
	Recover = 6,
	-- Standing still (under IdleBelow studs / s): the weight goes onto one foot, holds, then onto the other.
	IdleBelow = 1.5,
	ShiftEvery = 5.5, -- seconds per shift (each starts at a moment of its own)
	ShiftTime = 1.3, -- seconds the move from one foot to the other takes
	ShiftSway = 0.07, -- studs the hips move sideways
	ShiftRoll = 2.2, -- degrees the hips tip (the free side down)
	ShiftKnee = 9, -- degrees the free knee bends
	-- The head: a person or a courier within LookRange in front is looked at (your own courier also the job's ring
	-- within LookRing); at most LookYaw / LookPitch, the chest turning LookChest of it, followed at LookSpeed (1 / s).
	LookRange = 14,
	LookRing = 30,
	LookBehind = 110, -- degrees: farther round than this is not looked at
	LookYaw = 65,
	LookPitch = 25,
	LookChest = 0.3,
	LookSpeed = 5,
	-- Blinks (a face with EyeL / EyeR): every BlinkEvery seconds or so, shut for BlinkTime, to BlinkShut of the height.
	BlinkEvery = 4.2,
	BlinkTime = 0.14,
	BlinkShut = 0.12,
	-- The landing: a knee dip, from LandMin studs (falling at LandFrom studs / s) to LandDrop (at LandFull), LandDown
	-- seconds down and LandUp back up, the upper body tipping LandLean degrees forward at the deepest.
	LandFrom = 30,
	LandFull = 90,
	LandMin = 0.12,
	LandDrop = 0.5,
	LandDown = 0.08,
	LandUp = 0.34,
	LandLean = 12,
	-- Hit (health lost, FlinchMin at least): the chest jerks back FlinchBack degrees, the head turns FlinchTurn,
	-- FlinchIn seconds in, FlinchOut back.
	FlinchMin = 3,
	FlinchIn = 0.06,
	FlinchOut = 0.38,
	FlinchBack = 10,
	FlinchTurn = 16,
	-- The walk (WalkFrom studs / s up to Config.Courier.Sprint.From, where client/SprintPose.luau's run takes over): the
	-- stock walk's own thighs give the weight: the body sinks WalkBob studs with the legs apart (Spread degrees at the
	-- widest), the arms swing WalkArm of the legs' spread more, the chest turns WalkTwist degrees against the hips.
	WalkFrom = 4,
	WalkBob = 0.09,
	WalkArm = 0.45,
	WalkTwist = 4,
	Spread = 50,
	-- The carry (client/ArmPose.luau): the hands reach the box's sides (server/Cargo.luau's CarryAt / CarrySize on the
	-- character), CarryLow of its height under its middle; the upper body leans back CarryLean degrees with both hands
	-- full, CarryHeavy when the load slows you (CarrySpeed).
	CarryLow = 0.15,
	CarryLean = 4,
	CarryHeavy = 8,
	-- The phone lies in the palm (shared/KitFit.luau Palm): the wrist rolls it this many degrees, the screen up.
	PhoneRoll = -90,
	-- The gestures with the legs (shared/Gestures.luau, posed by client/ArmPose.luau): "pickup" crouches PickupDrop
	-- studs (at most 0.8: client/Unstuck.luau resets a Root joint hung lower), the hips tip PickupHips and the waist
	-- PickupBend degrees, the right hand reaching down; "land" is a short dip. Seconds each.
	PickupDrop = 0.7,
	PickupHips = 30,
	PickupBend = 45,
	-- A piece picked up off the ground stays where it lies this long (server/Cargo.luau), the hands reaching down to
	-- it, then comes up into them as the body rises.
	PickupLift = 0.4,
	Gestures = { pickup = 0.7, land = 0.42 } :: { [string]: number },
}

-- 3.9: the gun goes away (B: holster / draw) and the hands fight (V: melee). Holstered (the default after every spawn)
-- the hands are empty, V punches; with the gun out V strikes with it (a pistol-whip, a rifle butt). The server checks
-- every swing (server/CloseCombat.luau) and hits the nearest living zombie or bandit in a short cone in front of you
-- (shared/Melee.luau); everybody sees the right arm swing (client/ArmPose.luau). No headshots; kills count as usual.
-- 6.7, the Baseball Bat (Config.Kit "bat", BatKit: $150 at Lead & Co.): owned, V with the gun away (fists or the bag)
-- swings the bat instead of a punch (Melee.kindOf): its own damage, cooldown, push and a longer `reach` (studs; the
-- others use Reach). The arm reuses the gun's overhead strike (Poses: the MeleeKind attribute client/ArmPose.luau
-- reads), and a bat is welded into the right hand for the swing only (server/CloseCombat.luau, BatLook).
Config.Melee = {
	Reach = 5.5, -- studs from your root to the enemy's root, along the ground
	HalfAngle = 70, -- degrees to either side of where you swing
	Height = 5, -- studs up or down at most (a body on a ledge above you is out of reach)
	SwingTime = 0.25, -- seconds the arm swings forward and back (client/ArmPose.luau)
	Kinds = {
		punch = { damage = 12, cooldown = 0.55, push = 22 }, -- the fist (holstered)
		gun = { damage = 22, cooldown = 0.8, push = 38 }, -- the gun in the hand
		bat = { damage = 30, cooldown = 0.7, push = 44, reach = 7 }, -- 6.7: the Baseball Bat (a walker in two swings)
	} :: { [string]: { damage: number, cooldown: number, push: number, reach: number? } },
	BatKit = "bat", -- 6.7: the Config.Kit id that turns the punch into a bat swing
	Poses = { bat = "gun" } :: { [string]: string }, -- 6.7: a kind's arm swing when it has none of its own
	-- 6.7: the bat in the hand during a swing (studs, RGB): the handle and the barrel along the hand's grip, gone after
	-- SwingTime + Linger seconds
	BatLook = { Length = 3.2, Handle = 0.22, Barrel = 0.4, Wood = { 196, 150, 96 }, Grip = { 40, 40, 44 }, Linger = 0.1 },
}

-- 6.0: no free gun; 6.0.2: the start kit is the phone, the pistol (Starter) and the plastic bag. 6.7: so the pistol is
-- not sold any more (WeaponDef starter: "STARTER · yours" at Lead & Co.) and Marge's old "buy a pistol" text is gone
-- (every profile has it: server/PlayerData.luau newProfile, starterKit). The vests' numbers are in Config.Kit
-- (armour); MaxArmour caps any vest's share (shared/Armour.luau).
Config.Arms = {
	Starter = "pistol",
	MaxArmour = 0.8,
	-- 6.0.1: Marge's text about the plastic bag (server/Tutorial.luau bagCheck); 6.7: the vest's tips
	-- 6.12.2: Last Stop Supplies is the GEAR counter of the gear stall by the spawn, ZDC Bags the counter next to it
	BagTip = "Customers tip a courier they can see: the ZDC Courier Vest ({price}) adds 5% to every delivery. Last Stop Supplies sells it at the gear stall by the spawn. It's on your GPS. Bags are at the counter next to it.",
}

-- 3.7: the first-day tutorial (server/Tutorial.luau, client/TutorialUi.luau): the dispatcher at the depot greets a new
-- player, gives them the first job and explains each step until it is delivered. 6.7: she shows the screen with an
-- arrow tour (client/TutorialArrow.luau) and gives no job: you take any one, the first delivery pays Reward.
Config.Tutorial = {
	NpcName = "Marge",
	NpcTitle = "Dispatcher",
	Reward = 50, -- money for the first delivery (6.7: of any job, on top of its pay; a skipped tutorial pays none)
	NpcSpot = { -4, -20 }, -- where she stands, studs from the depot's centre (Map.Shops.depot): by the job board, facing the yard
	TalkRange = 10, -- her Talk prompt's reach (the job board's own prompt stays out of it)
	StartDelay = 2, -- seconds after PLAY before her welcome shows (6.7: on its own; the start screen fades out first)
	RetryAfter = 1.5, -- a first job gone this long without a result (a special job ended, an admin): back to "board"
	InStudio = true, -- a Studio Play test (no saves: a new profile every time) runs it too; false skips it there
	-- 6.7: the arrow tour of the screen (client/TutorialArrow.luau; px at the screen's scale)
	TourBounce = 10, -- how far the arrow bounces back from its target
	TourBounceSpeed = 1.6, -- bounces a second
	TourGap = 8, -- between the target and the arrow's tip
	TourCaptionWidth = 300, -- the caption box's width
}

-- 3.7: the map you discover (shared/Explore.luau, server/Explore.luau, client/MapView.luau, the minimap in Hud).
Config.Explore = {
	Cell = 120, -- the map is a grid of cells this many studs wide; you uncover the ones around you
	Radius = 180, -- studs around you that are uncovered
	Every = 1, -- seconds between two checks of where you are
	PlaceRadius = 70, -- this close to a place (a shop, an employer, a mission place) and it is discovered
	-- The grid covers Map.Bounds and this much more on every side (the world's walls stand on Map.Bounds).
	Pad = 60,
	-- A new player (or a save from before 3.7) starts with the cells over this square around the middle uncovered
	-- (the safe zone, Config.City.SafeHalf, and a little more; the park, the depot and the shops): nobody starts lost.
	StartHalf = 240,
	-- A jump farther than this between two checks is a teleport (the admin, a home spawn): the way between is not
	-- uncovered. Shorter (a fast car): the cells along the way are.
	Teleport = 600,
	Banner = 3, -- seconds the "NEW LOCATION DISCOVERED" banner stays (client/Discovery.luau; shorter while more wait)
}

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
	SafeHalf = 235, -- the safe zone round the middle (6.11: the Central Park; the depot is in it): a square, |x|, |z| below this
	-- 6.10, the curb (Map.WalkTop, Map.CurbRun; shared/CurbShape.luau): the vehicle you drive, over a kerb, rises at most
	-- this fast (studs / s; client/CurbRide.luau): it drives up the slope and stays on the walk instead of hopping off it
	CurbHop = 6,
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
	-- (server/Vehicles.luau STYLES cargo; tests/run_tests.py checks they match). 3.5: the slots of stage 0.
	role: string?, -- 3.5: what the car is for, in a few words (the dealer's card, the README's table)
	stages: { StageDef }?, -- 3.5: the stages bought at Wrench Garage; stages[1] is stage 0 (the car as it is sold)
	-- 4.0, freight: how many PALLETS it takes (nil: none). A pallet fills Config.Cargo.PalletSlots of its cargo slots
	-- (the first ones: a car's slots begin with a 2 x 2 group at the front of the box; the Freight Truck's are three
	-- such bays, front to back). A stage's own `pallets` wins (StageDef.pallets); Economy.palletsOf(carId, stage).
	pallets: number?,
	-- 4.0: may it take the Hand Trolley (4.6: Config.Gear "trolley": the vans and the trucks)? Economy.gearFits.
	trolley: boolean?,
	-- 4.6: the gear slots (Config.Gear pieces installed at once at Wrench Garage). A stage's own gearSlots wins
	-- (StageDef.gearSlots); nil: none (the company vehicles come with what their job needs). Economy.gearSlots.
	gearSlots: number?,
	-- 5.1: a bicycle (style "bike"; Config.Cars ids rustbike, citybike, cargobike, ebike, appended after the cars): sold at
	-- Spoke & Chain (Map.Shops.bikes), light cargo only, no fuel, no traffic / chauffeur / car gun / paint / car
	-- upgrade tracks; it never counts as "a vehicle" for car jobs and missions (shared/Transport.luau mode "bike").
	bike: boolean?,
	-- 5.1.1: the rider stands (the E-Scooter, style "scooter": a deck, no saddle, no pedals; client/BikeRider.luau's
	-- standing pose through shared/RiderPose.luau), and a badge on its card at Spoke & Chain ("⚡ ELECTRIC · STAND-UP").
	stand: boolean?,
	badge: string?,
	-- 5.4, fuel (Config.Fuel, shared/FuelMath.luau): the tank in litres and what it burns, litres per 1,000 studs driven.
	-- Every car has both; a bike has none (no fuel).
	tank: number?,
	burn: number?,
}

-- 3.5, a stage of a car (CarDef.stages): bought at Wrench Garage one after the other for the car you drive. Each one
-- changes how the car looks (server/Vehicles.luau LOOKS[look]: boxes added on the body, some taken off, its own
-- cargo slots) and how much it holds; a little more health, a small speed tweak. stages[1] is stage 0 (no price, no
-- look: the plain body of STYLES); the saved stage is profile.carUpgrades[carId].stage (Economy.stageOf).
export type StageDef = {
	name: string, -- what the car is called at this stage ("Work Van")
	price: number, -- 0 for stage 0
	level: number?, -- the driver level needed to buy it
	capacity: number, -- the cargo slots at this stage (= its look's slots; tests/run_tests.py checks it)
	health: number?, -- + health over the car's own (before the Armor upgrade)
	speed: number?, -- + top speed in studs / s (may be negative: a high roof is heavier)
	accel: number?, -- 4.0: + acceleration in studs / s² (the Old Van's stages rebuild a slow, heavy van)
	look: string?, -- the look in server/Vehicles.luau LOOKS (nil: the plain body; 4.0: a look may stretch the body)
	pallets: number?, -- 4.0: the pallets it takes at this stage (wins over CarDef.pallets; Economy.palletsOf)
	gearSlots: number?, -- 4.6: the gear slots at this stage (wins over CarDef.gearSlots; Economy.gearSlots)
	adds: string, -- what it adds, in a few words (the STAGE card)
}

-- 3.2, the progression (Config.Levels): the van is where you start, the pickup opens at level 4, the muscle car at 8
-- (a fourth car needs a slot: a garage from level 5, Config.Estate). The guns and the car guns open the same way.
-- 3.3: five more vans in between, each with its own body (server/Vehicles.luau STYLES): the Courier Van at 2, the
-- High-Roof Van at 3, the Box Truck at 6, the Armored Van at 10 and the Rally Van at 12. The dealer's cars stay in
-- the order of their level (and price): the showroom and the dealer window list them this way.
-- 3.4: every car has a capacity (cargo slots); a job or a mission with more pieces than your car holds waits until
-- you have a bigger car. The employers' vehicles hold what their jobs need.
-- 3.5: STAGES instead of the Cargo Rack. You keep your Old Van and build it up at Wrench Garage: the Rusty Van (2
-- slots) becomes a Work Van (3) and a Cargo Van (4), each stage with its own look. 4 is where a van ends: more needs a
-- bigger vehicle. The other cars are not "the next van" but have a ROLE (CarDef.role): the Courier Van is fast, the
-- High-Roof Van the tougher in-between, the Box Truck the big one (6 – 8 slots, the only way to 6 and more), the
-- Armored Van the car-gun platform, the Rally Van the fastest, the Pickup the crew car, the Muscle Car the getaway
-- car. Each has one or two small stages of its own.
-- 4.0, Freight: the Old Van starts SLOW (max 42, accel 11: about 3.5 s to its top speed through a gentle torque curve,
-- Economy.torque, client/Drive.luau) and has a longer way up: Rusty Van (2) → Patched Van (2, $250) → Work Van (3,
-- $700, a body 1.5 studs longer) → Long Cargo Van (4, $2,200, 3.5 studs longer, a high roof). Every stage adds speed
-- and acceleration (StageDef speed, accel); the Engine upgrade is the other way up. A stage's look may STRETCH the body
-- (server/Vehicles.luau Look.stretch): more room makes the car bigger. The Box Truck's last stage is longer too and
-- takes a pallet. The Freight Truck (level 9: 12 slots or 3 pallets, a roll-up door, its own pallet jack) is the big
-- one; the Moving Truck takes a pallet. CarDef.trolley marks the vans and trucks that may take the Hand Trolley.
Config.Cars = {
	{
		id = "van",
		mount = true,
		trolley = true,
		name = "Old Van",
		level = 4, -- 5.0: bought from Earl at Earl's Used Wheels (Config.VanQuest: Marge's quest; you start on foot)
		price = 1800,
		style = "van",
		maxSpeed = 42,
		accel = 11,
		turn = 1.8,
		health = 300,
		capacity = 2,
		tank = 40, -- 5.4: litres (Config.Fuel)
		burn = 12, -- litres per 1,000 studs
		ramPower = 1.0,
		color = { 214, 196, 160 },
		role = "Your first vehicle: it grows with you",
		description = "Rusty, dented, slow off the line, and yours. Build it up at Wrench Garage: a Patched Van, a Work Van (3 slots, a longer body), then a Long Cargo Van (4, a high roof). 1 passenger.",
		stages = {
			{ name = "Rusty Van", price = 0, capacity = 2, gearSlots = 1, adds = "rust patches, a primer-grey door, a crooked bumper, a cracked windscreen, bald tyres, a yellowed headlight, a smoking exhaust" },
			{ name = "Patched Van", price = 250, level = 4, capacity = 2, gearSlots = 1, health = 20, speed = 6, accel = 4, look = "van_patched", adds = "the rust ground off and patched in grey primer, a straight new bumper; a quicker, healthier van" },
			{ name = "Work Van", price = 700, level = 5, capacity = 3, gearSlots = 2, health = 40, speed = 12, accel = 8, look = "van_work", adds = "clean paint, a chrome bumper, a new windscreen and lamps, a ladder, shelves, a body 1.5 studs longer" },
			{ name = "Long Cargo Van", price = 2200, level = 6, capacity = 4, gearSlots = 3, health = 70, speed = 14, accel = 10, look = "van_cargo", adds = "a body 3.5 studs longer with a high roof, a roof rack, a light bar, mud flaps" },
		},
	},
	{
		id = "courier",
		gearSlots = 2, -- 4.6
		trolley = true,
		level = 5,
		mount = true,
		name = "Courier Van",
		price = 3500,
		style = "courier",
		maxSpeed = 70,
		accel = 31,
		turn = 2.05,
		health = 320,
		capacity = 2,
		tank = 35, -- 5.4: litres (Config.Fuel)
		burn = 7, -- litres per 1,000 studs
		ramPower = 1.0,
		color = { 232, 170, 40 },
		role = "Fast and nimble: the rush jobs",
		description = "Small, low and quick off the line, an amber light bar on the roof. Made for speed, not for big loads (2 slots, 3 as an Express Courier). 1 passenger.",
		stages = {
			{ name = "Courier Van", price = 0, capacity = 2, adds = "" },
			{ name = "Express Courier", price = 1200, level = 6, capacity = 3, speed = 2, look = "courier_express", adds = "a roof pod, a checker stripe down the sides" },
		},
	},
	{
		id = "highroof",
		gearSlots = 3, -- 4.6
		trolley = true,
		level = 5,
		mount = true,
		name = "High-Roof Van",
		price = 7000,
		style = "highroof",
		maxSpeed = 62,
		accel = 27,
		turn = 1.75,
		health = 450,
		capacity = 4,
		tank = 50, -- 5.4: litres (Config.Fuel)
		burn = 10, -- litres per 1,000 studs
		ramPower = 1.1,
		color = { 168, 186, 200 },
		role = "Tougher, the in-between",
		description = "Stand up inside: a tall roof, thicker walls and a jump seat for a friend. 4 slots from the start, 5 as a Tall Hauler. 2 passengers.",
		stages = {
			{ name = "High-Roof Van", price = 0, capacity = 4, adds = "" },
			{ name = "Tall Hauler", price = 3000, level = 7, capacity = 5, health = 60, look = "highroof_hauler", adds = "a ladder rack with a spare wheel, side steps, a stacked shelf" },
		},
	},
	{
		id = "pickup",
		gearSlots = 2, -- 4.6
		level = 6,
		mount = true,
		name = "Pickup",
		price = 12000,
		style = "pickup",
		maxSpeed = 72,
		accel = 32,
		turn = 2.0,
		health = 420,
		capacity = 2,
		tank = 60, -- 5.4: litres (Config.Fuel)
		burn = 8, -- litres per 1,000 studs
		ramPower = 1.15,
		color = { 196, 60, 50 },
		role = "The crew car: friends shoot from the bed",
		description = "An open bed where two friends ride and shoot. Room for 2 pieces beside them (3 as a Ranch Pickup). 3 passengers.",
		stages = {
			{ name = "Pickup", price = 0, capacity = 2, adds = "" },
			{ name = "Ranch Pickup", price = 2500, level = 7, capacity = 3, health = 50, look = "pickup_ranch", adds = "a roll bar with spotlights, chrome bed rails" },
		},
	},
	{
		id = "boxtruck",
		gearSlots = 3, -- 4.6
		trolley = true,
		level = 7,
		mount = true,
		name = "Box Truck",
		price = 22000,
		style = "boxtruck",
		maxSpeed = 64,
		accel = 26,
		turn = 1.6,
		health = 650,
		capacity = 6,
		tank = 80, -- 5.4: litres (Config.Fuel)
		burn = 10, -- litres per 1,000 studs
		ramPower = 1.4,
		color = { 238, 238, 232 },
		role = "The big one: the only way to 6 and more",
		description = "A cab and a big box behind it. Slow to stop, hard to kill: 6 slots, 8 as a Freight Hauler (a longer box that takes a pallet). The big loads need it. 2 passengers.",
		stages = {
			{ name = "Box Truck", price = 0, capacity = 6, gearSlots = 3, adds = "" },
			{ name = "Liftgate Truck", price = 7500, level = 9, capacity = 7, gearSlots = 3, health = 80, look = "boxtruck_lift", adds = "a liftgate, marker lights, a chrome bumper, a stacked row" },
			{ name = "Freight Hauler", price = 15000, level = 11, capacity = 8, gearSlots = 4, health = 150, speed = -2, pallets = 1, look = "boxtruck_freight", adds = "a box 3 studs longer (a fourth row on the floor) that takes a pallet, a tall wind deflector, side skirts" },
		},
	},
	{
		id = "muscle",
		gearSlots = 1, -- 4.6
		level = 9,
		mount = true,
		name = "Muscle Car",
		price = 40000,
		style = "muscle",
		maxSpeed = 95,
		accel = 46,
		turn = 2.3,
		health = 340,
		capacity = 2, -- 6.7: two in the trunk (one was too little for a $40,000 car)
		tank = 65, -- 5.4: litres (Config.Fuel)
		burn = 7, -- litres per 1,000 studs
		ramPower = 1.0,
		color = { 30, 30, 36 },
		role = "The getaway car: two pieces, all speed",
		description = "Outruns every zombie. Two pieces in the trunk (3 as a Street Machine). Do not crash. 1 passenger.",
		stages = {
			{ name = "Muscle Car", price = 0, capacity = 2, adds = "" },
			{ name = "Street Machine", price = 6000, level = 10, capacity = 3, speed = 3, look = "muscle_street", adds = "a blower on the hood, side pipes, a wider trunk (3 pieces)" },
		},
	},
	{
		id = "freight",
		gearSlots = 4, -- 4.6
		level = 10,
		trolley = true,
		pallets = 3,
		name = "Freight Truck",
		price = 45000,
		style = "freighttruck",
		maxSpeed = 45,
		accel = 12,
		turn = 1.2,
		health = 900,
		capacity = 12,
		tank = 120, -- 5.4: litres (Config.Fuel)
		burn = 11, -- litres per 1,000 studs
		ramPower = 2.0,
		color = { 46, 88, 150 },
		role = "Warehouse freight: pallets and 12 slots",
		description = "A cab-over truck with a long box, a roll-up door and a loading floor at dock height: 12 slots or 3 pallets, its own pallet jack inside. Slow and heavy, no car gun. 1 passenger.",
		stages = {
			{ name = "Freight Truck", price = 0, capacity = 12, adds = "" },
		},
	},
	{
		id = "armorvan",
		gearSlots = 3, -- 4.6
		level = 11,
		mount = true,
		name = "Armored Van",
		price = 55000,
		style = "armorvan",
		maxSpeed = 74,
		accel = 34,
		turn = 1.8,
		health = 900,
		capacity = 3,
		tank = 90, -- 5.4: litres (Config.Fuel)
		burn = 9, -- litres per 1,000 studs
		ramPower = 1.6,
		color = { 72, 78, 84 },
		role = "Very tough: the car-gun platform",
		description = "Steel plates, grilles on the windows, a roof made for a gun. The bullets knock, nobody answers. 3 slots, 4 as a Fortress Van. 2 passengers.",
		stages = {
			{ name = "Armored Van", price = 0, capacity = 3, adds = "" },
			{ name = "Fortress Van", price = 14000, level = 12, capacity = 4, health = 200, speed = -2, look = "armorvan_fortress", adds = "a gun shield on the roof, side lockers, a spare wheel" },
		},
	},
	{
		id = "rallyvan",
		gearSlots = 2, -- 4.6
		level = 13,
		mount = true,
		name = "Rally Van",
		price = 80000,
		style = "rallyvan",
		maxSpeed = 98,
		accel = 46,
		turn = 2.25,
		health = 420,
		capacity = 2,
		tank = 55, -- 5.4: litres (Config.Fuel)
		burn = 6, -- litres per 1,000 studs
		ramPower = 1.1,
		color = { 30, 90, 200 },
		role = "The fastest van: rush jobs",
		description = "Lowered, striped, a spoiler and big wheels: the fastest van on the road, 2 slots and no more. 1 passenger.",
		stages = {
			{ name = "Rally Van", price = 0, capacity = 2, adds = "" },
			{ name = "Works Rally", price = 10000, level = 14, capacity = 2, speed = 3, health = 100, look = "rally_works", adds = "a light pod, a roof scoop, mud flaps and a welded cage: +100 health (no more room)" }, -- 6.7: + health (a stage's tweaks stay under a quarter of the car's)
		},
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
		tank = 90, -- 5.4: litres (Config.Fuel)
		burn = 12, -- litres per 1,000 studs
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
		tank = 100, -- 5.4: litres (Config.Fuel)
		burn = 12, -- litres per 1,000 studs
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
		tank = 80, -- 5.4: litres (Config.Fuel)
		burn = 14, -- litres per 1,000 studs
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
		tank = 60, -- 5.4: litres (Config.Fuel)
		burn = 9, -- litres per 1,000 studs
		ramPower = 1.3,
		color = { 250, 240, 245 },
		description = "Frosty's ice cream truck. 1 passenger.",
		company = true,
		employer = "icecream",
	},
	{
		id = "movingtruck",
		pallets = 1,
		name = "Moving Truck",
		price = 0,
		style = "movingtruck",
		maxSpeed = 58,
		accel = 22,
		turn = 1.5,
		health = 900,
		capacity = 10,
		tank = 90, -- 5.4: litres (Config.Fuel)
		burn = 11, -- litres per 1,000 studs
		ramPower = 1.6,
		color = { 230, 120, 40 },
		description = "Big Move's moving truck: a tall box that takes a pallet. 1 passenger.",
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
		tank = 100, -- 5.4: litres (Config.Fuel)
		burn = 12, -- litres per 1,000 studs
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
		tank = 70, -- 5.4: litres (Config.Fuel)
		burn = 9, -- litres per 1,000 studs
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
		tank = 100, -- 5.4: litres (Config.Fuel)
		burn = 12, -- litres per 1,000 studs
		ramPower = 1.6,
		color = { 220, 60, 50 },
		description = "A flatbed with a barrel rack, from the gas station. 1 passenger.",
		company = true,
		employer = "gas",
	},
	-- 5.1, the bikes (CarDef.bike): sold at Spoke & Chain from level 2, after the cars (Config.Cars[1] stays the van).
	-- server/Vehicles.luau builds them on the styles "bike" (a rear rack: 1 slot) and "cargobike" (a front box: 4) with
	-- Codex's art (server/BikeArt/Geometry.luau, the art id = the car id). No fuel, no passengers, no car gun, no stages;
	-- the bike gear (Config.Gear bikeOnly: basket, panniers, trailer) adds light slots. Sprint on foot is 28 for ~6 s,
	-- so even the Rusty Bike (30, all day) is clearly better.
	{
		id = "rustbike",
		bike = true,
		level = 2,
		name = "Rusty Bike",
		price = 300,
		style = "bike",
		maxSpeed = 30,
		accel = 16,
		turn = 2.4,
		health = 120,
		capacity = 1,
		gearSlots = 1,
		ramPower = 0.3,
		color = { 110, 118, 110 },
		role = "Your first wheels: faster than running, all day",
		description = "Worn tubes, mismatched wheels, a squeaky chain. A rear rack for one light parcel: the bike's own bag. Rider only.",
	},
	{
		id = "citybike",
		bike = true,
		level = 2,
		name = "Courier Bike",
		price = 1100,
		style = "bike",
		maxSpeed = 38,
		accel = 20,
		turn = 2.5,
		health = 150,
		capacity = 1,
		gearSlots = 2,
		ramPower = 0.35,
		color = { 153, 49, 43 },
		role = "The quick one: a clean frame, a lamp, two gear slots",
		description = "A clean red courier frame with a front lamp. A rear rack for one light parcel and room for two pieces of bike gear. Rider only.",
	},
	-- 5.1.1, the E-Scooter (style "scooter": a narrow low deck, two small wheels, a tall stem; server/ScooterArt): a
	-- bike by the rules (light cargo, the BIKE jobs, no fuel, sold at Spoke & Chain) that you ride standing. Quick off
	-- the line and nippy; a small rack over the rear wheel and one gear slot for the basket (a handlebar bag: no
	-- panniers, no trailer, Config.Gear notOn). 5.7 (the owner: "a bit slower, so it isn't too much"): 36 at the top
	-- (44 before; the Courier Bike 38, the E-Bike 48) and two light pieces stacked on its rack (a ZDC RIDE rental keeps
	-- one: Config.Rental.Room). 6.7 (it was dearer than the Cargo Bike and held less): three light pieces (two on the
	-- rack, one on the deck at your feet) for $1,900 at level 3, below the Cargo Bike; the speed stays the owner's 32.
	-- 6.10: its turn eases off with the speed, a firm brake and the wheelie (Config.Scooter); you hop on (Config.Interact).
	{
		id = "escooter",
		bike = true,
		stand = true,
		badge = "⚡ ELECTRIC · STAND-UP",
		level = 3, -- (6.7: 4 → 3, beside the Cargo Bike it undercuts; listed before it, the bikes rise in level and price)
		name = "E-Scooter",
		price = 1900,
		style = "scooter",
		maxSpeed = 32, -- 6.0 (the owner: "not too fast, but a quicker start: electric"): 36 → 32, accel 26 → 42
		accel = 42,
		turn = 2.8,
		health = 110,
		capacity = 3,
		gearSlots = 1,
		ramPower = 0.25,
		color = { 35, 40, 43 },
		role = "The nippy one: stand on it, zip off, no pedalling",
		description = "A battery under the deck, a lamp for the night. Zips off the line and darts through traffic. Three light pieces (two on the rear rack, one at your feet), a basket on the bar; no panniers, no trailer. Rider only, standing.",
	},
	{
		id = "cargobike",
		bike = true,
		level = 3,
		name = "Cargo Bike",
		price = 2400,
		style = "cargobike",
		maxSpeed = 32,
		accel = 14,
		turn = 2.1,
		health = 180,
		capacity = 4,
		gearSlots = 2,
		ramPower = 0.4,
		color = { 153, 49, 43 },
		role = "The hauler: a front box for four light pieces",
		description = "A long low frame with a box up front: four light pieces ride in it. Slower off the line; it takes a basket or panniers, not a trailer. Rider only.",
	},
	{
		id = "ebike",
		bike = true,
		level = 5,
		name = "E-Bike",
		price = 6500,
		style = "bike",
		maxSpeed = 48,
		accel = 24,
		turn = 2.6,
		health = 160,
		capacity = 1,
		gearSlots = 2,
		ramPower = 0.4,
		color = { 153, 49, 43 },
		role = "The fast one: a battery does half the pedalling",
		description = "A battery in the frame, a bar display, disc brakes. The fastest thing on two wheels, no fuel needed. A rear rack and two gear slots. Rider only.",
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
	starter: boolean?, -- 6.7: every profile starts with it (Config.Arms.Starter): not sold, "STARTER · yours" at Lead & Co.
}

Config.Weapons = {
	{
		id = "pistol",
		oneHanded = true,
		name = "Pistol",
		level = 1, -- 6.0: bought at Lead & Co.; 6.0.2: every courier starts with it; 6.7: so it is not sold any more
		price = 0,
		starter = true, -- 6.7
		damage = 20,
		fireRate = 3,
		range = 140,
		pellets = 1,
		spread = 0.5,
		splash = 0,
		color = { 255, 230, 140 },
		description = "Your starter gun: one-handed, so it also fires out of a car window. Better than throwing the pizza at them.",
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
		description = "Sprays a lot of lead, less precise far out. One-handed: it fires out of a car window too.",
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
		description = "Seven pellets: point blank, everything falls apart; past 40 studs they spread thin. Two hands: not from a car.",
	},
	{
		id = "rifle",
		level = 6,
		name = "Hunting Rifle",
		price = 15000,
		damage = 60, -- 6.7: 48 → 60 (132 a second: more than the SMG's 117 even before its spread misses at range)
		fireRate = 2.2,
		range = 240,
		pellets = 1,
		spread = 0.2,
		splash = 0,
		color = { 200, 255, 200 },
		description = "Long range and dead accurate: one shot drops a walker or a runner, a headshot most bandits. Two hands: not from a car.",
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
		description = "Sixteen shots a second: the delivery always arrives. Two hands: not from a car.",
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
		description = "Every shot is a small explosion (a 14-stud blast). Two hands: not from a car.",
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
		name = "Maria's Carbine",
		price = 0,
		damage = 28,
		fireRate = 8,
		range = 220,
		pellets = 1,
		spread = 0.7,
		splash = 0,
		color = { 170, 210, 110 },
		description = "Captain Maria's own rifle, given to the courier who kept the base alive.",
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
-- A car starts without one. The Gun Damage / Fire Rate upgrades work for them too (Economy.carGunStats; 6.7: those are
-- sold at Lead & Co.).
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
	guard: number?, -- 6.7, the Ram Plow: each level takes this share off the dent a ram costs the car (Economy.ramGuard)
}

-- Wrench Garage. 3.3: the car tracks (car = true) belong to ONE car, the equipped one when you buy (the price grows
-- with that car's level; the company vehicles take none); the gun tracks count for all your guns and car guns. The
-- car tracks show on the car (server/Vehicles.luau): Ram Plow a bull bar (bigger with the level), Armor side plates
-- (and window grilles from level 3), Engine a hood scoop and twin exhaust pipes from level 3.
-- 3.4: you keep your first car and upgrade it, so the first levels of the car tracks are cheap (a few deliveries)
-- and the last ones dear. 3.5: the Cargo Rack (+1 slot a level) is gone: the car's STAGES (CarDef.stages) give the
-- room now; a 3.4 save's cars became the stage that holds the slots they had, rack included (Economy.legacyStage).
-- 4.0, the upgrades you see: Engine level 1 stops the Rusty Van's smoking exhaust; Handling is Tyres & Suspension now
-- (the id stays, for the saves): new black tyres with a tread ring from level 1 (bald grey ones before, on the Rusty
-- and the Patched Van), alloy rims from 3, a lower stance at 5. 4.6: the Hand Trolley is not an upgrade track any more
-- but GEAR (Config.Gear below; its id "trolley" and a save's trolley level stay: PlayerData moves it, once).
-- 6.7: the gun tracks (Gun Damage, Fire Rate: no `car`) are sold at Lead & Co. with the guns (server/Shops.luau
-- onUpgrade: a gun track there, a car track and the stages at Wrench Garage); their save keys (profile.upgrades
-- damage / firerate) stay. The Ram Plow's bull bar also takes the dent: `guard` a level (Economy.ramGuard,
-- server/Zombies.luau hitByCar: the car's share of a ram survivor's health × car.stats.ramGuard).
Config.Upgrades = {
	{ id = "engine", car = true, name = "Engine", description = "+8% top speed and acceleration · Lv 1: no more exhaust smoke · Lv 3: a hood scoop and twin pipes", maxLevel = 5, baseCost = 400, costGrowth = 2.0, perLevel = 0.08 },
	{ id = "handling", car = true, name = "Tyres & Suspension", description = "+8% steering · Lv 1: new tyres with tread · Lv 3: alloy rims · Lv 5: a lower stance", maxLevel = 5, baseCost = 300, costGrowth = 1.95, perLevel = 0.08 },
	{ id = "armor", car = true, name = "Armor", description = "+15% car health · side plates, Lv 3: window grilles", maxLevel = 5, baseCost = 350, costGrowth = 2.0, perLevel = 0.15 },
	{ id = "plow", car = true, name = "Ram Plow", description = "+30% ram damage, −12% of the dent a zombie you don't kill leaves · a bull bar on the front", maxLevel = 5, baseCost = 300, costGrowth = 1.95, perLevel = 0.30, guard = 0.12 },
	-- (4.0.1: Quick Hands, "loading", is gone: a save's levels are refunded; 5.7: its hold code too)
	{ id = "damage", name = "Gun Damage", description = "+20% damage for every gun you own, the car guns too (not the melee)", maxLevel = 5, baseCost = 800, costGrowth = 1.85, perLevel = 0.20 },
	{ id = "firerate", name = "Fire Rate", description = "+12% shots a second for every gun you own, the car guns too", maxLevel = 5, baseCost = 800, costGrowth = 1.85, perLevel = 0.12 },
} :: { UpgradeDef }

-- 4.6, GEAR: pieces of equipment bought for ONE car at Wrench Garage (the GEAR tab) and installed in its gear slots
-- (CarDef / StageDef gearSlots, Economy.gearSlots). Buying gives that car the piece (profile.carGear[carId][gearId] =
-- "owned"); installing or removing it there is free, as long as a slot is free ("installed"). Each piece has a driver
-- level and shows on the car (server/Vehicles.luau buildKit). `needs`: the CarDef flag a car must have to take it
-- (the trolley: CarDef.trolley, the vans and trucks); `notOn`: cars it does not fit (no roof rack on an open bed or a
-- low muscle car). The company vehicles have no gear slots: they come with what their jobs need.
--   trolley   the Hand Trolley (4.0's upgrade, the same id and save): folded inside the back, server/Equipment.luau
--   straps    Ratchet Straps: the cargo's condition losses × GearTuning.StrapsLoss (4.7's cargo rules use it)
--   cooler    Cooler Box: food freshness drains × GearTuning.CoolerDrain (4.7)
--   roofrack  Roof Rack: + GearTuning.RoofRackSlots cargo slots for LIGHT pieces (Config.Cargo.LightLooks), on the
--             roof (Economy.capacity with the installed gear and the cargo's look; server/Cargo.luau shows them there,
--             6.7: two side by side, RoofRackGap apart)
export type GearDef = {
	id: string,
	name: string,
	level: number, -- the driver level needed to buy it
	price: number,
	description: string,
	icon: string, -- an emoji (the shop card, the career road)
	needs: string?, -- a CarDef flag the car must have ("trolley")
	notOn: { string }?, -- car ids it does not fit
	bikeOnly: boolean?, -- 5.1: bike gear (basket, panniers, trailer): fits only CarDef.bike, installed at Spoke & Chain
	room: number?, -- 5.1: bike gear's extra light slots
}

-- 5.0: personal gear (yours, not a car's), bought at Last Stop Supplies and kept for good (profile.kit): what you
-- carry on foot and on a bike (shared/Transport.luau). speed = walk / sprint multiplier (the best one counts; 6.12.2:
-- the Running Shoes and their 1.1 are gone, only the Heavy Armour's slow-down is left).
-- 6.7: the Thermal Jacket (warm: food cooled ×0.8) is gone (the Thermal Delivery Bag keeps food hot; Config.RetiredKit
-- pays it back once). `tips` = the share of an order's pay a piece adds as the customer's tip on every delivery (the
-- Courier Vest: shared/JobRules.luau kitTip, server/Jobs.luau payOrder). `starter` = every profile has it (the plastic
-- bag: "STARTER · yours", never sold). `shop` = the Map.Shops id that sells it (shared/Transport.luau kitShop: else a
-- bag at ZDC Bags, the rest at Last Stop Supplies): the Baseball Bat at Lead & Co. `melee` = the Config.Melee kind it
-- turns the punch into (the bat).
-- 6.0: extra = light pieces a bag adds on top of the hands.
-- 6.6, one carrying item (the owner: "you can't have a bag and a backpack at the same time"): the backpacks are gone
-- (Config.RetiredKit, refunded once: server/PlayerData.luau), your room on foot is the hands + the bag in use, and the
-- bags are sold at ZDC Bags, the kiosk at the depot (Config.BagShop); Last Stop Supplies keeps the vests and the rest.
-- 6.12.2: both are the two counters of the gear stall at the spawn (Config.GearStall).
-- 6.0: armour = the share of every hit a vest takes off (the best vest owned counts, shared/Armour.luau); a speed below 1
-- slows the walk and the sprint (shared/Transport.luau speedMult: the best speed-up × the slowest piece).
-- 6.4, the bags (a piece with `extra` is a bag): only ONE bag is in your hand, the active one (profile.activeBag, else
-- the best owned: the most room, a tie the later one here; shared/Transport.luau activeBag / bagRoom), so owning
-- several never adds up. The point of every bag: you SPRINT with your deliveries (pieces in a bag are never "in
-- your hands": no Carrying attribute, no carry step; only the hands' pieces stop the sprint,
-- client/CameraRig.luau). Its perks work only for that bag, while it is your hand (key 2):
--   bagWarm    food in it cools × this (shared/Transport.luau mixWarm: by the share of the order's pieces in it)
--   padded     fragile pieces in it take no knock from a hard fall or a bite on foot (Config.Jobs.CargoRules FootFall …)
--   bagBreath  the sprint drains the breath × this while you hold it (the character's BreathCost attribute,
--              server/Transport.luau applyKit; client/Stamina.luau): a heavy bag, you still sprint, a little shorter
-- Its look in the hand: server/KitArt/Geometry.luau (the same id); its swing: Config.Courier.Bags[id].
-- 6.4, how it is carried (shared/Holding.luau wornAs / bagLeaves, server/KitWear.luau, Config.Courier.BagPlaces):
--   carry      while it is your hand: "hand" (in the left hand; the default), "shoulder" (the handles over the left
--              shoulder, the bag at the hip) or "hip" (cross-body: the strap over the right shoulder, the bag on the
--              left hip)
--   stays      when you take the fists or the gun it stays on you, swung onto your back (a strap; the messenger slid
--              behind the hip), loaded or not: its pieces stay with you, the hands are free. Without it, a hand bag
--              as in 6.1: stowed when empty, set down on the ground when loaded. Pickups go into a bag (and you throw
--              from it) only while it is your hand: press 2 to swing it to the front again.
export type KitDef = { id: string, name: string, level: number, price: number, description: string, icon: string, speed: number?, armour: number?, extra: number?, bagWarm: number?, padded: boolean?, bagBreath: number?, carry: string?, stays: boolean?, tips: number?, starter: boolean?, shop: string?, melee: string? }
Config.Kit = {
	-- 6.7: every profile has it (newProfile, starterKit): not sold, "STARTER · yours" at ZDC Bags
	{ id = "bag", name = "Plastic Bag", level = 1, price = 0, starter = true, icon = "🛍️", extra = 2, description = "Your starter bag. Sprint with your deliveries: 2 light pieces of any kind (a bouquet, a cake too) ride in it while you hold it (2); what you pick up drops straight in." },
	-- 6.0.1: the red reflective vest, no longer part of a new courier's body (server/CharacterArt/Geometry.luau hivis):
	-- just the look (no armour), worn until a Kevlar or heavy vest covers it (shared/KitFit.luau). Saves from before
	-- 6.0.1 get it once on load (server/PlayerData.luau), so nobody who played loses it. 6.7: customers tip a courier
	-- they can see: +5% of every order's pay (tips; it counts under an armoured vest too: kit is always worn).
	{ id = "hivis", name = "Courier Vest", level = 1, price = 20, icon = "🦺", tips = 0.05, description = "The ZDC reflective vest: customers see a courier and tip +5% on every delivery (it still counts under a Kevlar or heavy vest)." },
	-- 6.4, the bigger bags (6.6: sold at ZDC Bags; USE there or in the I window's BAGS tab picks the one you hold)
	{ id = "tote", name = "Canvas Tote", level = 2, price = 120, icon = "👜", extra = 3, carry = "shoulder", stays = true, description = "Sprint with your deliveries: 3 light pieces ride in this canvas tote over your shoulder. Swings onto your back when you draw your gun." },
	{ id = "thermal", name = "Thermal Delivery Bag", level = 3, price = 300, icon = "🔥", extra = 4, carry = "hand", bagWarm = 0.35, description = "Sprint with your deliveries: 4 light pieces ride in it. Insulated: food in it stays hot (cools ×0.35)." },
	{ id = "padded", name = "Padded Messenger Bag", level = 4, price = 650, icon = "💼", extra = 4, carry = "hip", stays = true, padded = true, description = "Sprint with your deliveries. Stays on your back when you draw your gun. Foam-padded: 4 light pieces, fragile ones take no knocks." },
	{ id = "duffel", name = "Big Delivery Duffel", level = 6, price = 1200, icon = "🧳", extra = 6, carry = "hand", stays = true, bagBreath = 1.15, description = "Sprint with your deliveries: 6 light pieces ride in it. Slung on your back when you draw your gun. Heavy: sprinting costs 15% more breath." },
	-- (6.12.2: the Running Shoes are gone, the owner: "remove the shoes, they bore me": Config.RetiredKit pays them back)
	-- 6.0, the vests (server/Armour.luau takes the share off every bite and bullet; their looks: KitArt / KitWear).
	{ id = "kevlar", name = "Kevlar Vest", level = 3, price = 600, icon = "🦺", armour = 0.3, description = "Takes 30% off every bite and bullet. Light enough to run in." },
	{ id = "heavy", name = "Heavy Armour", level = 5, price = 1500, icon = "🛡️", armour = 0.5, speed = 0.92, description = "Plates and shoulder guards: takes 50% off every bite and bullet, but you walk and sprint 8% slower." },
	-- 6.7, the Baseball Bat (Config.Melee.Kinds bat): sold at Lead & Co. (shop), yours for good like any kit
	{ id = "bat", name = "Baseball Bat", level = 1, price = 150, icon = "🏏", shop = "guns", melee = "bat", description = "V swings a bat instead of a punch: 30 damage (a punch does 12), a longer reach. With the gun away (fists or the bag); the gun out still strikes with the gun." },
} :: { KitDef }

-- 6.6: the backpacks that are no longer sold (Config.Kit had them from 5.0 to 6.5). A save that owns one gets its price
-- back once (shared/Transport.luau packRefund, server/PlayerData.luau: the save's noPacks flag) and Marge's text says
-- so (Config.Courier.PackRefund, server/Tutorial.luau). 6.7: the Thermal Jacket too, with a flag of its own (`flag`:
-- the save's mark that it was paid back; noJacket, Config.Courier.JacketRefund), so a 6.6 save is paid for it once.
-- 6.12.2: the Running Shoes the same way (noShoes, Config.Courier.ShoeRefund; level 4's reward is the Thermal Delivery
-- Bag now).
Config.RetiredKit = {
	{ id = "backpack", name = "Courier Backpack", price = 150, flag = "noPacks" },
	{ id = "bigpack", name = "Big Backpack", price = 400, flag = "noPacks" },
	{ id = "jacket", name = "Thermal Jacket", price = 300, flag = "noJacket" }, -- 6.7
	{ id = "shoes", name = "Running Shoes", price = 250, flag = "noShoes" }, -- 6.12.2: their +10% walk and sprint gone too
} :: { { id: string, name: string, price: number, flag: string } }

-- 6.12.2, the gear stall at the spawn (the owner: "next to it [the jobs] make a stall for the bags and the gear ... the
-- shops feel unnecessarily big"; server/GearStall.luau): one open-air market stall under one awning on the west side of
-- the depot's yard, next to the JOBS spot (server/JobsSpot.luau), facing the yard (+X): two counters side by side, BAGS
-- (ZDC Bags, Map.Shops.bags: the bags, as the 6.6 kiosk sold them) to the north and GEAR (Last Stop Supplies,
-- Map.Shops.supplies: the vests and the items; its old building on block (0, -1) is no shop any more) to the south,
-- each with its clerk (server/ShopClerks.luau: Nell, Dot). Clear of the spawn pad (World.DepotSpawn at 0, 26), the
-- scooter rack (Config.Rental.SpawnRack, z 44), the JOBS spot round the job board (-18, -25), the garage terminal
-- (18, -25) and Marge (Config.Tutorial.NpcSpot), all studs from the depot's middle (Map.Depot).
--   X, Z      the stall's middle; Width along its front (Z), Depth (X), Height to the roof
--   Counter   each counter's middle from the stall's middle along the front
--   Radius    studs from a counter's front the shop counts as "here" (the counter's BUY, the server's check): the stall,
--             not the whole yard (Map.ShopRadius for the big shops)
--   Board     the name board on its roof (a second line after the double space)
Config.GearStall = {
	X = -33,
	Z = 8,
	Width = 26,
	Depth = 9,
	Height = 10,
	Counter = 6.5,
	Radius = 14,
	Board = "LAST STOP SUPPLIES · ZDC BAGS  GEAR & BAGS FOR COURIERS",
}

-- 6.6, ZDC Bags (Map.Shops.bags): the bags (Config.Kit pieces with `extra`). 6.12.2: the BAGS counter of the gear stall
-- (Config.GearStall; the 6.6 kiosk east of the spawn is gone). X / Z: the counter's front (the customers' side), studs
-- from the depot's middle; Radius: the stall's. (Last Stop Supplies, the GEAR counter: Map.Shops.supplies.)
Config.BagShop = {
	Name = "ZDC Bags",
	X = Config.GearStall.X + Config.GearStall.Depth / 2,
	Z = Config.GearStall.Z - Config.GearStall.Counter,
	Radius = Config.GearStall.Radius,
}

-- 5.0, Earl's van (shared/VanQuest.luau, server/VanQuest.luau): the first vehicle is not sold at Dead End Motors. When
-- you reach the van's level (Config.Cars "van" level) without one, Marge texts you about a guy out west; Earl sells his
-- old van at Earl's Used Wheels (Map.VanSeller, far out on the West Highway) for the van's price. Its stages are
-- bought at Wrench Garage as usual. Range: studs from Earl the purchase is allowed within (the prompt reaches 10).
Config.VanQuest = {
	Car = "van",
	Seller = "Earl",
	Place = "Earl's Used Wheels",
	Range = 16,
	-- The words (the dealer's card, the board, the missions, the career road, the tutorial, Marge's and Earl's lines).
	Where = "Earl's Used Wheels (Marge's quest at level 4)",
	DealerNote = "Sold privately — Marge knows a guy (level 4).",
	MissionsNeed = "Missions need a vehicle — the Old Van at level 4 (Earl's Used Wheels, Marge's quest).",
	Unlock = "A guy out west is selling his old van. Cheap-ish. Go see Earl — I put him on your GPS.",
	Reminder = "Earl still has that van for you, out west on the West Highway. He's on your GPS.",
	Bought = "Nice. Now you can take ★ car jobs — and don't forget fuel later.",
	Keys = "Here are the keys, kid. She's ugly but she runs.",
	TooYoung = "You're green, kid. Come back when Marge sends you.",
	Sold = "Already sold you one, kid. Treat her right.",
}

-- 5.1, Spoke & Chain Cycles (Map.Shops.bikes, Downtown block (-1, 1), its door on Main St): the bikes (Config.Cars with
-- bike = true) and the bike gear (Config.Gear bikeOnly). A bike needs no garage slot and comes to you at once (MY
-- BIKE); you may own bikes and cars: profile.car is the one CAR / MY BIKE brings, profile.bike your bike of choice,
-- profile.lastCar the car CALL CAR brings back (server/Shops.luau). At Career.BIKE_LEVEL Marge texts you about the
-- shop (server/Tutorial.luau, the Tutorial remote's "message" with the GPS): Unlock ({price}: the cheapest bike's).
Config.BikeShop = {
	Shop = "Spoke & Chain",
	Street = "Main St",
	Unlock = "You've got legs, now get wheels — Spoke & Chain on Main St sells a rusty bike for {price}. I put it on your GPS.",
	Reminder = "Spoke & Chain on Main St still has bikes for you. More room and way faster than walking. It's on your GPS.",
	Bought = "Nice wheels. The BIKE runs on the board are yours now. A basket holds more.",
	MissionsNeed = "Missions need your car (a bike won't do): CALL CAR on your phone.",
}

Config.Gear = {
	{ id = "trolley", name = "Hand Trolley", level = 3, price = 600, icon = "🛒", needs = "trolley", description = "Heavy cargo by hand at a normal pace: up to 4 pieces at once (not people, horses or pallets). Folds inside the back: vans and trucks only." },
	{ id = "straps", name = "Ratchet Straps", level = 4, price = 900, icon = "🔗", description = "The load is strapped down: cargo condition losses from bumps and damage ×0.6. Cars only." },
	{ id = "cooler", name = "Cooler Box", level = 5, price = 1400, icon = "🧊", description = "Food in the car stays fresh twice as long (freshness drains ×0.5). Cars only." },
	{ id = "roofrack", name = "Roof Rack", level = 7, price = 2500, icon = "🧳", notOn = { "muscle", "pickup" }, description = "+2 cargo slots on the roof for light pieces only (pizza, parcels, mail, bread, medicine …). Not on the Muscle Car or the Pickup." }, -- 6.7: +1 → +2
	-- 5.1, bike gear (bikeOnly: only on a bike, CarDef.bike; the car gear never goes on one), sold and fitted at Spoke &
	-- Chain (Map.Shops.bikes) for the bike you ride: `room` more light pieces (Economy.capacity, Transport mode "bike").
	{ id = "basket", name = "Front Basket", level = 2, price = 150, icon = "🧺", bikeOnly = true, room = 2, description = "+2 light pieces in a wire basket over the front wheel. Fits every bike and the E-Scooter." },
	{ id = "panniers", name = "Panniers", level = 3, price = 450, icon = "👜", bikeOnly = true, room = 3, notOn = { "escooter" }, description = "+3 light pieces in two bags on the rear rack. Not on the E-Scooter." },
	{ id = "trailer", name = "Bike Trailer", level = 4, price = 1200, icon = "📦", bikeOnly = true, room = 4, notOn = { "cargobike", "escooter" }, description = "+4 light pieces in a two-wheeled trailer behind you: bike runs take up to 8 pieces. Not on the Cargo Bike or the E-Scooter." },
} :: { GearDef }

-- 4.6: what the gear does (4.7's cargo rules read StrapsLoss and CoolerDrain).
Config.GearTuning = {
	StrapsLoss = 0.6, -- Ratchet Straps: cargo condition losses × this
	CoolerDrain = 0.5, -- Cooler Box: food freshness drains × this
	RoofRackSlots = 2, -- Roof Rack: + this many cargo slots for light pieces (6.7: 1 → 2)
	RoofRackGap = 1.8, -- 6.7: studs between the rack's pieces, side by side (server/Cargo.luau)
}

export type ItemDef = {
	id: string,
	name: string,
	icon: string,
	price: number,
	max: number,
	description: string,
	car: boolean?, -- 6.7: for a car only: shown (the shop, the bottom bar, the crates) once you own a car (Economy.itemShown)
}

-- Consumables, bought at Last Stop Supplies, used from the bottom bar (client/Hotbar.luau: in this order, the first
-- BarSlots kinds you have; 6.7: more than that, the last slot is MORE: the I window). 6.7: the ones for a car (`car`:
-- the repair kit, nitro, the landmine, the jerry can) come after the ones on foot, show in the shop and on the bar only
-- once you own a car (any vehicle that is not a bike: Economy.ownsCar), a supply crate gives them only then, and the
-- server sells them only then (server/Shops.luau). The Energy Drink (Stamina: EnergyTime, EnergyBreath) is new.
Config.Items = {
	{ id = "medkit", name = "Medkit", icon = "➕", price = 80, max = 10, description = "Heals you fully, at once." },
	{ id = "energy", name = "Energy Drink", icon = "🥤", price = 40, max = 5, description = "Your breath full at once, and ×1.3 breath for 30 s: you sprint longer. On foot." }, -- 6.7
	{ id = "molotov", name = "Molotov", icon = "🔥", price = 60, max = 20, description = "Throw it where you aim (90 studs at most): burns zombies for 8 s. From a car too." },
	{ id = "repair", name = "Repair Kit", icon = "🔧", price = 150, max = 10, car = true, description = "Car only: fixes 40% of your car's health. Stand next to it." },
	{ id = "nitro", name = "Nitro", icon = "⚡", price = 120, max = 10, car = true, description = "Car only: 4 seconds of +60% speed while you drive." },
	{ id = "mine", name = "Landmine", icon = "💣", price = 100, max = 10, car = true, description = "Car only: drops behind your car while you drive; a zombie or a bandit car close by sets it off. 5 at most down (a 6th blows the oldest), gone after 2 minutes." },
	-- 5.4: sold at Last Stop Supplies and at every gas station's kiosk (Map.GasStations); Config.Fuel.CanLitres.
	{ id = "jerrycan", name = "Jerry Can", icon = "⛽", price = 35, max = 5, car = true, description = "Car only: +10 L of fuel. Use it next to your car (or in it). The gas stations' kiosks sell it too." },
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
	BarSlots = 5, -- 6.3: the bottom bar's item slots on a computer (client/Hotbar.luau)
	-- 6.7, the Energy Drink (server/Items.luau sets the character's EnergyUntil, server time; client/Stamina.luau fills
	-- the breath when it changes and divides the sprint's drain by EnergyBreath until then)
	EnergyTime = 30,
	EnergyBreath = 1.3,
}

-- 5.4, fuel (shared/FuelMath.luau, server/Fuel.luau, client/FuelGauge.luau). Every car (never a bike or the scooter)
-- has a tank (CarDef.tank, litres) and burns CarDef.burn litres per 1,000 studs it is driven: the server's Tick measures
-- the chassis' flat distance while somebody drives it, never while a chauffeur does, and skips a jump of more than
-- MaxJump studs (a teleport, a tow, a rebuild). A full tank lasts about 3 – 5 jobs of the tier the car opens at
-- (FuelMath.jobsPerTank, tests/fuel_test.luau). Below Low (a share of the tank) the gauge turns red and a toast says LOW
-- FUEL; empty, the car crawls at CrawlSpeed at most (client/Drive.luau) to a pump, or the phone's TOW brings it to the
-- nearest station's pump with TowLitres for TowPrice (only with an empty tank). The gas stations (Map.GasStations) sell
-- fuel at PricePerLitre: the pump's Refuel prompt (hold PumpHold s, on foot, your car parked within PumpReach studs of the
-- pump) pours PourRate litres a second, charged as it pours, until the tank is full, the money runs out or you stop it.
-- The jerry can (Config.Items "jerrycan") pours CanLitres next to your car. Your own cars' levels are saved
-- (profile.carFuel); a new car comes full, a company vehicle a job lends you comes full and is not saved.
Config.Fuel = {
	PricePerLitre = 2,
	CrawlSpeed = 6, -- studs / s: the top speed with an empty tank
	Low = 0.15, -- the share of the tank under which it is low (red gauge, the LOW FUEL toast)
	Tick = 0.5, -- seconds between the server's burns
	MaxJump = 200, -- studs: a move longer than this in one tick is not driving (no burn)
	PourRate = 8, -- litres a second at a pump
	PumpReach = 12, -- studs from the pump to your car's body at most (a Freight Truck parks outside the canopy posts)
	PumpHold = 0.5, -- seconds to hold the Refuel prompt
	PumpWalk = 14, -- studs: walk farther from the pump than this and it stops pouring
	TowPrice = 150,
	TowLitres = 5,
	TowRide = 80, -- studs: on foot this close to your car and you ride along with the tow
	CanLitres = 10,
	CanReach = 12, -- studs from your car's body at most to pour a jerry can
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
	-- 4.6, the career (Config.Levels.Rewards): reaching a level gives these, never sold.
	{ id = "hivis", name = "Hi-Vis Orange", price = 0, color = { 255, 122, 24 }, exclusive = "career" },
	{ id = "legend", name = "Legend Chrome", price = 0, color = { 214, 220, 228 }, material = "Foil", exclusive = "career" },
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
	SpotTime = 0.7, -- 4.0.4: a bandit has to see you this long (a clear line, nothing in between) before it fires
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
	RamGuardMin = 0.25, -- 6.7: the Ram Plow cuts that dent to this share at most (Economy.ramGuard: −12% a level)
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
	-- 5.3, the real places (shared/Deliveries.luau): the pick-up is the business's storefront (Map.venuesOf), the drop
	-- one of `to`: "house" (a Suburbs house of Map.Homes), "apartment" (a downtown entrance), "venue:<business id>"
	-- (that business's storefront: its person takes it), "harbor" (an address in the Harbor: the dock foreman). Nil:
	-- any address as before 5.3 (the far places on the dangerous levels). `hours` = { from, to } on the game clock it
	-- sends anything (nil: round the clock; from > to runs over midnight); `peak` = { from, to, pay }: those hours pay
	-- × pay (the evening rush).
	to: { string }?,
	hours: { number }?,
	peak: { number }?,
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

-- 4.6: what a level gives on top of its unlocks (Config.Levels.Rewards).
export type LevelReward = {
	money: number?,
	items: { [string]: number }?, -- Config.Items id → how many
	paint: string?, -- a Config.Paints id (exclusive "career")
	title: string?, -- a title shown over your head (profile.titles)
	text: string?, -- 5.0: what else the level brings, in words ("The bike shop opens (5.1)")
	kit: string?, -- 5.7: a piece of personal gear (a Config.Kit id), yours for good; owned already: its price instead
}

-- Driver levels (shared/Levels.luau): XP for every delivery, a rank for every level; levels unlock the danger levels
-- on the job board (Jobs.Tiers level), cars, guns and car guns (their level field), some special jobs, the
-- campaigns (shared/Missions.luau) and the real estate.
-- 6.8, the progression: the first clears of the story chapters (the 60 non-DUO missions' job XP × FirstClearXp, no
-- kills) give about 30 800 XP; level 15 needs 34 037 (XpBase 575 × 1.2^n). Played in order with about 10 kills a
-- mission (+40 XP) no mission is ever above your level (a chapter's missions sit at its level, the finale at the next
-- chapter's: shared/Missions.luau levelOf), and Last Convoy's finale opens at 15. Without the kills you come short
-- in the last chapters (a few board jobs). The DUO chapter, the job board and the replays (Config.Missions.ReplayXp:
-- a quarter) come on top. 3.1 saves (the old curve, Legacy) keep their level (PlayerData, Curve).
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
	-- 4.6, the career (shared/Career.luau, client/CareerUi.luau): every level from 2 gives a reward on top of what it
	-- unlocks, once (server/PlayerData.luau: profile.levelRewards; a save from before 4.6 counts the levels it had
	-- reached as given, nothing is paid back). Money from $500 to $15,000, items (Config.Items ids, capped at their
	-- max), and at 5 / 10 / 15 a career paint (Config.Paints exclusive "career") or a title.
	-- 5.7: the levels before a car (2 – 4) give what a courier on foot or on a bike uses (medkits, 6.6: the Canvas Tote,
	-- the Running Shoes: Config.Kit; 6.12.2: the shoes are gone, level 4 gives the Thermal Delivery Bag); the car's items
	-- (repair kits, nitro, mines) start at 5, once you drive.
	Rewards = {
		[2] = { money = 500, items = { medkit = 2 }, text = "The bike shop: Spoke & Chain on Main St" },
		[3] = { money = 750, items = { medkit = 2 }, kit = "tote" }, -- (6.6: the Canvas Tote, no backpack any more)
		[4] = { money = 1000, items = { medkit = 2 }, kit = "thermal", text = "Old Van: Earl's Used Wheels (Marge's quest)" }, -- (6.12.2: the shoes before)
		[5] = { money = 1500, items = { repair = 2 }, paint = "hivis" },
		[6] = { money = 2000, items = { molotov = 4 } },
		[7] = { money = 2500, items = { mine = 2 } },
		[8] = { money = 3500, items = { nitro = 3 } },
		[9] = { money = 4500, items = { repair = 3 } },
		[10] = { money = 6000, title = "Iron Courier" },
		[11] = { money = 7000, items = { medkit = 3 } },
		[12] = { money = 8500, items = { nitro = 3, molotov = 4 } },
		[13] = { money = 10000, items = { mine = 3 } },
		[14] = { money = 12000, items = { repair = 3, medkit = 3 } },
		[15] = { money = 15000, paint = "legend", title = "Legend of the Last Road" },
	} :: { [number]: LevelReward },
}

-- Traffic (server/Traffic.luau): civilian cars driving the roads and people walking the sidewalks, near the players
-- only (they appear out of sight and disappear far away).
-- 3.9, living streets: more people (many of them standing and chatting in small groups, which costs no walking),
-- walkers who stop at a shop window or for a word with somebody, crosswalks (the only places people cross) and
-- traffic lights at the city's four-way junctions (shared/Crossings.luau: one cycle every client computes itself).
Config.Traffic = {
	CarsPerPlayer = 6,
	MaxCars = 24,
	PedestriansPerPlayer = 13, -- around one player by day (3.8: 8); at night NightPeople of it
	MaxPedestrians = 48, -- on the whole server (3.8: 30)
	NightPeople = 0.4,
	SpawnMin = 120,
	SpawnMax = 260,
	Despawn = 340,
	CarSpeed = 34,
	-- 3.10, people on foot: a calm stroll, each their own (studs/s; the legs match: Roblox's walk animation is a pure
	-- walk below about 5.3, a jog at 8), a run from a zombie, and how a stuck walk ends.
	WalkSpeed = { 4.4, 5.4 },
	RunSpeed = 13,
	StuckAfter = 3, -- seconds without getting closer: the walk is given up (back the other way)
	StuckLimit = 3, -- walks given up in a row: the person goes, when nobody looks
	-- Groups: people standing in a loose circle on a sidewalk, talking; after a while they break up and walk off.
	GroupChance = 0.4, -- share of the new people that come as a group (when there is room for two)
	GroupSize = { 2, 4 },
	GroupTime = { 25, 60 }, -- seconds a group stands
	TalkEvery = { 2.5, 5 }, -- seconds between a group's turns to the speaker / gestures
	SayChance = 0.3, -- of those turns, a line in a speech bubble
	-- Walkers stopping.
	WindowChance = 0.012, -- per half second of walking along a block: stop at a shop window
	WindowTime = { 3, 7 },
	MeetChance = 0.35, -- two walkers passing each other stop for a word
	MeetTime = { 4, 8 },
	MeetCooldown = 40,
	-- Crossing the street (only over a crosswalk, next to a junction).
	CrossChance = 0.28, -- at a corner
	CrossTime = 6, -- seconds of walk phase still left to step out (the crossing takes about 5)
	CrossWait = 30, -- seconds waiting at the curb before going on round the block instead
	CrossGap = 40, -- no lights: no traffic car this close coming toward the crosswalk
	-- Traffic lights: green for one axis, amber, all red, then the other axis (one cycle = 2 × the three).
	LightGreen = 12,
	LightAmber = 3,
	LightAllRed = 1,
	StopBack = 7, -- the stop line, this far before the end of a lane (just before the crosswalk)
	AmberBrake = 20, -- studs/s²: on amber a car stops when it can at this, else drives on
}

-- 5.5, the city buses (shared/BusLines.luau, server/Buses.luau, server/BusStops.luau, client/BusRide.luau): free
-- rides on three loops, driven by one timetable from the server's clock (every client works out the same bus).
-- A line is a closed loop of road-centre corners (Map's grid; -Z is north), driven clockwise on the right-hand lane;
-- its stops are worked out along it (every ~2 blocks at the kerb, never on a special block's side or by a door; 6.3:
-- express, every ~4 blocks and at the key places).
export type BusLineDef = {
	id: number,
	name: string, -- "Downtown Ring"
	short: string, -- the caps word on the signs and the HUD ("RING")
	color: { number },
	buses: number, -- how many drive the loop, evenly spaced (the wait is at most its loop time / buses)
	corners: { { number } },
}
Config.Bus = {
	-- 6.3, express lines: fewer stops, farther apart and at the key places, and quicker buses (the bus is for when
	-- it is too far to walk). The corner speed, the approach and the ramp grew with the speed (the curves stay smooth).
	Speed = 55, -- studs/s on a straight (5.5: 40)
	TurnSpeed = 20, -- through a corner (straight over a junction: Speed)
	Approach = 30, -- studs before and after a corner at the speed between the two
	Ramp = 2.0, -- seconds from a stop to full speed (and from full speed into a stop)
	Dwell = 4, -- seconds at every stop, the door open
	StopGap = 560, -- along the loop, a stop at least this far after the one before (about 4 blocks; 5.5: 250)
	PickWindow = 200, -- … and within this much more the lane nearest the key places is taken (shared/BusLines.luau)
	LastGap = 420, -- the last stop round the loop at least this far before the first
	KeyReach = 230, -- a key place (Map.Landmarks, the districts' middles) draws the stops within this of it
	NameReach = 140, -- a stop within this of a key place is named after it ("City Clinic"), else after its street
	StopClear = 18, -- no stop by the kerb within this of a door, a pile, a park, a place or an employer's board
	MaxWait = 25, -- the longest wait at a stop (the tests hold every line to it)
	BodyColor = { 226, 228, 222 }, -- the buses' paint; the line's colour is the stripe and the sign
	Reach = 10, -- the Board prompt's reach at the door
	NearStop = 25, -- the arrivals card shows within this of a stop
	HintDistance = 500, -- a foot or bike job's stop farther than this: the HUD may suggest a bus (6.3: long trips only)
	RouteReach = 420, -- a route walks at most this far (manhattan) to the first stop and from the last
	RouteSaving = 10, -- seconds the bus must save over walking to be suggested
	MapBoardReach = 60, -- 6.3: the map board of the nearest stop within this is drawn (client/BusMapBoard.luau)
	Lines = {
		{
			id = 1,
			name = "Downtown Ring",
			short = "RING",
			color = { 205, 45, 45 },
			buses = 6, -- (6.3: 8; the express loop is quicker, a bus still every ~19 s)
			corners = { { -504, -504 }, { 504, -504 }, { 504, 504 }, { -504, 504 } },
		},
		{
			id = 2,
			name = "Downtown Cross",
			short = "CROSS",
			color = { 235, 180, 30 },
			buses = 5, -- (6.3: 7)
			corners = {
				{ -72, -360 }, { 72, -360 }, { 72, -72 }, { 360, -72 }, { 360, 72 }, { 72, 72 },
				{ 72, 360 }, { -72, 360 }, { -72, 72 }, { -360, 72 }, { -360, -72 }, { -72, -72 },
			},
		},
		{
			id = 3,
			name = "Suburbs Link",
			short = "SUBURBS",
			color = { 50, 120, 220 },
			buses = 4, -- (6.3: 6)
			corners = { { -216, 216 }, { 216, 216 }, { 216, 1116 }, { -216, 1116 } },
		},
	} :: { BusLineDef },
}

-- 5.6, ZDC RIDE: free rental e-scooters at docks on the kerbs of Downtown and the Suburbs (shared/RentalDocks.luau
-- places them, server/Rental.luau runs them). A rental is the E-Scooter (CarId) by every riding rule, never yours: not
-- saved, not in your cars, no paint, no gear, no fuel, no garage, no car jobs, never on a mission.
Config.Rental = {
	CarId = "escooter", -- the Config.Cars bike a rental is
	Price = 0, -- free (the money check stays for later)
	Docks = 20, -- about this many docks on the kerbs (one of them just outside the safe zone by the park; 6.3: and the
	-- spawn's rack, SpawnRack, on top)
	DowntownDocks = 14, -- of those, at most this many Downtown (the rest in the Suburbs)
	Spacing = 210, -- no two docks closer than this (studs)
	Slots = { 2, 3 }, -- scooters in a dock (the dock's dice pick one)
	SlotPitch = 5.6, -- studs between two docked scooters along the kerb (nose to tail)
	Start = 8, -- the dock starts this far from its block's corner (past the crosswalk)
	Depth = 1.6, -- the scooters stand this far in from the curb (the walkers' line, 4.5 in, stays clear)
	Clear = 10, -- no dock within this of a door, a pile, a cargo spot, an employer's board or an address
	ParkClear = 8, -- … nor of a home's or a storefront's park on the road
	StopClear = 24, -- … nor of a bus stop's kerb
	GasClear = 50, -- … nor of a gas station's middle
	PlaceClear = 30, -- … nor of a place (Map.Places)
	Reach = 10, -- the dock's Rent (6.10: only while it is empty) / Return prompts' reach (a scooter's Ride: ScooterReach)
	Hold = 0, -- the Ride prompt's hold (s; 6.10: 0.4 → 0, E and you hop on)
	WalkAway = 30, -- off the scooter and farther than this from it: it goes back ("returned")
	Idle = 45, -- off the scooter this long: it goes back
	Restock = 20, -- seconds until a rented scooter stands in its dock again (once it is returned)
	Color = { 214, 72, 64 }, -- the ZDC RIDE red on the rentals' deck and stem
	-- 5.7, the balance: a free rental is the slow way round (the Rusty Bike does 30, the bought E-Scooter 32) and its
	-- rack takes one light piece (the bought one two). server/Vehicles.luau caps the rental's MaxSpeed and its room.
	MaxSpeed = 26,
	Accel = 36, -- 6.0: quick off the line like the bought one (42), the cap above keeps it slow at the top
	Room = 1,
	-- 6.3, the rack at the spawn: a row of scooters side by side in the depot's yard, behind the spawn pad (the walk
	-- to Marge and the job board in front of it stays free), their noses toward the yard's open south edge and the
	-- street. It is the first dock (shared/RentalDocks.luau), the only one in the safe zone; renting and returning work
	-- as at any dock. x, z: the row's middle, studs from the depot's middle (6.11: Map.Depot); along X.
	SpawnRack = { x = 0, z = 44, slots = 6, pitch = 3.4, name = "Depot Yard" },
}

-- 5.6, zip lines between Downtown's rooftops (shared/ZipLines.luau picks them, server/ZipLines.luau builds them and
-- checks the rides, client/ZipRide.luau rides them): up the start tower's ladder, Zip on its platform, a fast ride over
-- the road to a lower roof across it, down its ladder. 6.10 (the owner: "like a building you climb up by yourself, and
-- onto the zip line you just jump"): the ladders are real trusses the body climbs itself (no Climb prompts any more),
-- the platform's back rail has a gap to walk in through, and a jump on the start platform grabs the trolley.
Config.ZipLines = {
	Count = 8, -- cables (6 – 10)
	MinLength = 120, -- studs along the ground between the two platforms
	MaxLength = 260,
	MinDrop = 10, -- the start's roof at least this much higher than the end's
	MaxSlope = 0.35, -- drop / length at most
	Spread = 180, -- no two cables' middles closer than this
	Speed = 55, -- studs / s along the cable
	Ramp = 0.8, -- seconds from standing to full speed
	Brake = 12, -- the last studs slow down …
	EndSpeed = 18, -- … to this
	Sag = 0.035, -- the cable's sag in the middle, per stud of length
	CableHeight = 7, -- the cable's ends over the platforms' floors
	-- the rider's root under the cable (hands up on the trolley's handle). 6.8 review: 3.6 → 3.1, the body about where
	-- 6.7 hung it (the root moved 0.6 up in it: shared/ZipLines.luau Feet 3.8): the feet 0.1 over the end platform.
	-- 6.9: Roblox's classic R15 (its feet 3 under the root): 3.9, the feet still 0.1 over it (CableHeight 7)
	Hang = 3.9,
	-- 6.8 review: the trolley's handle hangs HandleDrop under the cable; client/ZipRide.luau reaches the hands to it
	-- (HandSpread apart, the elbows bent: a two-bone reach on the body's own arms) instead of a fixed pose that put them
	-- 0.9 studs up through the trolley; arms too short to reach it bring it down to the hands. 6.9: 1.55, the classic
	-- R15's shorter arms (the handle's strap longer, the elbows a little bent; 6.7's body hung 0.35 under the cable)
	HandleDrop = 1.55,
	HandSpread = 2.0,
	Clearance = 3, -- the cable over every roof it crosses (the tests' rule), at least
	Margin = 9, -- the lines are picked with this much over every roof they cross (the rider's feet clear it)
	OverStreet = 24, -- the cable over a street, a sidewalk or a lawn (lamps, trees), at least
	Platform = 7, -- the landing platform's floor (square)
	RailGap = 3, -- 6.10: the gap in the middle of a platform's back rail (walk in from the roof; the floor 0.5 up)
	-- the server's check of where a ride starts: this far from the start platform's middle along the ground (6.10: the
	-- feet from a little under its floor up to GrabRise over it)
	Reach = 10,
	PromptReach = 6, -- 6.10: the Zip prompt's, from the start platform's middle: anywhere on it, not from the ladder
	GrabRise = 8, -- 6.10: a jump there grabs the trolley: the feet up to this over the floor (a whole jump)
	LadderOver = 0.2, -- 6.10: a ladder's truss ends this far over its roof (its foot sunk into the sidewalk to fit)
	Cooldown = 3, -- seconds between the end of a ride and the next ride of one player
	SafeDrop = 6, -- Space lets go only this low over a platform's roof (else it is ignored)
	Grace = 0.8, -- seconds after a ride's end before the server puts a late rider down at the end
}

-- 5.7, the interactions at the car's level (shared/InteractPose.luau has the curves; client/Interact.luau lays the
-- poses on the joints): getting on a bike or a scooter (client/CarBoarding.luau; the server seats you at the move's
-- end: server/Vehicles.luau), the bus's folding door and the walk to a seat (client/BusRide.luau, server/Buses.luau),
-- the zip lines' ladders climbed for real (client/ZipRide.luau, server/ZipLines.luau) and a ZDC RIDE scooter unclipped
-- from its dock (client/RentalUi.luau, server/Rental.luau). 6.10: the zip lines' ladders are real trusses the body
-- climbs itself; the Climb numbers are only shared/InteractPose.luau's climbRoute's now (not played).
Config.Interact = {
	BikeMount = 0.6, -- seconds from the E to the saddle: a step to the bike's side, then the leg over (the server seats you)
	BikeStep = 0.3, -- of BikeMount: the step to the side
	BikeDismount = 0.55, -- seconds: the leg back over and a step off to the side
	-- 6.10 (the owner: "don't teleport me onto the scooter, I want to grab it and jump on it quickly"): onto an E-Scooter
	-- (yours or a ZDC RIDE rental) a quick hop from where you stand, no walk to its side (shared/ScooterRide.luau hop,
	-- InteractPose.scooterHop); its prompt reaches only right beside it. The bikes keep the step and the leg over.
	ScooterHop = 0.3, -- seconds from the E to the deck (the server seats you then)
	ScooterHopOff = 0.25, -- seconds: off the deck, a hop down to its left side
	ScooterArc = 0.7, -- studs: the hop's arc over the straight line
	ScooterReach = 4, -- the scooter's Drive / Ride prompt reach (yours, and every docked rental's own)
	ScooterPromptOut = 0.6, -- that prompt sits this far left of the deck's middle (a bike's 1.9 out, at its side)
	ScooterOff = 2.4, -- off the deck you land this far left of its middle
	ScooterCallSide = 2.6, -- MY BIKE (and PLAY, a respawn) puts the scooter this far to your side, then you hop on
	ScooterHopReach = 8, -- a scooter put out this close to you is hopped onto; farther, you are seated at once
	DockUnclip = 0.25, -- seconds: a rented scooter slides off the dock's charging rail (6.10: 0.45; you hop on meanwhile)
	DockSlide = 1.0, -- studs it slides out (toward the street)
	BusBoard = 1.7, -- seconds from the Board prompt to the seat: to the door, up the step, along the aisle, sit (the server seats you)
	BusAlight = 1.3, -- seconds from the seat out of the door onto the kerb
	BusDoor = 0.45, -- seconds: the folding door opens (or shuts)
	BusDoorShut = 0.8, -- the door shuts this long before the bus leaves (no Board after that)
	BusAlightGrace = 0.5, -- seconds after BusAlight: somebody not on the kerb by then is put there by the server
	ClimbSpeed = 8, -- studs / s up (or down) a zip line's ladder
	ClimbWalk = 14, -- studs / s across the roof between the ladder and the platform
	ClimbOnto = 0.5, -- seconds from the street onto the ladder (or off it at the foot)
	ClimbOver = 0.8, -- seconds over the roof's edge
	ClimbHop = 0.45, -- seconds over a platform's rail
	RungStep = 1, -- studs climbed per hand-over-hand stroke
	StepLength = 2.2, -- studs per step of a walk played by a move
	ZipReach = 0.4, -- seconds: the hands go up to the trolley as a ride starts
}

-- 6.10, the E-Scooter's ride (the owner: "give the scooter better controls, and maybe pop it onto its back wheel"):
-- its handling (client/Drive.luau through shared/ScooterRide.luau, pure: tests/scooter_test.luau) and the wheelie (hold
-- Shift, a gamepad's R1 or the touch WHEELIE button: the deck pitches back round its rear axle, client/CarVisuals.luau;
-- the rider sits back, client/BikeRider.luau; server/Wheelie.luau checks it and tells everybody through the scooter's
-- attribute WheelieAt). A ZDC RIDE rental rides the same (its own top speed and pull: Config.Rental). The bikes and the
-- cars keep their handling.
Config.Scooter = {
	-- The steering: CarDef.turn (rad/s) times a share that eases from LowTurn at walking pace down to HighTurn at the
	-- scooter's top speed (MaxSpeed): quick and precise in the city's corners, calm at full speed (6.0: 2.8 at any speed)
	LowTurn = 1.15,
	HighTurn = 0.45,
	EaseFrom = 6, -- studs/s: the turn starts easing off from here
	GripSpeed = 2.5, -- studs/s: from a stand the steering fades in up to this speed (it does not spin on the spot)
	SteerIn = 7, -- the steering goes to the key's full lock at this rate (1/s: about 0.14 s, no snap) …
	SteerOut = 12, -- … and back to the middle at this one (about 0.08 s)
	Brake = 80, -- studs/s²: S while rolling forward (32 → 0 in 0.4 s)
	Coast = 14, -- studs/s²: no key, it rolls on (32 → 0 in about 2.3 s)
	Reverse = 0.2, -- of the top speed: S from a stand walks it back
	LeanMax = 0.2, -- radians (about 11°) the scooter leans into a turn at most (the look only; a bike: 0.16)
	LeanRate = 0.0075, -- per (rad/s of turning × stud/s of speed)
	Wheelie = {
		Angle = 24, -- degrees the deck pitches back round the rear axle when it is up
		Pop = 0.18, -- seconds to come up …
		Drop = 0.22, -- … and to come down
		MinSpeed = 5, -- studs/s: it pops from this speed (hold the key and it pops as you get there)
		DropSpeed = 3, -- under this it comes down
		MaxSeconds = 3.5, -- the balance holds this long, then it drops by itself (let go and press again)
		Cooldown = 0.8, -- seconds after a drop before the next one
		Turn = 0.4, -- the steering's share while up (the front wheel is in the air)
		SpeedBonus = 0.08, -- the top speed +8% while up
		Wobble = 2.5, -- degrees: the balance's wobble at the end (a third of it at the start)
		WobbleHz = 1.6,
		ServerSlack = 0.6, -- seconds past MaxSeconds before the server takes it down itself (the trip of the remote)
	},
}

-- 5.6, the alley shortcuts (shared/Shortcuts.luau, built by server/Shortcuts.luau from World's build list): a lit
-- path straight through a Downtown block where two neighbouring lots are open (a lawn or a parking lot), a low fence
-- to hop at each end and a SHORTCUT sign.
Config.Shortcuts = {
	Count = 8, -- alleys (6 – 10)
	Width = 5, -- the path
	FenceHeight = 2.2, -- low enough to jump
	Clear = 10, -- no alley's mouth within this of a door, a pile, a park, a cargo spot or a bus stop
}

-- Crews (server/Crew.luau): invite another player into your job (they ride along or follow, share the pay).
Config.Crew = {
	MaxMembers = 3,
	InviteRange = 60, -- studs to the player you invite (or use the crew button from anywhere)
	InviteTimeout = 30,
	RiderRange = 250, -- a rider who got out stays on the owner's job (paid, credited) within this of the owner
}

-- 4.5: the admin's test buddies (server/Buddy.luau, shared/BuddyBrain.luau): NPC couriers that follow their owner on
-- foot, ride in the owner's passenger seats, and shoot the zombies, bandits and bandit cars around them. Their kills
-- pay nobody (the economy stays clean). Modes: follow, stay (stand and fight), guard (hold a spot, step out a little
-- toward an enemy, walk back).
Config.Buddy = {
	Max = 3, -- buddies per owner
	Health = 150,
	RespawnSeconds = 10, -- a fallen buddy comes back near its owner after this
	Tick = 0.2, -- seconds between the buddies' decisions (one loop for all of them)
	FollowDistance = 7, -- studs behind the owner (each buddy at its own place round them)
	Arrive = 2, -- a walking buddy stops this close to its place
	Restart = 5, -- a standing buddy sets off once its place is this far
	Speed = 14, -- walk (the players' walk)
	RunSpeed = 24, -- run (a player's sprint is 28)
	RunFrom = 18, -- studs from the owner (or its spot) from which it runs
	TeleportDistance = 150, -- farther than this from the owner (its spot): it appears next to them
	StuckPath = 1.5, -- seconds without moving while it should: it looks for a way round (PathfindingService)
	StuckSeconds = 4, -- seconds without moving: it appears at its place
	BoardReach = 40, -- studs from the owner's car (standing still) from which it gets into a free passenger seat
	Range = 90, -- studs it shoots (with a clear line)
	Damage = 10, -- per hit
	FireEvery = 0.7, -- seconds between shots
	Accuracy = 0.8, -- hit chance at a standing target (less at a fast one)
	GuardLeash = 30, -- guard: how far from its spot it steps out toward an enemy
	GuardCloseIn = 25, -- guard: it steps toward an enemy farther than this (to get it in sight)
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
	ArriveWithin = 15, -- seconds: about how long a trip should take (how far away the car may start)
	StuckFor = 10, -- 3.9.1: seconds without getting closer (a red light counts as getting on) before it is rescued
	MaxTime = 75, -- and the longest a whole trip may take
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

-- 5.7, sound and juice: the world's sounds (client/Sounds.luau; art/audio/sfx2.ogg, shared/SoundSheet.luau Sfx2), the
-- HUD money counting up and the confetti of a top rating (client/Juice.luau), and the short arm gestures of people and
-- couriers (shared/Gestures.luau, client/ArmPose.luau; set by server/Npcs.luau Npcs.act). Volumes 0..1.
Config.Juice = {
	StepStride = 5.4, -- studs walked per footstep (on foot, on the ground)
	StepMinSpeed = 3, -- slower than this (studs / s): no steps
	StepVolume = 0.32,
	BikeVolume = 0.32, -- the freewheel's ticking (pedal bikes), silent standing still
	ScooterVolume = 0.28, -- the electric hum (the E-Scooter, the rental scooters, the E-Bike)
	ZipVolume = 0.5, -- the trolley's whirr on a zip line (its pitch rises to Config.ZipLines.Speed)
	BusVolume = 0.7, -- the brake and the doors' hiss at a stop
	BusRange = 110, -- studs: buses farther from the camera are not heard
	KnockVolume = 0.85,
	DoorVolume = 0.6,
	DoorDelay = 0.45, -- seconds from the knock to the door's creak
	CoinVolume = 0.55, -- a paid job (and, quieter, the money popped by a kill)
	BuzzVolume = 0.5, -- the phone's buzz under a banner
	AmbienceDay = 0.12, -- the city's hum, by day / by night
	AmbienceNight = 0.2,
	WindDay = 0.04,
	WindNight = 0.13,
	AmbienceFade = 4, -- seconds to go from the day's to the night's level
	CountUpSeconds = 0.7, -- the HUD money runs up to the new amount in this long
	ConfettiPieces = 40, -- a ★★★ rating
	ConfettiSeconds = 1.8,
	-- Seconds each gesture lasts (Gestures.weight eases it in and out).
	-- 6.7: give 0.5 (the piece held out in the hands), bag 0.5 (looked down at, put in), throw 0.45 (the wind-up to
	-- Config.Throw.WindUp, the whip, the follow-through), receive 1.3 (a receiver holding the piece handed over).
	Gestures = { wave = 1.6, give = 0.5, take = 0.45, knock = 0.6, bag = 0.5, throw = 0.45, vest = 1.2, sling = 0.55, unsling = 0.55, receive = 1.3 } :: { [string]: number }, -- 6.0: bag, throw, vest; 6.4: sling, unsling; 6.7: receive
	WaveHz = 2.2, -- the hand's wave, back and forth per second
	KnockGap = 0.17, -- seconds between two knocks (the sound's too)
}

-- 6.12, the world sounds alive (the owner: "more sounds so the game feels alive"): art/audio/sfx3.ogg
-- (shared/SoundSheet.luau Sfx3), what plays where picked by shared/SoundPlan.luau, played by client/SoundScape.luau and
-- client/Sounds.luau. Volumes 0..1, under the SOUND setting's effects volume (Config.Audio.EffectsVolume).
Config.Soundscape = {
	-- Footsteps by surface: the material under the feet (a ray down, Terrain too) → a surface; every material not here
	-- is "concrete" (asphalt, pavement, brick, slate …). The park's lawns are decoration over its concrete slab: they
	-- are found from Map.Park's layout (SoundPlan.parkLawn). In the water (the pond, the river, the sea): "water".
	Materials = {
		Grass = "grass", LeafyGrass = "grass", Ground = "grass", Mud = "grass", Sand = "grass", Snow = "grass",
		Wood = "wood", WoodPlanks = "wood", Cardboard = "wood",
		Metal = "metal", CorrodedMetal = "metal", DiamondPlate = "metal", Foil = "metal",
		Water = "water",
	} :: { [string]: string },
	StepVolume = { concrete = 1, grass = 0.9, wood = 1.05, metal = 0.85, water = 1 } :: { [string]: number }, -- × Config.Juice.StepVolume
	ClimbStride = 2.2, -- studs climbed per step on a ladder (a metal rung)
	WadeStride = 1.3, -- × Config.Juice.StepStride in the water (slower strides, strokes when swimming)
	Others = 6, -- other players' characters stepping (the nearest to the camera) …
	OthersRange = 60, -- … within this many studs
	OthersVolume = 0.75, -- × their steps' volume (3D, at their feet)
	OthersEvery = 0.5, -- seconds between the looks for who is near
	SplashVolume = 0.85, -- a body going into the water (louder falling fast)
	SplashGap = 1.2, -- seconds before the same body splashes again
	SplashRange = 140, -- studs from the camera
	-- Doors (client/CarVisuals.luau's swings, every car near you).
	DoorVolume = 0.7, -- a cabin door opening / shut
	BackVolume = 0.8, -- the back: the rear doors, a roll-up door, a tailgate, a trunk lid, a ramp
	DoorRange = 90, -- studs from the camera
	-- The horn: H in the driver's seat (server/Horn.luau sends it to everybody near; others hear the car's own horn).
	HornVolume = 0.65,
	HornRange = 260, -- studs: farther clients are not even sent it
	HornGap = 0.6, -- seconds between two honks of one player (the server's check too)
	HornPerSecond = 3, -- the Horn remote's rate limit (Net.limit)
	-- CarId → its horn (else horn_car; a pedal bike rings bike_bell, a stand-up scooter beeps scooter_beep).
	Horns = {
		van = "horn_van", courier = "horn_van", highroof = "horn_van", armorvan = "horn_van", rallyvan = "horn_van",
		icecream = "horn_van", ambulance = "horn_van",
		pickup = "horn_car", muscle = "horn_car",
		boxtruck = "horn_truck", freight = "horn_truck", armored = "horn_truck", bus = "horn_truck", monster = "horn_truck",
		movingtruck = "horn_truck", livestock = "horn_truck", fueltruck = "horn_truck",
	} :: { [string]: string },
	-- The ambience (2D loops, in the game only): the day's (traffic far off, birds) and the night's (wind, crickets,
	-- groans far away) blend with the clock (Map.nightFactor of the workspace's ClockHour); a rooftop's wind rises from
	-- RoofFrom to RoofFull studs up and turns the street's ambience down by RoofDuck. Without sfx3.ogg the 5.7 hum and
	-- wind play as before (Config.Juice), the wind up to RoofStandIn louder on a roof.
	Day = 0.13,
	Night = 0.2,
	Roof = 0.3,
	RoofFrom = 22,
	RoofFull = 60,
	RoofDuck = 0.45,
	RoofStandIn = 0.12,
	Blend = 0.12, -- the share of the way to the goal volume every Tick
	Tick = 0.25, -- seconds between the looks at the ambience, the cars in the water and who is near
	-- The park's fountain (Map.Park): a 3D loop at the fountain, heard within FountainRange studs.
	Fountain = 0.55,
	FountainRange = 75,
	FountainHeight = 4, -- studs over the walk (the basin and the jet)
	-- The UI stings (client/Sounds.luau play: "task_done", "purchase", "event_start", "event_end").
	PurchaseVolume = 0.75, -- money that went down outside a job (a purchase; up: the old cash sound)
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
	FirstClearXp = 2.5, -- the XP of the first clear × this (6.8: 1.5 before; six missions a chapter carry the same road)
	-- 6.8, replays (shared/Missions.luau replayPay / replayXp, server/Jobs.luau): a mission you have done before pays
	-- this share of the job's pay and of its XP, and nothing else (the first clear's reward, the chapter's reward and
	-- the unlocks come once). A crew member's share follows their own record.
	ReplayPay = 0.25,
	ReplayXp = 0.25,
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
		-- 6.8: what START says without a partner (server/Missions.luau, the MISSIONS window)
		NeedsPartner = "NEEDS A PARTNER: invite a friend to your crew (K) and bring them here. Rosa & Rico's chapter is a side story: the main story never waits for it.",
	},
}

Config.Jobs = {
	DeliverRadius = 18,
	RefreshSeconds = 120, -- 3.7: the board gets new offers on its own this often (no refresh button); 4.0.2: 2 min
	-- 3.7: the tutorial's first delivery (Jobs.startTutorialJob): an easy one close to the depot (5.0: on foot, Foot).
	TutorialPieces = 2, -- pieces at most (5.0: two letters, what your hands hold)
	TutorialPickupMax = 400, -- studs (manhattan) from the player to the pick-up at most (the nearest homes to the depot: ~330)
	TutorialDropMax = 450, -- studs from the pick-up to the drop at most (an easy car delivery: Jobs ordinaryOffer easy; 5.0: the tutorial walks, Foot.TutorialDrop)
	TutorialTries = 6, -- deliveries made for it; the shortest one is given
	-- 5.0, the ON FOOT jobs (server/Jobs.luau footOffer, server/Cargo.luau's foot flow, shared/Transport.luau): the
	-- board's own section of Offers, always open (level 1) and for everybody (a driver too: quick money). A business
	-- that sends a light look (Config.Cargo.LightLooks) sends Pieces pieces, never more than you carry (Transport
	-- room: your hands and your bag), from an address PickupMin … PickupMax (manhattan) from you to one
	-- MinDistance … MaxDistance on, inside the Districts only (never across the river). Internally a ★ job (tier 1:
	-- the tier-indexed tables stay as they are) with `mode = "foot"`: its own pay (JobRules.footPay: BasePay +
	-- PayPerStud × the walk + PayPerPiece a piece, PayMin … PayMax, × the role's and the modifier's multiplier up to
	-- PayMax × PayTop; the fast bonus is the tip), its own clock (JobRules.footTime: TimeBase + the walk / Speed +
	-- the handling), a ★ job's XP (Levels.jobXp: 70 – 90, about 8 jobs to level 2), the 4.7 rating and streak. No
	-- waves, no bandits, no road events: while you walk out of the safe zone, every StrayEvery s (± 20 %) with
	-- StrayChance one walker comes from StrayDistance studs away (StrayMax of yours alive at most).
	-- The tutorial's first delivery (Jobs.startTutorialJob) is on foot: Config.Jobs.TutorialPieces letters on one
	-- street (the drop at most TutorialDrop studs from the pick-up), its own cargo (TutorialCargo).
	Foot = {
		Offers = 3,
		Pieces = { 1, 3 } :: { number },
		PickupMin = 40,
		PickupMax = 250,
		PickupWiden = 250, -- none within PickupMax (the depot's safe zone has no addresses): up to this much farther
		MinDistance = 80,
		MaxDistance = 350,
		Districts = { Downtown = true, Suburbs = true } :: { [string]: boolean },
		BasePay = 50,
		PayPerStud = 0.08,
		PayPerPiece = 6,
		PayMin = 60,
		PayMax = 110,
		PayTop = 1.25, -- a LONG HAUL or a RISKY (RUSH) foot job pays more, at most PayMax × this
		TimeBase = 40,
		Speed = 9, -- studs / s the clock expects (a walk is 14, a sprint 28: generous)
		StrayEvery = 40,
		StrayChance = 0.5,
		StrayMax = 1,
		StrayDistance = { 60, 110 } :: { number },
		-- A car job (the board's ★ … ★★★★, a special in your own car) while you have no vehicle: locked with these words.
		NeedsVehicle = "Needs a vehicle (Old Van at level 4): until then you deliver on foot.",
		NeedsVehicleButton = "🚐 NEEDS A VEHICLE",
		TutorialDrop = 220,
		TutorialCargo = { cargo = "Letters", kind = "crate", look = "mail", piece = "letter bundle", plural = "letter bundles" },
	},
	-- 5.1, the BIKE jobs (server/Jobs.luau lightOffer with this table, offer.mode = "bike"; the same fields as Foot,
	-- JobRules.footPay / footTime / footPieces take it): the board's BIKE section from Level on, light looks only,
	-- longer (MinDistance … MaxDistance) and bigger (Pieces, never more than your bike holds: its room + its bike gear +
	-- your bag, Transport mode "bike") than a walk, Downtown, in the Suburbs and in the Harbor. Pay: BasePay +
	-- PayPerStud × the ride + PayPerPiece a piece (PayMin … PayMax); the clock expects Speed studs / s; XP: a ★ job's
	-- + XpBonus (about 100 – 130). Done on your bike only (riding it or standing by it; never in a car), Cargo's light
	-- flow (6.6: the pieces ride in the bike's own bag and yours: Info.rack, the bag). No waves: now and then a stray walker.
	-- 6.7: up to 8 pieces a run (6 before): a bike's own room with its gear and your bag passed 6 long ago, so the Bike
	-- Trailer's +4 (and the panniers') only paid off by stacking orders; now a bigger rig takes a bigger run.
	Bike = {
		Level = 2,
		Offers = 3,
		Pieces = { 2, 8 } :: { number },
		PickupMin = 60,
		PickupMax = 450,
		PickupWiden = 350,
		MinDistance = 300,
		MaxDistance = 1000,
		Districts = { Downtown = true, Suburbs = true, Harbor = true } :: { [string]: boolean },
		BasePay = 45,
		PayPerStud = 0.15,
		PayPerPiece = 5,
		PayMin = 90,
		PayMax = 240,
		PayTop = 1.25,
		TimeBase = 45,
		Speed = 18, -- studs / s the clock expects (the Rusty Bike tops out at 30: generous, with stops)
		XpBonus = 20,
		StrayEvery = 30,
		StrayChance = 0.55,
		StrayMax = 2,
		StrayDistance = { 70, 130 } :: { number },
		-- The board's words: no bike yet; in your car (a bike job is ridden); on your bike (a car job needs your car).
		NeedsBike = "Needs a bike: Spoke & Chain on Main St sells them from level 2 (the Rusty Bike is the cheapest).",
		NeedsBikeButton = "🚲 NEEDS A BIKE",
		RideBike = "Bike jobs are ridden: MY BIKE on your phone brings your bike (your car stays where it is).",
		RideBikeButton = "🚲 RIDE YOUR BIKE",
		NeedsCar = "You're on your bike: car jobs need your car. CALL CAR on your phone.",
		NeedsCarButton = "🚐 CALL YOUR CAR",
	},
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
			level = 4,
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
			level = 5,
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
			level = 6,
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
			level = 9,
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
	-- level n is a bulk order with BulkChance[n], its pieces + BulkExtra[n] (min, max).
	-- 3.5 (the stages): ★ never, and at most EasyMaxPieces (the Rusty Van's 2 slots); ★★ (3 at most: the Work Van)
	-- rarely 4 (the Long Cargo Van); ★★★ up to 5 (a Tall Hauler or a Box Truck); ★★★★ up to 8 (a Freight Hauler).
	-- 4.0: pallets are the Freight Run's (Config.JobTypes "freightrun"), never an ordinary delivery's.
	EasyMaxPieces = 2,
	BulkChance = { 0, 0.2, 0.45, 0.6 } :: { number },
	BulkExtra = { { 0, 0 }, { 1, 1 }, { 1, 2 }, { 3, 6 } } :: { { number } },
	-- 4.7, a choice on the board (server/Jobs.luau makeBoard, shared/JobRules.luau): every danger level you may take
	-- offers Offers ordinary deliveries, each with its own trade-off (a role, JobRules.roles: the short one always,
	-- then two of the other three):
	--   short  SHORT & SAFE  the drop in the first Short share of the tier's distance range, the fewest pieces, never a
	--                        modifier, never bulk
	--   long   LONG HAUL     the drop in the last part (Long), the pay × LongPay
	--   risky  RISKY         a modifier always (RiskyModifiers[tier]), the bandits want it (× RiskyBoost) where the
	--                        tier has bandits on the road, the pay × RiskyPay on top of the modifier's
	--   bulk   BULK ORDER    the business's most pieces + the tier's BulkExtra always (a bigger car)
	-- A tier's distance range is its minDistance … min(maxDistance, minDistance + MaxSpan). REROLL: the ordinary offers
	-- of one tier made again for RerollFee × the tier's stars, once per tier until the board's next refresh.
	Choice = {
		Offers = 3,
		Short = { 0, 0.35 } :: { number },
		Long = { 0.6, 1 } :: { number },
		MaxSpan = 1500,
		LongPay = 1.15,
		RiskyPay = 1.1,
		RiskyBoost = 2,
		RiskyModifiers = { { "rush" }, { "horde", "fragile", "rush" }, { "horde", "fragile", "rush" }, { "horde", "fragile", "rush", "heavy" } } :: { { string } },
		RerollFee = 50,
	},
	-- 4.7, the rating of every ordinary and special job (not a mission: it has its own, Missions.rate), JobRules.rate:
	-- a miss for each of: finished with less than OnTime of the clock left, the cargo below GoodCondition (two below
	-- PoorCondition), a wreck on the way, a piece lost. 0 misses ★★★, 1 ★★, 2 or more ★. The pay × Pay[stars], the
	-- XP × Xp[stars]. A streak of good jobs (★★ or better, profile.streak) adds StreakStep of the pay a job, at most
	-- StreakMax; a ★ job or a failed one ends it.
	Rating = {
		OnTime = 0.25,
		GoodCondition = 0.85,
		PoorCondition = 0.5,
		Pay = { 0.9, 1, 1.2 } :: { number },
		Xp = { 1, 1, 1.25 } :: { number },
		StreakStep = 0.05,
		StreakMax = 0.25,
	},
	-- 4.7, the licences (JobRules.hasLicence; profile.licences, profile.licenceJobs): the board's ordinary deliveries of
	-- a tier listed here (and a board special without its own level, the Winter Run) need its level AND `jobs` jobs
	-- rated ★★ or better at danger `atTier` or higher. A save from before 4.7 that has delivered and already has the
	-- level keeps the tier (JobRules.grandfather).
	Licences = {
		{ tier = 3, level = 6, jobs = 5, atTier = 2 }, -- 5.0: level 6 (4.7: 4)
		{ tier = 4, level = 9, jobs = 10, atTier = 3 }, -- 5.0: level 9 (4.7: 7)
	} :: { { tier: number, level: number, jobs: number, atTier: number } },
	-- 4.8, cargo with rules (shared/JobRules.luau cargoRules …, server/Jobs.luau, server/Cargo.luau): what a job's cargo
	-- asks of you, from the look of its pieces (Looks), its Carrying kind (Kinds) and, for a business whose look is
	-- shared, its id (Businesses). Never the tutorial's delivery or a mission (they are told as they are written).
	--   fragile  hard braking (a drop of BrakeDecel studs/s² or more from BrakeSpeed or faster) or a bump (BumpDecel or
	--            more: a wall, a car, a zombie) costs FragileBrake / FragileBump of the condition, a hit while faster
	--            than HitSpeed FragileHit on top of the usual damage loss; one jolt every JoltCooldown s at most, and
	--            the HUD says CAREFUL — FRAGILE
	--   food     the freshness goes from 100 % down by FoodDrain[tier] a minute once the food is picked up (a Cooler Box:
	--            × Config.GearTuning.CoolerDrain); below GoodFresh it is a miss of the rating (two below PoorFresh),
	--            and the pay × FreshPayMin … 1 with the freshness
	--   heavy    carried by hand alone you walk at HeavyCarrySpeed; the hand trolley, or a crew mate within
	--            Config.Missions.LiftHelpRange, at the normal pace
	--   cash     the bandits come more (the job's banditBoost at least CashBoost where the tier has bandits)
	--   people   a bump makes them complain: PeopleBump of the condition
	-- Ratchet Straps (Config.GearTuning.StrapsLoss) cut every condition loss from driving: the jolts and the car's
	-- damage.
	CargoRules = {
		Looks = {
			pizza = { "food" },
			bread = { "food" },
			groceries = { "food" },
			soup = { "food" },
			cake = { "fragile", "food" },
			vaccine = { "fragile" },
			sample = { "fragile" },
			electronics = { "fragile" },
			painting = { "fragile" },
			barrel = { "heavy" },
			generator = { "heavy" },
			furniture = { "heavy" },
			gold = { "cash" },
			-- 5.3, the storefronts' own pieces
			burger = { "food" },
			noodles = { "food" },
			pastry = { "food" },
			icecream = { "food" },
			gadget = { "fragile" },
		} :: { [string]: { string } },
		Kinds = {
			cash = { "cash" },
			kid = { "people" },
			patient = { "people" },
			survivor = { "people" },
		} :: { [string]: { string } },
		Businesses = {
			electronics = { "fragile" }, -- radio parts in the parcel look
			bank = { "heavy" }, -- the strongboxes (the gold look is the cash sacks too)
		} :: { [string]: { string } },
		BrakeSpeed = 30, -- studs / s: hard braking counts from this speed
		BrakeDecel = 50, -- studs / s²: the speed dropping this fast is hard braking (coasting ~20, an Old Van's brake ~28)
		BumpDecel = 160, -- … this fast a bump (no brake does it: a wall, a car, a zombie run over)
		JoltCooldown = 1.2,
		FragileBrake = 0.03,
		FragileBump = 0.08,
		HitSpeed = 20, -- a hit (the car damaged) while faster than this …
		FragileHit = 0.04, -- … costs a fragile cargo this on top
		PeopleBump = 0.05,
		-- 6.4, fragile pieces on foot (Config.Throw.FragileLooks or a fragile job: a cake, a gadget, electronics …) with
		-- you in the hands or a bag (shared/JobRules.luau footKnock / knockLoss, server/Cargo.luau Cargo.footKnock): a
		-- landing after falling faster than FootFallSpeed costs FootFall of each such order's condition, a bite or a
		-- bullet (FootHitMin health or more at once) FootHit; one knock every FootKnockCooldown s. The Padded Messenger
		-- Bag (Config.Kit padded) in your hand keeps the pieces in it safe. (A jump lands at ~50 studs / s.)
		FootFallSpeed = 75,
		FootFall = 0.1,
		FootHit = 0.05,
		FootHitMin = 5,
		FootKnockCooldown = 1.5,
		FoodDrain = { 0.05, 0.06, 0.07, 0.08 } :: { number }, -- freshness a minute, by danger level
		GoodFresh = 0.7,
		PoorFresh = 0.35,
		FreshPayMin = 0.7, -- stale food (0 %) pays this share; fresh 100 %
		HeavyCarrySpeed = 4, -- studs / s
		CashBoost = 1.6,
		NoticeEvery = 2.5, -- seconds between two CAREFUL notices
	},
	-- 4.8, multi-drop (server/Jobs.luau ordinaryOffer, JobRules.dropCount): a board delivery of these danger levels
	-- (not the SHORT & SAFE one) goes to 2 … Max[tier] customers with Chance[tier]: every piece is labelled for its
	-- customer (the wrong one is refused), the drops Gap studs apart one after the other; each extra drop pays
	-- PayPerStop.
	MultiDrop = {
		Chance = { 0, 0, 0.45, 0.6 } :: { number },
		Max = { 1, 1, 2, 3 } :: { number },
		Gap = { 150, 450 } :: { number },
		PayPerStop = 60,
	},
	-- 4.8, road events (server/Jobs.luau, JobRules.pickEvent): at most one a job, with Chance, never the tutorial's or a
	-- mission; it comes after After (min, max) seconds of driving out of the safe zone, by Weights:
	--   survivor   somebody waves by the road SurvivorAhead studs ahead: stop next to them (SurvivorReach) and they
	--              hop in; drop them in the depot's safe zone (the job may end meanwhile, SurvivorKeep s at most) for
	--              SurvivorBonus × the tier's stars; they give up after SurvivorWait s or when you drive off
	--   addon      a side pick-up: one more piece from an address AddOnDistance studs from you, before the drop it
	--              goes to: + AddOnPay and the time for it; Y (or the button) within AddOnAnswer s
	--   roadblock  the street ahead is blocked (a bandit roadblock; on a ★ job without bandits)
	RoadEvents = {
		Chance = 0.3,
		After = { 25, 70 } :: { number },
		Retry = 8, -- no spot for it now: tried again after this many seconds of driving …
		Tries = 5, -- … this often at most
		Weights = { survivor = 1, addon = 1, roadblock = 1 } :: { [string]: number },
		SurvivorAhead = 150,
		SurvivorReach = 18,
		SurvivorWait = 45,
		SurvivorKeep = 600,
		SurvivorBonus = 60, -- × the tier's stars
		AddOnPay = 180,
		AddOnDistance = { 80, 220 } :: { number },
		AddOnAnswer = 15,
		AddOnGivers = { "Mabel", "Old Tom", "Kenny", "Norm", "Aunt Maple" } :: { string },
	},
	-- 5.7, life on a run on foot or by bike (shared/FootEvents.luau picks, server/RunEvents.luau runs them; never the
	-- tutorial's delivery, a car job or a mission). A light road event on about one run in four (Chance), after After
	-- (min, max) seconds out of the safe zone, by Weights (none of the car-only ones: no add-on, no blocked street):
	--   runner    a runner zombie comes after you from RunnerDistance studs away: keep moving, or fight it off
	--   survivor  somebody calls for help SurvivorAhead studs ahead: walk up (SurvivorReach) and help them for a Tip
	--             (min, max dollars; a bike pays the same); they give up after SurvivorWait s or once you are far past
	--   gate      a locked gate across the sidewalk GateAhead studs ahead (GateWidth wide, from the kerb in): go round
	--             by the road; it is taken away after GateTime s
	-- No spot for it now: tried again after Retry s, Tries times at most. And at about one drop in five (GroupChance),
	-- once you come within GroupNear studs of it, a small group of walkers (Group: min, max) shambles about
	-- GroupDistance studs from the drop (never in the safe zone).
	FootEvents = {
		Chance = 0.25,
		After = { 20, 60 } :: { number },
		Retry = 6,
		Tries = 5,
		Weights = { runner = 1, survivor = 1, gate = 1 } :: { [string]: number },
		RunnerDistance = { 70, 110 } :: { number },
		SurvivorAhead = 45,
		SurvivorReach = 7,
		SurvivorWait = 40,
		SurvivorNames = { "Ada", "Big Lou", "Pam", "Toby", "Nina", "Grandpa Joe", "Eli", "Martha" } :: { string },
		Tip = { 15, 35 } :: { number },
		GateAhead = 30,
		GateWidth = 10,
		GateTime = 60,
		GroupChance = 0.2,
		Group = { 2, 3 } :: { number },
		GroupDistance = { 30, 55 } :: { number },
		GroupNear = 120,
	},
	-- 5.7, the step up to a car: a ★ board delivery done in your own car gives XpBonus more XP than a ★ job and takes
	-- Pieces (min, max; SHORT & SAFE the fewest) pieces, never more than your car holds now (at least EasyMaxPieces),
	-- so the Old Van at level 4 is clearly a promotion over a bike run (Bike.XpBonus).
	CarStep = {
		XpBonus = 40,
		Pieces = { 3, 4 } :: { number },
	},
	-- 5.7: a job whose server tick fails this many times in a row ends (Jobs.fail) instead of stranding its player.
	TickFails = 5,
	-- 5.2, several orders at once (server/Jobs.luau addOrder, shared/JobRules.luau's orders): while a stackable run is
	-- on (an ordinary board delivery on foot, on a bike, or a car one of the ★ … CarTiers tiers; never a mission, a
	-- special, an employer's job, DUO, the Freight Run or the tutorial's), ACCEPT on the board adds another order of
	-- the same kind (+ ADD ORDER) while your free room takes its pieces (what you carry: hands + bag on foot, the
	-- bike + its gear + your bag, the car + its gear; minus the pieces the open orders still hold or will pick up)
	-- and fewer than Max[mode] orders are open. Every order keeps its own clock (its offer's, from when it was added),
	-- pay and rating. The stops go in any order: the GPS takes the open stop whose circle you are at (AtStop studs),
	-- else the pinned order's nearest, else the nearest one (the current one kept unless another is Hysteresis studs
	-- nearer). A road event's add-on becomes an order of its own (AddOnTime s on top of the trip for it).
	Orders = {
		Max = { foot = 2, bike = 3, car = 4 } :: { [string]: number },
		CarTiers = 2, -- the car tiers whose board deliveries stack (★, ★★)
		AtStop = 30,
		Hysteresis = 80,
		SwitchEvery = 1, -- seconds between two changes of the stop the GPS shows (no flicker between two close ones)
		AddOnTime = 30,
	},
	-- 5.3, real places (shared/Deliveries.luau, server/Jobs.luau, server/Cargo.luau): the board's deliveries start at
	-- the business's storefront (Map.Venues; the nearest one to you: within the light job's PickupMax + PickupWiden on
	-- foot or by bike, CarReach in a car) where its cook / clerk hands the order over in the doorway, and go to a home's
	-- door (Map.Homes) or another storefront (Config.Jobs.Businesses `to`). At a home you knock (the owner comes within
	-- KnockRange of the door): the door swings open (DoorSwing degrees, for DoorOpen s) and the receiver steps out
	-- after KnockDelay s. With NobodyHome a drop has nobody in: "Leave at the door" (it counts the same).
	Places = {
		CarReach = 1600,
		KnockRange = 22,
		KnockDelay = 1.2,
		DoorSwing = 80,
		DoorOpen = 6,
		NobodyHome = 0.1,
		-- 5.3 review: two couriers at the same storefront (or door) at once: the second one's pile, clerk and pieces
		-- stand SessionGap studs to the side (then the other side, then twice as far …), never on top of each other.
		SessionGap = 10,
		-- 5.3 review: no ON FOOT run because every storefront near you is shut (the Suburbs or the Harbor at night; the
		-- board looks up to twice the usual reach first): the board says so.
		ClosedNote = "Shops here are closed — Downtown food is open late",
	},
	-- 5.3, the newspaper round (server/Jobs.luau footOffer's "round", shared/Deliveries.luau Deliveries.round, the
	-- toss in server/Cargo.luau): from Hours on the game clock (the morning) the ON FOOT and the BIKE sections offer a
	-- round of The Daily Undead (Business). Pick up the bundle (Papers: one E, it goes into your newspaper satchel: no
	-- room needed) and bring one paper to every door on one or two streets (Streets; a third only when two do not
	-- hold Papers[1]), every door within FootReach / BikeReach of the print shop and the route from it through them
	-- within FootRoute / BikeRoute (5.3 review): a house takes one, an
	-- apartment entrance FlatPapers (its subscribers). At a door "Toss newspaper" (E) works from TossRange studs:
	-- within SureToss it always lands on the porch, farther it lands in the bushes with a chance growing to MissAtRange
	-- (still delivered, but a miss). Pay: PayBase + PayPerPaper a paper + PayPerStud × the route (bike × BikePay),
	-- rounded to $5, + NoMissTip with no miss at all; clock: TimeBase + the route at the light job's Speed + TimePerDoor
	-- a door. Never stacked with other orders (a round is one order). Level 1 on foot, the bike's level by bike.
	Round = {
		Business = "news",
		Hours = { 4, 11 } :: { number },
		Papers = { 8, 12 } :: { number },
		Streets = 2,
		FlatPapers = 2,
		FootReach = 700,
		BikeReach = 1500,
		-- 5.3 review: the route from the print shop through every door at most this long (a walk stays a walk)
		FootRoute = 700,
		BikeRoute = 1600,
		TossRange = 18,
		SureToss = 8,
		MissAtRange = 0.5,
		PayBase = 40,
		PayPerPaper = 8,
		PayPerStud = 0.04,
		BikePay = 1.3,
		NoMissTip = 40,
		TimeBase = 60,
		TimePerDoor = 10,
	},
	-- The ordinary deliveries: every business sends what it makes or sells, to somebody who needs it.
	-- 5.3, real places (shared/Deliveries.luau, server/Jobs.luau): a business with a storefront (Map.Venues) sends from
	-- there: its cook / clerk hands the order over at the door. B2C goes to a home's door (`to`: "house" | "apartment",
	-- Map.Homes; the receivers are the people living there); B2B to another business's storefront ("venue:<id>": its
	-- own person takes it) or to the Harbor ("harbor": the dock foreman). The bakery bakes in the morning (`hours`),
	-- the pizzas, burgers and noodles pay more in the evening and at night (`peak`), the café opens early, The Daily
	-- Undead prints the morning paper (and its round: Config.Jobs.Round). `to` nil: any address as before (the far
	-- places of the dangerous levels: the lab, the bank's gold, the warehouse's fuel).
	Businesses = {
		{
			id = "pizzeria",
			place = "Luigi's Pizza",
			cargo = "Pizzas",
			piece = "pizza stack",
			plural = "pizza stacks",
			kind = "crate",
			look = "pizza",
			pieces = { 1, 2 },
			tiers = { 1, 2 },
			giver = { name = "Luigi", title = "Pizza chef", role = "cook" },
			receivers = {
				{ name = "Hungry Hannah", title = "Ordered extra cheese", role = "townsperson" },
				{ name = "The Twins", title = "Night shift", role = "townsperson" },
				{ name = "Norm", title = "Movie night", role = "townsperson" },
			},
			to = { "house", "apartment" },
			peak = { 18, 4, 1.25 },
		},
		{
			id = "bakery",
			place = "Daily Bread Bakery",
			cargo = "Fresh Bread",
			piece = "bread sack",
			plural = "bread sacks",
			kind = "sack",
			look = "bread",
			pieces = { 2, 3 },
			tiers = { 1, 2 },
			giver = { name = "Anna", title = "Baker", role = "cook" },
			receivers = {
				{ name = "Grandma Rose", title = "Feeds the street", role = "townsperson" },
				{ name = "Hungry Hannah", title = "Breakfast for six", role = "townsperson" },
				{ name = "Old Tom", title = "Fresh rolls, every day", role = "townsperson" },
			},
			to = { "house", "apartment", "venue:cafe", "venue:burgers" },
			hours = { 4, 12 },
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
			giver = { name = "Fred", title = "Postmaster", role = "clerk" },
			receivers = {
				{ name = "Grandma Rose", title = "Waiting for letters", role = "townsperson" },
				{ name = "Sal", title = "Mail-order clippers", role = "shopkeeper" },
				{ name = "Norm", title = "New boots", role = "townsperson" },
			},
			to = { "house", "apartment" },
		},
		{
			id = "pharmacy",
			place = "Corner Pharmacy",
			cargo = "Medicine",
			piece = "medicine box",
			plural = "medicine boxes",
			kind = "crate",
			look = "medicine",
			pieces = { 1, 3 },
			tiers = { 1, 2, 3 },
			giver = { name = "Phil", title = "Pharmacist", role = "clerk" },
			receivers = {
				{ name = "Grandma Rose", title = "Needs her pills", role = "townsperson" },
				{ name = "Bert", title = "Bitten? Just a scratch", role = "townsperson" },
				{ name = "Lorna", title = "Fever since Monday", role = "townsperson" },
			},
			to = { "house", "apartment" },
		},
		{
			id = "supermarket",
			place = "FreshMart",
			cargo = "Groceries",
			piece = "grocery box",
			plural = "grocery boxes",
			kind = "crate",
			look = "groceries",
			pieces = { 2, 3 },
			tiers = { 1, 2 },
			giver = { name = "Carla", title = "Store manager", role = "shopkeeper" },
			receivers = {
				{ name = "Hungry Hannah", title = "Empty fridge", role = "townsperson" },
				{ name = "Old Tom", title = "Can't carry the bags", role = "townsperson" },
				{ name = "The Twins", title = "The weekly shop", role = "townsperson" },
			},
			to = { "house", "apartment" },
			hours = { 7, 22 },
		},
		{
			id = "hardware",
			place = "Bolt & Nail Hardware",
			cargo = "Tools",
			piece = "tool crate",
			plural = "tool crates",
			kind = "crate",
			look = "tools",
			pieces = { 1, 3 },
			tiers = { 2, 3 },
			giver = { name = "Bob", title = "Hardware store", role = "worker" },
			receivers = {
				{ name = "Old Pete", title = "Fixing his roof", role = "townsperson" },
				{ name = "Norm", title = "Boarding up the windows", role = "townsperson" },
				{ name = "Aunt Maple", title = "A new fence", role = "townsperson" },
			},
			to = { "house", "harbor" },
			hours = { 6, 20 },
		},
		{
			id = "electronics",
			place = "Volt Electronics",
			cargo = "Electronics",
			piece = "electronics box",
			plural = "electronics boxes",
			kind = "crate",
			look = "gadget",
			pieces = { 1, 2 },
			tiers = { 2, 3 },
			giver = { name = "Kenji", title = "Electronics store", role = "clerk" },
			receivers = {
				{ name = "Sparks", title = "Ham radio operator", role = "worker" },
				{ name = "Kenny", title = "A new console, still", role = "townsperson" },
				{ name = "Miss Amy", title = "A radio for the news", role = "teacher" },
			},
			to = { "apartment" },
		},
		{
			id = "pawnshop",
			place = "Second Life Pawn",
			cargo = "Ammo",
			piece = "ammo crate",
			plural = "ammo crates",
			kind = "ammo",
			look = "ammo",
			pieces = { 1, 2 },
			tiers = { 2, 3, 4 },
			giver = { name = "Vinnie", title = "Pawn broker", role = "banker" }, -- 6.8: the fixer of the missions (shared/Cast.luau)
			receivers = {
				{ name = "Old Pete", title = "Guards his street", role = "townsperson" },
				{ name = "Jax", title = "Holding out at home", role = "worker" },
				{ name = "Aunt Maple", title = "Shells for the shotgun", role = "townsperson" },
			},
			to = { "house", "apartment" },
		},
		{
			id = "warehouse",
			place = "Harbor Warehouse",
			cargo = "Generator Fuel",
			piece = "fuel barrel",
			plural = "fuel barrels",
			kind = "barrel",
			look = "barrel",
			pieces = { 1, 2 },
			tiers = { 2, 3, 4 },
			giver = { name = "Rocco", title = "Harbor boss", role = "foreman" }, -- 6.8: shared/Cast.luau (Gus runs the Train Yard)
			receivers = {
				{ name = "Nurse Kim", title = "The clinic's generator", role = "nurse" },
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
			giver = { name = "Doctor Hiro", title = "Lab chief", role = "doctor" }, -- 6.8: shared/Cast.luau
			receivers = {
				{ name = "Doctor Ellie", title = "Doctor", role = "doctor" },
				{ name = "Nurse Kim", title = "Rooftop clinic", role = "nurse" },
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
			giver = { name = "Doctor Hiro", title = "Lab chief", role = "doctor" }, -- 6.8: shared/Cast.luau
			receivers = {
				{ name = "Doctor Ellie", title = "Working on a cure", role = "doctor" },
			},
		},
		{
			id = "bank",
			place = "First Zombie Bank",
			cargo = "Gold Bars",
			piece = "strongbox",
			plural = "strongboxes",
			kind = "crate",
			look = "gold",
			pieces = { 1, 2 },
			tiers = { 3, 4 },
			giver = { name = "Simon", title = "Bank teller", role = "clerk" }, -- (6.8: Gordon is the manager)
			receivers = {
				{ name = "The Mayor", title = "City hall", role = "clerk" },
				{ name = "Officer Nate", title = "Police bunker", role = "soldier" },
			},
		},
		{
			id = "cake",
			place = "Daily Bread Bakery",
			cargo = "Wedding Cake",
			piece = "cake box",
			plural = "cake boxes",
			kind = "crate",
			look = "cake",
			pieces = { 1, 1 },
			tiers = { 2, 3 }, -- 5.3 review: its houses are 470 … 1,300 studs from the bakery (never a ★★★★ ride)
			giver = { name = "Anna", title = "Baker", role = "cook" },
			receivers = {
				{ name = "Lucy and Tom", title = "Getting married", role = "townsperson" },
			},
			to = { "house" },
			hours = { 6, 18 },
		},
		-- 5.3, the storefronts that came with the real places (Stream W's stubs, filled):
		{
			id = "burgers",
			place = "Last Bite Burgers",
			cargo = "Burgers",
			piece = "burger bag",
			plural = "burger bags",
			kind = "crate",
			look = "burger",
			pieces = { 1, 2 },
			tiers = { 1, 2 },
			giver = { name = "Big Al", title = "Grill cook", role = "cook" },
			receivers = {
				{ name = "The Twins", title = "Night shift", role = "townsperson" },
				{ name = "Hungry Hannah", title = "Ordered fries too", role = "townsperson" },
				{ name = "Kenny", title = "Double cheese, no pickles", role = "townsperson" },
			},
			to = { "house", "apartment" },
			peak = { 18, 4, 1.25 },
		},
		{
			id = "noodles",
			place = "Wok Dead",
			cargo = "Noodles",
			piece = "noodle box",
			plural = "noodle boxes",
			kind = "soup",
			look = "noodles",
			pieces = { 1, 2 },
			tiers = { 1, 2 },
			giver = { name = "Mei", title = "Wok cook", role = "cook" },
			receivers = {
				{ name = "Sparks", title = "Up all night on the radio", role = "worker" },
				{ name = "The Twins", title = "Night shift", role = "townsperson" },
				{ name = "Miss Amy", title = "Marking homework", role = "teacher" },
			},
			to = { "apartment", "house" },
			hours = { 11, 4 },
			peak = { 18, 4, 1.3 },
		},
		{
			id = "cafe",
			place = "Grind House",
			cargo = "Pastries",
			piece = "pastry bag",
			plural = "pastry bags",
			kind = "sack",
			look = "pastry",
			pieces = { 1, 2 },
			tiers = { 1 },
			giver = { name = "Jules", title = "Barista", role = "cook" },
			receivers = {
				{ name = "Grandma Rose", title = "Her morning croissant", role = "townsperson" },
				{ name = "Miss Amy", title = "Breakfast before school", role = "teacher" },
				{ name = "Benny", title = "Two cinnamon rolls", role = "shopkeeper" },
			},
			to = { "house", "apartment" },
			hours = { 6, 15 },
		},
		{
			id = "news",
			place = "The Daily Undead",
			cargo = "Newspapers",
			piece = "newspaper",
			plural = "newspapers",
			kind = "sack",
			look = "newspaper",
			pieces = { 1, 3 },
			tiers = { 1 },
			giver = { name = "Ed", title = "Printer", role = "clerk" },
			receivers = {
				{ name = "Old Tom", title = "Reads it twice", role = "townsperson" },
				{ name = "Grandma Rose", title = "Wants the crossword", role = "townsperson" },
			},
			to = { "house", "apartment" },
			hours = { 4, 11 },
		},
		{
			id = "flowers",
			place = "Bloom",
			cargo = "Flowers",
			piece = "bouquet",
			plural = "bouquets",
			kind = "crate",
			look = "bouquet",
			pieces = { 1, 2 },
			tiers = { 1, 2 },
			giver = { name = "Lily", title = "Florist", role = "shopkeeper" },
			receivers = {
				{ name = "Lucy and Tom", title = "Getting married", role = "townsperson" },
				{ name = "Grandma Rose", title = "Her birthday", role = "townsperson" },
				{ name = "Lorna", title = "Their anniversary", role = "townsperson" },
			},
			to = { "house", "apartment" },
			hours = { 8, 19 },
		},
		{
			id = "icecream",
			place = "Frosty's Ice Cream",
			cargo = "Ice Cream",
			piece = "ice cream tub",
			plural = "ice cream tubs",
			kind = "icebox",
			look = "icecream",
			pieces = { 1, 2 },
			-- 5.3 review: Frosty's is at the Harbor, the nearest home ~800 studs off: a ★★ ride, never a ★ walk
			tiers = { 2 },
			giver = { name = "Frosty", title = "Ice cream man", role = "shopkeeper" },
			receivers = {
				{ name = "The Twins", title = "Hot day", role = "townsperson" },
				{ name = "Aunt Maple", title = "A birthday party", role = "townsperson" },
			},
			to = { "house", "apartment" },
			hours = { 11, 20 },
		},
	} :: { BusinessDef },
	-- At a far place the place's own person takes the ordinary deliveries.
	PlacePeople = {
		base = { name = "Sergeant Roy", title = "Quartermaster", role = "soldier" },
		lodge = { name = "Ingrid", title = "Lodge keeper", role = "shopkeeper" },
		radio = { name = "Sparks", title = "Radio operator", role = "worker" },
		farm = { name = "Lucy", title = "Farm hand", role = "farmer" },
		docks = { name = "Rocco", title = "Harbor boss", role = "foreman" }, -- 6.8: shared/Cast.luau
		gas = { name = "Tony", title = "Pump attendant", role = "attendant" },
		school = { name = "Miss Amy", title = "Teacher", role = "teacher" },
		frosty = { name = "Molly", title = "At the counter", role = "icecream" },
		movers = { name = "Cody", title = "Big Move Movers", role = "mover" },
		ranch = { name = "Jesse", title = "Ranch hand", role = "rancher" },
		stables = { name = "Emma", title = "Riding instructor", role = "rider" },
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
		cashrun = { giver = "banker", receiver = "soldier" }, -- Gordon, the bank manager; Sergeant Roy as at the base
		ambulance = { giver = "townsperson", receiver = "nurse" }, -- Nurse Ada; the patient walks in by themselves (board)
		pizzarush = { giver = "cook", receiver = "townsperson" },
		freightrun = { giver = "foreman", receiver = "worker" }, -- 4.0: the dock foreman; FreightReceivers at the drop
	} :: { [string]: { giver: string, receiver: string } },
	-- 4.0, the Freight Run: who takes the pallets at each receiving dock (shared/Map.luau ReceivingDocks).
	FreightReceivers = {
		market = { name = "Rita", title = "FreshMart stock room", role = "clerk" },
		movers = { name = "Cody", title = "Big Move Movers", role = "mover" },
		powerplant = { name = "Engineer Ivan", title = "Power Plant", role = "foreman" }, -- 6.8: shared/Cast.luau
	} :: { [string]: PersonDef },
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
		-- 4.0, freight (shared/Freight.luau): a wooden pallet of shrink-wrapped boxes, moved only with a pallet jack
		pallet = { piece = "pallet", plural = "pallets", look = "pallet" },
	} :: { [string]: { piece: string, plural: string, look: string } },
	-- Extra seconds on the clock for every piece handled at a stop (loading and unloading each count).
	TimePerPiece = { carry = 9, lead = 14, board = 4, serve = 0, pallet = 20 } :: { [string]: number },
	PayPerPiece = 15, -- an ordinary delivery pays this per piece on top of the tier's pay
	SpawnDistance = 300, -- the people and the cargo appear when the job's owner is this close to the stop
	ApproachDistance = 80, -- closer than this the HUD says what to do on foot and the enemies come on foot
	PileOffset = 12, -- an address without a cargo spot: the pile is this far from the road toward the building
	PromptDistance = 10,
	-- 5.3 review: the CollectionService tag of every job prompt (server/Cargo.luau; the attribute CargoOwner = the job
	-- owner's UserId): client/CargoPrompts.luau hides the ones of a job you do not work for.
	PromptTag = "CargoPrompt",
	HoldDuration = 0, -- 4.0.1: E picks up / loads / opens the back at once (no hold; it was 0.25 s)
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
	-- 3.7, two in your hands (server/Cargo.luau): a piece of a light look (the model, not the kind: the pizzeria sends
	-- "crate" kind pizza stacks) can be carried two at a time, stacked. One light piece leaves a hand free: you open and
	-- close the back yourself (server/Vehicles.luau reads the character attribute CarryHands = 1). Two pieces (or one
	-- heavy piece, a horse) fill both hands: put one down (G, one at a time) or let a crew mate open it. Everything not
	-- listed is heavy (crates, barrels, ammo, furniture, coolers, people, horses) and goes one at a time; so does every
	-- piece of a job with the lift or the pair twist.
	LightLooks = {
		pizza = true,
		parcel = true,
		mail = true,
		bread = true,
		medicine = true,
		documents = true,
		cake = true,
		groceries = true,
		plants = true,
		-- 5.3, the storefronts' own pieces
		burger = true,
		noodles = true,
		pastry = true,
		newspaper = true,
		bouquet = true,
		icecream = true,
		gadget = true,
	} :: { [string]: boolean },
	-- 6.6: no backpack (5.3's PackLooks are gone): every light piece fits your bag and the bike's own bag, a heavy one
	-- only your hands.
	-- 6.7, real sizes (the owner: "not realistic"): a light piece is built at LightScale of its 3.x size (a pizza box about
	-- 33 cm across, a parcel 30–40 cm: a box carried in both hands is about a stud wide), LookScale per look; the heavy
	-- ones as before (server/Cargo.luau buildLook). In the hands the stack's bottom is at most CarryLow studs over the
	-- body's root (on the forearms) and its back CarryFront in front of it.
	-- 6.8 review: the root's middle is 0.6 higher in the body now (server/CharacterArt/Geometry.luau G 3.8): the stack
	-- goes as much lower on it, to where the forearms are (the elbows 0.3 under the root): CarryLow 0.05 → -0.55; a
	-- tall stack's middle at most CarryMiddle over the root (it was 1.1 in server/Cargo.luau stackHeld).
	-- 6.9: Roblox's classic R15 (the hips 1 under the root's middle, the 6.0 body's numbers): 0.05 and 1.1 again
	LightScale = 0.5,
	LookScale = { cake = 0.36, medicine = 0.42, newspaper = 0.6, bouquet = 0.55 } :: { [string]: number },
	CarryLow = 0.05,
	CarryMiddle = 1.1,
	CarryFront = 0.52,
	HandsMax = 2, -- light pieces in one player's hands at most
	-- 6.6, the bike's own bag (its rack, basket or box: server/Cargo.luau, shared/Holding.luau bikeNear): on a run with a
	-- bike, a pickup goes onto it while your bike is within BikeReach studs of you (or you sit on it), and at a drop E
	-- takes its pieces from it only then ("Your bike has it: bring it closer.").
	BikeReach = 12,
	TwoPieceSpeed = 7, -- the walk (studs / s, the CarrySpeed attribute) with two pieces stacked (one: client/CameraRig's carry step)
	-- 3.7, the car doors (server/Vehicles.luau, client/CarVisuals.luau): the E to get in shows only at a door (the driver's
	-- on the left, the passengers' on their side), this close; the door swings out this far.
	DoorReach = 5,
	DriverDoorReach = 7, -- the owner's door: parked flush against a wall you still reach it from the front corner (the
	-- passenger side of the narrowest car is 8+ away, so "Drive" still never shows there)
	SeatReach = 3.5, -- a seat with no door (a bed, a roof gunner, a jump seat): close, so its E never takes the back's E
	DoorSwing = 70, -- degrees
	-- 3.10, getting in and out (shared/Boarding.luau, client/CarBoarding.luau, server/Vehicles.luau): E at a door, a step
	-- to the handle (BoardStepSeconds, the hand on it, the door swings open), a slide in through the door, the server
	-- seats you BoardSeconds after the E and the door shuts behind you; E (or Space) in a seat slides you out at your
	-- door in AlightSeconds. A seat with no door (a bed, a roof, a jump seat) is a short climb in an arc.
	BoardSeconds = 0.5,
	BoardStepSeconds = 0.15, -- to the handle, of BoardSeconds
	AlightSeconds = 0.35,
	DoorSwingSeconds = 0.18, -- a cabin door swinging open
	DoorShutSeconds = 0.2, -- and shut
	DoorStandOut = 1.4, -- where you stand at a door: this far out from the body (the prompt's attachment too)
	BoardSitLift = 1.5, -- seated, the root sits this far over the seat's top (where the slide in ends)
	BoardDuck = 14, -- degrees: the body ducks forward this much through the door
	ClimbArc = 1.6, -- studs: a doorless seat's climb goes this much over the higher end
	BoardMaxSpeed = 8, -- studs / s: the car faster than this, getting in is cancelled (you stand at the door)
	AlightSlideMaxSpeed = 14, -- studs / s: out of a car faster than this you are put out at once (no slide)
	BoardRange = 16, -- studs: farther than this from the seat when it is time to sit, getting in is cancelled
	-- 4.0, freight and equipment (shared/Freight.luau, server/Equipment.luau, server/Cargo.luau). The hand trolley of a
	-- car with the "trolley" gear (4.6, Config.Gear; its TrolleyMount) takes TrolleyPieces pieces of any kind but people,
	-- horses and pallets; a pallet (Kinds.pallet) moves only on a pallet jack, one at a time, into a vehicle that takes
	-- pallets (Economy.palletsOf), where it uses PalletSlots of the cargo slots.
	TrolleyPieces = 4,
	TrolleySpeed = 10, -- the walk (studs / s, the CarrySpeed attribute) pushing an empty trolley
	TrolleyLoadedSpeed = 8.5, -- … a loaded one
	JackSpeed = 6, -- … the pallet jack (empty or with a pallet)
	TrolleyColumnGap = 2.3, -- two pieces side by side on the trolley's toe plate: their middles this far apart
	PalletSlots = 4, -- the cargo slots a pallet uses
	PalletSpacing = 4.3, -- pallets in a row in a vehicle without its own pallet slots (shared/Freight.luau palletSpots)
	SlotDepth = 3.4, -- how deep a cargo slot is (the pallets start half a slot in front of the front slot's middle)
	ToolReach = 9, -- G stows the trolley / the truck's jack this close to its mount
	ToolNearby = 40, -- a tool left with nobody this close goes home after …
	TrolleyReturnSeconds = 60, -- … this long (the trolley to its car's mount)
	JackReturnSeconds = 90, -- … or this long (a pallet jack to its parking spot or its truck)
	TrolleyTipPieces = 4, -- the job card says a trolley helps from this many pieces carried
	PalletPay = 120, -- a Freight Run pays this per pallet on top of its pay
}

-- 6.0, the courier on foot: throwing a delivery at a home's door (shared/Throws.luau has the maths, server/Cargo.luau
-- decides, client/Throw.luau aims). Hold X (a gamepad's R1, the touch THROW button) within Range of the door with a
-- light piece that is not fragile: a dotted arc shows where it lands, the power swings while you hold, release throws.
-- The server traces the same arc (Step, Gravity; one bounce off a wall) from your release point (Release: from your
-- body, studs to your right, up and ahead). Landing within DoorRadius of the door = delivered; a miss lies on the
-- ground to pick up (a newspaper round's: in the bushes, a miss). A TRICKSHOT tip when it lands: farther than FarFrom
-- (FarMin … FarMax by the distance up to Range), over something in the way (the straight line blocked, the arc clear:
-- OverTip), off a wall (WallTip).
Config.Throw = {
	Range = 45, -- studs (flat) from the door you may throw from
	DoorRadius = 4, -- a landing this close (flat) to the door's spot is delivered
	Cooldown = 0.8, -- seconds between two throws
	-- 6.7: the throw's wind-up (shared/Gestures.luau "throw": the arm back, the torso turned): the server launches the
	-- piece this many seconds after the throw, when the arm whips through (the piece leaves the hand then)
	WindUp = 0.18,
	MinSpeed = 16, -- studs / s at the weakest …
	MaxSpeed = 60, -- … and the strongest (60 at 45° flies ~45 studs)
	Gravity = 80, -- studs / s² (floatier than the world's: a readable arc)
	MinUp = 5, -- degrees: the throw's angle over the flat, at least …
	MaxUp = 70, -- … and at most
	Lift = 22, -- degrees over where the camera looks (looking level throws up at this)
	ChargeTime = 1.3, -- seconds from the weakest to the strongest throw while you hold (then back down, and again; 6.2:
	-- slower, the gold PERFECT zone has to be catchable)
	Step = 1 / 30, -- seconds per step of the traced arc
	MaxTime = 3, -- the arc is traced this long at most
	Bounce = 0.45, -- the speed kept off a wall (once: MaxBounces) …
	MaxBounces = 1,
	GroundNormal = 0.6, -- … a surface facing up more than this is ground: it lands there
	-- 6.8 review: where the piece leaves the hand, from the root: the right hand's grip at the whip (shared/Gestures.luau
	-- "throw" WindUp seconds in, the arm over the shoulder coming forward, on the courier's body: tests/throws_test.luau
	-- works it out from the rig and holds this to it). It was the shoulder (0.7, 1.3, 0.6): the piece popped down
	-- ~1.8 studs out of the raised hand. The client's arc, its zones and the server all start here (Throws.release).
	-- 6.9: on Roblox's classic R15, the couriers' body again (wider shoulders, shorter arms than 6.7's: 1.4, 2.6, 0.25)
	Release = { side = 1.9, up = 2.0, ahead = 0.1 } :: { side: number, up: number, ahead: number },
	FarFrom = 18, -- studs: a landed throw from farther than this tips …
	FarMin = 5, -- … this at FarFrom …
	FarMax = 25, -- … up to this at Range
	OverTip = 15, -- over a car, a fence, a wall: the straight line was blocked
	WallTip = 10, -- off a wall
	TipCap = 60, -- 6.0 review: the trickshot tips of one run add up to this at most
	Dots = 20, -- the aim's dotted arc
	-- 6.2, the auto-aim (client/Throw.luau): the throw turns to the door by itself at the first of these angles (degrees)
	-- whose arc reaches the door; you time the power. Landing within PerfectRadius of the door's spot is PERFECT: the
	-- customer tips PerfectTip, at most PerfectCap a job (beside the TRICKSHOT tip and its TipCap).
	AutoAngles = { 35, 45, 55, 65 } :: { number },
	PerfectRadius = 1.5,
	PerfectTip = 20,
	PerfectCap = 80,
	PerfectLines = {
		"Right on the mat! Here's a little extra.",
		"What a throw! Keep the change.",
		"Perfect! I'm telling all my neighbours about you.",
		"Bullseye! That deserves a tip.",
	} :: { string },
	-- Too fragile to throw (with a job of the FRAGILE modifier or the fragile cargo rule: everything).
	FragileLooks = { cake = true, vaccine = true, sample = true, electronics = true, painting = true, gadget = true } :: { [string]: boolean },
}

-- 6.0, the courier's look on foot (client/SprintPose.luau, server/KitWear.luau): the plastic bag (Config.Kit BagKit)
-- in the left hand flies behind you by your speed. 6.0.1: from From studs / s on foot the sprint is a real run cycle
-- (shared/RunCycle.luau: the legs, the arms, the waist, the head and the body's bob, set over the stock run animation),
-- for everybody within Range of the camera.
Config.Courier = {
	BagKit = "bag", -- the Config.Kit id: owned, a light piece picked up drops straight into the bag (6.4: the
	-- plastic one; any Config.Kit piece with `extra` is a bag, and the active one is in your hand: shared/Transport.luau)
	VestKit = "hivis", -- 6.0.1: the Courier Vest's Config.Kit id (server/KitWear.luau; given once to pre-6.0.1 saves)
	Sprint = {
		From = 20, -- studs / s on foot: the sprint cycle takes over from here …
		Off = 18.5, -- … and lets go under this (no flicker around From; the walk is 14, the stock run from 18)
		Full = 26, -- the full swing and lean from here (Config.Movement.Sprint is 28)
		Range = 150, -- studs from the camera (yours always)
		BlendTime = 0.15, -- seconds to blend the cycle in or out
		Stride = 7, -- studs run per full cycle (two steps): the cadence follows the speed (6.8 review: on the stock 2-stud
		-- leg; client/SprintPose.luau scales it by each body's own, shared/CourierMotion.luau stride: the courier's 9.8)
	},
	-- 6.1: the bag is a pendulum on a spring (shared/BagSwing.luau, client/BagSway.luau): the hand's real acceleration
	-- swings it (it trails when you start, swings forward when you stop, out on a turn), the air leans it back at a run.
	Bag = {
		Grip = 0.12, -- studs under the hand
		Clear = 0.25, -- 6.7: studs a real-size bag stays over the ground at rest (tools/character-art/bag-check.luau, on the real body)
		Spring = 70, -- the swing's stiffness (ω², 1 / s²: about 1.3 swings a second) …
		Damp = 5, -- … and its damping (1 / s: a few swings, then it hangs still)
		Kick = 0.006, -- radians of swing for every stud / s² the hand speeds up or slows down (a real pendulum: 1 / g)
		HandShare = 0.35, -- of the hand's own swing on top of the body's (the arms pumping must not throw it around)
		MaxAccel = 260, -- studs / s²: the acceleration is clamped to this (a hitch, a respawn, a teleport)
		Smooth = 0.06, -- seconds: the velocities are smoothed over this before they are differentiated
		Drag = 0.0011, -- radians of lean back for every (stud / s)² of the speed (the air at a run: ~50° at 28)
		MaxTilt = 75, -- degrees from hanging straight, at most
		FullSpeed = 28, -- studs / s for the full flutter
		FlutterHz = 5.5, -- the flutter at speed …
		Flutter = 5, -- … degrees at FullSpeed (nothing below a walk)
		Twist = 9, -- degrees it twists about its handles at FullSpeed
		Teleport = 150, -- studs / s: the hand moving faster than this is a jump (a respawn, a seat): the swing starts again
		Range = 120, -- studs from the camera (yours always)
	},
	-- 6.4: each bigger bag swings heavier (shared/BagSwing.luau tuning: these over Bag; the plastic bag is Bag itself):
	-- a softer spring (a slower swing: Spring = ω²), more damping, less flutter at a lower rate, less twist, less lean
	-- in the air. The pivot's Bag attribute (server/KitWear.luau) tells client/BagSway.luau which one hangs there.
	Bags = {
		tote = { Spring = 52, Damp = 5.2, Kick = 0.0055, Drag = 0.0008, Flutter = 3, FlutterHz = 4.4, Twist = 6, MaxTilt = 65 },
		thermal = { Spring = 40, Damp = 5.8, Kick = 0.005, HandShare = 0.3, Drag = 0.0004, Flutter = 1.4, FlutterHz = 3.4, Twist = 3.5, MaxTilt = 50 },
		padded = { Spring = 38, Damp = 6, Kick = 0.005, HandShare = 0.3, Drag = 0.00035, Flutter = 1.2, FlutterHz = 3.2, Twist = 3, MaxTilt = 50 },
		duffel = { Spring = 28, Damp = 6.5, Kick = 0.0042, HandShare = 0.22, Drag = 0.0002, Flutter = 0.6, FlutterHz = 2.6, Twist = 1.5, MaxTilt = 38 },
	} :: { [string]: { [string]: number } },
	-- 6.4, where a bag sits (server/KitWear.luau hangs its pivot there; Config.Kit carry / stays, Holding.wornAs): the
	-- body part, the pivot's spot on it (studs on the nominal block body, scaled to the real one: shared/KitFit.luau)
	-- and its turn (degrees). "hand" is the left hand's grip (Bag.Grip under it; HandOut[id] studs further out: the
	-- boxy thermal bag off the leg). "back" is a bag slung on the back (the tote, the duffel: lying across it),
	-- "hipBack" the messenger slid behind the hip.
	BagPlaces = {
		shoulder = { part = "UpperTorso", at = { -1.14, 0.8, 0.62 }, turn = { 0, 0, -3 } }, -- (6.7: under the arm, behind it)
		hip = { part = "UpperTorso", at = { -1.25, 0.1, 0.6 }, turn = { 0, 0, -2 } }, -- (6.7: the real-size messenger at the back of the hip, clear of the arm)
		back = { part = "UpperTorso", at = { 0, 0.62, 0.95 }, turn = { 0, 90, 0 } },
		hipBack = { part = "UpperTorso", at = { -0.5, 0.05, 0.72 }, turn = { 0, 90, 0 } },
	} :: { [string]: { part: string, at: { number }, turn: { number } } },
	HandOut = { thermal = 0.18, duffel = 0.14 } :: { [string]: number }, -- (6.4.1: the duffel too: full, it swells against the leg; 6.7: the real-size thermal bag and duffel further out)
	-- 6.4: a worn bag's motion (client/BagSway.luau; BagSwing.tuning / BagSwing.bob): on the shoulder or the hip a stiff
	-- small swing (Wear over Bag) and a bounce of Bounce studs with each step (Step studs a step, the full bounce from
	-- FullSpeed); on the back only a soft bob (BackBob studs). Switch: seconds the bag takes to move between the front
	-- and the back (the "sling" / "unsling" gestures of shared/Gestures.luau go with it: the right arm reaches over the
	-- left shoulder).
	Wear = { Spring = 150, Damp = 12, Kick = 0.0015, HandShare = 0, Drag = 0.0001, Flutter = 0, Twist = 0, MaxTilt = 12 } :: { [string]: number },
	Bounce = 0.06,
	BackBob = 0.035,
	Step = 3.5,
	Switch = 0.5,
	-- 6.4: Marge texts once when a level opens a bag you don't own (server/Tutorial.luau; {name}, {room}, {price}).
	BagUnlock = "Sprint with more of your deliveries: ZDC Bags at the depot has the {name} for you now, {room} pieces in it, {price}. It's on your GPS.",
	-- 6.6: Marge's text, once, to a save that owned a backpack (Config.RetiredKit): {money} is the refund
	PackRefund = "Backpacks are gone: bags do it all now. You got {money} back.",
	-- 6.7: Marge's text, once, to a save that owned the Thermal Jacket (Config.RetiredKit, its noJacket flag)
	JacketRefund = "The Thermal Jacket is gone: the Thermal Delivery Bag at ZDC Bags keeps food far hotter. You got {money} back.",
	-- 6.12.2: … and to a save that owned the Running Shoes (Config.RetiredKit, its noShoes flag)
	ShoeRefund = "The Running Shoes are gone from the shops: you got {money} back. Need more legs? An Energy Drink at the gear stall by the spawn.",
	-- 6.4.1, what is in the bag shows (shared/BagFill.luau; server/KitWear.luau on you, server/Cargo.luau on the ground):
	-- the pieces in it (the player's BagCount / BagLooks attributes) show in its opening, up to its room and Max.
	-- 6.7, real sizes (the owner: "the things would never really fit in it"): each piece is its real packed size
	-- (Packed, per BagFill.kind: a pizza box 33 × 4 × 33 cm lying flat, a parcel, a bouquet …; studs on the bag's frame:
	-- x across its thickness, y up, z along its length; `upright` ones are never laid on their side, `stack` ones lie flat
	-- on each other, `proud` their own share sticking out). They are packed as a courier packs: a lane along the length,
	-- the next lane beside it across the thickness, then a layer below (a pizza box that does not fit flat stands on its
	-- edge). The top layer sticks out of the opening by Proud of its height (a flat stack of pizza boxes: its top box at
	-- the rim, seen through the open top); a piece that fits no way round is shrunk, never under MinScale; an overfull bag
	-- pushes them up. Gap studs between them, Tilt degrees of lean (every other one the other way). The body swells as
	-- it fills: its thickness by up to the bag's `bulge` (else Bulge), its length by up to Swell.
	-- Mouth: each bag's opening on its pivot (server/KitArt/Geometry.luau's frame: the grip at the origin, hanging -Y):
	-- the rim's height (y), the inside's thickness (x) and length (z), its depth from the rim to the bottom (d).
	BagFill = {
		Max = 6,
		Proud = 0.3,
		Tilt = 3,
		Gap = 0.015,
		MinScale = 0.7,
		Bulge = 0.25,
		Swell = 0.06,
		Mouth = {
			-- (6.8: x and z grown with KitArt's Geometry.BagScale 1.15: the bags a little wider and deeper)
			bag = { y = -0.39, x = 0.575, z = 1.196, d = 1.08, bulge = 0.25 },
			tote = { y = -0.67, x = 0.368, z = 1.219, d = 1.04, bulge = 0.3 },
			thermal = { y = -0.52, x = 1.196, z = 1.38, d = 0.86, bulge = 0.04 }, -- (rigid: it hardly swells)
			padded = { y = -0.57, x = 0.345, z = 1.242, d = 0.82, bulge = 0.12 },
			duffel = { y = -0.4, x = 0.56, z = 1.6, d = 0.9, bulge = 0.15 }, -- (the open zip along its top; 6.8: not grown)
		} :: { [string]: { y: number, x: number, z: number, d: number, bulge: number? } },
		Packed = {
			pizza = { size = { 0.95, 0.12, 0.95 }, stack = true },
			parcel = { size = { 0.5, 0.45, 0.6 } },
			bouquet = { size = { 0.35, 1.0, 0.35 }, upright = true, proud = 0.4 },
			cake = { size = { 0.65, 0.65, 0.65 }, upright = true },
			groceries = { size = { 0.5, 0.55, 0.7 }, upright = true },
			gadget = { size = { 0.35, 0.4, 0.6 } },
			medicine = { size = { 0.4, 0.4, 0.55 } },
			mail = { size = { 0.08, 0.35, 0.5 } }, -- a bundle of letters
			paper = { size = { 0.18, 0.85, 0.18 }, upright = true }, -- a rolled newspaper
			folder = { size = { 0.06, 0.45, 0.6 } },
			food = { size = { 0.4, 0.45, 0.5 }, upright = true }, -- a take-out bag or box
			bread = { size = { 0.16, 1.0, 0.16 }, upright = true, proud = 0.4 }, -- a baguette
			plants = { size = { 0.45, 0.5, 0.6 }, upright = true }, -- a seedling tray
		} :: { [string]: { size: { number }, upright: boolean?, stack: boolean?, proud: number? } },
	},
	-- 6.7, the bag arm (client/BagSway.luau, every client for every courier near the camera): while a bag hangs in the
	-- left hand its arm is a little straighter and out (Out degrees away from the body; the animation's elbow bend cut by
	-- Straight, its swing by SwingCut: the weight pulls it down), and a loaded bag leans the torso the other way (Lean
	-- degrees with Full pieces in it), laid on top of the animation, blended over Blend seconds. Only while nothing else
	-- has the arm (aiming, carrying, the phone, a gesture, a swing, a car door, the sprint, and Hold seconds after); the
	-- lean only while you stand or walk slower than Calm studs / s (client/ArmPose.luau leans the waist faster than that).
	BagArm = { Out = 9, Straight = 0.5, SwingCut = 0.35, Lean = 3.5, Full = 6, Blend = 0.25, Hold = 0.35, Calm = 10 },
	-- 6.7, items in the hand (server/HandItem.luau, server/Cargo.luau): a piece handed over at a door is in the courier's
	-- right hand for Reach seconds (the "give" gesture), then in the receiver's hands for Pass seconds (they reach for it
	-- Lead seconds before it comes: the "receive" gesture), then on the door's stack; a piece put into the bag is in the
	-- right hand until BagIn seconds into the "bag" gesture, then in the bag (its fill shows it from then on).
	HandItem = { Reach = 0.4, Lead = 0.15, Pass = 0.85, BagIn = 0.3 },
	-- 6.4.1: client/BagSway.luau looks once per spawn, After seconds after your bag shows, whether it really is on you
	-- (parts, not see-through, within Far studs of your hand and of its place) and says in the Output when not.
	BagCheck = { After = 3, Far = 4 },
}

-- 6.1, what you hold (the owner's wish: "you choose to hold the pistol or the bag; with cargo in the bag you can only put
-- it down"): fists, the plastic bag or your gun (shared/Holding.luau, server/Hand.luau, the Hand remote; the bottom
-- bar's hand slots, keys 1 / 2 / 3, client/Hotbar.luau). A loaded bag that leaves your hand is set down on the ground
-- with its cargo (server/Cargo.luau), an empty one is stowed.
Config.Hand = {
	Cooldown = 0.2, -- seconds between two switches (the server)
	Predict = 1.5, -- seconds the client shows its own choice before the server's Hand attribute is trusted again
	BagAhead = 1.3, -- studs in front of your feet (and a little to the left) where a loaded bag is set down
	BagHold = 0.25, -- seconds: the "Pick up bag" prompt's hold
	BagReach = 9, -- studs: its reach
}

-- 6.1, the key hints under the HUD's top buttons (client/KeyHints.luau): a quiet strip of what the keys do now.
-- 6.5: only the keys of the moment (the hands, E, G, X; the driving keys in a seat), folded to "? KEYS [F1]" after the
-- first two deliveries.
Config.KeyHints = {
	OpenUnder = 2, -- deliveries: a courier with fewer starts with the strip open (else folded to its KEYS chip; 5 before 6.5)
	TextSize = 12,
	Check = 0.25, -- seconds between the looks at what to show
}

-- 6.5, the NEXT card and the way to it (the owner: "When I join I don't know what to do. I can't find my way in
-- anything"): shared/Goal.luau picks the words, client/Objective.luau shows the card at the top left of the contract
-- column, client/Hud.luau the marker in the world (the beam and the waypoint; with no job the job board's).
Config.Goal = {
	ResultShown = 8, -- seconds the card says "Delivered! +$45" after a result (while no new job came)
	BoardSpot = { -18, -25 }, -- the depot's job board (server/World.luau buildDepot), studs from the depot's centre
	BoardNear = 9, -- studs: closer than this the board's marker hides (you are at it)
	BeamHeight = 320, -- studs: the light over the goal (4.4.1: 240)
	BeamWide = 1.6, -- studs: its width over the park circle (1.2 before)
	BeamThin = 0.6, -- over the pile / the person / the board (0.5 before)
	BeamAlpha = 0.35, -- its transparency at the bottom (0.6 before): brighter
	PinTextSize = 18, -- the waypoint's words "TONY'S PIZZA · 120 m" (14 before)
	TitleSize = 22, -- the card's title
	PlaceMax = 250, -- px at scale 1: the card's place line at its widest (the distance follows it)
	-- 6.12.1 (the owner: "this shows all game long"): "Take a delivery job" and the job board's marker only for a new
	-- courier, up to this many deliveries; after that, with no job, the card and the marker stay away (J opens the board)
	HintJobs = 3,
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
	-- 4.0, freight (load = unload = "pallet": shared/Map.luau FreightDocks / ReceivingDocks): the drop is one of these
	-- places (their receiving docks), and the job takes 1 … items pallets.
	dropChoices: { string }?,
}

-- Special jobs. The ones with an employer are taken at the employer's place; the others show up on the job board.
Config.JobTypes = {
	{
		id = "schoolrun",
		name = "School Run",
		description = "Pick the kids up at three homes and bring them to Sunny Hill School in the school bus.",
		vehicle = "bus",
		employer = "school",
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4
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
		receiver = "Miss Amy, the teacher",
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
		receiver = "Sergeant Roy",
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
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4
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
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4
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
		giver = "Ruby's family",
		receiver = "Ruby's family",
	},
	{
		id = "farmrun",
		name = "Farm Run",
		description = "Load fresh food at the Old Farm and bring it to two markets in the city.",
		vehicle = "monster",
		employer = "farm",
		level = 9, -- 5.0: the Muscle Car's level (4.x: 8)
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
		giver = "Gordon, the bank manager",
		receiver = "Sergeant Roy",
		banditBoost = 2,
	},
	{
		id = "ambulance",
		name = "Ambulance Run",
		description = "A patient is waiting at their home. Pick them up in the clinic's ambulance and rush them to the City Clinic before it is too late.",
		vehicle = "ambulance",
		employer = "clinic",
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4
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
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4
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
	-- 4.0, freight: pallets from the Harbor Warehouse's loading docks to a receiving dock. A pallet moves only with a
	-- pallet jack (one waits at every dock and every receiving dock, the Freight Truck carries its own) and goes only
	-- into a vehicle that takes pallets (Economy.palletsOf): the board shows it locked "NEEDS N PALLETS" for any other.
	-- On the board (sorted by its stars) from its level, every time (server/Jobs.luau makeBoard); 1 … items pallets.
	{
		id = "freightrun",
		name = "Freight Run",
		description = "Pallets from the Harbor Warehouse's loading docks to a receiving dock. Back up to the dock, lift each pallet with a pallet jack and push it into your truck.",
		vehicle = nil,
		employer = nil,
		board = true,
		level = 6,
		pickups = 1,
		pickupAt = "warehouse",
		drops = 1,
		dropAt = nil,
		dropChoices = { "market", "movers", "powerplant" },
		loadTime = 6,
		unloadTime = 6,
		payPerStop = 220,
		tier = 3,
		cargo = "Freight",
		pickupLabel = "LOAD THE PALLETS AT",
		dropLabel = "DELIVER THE PALLETS TO",
		load = "pallet",
		unload = "pallet",
		items = 3,
		itemKind = "pallet",
		giver = "Gus, the dock foreman",
		receiver = "The stock room",
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
	{ id = "school", name = "Sunny Hill School", icon = "🏫", jobType = "schoolrun", reward = "bus", needed = 3, person = "Principal Helen", pitch = "Our bus driver ran away. Drive the kids to school!" },
	{ id = "army", name = "Military Base", icon = "🪖", jobType = "armysupply", reward = "armored", needed = 4, weapon = "carbine", weaponAt = 2, person = "Captain Maria", pitch = "We need ammo from the docks. Bring it through the tunnel." },
	{ id = "icecream", name = "Frosty's Ice Cream", icon = "🍦", jobType = "icecream", reward = "icecream", needed = 3, person = "Frosty", pitch = "People still want ice cream. Sell it for us!" },
	{ id = "movers", name = "Big Move Movers", icon = "🚚", jobType = "moving", reward = "movingtruck", needed = 3, person = "Dana, the boss", pitch = "Families are getting out of town. Move their things." },
	{ id = "farm", name = "Old Farm", icon = "🌽", jobType = "farmrun", reward = "monster", needed = 3, person = "Old Man Jed", pitch = "The city is hungry. Take my monster truck to the markets." },
	{ id = "ranch", name = "Silver Spur Ranch", icon = "🐴", jobType = "horses", reward = "livestock", needed = 4, weapon = "revolver", weaponAt = 2, person = "Walt, the rancher", pitch = "My horses are sold to the riding school. Lead them into the truck gently, and keep the bandits off them." },
	{ id = "clinic", name = "City Clinic", icon = "🏥", jobType = "ambulance", reward = "ambulance", needed = 3, person = "Doctor Ellie", pitch = "The phones never stop ringing. Take the ambulance, bring the patients in alive." },
	{ id = "gas", name = "Gas Station", icon = "⛽", jobType = "fuelrun", reward = "fueltruck", needed = 3, person = "Dolly, the owner", pitch = "My pumps are dry. Bring fuel barrels from the harbor depot." },
} :: { EmployerDef }

-- 5.5, people in every building (shared/Residents.luau, shared/Deliveries.luau): every home has residents, made up
-- from these lists the same way every time (seeded by the home's id). An apartment building has `floors` × 4 flats
-- (A – D), FlatPeople in each; a Suburbs house HousePeople. A delivery to a home goes to one of its residents (an
-- apartment: "Apt 4C, 40 6th Ave"); a home weighs as many times as it has residents in the board's draw, at most
-- MaxWeight (a tower comes up more often than a house, but does not flood the board).
-- 6.3 (the owner: "the people's names without surnames, in English"): a resident is one English first name ("Sarah",
-- "Mike"), or now and then only a nickname (NicknameChance: "Lucky Jim", "Radio Rita"). No surnames, no Czech
-- lists any more. Women and Men hold more than 60 names each, so the biggest tower (9 floors × 4 flats × 2 people,
-- 72 at most) still has a name of its own for everybody.
Config.Residents = {
	FlatPeople = { 1, 2 } :: { number },
	HousePeople = { 1, 4 } :: { number },
	MaxWeight = 6,
	NicknameChance = 0.04,
	Women = {
		"Sarah", "Emma", "Kate", "Linda", "Megan", "Rosie", "Grace", "Holly", "Nora", "Tina", "Alice", "Amber", "Beth", "Bonnie",
		"Carol", "Chloe", "Claire", "Daisy", "Debbie", "Ellen", "Emily", "Fiona", "Gemma", "Hazel", "Heather", "Iris", "Jade", "Janet",
		"Jenny", "Jess", "Joan", "Julie", "Karen", "Laura", "Leah", "Lily", "Lisa", "Lucy", "Maggie", "Martha", "Mary", "Molly",
		"Nancy", "Olivia", "Paige", "Penny", "Polly", "Rachel", "Rebecca", "Ruby", "Sally", "Sophie", "Stella", "Susan", "Tara", "Vicky",
		"Wendy", "Zoe", "Abby", "Brenda", "Diana", "Eve", "Faye", "Ivy", "Judy", "Kelly", "Mandy", "Pam",
	} :: { string },
	Men = {
		"Mike", "Dave", "Tom", "Jack", "Sam", "Bill", "Frank", "Ray", "Eddie", "Luke", "Adam", "Alan", "Andy", "Ben",
		"Bob", "Brian", "Carl", "Chris", "Colin", "Dan", "Dean", "Doug", "Ed", "Fred", "Gary", "George", "Greg", "Harry",
		"Henry", "Ian", "Jake", "James", "Jeff", "Jim", "Joe", "John", "Josh", "Keith", "Ken", "Kevin", "Larry", "Leo",
		"Mark", "Matt", "Neil", "Nick", "Owen", "Paul", "Pete", "Phil", "Rob", "Roger", "Ryan", "Scott", "Steve", "Ted",
		"Terry", "Tim", "Tony", "Walter", "Will", "Zack", "Barry", "Craig", "Gavin", "Hugh", "Lewis", "Max",
	} :: { string },
	-- (whole names: what everybody on the block calls them)
	Nicknames = { "Old Pete", "Doc", "Granny Mae", "Sarge", "Mad Mira", "Tin-Can Tony", "Lucky Jim", "Two-Dogs Dana", "Bunker Bob", "Radio Rita" } :: { string },
}

-- 5.7, robustness and load (server/Zombies.luau, shared/Net.luau, server/Shops.luau, server/Jobs.luau, Main.server).
-- Zombies: TouchEvery = how often (seconds) the car-touch test and the targets' list run (20 Hz, not every frame:
-- a car at 120 studs/s moves 6 studs between two tests, far less than its own length plus the reach). Limits: how
-- many requests a second each remote takes from one player (a token bucket: as many in a burst, then that many a
-- second; Net.limit drops the rest, Net.latest keeps the last one and runs it once there is room again). Aiming,
-- PinOrder and RequestOffers keep the last (a state: the final one always arrives; a burst of board requests is
-- answered once); the shop actions and CancelJob drop the extra clicks.
Config.Robust = {
	Zombies = {
		TouchEvery = 0.05,
	},
	Limits = {
		RequestOffers = 2,
		PinOrder = 5,
		CancelJob = 2,
		Buy = 5,
		Equip = 6,
		Paint = 5,
		Gear = 5,
		Kit = 4,
		Aiming = 12,
		Wheelie = 8, -- 6.10: up / down on the E-Scooter (server/Wheelie.luau)
		Zip = 4, -- 6.10 review: a zip line's grab (a jump on the start platform) and letgo (server/ZipLines.luau)
		Tasks = 4, -- 6.12: the TASKS app's "open" and CLAIM (server/Tasks.luau)
	},
}

-- 6.12, the daily and weekly tasks (the owner: "daily and weekly tasks so players come back"; shared/Tasks.luau picks
-- and counts them, server/Tasks.luau keeps profile.tasks and pays, client/TasksApp.luau is the phone's TASKS app).
-- Every UTC day a courier gets Daily tasks from DailyPool, every UTC week (from Monday 00:00 UTC) one from WeeklyPool,
-- picked by the day's (the week's) number and the UserId: the same all day, new at 00:00 UTC; never two of one
-- `group` a day, only the kinds open at the courier's level when the day starts (`level`, 1 when missing).
-- A kind: `event` is what server/Tasks.luau's Tasks.note counts (deliver: pieces delivered, `look` only that cargo
-- look; ride: deliveries on a bike or a scooter; stars3: jobs finished at ★★★; perfect: PERFECT throws; zip: zip-line
-- rides; wheelie: seconds of wheelie; bus: bus trips; kill: zombies killed, `night` only after dark; tips: tip
-- money; earn: delivery pay; mission: missions finished). `text` is the title ({n} the target; `one` when it is 1),
-- `target` the range it is picked from (in `step`s; `grow`: × (1 + grow × (level − 1)) for the ones that grow with
-- you), `money` and `xp` the reward (× (1 + LevelScale × (level − 1)), the level when the day starts).
-- All the dailies done opens the AllDaily bonus (its own CLAIM). A task done and not claimed by the reset is paid then.
export type TaskDef = {
	id: string,
	event: string,
	text: string,
	one: string?,
	target: { number },
	step: number?,
	grow: number?,
	money: number,
	xp: number,
	level: number?,
	group: string?,
	look: string?,
	night: boolean?,
}

Config.Tasks = {
	Daily = 3, -- daily tasks a day
	LevelScale = 0.12, -- the rewards × (1 + this × (level − 1)): a level-10 courier's × 2.08
	AllDaily = { money = 300, xp = 150 }, -- every daily done: the bonus (× the same scale)
	BusTrip = 8, -- seconds seated at least before getting off at a stop counts as a bus trip (not the same stop)
	StateGap = 0.5, -- seconds between two states to one player (server/Tasks.luau)
	CheckEvery = 10, -- seconds between two checks of everybody for the reset at 00:00 UTC
	SaveDelay = 5, -- seconds after a CLAIM until it is saved (one save for a burst)
	DailyPool = {
		{ id = "deliver", group = "deliver", event = "deliver", text = "Deliver {n} pieces of cargo", target = { 6, 12 }, money = 150, xp = 100 },
		{ id = "pizza", group = "deliver", event = "deliver", look = "pizza", text = "Deliver {n} pizza stacks", one = "Deliver a pizza stack", target = { 2, 4 }, money = 180, xp = 110 },
		{ id = "parcel", group = "deliver", event = "deliver", look = "parcel", text = "Deliver {n} parcels", target = { 3, 5 }, money = 170, xp = 100 },
		{ id = "medicine", group = "deliver", event = "deliver", look = "medicine", text = "Deliver {n} medicine boxes", target = { 3, 5 }, money = 170, xp = 100 },
		{ id = "perfect", event = "perfect", text = "Land {n} PERFECT throws", one = "Land a PERFECT throw", target = { 2, 4 }, money = 200, xp = 120 },
		{ id = "zip", event = "zip", text = "Ride {n} zip lines", one = "Ride a zip line", target = { 1, 2 }, money = 120, xp = 80 },
		{ id = "stars3", event = "stars3", text = "Finish {n} jobs at ★★★", one = "Finish a job at ★★★", target = { 2, 3 }, money = 220, xp = 130 },
		{ id = "bus", event = "bus", text = "Take {n} bus trips", one = "Take a bus trip", target = { 1, 2 }, money = 120, xp = 80 },
		{ id = "night", event = "kill", night = true, text = "Kill {n} zombies at night", target = { 15, 25 }, step = 5, money = 200, xp = 120 },
		{ id = "tips", event = "tips", text = "Earn ${n} in tips", target = { 40, 80 }, step = 10, grow = 0.25, money = 150, xp = 100 },
		{ id = "wheelie", event = "wheelie", text = "Wheelie for {n} seconds in all", target = { 10, 20 }, step = 5, money = 150, xp = 90, level = 2 },
		{ id = "ride", event = "ride", text = "Make {n} deliveries on a bike or a scooter", one = "Make a delivery on a bike or a scooter", target = { 2, 4 }, money = 180, xp = 110, level = 2 },
		{ id = "mission", event = "mission", text = "Finish {n} missions", one = "Finish a mission", target = { 1, 2 }, money = 300, xp = 150, level = 5 },
	} :: { TaskDef },
	WeeklyPool = {
		{ id = "w_deliver", event = "deliver", text = "Deliver {n} pieces of cargo", target = { 40, 60 }, step = 5, money = 1500, xp = 600 },
		{ id = "w_earn", event = "earn", text = "Earn ${n} on deliveries", target = { 2500, 3500 }, step = 250, grow = 0.4, money = 1500, xp = 600 },
		{ id = "w_perfect", event = "perfect", text = "Land {n} PERFECT throws", target = { 15, 25 }, step = 5, money = 1500, xp = 600 },
		{ id = "w_stars3", event = "stars3", text = "Finish {n} jobs at ★★★", target = { 10, 15 }, money = 1600, xp = 650 },
		{ id = "w_kill", event = "kill", text = "Kill {n} zombies", target = { 150, 250 }, step = 25, money = 1400, xp = 550 },
		{ id = "w_tips", event = "tips", text = "Earn ${n} in tips", target = { 300, 500 }, step = 50, grow = 0.25, money = 1500, xp = 600 },
		{ id = "w_missions", event = "mission", text = "Finish {n} missions", target = { 4, 6 }, money = 2500, xp = 900, level = 5 },
	} :: { TaskDef },
}

-- 5.7, a living city and its air: the towers' four looks (shared/TowerLooks.luau), the street props on every ordinary
-- block (shared/StreetProps.luau, server/StreetDressing.luau), the night lights restyled on every client
-- (client/WorldFx.luau), the rare rain and fog (shared/WeatherPlan.luau: server/DayNight.luau picks, client/Weather.luau
-- draws) and the camera's shake and speed (client/CameraRig.luau).
Config.LivingCity = {
	Towers = {
		Budget = 10, -- parts a tower's look adds, at most
		DoorClear = 6, -- nothing of a look within this (along the wall) of an apartment entrance's door, below 12 studs
		LadderClear = 6, -- … nor of a zip line's ladder; a zip line's two towers get nothing on the roof
		RoofHeight = 3, -- a roof's tanks and units stay this low (the zip cables' rule: shared/ZipLines.luau extra)
	},
	Street = {
		Props = { 3, 6 } :: { number }, -- props a block (a Harbor block: the lower half)
		CurbDepth = 1.7, -- the kerb props' middle, in from the curb (the people walk 4.5 in: shared/TrafficLanes.luau)
		CornerClear = 15, -- no prop this close (along the side) to a block's corner: the crosswalks, the lamps and poles
		Clear = 9, -- no prop within this of a door, a pile, a cargo spot, an employer's board, an address or a dock
		ParkClear = 12, -- … of a home's or a storefront's park (a car pulls in there)
		StopClear = 24, -- … of a bus stop's kerb
		GasClear = 50, -- … of a gas station's middle
		PlaceClear = 30, -- … of a place or a house for sale
		LadderClear = 9, -- … of a zip line's ladder
		Spacing = 7, -- no two props of a block closer than this
		CarShare = 0.22, -- a block side (not on a bus line) has an abandoned car at its kerb this often
		CarCornerClear = 30, -- the car keeps this far from the corners (the traffic's turns)
		CarKerb = 2.5, -- the car's middle this far out on the road from the curb (clear of the traffic's lane)
		FlareShare = 0.5, -- an abandoned car has a red flare by it this often
		BoardedShare = 0.3, -- a tower's street wall has a boarded shopfront this often
	},
	Lights = {
		RestyleNear = 400, -- 5.9.2: when the night turns, the night lights within this of the camera are restyled first …
		RestyleNearPerFrame = 60, -- … this many a frame (no hitch)
		RestyleFarPerFrame = 40, -- … then the far ones, this many a frame
		BrokenShare = 0.07, -- the street lamps that flicker at night
		FlickerRange = 320, -- they flicker only this close to the camera
	},
	Clock = {
		SendEvery = 1, -- seconds between the clock's replications (every client runs it smoothly in between)
		Step = 0.01, -- 5.9.2: hours; a client writes Lighting.ClockTime only when it moved this much (each write re-lights)
	},
	Weather = {
		CheckEvery = 75, -- seconds between the server's rolls for a change in clear weather
		RainChance = 0.06, -- per roll, by day (× NightBoost at night)
		FogChance = 0.05,
		NightBoost = 1.8,
		Minutes = { 2.5, 6 } :: { number }, -- how long a rain or a fog lasts
		Calm = 4, -- minutes of clear weather at least after one
		Fade = 12, -- seconds a client takes to blend into or out of it
		RainDensity = 0.12, -- added to the atmosphere's density
		FogDensity = 0.32,
		WetReflectance = 0.16, -- the roads' shine in the rain
		RainRate = 900, -- raindrops a second around the camera
		MistRange = 650, -- the river's mist shows within this of the camera
		SunRays = 0.18, -- the sun rays' intensity at dawn
	},
	Camera = {
		Explosion = 0.9, -- shake (0 … 1) next to an explosion …
		ExplosionReach = 140, -- … fading to nothing this far away
		Damage = 1.6, -- × the share of your health one hit took
		Ram = 0.022, -- × the speed (studs / s) your car lost in a blink
		RamFrom = 22, -- … from a loss this big
		Decay = 1.6, -- shake lost per second
		Angle = 1.4, -- degrees at full shake
		Offset = 0.35, -- studs (a touch screen's camera moves, it does not turn)
		Fov = 6, -- extra field of view at top speed and on a zip line
		FovFrom = 0.72, -- … from this share of the car's top speed
		FovBlend = 3, -- per second
	},
}

return Config
