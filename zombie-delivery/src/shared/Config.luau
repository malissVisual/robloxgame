--!strict
-- Every number of the game in one place: the cars, the guns, the upgrades, the items, the paints, the zombies and
-- the jobs. Pure data (colours are { r, g, b }), so the logic tests can load it outside Roblox.
-- The layout of the world (districts, roads, bridges, places) is in shared/Map.luau.

local Config = {}

-- Shown on the start screen: tells which version Studio really runs (bump it with every update).
Config.Version = "8.9.6"

-- 5.0 "From the bottom": everybody starts again on foot (a new store; the v1 saves stay stored and unread, so a
-- rollback is possible). A new player has no vehicle, $40 and a medkit (server/PlayerData.luau); 6.0: no gun either
-- (fists only: the pistol is bought at Lead & Co., Config.Arms). 7.x: every courier has the ZDC Van from the start
-- (Config.CompanyVan), the only car of the game.
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
	-- 6.24: the walk's weight and the landing below are client/GaitPose.luau's gait now (Config.Gait); these numbers stay
	-- shared/BodyMotion.luau's (stride, landDrop: tests/bodymotion_test.luau).
	-- The walk (WalkFrom studs / s up to Config.Courier.Sprint.From, where the sprint's run takes over): the
	-- stock walk's own thighs give the weight: the body sinks WalkBob studs with the legs apart (Spread degrees at the
	-- widest), the arms swing WalkArm of the legs' spread more, the chest turns WalkTwist degrees against the hips.
	WalkFrom = 4,
	WalkBob = 0.09,
	WalkArm = 0.45,
	WalkTwist = 4,
	Spread = 50,
	-- The carry (client/ArmPose.luau): the hands reach the box's sides (server/Cargo.luau's CarryAt / CarrySize on the
	-- character), CarryLow of its height under its middle; the upper body leans back CarryLean degrees with both hands
	-- full, CarryHeavy when the load slows you (CarrySpeed). 8.3 (the owner: "he goes behind me with his arms stretched
	-- out"): a hand reaches CarryReach of the arm's whole length at most (shared/BodyMotion.luau capReach): a spot
	-- farther off is reached that far toward it, the elbow still bent (a natural carry, never a stretched-out arm).
	CarryLow = 0.15,
	CarryLean = 4,
	CarryHeavy = 8,
	CarryReach = 0.92,
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
	-- 9.0 Danny's pick-up and setting down ("lift", "setdown": server/MoveHelper.luau, Config.MoveHelper.Pick's times
	-- within their seconds): a shorter bend, both hands to the piece, LiftDrop studs, the hips LiftHips, the waist LiftBend
	LiftDrop = 0.45,
	LiftHips = 18,
	LiftBend = 28,
	Gestures = { pickup = 0.7, land = 0.42, lift = 1.0, setdown = 0.8 } :: { [string]: number },
}

-- 6.24, the gait (the owner: "better animations, how he walks and moves"): client/GaitPose.luau walks every courier and
-- person near the camera with shared/Gait.luau's procedural gait over the stock tracks (they stay underneath: a far body
-- shows them alone). Speeds in studs / s, angles in degrees, times in seconds; "legs" are the body's own leg, hip to sole
-- (the classic R15's 2 studs), so a kid steps in proportion.
Config.Gait = {
	Range = 150, -- studs from the camera: the bodies walked (yours always) …
	MaxPosed = 40, -- … at most this many, the nearest …
	Detail = 60, -- … the whole gait this close (ground rays, fidgets); farther it is worked out FarHz times a second
	FarHz = 15,
	Retarget = 0.4, -- seconds between the looks for whom to walk
	-- The walk. A cycle (two steps) covers StrideBase legs + StrideGain × the speed, so the steps quicken with the speed
	-- (about 1.6 cycles a second at the aim's 3.5, 2.4 at the brisk 14). A foot on the ground is planted: it goes back
	-- under the body at the body's speed (the leg reaches it: two bones), rolling from the heel onto the toe.
	StrideBase = 0.55,
	StrideGain = 0.335,
	WalkRef = 14, -- the brisk walk (Config.Movement.Walk): the swings, rolls and sways below are full here
	DutySlow = 0.62, -- the share of a cycle a foot is down, strolling …
	DutyBrisk = 0.52, -- … and at WalkRef
	Lift = 0.12, -- legs: the swinging foot's lift at WalkRef …
	LiftSlow = 0.04, -- … and strolling
	Heel = 15, -- the heel strike's toe-up at WalkRef …
	Toe = 32, -- … and the push-off's heel-up
	Reach = 0.995, -- of the leg the knee never straightens past (a soft knee)
	MaxDrop = 0.12, -- legs: the hips dip at most this much reaching for both feet (the walk's bob comes from this) …
	DipRate = 30, -- … followed at this rate (1 / s: the reach turns steeply near the leg's length, no snap)
	MoveFrom = 0.8, -- faster than this a body walks …
	StopBelow = 0.5, -- … and slower than this it settles
	StartTime = 0.14, -- seconds the stride takes to open from standing
	SettleTime = 0.3, -- seconds of the settling step (the trailing foot comes down beside the other) …
	LetGo = 0.25, -- … then back to the stock idle over this
	-- The body over the steps (at WalkRef; strolling the *Slow ones; nothing standing still).
	Sway = 0.025, -- legs the hips shift over the foot on the ground …
	SwaySlow = 0.04,
	HipRoll = 4.5, -- the free side's hip drops
	HipTurn = 6, -- the hips turn with the leg in front …
	ChestTurn = 7, -- … and the shoulders against them
	HeadKeep = 0.85, -- the neck takes back this share of the body's turns and tips: the head stays level
	WalkLean = 3, -- the upper body forward at WalkRef
	ArmSwing = 32, -- the arms forward and back against the legs …
	ArmSlow = 7,
	Elbow = 24, -- the elbows bent …
	ElbowSlow = 8,
	ElbowForward = 18, -- … more on the forward swing
	ArmOut = 5, -- the arms a little away from the body
	ArmLag = 0.04, -- of a cycle the arms come after the legs
	-- Walking any way (aiming, the body faces the crosshair): the hips turn toward where you go, at most StrafeYaw
	-- (backwards: against it, the legs walk back), the chest turns back to the front (all of it aiming, ChestFollow of it
	-- else); the feet never cross (FootGap legs from the middle at least).
	StrafeYaw = 55,
	YawRate = 9,
	ChestFollow = 0.5,
	FootGap = 0.06,
	-- The run: from RunFrom the walk turns into Config.Courier.Sprint's run cycle (shared/RunCycle.luau), all of it at
	-- the sprint's From; the run's keys sit RunPhase of a cycle after the walk's.
	RunFrom = 15,
	RunPhase = 0.08,
	-- Starting and stopping: the body leans into the speed it gains (Accel degrees per stud / s², at most LeanMax
	-- forward, LeanBack back braking) on a spring (LeanHz, LeanDamp: a small sway forward as it stops); LeanRoot of it
	-- tips the whole body about the feet, the rest bends the waist.
	Accel = 0.18,
	LeanMax = 9,
	LeanBack = 7,
	LeanHz = 2.4,
	LeanDamp = 0.5,
	LeanRoot = 0.35,
	-- Turning: the body leans into the turn about the feet, TurnLean of what the turn's pull would tip it, at most
	-- TurnMax.
	TurnLean = 0.8,
	TurnMax = 11,
	-- Slopes (a ray down every SlopeEvery seconds, within Detail): the feet land on the slope, the body leans into it
	-- (SlopeLean degrees per stud of rise a stud: uphill forward), the stride shortens SlopeStride of it.
	SlopeEvery = 0.15,
	SlopeLean = 14,
	SlopeStride = 0.3,
	-- Out of breath (your breath, client/Stamina.luau; another courier's guessed from their sprint): under TiredFrom of
	-- it the run tires (the body hunches, the head drops, the arms pump lower and across, the body wobbles). Spent
	-- (under 5 %, until half is back) the walk droops, and standing still with a hand free the courier catches the breath
	-- bent over, the hands on the knees (CatchAfter seconds after stopping, until CatchUntil of the breath is back).
	TiredFrom = 0.4,
	TiredLean = 9,
	TiredHead = 10,
	TiredArms = 0.35,
	TiredWobble = 3,
	SpentHead = 8,
	SpentArms = 0.6,
	CatchAfter = 0.35,
	CatchUntil = 0.55,
	-- The jump: up from the ground faster than JumpFrom the body springs out of a crouch (TakeoffDrop legs over
	-- TakeoffTime), tucks the knees rising, reaches for the ground falling and flails falling long (FlailAfter). A body
	-- in the air under FallAfter (a kerb's step down) is not posed.
	JumpFrom = 8,
	TakeoffDrop = 0.17,
	TakeoffTime = 0.14,
	FallAfter = 0.15,
	FlailAfter = 0.9,
	AirBlend = 0.08, -- seconds into the air pose (falling) …
	JumpBlend = 0.06, -- … and jumping
	-- The landing squashes by the height fallen: LandMin legs from LandFrom studs up to LandMax at LandFull (never more:
	-- client/Unstuck.luau sets a body hung 0.8 studs low straight), LandDown seconds down, LandUp (LandUpFull from a
	-- full fall) back up; landing on the move MoveLand of it.
	LandFrom = 1.5,
	LandFull = 30,
	LandMin = 0.05,
	LandMax = 0.28,
	LandDown = 0.07,
	LandUp = 0.22,
	LandUpFull = 0.55,
	LandLean = 16,
	MoveLand = 0.55,
	Lowest = 0.72, -- studs: the Root joint never hangs lower, whatever adds up (a squash, a crouch, the catch)
	-- Idle: after IdleAfter seconds standing still a small fidget now and then (about every FidgetEvery seconds, each
	-- body its own moment; their seconds in Fidgets), what fits the hands: a look round, a stretch, a look at the watch,
	-- the shoulders rolled, the gun checked, a peek into the bag, the load hoisted. None with Reduced Motion.
	IdleAfter = 5,
	FidgetEvery = 9,
	Fidgets = { look = 3.2, stretch = 2.8, watch = 2.2, shoulders = 2.4, checkgun = 2.4, peek = 2, hoist = 1.3 } :: { [string]: number },
	-- What the hands hold: the gun out (not aiming) is held low and ready (GunHold: the right shoulder's x, y, z, the
	-- elbow, the wrist), swinging GunSwing of a free arm; the bag in the left hand hangs out (Config.Courier.BagArm);
	-- a load in the hands widens the stance (CarryWide legs), shortens the steps (CarryStride) and sways the hips
-- CarrySway × as much (a heavy one);
	-- aiming the knees soften (AimDrop legs). Blended in and out over HoldBlend.
	GunHold = { 24, 8, 0, 62, -14 } :: { number },
	GunSwing = 0.2,
	CarryWide = 0.06,
	CarryStride = 0.85, -- … and shortens the steps
	CarrySway = 1.7,
	AimDrop = 0.03,
	HoldBlend = 0.25,
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
	VanDelay = 6, -- 7.x: seconds after her first day ends (delivered or skipped) before her text about your ZDC Van
	RetryAfter = 1.5, -- a first job gone this long without a result (a special job ended, an admin): back to "board"
	TalkQuiet = 6, -- 7.1 review: s after a Talk with her in which her Moving kiosk line waits (server/MoveGreeters.luau; her bubbles: their own time)
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
	company: boolean?, -- not for sale: an employer lent it for their jobs and gave it to you after a few of them (until 7.x)
	level: number?, -- the driver level (Config.Levels) needed to buy it
	mission: string?, -- 6.19: the mission (shared/Missions.luau id) to finish before it is sold (Career.missionLock); `level` is then that mission's level
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
	-- the bike counter (Map.Shops.bikes; 6.12.7: Dead End Motors' BIKES counter), light cargo only, no fuel, no traffic /
	-- chauffeur / car gun / paint / car upgrade tracks; it never counts as "a vehicle" for car jobs and missions
	-- (shared/Transport.luau mode "bike").
	bike: boolean?,
	-- 5.1.1: the rider stands (the E-Scooter, style "scooter": a deck, no saddle, no pedals; client/BikeRider.luau's
	-- standing pose through shared/RiderPose.luau), and a badge on its card at the BIKES counter ("⚡ ELECTRIC · STAND-UP").
	stand: boolean?,
	badge: string?,
	-- 5.4, fuel (Config.Fuel, shared/FuelMath.luau): the tank in litres and what it burns, litres per 1,000 studs driven.
	-- Every car has both; a bike has none (no fuel).
	tank: number?,
	burn: number?,
	-- 7.x, one car (Config.CompanyVan): `starter` every courier owns it from the start, never sold (the ZDC Van);
	-- `ambient` a body only the world builds (Config.AmbientCars: traffic, buses, bandits), never a player's car.
	starter: boolean?,
	ambient: boolean?,
	-- 8.0 SANDBOX: a car of the sandbox only (the ZDC Sprinter): never listed in the city, a player's car only while
	-- Config.Sandbox.On (Economy.isPlayerCar)
	sandboxOnly: boolean?,
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
-- 7.x, ONE car (the owner: "dej pryč auta, ostatní, nech ve hře jen van"): Config.Cars holds the vehicles a player can
-- have, the ZDC Van (Config.Cars[1], every courier's from the start: Config.CompanyVan) and the bikes. Every other car
-- above is history: their bodies moved to Config.AmbientCars (the traffic, the buses and the bandits still drive
-- them), a save that owned one was paid back once (Economy.carRefund). The notes above tell how they used to work.
Config.Cars = {
	-- 6.25, the ZDC Van (the owner: "connect it to the game so it drives and works"): the owner's own Blender model
	-- (design/blender-van/, server/VanMesh.luau): the company's van with a bull bar and a loaded roof rack. Until
	-- ZDCVanArt is imported in Studio it wears the fleet's panelled skin.
	-- 7.x (the owner: "dej pryč auta, ostatní, nech ve hře jen van"): the one car of the game. Every courier owns it from
	-- the start and drives it (Config.CompanyVan; `starter`: never sold, CAR and the chauffeur bring it); its paints,
	-- the car tracks, the gear and a roof gun on its rack are bought for it at Wrench Garage. (7.2 review: never paid
	-- back, bought before 7.x or not: every save owns it for free now; Economy.carRefund.)
	{
		id = "zdcvan",
		starter = true,
		gearSlots = 3,
		trolley = true,
		level = 1,
		mount = true,
		name = "ZDC Van",
		price = 0,
		style = "zdcvan",
		maxSpeed = 66,
		accel = 28,
		turn = 1.85,
		health = 560,
		capacity = 4,
		tank = 65, -- 5.4: litres (Config.Fuel)
		burn = 9, -- litres per 1,000 studs
		ramPower = 1.35,
		color = { 217, 204, 176 },
		role = "The company van: every courier drives one",
		description = "Zombie Delivery Co.'s own van, yours from day one: a bull bar in front, a roof rack with a spare wheel, a hollow cargo bay with two back doors. Room for 4 pieces (+2 light ones with the Roof Rack). 1 passenger.",
		stages = {
			{ name = "ZDC Van", price = 0, capacity = 4, adds = "" },
		},
	},
	-- 5.1, the bikes (CarDef.bike): sold at the bike counter from level 2 (6.12.7: Dead End Motors' BIKES counter), after
	-- the van (7.x: Config.Cars[1] is the ZDC Van, the one car).
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
	-- bike by the rules (light cargo, the BIKE jobs, no fuel, sold with the bikes) that you ride standing. Quick off
	-- the line and nippy; a small rack over the rear wheel and one gear slot for the basket (a handlebar bag: no
	-- panniers, no trailer, Config.Gear notOn). 5.7 (the owner: "a bit slower, so it isn't too much"): 36 at the top
	-- (44 before; the Courier Bike 38, the E-Bike 48) and two light pieces stacked on its rack (a ZDC RIDE rental keeps
	-- one: Config.Rental.Room). 6.7 (it was dearer than the Cargo Bike and held less): three light pieces (two on the
	-- rack, one on the deck at your feet) for $1,900 at level 3, below the Cargo Bike; the speed stays the owner's 32.
	-- 6.10: its turn eases off with the speed, a firm brake (Config.Scooter); you hop on (Config.Interact).
	{
		id = "escooter",
		bike = true,
		stand = true,
		badge = "⚡ ELECTRIC · STAND-UP",
		level = 3, -- (6.7: 4 → 3, beside the Cargo Bike it undercuts; listed before it, the bikes rise in level and price)
		name = "E-Scooter",
		price = 1900,
		style = "scooter",
		maxSpeed = 34, -- 6.0 (the owner: "not too fast, but a quicker start: electric"): 36 → 32, accel 26 → 42; 6.14.1: 34
		accel = 38, -- (6.14.1: 42, with the softer first push and the glide into the top speed, Config.Scooter.Pull)
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
	-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md): the ZDC Sprinter, every player's van in the sandbox (Config.Sandbox.Van):
	-- a Mercedes-Sprinter-like high-roof panel van in the company's livery that you walk into (its measures:
	-- Config.Sprinter; its look and walk-in bay: shared/SprinterLooks.luau and server/Vehicles.luau STYLES.sprinter). A
	-- bit heavier than the ZDC Van (slower, slower off the line, a wider turn), a big tank (the sandbox has no pumps).
	-- `sandboxOnly`: never sold or listed in the city (the dealer, the phone, the career road, the room advice skip it)
	-- and a player's car only while Config.Sandbox.On (Economy.isPlayerCar). No stages, upgrades, gear or roof gun.
	{
		id = "sprinter",
		sandboxOnly = true,
		level = 1,
		name = "ZDC Sprinter",
		price = 0,
		style = "sprinter",
		maxSpeed = 58,
		accel = 22,
		turn = 1.55,
		health = 720,
		capacity = 8,
		tank = 160, -- litres (Config.Fuel): about 130,000 studs at its burn × Config.Fuel.Lasts
		burn = 6,
		ramPower = 1.5,
		color = { 232, 226, 210 },
		role = "The sandbox's walk-in van",
		description = "Zombie Delivery Co.'s high-roof van: walk into its cargo bay through the back doors or the sliding side door. 1 passenger.",
	},
} :: { CarDef }

-- 7.x, the cars nobody owns any more (the owner: "dej pryč auta, ostatní, nech ve hře jen van"): every car but the ZDC
-- Van left the game for the players. Nobody buys, earns, is lent or takes out one of these: the dealer, the garages,
-- Earl, the career, the missions and the special jobs know only Config.Cars. They stay as BODIES the world still
-- builds: the traffic (server/Traffic.luau: the vans at random stages, the pickup, the box truck, the muscle car, the
-- moving truck and the bus), the city buses (server/Buses.luau), the bandits' cars, Earl's old van on his lot
-- (server/VanQuest.luau) and the fleet checks (tools/vehicle-preview). Economy.findCar still finds them (their stats,
-- stages and looks for those bodies; Config sets `ambient` on each), Economy.isPlayerCar does not. Their `price` and
-- stage prices are what they sold for before (× the 6.19 knobs): a save that owned one is paid them back once
-- (Economy.carRefund, Config.CompanyVan). The company vehicles were free (an employer's): nothing to pay back.
Config.AmbientCars = {
	{
		id = "van",
		mount = true,
		trolley = true,
		name = "Old Van",
		level = 4, -- 5.0 – 6.x: bought from Earl at Earl's Used Wheels (7.x: his lot keeps one for show, server/VanQuest.luau)
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
		level = 5, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
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
		level = 5, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
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
		level = 6, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
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
		level = 7, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
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
		level = 9, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
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
		level = 10, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
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
		level = 12, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
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
		level = 14, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
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
	-- Company vehicles (the special jobs lent them until 7.x; the traffic still drives the moving truck and the bus).
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
	mission: string?, -- 6.19: the mission (shared/Missions.luau id) to finish before it is sold (Career.missionLock); `level` is then that mission's level
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
		level = 4, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
		mission = "dispatch_2", -- 6.19: sold once you finish First Shift 2, Mail Call (Career.missionLock)
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
		level = 5, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
		mission = "dispatch_10", -- 6.19: sold once you finish the First Shift finale, Rush Hour of the Dead (Career.missionLock)
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
		level = 6, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
		mission = "clinic_10", -- 6.19: sold once you finish the Code Red finale (Career.missionLock)
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
		level = 11, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
		mission = "power_10", -- 6.19: sold once you finish the Lights Out finale (Career.missionLock)
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
		level = 13, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
		mission = "lab_10", -- 6.19: sold once you finish the Patient Zero finale, The Cure (Career.missionLock)
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
	mission: string?, -- 6.19: the mission (shared/Missions.luau id) to finish before it is sold (Career.missionLock); `level` is then that mission's level
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
		level = 11, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
		mission = "power_10", -- 6.19: sold once you finish the Lights Out finale (Career.missionLock)
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
		level = 13, -- 6.19: the level its mission is played at (the order, the fuel tier); the gate is the mission
		mission = "lab_10", -- 6.19: sold once you finish the Patient Zero finale, The Cure (Career.missionLock)
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

-- 6.16, the owner: "I want to upgrade the visuals and the feel" (shooting and hits). Everything here is the shooter's
-- own client's show (client/ShotKick.luau, client/ShotFx.luau, client/HitMarker.luau, the arms in client/ArmPose.luau;
-- the pure rules in shared/ShotFeel.luau): the server still decides every hit (server/Gun.luau).
export type ShotKickDef = {
	pitch: number, -- degrees the aiming camera kicks up a shot (at its peak; it springs back by itself)
	yaw: number, -- degrees of sideways kick at most, either way (random)
	arm: number, -- the arms' kick (the shoulders lift, the elbow bends, the hand and the gun slide back)
	casing: string?, -- "brass" | "shell": what flies out to the side (nil: nothing; a revolver keeps its brass)
	casingDelay: number?, -- seconds after the shot (a pump, a bolt, a lever)
}

Config.Shots = {
	-- Per gun (Config.Weapons and Config.CarGuns ids; anything not named kicks like Default).
	Guns = {
		pistol = { pitch = 0.9, yaw = 0.3, arm = 1, casing = "brass" },
		smg = { pitch = 0.35, yaw = 0.3, arm = 0.45, casing = "brass" },
		shotgun = { pitch = 2.6, yaw = 0.6, arm = 1.9, casing = "shell", casingDelay = 0.35 },
		rifle = { pitch = 2.1, yaw = 0.35, arm = 1.5, casing = "brass", casingDelay = 0.3 },
		minigun = { pitch = 0.18, yaw = 0.22, arm = 0.3, casing = "brass" },
		launcher = { pitch = 2.3, yaw = 0.4, arm = 2 },
		revolver = { pitch = 1.6, yaw = 0.35, arm = 1.3 },
		carbine = { pitch = 0.5, yaw = 0.3, arm = 0.6, casing = "brass" },
		reyes = { pitch = 0.55, yaw = 0.25, arm = 0.65, casing = "brass" },
		lever = { pitch = 2.1, yaw = 0.3, arm = 1.6, casing = "brass", casingDelay = 0.3 },
		goldpistol = { pitch = 1.1, yaw = 0.3, arm = 1.1, casing = "brass" },
		deadend = { pitch = 1.3, yaw = 0.3, arm = 1.2, casing = "brass" },
		roofmg = { pitch = 0.3, yaw = 0.15, arm = 0 },
		roofminigun = { pitch = 0.15, yaw = 0.12, arm = 0 },
		rooflauncher = { pitch = 1.2, yaw = 0.2, arm = 0 },
	} :: { [string]: ShotKickDef },
	Default = { pitch = 0.8, yaw = 0.3, arm = 1 } :: ShotKickDef,
	-- The camera's kick (a computer's aiming camera only: a touch screen's Roblox camera is never turned).
	KickRate = 18, -- 1/s: a critically damped spring, at its peak 1/KickRate s after the shot, settled in about 4 ×
	KickMax = 5, -- degrees: held down, the kick never piles up past this
	WindowShare = 0.6, -- a gun out of a car window kicks the camera this share (the car's camera is further back)
	ReducedMotion = 0.2, -- the kick's share with reduced motion (the player's Roblox setting); no headshot punch then
	ArmMax = 2.5, -- the arms' kick piles up to this at most (client/ArmPose.luau)
	ArmBack = 0.1, -- studs the hand (and the gun in it) slides back per unit of the arms' kick
	ArmWrist = 0.07, -- radians the wrist tips the muzzle up per unit
	-- The flash at the muzzle: a glowing ball, a small burst of flame and, near the camera and within the light budget,
	-- a real light for a blink. Everybody's on-foot shots that this client draws (their tracers), the car guns' too.
	Flash = {
		Seconds = 0.06,
		Pool = 6, -- flashes at once (a 7th takes the oldest's place)
		Lights = 3, -- real lights at once (a phone: LiteLights)
		LiteLights = 1,
		LightRange = 160, -- studs from the camera
		LightBrightness = 3,
		LightReach = 12, -- the light's Range
		Burst = 3, -- flame particles a shot
	},
	-- Shell casings: client-only parts thrown out to the gun's right, falling, bouncing on the floor under them and fading.
	Casings = {
		Max = 24, -- at once (the oldest goes first); a phone throws none (DeviceBudget.lite)
		Life = 1.5, -- seconds, the last Fade of them fading out
		Fade = 0.35,
		Range = 70, -- studs: another player's casings only this close to the camera
		Side = { 5, 8 } :: { number }, -- studs/s out to the right …
		Up = { 4, 7 } :: { number }, -- … and up
		Gravity = 110, -- studs/s² (Roblox's own is 196: a little floaty, so the eye catches them)
		Bounce = 0.35, -- the share of the fall's speed a bounce keeps
		Friction = 0.6, -- the share of the sideways speed a bounce keeps
		Spin = 25, -- radians/s at most
	},
	-- Where a round stops: sparks on metal and stone, dust on the ground, chips off wood, a dark mark on a wall that
	-- fades; on a zombie (or a bandit) a small dark-red puff, never gore.
	Impacts = {
		Range = 220, -- studs from the camera (a phone: DeviceBudget.range): other shooters' impacts farther are not drawn
		PerSecond = 40, -- other shooters' impacts drawn a second at most (a busy fight); your own always
		Burst = 12, -- … with this many at once
		Pellets = 4, -- a shotgun's shot shows at most this many impacts of its own (a phone: 2)
		Emitters = 4, -- spots that can puff in the same frame (round robin)
		Marks = 30, -- dark marks on the walls at once (a phone: LiteMarks)
		LiteMarks = 8,
		MarkSize = 0.45,
		MarkLife = 6, -- seconds, the last MarkFade of them fading
		MarkFade = 2,
		Sparks = 9, -- particles: a hit on metal …
		StoneSparks = 4, -- … on stone, concrete, brick (with Dust/2 of dust)
		Dust = 5, -- on the ground, grass, sand, wood
		Splat = 5, -- on a zombie or a bandit (a dark-red puff)
	},
	-- The hit marker: an X around the crosshair on every hit (on a touch screen, or with the mouse free, at the spot hit),
	-- white on a hit, red on a kill, gold and bigger on a headshot; a kill shows a small skull over it.
	Marker = {
		Hit = { color = { 255, 255, 255 } :: { number }, size = 1, seconds = 0.2, thick = 2 },
		Kill = { color = { 255, 64, 52 } :: { number }, size = 1.25, seconds = 0.32, thick = 3 },
		Head = { color = { 255, 196, 60 } :: { number }, size = 1.6, seconds = 0.45, thick = 3 },
		Skull = true,
		Pop = 1.4, -- the X starts this much bigger and settles in 0.08 s
		HeadPunch = 1.6, -- degrees the field of view closes for a blink on a headshot (computer)
		HeadShake = 0.12, -- a touch screen's camera: a small shake instead (CameraRig.shake)
		-- The soft tick under the hit's own sound (client/Sounds.luau): a sound of the sheet, its volume, its pitch.
		Ticks = {
			hit = { "ui_click", 0.3, 1.8 },
			kill = { "ui_click", 0.45, 1.35 },
			head = { "ding", 0.22, 2.2 },
		} :: { [string]: { any } },
		TickGap = 0.05, -- seconds: a shotgun's seven pellets tick once
	},
}

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
	bikeOnly: boolean?, -- 5.1: bike gear (basket, panniers, trailer): fits only CarDef.bike, installed at the BIKES counter
	room: number?, -- 5.1: bike gear's extra light slots
}

-- 5.0: personal gear (yours, not a car's), bought at Last Stop Supplies and kept for good (profile.kit): what you
-- carry on foot and on a bike (shared/Transport.luau). speed = walk / sprint multiplier (the best one counts; 6.12.2:
-- the Running Shoes and their 1.1 are gone, only the Heavy Armour's slow-down is left).
-- 6.7: the Thermal Jacket (warm: food cooled ×0.8) is gone (the Thermal Delivery Bag keeps food hot; Config.RetiredKit
-- pays it back once). `tips` = the share of an order's pay a piece adds as the customer's tip on every delivery (the
-- Courier Vest: shared/JobRules.luau kitTip, server/Jobs.luau payOrder). `starter` = every profile has it (the plastic
-- bag: "STARTER · yours", never sold; 6.23: no piece is a starter any more). 6.23: the bags (a piece with `extra`) are
-- not kept for good: they are bought for each game (Config.BagShop PerGame, profile.bags, never saved). `shop` = the Map.Shops id that sells it (shared/Transport.luau kitShop: else a
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
-- Its look in the hand: shared/KitArt.luau (the same id); its swing: Config.Courier.Bags[id].
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
	-- 6.7: every profile had it (newProfile, starterKit). 6.23: sold for each game like every bag (Config.BagShop
	-- PerGame), free for the game only while the tutorial is ahead (Config.BagShop.Free); its base price stays 0, so an
	-- old save is paid nothing back for it (Config.BagShop.Refund)
	{ id = "bag", name = "Plastic Bag", level = 1, price = 0, icon = "🛍️", extra = 2, description = "A thin plastic bag. Sprint with your deliveries: 2 light pieces of any kind (a bouquet, a cake too) ride in it while you hold it (2); what you pick up drops straight in." },
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
-- Map.Shops.supplies: the vests and the items; its old building on block (0, -1) is gone: 6.12.15) to the south,
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
	-- 6.23, bags for each game (the owner: "what if you always had to buy a backpack for the game"; he chose a bag
	-- bought for each game, each server session): a bag is no longer yours for good. The bags bought this game live in
	-- the server's profile only (profile.bags, never saved: server/PlayerData.luau), and so does the one in use
	-- (profile.activeBag); leaving the game loses them, a death keeps them. After you join your hands carry alone until
	-- you buy one here (the bottom bar's bag slot says BUY A BAG: a tap sets the GPS here).
	--   PerGame   each bag's price for one game ($): set over Config.Kit's price after the 6.19 pass (no Kit knob on a
	--             bag); a small share of one game's pay (a foot job pays ~$60 - $150)
	--   Free      the bag a courier gets for free for the game while the tutorial is ahead (profile.tutorial false: a
	--             brand-new courier's first game, a Studio test), so the first job and its tour stop "2 your bag" work
	--   Refund    filled by the 6.19 pass below: each bag's price for good before 6.23 (its base price × the Kit knob),
	--             what an old save is paid back once for each bag it owned (shared/Transport.luau bagRefund)
	--   Flag      the save's mark that its bags were paid back (only real saves; every save is written with it)
	--   Refunded  the notice ({money}), NoBag the one-time hint on your first foot run of a game without a bag, BuyHint
	--             the bottom bar's bag slot line without a bag, Pill its pill, ForGame a bag's price label
	PerGame = { bag = 20, tote = 60, thermal = 120, padded = 200, duffel = 350 } :: { [string]: number },
	Free = "bag",
	Refund = {} :: { [string]: number },
	Flag = "perGameBags",
	Refunded = "Bags are now bought for each game: {money} refunded for your bags.",
	NoBag = "No bag this game: buy one at ZDC Bags (by the spawn).",
	BuyHint = "BUY A BAG",
	Pill = "BUY",
	ForGame = "FOR THIS GAME",
}

-- 5.0 – 6.x, Earl's van: the first vehicle was bought second-hand from Earl at Earl's Used Wheels (Map.VanSeller, far
-- out on the West Highway) after Marge's text at level 4. 7.x (one car, Config.CompanyVan): retired. Every courier has
-- the ZDC Van from the start, so Earl sells nothing any more: his lot (built by server/World.luau) keeps his old van for
-- show with a SOLD tag (server/VanQuest.luau), his prompt is a chat (Prompt: shared/VanQuest.luau promptText) and he
-- says one of his Lines. Sign: what follows "FOR SALE" on his lot's plate (VanQuest.priceText); Tag: the old van's tag.
Config.VanQuest = {
	Seller = "Earl",
	Place = "Earl's Used Wheels",
	Prompt = "Talk",
	Sign = "· SOLD",
	Tag = "SOLD · Earl's own, not for sale",
	Lines = {
		"Sold my last van years ago, kid. Your company hands every courier a ZDC Van now.",
		"She ain't for sale. Thirty years on the road: she's earned her rest.",
		"Treat that ZDC Van right, kid. They don't build 'em like my old girl any more.",
	} :: { string },
}

-- 7.x, one car (the owner: "dej pryč auta, ostatní, nech ve hře jen van": take the other cars away, leave only the
-- van): the ZDC Van (Config.Cars[1], the owner's Blender model) is the only car of the game. Every courier owns it from
-- the start (server/PlayerData.luau: a new profile and every save on load) and drives it: CAR and the chauffeur bring
-- it, it is never sold. Earl's quest is retired (Config.VanQuest); Dead End Motors' CARS counter shows the van (its
-- paints, upgrades, gear and roof guns are Wrench Garage's); the special jobs and the missions all go in it (no company
-- vehicle is lent any more), and no job or mission carries more pieces than its four slots.
--   Car       the van's Config.Cars id
--   Flag      the save's mark that its other cars were paid back (only a real save without it, once; every save is
--             written with it)
--   Refunded  Marge's text and the notice ({money}) after a save got money back for the cars it owned
--             (Economy.carRefund: each car's price as sold, Config.AmbientCars × the Vehicles knob, and the stages it
--             had bought, × the Stages knob; nothing for an employer's free vehicle; 7.2 review: never the ZDC Van, the
--             Old Van's price only when bought from Earl). The van takes over the best of the old cars (Economy.vanCarry:
--             every car track at its highest level, their gear, the paint and the roof gun of the car you drove); 7.2
--             review: what it could not take over is paid back too (VanCarry.lost), and so is the bonus of an employer
--             whose vehicle the save had earned (Economy.employerBonus)
--   Kept      her text when cars went but nothing was paid (only an employer's free ones)
--             (the money's reason: "CarRefund", shared/AnalyticsPlan.luau)
--   Bonus     an employer's thanks after `needed` jobs (Config.Employers bonus: the money that replaced their car;
--             server/Jobs.luau): {employer}, {money} (the money's reason: "EmployerBonus")
--   MissionsNeed  a mission's refusal (and the MISSIONS window's line) while your van is not what you drive
--   Hello     Marge's text when her first day ends ({level}: the ★ car jobs'; server/Tutorial.luau): the van waited while
--             she showed you the job on foot (Main's PLAY puts it out only once her first day is behind you)
Config.CompanyVan = {
	Car = "zdcvan",
	Flag = "vanOnly",
	Refunded = "The company runs on one car now: your ZDC Van. {money} paid back for your other cars, and the van took over their best upgrades.",
	Kept = "The company runs on one car now: your ZDC Van. It took over the best upgrades of your other cars.",
	Bonus = "{employer} pays you a {money} bonus for your work!",
	Hello = "One more thing: the company's ZDC Van is yours. Press CAR and it comes to you. The ★ car jobs open at level {level}.",
	MissionsNeed = "Missions need your ZDC Van: press CAR and it comes to you.",
}

-- 5.1, the bikes (Config.Cars with bike = true) and the bike gear (Config.Gear bikeOnly), sold at Spoke & Chain Cycles
-- on Downtown block (-1, 1) until 6.12.7. A bike needs no garage slot and comes to you at once (MY BIKE); you may own
-- bikes and cars: profile.car is the one CAR / MY BIKE brings, profile.bike your bike of choice, profile.lastCar the car
-- CALL CAR brings back (server/Shops.luau). At Career.BIKE_LEVEL Marge texts you about the bikes (server/Tutorial.luau,
-- the Tutorial remote's "message" with the GPS to the BIKES counter): Unlock ({price}: the cheapest bike's).
-- 6.12.7 (the owner: "I wanted to merge the bike shop with Motors, so it's one shop"): one shop, Dead End Motors on
-- 6th Ave, with two counters at the back of its showroom (World buildDealer), like the gear stall at the spawn: CARS
-- (Sal, shop id "dealer", the car catalog) and BIKES (Kip, shop id "bikes": the bikes, the E-Scooter, the bike gear and
-- Kip's bike paint), the bikes on their stands behind the front glass. Spoke & Chain's old building on block (-1, 1) is
-- an ordinary one now (Map.FormerBikeShop). Where it all stands, in Dead End Motors' own frame (x across the showroom,
-- + toward its north end; z from the building's middle, - toward the front glass and the door, + toward the back wall):
--   Building  the showroom, Width × Depth × Height, its middle Back studs east of its block's middle (Map.Shops.dealer);
--             its front, the glass and the door, to the west (the park)
--   Cars      the CARS counter: its middle (X, Z) and Width (where World's counter() puts it: 8 in from the back wall)
--   Desk      the BIKES counter beside it, to the north: its middle (X, Z), Width and Deep (Map.Shops.bikes is its
--             front, the customers' side)
--   Stands    the bike stands (World.BikeSlots: server/Shops.luau puts a bike and its "Look" prompt on each, in
--             Config.Cars' order): their X in one row at Z, turned Turn degrees toward the door
--   Radius    studs from the BIKES counter's front the bikes count as "here" (the counter's BUY, the server's check, Kip's
--             paint): the counter and every stand with room round it, most of the showroom (Dead End Motors' own
--             "here" is its whole block, Map.ShopRadius)
Config.BikeShop = {
	Shop = "Dead End Motors",
	Counter = "the BIKES counter",
	Street = "6th Ave",
	Unlock = "You've got legs, now get wheels — Dead End Motors on 6th Ave sells bikes too: a rusty bike for {price} at the BIKES counter. I put it on your GPS.",
	Reminder = "Dead End Motors on 6th Ave still has bikes for you at the BIKES counter. More room and way faster than walking. It's on your GPS.",
	Bought = "Nice wheels. The BIKE runs on the board are yours now. A basket holds more.",
	MissionsNeed = "Missions need your car (a bike won't do): CALL CAR on your phone.",
	Building = { Width = 84, Depth = 52, Height = 18, Back = 22 },
	Cars = { X = 0, Z = 18, Width = 16 },
	Desk = { X = 17.5, Z = 18, Width = 11, Deep = 3 },
	Stands = { X = { 12.5, 18.75, 25, 31.25, 37.5 } :: { number }, Z = -14, Turn = 30 },
	Radius = 44,
}

-- 6.12.14, Lead & Co.'s shooting range (the owner: "move the gun store out of the safe zone, to a shooting range: a
-- different, smaller shop; keep the props, but make the shop smaller, like the shop at a shooting range";
-- server/GunRange.luau builds it, Map.GunRange, Map.Shops.guns). It fills Downtown block (-2, 1), south-west of the
-- park, just outside the safe zone (its gate 8 studs past the line, across 4th Ave from Spoke & Chain's old building):
-- once an ordinary block (Map.FormerBlocks: its dice still roll, nothing else in the city moved; its three apartment
-- buildings and its car park are gone). Lead & Co.'s old building on block (-1, 0) is an ordinary one now
-- (Map.FormerGunShop). The shop id ("guns"), its name ("Lead & Co."), Ray and everything it sells are as before.
-- Where it all stands, in the range's own frame (its origin the block's middle on the walk, -Z its Facing: the front
-- with the gate, east to 4th Ave and the park; +X to the right looking out of the gate, south; Map.gunRangeAt turns a
-- spot of it into the map's x, z):
--   Fence     the chain-link square round it, Fence studs from its middle each way (10 in from the curb: the people's
--             walk lines and their detours stay clear), FenceHeight tall
--   Gate      the opening in the front fence: its middle (X) and Width (cars drive in too)
--   Cabin     the range shop, Width × Depth × Height (to its roof slab), its middle (X, Z); its door to the front
--   Counter   in the cabin's own frame (z from its middle, + toward its back wall): the counter's middle Z, Width and
--             Deep; Ray behind it (server/ShopClerks.luau), the shop's "Shop" prompt on it, Map.Shops.guns its front
--   Lanes     four lanes side by side: their middles (X), each Width wide, running from the firing line (Line, the
--             benches' front edge under the pavilion) back toward the berm; a target on a stand in every lane at each
--             of Targets studs downrange, Plates its plate (width, height) at that distance
--   Berm      the sand bank behind the farthest targets: from Z, Depth deep, Height tall
--   Radius    studs from the counter's front that count as "at the shop" (the window's BUY, the server's check): the
--             cabin, its forecourt and the gate
--   Down      seconds a target stays down after a hit (server/GunRange.luau GunRange.shot: the server's own ray hits
--             it, server/Gun.luau); then it springs back up
--   Board     the cabin's name board (a second line after the double space)
--   Shop      where a gun on the career road is sold ("SMG at Lead & Co.'s range", shared/Career.luau)
Config.GunRange = {
	Block = { -2, 1 } :: { number },
	Facing = { 1, 0 } :: { number },
	Fence = 45,
	FenceHeight = 7,
	Gate = { X = -7.5, Width = 15 },
	Cabin = { X = -28, Z = -23, Width = 22, Depth = 14, Height = 10 },
	Counter = { Z = 1.2, Width = 14, Deep = 2.4 },
	Lanes = { X = { 14, 22, 30, 38 } :: { number }, Width = 8, Line = -38, Targets = { 25, 50, 75 } :: { number } },
	Plates = { { 2.2, 3 }, { 2.6, 3.5 }, { 3, 4 } } :: { { number } },
	Berm = { Z = 38, Depth = 7, Height = 9 },
	Radius = 40,
	Down = 4,
	Board = "LEAD & CO. · RANGE  GUNS · AMMO · LANES",
	Shop = "Lead & Co.'s range",
}

Config.Gear = {
	{ id = "trolley", name = "Hand Trolley", level = 3, price = 600, icon = "🛒", needs = "trolley", description = "Heavy cargo by hand at a normal pace: up to 4 pieces at once (not people, horses or pallets). Folds inside the back: vans and trucks only." },
	{ id = "straps", name = "Ratchet Straps", level = 4, price = 900, icon = "🔗", description = "The load is strapped down: cargo condition losses from bumps and damage ×0.6. Cars only." },
	{ id = "cooler", name = "Cooler Box", level = 5, price = 1400, icon = "🧊", description = "Food in the car stays fresh twice as long (freshness drains ×0.5). Cars only." },
	{ id = "roofrack", name = "Roof Rack", level = 7, price = 2500, icon = "🧳", notOn = { "muscle", "pickup" }, description = "+2 cargo slots on the roof for light pieces only (pizza, parcels, mail, bread, medicine …). Not on the Muscle Car or the Pickup." }, -- 6.7: +1 → +2
	-- 5.1, bike gear (bikeOnly: only on a bike, CarDef.bike; the car gear never goes on one), sold and fitted at the bike
	-- counter (Map.Shops.bikes; 6.12.7: Dead End Motors' BIKES counter) for the bike you ride: `room` more light pieces
	-- (Economy.capacity, Transport mode "bike").
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
-- MaxJump studs (a teleport, a tow, a rebuild). A full tank lasts about 3 – 5 jobs of the tier the car opens at (6.12.7: × Lasts, 15 – 25)
-- (FuelMath.jobsPerTank, tests/fuel_test.luau). Below Low (a share of the tank) the gauge turns red and a toast says LOW
-- FUEL; empty, the car crawls at CrawlSpeed at most (client/Drive.luau) to a pump, or the phone's TOW brings it to the
-- nearest station's pump with TowLitres for TowPrice (only with an empty tank). The gas stations (Map.GasStations) sell
-- fuel at PricePerLitre: the pump's Refuel prompt (hold PumpHold s, on foot, your car parked within PumpReach studs of the
-- pump) pours PourRate litres a second, charged as it pours, until the tank is full, the money runs out or you stop it.
-- The jerry can (Config.Items "jerrycan") pours CanLitres next to your car. Your own cars' levels are saved
-- (profile.carFuel); a new car comes full, a company vehicle a job lends you comes full and is not saved.
Config.Fuel = {
	-- 6.12.7 (the owner: "make the fuel last really long"): a tank goes this many times as far as the 5.4 balance
	-- (shared/FuelMath.luau burn and range: CarDef.burn ÷ Lasts): about 15 – 25 jobs a tank instead of 3 – 5
	Lasts = 5,
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

-- 6.12: cosmetics (the owner: "something to spend the game's money on, looks only, no advantage"). Looked at, tried,
-- worn and taken off in the phone's STYLE app (client/StyleApp.luau, client/StylePreview.luau). The clerks (the owner:
-- "things are bought only from the NPCs in the shops, for the vibe"): bought only at a shop that sells the slot (a
-- slot's `shops`; Counters, their clerks). The server decides every purchase and puts the looks on
-- (server/StyleWear.luau; the Style remote, Config.Robust.Limits.Style). No numbers of the game change: a cosmetic has
-- no stats. profile.style = { owned = { id → true }, worn = { slot → id } } (shared/Style.luau: the rules;
-- server/PlayerData.luau saves it). The geometry is shared/StyleLooks.luau's, built by
-- shared/StyleBuild.luau: welded, massless, non-colliding, never hit by rays.
--   look     a hat or a jacket of StyleLooks (built on the courier's classic R15 body, fitted to its real parts), "dye"
--            (the Courier Vest's or the bag's colour, through KitWear's tint hook), "wrap" (a colour over the car's paint
--            job), "bikepaint" (a bike's or the E-Scooter's frame), a decal of StyleLooks (stripes, flames, logo, checker,
--            pinstripe: thin parts laid on the body's painted panels, round its lamps, racks, labels and doors)
--   color    the main colour (RGB); trim the second one (a cuff, a band, a stripe, the flames' core)
--   material an Enum.Material name for the main colour (default: Fabric on the courier, SmoothPlastic on a vehicle)
--   level    sold from this driver level (default 1)
--   reward   never sold: given later by tasks, events or passes (StyleWear.give); the app shows it as a reward
-- Prices against the economy: a walk pays $60 – 110, a bike run $100 – 250, a level's reward $500 – 15,000; the kit
-- costs $120 – 1,500 and Wrench Garage's paints $300 – 3,000. So the courier's looks start at a delivery or two and the
-- vehicles' wraps and decals sit with the garage's paints (tests/style_test.luau keeps them there).
export type CosmeticDef = {
	id: string,
	name: string,
	slot: string,
	look: string,
	price: number,
	color: { number },
	trim: { number }?,
	material: string?,
	level: number?,
	reward: string?,
	description: string,
}
-- The clerks: a slot's `shops`, the Map.Shops ids that sell it (the first one with a counter: where the app sends you).
export type CosmeticSlot = { id: string, tab: string, name: string, note: string, shops: { string } }
-- The clerks: a counter that sells looks (Config.Cosmetics.Counters): its clerk (server/ShopClerks.luau's person, the
-- same name), the place in a sentence ("Wrench Garage"), the STYLE tab their "Style" prompt opens, the prompt's line.
export type CosmeticCounter = { clerk: string, place: string, tab: string, pitch: string }

Config.Cosmetics = {
	-- The slots, one item worn in each, in the app's order; `tab` is the app's tab ("courier" | "vehicle"); `shops`, who
	-- sells it: the courier's looks at the gear stall (Dot's GEAR counter, and Nell's BAGS beside it), the wraps and
	-- decals at Wrench Garage (Gus), the bike paint at Dead End Motors' BIKES counter (Kip; 6.12.7: Spoke & Chain before)
	-- and at Wrench Garage.
	Slots = {
		{ id = "hat", tab = "courier", name = "Hats", shops = { "supplies", "bags" }, note = "Your own hats and hair hide under it while you wear it." },
		{ id = "jacket", tab = "courier", name = "Jackets", shops = { "supplies", "bags" }, note = "Over your own clothes; the vest and the bag go on top." },
		{ id = "vest", tab = "courier", name = "Courier Vest colour", shops = { "supplies", "bags" }, note = "Shows on the Courier Vest (Last Stop Supplies) while no Kevlar or heavy vest covers it." },
		{ id = "bag", tab = "courier", name = "Bag colour", shops = { "supplies", "bags" }, note = "The bag in your hand, whichever bag it is." },
		{ id = "wrap", tab = "vehicle", name = "Wraps · cars, vans, trucks", shops = { "mechanic" }, note = "A colour wrap over the paint job of every car you own. TAKE OFF shows the paint again." },
		{ id = "bikepaint", tab = "vehicle", name = "Paint · bikes and the E-Scooter", shops = { "bikes", "mechanic" }, note = "The frame of every bike you own and of the E-Scooter." },
		{ id = "decal", tab = "vehicle", name = "Decals · cars, vans, trucks", shops = { "mechanic" }, note = "On every car you own, around its lamps, racks, labels and doors." },
	} :: { CosmeticSlot },
	-- The shops whose clerk sells looks (Map.Shops ids): server/ShopClerks.luau gives the clerk a "Style" prompt beside
	-- "Shop" (`pitch` after their name) that opens the phone's STYLE on `tab`. Nell at ZDC Bags, next to Dot, sells the
	-- courier's looks too (the slots' shops) but has no prompt of her own.
	Counters = {
		supplies = { clerk = "Dot", place = "the gear stall", tab = "courier", pitch = "Looks for you" },
		mechanic = { clerk = "Gus", place = "Wrench Garage", tab = "vehicle", pitch = "Looks for your rides" },
		bikes = { clerk = "Kip", place = "Dead End Motors", tab = "vehicle", pitch = "Paint for your bikes" }, -- (6.12.7: its BIKES counter)
	} :: { [string]: CosmeticCounter },
	Items = {
		-- Hats (StyleLooks.hat: fitted to the head; the player's own hat and hair accessories hide under it)
		{ id = "cap_red", name = "Backwards Cap · ZDC Red", slot = "hat", look = "cap", price = 120, color = { 196, 40, 38 }, trim = { 28, 31, 34 }, description = "The dispatcher's favourite, worn the courier way." },
		{ id = "cap_black", name = "Backwards Cap · Black", slot = "hat", look = "cap", price = 120, color = { 32, 34, 38 }, trim = { 196, 40, 38 }, description = "A black cap with a red snap, peak to the back." },
		{ id = "beanie_orange", name = "Beanie · Safety Orange", slot = "hat", look = "beanie", price = 150, color = { 245, 120, 30 }, trim = { 214, 92, 22 }, description = "A knitted beanie with a pom-pom. Seen from three blocks away." },
		{ id = "beanie_grey", name = "Beanie · Heather Grey", slot = "hat", look = "beanie", price = 150, color = { 150, 152, 156 }, trim = { 196, 40, 38 }, description = "A grey beanie with a red cuff." },
		{ id = "hardhat", name = "Hard Hat", slot = "hat", look = "hardhat", price = 300, color = { 246, 196, 36 }, trim = { 40, 40, 44 }, description = "A site helmet with a ridge and a peak. Looks only: it stops no bites." },
		{ id = "helmet", name = "Bike Helmet", slot = "hat", look = "helmet", price = 380, color = { 40, 110, 210 }, trim = { 235, 236, 232 }, description = "A vented cycling helmet with a visor." },
		{ id = "cowboy", name = "Cowboy Hat", slot = "hat", look = "cowboy", price = 450, level = 4, color = { 122, 82, 50 }, trim = { 40, 30, 24 }, description = "A wide brim and a creased crown, for the long roads out west." },
		{ id = "cap_gold", name = "Golden Cap", slot = "hat", look = "cap", price = 0, reward = "event", color = { 226, 178, 52 }, trim = { 120, 84, 20 }, material = "Metal", description = "Not for sale: a reward of a later event." },
		{ id = "helmet_chrome", name = "Chrome Helmet", slot = "hat", look = "helmet", price = 0, reward = "pass", color = { 205, 210, 216 }, trim = { 30, 30, 34 }, material = "Foil", description = "Not for sale: a reward of a later pass." },
		-- Jackets (StyleLooks.jacket: thin shells over the torso and the arms, under the vest and the bag)
		{ id = "hoodie_grey", name = "Hoodie · Grey", slot = "jacket", look = "hoodie", price = 350, color = { 118, 122, 128 }, trim = { 196, 40, 38 }, description = "A grey hoodie: a hood, a kangaroo pocket, red cuffs." },
		{ id = "hoodie_red", name = "Hoodie · ZDC Red", slot = "jacket", look = "hoodie", price = 350, color = { 176, 36, 34 }, trim = { 30, 32, 36 }, description = "The company's red hoodie with black cuffs." },
		{ id = "track_blue", name = "Track Jacket", slot = "jacket", look = "track", price = 500, color = { 36, 74, 160 }, trim = { 236, 236, 232 }, description = "Blue, with two white stripes down each sleeve." },
		{ id = "bomber_olive", name = "Bomber Jacket", slot = "jacket", look = "bomber", price = 650, level = 3, color = { 88, 98, 62 }, trim = { 214, 110, 40 }, description = "An olive bomber with ribbed orange cuffs and a sleeve pocket." },
		{ id = "puffer_yellow", name = "Puffer Jacket", slot = "jacket", look = "puffer", price = 800, level = 4, color = { 238, 190, 40 }, trim = { 60, 60, 64 }, material = "SmoothPlastic", description = "A quilted puffer for the cold night shifts." },
		{ id = "leather_black", name = "Leather Jacket", slot = "jacket", look = "leather", price = 1200, level = 6, color = { 34, 34, 36 }, trim = { 170, 172, 176 }, material = "Leather", description = "A biker's jacket: lapels, a slanted zip, a belt." },
		{ id = "hoodie_night", name = "Night Shift Hoodie", slot = "jacket", look = "hoodie", price = 0, reward = "tasks", color = { 24, 26, 30 }, trim = { 200, 236, 80 }, description = "Not for sale: a reward of the daily tasks later." },
		-- The Courier Vest's colour (dye: the vest's cloth; its reflective bands stay)
		{ id = "vest_orange", name = "Safety Orange", slot = "vest", look = "dye", price = 100, color = { 245, 118, 26 }, description = "The road crew's orange." },
		{ id = "vest_lime", name = "Hi-Vis Lime", slot = "vest", look = "dye", price = 100, color = { 196, 232, 40 }, description = "The brightest thing in a dead city." },
		{ id = "vest_blue", name = "Courier Blue", slot = "vest", look = "dye", price = 150, color = { 40, 98, 196 }, description = "A calm blue vest." },
		{ id = "vest_pink", name = "Hot Pink", slot = "vest", look = "dye", price = 200, color = { 236, 72, 150 }, description = "Nobody misses this courier." },
		{ id = "vest_black", name = "Stealth Black", slot = "vest", look = "dye", price = 250, color = { 34, 36, 40 }, description = "Black cloth, the silver bands still shine." },
		{ id = "vest_gold", name = "Gold Vest", slot = "vest", look = "dye", price = 0, reward = "event", color = { 222, 176, 48 }, material = "Metal", description = "Not for sale: a reward of a later event." },
		-- The bag's colour (dye: the active bag's body)
		{ id = "bag_black", name = "Midnight Black", slot = "bag", look = "dye", price = 80, color = { 30, 32, 36 }, description = "Every bag you hold in black." },
		{ id = "bag_sky", name = "Sky Blue", slot = "bag", look = "dye", price = 100, color = { 90, 170, 230 }, description = "Every bag you hold in sky blue." },
		{ id = "bag_mint", name = "Mint", slot = "bag", look = "dye", price = 100, color = { 120, 210, 170 }, description = "Every bag you hold in mint." },
		{ id = "bag_purple", name = "Royal Purple", slot = "bag", look = "dye", price = 150, color = { 110, 60, 170 }, description = "Every bag you hold in purple." },
		{ id = "bag_yellow", name = "Hi-Vis Yellow", slot = "bag", look = "dye", price = 150, color = { 240, 214, 40 }, description = "Every bag you hold in hi-vis yellow." },
		{ id = "bag_gold", name = "Gold Bag", slot = "bag", look = "dye", price = 0, reward = "pass", color = { 222, 176, 48 }, material = "Metal", description = "Not for sale: a reward of a later pass." },
		-- Wraps for the cars, vans and trucks (over Wrench Garage's paint job while worn)
		{ id = "wrap_sand", name = "Desert Sand", slot = "wrap", look = "wrap", price = 800, color = { 196, 170, 120 }, description = "A dusty sand wrap." },
		{ id = "wrap_teal", name = "Satin Teal", slot = "wrap", look = "wrap", price = 900, color = { 32, 150, 150 }, description = "A satin teal wrap." },
		{ id = "wrap_orange", name = "Sunset Orange", slot = "wrap", look = "wrap", price = 900, color = { 240, 110, 40 }, description = "A sunset orange wrap." },
		{ id = "wrap_ice", name = "Ice Blue", slot = "wrap", look = "wrap", price = 900, color = { 150, 200, 236 }, description = "A pale ice-blue wrap." },
		{ id = "wrap_red", name = "ZDC Courier Red", slot = "wrap", look = "wrap", price = 1000, color = { 190, 36, 34 }, description = "The company's red, on every car of yours." },
		{ id = "wrap_green", name = "Racing Green", slot = "wrap", look = "wrap", price = 1100, color = { 22, 92, 56 }, description = "A deep racing green." },
		{ id = "wrap_matte", name = "Matte Black", slot = "wrap", look = "wrap", price = 1200, color = { 30, 31, 34 }, material = "Plastic", description = "A flat, matte black." },
		{ id = "wrap_purple", name = "Candy Purple", slot = "wrap", look = "wrap", price = 1500, level = 6, color = { 130, 40, 170 }, material = "Metal", description = "A metallic candy purple." },
		{ id = "wrap_chrome", name = "Mirror Chrome", slot = "wrap", look = "wrap", price = 0, reward = "pass", color = { 200, 206, 212 }, material = "Foil", description = "Not for sale: a reward of a later pass." },
		-- Paint for the bikes and the E-Scooter (their frames)
		{ id = "bike_mint", name = "Mint Frame", slot = "bikepaint", look = "bikepaint", price = 150, color = { 120, 210, 170 }, description = "Every bike's frame and the E-Scooter in mint." },
		{ id = "bike_sky", name = "Sky Blue Frame", slot = "bikepaint", look = "bikepaint", price = 150, color = { 90, 170, 230 }, description = "Every bike's frame and the E-Scooter in sky blue." },
		{ id = "bike_yellow", name = "Sunflower Frame", slot = "bikepaint", look = "bikepaint", price = 200, color = { 244, 200, 40 }, description = "Every bike's frame and the E-Scooter in yellow." },
		{ id = "bike_pink", name = "Bubblegum Frame", slot = "bikepaint", look = "bikepaint", price = 200, color = { 240, 120, 180 }, description = "Every bike's frame and the E-Scooter in pink." },
		{ id = "bike_black", name = "Matte Black Frame", slot = "bikepaint", look = "bikepaint", price = 250, color = { 32, 33, 36 }, material = "Plastic", description = "Every bike's frame and the E-Scooter in matte black." },
		{ id = "bike_white", name = "Pearl White Frame", slot = "bikepaint", look = "bikepaint", price = 250, color = { 236, 236, 230 }, description = "Every bike's frame and the E-Scooter in pearl white." },
		{ id = "bike_gold", name = "Gold Frame", slot = "bikepaint", look = "bikepaint", price = 0, reward = "event", color = { 222, 176, 48 }, material = "Metal", description = "Not for sale: a reward of a later event." },
		-- Decals for the cars, vans and trucks (StyleLooks.decals)
		{ id = "logo", name = "ZDC Logo", slot = "decal", look = "logo", price = 500, color = { 236, 236, 232 }, trim = { 196, 40, 38 }, description = "The company's roundel on both sides." },
		{ id = "stripes_white", name = "Racing Stripes · White", slot = "decal", look = "stripes", price = 900, color = { 236, 236, 232 }, description = "Two white stripes over the hood and the roof." },
		{ id = "stripes_black", name = "Racing Stripes · Black", slot = "decal", look = "stripes", price = 900, color = { 26, 27, 30 }, description = "Two black stripes over the hood and the roof." },
		{ id = "checker", name = "Checker Band", slot = "decal", look = "checker", price = 1200, level = 5, color = { 236, 236, 232 }, trim = { 24, 24, 26 }, description = "A black and white checker band down both sides." },
		{ id = "flames", name = "Hot Rod Flames", slot = "decal", look = "flames", price = 1600, level = 5, color = { 240, 96, 24 }, trim = { 255, 206, 60 }, description = "Orange flames off the hood and down the sides." },
		{ id = "flames_blue", name = "Blue Flames", slot = "decal", look = "flames", price = 1800, level = 7, color = { 40, 110, 230 }, trim = { 150, 220, 255 }, description = "Blue flames off the hood and down the sides." },
		{ id = "pinstripe_gold", name = "Gold Pinstripes", slot = "decal", look = "pinstripe", price = 0, reward = "tasks", color = { 222, 176, 48 }, description = "Not for sale: a reward of the daily tasks later." },
	} :: { CosmeticDef },
	-- How the looks sit (studs; shared/StyleLooks.luau, shared/StyleBuild.luau).
	Fit = {
		Shell = 0.02, -- a jacket's shell over a body part, each side (under the Courier Vest's cloth, 0.07, and a bag's strap)
		Head = 1.2, -- the classic R15 head every way: the hats are drawn on it, then scaled to the real head
		HeadMin = 0.6, -- … by at least / at most this (an odd head: still on it, not absurd)
		HeadMax = 1.6,
		Lift = 0.008, -- a decal's gap over the panel it lies on
		Thick = 0.03, -- a decal's thickness
		Margin = 0.05, -- a decal keeps this far from a lamp, a rack, a label, a door
		MinRun = 0.6, -- a stripe's piece shorter than this between two obstacles is left out
		Budget = 56, -- parts one decal adds to a vehicle at most
		Checker = 0.3, -- the checker band's square
	},
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
	-- 6.24, the special zombies (server/Zombies.luau; the rules shared/ZombieKinds.luau; see Config.ZombieTypes):
	xp: number?, -- XP for the kill, on top of everything else (the kill reward is `reward`, "KillReward")
	noLatch: boolean?, -- too big to hang on a car: it hits it from the ground
	carDamage: number?, -- a blow on a car from the ground (else `damage`) …
	carBump: number?, -- … and the car keeps this share of its speed (the Bump remote)
	lunge: LungeDef?, -- the runner's leap at a player on foot
	shove: ShoveDef?, -- its bite throws a player on foot back
	armour: ArmourDef?, -- the brute's plates: less damage from the front and from small guns
	blast: BlastDef?, -- the bloater: it blows up (when killed, or once it reaches you)
}

-- 6.24: the runner's leap. Within range[1] … range[2] studs of a player on foot, on the ground, every `every` s (± 15 %)
-- it leaps at them: pushed `speed` studs / s forward and `up` up for `push` s (a LinearVelocity on its root: its walk
-- cannot cancel it), then it flies on and lands; within `reach` studs of them during the `time` s of the leap its
-- strike lands once (`damage`, through the vest: server/Armour.luau).
export type LungeDef = { range: { number }, every: number, speed: number, up: number, push: number, time: number, damage: number, reach: number }
-- 6.24: a bite that throws the player back: `speed` studs / s away, `up` up (the Knock remote: the client pushes its own
-- body for Config.ZombieTypes.KnockTime s), at most every `every` s a zombie.
export type ShoveDef = { speed: number, up: number, every: number }
-- 6.24: armour plates (shared/ZombieKinds.luau armourShare). A hit within `angle` degrees of where it faces takes
-- `front` of the damage; a small gun's round (at most `smallDamage` a pellet, fewer than `pellets` pellets) `small`
-- (both: multiplied); never less than `least`. Full damage always: a headshot, a blast, a car, a fire, a shotgun.
export type ArmourDef = { front: number, angle: number, small: number, smallDamage: number, least: number, pellets: number }
-- 6.24: a blast (shared/ZombieKinds.luau blastShare). Within `trigger` studs of a player on foot (or touching a car) it
-- stops, hisses and swells for `fuse` s and goes off; killed (a shot, a car, a blast: the chain) it goes off after
-- `deathFuse` s. Full damage within `inner` studs, falling to `edge` of it at `radius` (nothing farther): `player`
-- (through the vest), `car`, `zombie` (every other zombie: a blast, no armour helps; one of these dying goes off too).
-- A player on foot is thrown `knock` studs / s away (+ `knockUp`) at full, a car keeps `carBump` of its speed.
export type BlastDef = { trigger: number, fuse: number, deathFuse: number, radius: number, inner: number, edge: number, player: number, car: number, zombie: number, knock: number, knockUp: number, carBump: number }

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
	-- 6.24: thin and fast (a sprint's pace), little health; it leaps at you from a few strides away. More of them at
	-- night and in the later missions (Config.ZombieTypes.Spawn, Config.Missions.Fixed.RunnerGrow).
	runner = {
		name = "Runner",
		health = 35,
		speed = 27,
		damage = 4,
		attackEvery = 0.7,
		reward = 8,
		xp = 1,
		scale = 0.9,
		skin = { 150, 160, 110 },
		shirt = { 150, 40, 40 },
		pants = { 40, 40, 40 },
		lunge = { range = { 7, 16 } :: { number }, every = 4, speed = 42, up = 9, push = 0.25, time = 0.7, damage = 8, reach = 5 },
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
	-- 6.24: big, slow, armour plates on its chest, shoulders, arms and shins (none on its back): a hit from the front or
	-- a small gun's round does far less (aim for the head, flank it, bring a shotgun or something that explodes). Its
	-- blow throws you back and dents a car hard.
	brute = {
		name = "Brute",
		health = 420,
		speed = 10,
		damage = 22,
		attackEvery = 1.4,
		reward = 45,
		xp = 6,
		scale = 1.8,
		skin = { 100, 120, 80 },
		shirt = { 60, 60, 60 },
		pants = { 70, 50, 40 },
		noLatch = true,
		carDamage = 40,
		carBump = 0.55,
		shove = { speed = 55, up = 22, every = 1.2 },
		armour = { front = 0.45, angle = 65, small = 0.65, smallDamage = 30, least = 0.3, pellets = 4 },
	},
	-- 6.24: swollen, glowing, slow. It never bites: it walks up to you and blows up after a hiss (flash, swell), and a
	-- shot that kills it sets it off too, a moment later. Shoot it from range; its blast hurts the zombies round it
	-- (chain reactions with other bloaters), you and your car.
	bloater = {
		name = "Bloater",
		health = 90,
		speed = 8,
		damage = 0,
		attackEvery = 1,
		reward = 12,
		xp = 3,
		scale = 1.15,
		skin = { 150, 164, 92 },
		shirt = { 112, 104, 78 },
		pants = { 64, 60, 50 },
		noLatch = true,
		blast = { trigger = 7, fuse = 1.6, deathFuse = 0.7, radius = 16, inner = 5, edge = 0.25, player = 45, car = 70, zombie = 150, knock = 50, knockUp = 28, carBump = 0.7 },
	},
} :: { [string]: ZombieDef }

-- 6.24, the owner: "new zombies, so the fighting isn't always the same". Where the special ones come
-- (shared/ZombieKinds.luau weights, server/Zombies.luau pickKind: every random pick of a kind, never a mission's fixed
-- plan) and the server's caps. Each table's kinds' weights (Roam.kinds, a tier's waveKinds and kinds, the residents', a
-- live event's) are multiplied:
--   Night     × (1 + Night[kind] × the night's share, 0 by day … 1 at night: DayNight.nightFactor)
--   Danger    × (1 + Danger[kind] × the danger, 0 … 1: a job's tier ((stars − 1) / 3) or how far from the depot
--             (DangerNear … DangerFar studs), the bigger)
--   Level     below FromLevel[kind] (the job's owner, else the lowest level in the server) × Young[kind] (0: never)
--   BloodMoon × BloodMoon[kind] while the Blood Moon is up (server/LiveEvents.luau sets Zombies.bloodMoon)
-- MaxAlive: at most this many of a kind alive in the whole server (a pick over it comes as a walker); a mission's own
-- (its plan's kinds) are never turned. Parts: the most parts of a kind's body in any of its looks (the R15 template
-- with every piece, tests/zombiekinds_test.luau builds each), Server: the parts of a full server at the worst mix
-- (Horde.MaxTotal bodies, the capped kinds at their caps) at most. KnockTime: seconds the client pushes its own body
-- on a shove or a blast (client/ZombieFx.luau), KnockEvery: at most one knock a player this often (server).
Config.ZombieTypes = {
	Night = { runner = 0.8, bloater = 0.5 } :: { [string]: number },
	Danger = { runner = 0.3, brute = 1, bloater = 1 } :: { [string]: number },
	DangerNear = 350,
	DangerFar = 1600,
	FromLevel = { brute = 4, bloater = 3 } :: { [string]: number },
	Young = { brute = 0.3, bloater = 0 } :: { [string]: number },
	BloodMoon = { runner = 1.8, bloater = 2 } :: { [string]: number },
	MaxAlive = { brute = 10, bloater = 8 } :: { [string]: number },
	Parts = { walker = 48, runner = 50, soldier = 48, brute = 58, bloater = 58 } :: { [string]: number },
	Server = 5000,
	KnockTime = 0.2,
	KnockEvery = 0.4,
	-- The clients' warning before a bloater blows (client/ZombieFx.luau): its belly and hump swell to Swell × their size
	-- and its boils to BoilSwell × theirs (they stay on top of the belly), the boils flash from FlashHz to FlashEnd Hz, a
	-- hiss (a sound of the sheet pitched: HissPitch); its boils pulse Pulse Hz while it walks. Within Range of the camera,
	-- the nearest Most of them.
	Bloater = { Swell = 1.25, BoilSwell = 1.9, FlashHz = 3, FlashEnd = 14, HissPitch = 1.5, HissVolume = 0.9, Pulse = 0.8, Range = 160, Most = 10 },
	-- A hit the brute's plates took (the Clank attribute): a clink (a step's metal sound pitched up) and a spark.
	Clank = { Pitch = 1.8, Volume = 0.7, Range = 90 },
	-- The runner's leap (the Lunge attribute): a shriek (a zombie voice pitched up).
	Shriek = { Pitch = 1.75, Volume = 0.85, Range = 90 },
}

-- 6.15, the owner: "I'd outline the zombies: a red outline, but just subtle." A thin outline (a Highlight: no fill,
-- never through walls) on the nearest living enemies on each client (client/EnemyOutline.luau, shared/OutlinePick.luau):
-- the zombies in Zombie's colour, the people in Human's (the ones the server marks Bandit: the bandits, the gunners, and
-- with Pickups the bandits' pickups as a whole, their crew inside; plus any kind HumanKinds names true). Roblox draws at
-- most 31 Highlights on a client: Count at most (Spare left for anything else), within Range studs of the camera, picked
-- again every Every seconds; a phone gets DeviceBudget.count / range of them (Config.Performance.Lite). One already
-- outlined keeps it out to HoldRange × the range and counts HoldRange times nearer (no blinking at the edge).
Config.Outline = {
	Zombie = { 255, 45, 45 },
	Human = { 255, 150, 30 },
	Transparency = 0.6, -- the outline's (0 solid … 1 none): just subtle
	Count = 24,
	Spare = 7, -- Count + Spare stays within Roblox's 31
	Range = 160,
	Every = 0.25,
	HoldRange = 1.15,
	Pickups = true,
	-- The base's soldiers bite and look infected since 5.9 (a green face, glowing eyes): red like the zombies. true
	-- here outlines a kind orange (a person) though the server does not mark it Bandit.
	HumanKinds = { soldier = false } :: { [string]: boolean },
}

-- 6.16, the owner: "upgrade the visuals and the feel" (the zombies). The looks are shared/ZombieStyle.luau's (several
-- per kind, picked from the zombie's id: its Seed attribute); these are the numbers of how they move, glow, sound and
-- fall. Angles in degrees, distances in studs, times in seconds.
--   * The poses (client/ZombieAnimator.luau, laid over the stock zombie animations through client/PoseLedger.luau):
--     the MaxPosed nearest within Range of the camera, worked out every frame within Near, every FarEvery frames
--     farther (the pose in between kept), picked again every Retarget s; a phone: DeviceBudget.range / count of them.
--   * The server marks a hit (the Hit attribute, at most every HitEvery s a zombie but a hard one) and a bite or a
--     swipe (Attack) for the clients' flinch and lunge (server/Zombies.luau); Death has the falls' speeds.
--   * Eyes: dull by day, a glow by night (Map.nightFactor of the clock), within EyeRange, looked at every EyeEvery s.
--   * Voices (client/ZombieLife.luau, the existing zombie_a / zombie_b cues pitched): groans from the nearest within
--     Groan.Range (each its own pause, at most Voices at once), a runner's scream when it comes for you, a grunt on a
--     hit, a gurgle on a death, a brute's stomp.
Config.ZombieLife = {
	Range = 160,
	Near = 70,
	FarEvery = 3,
	MaxPosed = 24,
	Retarget = 0.3,
	WalkRef = 12, -- studs / s that count as a full walk (the shamble's and the stomp's full size)
	HipSwing = 35, -- degrees of the stock walk's thigh swing that count as a full step (the limp and the stomp follow it)
	-- The shamble (walkers, soldiers): the body dips and rolls onto the bad leg, a hunch, the head on one side, an arm
	-- hanging lower.
	Limp = 0.22,
	LimpRoll = 8,
	Hunch = 12,
	HeadTilt = 16,
	ArmDrop = 28,
	-- The runner's lurch: leaning into it, the body thrown from side to side, the arms flailing.
	RunLean = 20,
	RunRoll = 9,
	Flail = 14,
	-- The brute's stomp: the body drops on every step and sways onto the leg, the arms held out.
	StompDip = 0.4,
	StompRoll = 7,
	StompArms = 14,
	-- 6.24, the special zombies' moves (shared/ZombieStyle.luau pose):
	--   the runner's sprint: at a run (from SprintFrom × WalkRef) the arms pump with the legs (Pump degrees) instead of
	--     flailing, the body leans SprintLean more; its leap (the Lunge attribute): a dive for Dive.Time s, the body
	--     Dive.Lean forward, the arms Dive.Arms up in front, the head Dive.Head up at you
	--   the brute's stomp: StompPitch degrees forward as each foot lands (on top of the dip)
	--   the bloater's waddle: rolled WaddleRoll from foot to foot, leaning back WaddleLean (the belly out), the arms held
	--     out WaddleArms; its fuse (the Fuse attribute): arched back Swell.Arch, the arms flung out Swell.Arms, trembling
	--     Swell.Tremble degrees at Swell.Hz, all growing to the blast
	SprintFrom = 1.6,
	SprintLean = 12,
	Pump = 32,
	Dive = { Time = 0.7, Lean = 55, Arms = 85, Head = 25 },
	StompPitch = 6,
	WaddleRoll = 13,
	WaddleLean = 8,
	WaddleArms = 24,
	Swell = { Arch = 20, Arms = 45, Tremble = 5, Hz = 24 },
	-- Waiting (under IdleBelow studs / s): a slow sway and a lolling head (each its own rhythm).
	IdleBelow = 1.5,
	Sway = 5,
	SwayHz = 0.32,
	Loll = 12,
	-- The attack (the Attack attribute): a wind-up, a lunge and a swipe of one arm (the brute both, overhead).
	AttackTime = 0.55,
	Wind = 12, -- the body back on the wind-up
	Lunge = 26, -- … and forward on the strike
	LungeStuds = 0.6,
	ArmRaise = 55,
	ArmStrike = 75,
	Bite = 18, -- the head forward on the strike
	-- The flinch (the Hit attribute): the chest jerked back, the head snapped; a hard hit (a headshot, a punch, a ram or a
	-- blast) further and longer, a stagger back.
	FlinchTime = 0.35,
	HardTime = 0.7,
	Flinch = 16,
	FlinchHard = 32,
	HeadSnap = 18,
	HeadShotSnap = 45,
	Stagger = 0.55,
	HitEvery = 0.12,
	-- The clawing at a car it hangs on.
	Claw = 35,
	-- Eyes (the Neon EyeL / EyeR, the block body's Eye): Day's colour by day, the kind's Glow at night.
	EyeRange = 260,
	EyeEvery = 0.5,
	EyeDay = { 150, 140, 104 },
	Glow = {
		walker = { 215, 255, 120 },
		runner = { 255, 226, 90 },
		soldier = { 255, 160, 50 },
		brute = { 255, 70, 40 },
		bloater = { 190, 255, 80 }, -- 6.24
	} :: { [string]: { number } },
	GlowDefault = { 230, 240, 140 },
	-- Voices.
	Groan = { Range = 55, Min = 4, Max = 9, Night = 0.75, Hunt = 0.7, Voices = 3, Gap = 0.45, Volume = 0.55 },
	Scream = { Range = 80, Speed = 14, Toward = 0.75, Again = 25, Gap = 1.5, Volume = 0.9, Pitch = 1.55 },
	Grunt = { Range = 70, Again = 0.6, Gap = 0.12, Volume = 0.45, Pitch = 1.35 },
	Gurgle = { Range = 70, Gap = 0.3, Volume = 0.5, Pitch = 0.72 },
	-- (6.24: a brute's step within Shake studs of you shakes the camera a little: ShakeAmount at its feet)
	Stomp = { Range = 60, Volume = 0.9, Pitch = 0.55, Shake = 26, ShakeAmount = 0.22 },
	Snarl = { Range = 40, Again = 2.5, Volume = 0.5, Pitch = 1.2 },
	-- Each kind's voice (× the pitch of every cue, ± Spread for each zombie).
	Pitch = { walker = 0.95, runner = 1.2, soldier = 0.85, brute = 0.62, bloater = 0.7 } :: { [string]: number },
	Spread = 0.08,
	-- Deaths (server/Zombies.luau kill; shared/ZombieStyle.luau death picks which): Fall rad / s the body tips over
	-- about its feet (÷ its scale), Spin rad / s round on a spin, Back studs / s on a knock back (a headshot's head
	-- HeadBack more), Slump studs / s down on a crumple.
	Death = { Fall = 2.6, Spin = 8, Back = 9, HeadBack = 10, Slump = 3, Lift = 4 },
}

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
		kinds = { walker = 0.7, runner = 0.23, brute = 0.05, bloater = 0.03 }, -- (6.24: × Config.ZombieTypes' rules)
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
	-- Zombies that live in the world all the time (they never despawn, the dead come back). 6.24: their kinds (were
	-- server/Zombies.luau's), × Config.ZombieTypes' rules.
	Residents = { count = 36, respawn = 25, kinds = { walker = 0.7, runner = 0.22, brute = 0.06, bloater = 0.03 } :: { [string]: number } },
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

-- 6.16, light and atmosphere (shared/SkyGrade.luau; drawn on every client: client/Weather.luau, client/SkyFx.luau): the
-- look of every time of day. Looks names a look; Clock says at which hour each one is full (sorted, 0 … 24; after the
-- last the clock wraps round to the first), and in between two looks blend smoothly (smoothstep). Colours are
-- { r, g, b } (0 … 255). A look holds:
--   brightness, exposure     Lighting.Brightness (the sun or the moon) and ExposureCompensation
--   ambient, outdoor         Lighting.Ambient and OutdoorAmbient (the light in the shade, indoors and out)
--   top, bottom              Lighting.ColorShift_Top (the sunlit sides: a golden sun) and ColorShift_Bottom (the bounce)
--   diffuse, specular, soft  Lighting.EnvironmentDiffuseScale, EnvironmentSpecularScale (the sky's light and shine) and
--                            ShadowSoftness
--   tint, saturation, contrast, lift   the colour grade (the ColorCorrection ZombieGrade: TintColor, Saturation,
--                            Contrast, Brightness)
--   bloom, bloomSize, threshold   the bloom: the lamps, the lit windows and the headlights glow at night (a high
--                            threshold by day, so nothing washes out)
--   rays                     the sun rays' intensity (under a clear sky, from a medium graphics quality up)
--   air, decay, density, offset, glare, haze   the atmosphere (it is the fog too: Lighting's Fog* do nothing with an
--                            Atmosphere): Color, Decay, Density, Offset, Glare, Haze
--   clouds                   the clouds' colour
--   blur                     0 … 1 of Blur.Far (the soft blur far away)
--   dust                     0 … 1 of Dust.Rate (the motes floating in the sun)
-- The rain, the fog, the snow, the town's glow at night and the Blood Moon (Config.LiveEvents) blend over it as before.
-- 3.0.1's rule: the night is dark but readable, never so dark a zombie hides in it: ReadableFloor is the least any hour
-- may have (the luma of OutdoorAmbient, Ambient and the tint, 0 … 255; the sun's or the moon's brightness);
-- tests/skygrade_test.luau checks every minute of the day.
Config.Atmosphere = {
	Looks = {
		-- Night: a readable blue night (3.0.1's look: a bright moon, a blue grade, a dark blue haze); the lamps bloom.
		night = {
			brightness = 1.5, exposure = 0.05, ambient = { 68, 72, 94 }, outdoor = { 96, 104, 138 },
			top = { 0, 8, 30 }, bottom = { 4, 6, 14 }, diffuse = 0.3, specular = 0.55, soft = 0.6,
			tint = { 200, 212, 255 }, saturation = -0.25, contrast = 0.12, lift = 0,
			bloom = 1, bloomSize = 30, threshold = 1.05, rays = 0,
			air = { 62, 72, 102 }, decay = { 30, 36, 56 }, density = 0.3, offset = 0.25, glare = 0, haze = 0.7,
			clouds = { 70, 78, 104 }, blur = 0.6, dust = 0,
		},
		-- Dawn, the blue hour before the sun: cool and blue, the lamps still on.
		dawn = {
			brightness = 1.45, exposure = 0.1, ambient = { 66, 74, 100 }, outdoor = { 94, 106, 144 },
			top = { 16, 26, 60 }, bottom = { 6, 10, 22 }, diffuse = 0.4, specular = 0.55, soft = 0.6,
			tint = { 206, 222, 255 }, saturation = -0.18, contrast = 0.1, lift = 0.01,
			bloom = 0.85, bloomSize = 28, threshold = 1.1, rays = 0.04,
			air = { 112, 128, 168 }, decay = { 58, 70, 112 }, density = 0.33, offset = 0.15, glare = 0.3, haze = 1.3,
			clouds = { 150, 162, 196 }, blur = 1, dust = 0.1,
		},
		-- Sunrise: the golden hour, a warm low sun, long soft shadows, rays and dust in the light.
		sunrise = {
			brightness = 1.6, exposure = 0.05, ambient = { 84, 74, 72 }, outdoor = { 122, 106, 102 },
			top = { 120, 70, 30 }, bottom = { 30, 18, 14 }, diffuse = 0.5, specular = 0.65, soft = 0.45,
			tint = { 255, 226, 198 }, saturation = 0, contrast = 0.14, lift = 0.01,
			bloom = 0.6, bloomSize = 26, threshold = 1.25, rays = 0.16,
			air = { 214, 152, 114 }, decay = { 150, 98, 82 }, density = 0.33, offset = 0.08, glare = 1.6, haze = 1.8,
			clouds = { 255, 208, 172 }, blur = 1, dust = 1,
		},
		-- Morning: fresh and clear. 7.1, the Alps: a cool, crisp blue air (the far mountains fade blue), lush colours.
		morning = {
			brightness = 1.75, exposure = 0, ambient = { 74, 74, 82 }, outdoor = { 106, 110, 120 },
			top = { 36, 26, 12 }, bottom = { 10, 10, 10 }, diffuse = 0.55, specular = 0.7, soft = 0.3,
			tint = { 246, 248, 248 }, saturation = -0.01, contrast = 0.12, lift = 0,
			bloom = 0.35, bloomSize = 22, threshold = 1.45, rays = 0.06,
			air = { 182, 202, 226 }, decay = { 116, 138, 172 }, density = 0.26, offset = 0.15, glare = 0.5, haze = 1.25,
			clouds = { 255, 255, 255 }, blur = 0.8, dust = 0.7,
		},
		-- Noon: clean and crisp, true colours, sharp shadows, the least haze. 7.1: the alpine noon: a clear blue air,
		-- lush, a touch cool.
		noon = {
			brightness = 1.8, exposure = -0.05, ambient = { 72, 72, 80 }, outdoor = { 106, 110, 120 },
			top = { 14, 12, 6 }, bottom = { 8, 8, 8 }, diffuse = 0.6, specular = 0.7, soft = 0.2,
			tint = { 247, 251, 255 }, saturation = 0.02, contrast = 0.14, lift = 0,
			bloom = 0.3, bloomSize = 20, threshold = 1.5, rays = 0.03,
			air = { 178, 200, 228 }, decay = { 118, 142, 178 }, density = 0.24, offset = 0.15, glare = 0.2, haze = 1,
			clouds = { 255, 255, 255 }, blur = 0.7, dust = 0.5,
		},
		-- Afternoon: warming up (7.1: still the clear alpine air, a little warmer).
		afternoon = {
			brightness = 1.75, exposure = 0, ambient = { 76, 72, 76 }, outdoor = { 108, 106, 110 },
			top = { 50, 34, 14 }, bottom = { 12, 10, 8 }, diffuse = 0.55, specular = 0.7, soft = 0.3,
			tint = { 252, 246, 234 }, saturation = 0.02, contrast = 0.13, lift = 0,
			bloom = 0.35, bloomSize = 22, threshold = 1.45, rays = 0.06,
			air = { 196, 204, 214 }, decay = { 128, 136, 150 }, density = 0.26, offset = 0.12, glare = 0.6, haze = 1.25,
			clouds = { 255, 250, 242 }, blur = 0.8, dust = 0.7,
		},
		-- Sunset, the golden hour: the warmest look, an orange haze and the sun's glare, rays and dust in the light.
		golden = {
			brightness = 1.65, exposure = 0.05, ambient = { 90, 74, 70 }, outdoor = { 128, 104, 98 },
			top = { 140, 78, 30 }, bottom = { 34, 18, 14 }, diffuse = 0.5, specular = 0.65, soft = 0.45,
			tint = { 255, 218, 186 }, saturation = 0.04, contrast = 0.16, lift = 0.01,
			bloom = 0.65, bloomSize = 26, threshold = 1.2, rays = 0.18,
			air = { 222, 142, 98 }, decay = { 160, 88, 72 }, density = 0.34, offset = 0.06, glare = 2, haze = 2,
			clouds = { 255, 192, 152 }, blur = 1, dust = 1,
		},
		-- Dusk, the blue hour after the sun: violet and blue, the lamps coming on.
		dusk = {
			brightness = 1.45, exposure = 0.1, ambient = { 74, 70, 98 }, outdoor = { 104, 100, 142 },
			top = { 40, 20, 50 }, bottom = { 10, 8, 20 }, diffuse = 0.4, specular = 0.55, soft = 0.55,
			tint = { 214, 208, 255 }, saturation = -0.12, contrast = 0.12, lift = 0.01,
			bloom = 0.9, bloomSize = 28, threshold = 1.08, rays = 0.04,
			air = { 118, 94, 132 }, decay = { 64, 46, 80 }, density = 0.32, offset = 0.15, glare = 0.5, haze = 1.2,
			clouds = { 172, 134, 162 }, blur = 0.9, dust = 0.1,
		},
	},
	-- When each look is full (hours; the default Roblox sun rises at about 6:00 and sets at about 18:00).
	Clock = {
		{ hour = 4.6, look = "night" },
		{ hour = 5.5, look = "dawn" },
		{ hour = 6.5, look = "sunrise" },
		{ hour = 8.5, look = "morning" },
		{ hour = 12.5, look = "noon" },
		{ hour = 16.2, look = "afternoon" },
		{ hour = 17.7, look = "golden" },
		{ hour = 18.9, look = "dusk" },
		{ hour = 20.3, look = "night" },
	} :: { { hour: number, look: string } },
	ReadableFloor = { outdoor = 95, ambient = 64, tint = 200, brightness = 1.4 },
	-- The sky (server/World.luau): the sun's and the moon's size (degrees), the stars (0 … 5000). Optional pictures:
	-- empty strings keep Roblox's own sky; an "rbxassetid://…" in all six Skybox sides (Bk, Dn, Ft, Lf, Rt, Up), in Sun
	-- or in Moon sets that one.
	Sky = {
		SunSize = 12,
		MoonSize = 16,
		Stars = 5000,
		Skybox = { Bk = "", Dn = "", Ft = "", Lf = "", Rt = "", Up = "" } :: { [string]: string },
		Sun = "",
		Moon = "",
	},
	-- Roblox's moving clouds (Terrain.Clouds, made on every client): Cover and Density in clear weather, in the rain and
	-- in a fog (blended with the weather); their colour is the look's. Lite: on a phone or a tablet too (false: none
	-- there, unless the place has its own). 7.1: fewer, brighter fair-weather clouds over the Alps.
	Clouds = { Cover = 0.42, Density = 0.45, RainCover = 0.88, RainDensity = 0.85, FogCover = 0.72, FogDensity = 0.75, Lite = true },
	-- The soft blur far away (a DepthOfFieldEffect): sharp out to Focus + Radius studs, beyond that Far × the look's blur
	-- (half of it in the rain or the fog: the air blurs already). Never on a phone or a tablet, below graphics quality
	-- Quality (1 … 10), or while you aim (it fades out over Fade seconds).
	Blur = { Focus = 200, Radius = 50, Far = 0.12, Quality = 4, Fade = 0.4 },
	-- Dust in the air by day: tiny slow motes in a Box-stud box around the camera, Rate a second × the look's dust (none
	-- in the rain, the fog, the snow, at night, or with Reduced Motion); a phone or a tablet Lite of them, fewer at a low
	-- graphics quality.
	Dust = { Rate = 7, Lite = 0.4, Box = 44, Size = 0.09, Life = { 7, 11 } :: { number } },
	-- A soft haze around the street lamps at night: the Count nearest lamps that shine (the 6.13.1 light budget) within
	-- Range of the camera get a faint glow Size studs across (a phone or a tablet: Lite of them).
	Halo = { Count = 12, Lite = 0, Range = 160, Size = 7, Transparency = 0.9 },
}

-- 7.1, the Alps (the owner: "make the map a smaller alpine valley, step by step"; step 1B: mountains and forests, nothing
-- you play on moves): shared/AlpineLayout.luau lays it out as plain numbers (tests/alpine_test.luau checks it),
-- server/Alpine.luau builds it once from World.build (tools/alpine-preview draws it).
--   Box          the ring of mountains stands round this box (Map.Bounds today: the world's walls); step 2 pulls it in
--   Gap          studs from the box to the front row's foot (the mountains never reach into the box)
--   Layer        a mountain is a stack of terrain cylinders this many studs thick (a cone: its radius at height y is
--                its base × ((height − y) / (height − floor)) ^ Profile; > 1: the flanks steepen toward the summit);
--                7.1 review: exactly two rows of the terrain's 4-stud voxels (a layer never writes a row of the next)
--   Floor / WetFloor   the bottom layer's foot under the ground's 0; in the river or the lake from its bed (both on the
--                4-stud voxel grid, so every layer covers whole voxel rows)
--   Front / Back the two rows: Height (summits, studs), Spread (the base's radius = the height × this), Profile; the back
--                row's feet Behind studs behind the front row's, each back peak with up to two lower Shoulders (chance)
--   Lean         a peak leans one way (a steep face on that side, a long ridge on the other): each layer's middle moves
--                this share (a range) of what its radius shrinks, so every layer stays inside the one under it
--   Spacing      two cones next to each other stand at most this × the sum of their radii at Seal height apart, so the
--                ring's crest between them never drops under Seal (studs): no gap a car could drive through
--   Gorge        the river leaves the valley through a gorge this deep (studs past Gap); a back peak closes it
--   Green / Snow the slopes are grass up to Green (a height between the two; the forests climb it), rock above, snow
--                over Snow (summer); north of Map.WinterZ, west of the river, the mountains are all snow with rock bands
--   Strata       this share of a peak's rock layers is the other stone (a peak is Rock or Limestone): bands at random
--                heights; Rough: each layer's radius ± half this share (the flanks' crags; still inside the one under it)
--   Glaciers     tongues of glacier ice down the inner flanks of the tallest summer peaks: Width at the top and at the
--                snout, Thick studs (Protrude of it out of the slope)
--   Scree        light stone fans at the front row's foot: Count a peak (summer), Radius
--   Silhouettes  a far look of every peak of MinHeight or more (Persistent parts inside the terrain: with streaming the
--                terrain far away is not sent, these are): a square pyramid Lower × the summit high, Margin studs inside
--                the slopes everywhere, its snow cap from the peak's snow line
--   Portals      where a road would leave the valley: the mountains open into a cliff with a tunnel mouth (Depth deep,
--                Height high, the rock over it Cliff high) and a ROAD CLOSED barrier at the box's edge; the road runs
--                there along x from `from` (a yard's edge) at z (the West Highway past the Old Farm)
--   Waterfall    a waterfall where the river comes out of the north gorge
--   Colors       the terrain's material colours (Terrain:SetMaterialColor), Valley the open ground's colour and material
--   Budget       Volume: studs³ the fills may hold at most (overlaps counted twice); Fills: terrain calls; Parts: the
--                parts of it all (the trees, the flowers, the huts, the silhouettes, the portal, the waterfall)
--   SkipInStudio a dev toggle (default off): in a Studio Play test the terrain's fills are left out (the slowest part of
--                the build); the silhouettes, the pass and the forests still stand (the slope trees on the flat ground
--                under where the mountains would be). Never on a live server (RunService:IsStudio())
--   Trees        the forests: at most Max trees of Parts parts (7.1 review: a trunk and one needle spire; spruce and
--                fir), on a grid Spacing apart (± Jitter), Slope of them on the ring's lower slopes (under the
--                Treeline), Height (studs);
--                never within RoadClear of a road's edge (nor its canopy over it), JunctionClear of a road's end or bend
--                (the drivers' view at the junctions), TownClear of a district's edge roads, YardClear of a yard,
--                LotClear of a home's lot, PlaceClear of a place, WaterClear of the water, nor in Keep (the ski lift);
--                thinner near town (TownFade studs; Copses of the valley's trees stand there in small copses), denser
--                within Edge of the box's edge; Noise: the forests' and the
--                meadows' patch sizes; ShadowNear: only trees this close to a road throw shadows; Chunk: one Atomic
--                model (streamed together) per Chunk × Chunk studs; Colors: the needles' variants, Snowy the winter's
--                frost on them
--   Meadows      open meadows with wildflowers: Patches of Flowers small parts, Gap apart, Road studs from a road's edge
--   Huts         Count wooden hay barns and huts in the meadows, Gap apart, Road studs from a road's edge
Config.Alpine = {
	Box = { x0 = -2150, z0 = -2950, x1 = 1900, z1 = 1500 },
	Gap = 40,
	Seed = 4711,
	Layer = 8,
	Floor = -12,
	WetFloor = -32,
	Front = { Height = { 250, 420 } :: { number }, Spread = { 1.0, 1.25 } :: { number }, Profile = 1.3 },
	Back = { Height = { 480, 700 } :: { number }, Spread = { 0.85, 1.05 } :: { number }, Profile = 1.5, Behind = 170, Shoulders = 0.6 },
	Lean = { 0.1, 0.5 } :: { number },
	Spacing = 0.8,
	Seal = 70,
	Gorge = 170,
	Green = { 110, 160 } :: { number },
	Snow = { 300, 360 } :: { number },
	Strata = 0.12,
	Rough = 0.1,
	Glaciers = { Count = 7, Width = { 110, 46 } :: { number }, Thick = 14, Protrude = 3 },
	Scree = { Count = 2, Radius = { 20, 34 } :: { number } },
	Silhouettes = { MinHeight = 300, Lower = 0.86, Margin = 6 },
	Portals = {
		{ id = "westpass", name = "WEST PASS", x = -2150, z = 520, nx = -1, nz = 0, from = -2030, width = 40 },
	} :: { { id: string, name: string, x: number, z: number, nx: number, nz: number, from: number, width: number } },
	Portal = { Depth = 36, Height = 26, Cliff = 60, Text = "ROAD CLOSED — EVACUATION ZONE" },
	Waterfall = true,
	Colors = {
		Grass = { 92, 134, 58 },
		LeafyGrass = { 84, 124, 54 },
		Ground = { 112, 98, 74 },
		Rock = { 120, 118, 114 },
		Limestone = { 158, 154, 146 },
		Snow = { 240, 244, 248 },
		Glacier = { 176, 214, 232 },
	} :: { [string]: { number } },
	Valley = { Color = { 96, 138, 60 } :: { number }, Material = "Grass" },
	Budget = { Volume = 1.0e10, Fills = 7500, Parts = 6500 },
	SkipInStudio = false,
	Trees = {
		Max = 2500,
		Parts = 2,
		Spacing = 25,
		Jitter = 7,
		Slope = 0.25,
		Copses = 0.12,
		Height = { 34, 66 } :: { number },
		Treeline = { 130, 180 } :: { number },
		RoadClear = 20,
		JunctionClear = 60,
		TownClear = 50,
		TownFade = 700,
		Edge = 700,
		YardClear = 30,
		LotClear = 16,
		PlaceClear = 55,
		WaterClear = 14,
		Keep = { { x0 = -1140, z0 = -2270, x1 = -790, z1 = -2180 } } :: { { x0: number, z0: number, x1: number, z1: number } },
		Noise = { Big = 420, Small = 140 },
		ShadowNear = 110,
		Chunk = 128,
		Colors = { { 34, 58, 40 }, { 44, 72, 46 }, { 58, 86, 50 } } :: { { number } },
		Trunk = { 86, 62, 44 } :: { number },
		Snowy = { 236, 240, 244 } :: { number },
	},
	Meadows = {
		Patches = 36,
		Flowers = 8,
		Gap = 160,
		Road = { 24, 150 } :: { number },
		Colors = { { 245, 245, 238 }, { 250, 208, 60 }, { 170, 110, 210 }, { 222, 64, 72 }, { 92, 140, 230 } } :: { { number } },
	},
	Huts = { Count = 4, Gap = 600, Road = { 34, 110 } :: { number } },
}

-- 7.2, the Alps on the maps (client/MapView.luau draws the minimap and the big map, shared/MapStyle.luau works out
-- what from Map and AlpineLayout, tools/phone-ui/mapview.luau checks it): a paper map, the valley green on cream, grey
-- rock and white snow round it, the roads light with a brown edge, the highways amber.
--   Margin     studs of the mountain ring drawn round Map.Bounds on both maps (the minimap sees at most about 300
--              studs from you, and you stay inside the bounds)
--   Colors     { r, g, b }: Paper (round the valley on the big map), Valley, Meadow (the wildflower meadows), Slope
--              (the ring's grass on the minimap), Forest and Trees (a forest band and its tree dots; SnowForest and
--              SnowTrees in the winter), Winter (the snowfield), Rock, Snow, Shadow (the peaks' shadow side), Water,
--              Shore, Ice, Yard, Blocks (by district style), Special, Park, Square, Footbridge, Road, RoadEdge,
--              Highway, Bridge, IceRoad, Fog, Ink / InkSoft / Halo (the captions), Closed (the ROAD CLOSED sign), Hut
--   Peaks      the big map's mountains: a shaded peak with its snow cap for every cone of the ring (the shoulders
--              only east and west), pulled into the margin. Base: where a peak's foot line stands, a share of Margin
--              out from the bounds { front row, back row }: north (the peaks rise up the map, away from the valley),
--              south (up the map, toward it, never into it), side (east and west, at most Side × Margin high, wide
--              enough to overlap into one range, their inner feet at most Into × Margin over the valley's edge);
--              Height: the lowest … the tallest cone's peak, a share of Margin; Cap: a snow cap's share of its peak
--              { least, most } (the winter's peaks: Winter); Shade: the shadow side's transparency; Haze: how far the
--              back row's rock fades toward the paper
--   Relief     the minimap's mountains seen from above: a cone's grassy foot, its rock (from its grass line up) and
--              its snow (from its snow line up) as discs lit from the north-west, each that reaches within Reach
--              studs of the bounds (the minimap sees about 290 from you at its widest); a snow disc smaller than
--              MinSnow studs is left out; Light: the far side of a disc is its colour × (1 - 2 × Light)
--   Forest     the valley's trees (AlpineLayout.forest) binned in Cell × Cell squares; a square with Min trees or
--              more is forest; a row's run of forest squares is one rounded band Overlap × Cell high (the rows melt
--              into each other) with PerCell tree dots a square
--   Meadows    a lighter disc Radius studs round every wildflower patch (AlpineLayout's meadows; Soft its
--              transparency), a flower's dot Flower studs round in it
--   Foothills  the soft green edge round the valley on the big map: studs out from the bounds
--   Altstadt   the old town's label (a placeholder until Map names its villages: Map.Villages) over District's name
--   Wait       seconds a client waits for the server's summary of the ring and the forest (MapStyle.publish, before
--              World.build) before it works them out itself
--   Budget     the most GuiObjects a layer may make on one map (tools/phone-ui/mapview.luau holds them): Peaks (big),
--              Relief (mini), Forest, Meadows (with the huts), Alpine (all of the alpine layers on one map), Mini (7.2
--              review: all of them on the minimap, whose CanvasGroup draws them again on every move); Summary:
--              the most characters the server's summary may have (a StringValue holds 200,000)
Config.MapStyle = {
	Margin = 420,
	Colors = {
		Paper = { 236, 228, 208 },
		Valley = { 186, 206, 150 },
		Meadow = { 208, 224, 166 },
		Slope = { 146, 164, 114 },
		Forest = { 118, 152, 98 },
		Trees = { 70, 108, 64 },
		SnowForest = { 164, 182, 172 },
		SnowTrees = { 92, 118, 104 },
		Winter = { 236, 241, 243 },
		Rock = { 164, 158, 148 },
		Snow = { 252, 252, 250 },
		Shadow = { 52, 56, 66 },
		Water = { 146, 194, 222 },
		Shore = { 98, 150, 188 },
		Ice = { 208, 228, 238 },
		Yard = { 216, 206, 182 },
		Blocks = { downtown = { 216, 200, 180 }, harbor = { 204, 198, 188 }, suburbs = { 224, 210, 186 } } :: { [string]: { number } },
		Special = { 202, 180, 152 },
		Park = { 150, 192, 118 },
		Square = { 210, 190, 154 },
		Footbridge = { 150, 108, 72 },
		Road = { 252, 250, 244 },
		RoadEdge = { 136, 122, 104 },
		Highway = { 244, 198, 96 },
		Bridge = { 214, 210, 200 },
		IceRoad = { 226, 238, 244 },
		Fog = { 92, 100, 112 },
		Ink = { 62, 54, 44 },
		InkSoft = { 106, 96, 82 },
		Halo = { 246, 240, 224 },
		Closed = { 196, 58, 46 },
		Hut = { 128, 86, 54 },
	} :: { [string]: any },
	Peaks = {
		Base = { north = { 0.12, 0.4 } :: { number }, south = { 0.62, 0.98 } :: { number }, side = { 0.42, 0.62 } :: { number } },
		Height = { 0.48, 0.84 } :: { number },
		Side = 0.6,
		Into = 0.12,
		Cap = { 0.2, 0.42 } :: { number },
		Winter = 0.6,
		Shade = 0.72,
		Haze = 0.4,
	},
	Relief = { Reach = 300, MinSnow = 10, Light = 0.12 },
	Forest = { Cell = 48, Min = 2, Overlap = 1.3, PerCell = 2 },
	Meadows = { Radius = 80, Flower = 10, Soft = 0.3 },
	Foothills = 120,
	Altstadt = { Name = "Altstadt", District = "downtown" },
	Wait = 10,
	Budget = { Peaks = 330, Relief = 220, Forest = 240, Meadows = 50, Alpine = 600, Mini = 380, Summary = 20000 },
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
		[2] = { money = 500, items = { medkit = 2 }, text = "Your first bike: the BIKES counter at Dead End Motors" }, -- (6.12.7: Spoke & Chain before)
		[3] = { money = 750, items = { medkit = 2 }, kit = "tote" }, -- (6.6: the Canvas Tote, no backpack any more)
		[4] = { money = 1000, items = { medkit = 2 }, kit = "thermal", text = "The ★ car jobs, in your ZDC Van" }, -- (6.12.2: the shoes before; 7.x: Earl's Old Van before)
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

-- 6.20, skills for levels (design/skills/PROPOSAL.md, approved with one change: RESET is always free). Every level from
-- 2 gives a skill point (shared/Skills.luau points: level − 1, 14 at level 15; an old save gets its points from its
-- level at once: nothing is stored but the ranks bought, profile.skills). Three branches; a rank costs `cost` points (1;
-- Strong Back's one rank 2), an apex (`apex`) ApexCost and it opens once ApexNeeds points are spent in its branch. Each
-- rank adds `effect` (every key × the rank: shared/Skills.luau effect). The server decides (server/Skills.luau: the
-- Skills remote's "buy" and "reset", the reset never during a job or a mission); the effects are wired where the game
-- computes them:
--   hands / bag    +1 light piece in your hands and in your bag (server/Cargo.luau handsMax, server/Transport.luau)
--   sprintTime     + seconds of sprint on a full breath (client/Stamina.luau)
--   sprintSpeed    + share of the sprint's speed (client/CameraRig.luau)
--   tips           + share of an order's pay the customer tips (server/Jobs.luau payOrder; not on a mission)
--   express        + share of an order's pay when it arrives in time (server/Jobs.luau payOrder)
--   carDamage      − share of the damage your vehicle takes (server/Vehicles.luau damage)
--   handling       − share of the time a serve stop and people boarding take (server/Cargo.luau)
--   fuel           − share of the fuel your car burns (server/Fuel.luau)
--   repair         − share of a repair shop's fee (server/Repair.luau)
--   stuntman       running a zombie over costs the car nothing, a bandit car's ram half (server/Vehicles.luau damage)
--   punch          + damage of a punch (server/CloseCombat.luau)
--   spread         − share of a hand gun's spread (server/Gun.luau; the guns have no reload to make quicker)
--   recoil         − share of the camera's kick (client/ShotKick.luau, through client/Shooting.luau)
--   health         + max health (server/Skills.luau, on every spawn)
--   regen          + share of the body's own healing (server/Skills.luau; a medkit heals at once, so the healing that
--                  takes time is what gets faster)
--   freeMedkit     a medkit used is not spent, once a job or mission (server/Items.luau)
--   secondWind     a lethal hit leaves you at SecondWindHealth instead, once a job or mission (server/Armour.luau)
-- A "once a job or mission" charge fills when a job or a mission starts (yours or your crew's) and on every spawn.
-- BaseHealth: a courier's health without Endurance (Roblox's default). Regen: the default healing a second (a share of
-- the max health; Roblox's own Health script) that `regen` adds to.
export type SkillDef = {
	id: string,
	name: string,
	icon: string,
	ranks: number,
	cost: number,
	apex: boolean?,
	effect: { [string]: number },
	text: string, -- what one rank does, in a few words
}
export type SkillBranch = { id: string, name: string, icon: string, skills: { SkillDef } }
Config.Skills = {
	PerLevel = 1,
	ApexNeeds = 6,
	SecondWindHealth = 25,
	BaseHealth = 100,
	Regen = 0.01,
	-- 6.20 review: a spent charge (Second Wind, the free medkit) fills again only in a different job or mission and
	-- at least this many seconds after it was spent (accepting and cancelling jobs, or a respawn, does not refill it)
	Recharge = 180,
	Branches = {
		{
			id = "courier",
			name = "Courier",
			icon = "📦",
			skills = {
				{ id = "strongBack", name = "Strong Back", icon = "🎒", ranks = 1, cost = 2, effect = { hands = 1, bag = 1 }, text = "+1 piece in your hands and in your bag" },
				{ id = "longBreath", name = "Long Breath", icon = "🫁", ranks = 3, cost = 1, effect = { sprintTime = 1.5 }, text = "+1.5 s of sprint" },
				{ id = "doorstepSmile", name = "Doorstep Smile", icon = "😊", ranks = 3, cost = 1, effect = { tips = 0.05 }, text = "+5% of the pay as a tip" },
				{ id = "lightStep", name = "Light Step", icon = "👟", ranks = 2, cost = 1, effect = { sprintSpeed = 0.04 }, text = "+4% sprint speed" },
				{ id = "express", name = "Express", icon = "⚡", ranks = 1, cost = 3, apex = true, effect = { express = 0.1 }, text = "+10% pay for an order delivered in time" },
			},
		},
		{
			id = "driver",
			name = "Driver",
			icon = "🚐",
			skills = {
				{ id = "toughBody", name = "Tough Body", icon = "🛡", ranks = 3, cost = 1, effect = { carDamage = 0.08 }, text = "−8% damage to your vehicle" },
				{ id = "quickHands", name = "Quick Hands", icon = "🙌", ranks = 3, cost = 1, effect = { handling = 0.1 }, text = "−10% time to serve and to board people" },
				{ id = "lightFoot", name = "Light Foot", icon = "⛽", ranks = 3, cost = 1, effect = { fuel = 0.07 }, text = "−7% fuel burnt" },
				{ id = "knownAtShop", name = "Known at the Shop", icon = "🔧", ranks = 2, cost = 1, effect = { repair = 0.15 }, text = "−15% repair fee" },
				{ id = "stuntman", name = "Stuntman", icon = "💥", ranks = 1, cost = 3, apex = true, effect = { stuntman = 1 }, text = "No damage from running zombies over, half from a ram" },
			},
		},
		{
			id = "fighter",
			name = "Fighter",
			icon = "🥊",
			skills = {
				{ id = "hardFist", name = "Hard Fist", icon = "👊", ranks = 3, cost = 1, effect = { punch = 3 }, text = "+3 punch damage" },
				{ id = "steadyHand", name = "Steady Hand", icon = "🎯", ranks = 3, cost = 1, effect = { spread = 0.1, recoil = 0.15 }, text = "−10% gun spread, −15% recoil" },
				{ id = "endurance", name = "Endurance", icon = "❤", ranks = 3, cost = 1, effect = { health = 10 }, text = "+10 max health" },
				{ id = "fieldMedic", name = "Field Medic", icon = "➕", ranks = 2, cost = 1, effect = { regen = 0.2, freeMedkit = 1 }, text = "+20% healing; a free medkit a job" },
				{ id = "secondWind", name = "Second Wind", icon = "💨", ranks = 1, cost = 3, apex = true, effect = { secondWind = 1 }, text = "Survive a lethal hit with 25 health, once a job" },
			},
		},
	} :: { SkillBranch },
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
	-- 5.7, the balance: a free rental is the slow way round (the Rusty Bike does 30, the bought E-Scooter 34; 6.14.1: the rental 28) and its
	-- rack takes one light piece (the bought one two). server/Vehicles.luau caps the rental's MaxSpeed and its room.
	MaxSpeed = 28, -- 6.14.1: 26 (it was slower than a sprint's 28)
	Accel = 34, -- 6.0: quick off the line like the bought one (6.14.1: 38), the cap above keeps it slow at the top
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

-- 6.10, the E-Scooter's ride (the owner: "give the scooter better controls"): its handling (client/Drive.luau through
-- shared/ScooterRide.luau, pure: tests/scooter_test.luau). A ZDC RIDE rental rides the same (its own top speed and
-- pull: Config.Rental). The bikes and the cars keep their handling. (6.14.2, the owner: "take the wheelie away, it
-- looks silly": the 6.10 wheelie is gone.)
Config.Scooter = {
	-- The steering: CarDef.turn (rad/s) times a share that eases from LowTurn at walking pace down to HighTurn at the
	-- scooter's top speed (MaxSpeed): quick and precise in the city's corners, calm at full speed (6.0: 2.8 at any speed)
	-- 6.14.1 (the owner: "a more pleasant ride on the scooter": the steering, the pull and the brake, the camera): 1.15 →
	-- 0.95 and 0.45 → 0.6, calmer at a middle speed (a 16 studs/s turn about 7 studs round, 6 before) and less lazy at
	-- the top (about 20 studs round, 25 before)
	LowTurn = 0.95,
	HighTurn = 0.6,
	EaseFrom = 6, -- studs/s: the turn starts easing off from here
	GripSpeed = 2.5, -- studs/s: from a stand the steering fades in up to this speed (it does not spin on the spot)
	SteerIn = 4.5, -- the steering goes to the key's full lock at this rate (1/s: about 0.22 s, a tap is a small turn) …
	SteerOut = 9, -- … and back to the middle at this one (about 0.11 s) (6.14.1: 7 and 12, a key snapped to a sharp turn)
	Brake = 55, -- studs/s²: S while rolling forward (34 → 0 in about 0.6 s; 6.14.1: 80 threw you over the bar)
	Coast = 10, -- studs/s²: no key, it rolls on (34 → 0 in about 3.4 s; 6.14.1: 14)
	-- 6.14.1, the pull (ScooterRide.pull, × the scooter's Accel by its share of the top speed): soft for the first push
	-- (Start at a stand, all of it from Full), all of it up to Ease, then fading to Top at the top speed: it glides
	-- into its top speed instead of hitting a wall at it
	Pull = { Start = 0.7, Full = 0.25, Ease = 0.7, Top = 0.35 },
	-- 6.14.1, the carve: the way it moves follows its nose at this rate (1/s) instead of at once, a touch of flow in a
	-- turn (not on ice or snow: their own slide)
	Carve = 16,
	Reverse = 0.2, -- of the top speed: S from a stand walks it back
	LeanMax = 0.2, -- radians (about 11°) the scooter leans into a turn at most (the look only; a bike: 0.16)
	LeanRate = 0.0075, -- per (rad/s of turning × stud/s of speed)
}

-- 6.26 (6.24's bikes, now every vehicle of a player: the cars, the vans, the trucks, the bikes, the E-Scooter, ridden
-- or parked), a vehicle knocked over gets back up (server/CarRighting.luau, shared/CarUpright.luau). Why it is needed:
-- the steering's AngularVelocity "Steer" (server/Vehicles.luau) holds every turn still, pitch and roll too, with about
-- ten times the torque gravity has on a car propped up on one end, so a car tipped by anything never falls back onto
-- its wheels by itself. Down means (shared/CarUpright.luau CarUpright.down): on its back or past its side (over 90°)
-- at any speed; or, moving slower than Slow studs/s (a jump, a stunt, a slide go on), its top more than the kind's
-- Lean degrees off straight up with a wheel Gap studs or more over the ground under it, or with no ground under a
-- wheel within Probe (resting on its nose, a bumper or its side: the owner's screenshot, a ZDC Van 20–25° nose down).
-- On all four wheels it is never down, however steep the ground. Down for Hold seconds, the server turns it back onto
-- its wheels (its AlignOrientation "Righting", Vehicles.righting) at most TurnRate rad/s, gently (Responsiveness),
-- level with the ground where it will stand (rays straight down round where it lies, aimed again every look while it
-- turns; ground steeper than Level degrees counts as none: straight up instead; a bike without the ground's roll),
-- facing where it pointed, the Steer's hold let go meanwhile; within Settled degrees of that it is the driver's again.
-- Still down after Give seconds (wedged against something) it is stood up where it lies, on the ground's plane, Lift
-- studs over it, nudged to free room when something is there (Vehicles.standUp, Config.SpawnSpot). Not a car on a
-- repair lift, an anchored one or one a chauffeur drives (righted after the hand-over).
Config.CarUpright = {
	Check = 0.25, -- seconds between the looks at the vehicles
	Slow = 6, -- studs/s (its whole speed, a fall too): only slower than this is a tilted vehicle down (on its back: any)
	Gap = 0.6, -- studs between a wheel's bottom and the ground under it: that wheel is in the air
	Probe = 6, -- studs a wheel's ray looks down (from half of it over the wheel's bottom): no ground in it, none at all
	Level = 20, -- degrees: the ground under the wheels is the level to turn back to only up to this steep
	Kinds = {
		-- (6.24's bike numbers; 6.24's Tilt 45° gone: a wheel off the ground decides, not an angle; Settled 20 → 6 from
		-- the ground's level: the Steer holds any tilt left once the turn lets go)
		bike = { Lean = 12, Hold = 1, Settled = 6, Give = 2.5, Responsiveness = 12, TurnRate = 5, Torque = 40000, Lift = 0.5 },
		car = { Lean = 12, Hold = 1.5, Settled = 6, Give = 3, Responsiveness = 10, TurnRate = 3, Torque = 40000, Lift = 0.4 },
	},
}

-- 6.26, a vehicle never comes out into something (Vehicles.spawnAt: the CAR button's chauffeur, PLAY, a respawn, the
-- garages, the admin panel, a job's company vehicle, MY BIKE; shared/SpawnSpot.luau): the room it needs (its hull's
-- length × width × height, Pad wider all round, from Lift over the ground under its wheels: a curb and the road's
-- paint stay under it) must hold nothing it would collide with (the props, the crates, the counters, the walls, the
-- other cars, a player's body: not a zombie, a person of the city or an animal, which never collide with a car), and
-- the ground under its four wheels must be one plane (Spread: a wheel's ground off the others' plane at most; a crate,
-- a step) no steeper than Slope degrees (a hill road or a ramp is fine: it comes out tilted to it). From the spot asked
-- for to another one nothing may stand in the way at its hull's middle height (no car through a wall). Else the next
-- spot, in a small spiral round it (SpawnSpot.candidates): steps of its length (+ Gap) along the way it faces, of its
-- width (+ Gap) to either side (Across at most: a road's other lanes), Tries in all. None free: the spot asked for, as
-- before (on its ground's plane when it has one; a warning in Studio). It is put down Drop studs over its wheels'
-- ground. Not a ZDC RIDE scooter (its dock is its place).
Config.SpawnSpot = {
	Tries = 12, -- spots looked at, the one asked for first
	Gap = 1.5, -- studs between two spots tried, past the vehicle's length or width
	Lift = 0.6, -- studs over its wheels' ground where the room it needs starts
	Pad = 0.3, -- studs of room all round
	Spread = 0.6, -- studs at most a wheel's ground lies off the plane of the other three
	Slope = 15, -- degrees at most of that plane (the roads climb 14° at most)
	Steepest = 40, -- degrees: nothing free, the spot asked for still stands it on its ground's plane up to this steep
	Probe = 8, -- studs a wheel's ray looks down (from half of it over the spot)
	Drop = 0.5, -- studs over its wheels' ground it is put down at (it drops onto them)
	Across = 1, -- spots to either side at most (a road's other lanes; never up onto the sidewalk)
	-- 8.0.1: the folders of the workspace (a dotted path) whose parts never take a spot's room: the loot and the
	-- animals (pushed along like the zombies) and the sandbox's ground (server/SandboxWorld.luau: its mounds are big
	-- buried balls, and a box query sees a part's whole box, a cube some 480 studs wide reaching 4 – 5 studs over
	-- the meadow; the wheels' rays still stand a car on them). A path that is not there is skipped (the city).
	Pass = { "Loot", "Animals", "Sandbox.Ground" } :: { string },
}

-- 6.16, driving that feels alive (the owner: "upgrade the visuals and the feel"; only the look and the sound, the
-- driving's physics stay as they are). Accelerations in studs/s² (gravity is 196), speeds in studs/s.
Config.DriveFeel = {
	-- The body sways on its springs (shared/Suspension.luau, client/CarSway.luau: the Motor6D "BodyRoll" of a player's
	-- car, server/Vehicles.luau): it rolls out of a turn, dips its nose on the brake, squats as it pulls away and sinks
	-- as it lands. A style's Soft share (1 when not listed) scales the angles up and the springs' swing down.
	Sway = {
		Roll = 3, -- degrees the body rolls out of a turn …
		RollAt = 100, -- … at this sideways acceleration (a car on full lock at about 55 studs/s)
		RollMax = 4.5, -- degrees at most
		Dive = 2, -- degrees the nose dips on the brake …
		DiveAt = 60, -- … at this deceleration (a van's full brake is about 65)
		Squat = 1.3, -- degrees the nose lifts as it pulls away …
		SquatAt = 30, -- … at this acceleration
		PitchMax = 3, -- degrees either way at most
		Sink = 0.12, -- studs the body sinks as it lands …
		SinkAt = 150, -- … at this upward acceleration
		HeaveMax = 0.25, -- studs either way at most
		Frequency = 1.9, -- Hz: how quickly the springs swing
		Damping = 0.42, -- of the critical damping: under 1 it rocks back once after a hard stop
		Smooth = 0.08, -- seconds: your own car's accelerations are smoothed over this …
		SmoothOthers = 0.16, -- … another player's (their speed arrives over the network in steps)
		Range = 140, -- studs: the cars this close to the camera sway (a phone: DeviceBudget.range)
		Soft = {
			muscle = 0.6, rallyvan = 0.75, armored = 0.75, pickup = 0.9, highroof = 1.2, icecream = 1.2, ambulance = 1.15,
			boxtruck = 1.15, movingtruck = 1.15, livestock = 1.15, fueltruck = 1.15, freighttruck = 1.2, bus = 1.2, monster = 1.15,
		} :: { [string]: number }, -- (6.16 review: the tall ones 1.3 – 1.4 before: a box truck's roof swung 1 – 1.5 studs)
	},
	-- What the tyres throw (shared/DriveFeel.luau tyres, client/TyreFx.luau): dust off grass and dirt, snow spray in
	-- the winter and on the ice, light smoke on asphalt when they work hard (a hard brake, a sharp fast turn, a slide,
	-- a hard launch), and skid marks then.
	Tyres = {
		Range = 110, -- studs: the cars this close to the camera throw something …
		Cars = 5, -- … this many of them at most (yours first; a phone: yours only)
		Dust = { Rate = 28, From = 8, Full = 45 }, -- particles a second per rear wheel, by the speed (From … Full)
		Snow = { Rate = 36, From = 6, Full = 40 },
		Smoke = { Rate = 24, From = 0.25 }, -- on asphalt, by the strain, from this strain
		Brake = { From = 38, Full = 62 }, -- the strain of braking (deceleration) …
		Corner = { From = 70, Full = 110 }, -- … of a fast turn (sideways acceleration) …
		Slide = { From = 5, Full = 14 }, -- … of a slide (sideways speed: the ice, the snow) …
		Launch = { From = 30, Full = 45, Below = 14 }, -- … of a hard launch (acceleration, under Below studs/s)
		MinSpeed = 14, -- the brake and the turn strain only from this speed
		Lite = 0.5, -- a phone's share of the particles
	},
	-- Skid marks: dark thin strips behind the wheels on asphalt while the strain is at least From; each fades out
	-- from FadeFrom to Life seconds. Count of them at most (the oldest is used again; a phone: Lite of them).
	Skids = { From = 0.4, Count = 160, Lite = 0.35, FadeFrom = 4.5, Life = 7.5, Step = 0.8, Length = 3.5, Width = 0.5, Opacity = 0.62 },
	-- A hard hit (client/CrashFx.luau): your car or a car near you loses at least From of its speed in a blink (Full:
	-- the hardest); a spark burst of up to Sparks (a phone: half), a metal thunk, and on top of CameraRig's ram shake
	-- (Config.LivingCity.Camera Ram) a little more, Shake at the hardest. Scraping a wall at Scrape.Speed or more
	-- throws sparks (Scrape.Rate a second) and trembles the camera a touch (Scrape.Shake a second).
	Crash = { From = 24, Full = 60, Sparks = 34, Shake = 0.25, Range = 120, Scrape = { Speed = 14, Rate = 70, Shake = 0.5, Reach = 0.9 } },
	-- The engine's note (client/Sounds.luau, shared/DriveFeel.luau engine): a little gearbox (Gears gears over the top
	-- speed, Shift of hysteresis), the pitch from Idle at a stand to Top at the top of the last gear, a touch higher on
	-- the throttle (Load) and lower as it coasts (Coast), the volume by the speed and the throttle. Styles: a style's
	-- class (a van when not listed). (A bike's freewheel and a scooter's hum stay as they were.)
	Engine = {
		Classes = {
			car = { Idle = 0.8, Top = 1.8, Gears = 5, Volume = 0.52 },
			van = { Idle = 0.7, Top = 1.5, Gears = 4, Volume = 0.52 },
			truck = { Idle = 0.52, Top = 1.18, Gears = 5, Volume = 0.58 },
			monster = { Idle = 0.6, Top = 1.38, Gears = 4, Volume = 0.6 },
		} :: { [string]: { Idle: number, Top: number, Gears: number, Volume: number } },
		Styles = {
			muscle = "car", pickup = "car", rallyvan = "car", boxtruck = "truck", freighttruck = "truck", bus = "truck",
			movingtruck = "truck", livestock = "truck", fueltruck = "truck", armored = "truck", monster = "monster",
		} :: { [string]: string },
		Shift = 0.03, -- of the top speed: a gear changes this far past its edge (no hunting at the edge)
		Load = 0.05, -- pitch added on the throttle
		Coast = 0.05, -- pitch taken off without it
		Rev = 0.55, -- the share of the rev range a held throttle reaches at a stand (stuck, the back open)
		Follow = 12, -- 1/s: how quickly the sound follows its pitch (a shift is heard as one)
	},
	-- Speed lines (client/SpeedLines.luau): thin streaks at the screen's edges from From of the top speed (full at
	-- Full); a scooter's or a bike's (TwoWheels) from a lower share. Count of them (a phone: Lite of them); none with
	-- reduced motion.
	SpeedLines = { From = 0.8, Full = 1.05, TwoFrom = 0.6, TwoFull = 0.95, Count = 16, Lite = 0.5, Opacity = 0.55 },
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
		van = "horn_van", zdcvan = "horn_van", courier = "horn_van", highroof = "horn_van", armorvan = "horn_van", rallyvan = "horn_van",
		icecream = "horn_van", ambulance = "horn_van", sprinter = "horn_van", -- (8.0: the sandbox's ZDC Sprinter)
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
	-- 7.1, the move's sounds (art/audio/sfx4.ogg): client/MoveSounds.luau hears them from the move's state, its result
	-- and your MoveCarry (shared/SoundPlan.luau moveCues, carryCue, dragged, resultCue). Volumes 0 … 1.
	Move = {
		StartWithin = 20, -- a move's first state plays move_start only this many seconds into it (not on a rejoin)
		Start = 0.7, -- move_start
		Siren = 0.6, -- the horde's air-raid siren, far off
		Ramp = 0.75, -- the truck's back opening …
		RampShut = 0.88, -- … and shutting (this pitch)
		Door = 0.6, -- the house's front door: going in …
		DoorOut = 1.08, -- … and out (this pitch)
		Load = 0.8, -- a piece you carried into the truck …
		LoadCrew = 0.35, -- … a crew mate's
		Break = 0.85, -- a piece of yours broken (glass_break if fragile, else heavy_drop) …
		BreakCrew = 0.45, -- … a crew mate's
		Jolt = 0.12, -- a piece in your hands losing this share of its condition at once (a fall, a hard knock) …
		JoltVolume = 0.6, -- … thuds (heavy_drop)
		Pickup = 0.7, -- furniture_pickup
		PutDown = 0.7, -- furniture_putdown
		Box = 0.6, -- a box picked up / put down (cardboard_box)
		PutDownWait = 0.6, -- your hands empty: the move's next state says where it went (into the truck: truck_load, else
		-- the put-down), at most this many seconds later (the server sends it 0.25 – 0.45 s after a change)
		Gate = 0.7, -- the Wall's gate opening as the move is delivered (the result card plays its jingle)
		Slip = 0.8, -- a heavy piece slipping from your hands (MoveSounds.slipped, for the grip's UI) …
		SlipQuiet = 1.5, -- … and no put-down and no heavy_drop (the slip's damage) for this many seconds after (grip_slip has its thud)
		Scrape = 0.5, -- a two-person piece dragged alone (wood_scrape_loop), while you move faster than …
		ScrapeFrom = 1.2, -- … studs a second
		ScrapeBlend = 0.35, -- the share of the way to its volume every Tick
		Tick = 0.1, -- seconds between the looks at the drag
	},
	-- 8.1 SANDBOX, the sandbox's own sounds (art/audio/sfx4.ogg's 8.1 part; until it is up their stand-ins, SoundSheet
	-- Fallback). Where you are (shared/SoundPlan.luau sandboxPlace): "outdoors" in the village, in a "warehouse" (8.3:
	-- its level's building, WarehouseLayout.site) or in the "house" (inside the Old Farmstead: the move's interior, its
	-- state's inside, or the farmstead's own box). client/SoundScape.luau blends the loops (SoundPlan.sandboxAmbience:
	-- the city's day and night never play here), plays the countryside's far sounds and sets the room's echo;
	-- client/SandboxSounds.luau the rest. Volumes 0 … 1.
	-- 8.9 in place of the Alps (no cowbells, no alpine meadow); 9.4 the countryside (design/countryside/plan.py; no
	-- village: no chapel's bell): outdoors the fields (birds and larks over them, a breeze), the D5 motorway's far hum from
	-- the east, now and then a woodpecker in the forest, a dog far off and a tractor on the fields. Each is a sound
	-- wanted on the next sheet; until a sheet has it, a
	-- sound of the sheets up now stands in (shared/SoundPlan.luau SandboxStandIns). Indoors and in a warehouse as before.
	Sandbox = {
		Fields = 0.24, -- the fields outdoors (amb_fields; its stand-in sfx4's amb_alpine: a breeze, finches, a lark) …
		FieldsStandIn = 0.09, -- … until sfx4 is up the stand-in's own, sfx2's wind: a breeze only
		FieldsIndoors = 0.3, -- … × this in a warehouse (through its open roller door; the D5's hum too)
		Warehouse = 0.22, -- amb_warehouse in a warehouse: the lights' hum, the hall's air, the roof ticking …
		WarehouseStandIn = 0.12, -- … until sfx4 is up its stand-in, sfx2's hum
		Room = 0.4, -- amb_room in the house: a quiet room tone and a clock (no stand-in: silent until sfx4 is up)
		-- SoundService.AmbientReverb by place (an Enum.ReverbType's name; a place not here: NoReverb), only while you are
		-- in the game and SOUND is not all off
		Reverb = { warehouse = "Room" } :: { [string]: string },
		-- The D5's far hum (amb_motorway): a 3D loop on the motorway's middle line (SandboxMap's landmark "d5": X, from
		-- Z0 to Z1) at its point nearest you, Y up, so it always comes from the east; Volume within Near
		-- studs, fading out (Roblox's inverse taper) to nothing at Range. Outdoors; × FieldsIndoors in a warehouse.
		Motorway = { X = 360, Z0 = -680, Z1 = 760, Y = 6, Volume = 0.35, Near = 80, Range = 1900 },
		-- Now and then outdoors, each on its own clock (Gap: seconds between two, a random pick), 3D (you hear where):
		-- Volume within Near studs, nothing past Range.
		--   Woodpecker  a woodpecker drumming in the forest (woodpecker_far, one drum) from its middle (SandboxMap's
		--             wood "forest": X, Z; Y up in the crowns), Drums drums Every s apart
		--   Dog       a dog barking far off (dog_far), Far studs (a random pick) a random way round you
		--   Tractor   a tractor on the fields (tractor_far, a loop), Far studs a random way round you at the middle of
		--             its pass: it drives across your view at Speed studs a second for Seconds s, fading in and out
		--             over Fade s
		Woodpecker = { X = -960, Z = -560, Y = 26, Gap = { 90, 200 } :: { number }, Drums = 3, Every = 0.9, Volume = 0.7, Near = 120, Range = 1500 },
		Dog = { Gap = { 45, 110 } :: { number }, Far = { 90, 170 } :: { number }, Volume = 0.8, Near = 30, Range = 260 },
		Tractor = { Gap = { 80, 170 } :: { number }, Far = { 150, 240 } :: { number }, Seconds = 16, Fade = 4, Speed = 5, Volume = 0.9, Near = 40, Range = 360 },
		Display = 0.7, -- a piece put on a stand (stand_display: a soft thunk and a sparkle)
		TakeDown = 0.6, -- … taken down (stand_takedown)
		Sold = 0.7, -- a sale (sale_register: the till's ka-ching)
		Stored = 0.65, -- a trip's pieces into your warehouse (stored_fanfare: a small fanfare) …
		StoredQuiet = 2.5, -- … not this many seconds after the move's result card (it plays its own jingle)
		Income = 0.14, -- the stands' income coming in (coin, sfx2's: a soft clink) …
		IncomeGap = 10, -- … at most once every this many seconds, not while the warehouse's window is open and not …
		SoldQuiet = 2, -- … this many seconds after a sale (its money comes in too)
		Slide = 0.75, -- the ZDC Sprinter's sliding door rolling open and slammed shut (van_slide_open / _close) …
		SlideRange = 90, -- … heard this many studs from the camera
		Step = 0.55, -- your foot onto a Sprinter's rear or side step (van_step_up) …
		StepGap = 0.8, -- … at most every this many seconds
		-- 8.3, the 8.2 features' feedback (the existing sheets only; shared/SoundPlan.luau feedbackOf / feedbackCues /
		-- slot, client/SandboxSounds.luau): the stings play one after the other, never over each other (the trip home's
		-- fanfare, then the book's chime, then a milestone's fanfare); the same one again only after its Gap s; one that
		-- would wait longer than FeedbackWait s behind the others is left out.
		Discovery = 0.5, -- a piece new in your collection book (ding: a bright bell, a little higher) …
		DiscoveryGap = 2,
		Milestone = 0.6, -- a book milestone paid (level_up: the bells' fanfare) …
		MilestoneGap = 4,
		TaskDone = 0.6, -- a task done (task_done) …
		TaskDoneGap = 1.5,
		Claimed = 0.55, -- a task's reward claimed (cash: the money's ka-ching) …
		ClaimedGap = 0.6,
		Fill = 0.38, -- ⭐ FILL BEST: a few soft stand clicks (stand_display, quieter, each a little higher) …
		FillClicks = 3, -- … at most this many (fewer when fewer pieces went up) …
		FillEvery = 0.13, -- … this many seconds apart …
		FillGap = 2,
		FillQuiet = 1.5, -- … and the state after it plays no stand_display of its own for this many seconds
		BulkSold = 0.9, -- 💰 SELL…'s sale: the till once (sale_register), louder than one piece's …
		BulkKa = 0.5, -- … the old ka-ching (cash) on top of it …
		BulkKaAt = 0.12, -- … this many seconds in …
		BulkGap = 1.5,
		FeedbackWait = 4.5,
	},
	-- 8.9, the newest features' own sounds (art/audio/sfx5.ogg; until it is up a stand-in from the older sheets or
	-- silence: SoundSheet.Fallback). shared/SoundPlan.luau Events names each (the event → its sound, volume, gap);
	-- client/SandboxSounds.luau event plays one. UI feedback: soft. Volumes 0 … 1.
	NoticeWait = 0.08, -- s a Notice's notify waits (client/Sounds.luau): a sound of its own answers it instead (an
	-- answer awaited from the server, a trade's: SandboxSounds' Sounds.answered), never both
	Danny = {
		-- 8.5 the clipboard (client/DannyOrders.luau: your character's ClipboardHeld)
		ClipOut = 0.5, -- taken out: a paper rustle and the clip (clip_out) …
		ClipAway = 0.42, -- … put away (clip_away) …
		ClipGap = 0.25, -- … at most every this many seconds
		Give = 0.55, -- a piece onto his list (pen_tick: ticked on the paper) …
		TakeBack = 0.5, -- … off it again (pen_untick: crossed off)
		Nope = 0.5, -- a pick, an order or the clipboard refused (soft_nope; its stand-in the notice's own notify, as loud)
		-- 8.6 his orders and his whistle (client/MoveHelperCard.luau, client/DannyBubble.luau)
		Ack = 0.5, -- an order of yours he took (order_chirp)
		Whistle = 0.55, -- his bubble turned orange because he needs you (danny_whistle; silent until sfx5 is up: his
		-- "needs you" toast pings already) …
		WhistleGap = 8, -- … at most every this many seconds …
		WhistleFor = { needs = true } :: { [string]: boolean }, -- … for these of his alerts (shared/MoveHelperBrain.luau Doing)
		-- an answer awaited from the server (client/SandboxSounds.luau await: a piece given or taken back, an order, the
		-- clipboard out): its outcome looked at every Poll s, given up Answer s after it was sent; its Notice came and
		-- nothing changed Grace s later: refused (the nope)
		Poll = 0.05,
		Answer = 2,
		Grace = 0.3,
	},
	-- 8.7 trading between players: SoundPlan.Events' trade_sold, trade_offer and trade_price, the hook the trade code
	-- calls (client/SandboxSounds.luau event); each answers the Notice that comes with it (its notify left out)
	Trade = {
		Sold = 0.6, -- your piece sold to a player (coin_kaching: the coins' ka-ching)
		Offer = 0.55, -- a player's offer for your piece (offer_ding: a desk bell's ding)
		Price = 0.45, -- a FOR SALE price set (price_paper: a tag flicked and written on)
		Gap = 0.4, -- s before the same again
	},
	-- 8.8 the auction (client/AuctionUi.luau, SoundPlan.auctionCues: while its window is open; your own lot's bell
	-- anywhere)
	Auction = {
		Bid = 0.4, -- the price went up: a bid (bid_tick) …
		BidGap = 0.12, -- … at most every this many seconds
		Gavel = 0.6, -- the lot on the podium closed: the gavel (gavel_knock) …
		Sold = 0.45, -- … and "sold!" (sold_bell), BellAt s after it …
		SoldMine = 0.65, -- … louder when it was yours or you bought it
		BellAt = 0.3,
	},
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
	FirstClearXp = 2.55, -- the XP of the first clear × this (6.8: 1.5 before; six missions a chapter carry the same road; 7.x: 2.5 before, the loads capped at the ZDC Van's four slots give fewer pieces: the story still carries you to level 15)
	-- 6.8, replays (shared/Missions.luau replayPay / replayXp, server/Jobs.luau): a mission you have done before pays
	-- this share of the job's pay and of its XP, and nothing else (the first clear's reward, the chapter's reward and
	-- the unlocks come once). A crew member's share follows their own record.
	ReplayPay = 0.25,
	ReplayXp = 0.25,
	-- Co-op missions (MissionDef.coop): every crew member besides the owner adds this share of the pay (for everyone)
	-- and this share of the enemies' health (6.15: their number is the mission's own, Fixed below: the same for a crew).
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
		gunner = { name = "SHOTGUN SEAT", icon = "🎯", description = "Gunners wait on the route; kills from the passenger seats pay triple", pay = 1.1 },
		spotless = { name = "SPOTLESS", icon = "💎", description = "The cargo must arrive in good shape: below 60 % the mission fails", pay = 1.4 },
		hunted = { name = "HUNTED", icon = "🏴", description = "Bandit roadblocks wait on the route", pay = 1.35 },
		pair = { name = "PAIR LIFT", icon = "🤝", description = "These pieces only move with two of you carrying together", pay = 1.3 },
		switches = { name = "TWIN SWITCHES", icon = "🎛", description = "Two levers far apart must be pulled at the same moment to open the gate", pay = 1.25 },
	} :: { [string]: { name: string, icon: string, description: string, pay: number } },
	SpotlessFail = 0.6, -- spotless: the mission fails below this condition
	QuietCost = 0.06, -- quiet: condition lost per shot
	LiftSlowSpeed = 4.5, -- lift: walking speed carrying alone (with a crew mate within LiftHelpRange: normal)
	LiftHelpRange = 10,
	GunnerKillBonus = 3, -- gunner: a passenger's kill pays KillBonus × this
	-- hunted: the cargo is wanted this many times as much (the start's "Every bandit in town wants this cargo!"; 6.15:
	-- a mission's bandits are its plan's roadblocks, Fixed.Roadblocks, never random chases)
	HuntedBoost = 2.5,
	DefendRadius = 45, -- defend: stay within this of the receiver
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
	-- 6.15, the fixed missions (the owner: "I want them to be about a number of zombies, and you have to complete it, so
	-- the mission is always the same, not random"): every mission has the same route and the same enemies at the same
	-- spots (shared/MissionPlan.luau plans them, server/MissionEnemies.luau puts them in the world); it is done when the
	-- cargo is delivered AND every one of them is dead. No random waves, strays, chases or roadblocks on a mission.
	Fixed = {
		-- How many. The zombies at the stops: Stops[tier], PerStop more for every stop past two, × (1 + ChapterGrow a
		-- story chapter after the first: the DUO chapter counts as the one at its level), × Guarded on a HOT ZONE mission;
		-- shared out by Weight (the last drop's horde the biggest; HOT ZONE: the other stops × GuardedStop) and by the
		-- tier's Kinds (largest remainders: the same every time).
		Stops = { 8, 11, 14, 18 },
		PerStop = 2,
		ChapterGrow = 0.06,
		Weight = { Drop = 2, Pickup = 1, OnTheWay = 0.6 },
		Guarded = 1.4,
		GuardedStop = 1.6,
		Kinds = {
			{ walker = 0.8, runner = 0.2 },
			{ walker = 0.65, runner = 0.3, brute = 0.05 },
			{ walker = 0.5, runner = 0.3, brute = 0.12, soldier = 0.08 },
			{ walker = 0.4, runner = 0.33, brute = 0.15, soldier = 0.12 },
		} :: { { [string]: number } },
		-- 6.24, the special zombies, still the same every time: the runners' weight in Kinds × (1 + RunnerGrow a story
		-- chapter after the first); Bloaters[chapter] of the stops' walkers are bloaters (+ FinaleBloaters on a chapter's
		-- last mission), one a stop from the last drop back to the first pick-up and round again (the total stays).
		RunnerGrow = 0.06,
		Bloaters = { 0, 1, 1, 1, 2, 2, 2, 3, 3, 3 } :: { number },
		FinaleBloaters = 1,
		-- HUNTED: bandit roadblocks at fixed points of the route (Roadblocks[tier] × the mission's banditBoost, at most
		-- RoadblocksMax), RoadblockSize[tier] bandits each (× the chapter's growth; from ★★★ one of them a gunner).
		Roadblocks = { 1, 2, 2, 2 },
		RoadblocksMax = 4,
		RoadblockSize = { 2, 3, 3, 4 },
		-- SHOTGUN SEAT: Gunners[tier] gunners posted by the road (× the chapter's growth), at GunnerPosts points at most.
		Gunners = { 1, 2, 2, 3 },
		GunnerPosts = 2,
		-- HOLD OUT: Defend[tier] zombies (× the chapter's growth) come at the last drop in #DefendSplit waves, shared by
		-- these weights (the last the biggest); wave n comes when the hold-out clock is (n − 1) / waves through.
		Defend = { 5, 8, 10, 12 },
		DefendSplit = { 2, 3, 4 },
		-- Every mission's enemies in all: at most Max (every group shrunk alike), at least Min.
		Max = 40,
		Min = 6,
		-- Where. A stop's group stands on the road by its circle: along the road up to SpreadAlong studs either way (more
		-- for a bigger group), out to SpreadOut; a yard's group in a ring Ring[1] … Ring[2] (+ RingPer a zombie, at most
		-- RingMax) round it. A route point (a roadblock, a gunner post) lies on the road at an even share of the route,
		-- at least FromStop studs from every stop; HOLD OUT's waves come from DefendRing studs round the last drop.
		SpreadAlong = 40,
		SpreadOut = 14,
		Ring = { 10, 24 },
		RingPer = 1.2,
		RingMax = 45,
		FromStop = 140,
		DefendRing = { 60, 100 },
		-- In the world (server/MissionEnemies.luau). One comes when somebody of the crew (alive, out of the safe zone) is
		-- within SpawnRange of its spot (a HOLD OUT wave's: once let loose too); one nobody of the crew is within
		-- ParkRange of goes back to waiting at its spot (alive again when they come back: the alive cap follows the crew;
		-- Zombies' own despawn leaves them alone). MaxAlive of a mission alive at once (the rest come as those die), Batch
		-- a tick at most. Reserve: while a mission runs, every other enemy (a board job's waves, the admin's) stops this
		-- many short of Config.Horde.MaxTotal (the roamers and the live events stop shorter already).
		SpawnRange = 230,
		ParkRange = 300,
		MaxAlive = 18,
		Batch = 6,
		Reserve = 15,
		-- A spot inside something (a wall, a bunker, the rock) is not used: the spot halfway to its anchor, else round the
		-- anchor (the stop's circle, the road), else (a HOLD OUT wave's) the nearest road. Delivered (clearing), one that
		-- has not moved StuckMove studs nor been hit for StuckTime s while it should (somebody close, or away from its
		-- spot; a bandit: it sees nobody) goes back to waiting and comes again by its anchor.
		StuckTime = 20,
		StuckMove = 3,
		-- They guard their spot: a zombie goes after somebody within Aggro of it (a bandit or a gunner: its range + 40)
		-- while they are within Leash of its spot, else it walks back; hit from further, it goes after them within its
		-- leash for AlertTime s.
		Aggro = 90,
		Leash = 150,
		AlertTime = 8,
		-- The clock: TimePerEnemy s more for every enemy of the mission (to clear them, the drive back to a horde you
		-- passed included: 6.15 review, 3 s was tight); a mission started far from its first stop gets the longer drive
		-- too (the pay stays the mission's own).
		TimePerEnemy = 5,
		-- Delivered with enemies left: the HUD's marker follows the nearest of them once it moved Retarget studs.
		Retarget = 10,
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
		-- (7.x: every courier has the ZDC Van, so only a save still loading sees them.)
		NeedsVehicle = "Needs your ZDC Van: press CAR and it comes to you.",
		NeedsVehicleButton = "🚐 CALL YOUR VAN",
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
		NeedsBike = "Needs a bike: Dead End Motors sells them at its BIKES counter from level 2 (the Rusty Bike is the cheapest).",
		NeedsBikeButton = "🚲 NEEDS A BIKE",
		RideBike = "Bike jobs are ridden: MY BIKE on your phone brings your bike (your car stays where it is).",
		RideBikeButton = "🚲 RIDE YOUR BIKE",
		NeedsCar = "You're on your bike: car jobs need your ZDC Van. CALL CAR on your phone.",
		NeedsCarButton = "🚐 CALL YOUR VAN",
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
			waveKinds = { walker = 0.62, runner = 0.3, brute = 0.05, bloater = 0.03 },
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
			waveKinds = { walker = 0.4, runner = 0.33, brute = 0.12, soldier = 0.1, bloater = 0.05 },
			kinds = { walker = 0.22, runner = 0.2, bandit = 0.35, gunner = 0.1, brute = 0.1, bloater = 0.03 },
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
			waveKinds = { walker = 0.24, runner = 0.35, brute = 0.15, soldier = 0.18, bloater = 0.08 },
			kinds = { walker = 0.12, runner = 0.15, soldier = 0.15, bandit = 0.3, gunner = 0.15, brute = 0.1, bloater = 0.03 },
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
	-- 7.x (one car): never more pieces than the ZDC Van's slots (server/Jobs.luau caps every car job at
	-- Economy.maxCapacity of Config.CompanyVan.Car: 4); ★★★★'s bulk is +1 – 2 now. The Freight Run is retired.
	EasyMaxPieces = 2,
	BulkChance = { 0, 0.2, 0.45, 0.6 } :: { number },
	BulkExtra = { { 0, 0 }, { 1, 1 }, { 1, 2 }, { 1, 2 } } :: { { number } },
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
	-- 6.14, the shift's pay (shared/Shift.luau, server/Shift.luau; the HUD's SHIFT chip, client/GrindChips.luau): every
	-- job finished and paid to you (a board job, on foot, by bike, an employer's, a mission; a run of stacked orders once,
	-- at its last order; a crew member there with you counts their own; not a road event's add-on) counts one, and Jobs
	-- of them in one go pay the shift: Money (rounded to MoneyStep) and Xp, both × (1 + LevelScale × (level − 1)) (level
	-- 1: $120 and 100 XP; level 7: $300 and 250; level 15: $540 and 450), then a new shift starts at 0. A failed job
	-- neither counts nor resets it (the streak punishes that already); more than IdleReset seconds without a job finished
	-- start it over (6.14 review: 20 minutes, a stacked run of several orders takes a while). Per play session, never
	-- saved.
	Shift = {
		Jobs = 5,
		Money = 120,
		Xp = 100,
		LevelScale = 0.25,
		MoneyStep = 5,
		IdleReset = 1200,
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
	-- 6.12.8, the NEXT UP queue (server/JobQueue.luau, shared/JobQueue.luau; the owner: "once I take a job I can't add
	-- more … I want to add even all of them"): the board's + QUEUE (a run that is full, a job that does not stack: a
	-- ★★★ / ★★★★ car job, another transport) and ADD ALL put ordinary board jobs in a line of Max at most. A queued
	-- job is the offer as it was (its pay); its clock starts when it starts (taken from where you are then). The next
	-- one starts on its own when you have no job, or joins the run when it stacks and fits (the same paths as ACCEPT
	-- and + ADD): after a drop, an order done or lost, the end of a run, and every CheckEvery s (a vehicle switched).
	-- One that could not start waits RetryAfter s before it tries again. Never saved (gone when you leave); kept
	-- through a death. Missions, specials, employers' jobs, the Freight Run, DUO, the tutorial's and the paper round
	-- never queue. Review: with no job running the next one starts StartDelay s after "NEXT UP in 4 s: …" (PAUSE or ✕
	-- cancels it; joining a run that goes on is at once); a failed delivery, a lost order, a mission or an employer's
	-- job PAUSE the queue until RESUME; CLEAR ALL empties it; a job whose place is shut by its start is dropped.
	Queue = {
		Max = 6,
		CheckEvery = 1.5,
		RetryAfter = 8,
		StartDelay = 4,
	},
	-- 6.14, the GOLDEN ORDERS (server/SpecialOrders.luau decides with shared/SpecialOrders.luau; the owner: "a bit MORE
	-- grind, but a FUN grind"): every Every s (the board's refresh) a courier from Level on has Chance of a GOLDEN
	-- ORDER on their board, one at a time (none while one is on the board, in NEXT UP or on the run). It is an ordinary
	-- delivery (a LONG HAUL) of the transport you use: on your bike a bike run; with a car of your own one of your two
	-- hardest open car tiers (the hardest TopTier of the time); else on foot. It pays Pay × the offer's pay, gives Xp ×
	-- the XP and stays Seconds on the board (and in NEXT UP) unless you take it: a countdown, then it is gone. More
	-- danger: a car run's waves × Waves[tier] (the way WANTED makes them: bigger, more often, more of them alive) and
	-- the bandits Bandits[tier] times as often where the tier has bandits; on foot or by bike its own lighter danger
	-- (Light: the stray walkers Every × as far apart, Chance more likely, Max more of them alive, Runner of them runners).
	-- It works with the crew like any job (the shares, the XP).
	Golden = {
		Level = 3,
		Every = 120,
		Chance = 0.15,
		Seconds = 180,
		Pay = 3,
		Xp = 2,
		TopTier = 0.6,
		Waves = { 1.6, 1.8, 2, 2.2 } :: { number },
		Bandits = { 1, 1.75, 2, 2.25 } :: { number },
		Light = { Every = 0.5, Chance = 0.3, Max = 1, Runner = 0.4 },
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

-- 6.0, the courier's look on foot (6.24: client/GaitPose.luau, server/KitWear.luau): the plastic bag (Config.Kit BagKit)
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
		Stride = 13, -- studs run per full cycle (two steps): the cadence follows the speed (6.8 review: on the stock 2-stud
		-- leg; shared/Gait.luau scales it by each body's own leg). 6.12.6, the slow-mo
		-- sprint: 7 → 13, big strides at about half the old cadence (2 cycles a second at 28 studs / s)
		Hang = 0.45, -- 6.12.6: the cycle slows by this share in the flights and hurries through the steps (RunCycle.hang)
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
	BagUnlock = "Sprint with more of your deliveries: ZDC Bags at the depot has the {name} for you now, {room} pieces in it, {price} for this game. It's on your GPS.", -- (6.23: bags for each game)
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
	-- Mouth: each bag's opening on its pivot (shared/KitArt.luau's frame: the grip at the origin, hanging -Y):
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

-- 6.14, get ready for the mission (the owner: "jobs are the daily work: you grind, you save up for something, and then
-- you can progress in the mission"). shared/Readiness.luau picks the next story mission and what it needs; the phone's
-- NEXT MISSION tile and its READY CHECK (client/ReadyCheck.luau), the HUD's savings line under the cash
-- (client/SavingsLine.luau) and the job result's "to go" line show it.
--   MaxRows     the READY CHECK's rows at most: every required one, then the recommended ones (those not done first)
--   HardTier    a mission of this danger tier or more recommends a vest and a two-handed gun
--   Medkits     medkits worth carrying into any mission (recommended)
--   RepairKits  repair kits worth carrying into a mission you drive (recommended once you own a car)
--   Sound       the sting of the one-time "Ready for …" toast (client/Sounds.luau)
--   LineHeight  px at scale 1: the HUD's savings line, under the cash line (the left column grows by it while it shows)
Config.Readiness = {
	MaxRows = 5,
	HardTier = 3,
	Medkits = 1,
	RepairKits = 1,
	NotGoals = { medkit = true, repair = true, bag = true } :: { [string]: boolean }, -- rows that never become the savings goal
	Sound = "task_done",
	LineHeight = 20,
}

export type JobTypeDef = {
	id: string,
	name: string,
	description: string,
	vehicle: string?, -- the employer lends this car for the job
	employer: string?, -- taken at the employer's place (Config.Employers), not on the job board
	pickups: number, -- pick-up stops (0 = the vehicle starts loaded)
	pickupAt: string?, -- the pick-up is at this place (shared/Map.luau Places), else around you (6.15: a mission's: a fixed address, shared/MissionPlan.luau)
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
-- 7.x (one car, Config.CompanyVan): no job lends a company vehicle any more (no `vehicle`): every one goes in your ZDC
-- Van and its pieces fit its four slots. The School Run, the Ice Cream Route and the Ambulance Run board their people
-- or sell from it (no slots); the Horse Transport became Feed and Tack (horses do not fit a van: carried sacks); the
-- Freight Run (pallets: the ZDC Van takes none) is retired.
Config.JobTypes = {
	{
		id = "schoolrun",
		name = "School Run",
		description = "Pick the kids up at three homes and bring them to Sunny Hill School in your ZDC Van.",
		employer = "school",
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4 (7.x: the car jobs' level)
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
		description = "Load ammo at the Harbor Docks and drive it in your ZDC Van through the tunnel to the base.",
		level = 7, -- (3.2: the armored truck it earned could carry a car gun; 7.x: the army's bonus)
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
		description = "Load up at Frosty's and sell ice cream from your ZDC Van at 4 stops. Hold still while the kids buy.",
		employer = "icecream",
		pickups = 1,
		pickupAt = "frosty",
		drops = 4,
		dropAt = nil,
		loadTime = 3,
		unloadTime = 3,
		payPerStop = 60,
		tier = 2,
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4 (7.x: the car jobs' level)
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
		description = "Load a family's furniture into your ZDC Van at their house and unload it at their new home.",
		employer = "movers",
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4 (7.x: the car jobs' level)
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
		description = "Load fresh food into your ZDC Van at the Old Farm and bring it to two markets in the city.",
		employer = "farm",
		level = 9, -- 5.0: the Muscle Car's level then (4.x: 8)
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
		id = "horses", -- (the id stays: 7.x turned the Horse Transport into Feed and Tack, horses do not fit a van)
		name = "Feed and Tack",
		description = "Walt's mares went to the Riverside Riding School. Load their feed sacks and saddles at Silver Spur Ranch into your ZDC Van and bring them over.",
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
		cargo = "Feed and Tack",
		pickupLabel = "LOAD THE FEED AT",
		dropLabel = "DELIVER THE FEED TO",
		load = "carry",
		unload = "carry",
		items = 4,
		itemKind = "sack",
		giver = "Jesse, the ranch hand",
		receiver = "Emma, the riding instructor",
	},
	{
		id = "fuelrun",
		name = "Fuel Run",
		description = "Load fuel barrels into your ZDC Van at the Harbor Fuel Depot and refill the Gas Station on the North Highway.",
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
		description = "Load sacks of cash at the First Zombie Bank into your ZDC Van and bring them to the Military Base vault. Every bandit in town wants this cargo.",
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
		description = "A patient is waiting at their home. Pick them up in your ZDC Van and rush them to the City Clinic before it is too late.",
		employer = "clinic",
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4 (7.x: the car jobs' level)
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
		level = 4, -- 5.0: a company vehicle (or your own car) needs level 4 (7.x: the car jobs' level)
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
	reward: string, -- what you get after `needed` jobs, in words (7.x: "bonus"; 2.x – 6.x their vehicle, gone with the cars)
	needed: number, -- jobs done for them before they give it to you
	bonus: number?, -- 7.x: the money of that bonus (once; Config.CompanyVan.Bonus, server/Jobs.luau)
	pitch: string,
	weapon: string?, -- a gun they give you (Config.Weapons, earned = this employer) …
	weaponAt: number?, -- … after this many jobs
	person: string, -- who runs it (the R15 NPC at their board)
}

-- People who run something in the world. Work for them: after a few jobs their vehicle was yours (until 7.x); now they
-- pay a bonus once (`bonus`), and the army and the ranch still give their gun.
Config.Employers = {
	{ id = "school", name = "Sunny Hill School", icon = "🏫", jobType = "schoolrun", reward = "bonus", bonus = 1500, needed = 3, person = "Principal Helen", pitch = "Our bus driver ran away. Drive the kids to school!" },
	{ id = "army", name = "Military Base", icon = "🪖", jobType = "armysupply", reward = "bonus", bonus = 3000, needed = 4, weapon = "carbine", weaponAt = 2, person = "Captain Maria", pitch = "We need ammo from the docks. Bring it through the tunnel." },
	{ id = "icecream", name = "Frosty's Ice Cream", icon = "🍦", jobType = "icecream", reward = "bonus", bonus = 1500, needed = 3, person = "Frosty", pitch = "People still want ice cream. Sell it for us!" },
	{ id = "movers", name = "Big Move Movers", icon = "🚚", jobType = "moving", reward = "bonus", bonus = 1500, needed = 3, person = "Dana, the boss", pitch = "Families are getting out of town. Move their things." },
	{ id = "farm", name = "Old Farm", icon = "🌽", jobType = "farmrun", reward = "bonus", bonus = 2500, needed = 3, person = "Old Man Jed", pitch = "The city is hungry. Take my food to the markets." },
	{ id = "ranch", name = "Silver Spur Ranch", icon = "🐴", jobType = "horses", reward = "bonus", bonus = 2000, needed = 4, weapon = "revolver", weaponAt = 2, person = "Walt, the rancher", pitch = "My mares went to the riding school. Their feed and saddles still need hauling: keep the bandits off them." },
	{ id = "clinic", name = "City Clinic", icon = "🏥", jobType = "ambulance", reward = "bonus", bonus = 1500, needed = 3, person = "Doctor Ellie", pitch = "The phones never stop ringing. Your van is our ambulance now: bring the patients in alive." },
	{ id = "gas", name = "Gas Station", icon = "⛽", jobType = "fuelrun", reward = "bonus", bonus = 2000, needed = 3, person = "Dolly, the owner", pitch = "My pumps are dry. Bring fuel barrels from the harbor depot." },
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
		AdminSandbox = 4, -- 8.0 SANDBOX: the admin panel's SANDBOX buttons (server/Admin.luau "sandbox", shared/SandboxAdmin.luau)
		Zip = 4, -- 6.10 review: a zip line's grab (a jump on the start platform) and letgo (server/ZipLines.luau)
		Tasks = 4, -- 6.12: the TASKS app's "open" and CLAIM (server/Tasks.luau)
		Style = 4, -- 6.12: the STYLE app's buy / wear / unwear (server/StyleWear.luau)
		JobQueue = 4, -- 6.12.8: the board's + QUEUE, ADD ALL and NEXT UP's ✕ (server/JobQueue.luau)
		ClientError = 0.05, -- 6.13: a client's script error (its script and line): one every 20 s at most (server/Analytics.luau)
		CrateDown = 4, -- 6.15: the PutDown remote (the touch PUT DOWN) while you carry a supply drop's crate (server/LiveEvents.luau)
		Skills = 4, -- 6.20: the SKILLS tab's +1 POINT and RESET (server/Skills.luau)
		Moving = 6, -- 7.0: the Moving remote: the contract card's START, GIVE UP, the item list (server/Moving.luau)
		MoveLobby = 6, -- 7.0 planning: the MoveLobby remote's role, READY, LAUNCH, CANCEL (server/MoveLobby.luau)
		QuickChat = 0.5, -- 7.0 planning: a quick chat line (the MoveLobby remote's "chat"): one every 2 s at most
		MovingBoard = 1, -- 7.0 review: the moving board's prompt (its contract card): one a second
		Collection = 6, -- 8.0: the Collection remote's display / undisplay / sell / state (server/Collection.luau)
		CollectionBulk = 1, -- 8.2: and its bulk buttons (fillbest / sellmany / undisplayall): one a second, on top
		Upgrades = 4, -- 8.1: the Upgrades remote's state / buy (server/Upgrades.luau)
		CollectionBook = 4, -- 8.2: the CollectionBook remote's state (server/CollectionBook.luau)
		SandboxTasks = 4, -- 8.2: the SandboxTasks remote's state / claim (server/SandboxTasks.luau)
		Auction = 4, -- 8.8: the Auction remote's state / consign / withdraw (the server's step: design/auction/PLAN.md)
		AuctionBid = 3, -- 8.8: and its bids (one step a tap)
		MoveHelper = 4, -- 8.3: Danny's HIRE, CLEAR QUEUE and STOP (the Moving remote's "helper": server/MoveHelper.luau)
		MoveHelperAssign = 5, -- 8.3: a piece clicked into (or out of) Danny's list (the Moving remote's ("helper", "assign"))
		Clipboard = 4, -- 8.5: Danny's clipboard out or away (the Clipboard remote: server/Clipboard.luau)
		MoveHelperOrder = 3, -- 8.6: an order to Danny, PUT IT DOWN / GET OUT (the Moving remote's ("helper", "putdown" | "getout"))
		VanPaint = 4, -- 8.3: the VanPaint remote's state / buy / wear (the PAINT shop: server/VanPaint.luau)
		Visitors = 2, -- 8.3: the Visitors remote's ACCEPT / DECLINE of a visitor's offer (server/VisitorOffers.luau)
		PlayerTrade = 4, -- 8.7: the PlayerTrade remote's offer / answer / price / buy (server/PlayerTrade.luau)
		TradeOffer = 0.2, -- 8.7: and a new offer to a player on top: one every 5 s at most (no offer spam)
	},
}

-- 6.13, analytics (server/Analytics.luau, shared/AnalyticsPlan.luau; the owner's guide: design/analytics/NAVOD.md).
-- Roblox's AnalyticsService gets the onboarding funnel, the Delivery and Mission funnels, the economy in Currency, the
-- progression and a short fixed list of custom events. Nothing is sent from Studio (the admin panel's WORLD tab counts
-- what would go). BatchSeconds: the frequent money (kill rewards, fuel at the pump, tips) goes as one economy event a
-- player this often (and when they leave). Budget: events a minute for the whole server at most (Base + PerPlayer ×
-- the players), under Roblox's own throttle; the rest is dropped and counted (an onboarding step dropped goes later).
-- The errors: ErrorsPerMinute warnings and events a minute for the whole server, for ServerError and ClientError each;
-- a client reports one error every 1 / Robust.Limits.ClientError s at most (client/Unstuck.luau keeps to the server's
-- limit), ClientErrorsMax from one player a session.
Config.Analytics = {
	Enabled = true, -- false: nothing is sent, also in a live server
	Currency = "Cash",
	BatchSeconds = 60,
	Budget = { Base = 100, PerPlayer = 15 },
	ErrorsPerMinute = 6,
	ClientErrorsMax = 20,
	-- 8.2 SANDBOX (server/SandboxAnalytics.luau): one grip check's outcome in this many is sent, a random one of each
	-- window of them, for every player (the GripCheck event: its value says how many it stands for)
	GripEvery = 10,
}

-- 6.12, the daily and weekly tasks (the owner: "daily and weekly tasks so players come back"; shared/Tasks.luau picks
-- and counts them, server/Tasks.luau keeps profile.tasks and pays, client/TasksApp.luau is the phone's TASKS app).
-- Every UTC day a courier gets Daily tasks from DailyPool, every UTC week (from Monday 00:00 UTC) one from WeeklyPool,
-- picked by the day's (the week's) number and the UserId: the same all day, new at 00:00 UTC; never two of one
-- `group` a day, only the kinds open at the courier's level when the day starts (`level`, 1 when missing).
-- A kind: `event` is what server/Tasks.luau's Tasks.note counts (deliver: pieces delivered, `look` only that cargo
-- look; ride: deliveries on a bike or a scooter; stars3: jobs finished at ★★★; perfect: PERFECT throws; zip: zip-line
-- rides; bus: bus trips; kill: zombies killed, `night` only after dark; tips: tip
-- money; earn: delivery pay; mission: missions finished; 6.14: shift: shifts finished; regular: orders for a
-- business you are a regular at; golden: golden orders finished). `text` is the title ({n} the target; `one` when
-- it is 1), `target` the range it is picked from (in `step`s; `grow`: × (1 + grow × (level − 1)) for the ones that
-- grow with you), `money` and `xp` the reward (× (1 + LevelScale × (level − 1)), the level when the day starts).
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
		{ id = "ride", event = "ride", text = "Make {n} deliveries on a bike or a scooter", one = "Make a delivery on a bike or a scooter", target = { 2, 4 }, money = 180, xp = 110, level = 2 },
		{ id = "mission", event = "mission", text = "Finish {n} missions", one = "Finish a mission", target = { 1, 2 }, money = 300, xp = 150, level = 5 },
		-- 6.14: the shift's pay (Config.Jobs.Shift: its deliveries in one go), server/Shift.luau notes "shift"
		{ id = "shift", event = "shift", text = "Finish {n} shifts", one = `Finish a shift ({Config.Jobs.Shift.Jobs} jobs in one go)`, target = { 1, 2 }, money = 200, xp = 120 },
		-- 6.14: the regulars (an order for a business you are Bronze or better at) and the golden orders
		{ id = "regular", event = "regular", text = "Deliver {n} orders where you're a regular", one = "Deliver an order where you're a regular", target = { 2, 4 }, money = 180, xp = 110, level = 3 },
		{ id = "golden", event = "golden", text = "Finish {n} golden orders", one = "Finish a golden order", target = { 1, 1 }, money = 300, xp = 160, level = 3 },
		-- 6.15: a live event (server/LiveEvents.luau notes "liveevent" once an event for each player: a job paid during a
		-- Blood Moon or a rush hour, the supply drop brought in, a share of the horde's reward)
		{ id = "liveevent", event = "liveevent", text = "Take part in {n} live events", one = "Take part in a live event", target = { 1, 1 }, money = 220, xp = 130, level = 2 },
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

-- 6.14, the REGULARS (shared/Regulars.luau, server/Regulars.luau, client/RegularsApp.luau; the owner: "a bit MORE
-- grind, but a FUN grind"): every business whose picture the job lists show (shared/JobThumbs.luau Assets, 25) counts
-- the orders and jobs you delivered for it (profile.regulars; a mission never counts, a crew member counts their own).
-- At a tier's `at` deliveries you are its regular: every delivery for it pays `bonus` more (on the rated pay, before
-- the tips and the crew's split). A count is kept up to Cap.
-- REGULAR'S ORDER (server/SpecialOrders.luau, the same path as the golden orders): every Order.Every s a courier who
-- is a regular at Order.Tier (Silver) or better somewhere has Order.Chance of a REGULAR'S ORDER from one of those
-- businesses on their board (one at a time): an ordinary delivery of that business paying Order.Pay × (Order.Xp × the
-- XP), on the board (and in NEXT UP) for Order.Seconds.
export type RegularTier = { id: string, name: string, at: number, bonus: number, icon: string }

Config.Regulars = {
	Tiers = {
		{ id = "bronze", name = "Bronze", at = 5, bonus = 0.05, icon = "🥉" },
		{ id = "silver", name = "Silver", at = 15, bonus = 0.1, icon = "🥈" },
		{ id = "gold", name = "Gold", at = 40, bonus = 0.15, icon = "🥇" },
		{ id = "platinum", name = "Platinum", at = 100, bonus = 0.2, icon = "💎" },
	} :: { RegularTier },
	Cap = 100000,
	Order = {
		Tier = 2,
		Every = 120,
		Chance = 0.2,
		Seconds = 300,
		Pay = 1.5,
		Xp = 1,
	},
}

-- 6.15, LIVE EVENTS (the owner: "events where working is better for earning, e.g. a Blood Moon"): one at a time for
-- the whole server (server/LiveEvents.luau runs them, shared/LiveEvents.luau holds the rules and the words,
-- tests/liveevents_test.luau checks them, client/EventBanner.luau shows them). The first one comes First minutes after
-- a player is in, then one every Every minutes (start to start, random in between), never in an empty server: the next
-- of a shuffled deck (Order) whose moment it is. The BLOOD MOON only at night with MinNightLeft s of it to go (it ends at
-- dawn at the latest), RUSH HOUR only by day with MinDayLeft s of it to go (it ends at dusk at the latest); a card whose
-- moment has not come waits in the deck while a later one goes first; none can start: the server looks again every
-- Retry s, after MaxWait s the deck is shuffled anew (MaxWait: longer than a day's cycle, Config.DayNight.DayLength,
-- less the event's window, so the night or the day always comes first). Missions are never touched: no event pay, no
-- event zombies, no faster zombies (Offer.mission).
--   Events     each event's name, icon, one-line hint, length in minutes and colour (the banner, the board, the toasts)
--   LevelScale the supply drop's and the horde's rewards × (1 + this × (level − 1)) for each player
--   Reach      an event zombie (the horde, the crate's guards) goes after a player this close; else it walks to its spot
--              (the gate, the crate) and waits there; it never despawns while its event runs (server/Zombies.luau march)
--   BloodMoon  Pay: jobs finished during it pay × this (on the job's pay: the same subtotal the night bonus takes,
--              Economy.payout; the rating, the streak, the regulars and the tips come on top as they do on the night's);
--              Waves: × the job waves' spawn multiplier (Jobs.dangerOf: bigger, more often, a higher cap of the alive
--              ones, like WANTED); Roam: × the roamers around every player (server/Zombies.luau, on top of the night's);
--              Speed: × every zombie's speed but a mission's (the people too are spared), at most MaxSpeed studs / s;
--              Fade: seconds the red sky and fog ease in and out (client/Weather.luau)
--   Rush       Pay: × the pay of a job finished during it (as the Blood Moon's); ExtraOffers: more ordinary offers a
--              danger level and on foot / by bike (JobRules.roles); Refresh: the board's new offers this often at most
--              (Config.Jobs.RefreshSeconds otherwise); every board is made anew when it starts (not during a run)
--   Supply     a crate falls by parachute (FallFrom studs, FallSpeed studs / s) onto a street Distance studs from the safe
--              zone's middle (on its square: past SafeHalf + Margin), a light beam and a map marker for everybody; its
--              Guards gather (First at the landing, Batch every Every s up to Max alive, Near … Far studs round it,
--              Kinds); anybody picks it up (Pickup studs, Hold s) and carries it on foot (G / PUT DOWN sets it down; it
--              drops when the carrier dies, sits or leaves); the first who brings it within DeliverRadius of the depot's
--              drop-off (DropOff: x, z from the depot's middle) gets Money and Xp (× LevelScale) ("SupplyDrop").
--              6.15 review: set down, it lands on the floor under it (a ray Drop studs down at most in front of a
--              grounded carrier, past the cars and the people; else where the carrier last stood); it drops by itself
--              when its carrier stands still Idle s or gets no StallGain studs nearer the drop-off in Stall s (no
--              hostage), and a carry faster than MaxPace studs / s (× an admin's walk) plus Slack studs a step is no
--              carry: the crate goes back down where it was (no teleport to the depot)
--   Horde      Count zombies (Kinds) in Bursts, one every BurstEvery s, Out studs past the safe zone's edge on the streets
--              of one side, walking to its Gates gates (Stop studs outside the edge; they never come in); beaten when all
--              came and Beaten of it fell before its time is up (6.15 review: a straggler stuck behind a building
--              does not hold it up); then (or at its end) everybody who killed some shares Money and Xp by their kills
--              (× LevelScale; at its end only the share of the horde that fell, of Beaten × Count) ("HordeReward")
--   Headroom   6.15 review, the event's own zombie budget: its zombies (the horde, the guards) spawn up to
--              Config.Horde.MaxTotal − Headroom (the job waves keep that room), StepSpawn a step at most. What it still
--              wants holds the roamers back (Zombies.eventReserve: they stop that much lower), and when a burst does not
--              fit, calm roamers far from everybody make room (Zombies.trimRoamers). The 36 residents and the whole
--              horde fit: 36 + Count ≤ MaxTotal − Headroom (tests/liveevents_test.luau runs a full server)
--   Linger     6.15 review: at its end its zombies nobody is within Vanish studs of go at once; the others fall back
--              (they walk away, after nobody) and go once nobody is that close, Linger s at most
export type LiveEventDef = { name: string, icon: string, hint: string, minutes: number, color: { number } }

Config.LiveEvents = {
	Enabled = true,
	First = { 10, 15 } :: { number },
	Every = { 20, 30 } :: { number },
	Retry = 5,
	MaxWait = 840,
	Tick = 0.25, -- seconds between the server's steps of a running event
	LevelScale = 0.15,
	Reach = 140,
	Headroom = 12,
	StepSpawn = 5,
	Linger = 30,
	Vanish = 150,
	Order = { "bloodmoon", "rush", "supply", "horde" } :: { string },
	Events = {
		bloodmoon = { name = "BLOOD MOON", icon = "🌕", hint = "Jobs pay ×2 · more zombies, and faster", minutes = 5, color = { 222, 64, 58 } },
		rush = { name = "RUSH HOUR", icon = "🕑", hint = "Jobs pay ×1.5 · more jobs on the board", minutes = 5, color = { 232, 174, 84 } },
		supply = { name = "SUPPLY DROP", icon = "📦", hint = "First to bring the crate to the depot wins", minutes = 6, color = { 126, 196, 120 } },
		horde = { name = "HORDE AT THE GATES", icon = "🧟", hint = "Hold the gate · share the reward by your kills", minutes = 6, color = { 178, 110, 222 } },
	} :: { [string]: LiveEventDef },
	BloodMoon = {
		Pay = 2,
		Waves = 1.5,
		Roam = 1.5,
		Speed = 1.2,
		MaxSpeed = 30,
		MinNightLeft = 300,
		Fade = 4,
	},
	Rush = {
		Pay = 1.5,
		ExtraOffers = 1,
		Refresh = 60,
		MinDayLeft = 300,
	},
	Supply = {
		Money = 450,
		Xp = 220,
		Distance = { 280, 480 } :: { number },
		Margin = 40,
		FallFrom = 150,
		FallSpeed = 7,
		Pickup = 9,
		Hold = 0.6,
		DropOff = { 24, 10 } :: { number },
		DeliverRadius = 12,
		Drop = 8,
		Idle = 20,
		Stall = 60,
		StallGain = 10,
		MaxPace = 16,
		Slack = 10,
		Guards = { First = 6, Every = 20, Batch = 2, Max = 10, Near = 18, Far = 45 },
		Kinds = { walker = 0.6, runner = 0.25, brute = 0.1, bloater = 0.05 } :: { [string]: number },
	},
	Horde = {
		Count = 40,
		Bursts = 4,
		BurstEvery = 20,
		Out = { 150, 300 } :: { number },
		Stop = 18,
		Gates = 2,
		Beaten = 0.9,
		Kinds = { walker = 0.54, runner = 0.28, brute = 0.12, bloater = 0.06 } :: { [string]: number },
		Money = 900,
		Xp = 450,
	},
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
		-- (6.16: the sun rays follow the time of day: Config.Atmosphere's looks, rays)
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
		-- 6.14.1 (the owner: "a more pleasant ride on the scooter … the camera and the feel"): on a scooter or a bike
		-- (the car's Bike attribute) the camera rides closer and lower, swings back behind you sooner and quicker, looks a
		-- little into the turn, tilts with the lean and widens from a lower speed (client/CameraRig.luau)
		TwoWheels = {
			Fov = 9, -- extra field of view at the top speed (a car: Fov) …
			FovFrom = 0.4, -- … from this share of the top speed (a car: FovFrom)
			Back = 8.5, -- studs behind (a car: its length × 0.7 + 9, about 12 for a scooter)
			Up = 1.5, -- studs over the focus (a car: 2)
			FollowAfter = 0.6, -- seconds without the mouse before it swings back behind you (a car: 1.2)
			Follow = 5, -- 1/s: how quickly it swings back (a car: 6 % a frame)
			FollowFrom = 4, -- studs/s: from this speed
			LookAhead = 0.2, -- seconds of the turn it looks ahead
			Roll = 0.35, -- the share of the ride's lean (Config.Scooter LeanRate / LeanMax) the picture tilts with
			RollRate = 6, -- 1/s
		},
	},
}

-- 6.13.1, performance and mobile (the game is public, many players are on phones: design/performance/REPORT.md, the
-- owner's phone test design/performance/NAVOD.md). shared/RenderBudget.luau has the rules, client/DeviceBudget.luau
-- the phone's share, client/PerfOverlay.luau the admin's numbers.
Config.Performance = {
	-- Shadows (RenderBudget.casts; World's part(), BuildingLooks/Kit, the street props, the stops, the alleys, the zip
	-- platforms, the docks, the cars' parts): a part throws a shadow only when its longest side is at least ShadowLong
	-- and its second side at least ShadowWide (a pole, a lamp post, a wall, a crate do; a rail, a strip, a rod, a frame,
	-- a bolt do not), and never as a plate lying flat on the ground (its thin side up, at most ShadowFlat thick, its
	-- middle at most ShadowFlatHeight high: road marks, lawns, mats; a raised canopy, an awning, a palm's leaves keep it).
	ShadowLong = 2,
	ShadowWide = 0.45,
	ShadowFlat = 0.25,
	ShadowFlatHeight = 2.5, -- studs of world height: the walk is at 0.9, so up to about 1.5 over it
	-- The night's real lights on this client (client/WorldFx.luau): only the MaxLights nearest within LightRange of the
	-- camera shine (a vehicle's lights together); every other lamp, window and headlight still glows (Neon), it just
	-- lights nothing. Looked at every LightEvery seconds; one that shines keeps shining out to LightHoldRange × the range
	-- and LightHoldExtra lights over the count (no blinking at the edge); a light fades in and out over LightFade s.
	MaxLights = 40,
	LightRange = 320,
	LightEvery = 0.5,
	LightHoldRange = 1.15,
	LightHoldExtra = 4,
	LightFade = 0.3,
	-- A phone or a tablet (a touch screen without a keyboard, client/DeviceBudget.luau): the cosmetic per-frame work
	-- (the poses, the bag's swing, the zombies' and the animals' legs, the traffic's glide and wheels, the cars' wheels
	-- and riders, the rooftop props, the flickering lamps) reaches Range of its distance on a computer, the posed bodies
	-- Count of their number; fewer real lights, closer; the minimap's routes and markers MapHz times a second, and its
	-- turning picture moved at most MapMoveHz times a second (its CanvasGroup is drawn again on every move).
	Lite = { Range = 0.6, Count = 0.5, MaxLights = 16, LightRange = 200, MapHz = 10, MapMoveHz = 30 },
	-- Small text (SurfaceGui.MaxDistance) is drawn only this close: the plain signs (World's sign(): JOBS, BAY 2 …), the
	-- building looks' labels, the house numbers, buzzers and mailboxes, the FOR SALE plates, the bus stops' boards and
	-- the alleys' signs; the buildings' name boards (art) from further.
	SignRange = 220,
	SignPerStud = 100, -- … but a big board stays readable farther: this many studs per stud of its height (a 6 tall: 600)
	NameBoardRange = 700,
	-- The admin's performance overlay (client/PerfOverlay.luau; the P panel's WORLD tab: PERFORMANCE): its numbers
	-- every Refresh seconds, the workspace counted every Count seconds, PerFrame instances a frame (never a hitch).
	Overlay = { Refresh = 0.5, Count = 5, PerFrame = 1500 },
}

-- 6.17, the JOBS app at a glance (redesign B; client/JobsView.luau draws it, shared/JobPick.luau picks the hero).
-- 6.18: its look is the UI kit's now (client/CardKit.luau draws, shared/CardLayout.luau measures, design/ui-kit/): every
-- popup and the phone's home use these sizes.
--   * a body SplitMin px wide (or wider) shows the hero card on the left (HeroShare of it) beside the compact rows;
--     narrower, the hero heads the rows;
--   * a popup's hero is the popup's room tall, between HeroMin and HeroMax px; its big value PayBig px from PayTall px
--     of hero, else PayMid; its big button Button px tall;
--   * the phone home's hero (6.18: NEXT MISSION, or YOUR RUN during a run) is HomeHeroMin .. HomeHeroMax px, its value
--     HomeValue px, its button HomeButton px and only from ButtonHeroMin px (a shorter hero is the button itself);
--   * a compact row is Row px tall: the picture Thumb px wide (an app's icon Icon px), the round action Add px square;
--     the rows Gap px apart; the header chips Chip px tall; the corners Corner (cards) and RowCorner (rows) px.
Config.UiKit = {
	SplitMin = 600,
	HeroShare = 0.46,
	HeroMin = 196,
	HeroMax = 330,
	PayTall = 260,
	PayBig = 52,
	PayMid = 42,
	Button = 44,
	HomeHeroMin = 128,
	HomeHeroMax = 190,
	HomeValue = 26,
	HomeButton = 40,
	ButtonHeroMin = 178,
	Row = 52,
	Thumb = 76,
	Icon = 52,
	Add = 40,
	Gap = 6,
	Chip = 24,
	Corner = 12,
	RowCorner = 10,
}

-- 6.21, the inventory as a clean hotbar (the owner picked redesign B "Clean hotbar + kit"; shared/Inventory.luau holds
-- the pure maths, client/Hotbar.luau and client/BagUi.luau draw it). Px at the HUD's design scale.
--   Tile / Selected       a slot, and the slot in your hand (it lifts by Lift px and grows to Selected px)
--   Gap / PadX / PadY     between the slots, and the frosted tray's padding around them
--   Corner / TrayCorner   the slots' and the tray's corners
--   Pill / PillMin        the count pill at a slot's bottom right corner (its height, its least width), Overhang px out
--   Ring / RingInset      the bag slot's fill ring (its thickness, its inset from the slot's edge)
--   Line / LineGap        the line over the bar (the name of what is in your hand and its count), its gap to the slots
--   TouchMin              a touch screen: the bar shrinks with the HUD (the mock's 62 %), but a slot never under
--                         TouchMin px (6.0.1's 48 px rule for fingers: 67 % of a slot)
--   TouchGap / TouchPad   a touch screen's tighter gaps and padding (the bar fits a 640 px phone between the
--                         thumbstick and JUMP)
Config.Hotbar = {
	Tile = 72,
	Selected = 80,
	Lift = 12,
	Gap = 10,
	PadX = 14,
	PadY = 10,
	Corner = 18,
	TrayCorner = 22,
	Pill = 22,
	PillMin = 26,
	Overhang = 6,
	Ring = 5,
	RingInset = 4,
	Line = 22,
	LineGap = 6,
	TouchMin = 48,
	TouchGap = 6,
	TouchPad = 7,
}

-- 6.21, the inventory's colours by kind (a row's left edge in BAG & ITEMS; shared/Inventory.luau category): weapons
-- red, medical green, explosives orange, cargo and bags blue, gear grey. Items: a consumable's kind (Config.Items id;
-- else gear). Stack: the cargo tiles on BAG & ITEMS' YOUR BAG card (at most Max tiles of Tile px, Gap px apart).
Config.Inventory = {
	Colors = {
		weapon = { 215, 74, 70 },
		medical = { 126, 196, 120 },
		explosive = { 240, 138, 58 },
		cargo = { 90, 162, 230 },
		gear = { 154, 163, 174 },
	} :: { [string]: { number } },
	Items = { medkit = "medical", energy = "medical", molotov = "explosive", mine = "explosive", repair = "gear", nitro = "gear", jerrycan = "gear" } :: { [string]: string },
	Stack = { Max = 6, Tile = 46, Gap = 6 },
}

-- 6.22, every thing in the inventory has a look (the owner: "every thing must look like something, not only an icon"):
-- client/ItemModel.luau draws each gun, the bat, your fists, the consumables, the bags, the vests and the cargo as a
-- small 3D model (shared/ItemLooks.luau) in a ViewportFrame: the bottom bar's slots, BAG & ITEMS' hero, rows and cargo
-- stack. The icon (or the emoji) shows only if a model cannot be built.
--   MaxParts          a look's parts at most (tests/itemlooks_test.luau builds every one)
--   Yaw / Pitch       the 3/4 angle (degrees): the camera turned from the front toward the right, and looking down
--   Fov / Fill        the camera's field of view (degrees) and the share of the frame the model fills
--   Ambient           the soft fill light (RGB); LightColor / LightDirection the key light (from the top left front)
--   Spin              the hero's slow turn (degrees a second; not with Reduced Motion), redrawn SpinRate times a second
--   Slot / Hand / Bag a model's square in a bottom bar item slot, a hand slot and inside the bag slot's ring (px)
--   Row               a row's thumb: its model's inset from the thumb's edges (px; a square)
--   Tile              the cargo stack's tile: its model's inset (px)
--   Hero              the hero card's model: its square as a share of the card's height, Shift px in from its right
--   Dim / Shut        a model's transparency while it can't be taken (a dim slot) and greyed while locked
Config.ItemModel = {
	MaxParts = 40,
	Yaw = 35,
	Pitch = 22,
	Fov = 30,
	Fill = 0.86,
	Ambient = { 150, 156, 166 },
	LightColor = { 255, 244, 226 },
	LightDirection = { 0.5, -1, 0.65 },
	Spin = 24,
	SpinRate = 30,
	Slot = 50,
	Hand = 50,
	Bag = 38,
	Row = 4,
	Tile = 4,
	Hero = 0.62,
	Shift = 10,
	Dim = 0.55,
	Shut = 0.35,
}

-- 8.1 grip (the owner: "when I fail, something must always happen, but make it easier, it can get harder later; it is
-- hard to keep pressing and walk at the same time. When we pick it up the first time I should have to hit a target:
-- I'm feeling for the grip, and when I succeed I can carry it away, I keep my balance"). No holding any more: a timing
-- check (a needle sweeps a bar with a green zone, one press) at the lift and now and then while you carry (a WOBBLE!).
-- shared/CarryGrip.luau has the rules (pure: tests/carrygrip_test.luau), client/CarryGripUi.luau shows a check and
-- reads the press, server/Moving.luau's grip block opens the checks, judges the answers and decides what a miss does.
-- Every number of the difficulty is here: a harder game later changes only these (Difficulty first).
--   On          false: no checks at all (the carry as before the grip; the server's runtime tests of other parts)
--   Difficulty  1 = the easy start: every zone ÷ it, every needle × it (1.5: a third smaller zones, half again as fast)
--   Kinds       the carries with checks (a one-hand thing that is not fragile has none): Zone, the green zone's share of
--               the sweep at weight 0; Speed, the needle's sweeps a second (edge to edge); Every, × the time between two
--               wobbles. "hand": a fragile one-hand thing (gentle, wobbles less); "both"; "pair": two carry it (each
--               their own checks, a bigger zone: the other end steadies it); "solo": a Mover lifts a pair thing alone;
--               "drag": a pair thing dragged alone, low (calm)
--   Weight      a weight point (1 … 10): the zone − Zone, the needle + Speed
--   Fragile     × the zone (Zone) and the needle (Speed) when fragile
--   Mover       × the zone for a Mover (every kind); Steadied: × the zone while Danny holds the other end of your piece
--               (the character attribute GripSteady, server/MoveHelper.luau)
--   Zone        the zone after all that is kept within Min … Max of the sweep; Start: never nearer the needle's start
--               (the left end) than this (an instant press never hits), Edge: never nearer the right end
--   Speed       the needle kept within Min … Max sweeps a second; Sweeps: every check lasts at least this many sweeps
--   Lift        the lift check ("feeling for the grip"): Window s to press (no press: a miss); a miss (Knock of the
--               piece's condition) leaves it where it is (it slips back down) and the next try waits Again s
--   Wobble      the checks while you carry: every Every[1] … Every[2] s of walking (× the kind's Every); its zone × Zone
--               and needle × Speed, Window s to press. The wobble clock runs at Still standing still (under StillAt
--               studs/s), 1 at the carry's own walk, + Rush × how far over it you go (half again over it: all of Rush),
--               + Turn turning at TurnFull rad/s or more, + Air in the air (a jump, a fall); a bite moves it Bump s on.
--               Two checks are at least Gap s apart
--   Miss        a wobble missed: Knock of the condition, the walk × Slow for SlowFor s (a stagger), the next wobble ×
--               Sooner. Drop: the misses in a row that drop the piece (a drop: Slip below): Sturdy, Heavy (from HeavyAt
--               weight on), Fragile (1: a fragile piece drops at its first miss). Every miss does something: a carry
--               put down or loaded with a wobble open takes it as a miss, and the misses stay with the piece Remember s
--               (a new lift of it picks them up again: 8.1 review)
--   FragileKnock × a knock when the piece is fragile; Shared: × a knock when two players hold it (each one's checks:
--               half each, as the 7.1 wear)
--   Slip        a drop's damage (× Moving.Damage.Fragile when fragile)
--   SteadySpeed × the carry's walk while every player holding it hit their last check (balanced, steady)
--   Server      Grace: s past a check's window before the server takes no answer as a miss; Lag: an answer's press may
--               be this many s older than the server's own clock of the check (the way there and back) at most, and
--               for each player LagPing × their round trip (Player:GetNetworkPing) + LagMin when that is less (8.1
--               review); Ahead: … or this much newer; Slack: the share of the sweep the zone is widened by when the
--               server judges a press
--   Ui          Tutorial: the checks with the longer hint ("… when the needle is in the green"); Shake: px a miss
--               shakes the widget (ReducedShake with Reduced Motion); Camera: client/CameraRig.luau's shake on a miss
--               (CameraDrop on a drop); Linger: s the outcome stays; Tap: the touch TAP button's side (px, at least
--               TapMin); Scale: the widget's least scale on a touch screen, Min: its least anywhere; the sounds
--               (art/audio/sfx4.ogg; the drop: MoveSounds.slipped): Open at a check's start, Tick as the needle enters
--               the zone, Hit, Knock, Warning (a wobble that drops on a miss)
Config.CarryGrip = {
	On = true,
	Difficulty = 1,
	Kinds = {
		hand = { Zone = 0.36, Speed = 0.45, Every = 1.25 },
		both = { Zone = 0.36, Speed = 0.5, Every = 1 },
		pair = { Zone = 0.4, Speed = 0.45, Every = 1 },
		solo = { Zone = 0.3, Speed = 0.55, Every = 0.85 },
		drag = { Zone = 0.4, Speed = 0.42, Every = 1.5 },
	} :: { [string]: { Zone: number, Speed: number, Every: number } },
	Weight = { Zone = 0.005, Speed = 0.012 },
	Fragile = { Zone = 0.9, Speed = 1.08 },
	Mover = 1.35,
	Steadied = 1.3,
	Zone = { Min = 0.1, Max = 0.6, Start = 0.3, Edge = 0.04 },
	Speed = { Min = 0.2, Max = 2, Sweeps = 1.5 },
	Lift = { Window = 3, Knock = 0.04, Again = 0.5 },
	Wobble = { Every = { 7, 12 } :: { number }, Zone = 0.85, Speed = 1.15, Window = 2.4, Still = 0.2, StillAt = 1.5, Rush = 1, Turn = 0.6, TurnFull = 3, Air = 1, Bump = 3, Gap = 3 },
	Miss = { Knock = 0.03, Slow = 0.6, SlowFor = 1.5, Sooner = 0.5, Drop = { Sturdy = 2, Heavy = 2, HeavyAt = 8, Fragile = 1 }, Remember = 8 },
	FragileKnock = 1.25,
	Shared = 0.5,
	Slip = 0.06,
	SteadySpeed = 1.1,
	Server = { Grace = 1.5, Lag = 2, LagPing = 2, LagMin = 0.3, Ahead = 0.1, Slack = 0.02 },
	Ui = { Tutorial = 3, Shake = 6, ReducedShake = 1, Camera = 0.2, CameraDrop = 0.35, Linger = 1.1, Tap = 96, TapMin = 80, Scale = 0.75, Min = 0.62, Open = 0.55, Tick = 0.3, Hit = 0.35, Knock = 0.6, Warning = 0.6 },
}

-- 7.0 prototype, MOVES (the owner's rework, design/rework/NAVRH.md: one house move first, the old game stays beside
-- it): server/Moving.luau runs a move, shared/MovingRules.luau has its rules (tests/moving_test.luau), client/
-- MovingHud.luau shows it. The art is shared/FurnitureLooks.luau, shared/HouseLayout.luau and server/HouseInterior.luau.
--   Time / HordeAt    the move's clock (s) and when the horde comes (s left); Fade: the fade at a door (s)
--   Contracts         the moves on the depot's board (home: a Map.Homes id, the house whose front door leads inside;
--                     seed: shared/HouseLayout.luau plan's)
--   Van / Beds        7.x van moves (the owner: "the move should be driven with MY van"): no truck is lent any more, a
--                     move uses its owner's own car (the ZDC Van, Van); Beds: the packing bed of a car by its id (its
--                     cargo bay: studs from the chassis' middle, Center x / z its middle, the floor at the chassis' top,
--                     the grid's Cell), a car without one the Van's. The ZDC Van's bay (server/Vehicles.luau
--                     STYLES.zdcvan: the cargo box 6.6 wide, 4.5 tall, from the bulkhead at z -0.35 to the back doors at
--                     z 6.3) less its walls: 6.2 × 6.4 × 4.3 round z 2.98; the old Moving Truck's box stays for a player
--                     who still drives one. Hitch: a piece too big for any bed that may be towed (FurnitureLooks bigDoor:
--                     the hay wagon) rides hitched behind the car, Gap studs behind its back (Back: the back's z), its
--                     wheels on the ground (Drop: the chassis' middle over the ground). VanAgain: s after the van was
--                     lost (wrecked or gone mid-move: what was in it is lost) before CAR brings it again.
--                     8.0 SANDBOX: sprinter, the walk-in Sprinter's bay (Config.Sandbox.Van: the sprinter's body is
--                     Config.Sprinter's): 6.6 wide (13 cells of 0.5: 6.5 of it packed, in its middle), 7.6 tall, 14 long:
--                     every house piece stands in it (the Grandfather Clock's 7.2 too; tests/vanmove_test.luau). Cell 0.5,
--                     not the ZDC Van's 0.4: the packer's cost grows with the cells (a 14-long bay at 0.4: a Load up to
--                     about 60 ms with its repack, 0.5 about 15 ms, and only about 2% fewer pieces packed). WalkIn:
--                     a carrier standing inside the bay (its box over the floor) may Load from there too (the bay's own
--                     Load prompt), not only at the back doors. Back: the bay's back end this far in front of the car's
--                     CargoDoor (its z from the door: it follows the body's length; Center's z only without a door, and
--                     for the admin's SHOW ZONES box, client/SandboxZones.luau: the same middle, the Sprinter's CargoDoor
--                     z 11.6 − Back − Length / 2 = 3.85)
--   Board / DropOff   studs from the depot's middle (Map.Depot): the "Moving contracts" board (facing -X) and the
--                     drop-off ("the Wall"); 7.x van moves: the van within DropRadius of it unloads its load there (a
--                     trip; the move goes on until the owner's FINISH or the clock)
--   Speed             × the walk with a thing: hand 1 − weight × HandPerWeight (not under MinHand), both, pair (two
--                     carry it: 8.1 a touch slower, and slower still while its heading turns: MoveHelper.PairTurnWalk), drag
--   Damage            shares of a thing's condition: a fall over SafeDrop studs (over a jump's top, about 7) PerStud a
--                     stud, PerHp of its carrier's lost health, Death when its carrier dies, PerTruckHp of the truck's;
--                     Fragile × as much; broken at BrokenAt or less (it pays nothing and costs Pay.BrokenFine × its value)
--   Pay               Σ value × condition × Scale, ★ things × Star, + TimeBonus × the share of the time left, late (the
--                     clock ran out: delivered within LateGrace s after 0:00, else nothing) × LateShare; XP Xp + the
--                     value delivered / XpPerValue + XpPerStar × the stars, at most XpMax (7.0 review: a one-lamp move
--                     is no full move); the crew within Present studs of the truck shares it (Economy.crewSplit)
--   Tether / Grace    a pair thing's helper stays within Tether studs of its end; farther for Grace s, it goes down
--   PairLift          8.6 carried in two (the owner: "the table seems to float between them"; MovingRules.pairLift,
--                     server/Moving.luau's holdOffset): lengthwise (its long side along the carry: the two at its ends)
--                     and low: its grips (two thirds of its height, Grip studs over its bottom at most: FurnitureLooks
--                     grips) Hands studs under the carriers' roots, its bottom Clear studs over the floor at least
--   Pace              a carried thing that moves faster than the carry's walk × Factor + Slack goes down (a teleport)
--   Horde / Roam      the horde round the house at HordeAt (Count in Bursts, Every s apart, Near … Far studs from the
--                     door), the few zombies round it while somebody is outside within Range
--   Reach             studs for the prompts (the server checks them again); Slots: moves at once (their interiors)
--   Doors             8.1 walk-in doors (the owner: "no E at the house, neither in nor out"): walk into a door's zone and
--                     the fade takes you through, as "Enter house" / "Leave house" did (server/Moving.luau's WalkIn, in
--                     the move's tick and every Every s between two ticks, only for the move's crew on foot). The zone:
--                     a box at the doorway, its width + Side studs either side, Depth studs in front of it (outside: out
--                     of the door; inside: into the room) and Through studs through it (the doorway and the porch or
--                     the apron beyond), Height tall round a body's middle. You stand in it Dwell s facing the door (the
--                     root's look · the way through at least Face: walking past it is no way in), then through; a
--                     refusal (a bigDoor piece at a small door: "Too big — use the barn doors"; the back end of a pair
--                     piece) is said once and you stay. After a trip you come out a few studs from the door facing away
--                     (Depth is less than that), and the zones stay shut for you until you have stepped out of the one
--                     you came out in and Rearm s have gone by (no ping-pong; Danny's own trips wait Rearm s too, his
--                     arrival out of his door's reach: server/MoveHelper.luau). Walk false: the E prompts as before
--                     (they stay, disabled, while it is on). Mat: the doormat on the ground at every door (its width at
--                     most, its depth): "▲ IN" outside while a move uses the door, "▲ OUT" inside. PairWalk: a leader
--                     carrying in two may back through it (facing the partner), but their back to it counts only while
--                     they walk into it at PairWalk studs/s or more (the root's flat velocity · the way through at least
--                     Face; 8.1 review: a drift back toward the door no longer takes them through)
--                     8.3 the doors swing and the trip is smooth (the owner: "when I go into the house, the door should
--                     open, and then it teleports me smoothly"; shared/DoorSwing.luau has the leaves' attributes and
--                     their swing, client/WalkDoors.luau swings them for everybody, client/Fade.luau holds the dark):
--                     Swing: a door's leaf (a part or model with the attribute DoorLeaf at its doorway) swings open
--                     Angle degrees on its hinge in Open s as a crew member walks up to it facing it (Approach studs in
--                     front of it, ApproachSide past the zone's sides; Danny too, any way he faces), shut again in Close
--                     s once its zone has been empty Shut s; the door's creak (Sound.Open) as it opens, a soft thud
--                     (Sound.Shut at ShutPitch) as it shuts, heard within Range. The trip: in the zone facing the door
--                     Dwell s and the leaf open Open s (a door without a leaf: Open s from the dwell's start), then the
--                     fade out (FadeOut s) while you walk on into the doorway; the server streams the other side in
--                     meanwhile (RequestStreamAroundAsync, Stream s at most) and moves you FadeOut + Margin s after the
--                     fade out was sent (Margin: the network's unevenness: the screen is black on the client by then);
--                     the client keeps it black until it sees itself there (within Arrive studs: Wait s at most), its
--                     camera behind you looking the way you face there, then Dark s more, then the fade in (FadeIn s).
--                     The crew mate or Danny at a pair piece's far end comes in the same dark moment, at that end
--                     8.5 walking through (the owner: "the doors should open when I'm at them, so it doesn't feel like
--                     I bumped into the door, but I keep walking smoothly, and then the transition"): the leaf opens as
--                     you come at its door, in its approach facing it or walking at it (your walk toward it at least
--                     PairWalk studs/s, its heading within Face of straight at it), or farther out walking at its
--                     doorway (your walk crosses its face within the approach's width in Lead s: a run finds it open);
--                     Open s quick, swinging out of the house (the sandbox house's leaves, as the interior's: seen
--                     against its dark doorway). The doorway is walkable: the house's body is solid but for a dark hall
--                     behind each of its doorways (Hall: Depth studs into the house, the opening's width and height,
--                     lined in Color: server/SandboxWorld.luau), Through reaching past it. Walking through is the trip:
--                     walking into the doorway (at PairWalk studs/s or more, mostly at it), your root across its
--                     threshold (Cross studs out of the doorway's face: outside the wall's, inside the inner one), or
--                     there within Ahead s at your walk (the server sees you a moment late and looks every Every s):
--                     the fade out starts at once while you walk on into the hall (onto the porch inside), the move
--                     behind the black, and you arrive still walking. Dwell stays for standing at a door facing it
--                     8.5.1 (the owner: "the doors, when you go into the house, just disappear. I'd like them to open
--                     nicely"; on the real house, rendered from a player's camera: 0.25 s of a cubic ease put the leaves
--                     half open in 50 ms and edge-on to the camera, square to the wall, by 150 ms: a black doorway with
--                     two slivers): Open 0.35 s along shared/DoorSwing.luau's quadratic ease (seen over its whole time),
--                     the sandbox house's leaves open Wide degrees (past square, folded back toward the wall: their
--                     faces stay in sight of whoever walks up), walking through waits for Seen × Open s of the leaf's
--                     swing before the fade (a walk from just beside the door: the swing mostly done before the screen
--                     darkens; from the approach it opened long before), and a client that first sees a leaf already
--                     opening (it streamed in, or the attribute came with its tag) swings it on from where it is now
--                     (its DoorOpenAt, the server's time it opened) instead of standing it open at once
--   Pack              the truck bed's packing (shared/MovingRules.luau fit): a thing rests on the highest top under
--                     it, at least Support of its footprint within Level studs of that (the floor: all of it) round its
--                     middle (not on one corner). The place it takes has the lowest score: − Contact × the share of its
--                     sides against the walls and the things beside it − Flush × the share of its edge level with its
--                     neighbours' tops + Waste × the air left under it (a share of its own room) + Base × its base +
--                     Side × its distance from the nearer side wall + Depth × its middle's distance from the cab
--                     (studs) + Dead × a sliver over it under Headroom studs (nothing goes there) + High × all the room
--                     over a fragile thing (it rides on top), both a share of its height. The fill counts a cell up to
--                     the roof when no flat Probe-stud square with Headroom over it covers it (Headroom 1.1: the
--                     smallest thing, the kitchen radio, is 1.1 tall). Lie: a both / pair piece with no place standing
--                     lies on its side (Placement.lying; server/Moving.luau's bedFrame rolls its model). Repack: a thing
--                     with no room as the bed is: the movers pack everything again, the biggest first (Load welds the
--                     moved models anew; the Load prompt says "won't fit" only when even that fails)
--   7.x farm move (chapter 1, Walt's Farm): a contract may have its own clock (time, hordeAt: s, over Time / HordeAt)
--                     and pay (pay: × the move's pay); a contract of kind "farm" stands at a Map.Places place (place,
--                     its site in Sites) instead of a Map.Homes house (home). It opens once its chapter's (shared/
--                     MoveStory.luau) chapters before it are done (the save's story flags "done:<chapter>")
--   Sites             a place's site (studs in the place's own frame from its Map.Places point: +X east, +Z south as
--                     the place stood before map step 2, Map.Relocations' turn turns them with it): Doors, in the plan's
--                     exits' order (exits[1] the farmhouse's front door, exits[2] the barn doors): At the door's foot
--                     outside, Facing out of it, Width, Name (the hints'); Curb: studs out of a door to the truck's
--                     middle (its back to the door: "Call truck to door"); Out: studs out of a door where you come out;
--                     House: the farmhouse (server/MoveSites.luau builds it: At its middle, Size width × wall height ×
--                     depth; its front door is Doors[1])
--   Sandbox           8.0 SANDBOX (Config.Sandbox.On; design/sandbox/KONTRAKT.md): in place of Contracts the houses of
--                     shared/SandboxMap.luau (Houses: their ids, names, front doors, the van's curbs), each refilled every
--                     move (a new HouseLayout seed), on the Moving contracts board of every player's plot (SandboxMap
--                     plot.board); the move goes with the player's own van (Config.Sandbox.Van, else Van). No Wall: the
--                     drop-off is the move owner's plot (plot.unload: the van's back inside its circle), where every piece
--                     in the van goes into their warehouse's stock (server/Collection.luau Collection.add: a trip). No pay
--                     per piece (the warehouse earns), no XP; no story. Icon: the cards'; HordeAt: the horde (s left);
--                     Horde: does it come at all; Roam: the zombies round the house while somebody is outside near it (0:
--                     none). Both off by default: the sandbox's client starts no guns (no Shooting, no Holster), so nothing
--                     to fight them with; the switches stay.
--                     8.3 the big move: The Old Farmstead (the owner's big Blender house, 44 × 14.5 × 34) empties as a big
--                     house: Kind its plan's (HouseLayout's "big", Config.Furniture.Big: more rooms, more pieces, a back
--                     door), a longer Time (the Sprinter's bed takes it home in several trips).
--                     8.9, 9.4 the countryside (design/countryside/plan.py): Houses, a contract per place to empty of
--                     SandboxMap.Houses (by its id; server/Moving.luau's kiosk offers one at a time, never one another
--                     player has): Client (a made-up Czech family), Address (by its road), Blurb (the card's), Kind (its
--                     plan: HouseLayout's "big" the farmstead, "house" the rest) and Time (the move's clock, s). Its pieces are its
--                     Kind's (HouseLayout): a family house Config.Furniture.Spots (18 – 24) and Collectibles.Count (1 – 2),
--                     19 – 26 pieces worth $5,700 – 14,000 at 90 % (Config.Collection's tuning), the farmstead Big.Spots
--                     (34 – 40) and Big.Collectibles.Count (2 – 3), 36 – 43 pieces worth $10,200 – 21,300: about half
--                     as much, so 15 minutes against the farmstead's 25 (tests/sandboxhouses_test.luau checks it)
--                     9.5 the countryside (design/countryside/): the five family houses are gone; six spots in open
--                     country instead, each a contract of its own: The Old Farmstead as ever, The Pond Cabin ("cabin"),
--                     The Lone House ("house", a family house's plan), The Forest Lodge ("lodge"), The Old Mill ("mill")
--                     and The Orchard Cottage ("cottage"): Kind its plan's (HouseLayout's; Config.Furniture.Countryside
--                     the new kinds' pieces), Address a short place, not a street number ("by the Little Pond"), Time
--                     by its size and its pieces (12 – 16 minutes: about the farmstead's minutes a piece)
Config.Moving = {
	Time = 12 * 60,
	HordeAt = 3 * 60,
	Fade = 0.35,
	CardFor = 240, -- s the contract card's START stays good after the board (or the admin) opened it (7.0 planning: the story's intro and briefing come first)
	Contracts = {
		{
			id = "marge",
			name = "Marge's House",
			client = "Marge",
			icon = "🏠",
			home = "home_suburbs_2_0_00", -- 155 Willow Ln, the nearest Suburbs house to the depot (its door faces north)
			seed = 1955,
			kind = "house",
			blurb = "Prologue: Marge's family house on Willow Lane. Get her things out before the Wall closes.",
		},
		-- 7.x farm move: chapter 1 "Hold Your Horses" (seed 1921: the Silver Spur's mark; its ★ pieces are Thunder's
		-- saddle, the branding iron and Grandma's milk churn, as shared/MoveStory.luau's keepsakes say)
		{
			id = "walt",
			name = "Walt's Farm",
			client = "Walt",
			icon = "🐴",
			place = "farm", -- Map.Places: the Old Farm (its site: Sites.farm)
			seed = 1921,
			kind = "farm",
			blurb = "Chapter 1: Walt's farm, the house and the barn. The hay wagon only fits through the barn doors.",
			time = 14 * 60,
			hordeAt = 3.5 * 60,
			pay = 1.25,
		},
	} :: { { id: string, name: string, client: string, icon: string, home: string?, place: string?, seed: number, kind: string, blurb: string, time: number?, hordeAt: number?, pay: number? } },
	Sites = {
		farm = {
			House = { At = { 45, -84 } :: { number }, Size = { 26, 10, 16 } :: { number } },
			Doors = {
				{ Id = "house", Name = "front door", At = { 45, -76 } :: { number }, Facing = { 0, 1 } :: { number }, Width = 4 },
				{ Id = "barn", Name = "barn doors", At = { -60, -64.4 } :: { number }, Facing = { 0, 1 } :: { number }, Width = 12 }, -- (World's barn: its doors' face)
			},
			Curb = 16,
			Out = 4,
		},
	} :: { [string]: { House: { At: { number }, Size: { number } }, Doors: { { Id: string, Name: string, At: { number }, Facing: { number }, Width: number } }, Curb: number, Out: number } },
	Van = "zdcvan",
	Beds = {
		zdcvan = { Width = 6.2, Length = 6.4, Height = 4.3, Cell = 0.4, Center = { 0, 2.98 } :: { number } }, -- (Cell 0.4: its whole 6.4 length, 15 × 16 cells)
		movingtruck = { Width = 7, Length = 10, Height = 7.4, Cell = 0.5, Center = { 0, 2.9 } :: { number } },
		sprinter = { Width = 6.6, Length = 13.7, Height = 7.6, Cell = 0.5, Center = { 0, 3.85 } :: { number }, Back = 0.9, WalkIn = true }, -- 8.0 SANDBOX (Center z: CargoDoor 11.6 − Back − Length / 2)
	} :: { [string]: { Width: number, Length: number, Height: number, Cell: number, Center: { number }, Back: number?, WalkIn: boolean? } },
	Hitch = { Gap = 1.2, Back = 7, Drop = 1.5 },
	VanAgain = 20,
	Board = { 44, 12 } :: { number },
	DropOff = { 34, 46 } :: { number },
	DropRadius = 20,
	Speed = { HandPerWeight = 0.03, MinHand = 0.6, Both = 0.75, Pair = 0.7, Drag = 0.35 }, -- (8.1: Pair 0.7, was 0.8: two carry slowly)
	Damage = { SafeDrop = 8, PerStud = 0.05, PerHp = 0.006, Death = 0.2, PerTruckHp = 0.002, Fragile = 2.5, BrokenAt = 0.2 },
	Pay = { Scale = 1, Star = 1.5, TimeBonus = 0.25, BrokenFine = 0.25, LateShare = 0.5, Xp = 40, XpPerValue = 8, XpPerStar = 20, XpMax = 400 },
	LateGrace = 120, -- 7.0 review: s after 0:00 the truck still has to reach the Wall (it pays LateShare); later: lost
	Present = 250,
	Tether = 6,
	Grace = 1.5,
	PairLift = { Hands = 0.3, Grip = 2.4, Clear = 0.5 }, -- 8.6
	Pace = { Factor = 1.8, Slack = 8 },
	Horde = {
		Count = 14,
		Bursts = 3,
		Every = 12,
		Near = 45,
		Far = 110,
		Kinds = { walker = 0.55, runner = 0.25, brute = 0.12, bloater = 0.08 } :: { [string]: number },
	},
	Roam = { Count = 3, Range = 220, Every = 8, Near = 50, Far = 110, Kinds = { walker = 0.8, runner = 0.2 } :: { [string]: number } },
	Reach = { Board = 12, Door = 10, Exit = 10, Item = 10, Truck = 12 },
	Doors = {
		Walk = true, Depth = 3.5, Through = 11, Side = 0.5, Height = 9, Face = 0.3, Rearm = 2, Every = 0.1, PairWalk = 1.5, Mat = { 6, 2.2 } :: { number }, -- 8.1 walk-in doors (8.5: Through 11, was 6: the house's dark hall)
		Dwell = 0.15, -- (8.3: 0.15, was 0.25: the leaf's Open comes first; 8.5: for standing at a door, walking through needs none)
		-- 8.3 the leaves and the trip (server/Moving.luau's WalkIn and travel, client/WalkDoors.luau, client/Fade.luau)
		-- (8.5: Approach 12 and ApproachSide 3, were 8 and 2; Open 0.25, was 0.35: the leaf open before you get there)
		Swing = true, Approach = 12, ApproachSide = 3, Angle = 95, Open = 0.35, Close = 0.45, Shut = 1.2, -- (8.5.1: Open 0.35, was 0.25)
		FadeOut = 0.25, Margin = 0.1, Stream = 2, Wait = 1.5, Arrive = 6, Dark = 0.15, FadeIn = 0.35,
		Sound = { Open = 0.55, Shut = 0.4, ShutPitch = 0.75, Range = 70 },
		-- 8.5 walking through (server/Moving.luau's WalkIn.coming and check; server/SandboxWorld.luau's door halls)
		Lead = 0.9, Cross = 0, Ahead = 0.15,
		Hall = { Depth = 11, Color = { 24, 18, 14 } :: { number } },
		Wide = 110, Seen = 0.6, -- 8.5.1 (the doors opening nicely)
	},
	Slots = 6,
	Tick = 0.2,
	Pack = { Support = 0.4, Level = 0.35, Contact = 7.5, Flush = 3.6, Waste = 4.2, Base = 0.3, Side = 0.45, Depth = 0.4, Dead = 2.4, High = 2.4, Headroom = 1.1, Probe = 1, Lie = true, Repack = true },
	Sandbox = {
		Icon = "🏡",
		-- a contract per place to empty of SandboxMap.Houses (its id), the families made up
		Houses = {
			sandbox_house = {
				Client = "The Nováks", -- (The Hubers in the Alps)
				Address = "the end of Pražská",
				Blurb = "A big old house packed full of things. Too much for one van: plan several trips home to your warehouse.",
				Kind = "big", -- 8.3: the big house's plan (shared/HouseLayout.luau, Config.Furniture.Big)
				Time = 25 * 60, -- (8.3: the big house's, was 20 min: it takes several trips)
			},
			-- 9.5 the countryside's spots (SandboxMap.Houses' ids; the families made up, Czech names, as ever)
			pond_cabin = {
				Client = "The Vodičkas",
				Address = "by the Little Pond",
				Blurb = "Grandpa's fishing cabin by the pond: rods, nets and an outboard motor. The motor is a two-person job.",
				Kind = "cabin", -- (shared/Layouts/Countryside.luau: a timber fishing cabin, its bunk room and its store)
				Time = 12 * 60,
			},
			lone_house = {
				Client = "The Kopeckýs",
				Address = "on Hill Road",
				Blurb = "The last house up the hill before the woods. The Kopeckýs are moving to the city at last.",
				Kind = "house", -- (a family house's plan, HouseLayout's "house")
				Time = 16 * 60,
			},
			forest_lodge = {
				Client = "The Lesáks",
				Address = "in the Black Wood",
				Blurb = "The old forester's lodge: antlers, a stuffed owl and a gun cabinet (empty, thank goodness).",
				Kind = "lodge",
				Time = 15 * 60,
			},
			old_mill = {
				Client = "The Mlynářs",
				Address = "on the mill stream",
				Blurb = "The old watermill still smells of flour. The spare millstone weighs a ton: grab a friend or Danny.",
				Kind = "mill",
				Time = 15 * 60,
			},
			orchard_cottage = {
				Client = "The Sadíleks",
				Address = "in the old orchard",
				Blurb = "A whitewashed cottage among the apple trees: jam jars, a beehive box and Grandma's sewing machine.",
				Kind = "cottage",
				Time = 13 * 60,
			},
		} :: { [string]: { Client: string, Address: string, Blurb: string, Kind: string, Time: number } },
		HordeAt = 3 * 60,
		Horde = false, -- (off: nobody carries a gun in the test world; true: the horde at HordeAt left)
		Roam = 0, -- (none, as the horde; e.g. 2: a few round the house)
		-- 8.4: a house's seed is a whole number 1 … this (server/Moving.luau rolls it); the one a player's card shows is
		-- kept in their save until a trip brings something home (server/PlayerData.luau's sandboxHouseSeed: another
		-- number there is none); with its house (sandboxHouse, a SandboxMap.Houses id)
		Seeds = 1073741823,
	},
}

-- 7.0 planning (design/rework/NAVRH.md §2–3, step 2 of §7): the planning lobby before a move and the three roles (the
-- owner took the Technician out: no locked front door, no fuse box, the house is lit from the start; the client greets
-- the crew at the door instead: Config.MoveGreeters). shared/MoveRoles.luau has the rules (tests/moveroles_test.luau), server/MoveLobby.luau the lobby and the quick chat,
-- server/Moving.luau the roles' abilities, client/MoveLobbyUi.luau, client/QuickChat.luau and client/MovingHud.luau
-- show them.
--   On                8.8 (the owner: "I don't want roles in the game. Everyone is simply the same."): the roles at
--                     all (MoveRoles.on), the city's only: the sandbox (Config.Sandbox.On) never has them, whatever this
--                     says. Without them nobody picks or has a role (the lobby is the crew, READY and LAUNCH; the HUD
--                     has no role line), everybody loads and unloads the van with no wait, anybody calls it to the
--                     door once a move (whoever is first: Driver.Curb, Driver.Near), and nobody has the Mover's or the
--                     Guard's perks (no pair piece carried alone, everybody × Mover.Climb up stairs, no damage bonus,
--                     barricades or sight through walls) nor the Driver's truck damage. false takes them out of the
--                     city too.
--   Order             the roles, in the lobby's order (a newcomer gets the first free one)
--   Switch            s between two role switches on a move (solo: switch to do everything; a crew: a free role)
--   Lobby             Timeout: s the planning stays open; Tick: its loop (the crew joining and leaving); TouchScale:
--                     the lobby window at least this big on a touch screen (it scrolls there; Ui.screenScale may be 0.55)
--   Driver            TruckDamage: × a hit on the truck (and so on its load) while a Driver is at its wheel; the
--                     truck's Load / Unload wait nothing for a Driver (client/MovingHud.luau); "Call truck to door"
--                     once a move: to the house's curb (Curb studs from the road's middle) unless somebody sits in it
--                     or it stands within Near of it already
--   Mover             Alone: × the walk with a pair thing ALONE (carried, not dragged at Moving.Speed.Drag); Carry: ×
--                     the carry's walk on everything else (never over the walk); the others go up stairs and slopes
--                     (Rise studs up a stud along, held Hold s) at × Climb with anything not one-handed, a Mover not
--   Guard             Damage: × weapon damage on the move's zombies (within Range of its house's door or its truck);
--                     Barricades a move, each Hp (Bite hp a second off it for every zombie within Reach) for Life s, put
--                     up outside within Near of the house's door (off the road, clear of cars and players); XRay: the
--                     zombies outlined through walls within this (client/EnemyOutline.luau)
--   Chat             the quick chat (hold T): Bubble s over the sender, Feed s in the move's HUD, Hold s of T
Config.MoveRoles = {
	On = true, -- (the city's; the sandbox has none)
	Order = { "driver", "mover", "guard" } :: { string },
	Switch = 30,
	Lobby = { Timeout = 15 * 60, Tick = 0.5, TouchScale = 0.75 },
	Driver = { TruckDamage = 0.6, Curb = 5, Near = 25 },
	Mover = { Alone = 0.6, Carry = 1.15, Climb = 0.75, Rise = 0.35, Hold = 0.8 },
	Guard = { Damage = 1.5, Range = 150, Barricades = 2, Hp = 400, Bite = 30, Reach = 4.5, Life = 120, Near = 40, XRay = 60 },
	Chat = { Bubble = 4, Feed = 6, Hold = 0.18 },
}

-- 7.0 prototype, the moving (design/rework/NAVRH.md): the furniture a moving job carries out of a house and the house
-- it stands in. shared/FurnitureLooks.luau draws every piece (its catalogue: size, class, weight, value),
-- shared/HouseLayout.luau lays a house out (rooms, doors, where every piece stands), server/HouseInterior.luau builds it
-- far off the map. Studs throughout.
--   MaxParts           a piece's parts at most, its invisible Root included (tests/furniture_test.luau builds each)
--   Ceiling / Wall     the rooms' height and the walls' thickness
--   DoorHeight         every doorway's height; Door, FrontDoor and HallOpening their widths (a "pair" piece passes Door)
--   HallWidth          the entrance hall's width between its walls' middles (the front door in its middle)
--   Corridor           the corridor's width between its walls' middles (inside: Corridor - Wall)
--   Spots              a house's pieces: at least, at most; Stars of them the client's ★ (sentimental first)
--   Gap / WallGap      the room left between two pieces / between a piece and the wall behind it
--   FixtureGap         the room left between a piece and the built-in things (counters, the tub)
--   DoorClear          how far into a room a doorway is kept clear (nothing stands there)
--   WindowSill         the windows' sill; a piece taller than this stands clear of them
--   Window             a window's width and height (BathWindow: the bath's small high one)
--   EntryIn / EntryUp  where you appear: this far in from the front door, the root this high over the floor
--   Grid               the reachability check's step (every piece must get out of the front door, carried)
--   Slot               the interiors' places, far off the map (Map.Bounds): Origin { x, y, z }, Spacing along X
--   Ground             the safety floor under an interior: this far round the house, this deep under its floor
--   InteriorMaxParts   an interior's parts at most, its furniture included (tests/houseinterior_test.luau; 7.x alpine:
--                      620, was 600: the chalet's beams, Kachelofen, corner bench and shelf, lace, painted front door,
--                      antlers and pictures add about 30 parts, the one plank floor, the tiled bathroom walls, the one sink
--                      run and the handle-less cabinets win back about 16; seeds 1-1000: the busiest 614 (was 599), on
--                      average 558 (was 539)); 8.0 SANDBOX: 700 (the farm's), was 620: a house's 2-4 collectibles add
--                      about 48 parts (seeds 1-1000: the busiest 688, seed 174; on average 606)
--   Light              the ceiling lights: Brightness, Range (a long corridor gets a second one past LongRoom); 7.x alpine:
--                      a warmer Color
--   DoorLight          the daylight through the front door (a SurfaceLight on the porch's glow)
--   Alpine             7.x, a house's inside as a chalet's (shared/HouseLayout.luau places, server/HouseInterior.luau draws):
--                      Stove the living room's Kachelofen (along its wall, tall, deep: its bench in front included); Bench
--                      the kitchen's corner bench (its long leg on the outer wall, its short leg on the back wall, deep,
--                      tall with its back); Shelf the Herrgottswinkel's corner shelf over it (its legs, its height over the
--                      floor); Wainscot the wood panelling's height on the walls; Decor the wall decor's bottom over the
--                      floor (over every piece), Picture and Antlers their size (wide, tall, deep); Beam a ceiling beam's
--                      thickness, BeamRows the beams across a row of rooms
Config.Furniture = {
	MaxParts = 30,
	Ceiling = 12,
	Wall = 1,
	DoorHeight = 9,
	Door = 6,
	FrontDoor = 7,
	HallOpening = 10,
	HallWidth = 12,
	Corridor = 8,
	Spots = { 18, 24 } :: { number },
	Stars = 3,
	Gap = 0.5,
	WallGap = 0.1,
	FixtureGap = 0.3,
	DoorClear = 5,
	WindowSill = 4,
	Window = { 5, 4 } :: { number },
	BathWindow = { 3, 2.5 } :: { number },
	EntryIn = 4.5,
	EntryUp = 3,
	Grid = 0.5,
	Slot = { Origin = { 9000, 400, 9000 } :: { number }, Spacing = 600 },
	Ground = { Margin = 24, Depth = 4 },
	InteriorMaxParts = 700,
	Light = { Brightness = 0.9, Range = 30, LongRoom = 40, Color = { 255, 218, 168 } :: { number } },
	DoorLight = { Brightness = 1.6, Range = 18, Color = { 255, 246, 226 } :: { number } },
	Alpine = {
		Stove = { 6, 6.6, 3.2 } :: { number },
		Bench = { 7, 2.4, 1.6, 3.4 } :: { number },
		Shelf = { 2.2, 4.9 } :: { number },
		Wainscot = 3.8,
		Decor = 7.6,
		Picture = { 2.6, 2.0, 0.2 } :: { number },
		Antlers = { 2.6, 2.0, 0.6 } :: { number },
		Beam = 0.9,
		BeamRows = 2,
	},
	-- 8.0 SANDBOX collectibles (design/sandbox/KONTRAKT.md): the rare pieces (shared/FurnitureLooks.luau's with a
	-- rarity) a house (HouseLayout.plan(seed, "house")) holds besides its Spots, after them and on their own dice (the
	-- seed + Salt), so the house's own pieces and its ★ stay as they were; never ★ themselves:
	--   Count       how many (at least, at most)
	--   Legendary   the chance a house holds a legendary one (one at most; 8.3 economy: one house in 25, the big one's
	--               one in 17: a legendary is a find)
	--   Odds        the others' rarities, by weight (a piece that finds no place gives way to one of the rarity below)
	Collectibles = {
		Count = { 1, 2 } :: { number },
		Legendary = 0.04,
		Odds = { uncommon = 70, rare = 25, epic = 5 } :: { [string]: number },
		Salt = 8017,
	},
	-- 8.3 the big house (the sandbox's one house, the owner's big Blender house: HouseLayout.plan(seed, "big"), one big
	-- floor laid out as a house's, bigger): six rooms in the back row (the house's four, a guest room and a study), a
	-- bigger front row (Front: its depth's least, 2 more a die step; Kitchen: the kitchen's least share of the front row
	-- beside the hall), and a second way out, the back door (BackDoor wide) at the corridor's east end. Every piece gets
	-- out by both doors. Its lights and Neon are every house's (Config.SandboxLight.House).
	--   Spots / Stars          its pieces (at least, at most) and its ★ ones
	--   Collectibles           its collector's pieces (Count: at least, at most; Legendary: the chance of one), the
	--                          house's Odds and Salt
	--   InteriorMaxParts       an interior's parts at most, its furniture included (tests/biglayout_test.luau)
	--   Roomy                  8.5.2 (the owner: "more room in the house"): its rooms, its hall and its corridor this
	--                          many times as wide and deep (whole studs; the dice, the doors and the furniture as they
	--                          were: 1.25, half as much floor again round the same pieces; 1: as before, at most 2)
	Big = {
		Front = 26,
		Kitchen = 0.4,
		BackDoor = 6,
		Roomy = 1.25,
		Spots = { 34, 40 } :: { number },
		Stars = 4,
		Collectibles = { Count = { 2, 3 } :: { number }, Legendary = 0.06 },
		InteriorMaxParts = 1100,
	},
	-- 7.x, Walt's farm (chapter 1 "Hold Your Horses": shared/Layouts/Farm.luau lays it out, HouseLayout.plan(seed,
	-- "farm"); server/HouseInterior.luau's farm block builds the barn and the yard). Studs, the walls' middles:
	--   HouseWidth / HouseDepth   the farmhouse (an even width); Hall: its mud room, a hall straight through it from the
	--                             front door to the BackDoor (that wide) into the yard; Kitchen / Pantry: those rooms'
	--                             depth behind the Stube and the bedroom
	--   StoveClear                the Stube's door to the kitchen stays this far from the Stube's outer wall (its
	--                             tiled stove, the Kachelofen, stands in that corner)
	--   Yard                      the yard's depth (open to the sky; its fences Fence high, an invisible wall over them
	--                             up to Barrier)
	--   BarnDepth / Threshing / Stable / Workshop   the barn's depth and its three rooms' widths (the threshing floor in
	--                             the middle, an even width); BarnCeiling: its rooms' height
	--   BarnDoor / BarnDoorHeight the barn doors (the second exit, in the threshing floor's back wall: a bigDoor piece
	--                             leaves only there); BarnOpening: the doorways from the yard and inside the barn
	--   Stalls / Stall / StallWall   the stable's horse stalls along its back wall: how many, { width, depth }, the
	--                             partitions' height; Loft: the hay loft's floor over the stable (decor); Beam: the tie
	--                             beams' underside
	--   BarnWindow / BarnSill     the barn's small windows (width, height) and their sill
	--   Spots / Stars             the farm's pieces (at least, at most) and its ★ ones (the sentimental first)
	--   InteriorMaxParts / Lights an interior's parts and lights at most (tests/farminterior_test.luau)
	--   Lantern                   the barn's hanging lanterns' light; BarnLight: the daylight through the barn doors;
	--                             Apron: the ground outside them (like the porch)
	Farm = {
		HouseWidth = { 40, 44 } :: { number },
		HouseDepth = { 28, 32 } :: { number },
		Hall = 10,
		Kitchen = { 12, 14 } :: { number },
		Pantry = { 9, 11 } :: { number },
		BackDoor = 6,
		StoveClear = 8.5,
		Yard = { 14, 18 } :: { number },
		Fence = 7,
		Barrier = 24,
		BarnDepth = { 32, 35 } :: { number },
		Threshing = { 20, 24 } :: { number },
		Stable = { 21, 23 } :: { number },
		Workshop = { 15, 18 } :: { number },
		BarnCeiling = 20,
		BarnDoor = 12,
		BarnDoorHeight = 13,
		BarnOpening = 10,
		Stalls = 3,
		Stall = { 6.5, 9 } :: { number },
		StallWall = 5,
		Loft = 11,
		Beam = 14,
		BarnWindow = { 3, 2.5 } :: { number },
		BarnSill = 7,
		Spots = { 22, 30 } :: { number },
		Stars = 3,
		InteriorMaxParts = 700,
		Lights = 12,
		Lantern = { Brightness = 1.1, Range = 30, Color = { 255, 206, 140 } :: { number } },
		BarnLight = { Brightness = 1.6, Range = 22, Color = { 255, 246, 226 } :: { number } },
		Apron = 6,
	},
	-- 9.5 the countryside (the owner: "instead of those houses make rather six different spots: by the pond, on the farm,
	-- one house, somewhere else again ... not any towns, and not villages"): the four new places to empty and their
	-- insides, shared/Layouts/Countryside.luau's plans (HouseLayout.plan(seed, kind) for the kinds below: the Pond Cabin's
	-- "cabin", the Forest Lodge's "lodge", the Old Mill's "mill", the Orchard Cottage's "cottage"; the Lone House is a
	-- family house's "house"); server/HouseInterior.luau builds each in its own style. Per kind:
	--   Box            the building's footprint on the map (SandboxMap.Houses' box: along its front × deep)
	--   Ceiling        its rooms' height (the mill's workroom is tall: its millstones' hopper)
	--   Spots / Stars  its pieces (at least, at most) and its ★ ones (its recipes' star entries first)
	--   Collectibles   its collector's pieces: Count (at least, at most), Legendary (the chance of one); the house's Odds
	--                  and Salt; the kind's own themed ones (Countryside.Themes in the layout) tried first in a rarity
	--   InteriorMaxParts  an interior's parts at most, its furniture included (tests/countryside_test.luau)
	--   Scale          an inside is its Box × Scale (whole even studs between its outer walls' middles), as a family
	--                  house's inside is about twice its 30 × 24 box
	Countryside = {
		Scale = 1.7,
		cabin = { Box = { 24, 18 } :: { number }, Ceiling = 11, Spots = { 12, 15 } :: { number }, Stars = 2, Collectibles = { Count = { 2, 4 } :: { number }, Legendary = 0.05 }, InteriorMaxParts = 520 },
		lodge = { Box = { 28, 22 } :: { number }, Ceiling = 12, Spots = { 18, 22 } :: { number }, Stars = 3, Collectibles = { Count = { 2, 4 } :: { number }, Legendary = 0.05 }, InteriorMaxParts = 640 },
		mill = { Box = { 24, 26 } :: { number }, Ceiling = 15, Spots = { 16, 20 } :: { number }, Stars = 2, Collectibles = { Count = { 2, 4 } :: { number }, Legendary = 0.05 }, InteriorMaxParts = 600 },
		cottage = { Box = { 26, 20 } :: { number }, Ceiling = 11, Spots = { 14, 18 } :: { number }, Stars = 3, Collectibles = { Count = { 2, 4 } :: { number }, Legendary = 0.05 }, InteriorMaxParts = 580 },
	},
	-- 9.5 the countryside's own pieces (shared/FurnitureLooks.luau draws them and reads its catalogue's numbers here; the
	-- collection book lists them with the rest): Class ("hand" one hand; "both" both hands; "pair" two people, or one
	-- dragging it), Weight (1 … 10), Value ($: under every collectible of its class) and Fragile
	Pieces = {
		-- the Pond Cabin's: the fishing things in its store, the bunk room's bed
		tackle_box = { Class = "hand", Weight = 2, Value = 90, Fragile = false },
		fishing_rods = { Class = "both", Weight = 2, Value = 320, Fragile = true },
		landing_net = { Class = "hand", Weight = 1, Value = 45, Fragile = false },
		oars = { Class = "both", Weight = 3, Value = 110, Fragile = false },
		outboard_motor = { Class = "pair", Weight = 7, Value = 620, Fragile = false },
		cool_box = { Class = "both", Weight = 3, Value = 70, Fragile = false },
		folding_chair = { Class = "hand", Weight = 1, Value = 30, Fragile = false },
		coal_scuttle = { Class = "hand", Weight = 3, Value = 55, Fragile = false },
		bunk_bed = { Class = "pair", Weight = 7, Value = 380, Fragile = false },
		-- the Forest Lodge's
		antler_trophy = { Class = "both", Weight = 2, Value = 380, Fragile = true },
		gun_cabinet = { Class = "pair", Weight = 9, Value = 420, Fragile = false },
		log_basket = { Class = "both", Weight = 4, Value = 60, Fragile = false },
		stuffed_owl = { Class = "hand", Weight = 1, Value = 240, Fragile = true },
		boot_rack = { Class = "both", Weight = 3, Value = 70, Fragile = false },
		oak_table = { Class = "pair", Weight = 9, Value = 520, Fragile = false },
		-- the Old Mill's
		flour_sacks = { Class = "both", Weight = 4, Value = 40, Fragile = false },
		grain_scales = { Class = "both", Weight = 5, Value = 240, Fragile = false },
		grain_crate = { Class = "both", Weight = 4, Value = 50, Fragile = false },
		millstone = { Class = "pair", Weight = 10, Value = 780, Fragile = false },
		sack_trolley = { Class = "both", Weight = 3, Value = 80, Fragile = false },
		joiners_bench = { Class = "pair", Weight = 8, Value = 260, Fragile = false },
		-- the Orchard Cottage's
		fruit_crates = { Class = "both", Weight = 3, Value = 50, Fragile = false },
		jam_shelf = { Class = "both", Weight = 4, Value = 150, Fragile = true },
		bee_box = { Class = "both", Weight = 4, Value = 180, Fragile = true },
		rocking_chair = { Class = "both", Weight = 4, Value = 160, Fragile = false },
		plate_dresser = { Class = "pair", Weight = 8, Value = 420, Fragile = true },
		sewing_machine = { Class = "both", Weight = 5, Value = 480, Fragile = false },
		apple_press = { Class = "pair", Weight = 8, Value = 360, Fragile = false },
		flower_pots = { Class = "hand", Weight = 2, Value = 35, Fragile = true },
	} :: { [string]: { Class: string, Weight: number, Value: number, Fragile: boolean } },
}

-- 7.0, the moves' story "The Last Move" (shared/MoveStory.luau: the chapters and their words; client/MoveStoryUi.luau
-- shows the story cards, the CHAPTERS on the contract card and the client's thanks on the result card; Marge's texts go
-- out from server/Moving.luau's MoveStory hook). The limits keep every text inside its card (movestory_test.luau):
--   Limits      characters at most: a chapter's Title, Place and Client name, its Hook (the CHAPTERS detail), the
--               client's Blurb, a story card's Line (the intro, a briefing, the radio's Taunt), a Keepsake's story,
--               Marge's phone Text (the dispatch at START, the debrief at the end), the result card's Quote (thanks)
--               and a greeter's Bubble (the speech bubbles of server/MoveGreeters.luau: MoveStory's greeter section)
--   Briefing    a briefing's lines (at least, at most); Intro: Marge's intro cards (at least, at most)
--   Great       a move done with this many stars or more is "great" (its debrief and thanks), with fewer "ok"
--   Guard       s after a story card opens before Space / Enter / A turn it (client/DialogKeys.luau)
Config.MoveStory = {
	Limits = { Title = 24, Place = 32, Client = 24, Hook = 240, Blurb = 120, Line = 130, Keepsake = 90, Text = 130, Quote = 110, Bubble = 60 },
	Briefing = { 3, 5 } :: { number },
	Intro = { 3, 4 } :: { number },
	Great = 4,
	Guard = 0.35,
}

-- 7.0, the depot's helper ("Danny from the depot": server/MoveHelper.luau, his decisions shared/MoveHelperBrain.luau,
-- tests/movehelper_test.luau; the owner: solo play is allowed with an AI helper). An NPC mover who comes with a move
-- whose crew is one player. 7.x (the owner: "he helps weirdly, mainly we don't carry anything together"): a partner who
-- carries with you. 8.3 for hire (the owner: "I have to PAY for him when I want help … you click on something, and that
-- assigns it to him, and the rest you carry yourself"; "he must sit in my car with me"): he waits by the van until a
-- crew player hires him for the move (Hire), then carries the pieces the crew clicks (Queue) to the van, lifts the
-- two-person ones with you and rides in the van's passenger seat.
--   Solo / Duo         a crew of one / of two players has him by the van for hire (Duo: off); once hired he stays with
--                      any crew until the move ends (or his hirer leaves it)
--   Name / Title       his name tag
--   Health / Respawn   his health; at 0 he drops what he holds and is back at the van Respawn s later
--   Speed              × the walk (Config.Movement.Walk), and × the carry's (MovingRules.speedFactor) with a piece:
--                      slower than a player; Sprint: × the walk on his way to your lift (8.3: and to the van's seat)
--   KeepUp / Flee      × the pair's carry speed (his speed's word for "with you"); × the walk running away
--   Tick / Think / Repath   s between his steps / his looks for the next piece / two paths (PathfindingService)
--   HelpFar            studs (the way there, the door counted) he comes from to help lift; HelpRetry: s before he tries
--                      a lift again whose take failed
--   BlinkFar / HelpBlink   your lift farther than BlinkFar studs on foot, his path failing, or not there HelpBlink s after
--                      he set off: he fades over to its far end (a quick fade-out, there, a fade-in) and takes it (8.3:
--                      only with WaitForHelper false; with it he walks, CallGain / CallBlink the last resort)
--   Standoff / HoldStep   his root stands Standoff studs past your piece's far face, turned to you, on the floor there
--                      within HoldStep studs of the floor under you (stairs, steps; 8.3: of your feet's floor, not your
--                      root's height: your jump never lifts him; a floor farther off, a roof or a ceiling, is not his)
--   HoldResponse       the Responsiveness of the constraints that keep him there (AlignPosition / AlignOrientation on
--                      his root); his own walk is off meanwhile (Npcs.carried)
--   8.6 (the owner: "he teleports from side to side"; a screenshot: Danny beside the Dining Table, at its side): his end is
--   the face of the piece across it from you, decided once as the hold starts, in the piece's own frame (MoveHelperBrain.
--   holdEnd; a crew mate's too, server/PairHold.luau): carried in two the piece lies along the carry (Config.Moving
--   PairLift), so that is the far end of its length; its turn, a square-ish piece, a lag never make it another end
--   Edge               carrying in two, the hands of both (yours and the far end's: client/ArmPose.luau's box, the
--                      CarryAt / CarrySize attributes) on its end's edge at its grips' height: Width across at most,
--                      Height, Depth (studs); 9.0 Reach: studs his hands reach on toward it at most, following you (his
--                      body never in the piece: HoldLead.In)
--   8.1 carrying in two (the owner: "when I turn around he teleports … we must walk, like, backwards and slowly"; shared/
--   PairCarry.luau the leader's steering, MoveHelperBrain.holdSpeed / holdTrack the far end's holder, server/PairHold.luau
--   the constraints; Danny and a crew mate who helps lift alike):
--   PairTurn           degrees a second the carry's heading (the leader's facing, the piece welded in front of it) turns
--                      at most toward where the leader walks while two carry a piece (client/PairSteer.luau); PairBand:
--                      degrees past 90 the way must be behind the facing before the leader walks backwards (and under
--                      90 before forwards again: no flicker sideways)
--   PairTurnWalk / PairTurnFull   × the pair's walk (Moving.Speed.Pair) while the heading is PairTurnFull degrees or
--                      more off its way (in between: less slow)
--   HoldMargin / HoldExtra   the far end's holder's top speed (AlignPosition.MaxVelocity): the carry's walk × HoldMargin
--                      + HoldExtra studs/s (the swing of a turn at PairTurn fits in); HoldTurn: × PairTurn his body
--                      turns at most (AlignOrientation.MaxAngularVelocity)
--   HoldBehind / HoldStuck / HoldEase   more than HoldBehind studs off his place for HoldStuck s: eased back over HoldEase
--                      s (never put there at once while holding; only a door's fade does: the piece in the other world)
--   8.3 (the owner: "he just jumps weirdly"; MoveHelperBrain.holdClimb / holdLegs, server/PairHold.luau's lift):
--   HoldClimb          studs a second his height goes up or down at most holding the far end (a step or a kerb stepped,
--                      never popped): the floor under his end followed that fast, and the lift (his root's own
--                      AlignPosition, up and down only) at most that fast
--   HoldLegs           his legs holding it (Npcs.stride, the far bodies' walk; near ones the clients' gait): stepping from
--                      From studs/s of his own speed along the ground, standing under To; backwards once the way is more
--                      than Band of it behind him, forwards once more than Band ahead (sideways: the way they went)
--   8.3 keeping up (the owner: "when I run, he just goes behind me with his arms stretched out"; MoveHelperBrain.
--   holdPace / holdSpeed / holdLead, server/MoveHelper.luau's actHold, server/PairHold.luau's follow, client/
--   PairSteer.luau's walk cap and RunHint):
--   HoldCap            studs/s: the holder's top speed follows the leader's real speed along the ground (their root's,
--                      measured at each look: × HoldMargin + HoldExtra on top, never under the carry's own), at most
--                      this (unless the carry's own walk, an admin's boost, needs more)
--   HoldPace           the leader's real speed measured: a rise is taken at once (to HoldCap at most), a fall over Fall
--                      s (one slow look never slows him while you walk on); a root more than Jump studs off its last
--                      look's place went there at once (a door's fade, a respawn): nothing measured
--   HoldLead           Danny only (the leader is the only one who sees him): he is aimed this many seconds of the
--                      leader's velocity ahead of his place (Base + the leader's ping, Player:GetNetworkPing, × Ping;
--                      Most s, Far studs at most; the velocity smoothed over Smooth s), so on the leader's screen, where
--                      his body shows that late, he walks at his end (Base 0 and Ping 0: off). A crew mate is not led
--                      (on their own screen they would walk ahead of the piece). 8.6 (the owner: "he teleports from side
--                      to side"): the velocity is his END's own (the piece's turn moves it too: MoveHelperBrain.endLead),
--                      and the lead changes Rate studs a second at most (it was your root's velocity, taken at once: a
--                      step back, a turn's step aside, an uneven look at you threw his aim up to Far × 2 studs across in
--                      a tenth of a second, and he ran there)
--   9.0 (the owner, 8.9.3: "Danny carries better now, but only when I walk backwards. When I want to walk forwards,
--   Danny can't walk backwards"; then "and he still teleports", a screenshot of Danny standing inside the Sofa):
--   HoldLead.In        studs his lead may take him toward the piece's middle at most (0: his body never goes into the
--                      piece, a stop after you walked backwards never leaves him in it; his hands reach on instead,
--                      Edge.Reach); HoldLead.Back: s more of lead while he walks backwards himself (your screen may show
--                      him later than the lead's guess: he stays clear of the piece, his hands reach on by it)
--   PairStart          s the carry in two takes from standing to its full walk (client/PairSteer.luau, shared/PairCarry.
--                      luau: the walk eases in, again after the way turns round): the far end's holder is shown on your
--                      screen a moment late, and a start at once ran the piece into him before he could step back
--                      (9.2: a held far end only, a crew mate's: Danny driven by the leader's client has none, PairLead)
--   PairKeep           the far end's holder as YOUR screen shows him (the character attributes PairFar: his place in
--                      your root's frame; PairWith: Danny's MoveHelperId, a crew mate's UserId): shown more than Wait
--                      studs nearer than his place, your walk's start waits for him (shared/PairCarry.luau waits); From
--                      studs nearer your walk toward him starts to go, all of it at Stop (keep): you never push the
--                      piece into him, whatever the lag
--   HoldWall           inside a house (its plan's wall slabs: shared/HouseRoute.luau slide) his place keeps Clear studs
--                      off the walls, sliding along them, never through; held back by a wall (his lead looks ahead), the
--                      leader's walk into that wall loses that many studs' share of Block (the character attribute
--                      PairWall: client/PairSteer.luau takes it away): slowed as he nears the wall, stopped against it
--                      (9.2: Clear is also his body's clearance the leader's client keeps off a wall, PairLead)
--   9.2 (the owner, 8.9.5: "the carrying is better, but it feels like it's harder to control … fix it so it's
--   playable"; 8.9.4 hid his server-held body's lag by holding your walk back: its start took 0.85 s in Studio, 2 s
--   online): while Danny holds the far end of a piece a PLAYER leads, that player's client drives his end (server/
--   PairHold.luau lead: his body's physics theirs, SetNetworkOwner; client/PairLead.luau sets his hold's goals from
--   their own piece every frame before the physics): nothing late to hide, so PairStart, PairKeep and PairWall are
--   only a crew mate's now (and Danny's when the server holds him: PairLead.On false, a drive it took back)
--   PairLead           On: the leader drives Danny's end (false: the server holds him as in 8.9.4, his lead and all);
--                      Turn: degrees a second the leader's heading turns meanwhile (PairTurn stays a crew mate's),
--                      TurnWalk: × the walk while it turns PairTurnFull or more (PairTurnWalk: a crew mate's); Glide:
--                      studs a second over his place's own speed he closes on it until he is there (the first catch-up
--                      glides the last studs, never a snap); Settle: studs off his place where he is there (rigid from
--                      then: Rigid studs a second, Spin radians a second his turn), Loose: studs off it where he glides
--                      again; Jump: his place this far off (a door's trip into or out of the house, its interior far
--                      off the map): put there at once; Soft: studs before his body's clearance from a wall of the house
--                      (HoldWall.Clear) where the leader's walk or turn pushing his end into it starts to go (all of it
--                      at the clearance; along the wall it stays); Sane / Grace: the server's look, his body more than
--                      Sane studs off his end in its own view for Grace s (a door's trip aside): it takes his body back
--                      and holds him itself for the rest of that carry (an exploit's fling, a client that stopped
--                      driving: walked back at the hold's speed, never put there); Look: s between two looks for the
--                      house's walls and floors while a carry in two is driven
--   RunHint           carrying in two (the character attribute CarryPair on both players, server/Moving.luau setHands)
--                      nobody runs: the walk is held at CarrySpeed (× the admin's and kit's boosts) every step, and the
--                      run key or button says this once a carry
--   PathRadius / PathHeight / PathSpacing   his paths (PathfindingService: never a jump, never a climb); PathAgain:
--                      studs his goal moves off a path's end before he asks for a new one; PathDrift: studs it may move
--                      off it while he still follows that path (then on from its end; straight lines only while no path
--                      is known: a straight line meets the low fixtures he would step onto)
--   ThreeAfter        s after "Got the other end!" he says "On three... lift!"
--   DoorWarn / VanSay  carrying with you: the piece this near a doorway: "Watch the doorframe!"; this near the van's
--                      back: "That's going in the van." (its back shut: he opens it for the two of you, OpenBack)
--   HelpReach / PickReach   studs from your piece's far end he takes it / from a piece's edge he picks it up; LoadReach:
--                      from the van's back he loads; DoorReach: from a door he goes through it
--   OpenBack / OpenNear / OpenFar   may he open the van's back himself (else he asks); somebody of the crew coming with
--                      a piece within OpenNear studs of the shut back while he is within OpenFar of it: he opens it
--   FleeRange / SafeRange / FleeStep   a zombie this close: he runs FleeStep studs away until none is within SafeRange
--                      (never while he holds the other end of your piece)
--   WaitShut           s he waits with a piece at the van's shut back (when he may not open it) before he sets it down
--   Far                studs on foot to his goal from which he may be put there at once (a fade in: Walk.Seen, never in
--                      a player's sight; your call's walk and the ride's never)
--   9.3 (the owner, 8.9.5: "Danny still annoys me. He takes it completely like a robot. For example, he runs for 2
--   seconds and then on the spot he somehow teleports around"; tests/movehelper_stuck_runtime_test.luau sweeps his body
--   along his ways in the six real houses, the parts as built: his walk turned to the next corner a stud before it, his
--   2-stud body 0.35 studs off a wall's end at the closest, then pressed against it, a stuck spell, and 4 s later the
--   nudge put him on: the teleport on the spot; server/MoveHelper.luau's go, shared/HouseRoute.luau ahead, MoveHelper-
--   Brain progress / unstuck / ease):
--   Walk               how he walks a way (inside a house its grid's, outside PathfindingService's): aimed at a point
--                      Ahead studs (his walk × Lead s when that is more, AheadMost at most) along his way, the farthest
--                      whose straight line from him keeps Clear studs off every wall, fixture and piece of the house
--                      (exactly: his root's half diagonal and a margin; never nearer to one than he is) or, outside,
--                      cuts the way's corners Cut studs at most; ordered again every Reorder s, or once he is within Near
--                      studs of the point (never a stop on the way). Over the last Ease studs to his goal he slows to
--                      EaseMin × his walk; standing still Settle s within Arrive studs of it past his `near` counts as
--                      there (the humanoid stops a hair short). DoorIn: studs into a doorway he walks on while he fades
--                      out (Config.Moving.Doors FadeOut + Margin, then he is put on its other side and fades in FadeIn s,
--                      walking on: the players' walk-in doors). Seen: studs from a player within which no teleport may
--                      be seen (the Far rule: he walks instead). Turn: s his turn on the spot takes (a short tween,
--                      never a snap)
--   Unstuck            no progress along his way (Progress studs nearer than its best) for Repath s: a new way from
--                      where he stands; then every Cycle s his walking ways out: a new way (to Back s into it), walked
--                      back BackStep studs off what blocks him (to Side s), a sidestep of SideStep studs onto open ground
--                      (the other side each time) at Pace × his walk; only Fade s without progress the last resort: he
--                      fades over onto his way Rescue studs on (never a pop)
--   Body               his body as the audit sweeps it and his way keeps off things (Roblox's classic R15: the root 2
--                      studs wide, Radius its half; Hip the HipHeight; Height his head's top; StepUp the highest rise a
--                      Humanoid walks onto without a jump, an assumption: with the Jumping state off a higher ledge in
--                      his way stops him); the built interior's collidable parts between StepUp and Height over the floor
--                      close his grid's cells as the plan's walls do (HouseRoute.solid)
--   Diag               Roblox Studio only (RunService:IsStudio): the Output's "[Danny] teleport <why> <studs> studs at
--                      <where>" for every time he is put somewhere (Every s apart at most for the same why) and "[Danny]
--                      stuck <s>s at <where> going to <where>, blocked by <the part's full name>" once a stuck spell lasts
--                      Stuck s (again every Every s while it lasts; the part a ray along his walk finds)
--   Aside              doorways he keeps clear of when he stands somewhere: within the door's half width + Margin
--                      along its wall and Depth (FrontDepth at the front door outside) through it, his place moves Step
--                      past its edge, Off at least from the wall
--   TruckFar           studs from the house: a van farther away is driving off (he waits at the house's door)
--   TalkGap / TalkRepeat   s at least between two lines / before the same line again
--   8.3 your call (the owner: "when you want to take a heavy thing you must wait until the helper comes";
--   shared/MoveHelperBrain.luau's inPlace, approach, callKept; server/MoveHelper.luau's call):
--   WaitForHelper      Danny hired for the move (his body up, his hands not on another piece): a two-person Lift calls him
--                      ("Danny, give me a hand!"), you wait at your end while he walks to its other end, and its lift
--                      check opens once he is there (false: today's rules, you drag it alone and he comes to it)
--   CallCheck          8.6 (the owner: "he does come to me and waits, but it doesn't look good"): false, once he is there
--                      it goes up at once on his "On three... lift!" (balanced: he steadies it), no lift check after the
--                      wait; true: 8.3's lift check opens then (its hit lifts it)
--   CallReady / CallClose / CallStuck   in place for your call: within CallReady studs of his place at its far end, or
--                      within CallClose and blocked CallStuck s (the hold walks him the rest: no snap)
--   CallGain / CallBlink   his walk to your call (or your dragged piece): no closer by CallGain studs for CallBlink s,
--                      the last resort, he fades over (a door's own walk-through is not a fade-over)
--   CallLeave / CallIdle   your call ends when you walk CallLeave studs past the Lift's reach, or he stood ready
--                      CallIdle s and you never lifted (Lift again, G or the STOP button end it too)
--   8.3 for hire (shared/MoveHelperBrain.luau's hirePrice, hireCheck, assignCheck, nextQueued, pickSeat, getOut;
--   server/MoveHelper.luau's hire, list and ride; client/MoveHelperCard.luau his card and the clicks on the pieces;
--   the rate limits Config.Robust.Limits.MoveHelper (HIRE, CLEAR QUEUE, STOP) and MoveHelperAssign (a piece clicked)):
--   Hire               the hire, for one move, paid by the crew player who hires him (PlayerData.spend, the analytics
--                      reason HelperHire): Base + PerPiece × the house's pieces (the bigger the house, the more he
--                      saves you), to Round dollars, Min … Max. The tuning: the sandbox starts you with $500 and a
--                      first haul on show earns about $40 – 50 a minute (8.3 economy), so the Old Farmstead's big
--                      house (36 – 43 pieces: $230 – 270) is a real choice on the first move and five or six minutes of
--                      the warehouse's income later; a smaller house (20 or so pieces: about $150) costs less, Max at
--                      most. Danny's training (Config.SandboxUpgrades danny) makes him faster, not cheaper. No
--                      refund: a hire lasts the move (CLEAR QUEUE stops him working; nothing more is charged)
--   Queue              the pieces on his list at most (a click on one more: "his list is full"); he carries them in
--                      the order they were clicked, the rest is yours
--   RideReach          studs from his spot at the van's passenger door (RideStand) where he starts getting in (your seat
--                      at its wheel: he walks there at the Sprint, RideBlink / RideFar his last resort; the seat taken
--                      by a crew mate: he follows the van on foot; 8.3 review: a seat somebody is getting into, its
--                      Reserved, is taken too)
--   8.5 getting in like a player (the owner: "when I got into the car, Danny got a bit stuck under the car and then
--   appeared in the car already"; server/MoveHelper.luau's ride, MoveHelperBrain.roundVan / rideBlink):
--   RideStand          studs out of the van's side his spot at a seat's door is (where he gets in and where he gets out):
--                      out of the RideMargin he walks by and out of PathRadius round the van's hull (the old spot, 1.5
--                      studs out, was inside it: no path came, he walked straight at it, into the van, whose parts his
--                      collision group passes through), on the ground, clear of the cars
--   RideMargin         studs he keeps off the van's footprint on his way to its door: the straight way when it keeps this
--                      off, else round the footprint's corners this far out (the shorter way round)
--   RideCorner         a corner of that way within this many studs: he walks on to the next point (no stop at it)
--   RideHug            8.5.1 (the owner: "Danny STILL goes through it"; server/MoveHelper.luau's go, MoveHelperBrain.
--                      crossesVan / outOfVan): studs round the move's van's footprint his body keeps off on EVERY way
--                      of his outside (his body's half width and a hair): a way across it (a path that knows nothing of
--                      the van, the straight line from behind it to its front) goes round the van instead (RideMargin
--                      out; nearer the van than that, its goal's own distance), his root inside the van itself (parked
--                      over him; a load into the walk-in bay left him on the ground under its floor) is put beside its
--                      nearer side at once, faded in (never a walk through its shell); waiting by it while it drives at
--                      him he steps out of its way (its side, RideMargin out)
--   RideBlink / RideFar   the last resort, a fade into the seat: no closer by CallGain studs for RideBlink s, or RideFar
--                      studs or more to go on foot (the van driven off without him: more than from deep in the biggest
--                      house to the van at its curb, so by the house or the warehouse he always walks). At his spot he
--                      gets in as a player does (Config.Cargo: a step to the handle facing the van, its door swung open
--                      for everybody, the slide in through it over BoardSeconds, seated, the door shut) and gets out
--                      the same way back (AlightSeconds); a van faster than BoardMaxSpeed calls the move in off (he
--                      stands at his spot and goes after it on foot), as does the seat taken, a zombie, your getting out
--   SeatYield / SeatAside   8.3 review: a crew mate's Ride along at the door of the seat he sits in: he gets out for
--                      them (Vehicles.yieldSeat), SeatAside studs past where he gets out otherwise (out of their way),
--                      and takes no seat for SeatYield s (their boarding reserves it meanwhile)
--   CardReach / ClickReach / TapSlop   the client's: his card closes when you are CardReach studs from him (8.3 review:
--                      at least ClickReach, or a click on him from afar opens a card that shuts at once), or CardSlack
--                      studs farther than you were as it opened (the status line opens it from anywhere); a click or
--                      tap reaches him (or a piece: the server checks ClickReach + 10 studs) from ClickReach studs,
--                      TapSlop studs beside his body counts
--   8.5 Danny's clipboard, orders mode (the owner: "I'll hold a paper in my hand, like a notepad … a kind of ordering
--   mode and I click on what he should carry"; shared/ClipboardRules.luau, server/Clipboard.luau, client/DannyOrders.luau;
--   the rate limit Config.Robust.Limits.Clipboard): only with it out does a click, a tap or R1 give him a piece
--   Clipboard.Key      the computer's key that takes it out and puts it away (Q: free in the sandbox; the gamepad's R1
--                      and B are shared/SandboxPad.luau's "clipboard" and "stow")
--   Clipboard.Look     s between two looks at the piece you point at (its outline and its words)
--   Clipboard.Flash    s a tapped piece stays outlined (a touch screen has no pointer)
--   Clipboard.Button / ButtonMin   the touch 📋 button's side at the HUD's scale 1 / at least (px; Ui.MinTouch or more)
--   Clipboard.Text     the bottom line's text size at scale 1 (Pad: px round its words, Tall: its height)
--   Clipboard.Give / Back / No   the outline's colours: it can be given (green), on his list (orange: take it back),
--                      not now (red, with the reason)
--   9.0 (the owner: "When I hold the clipboard (Q), the E shouldn't show 'pick up'; E should mark the piece for Danny"):
--   with it out your move's pieces' own Pick up / Lift prompts hide on your screen and client/DannyOrders.luau's own
--   "Give to Danny" / "Take back" prompts stand on the pieces near you that he can take (a door's and the van's keep E)
--   Clipboard.GiveKey  the keyboard's key of those prompts (E: the pieces' own; a gamepad's R1 stays SandboxPad's
--                      "dannygive", client/MoveHelperCard.luau's prompt on the nearest piece)
--   Clipboard.PromptNear / Prompts   studs from you a piece may get one / the most at once (made once, moved round)
--   8.6 (the owner: "Somewhere I'd like to see an indicator of what Danny is doing right now, and to be able to tell
--   him, for example, put it down on the ground, or get out of the car"; client/DannyBubble.luau, MoveHelperBrain.bubble
--   / orders, server/MoveHelper.luau's orders; the rate limit Config.Robust.Limits.MoveHelperOrder):
--   Bubble             what he does over his head, for his move's crew (the server's words: the player attribute
--                      MoveHelperBubble), stacked over his name tag (or his speech, while he talks): Near / Far studs
--                      from the camera it fades out between (Far its MaxDistance); AlwaysOnTop only within Top studs
--                      (nearer, the van or a piece never hides it; farther, the walls of other houses do); Tick s between
--                      two looks; Text its words' size, Tall its height, Pad px round its words, Gap px over the name
--                      tag, Wide px at most (its words cut with "…")
--   (the orders need no numbers of their own: GET OUT waits for the van at Config.Cargo.BoardMaxSpeed or slower, the
--   speed his own getting in is called off over; after it he stays out while the owner stays at the wheel)
--   9.0 (the owner, 8.9: "Danny can't walk around things logically. He goes to take things through the wall … He must
--   not take things through walls, and neither may the player. And he must come to the thing nicely and take it into
--   his hands properly, with an animation"; shared/HouseRoute.luau, server/MoveHelper.luau's way inside and his
--   pick-up, server/Moving.luau's sight check):
--   Route              his way inside a house, on the plan's grid (shared/HouseRoute.luau; PathfindingService only
--                      outside): Step studs a cell; Radius studs his body keeps off every wall, solid fixture and piece
--                      standing in the house (a cell he fits in is open: the doorways' 6 studs take him); Stand studs
--                      from a piece's footprint at most where he stands to take it (arm's length, its near side, his
--                      line to its middle through no wall; 9.3 1.8, was 2: his hands on it as he bends, not gliding
--                      from afar; StandFar where no such spot is; none: "can't get to it", refused at the assignment);
--                      Snap studs he looks for the nearest open cell from a spot off them (a start, a goal, a stuck
--                      spell's sidestep: onto it, never into a wall); Again s at least between two ways worked out for
--                      the same goal
--   Pick               his pick-up: within Arm studs of the piece's footprint (Stand and the walk's give), his chest's
--                      line to its middle through no wall (a ray at the interior's walls) he turns to it (Turn s), bends
--                      and reaches with both arms (Bend s: shared/BodyMotion.luau's "lift", client/ArmPose.luau's hands
--                      on the piece) and the piece comes up into his hands over Lift s (eased, never snapped), him
--                      standing up into his carry; putting one down the same the other way ("setdown"). Tries: takes
--                      that found it out of reach or behind a wall before he gives the piece up ("can't get to it")
--   MarkFar            studs the 🧑‍🔧 markers over his list's pieces are drawn from (AlwaysOnTop off: never through a
--                      wall, seen in the same room and through an open doorway)
Config.MoveHelper = {
	Solo = true,
	Duo = false,
	Name = "Danny",
	Title = "ZDC Moving",
	Health = 100,
	Respawn = 15,
	Speed = 0.7,
	Sprint = 1.5,
	KeepUp = 1.2,
	Flee = 1,
	Tick = 0.1,
	Think = 0.25,
	Repath = 1,
	HelpFar = 140,
	HelpRetry = 8,
	BlinkFar = 40,
	HelpBlink = 1.6,
	Standoff = 0.6,
	HoldStep = 2.5,
	HoldResponse = 200,
	PairTurn = 60, -- 8.1
	PairBand = 20,
	PairTurnWalk = 0.5,
	PairTurnFull = 45,
	HoldMargin = 1.25,
	HoldExtra = 6,
	HoldTurn = 3,
	HoldBehind = 3,
	HoldStuck = 3,
	HoldEase = 0.5,
	HoldClimb = 8, -- 8.3
	HoldLegs = { From = 0.8, To = 0.4, Band = 0.3 },
	HoldCap = 40, -- 8.3 keeping up
	HoldPace = { Fall = 0.5, Jump = 12 },
	HoldLead = { Base = 0.06, Ping = 1, Most = 0.25, Far = 3, Smooth = 0.1, Rate = 5, In = 0, Back = 0.05 }, -- (8.6 Rate; 9.0 In, Back)
	PairStart = 0.6, -- 9.0
	PairKeep = { Wait = 0.1, From = 0.25, Stop = 0.8 }, -- 9.0
	HoldWall = { Clear = 0.8, Block = 0.4 }, -- 9.0
	PairLead = { On = true, Turn = 120, TurnWalk = 0.75, Glide = 6, Settle = 0.5, Loose = 1.5, Rigid = 400, Spin = 30, Jump = 30, Soft = 0.6, Sane = 8,
		Grace = 1.5, Look = 0.5 }, -- 9.2
	Edge = { Width = 2.4, Height = 0.3, Depth = 0.6, Reach = 1.2 }, -- 8.6 (9.0 Reach)
	RunHint = "Too heavy to run with",
	PathRadius = 1.5,
	PathHeight = 5,
	PathSpacing = 4,
	PathAgain = 3,
	PathDrift = 6,
	ThreeAfter = 1.2,
	DoorWarn = 4,
	VanSay = 12,
	HelpReach = 2.5,
	PickReach = 3,
	LoadReach = 5,
	DoorReach = 3.5,
	OpenBack = true,
	OpenNear = 30,
	OpenFar = 30,
	FleeRange = 14,
	SafeRange = 24,
	FleeStep = 18,
	WaitShut = 8,
	Far = 120,
	-- 9.3 his walk (the owner: "he runs for 2 seconds and then on the spot he somehow teleports around")
	Walk = { Ahead = 2.5, Lead = 0.35, AheadMost = 5, Clear = 1.15, Cut = 0.5, Reorder = 0.2, Near = 1.5, Ease = 3, EaseMin = 0.35, Arrive = 0.6,
		Settle = 0.3, DoorIn = 0.5, Seen = 150, Turn = 0.25 },
	Unstuck = { Progress = 0.5, Repath = 1, Cycle = 2.4, Back = 0.6, Side = 1.4, BackStep = 1.5, SideStep = 2, Pace = 0.6, Fade = 10, Rescue = 4 },
	Body = { Radius = 1, Hip = 2, Height = 5.2, StepUp = 1 },
	Diag = { Every = 2, Stuck = 1.5 },
	Aside = { Margin = 1, Depth = 2.5, FrontDepth = 6, Step = 2.4, Off = 1.2 },
	TruckFar = 150,
	TalkGap = 3,
	TalkRepeat = 12,
	-- 8.3 your call
	WaitForHelper = true,
	CallCheck = false, -- 8.6
	CallReady = 3,
	CallClose = 6,
	CallStuck = 1.5,
	CallGain = 1,
	CallBlink = 15,
	CallLeave = 4,
	CallIdle = 25,
	-- 8.3 for hire
	Hire = { Base = 50, PerPiece = 5, Round = 10, Min = 100, Max = 400 },
	Queue = 6,
	RideReach = 1.2,
	RideStand = 2.8, -- 8.5 getting in like a player
	RideMargin = 2.4,
	RideCorner = 1.2,
	RideHug = 1.6, -- 8.5.1
	RideBlink = 20,
	RideFar = 200,
	SeatYield = 2, -- 8.3 review
	SeatAside = 2.5,
	CardReach = 90,
	CardSlack = 20,
	ClickReach = 90,
	TapSlop = 2.5,
	-- 8.5 Danny's clipboard (orders mode)
	Clipboard = {
		Key = "Q",
		Look = 0.1,
		Flash = 1.5,
		Button = 64,
		ButtonMin = 48,
		Text = 16,
		Pad = 14,
		Tall = 34,
		Give = { 96, 214, 112 } :: { number },
		Back = { 240, 132, 44 } :: { number },
		No = { 226, 72, 62 } :: { number },
		GiveKey = "E", -- 9.0
		PromptNear = 14,
		Prompts = 4,
	},
	-- 8.6 the bubble over his head
	Bubble = { Near = 35, Far = 75, Top = 20, Tick = 0.15, Text = 13, Tall = 26, Pad = 9, Gap = 4, Wide = 340 },
	-- 9.0 his way inside a house, his pick-up, his list's markers
	Route = { Step = 0.5, Radius = 1.25, Stand = 1.8, StandFar = 2.4, Snap = 3, Again = 0.5 }, -- (9.3 Stand 1.8, was 2: StandFar)
	Pick = { Arm = 2.8, Turn = 0.3, Bend = 0.45, Lift = 0.4, Tries = 3 },
	MarkFar = 60,
}

-- 7.0, the moving rework's world (design/rework/NAVRH.md: the city is evacuated, the army builds the Wall round the
-- safe zone, ZDC is ZDC Moving & Evacuation now): server/MoveSites.luau builds shared/MoveSiteLooks.luau's set pieces
-- (tests/movesites_test.luau, tools/move-sites/check.py check them; tools/move-sites/render.py previews them): the
-- Wall's checkpoint round the drop-off (Config.Moving.DropOff), the Moving contracts kiosk (Config.Moving.Board), each
-- contract's house dressed for moving day, the depot's banner and a few evacuation spots in the city.
--   Bay        the drop-off bay painted on the yard (width along X, depth along Z, round Config.Moving.DropOff): the truck
--              drives in from Bone St, nothing stands in it
--   Clear      studs over the walk the checkpoint's gantry sign hangs (the trucks pass under it)
--   Truck      the army truck's middle (x, z from the drop-off's middle), parked west of the gate, its nose to the Wall
--              (off the bay, the scooters' way out and the people's walk line round the block)
--   Banner     the ZDC MOVING & EVACUATION banner under the depot's front canopy: its middle (X, Z studs from the depot's
--              middle, Y over the walk), Width × Height, Hang (its ties up to the canopy)
--   Spots      the evacuation spots (a poster board, abandoned moving boxes) on a block's kerb: the block (district, i,
--              j), its side (n | e | s | w), studs along it from its middle (StreetProps' way: n, s along X, e, w along Z
--              with the side's turn), Depth in from the curb; clear of the street props (tests/movesites_test.luau)
--   Budget     parts in all of it at most; Lights the PointLights (the kiosk's lamp, the two floodlights)
--   TextRange  studs the small text is drawn at least (SurfaceGui.MaxDistance: a big sign SignPerStud × its height,
--              Config.Performance)
Config.MoveSites = {
	Bay = { 22, 18 } :: { number },
	Clear = 13.5,
	Truck = { -17.5, -4.9 } :: { number },
	Banner = { X = 0, Y = 16.1, Z = -7.3, Width = 34, Height = 3.2, Hang = 1.6 },
	Spots = {
		{ district = "downtown", i = 2, j = -1, side = "s", along = 28 }, -- Bone St, across the avenue from the checkpoint
		{ district = "downtown", i = 2, j = 2, side = "w", along = -24 }, -- the avenue south, just out of the safe zone
		{ district = "suburbs", i = 2, j = 0, side = "n", along = 2 }, -- Willow Ln, next to Marge's
	} :: { { district: string, i: number, j: number, side: string, along: number } },
	Depth = 1.8,
	Budget = 400,
	Lights = 4,
	TextRange = 90,
}

-- 7.0, the greeters (the owner: "there will be NPCs who sort of welcome you"): server/MoveGreeters.luau's people, their
-- words shared/MoveStory.luau's greeter section (tests/movegreeters_runtime_test.luau). Studs and seconds.
--   Porch      where a move's client stands from its start: { x, z } in the house door's frame (shared/MoveSiteLooks.luau
--              doorPlace: +X right, -Z out to the street): beside the door, off the path (its ±2.4 studs), clear of
--              the packed boxes and the yard sign
--   Hello      the first crew member this near her: she turns to them, waves and says her hello lines LineGap s apart,
--              then holds a hand out to the open door (once a move)
--   Star       a ★ thing carried this near her: her "Careful with that!" (each ★ thing once, StarAgain s at least apart)
--   Leave      the truck stood within Near of the house's door, then drove past Far with a load: her thanks (LeaveAgain s
--              at least apart)
--   Gap        s at least between two lines of hers (a reaction waits behind her hello)
--   Soldier    the soldier at the Wall's checkpoint, always there: Name, Title, At { x, z } from the drop-off's middle
--              (Config.Moving.DropOff: north of the booth's sandbags, off the bay and the people's walk line), facing the
--              bay; a move delivered with its truck within Greet of the drop-off: he turns to it, waves and welcomes it
--   Kiosk      Marge at the Moving contracts kiosk (server/Tutorial.luau's dispatcher at the depot: never a second Marge):
--              a player on foot and on no move who comes within Near of its corkboard: her line, her bubble seen from
--              Hear studs (she stands by the job board) and the player's notice; once per player every Again s
--   Tick       s between two steps of the greeters' loop (the kiosk, the soldier's body); Respawn: s between two looks
--              for a body that went (the soldier's, the dispatcher's)
Config.MoveGreeters = {
	Porch = { -4.4, -3.0 } :: { number },
	Hello = 25,
	LineGap = 2.6,
	Star = 30,
	StarAgain = 20,
	Leave = { Near = 60, Far = 110 },
	LeaveAgain = 90,
	Gap = 2,
	Soldier = { Name = "Private Reyes", Title = "The Wall · Checkpoint 01", At = { 13.3, -3.4 } :: { number }, Greet = 32 },
	Kiosk = { Near = 14, Hear = 120, Again = 180 },
	Tick = 0.4,
	Respawn = 5,
}

-- 6.19, prices as milestones (the owner: "make everything more expensive so they're real milestones"; the 6.14 design:
-- jobs are the grind, you save up for something, then progress in the missions). The tables above keep the old base
-- prices; this one pass, run once here, multiplies every `price` (and the upgrade tracks' baseCost) by its kind's
-- knob and rounds it to a nice step (Round: { below, step }, the first that fits): $5 under 100, $50 under 1,000, $100
-- under 10,000, $500 above. Every reader (the shops, the server's checks, Readiness, Career, the dealer's signs) reads
-- these tables, and no save stores a price: owned things stay owned, nothing is paid back. Free stays free (0 × n = 0),
-- reward-only things stay unsold. Kept as they were (×1): the real estate and the company (the endgame already),
-- the old backpacks' payback (Config.RetiredKit), fuel, the repair shop's fee and the board's reroll fee.
--   Vehicles  the dealer's cars and Earl's Old Van      Bikes    the bikes and the E-Scooter
--             (7.x: no car is sold any more; the pass still prices Config.AmbientCars: what a save that owned one gets
--             back, Economy.carRefund)
--   Stages    Wrench Garage's stages                    Upgrades Wrench Garage's tracks (baseCost)
--   Guns      Lead & Co.'s guns                         CarGuns  the car guns
--   Gear      the car and bike gear                     Kit      the vests, the bat (6.23: a bag's price is set
--                                                                for one game after it: Config.BagShop.PerGame)
--   Paints    Wrench Garage's paints                    Style    the looks (Config.Cosmetics)
--   Items     the consumables (medkits, repair kits, nitro, mines, molotovs, the energy drink, the jerry can)
--   Rewards   the money of a level-up (Config.Levels.Rewards), raised in step so a level still feels like a boost
Config.Prices = {
	Vehicles = 3,
	Bikes = 4,
	Stages = 2.5,
	Upgrades = 2.5,
	Guns = 2,
	CarGuns = 2,
	Gear = 2.5,
	Kit = 2.5,
	Paints = 2,
	Style = 2,
	Items = 1.5,
	Rewards = 1.5,
	Round = { { 100, 5 }, { 1000, 50 }, { 10000, 100 }, { math.huge, 500 } } :: { { number } },
}

-- 6.19: a base price × a knob, rounded to Config.Prices.Round's step (0 stays 0).
function Config.priced(base: number, knob: number): number
	local raw = base * knob
	for _, r in Config.Prices.Round do
		if raw < r[1] then
			return math.floor(raw / r[2] + 0.5) * r[2]
		end
	end
	return raw
end

do -- 6.19: the one pass over the tables (see Config.Prices)
	local P, priced = Config.Prices, Config.priced
	for _, list in { Config.Cars, Config.AmbientCars } do
		for _, def in list do
			def.price = priced(def.price, if def.bike then P.Bikes else P.Vehicles)
			local stages = def.stages
			if stages then
				for _, stage in stages do
					stage.price = priced(stage.price, P.Stages)
				end
			end
		end
	end
	for _, def in Config.AmbientCars do
		def.ambient = true -- 7.x: a body for the world, never a player's car (Economy.isPlayerCar)
	end
	for _, def in Config.Upgrades do
		def.baseCost = priced(def.baseCost, P.Upgrades)
	end
	local lists: { [string]: { { price: number } } } = {
		Guns = Config.Weapons :: any,
		CarGuns = Config.CarGuns :: any,
		Gear = Config.Gear :: any,
		Kit = Config.Kit :: any,
		Paints = Config.Paints :: any,
		Style = Config.Cosmetics.Items :: any,
		Items = Config.Items :: any,
	}
	for knob, list in lists do
		for _, def in list do
			def.price = priced(def.price, (P :: any)[knob])
		end
	end
	for _, reward in Config.Levels.Rewards do
		if reward.money then
			reward.money = priced(reward.money, P.Rewards)
		end
	end
	-- 6.23: a bag's price is for one game (Config.BagShop.PerGame); its price for good (after the Kit knob) is kept as
	-- an old save's refund (Config.BagShop.Refund)
	for _, def in Config.Kit do
		if def.extra then
			Config.BagShop.Refund[def.id] = def.price
			def.price = Config.BagShop.PerGame[def.id] or def.price
		end
	end
end

-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md): the owner's small test world (shared/SandboxMap.luau) in place of the
-- city: one house to empty, your walk-in Sprinter van, your ZDC warehouse where what you bring is put on show (it earns
-- while it stands there) or sold. On = false builds the old city as before (until it is deleted).
--   On          the sandbox world instead of the city (server/Main.server.luau, client/Main.client.luau)
--   Van         the car every player has in the sandbox (Config.Cars id; parked at their plot's vanSpot at PLAY; the
--               ZDC Van, Config.CompanyVan.Car, while this one is not in Config.Cars yet: server/SandboxBoot.luau)
--   MaxPlayers  the plots (SandboxMap.Plots): one player each (set the place's max players to this)
--   Store       the sandbox's own DataStore (server/PlayerData.luau): the city's saves (DataStoreName) are never read
--               or written while On
--   StartMoney  a new sandbox save's money (in Studio without saves too)
Config.Sandbox = {
	On = true,
	Van = "sprinter",
	MaxPlayers = 4,
	Store = Config.DataStoreName .. "_Sandbox",
	StartMoney = 500,
}

-- 8.0 SANDBOX, the collection (design/sandbox/KONTRAKT.md "Collection"): everything a move brings home is yours. It
-- waits in your warehouse's stock, stands on show on a display stand (it earns money every minute you play) or is sold
-- (any time). shared/CollectionRules.luau has the rules (tests/collection_test.luau), server/Collection.luau keeps
-- profile.collection, pays and answers the "Collection" remote (tests/collection_runtime_test.luau). A piece's worth
-- is its furniture's value (shared/FurnitureLooks.luau Items: the moves' `value`) × its condition (0 … 1).
--   Tiers      the rarities by id: name, colour (RGB), rank (1 common … 5 legendary), min (a piece without a `rarity`
--              of its own is the rarest tier whose min its value reaches), income (× the worth a minute on show) and
--              sell (× the worth when sold: about a quarter of an hour of showing it, 13 – 17 minutes)
--   Order      the tiers' ids, common first
--   BrokenAt   a condition at or under it is broken (the moves' own, Config.Moving.Damage.BrokenAt): it earns nothing
--              on show and sells for scrap, Scrap × its value (at least $1)
--   MaxStock   the pieces one player owns at most (Collection.add refuses more and says why); 8.4 review: also the most
--              uids a SELL… request may list (server/Collection.luau: a longer list is refused)
--   Stands     the display stands when Config.Warehouse.Stands is missing (CollectionRules.standsFor)
--   Tick       s between two payouts of the stands' income (exact: the fractions carry over to the next one)
--   IdleAfter  8.3 economy (AFK): s without activity after which the stands pay only IdleShare (0 … 1) of their income
--              (server/Collection.luau; the HUD's income line says "+$X/min · idle"). Activity is what the server sees:
--              the character's root moved IdleMove studs or more between two payouts (walking, a van driven), or a call
--              of one of IdleRemotes (not a bare "state" ask: the clients send those by themselves)
-- The tuning (8.3 economy, the owner: "much longer: you must save up, or have more luck to find a rare piece"), the
-- hauls of HouseLayout's 200 first seeds at 90 % condition: the sandbox's big house (kind "big", 36 – 43 pieces worth
-- $10,200 – 21,300, median $13,400) on 12 stands earns $39 – 150 a minute (median $53), all of it sold pays $920 –
-- 2,640 (median $1,260); a house ("house": 19 – 26 pieces worth $5,700 – 14,000) $28 – 125 a minute (median $37), sold
-- $510 – 1,900. A piece sells for 13 – 17 minutes of showing it (tests/collection_test.luau checks a sample haul).
-- Ordinary furniture is common, uncommon or rare (the piano, $1,200, is rare); epic and legendary are the collectibles'
-- own `rarity`. A legendary ($5,500 – 7,000) earns 1.5 % of its value a minute: $80 – 105, a whole haul's best 12.
export type CollectionTier = { name: string, rank: number, color: { number }, min: number, income: number, sell: number }
Config.Collection = {
	Tiers = {
		common = { name = "Common", rank = 1, color = { 178, 182, 188 }, min = 0, income = 0.005, sell = 0.08 },
		uncommon = { name = "Uncommon", rank = 2, color = { 92, 196, 104 }, min = 100, income = 0.006, sell = 0.1 },
		rare = { name = "Rare", rank = 3, color = { 70, 144, 240 }, min = 800, income = 0.008, sell = 0.12 },
		epic = { name = "Epic", rank = 4, color = { 178, 96, 236 }, min = 1500, income = 0.01, sell = 0.15 },
		legendary = { name = "Legendary", rank = 5, color = { 255, 178, 36 }, min = 3000, income = 0.015, sell = 0.2 },
	} :: { [string]: CollectionTier },
	Order = { "common", "uncommon", "rare", "epic", "legendary" } :: { string },
	BrokenAt = Config.Moving.Damage.BrokenAt,
	Scrap = 0.015, -- (8.3 economy: under a whole piece's worst price, common's 8 % × 0.21)
	MaxStock = 300,
	Stands = 12,
	Tick = 10,
	IdleAfter = 600, -- 8.3 economy: the stands of a player idle this long earn only IdleShare of their income
	IdleShare = 0.25,
	IdleMove = 4,
	IdleRemotes = { "Collection", "Moving", "Upgrades", "SandboxTasks", "Visitors", "VanPaint", "PlayerTrade" } :: { string }, -- (8.7: PlayerTrade)
}

-- 8.0 SANDBOX, the guide (client/SandboxGuide.luau, its steps shared/SandboxSteps.luau): a thin hint line at the top in
-- the middle and a 3D guide (a soft glowing path on the ground along the roads, a floating chevron over the target with
-- its distance) to what to do next. Each step goes quiet once done (per session); the arrow to the house and home
-- stays while you drive. Hold G (or press the hint's ✕) to hide it; hold G again (a touch screen: tap the 💡 chip) to bring
-- it back.
--   Every         s between two looks: the step, the path, the distance (nothing is done frame by frame)
--   Fade          s the hint line takes to fade in or out
--   HideHold      s G is held to hide the guide or bring it back
--   OffNote       s the "Guide off" line stays before it fades
--   InfoSeconds   s a step that only says something (the pieces earn money) shows before it counts as done
--   HouseMargin   studs round the contract's house's lot (SandboxMap.Houses' lot) that count as "at the house"
--   Direct        studs: a target closer than this gets a straight path, a farther one goes along the roads
--   Near          studs: closer than this the path hides (the chevron stays)
--   ChevronHeight studs over the target the chevron floats
--   PathLift      studs over the ground the path glows
--   PathWidth     studs: the path's width
--   PathAlpha     the path's transparency (0 solid … 1 gone)
--   Color         the guide's colour (the path, the chevron, the hint's edge): a warm ZDC orange
--   HintWidth     px at scale 1: the widest the hint line gets (its words wrap beyond)
--   TextSize      px at scale 1: the hint's words
--   TouchScale    the hint's smallest scale on a touch screen (readable on a phone held sideways)
--   SideClear     px at scale 1 kept free at the top's left and right (the money, Roblox's own buttons)
--   Top           px from the top when nothing else holds the top's middle; Gap: px under what does
--   8.3, the soft steps (shared/SandboxSteps.luau choose: the UPGRADES desk, the market's hot piece, the PAINT shop; only
--   when nothing more urgent is pending; the ✕ on one dismisses that step alone, for the session, the guide stays on):
--   SoftSeconds   s a soft step shows before it counts as done (said long enough)
--   SoftGap       s after a soft step ended (done, dismissed, covered) before the next one may show
--   PaintMoney    $ from which the PAINT shop's step may show (else once a warehouse level is bought)
--   8.4, Danny for hire's steps (hire him, give him a piece, a heavy piece: SandboxSteps.Danny; said once as a soft step):
--   HeavyNear     studs: a two-person piece of your move this near you (its Lift shown) says "press Lift and wait for
--                 Danny" (looked for at most once a second, only while that step may still show)
--   8.9, trading between players' step ("🏷 Sell to players: set a price on a piece on show", the last soft step):
--   SellShown     your pieces on show from which it may show (none with a FOR SALE sign yet: one set, it is done)
--   SellPlayers   the players on the server (you too) from which it may show (alone, nobody would buy)
Config.SandboxGuide = {
	Every = 0.2,
	Fade = 0.5,
	HideHold = 0.8,
	OffNote = 3,
	InfoSeconds = 12,
	HouseMargin = 40,
	Direct = 70,
	Near = 8,
	ChevronHeight = 7,
	PathLift = 0.45,
	PathWidth = 1.3,
	PathAlpha = 0.45,
	Color = { 255, 168, 60 },
	HintWidth = 460,
	TextSize = 15,
	TouchScale = 0.8,
	SideClear = 200,
	Top = 8,
	Gap = 6,
	SoftSeconds = 40, -- 8.3: the soft steps
	SoftGap = 15,
	PaintMoney = 2000,
	HeavyNear = 12, -- 8.4
	SellShown = 4, -- 8.9: the sell step
	SellPlayers = 2,
}

-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md, "warehouse"): the ZDC warehouse on every plot (SandboxMap.Plots' warehouse:
-- shared/WarehouseLayout.luau lays it out, server/Warehouse.luau builds it) and its display stands, where the pieces of
-- your collection stand on show (and earn every minute you play).
--   Stands          how many display stands a warehouse starts with (Collection.display's stand: 1 … Stands; 1 nearest
--                   the door, west to east); 8.1: the upgrades' More stands open more (Config.SandboxUpgrades), up to
--   MaxStands       the stands the hall holds (8.1): Stands big ones in the grid, the rest smaller (SmallStand) in the
--                   middle aisle and beside the receiving zone, each shown as a painted spot until it is bought
--   Columns         the stands across the hall (even: half each side of the middle aisle); the rows go back from the door
--   StandSize       a stand's podium (square, studs): every piece fits on it unturned (the biggest, the hay wagon, 6.4 × 9.6)
--   SmallStand      8.1: an upgrade stand's podium { across, deep } (studs): every piece but the beds, the hay wagon and
--                   the wheelbarrow fits on it unturned (Collection.display says which stand to use)
--   StandHeight     the podium's top over the floor
--   Aisle           the least walk between two stands and between the stands and the side walls (8.1: 5, room for the
--                   upgrade stands; the pieces come home with the van's unloading, nobody carries them in)
--   MiddleAisle     the walk from the roller door to the back wall, between the two halves (8.1: the upgrade stands'
--                   column down its middle, an Aisle each side of it)
--   Receiving       the receiving zone's depth inside the roller door (its width the door's, SandboxMap.DoorWidth)
--   DoorHeight      the roller door's opening (kept open)
--   Ridge           the gable roof's ridge (north-south) over the walls' top
--   Bay             the UNLOAD HERE box painted in front of the roller door: { width, length }, centred on the plot's
--                   vanSpot (the parked Sprinter's middle: 4 studs to spare at each end, its words at the door's end)
--   PromptDistance  the stands' prompts' reach (8.1: the UPGRADES desk's too); SellHold the Sell prompt's hold (s)
--   Rebuild         s: the changes to one collection this close together rebuild its shown pieces once
--   MaxParts        one warehouse's part budget (the building, its stands, the UPGRADES desk and its bay; not the
--                   pieces on show)
--   (8.3: the hall's lights are Config.SandboxLight.Warehouse's: each level's lamps there)
--   Rarity          a rarity's colour on a stand's tag (an unknown rarity: common's)
--   ArtLevel        8.2: the level (1 … 5) of the owner's Blender warehouse (design/blender-warehouse) the warehouses wear
--                   once ZDCWarehouseArt is imported (server/WarehouseMesh.luau; 4: the size the warehouse is). 8.3: only
--                   the fallback of a warehouse built without a level (each plot is its owner's level now)
--   Levels          8.3 (design/warehouse-levels/KONTRAKT.md): the warehouse's five levels, the owner's Blender ones
--                   (design/blender-warehouse, ZDCWarehouseArt: the same sizes, doors and roofs): name (in the game),
--                   size { W across, H the front wall, D deep }, door { width, height }, roof ("shed": its back wall
--                   rise lower; "gable"; "barrel": the game's own parts a gable of rise under it), rise (the roof over
--                   H; a shed's top is H) and stands (its big stands: StandSize podiums). Level 4 is the warehouse of
--                   8.0 – 8.2 (Stands, Ridge, DoorHeight above, SandboxMap's plot.warehouse). The UPGRADES desk sells
--                   the levels (Config.SandboxUpgrades.List.warehouse); the More stands' small stands from MoreFrom on
--   MoreFrom        8.3: the first level with the More stands upgrade's small stands (below it the card is locked)
--   FreeLevel       8.3: the level a plot nobody has shows (FOR RENT)
export type WarehouseLevelDef = { name: string, size: { number }, door: { number }, roof: string, rise: number, stands: number }
Config.Warehouse = {
	Stands = 12,
	MaxStands = 20,
	Columns = 4,
	StandSize = 10,
	SmallStand = { 8, 5 } :: { number },
	StandHeight = 1,
	Aisle = 5,
	MiddleAisle = 18,
	Receiving = 9,
	DoorHeight = 16,
	Ridge = 8,
	Bay = { 14, 30 } :: { number },
	PromptDistance = 8,
	SellHold = 1,
	Rebuild = 0.15,
	MaxParts = 400,
	ArtLevel = 4,
	Levels = {
		{ name = "Garage", size = { 26, 12, 22 }, door = { 14, 9.5 }, roof = "shed", rise = 2.5, stands = 2 },
		{ name = "Workshop", size = { 40, 15, 30 }, door = { 18, 12 }, roof = "gable", rise = 4.5, stands = 4 },
		{ name = "Storehouse", size = { 58, 19, 42 }, door = { 22, 14 }, roof = "gable", rise = 6, stands = 8 },
		{ name = "Big Warehouse", size = { 80, 24, 60 }, door = { 26, 16 }, roof = "gable", rise = 8, stands = 12 },
		{ name = "Logistics Center", size = { 104, 28, 84 }, door = { 26, 18 }, roof = "barrel", rise = 10, stands = 24 },
	} :: { WarehouseLevelDef },
	MoreFrom = 4,
	FreeLevel = 1,
	Rarity = {
		common = { 222, 224, 228 },
		uncommon = { 104, 214, 120 },
		rare = { 86, 164, 255 },
		epic = { 192, 120, 255 },
		legendary = { 255, 196, 64 },
	} :: { [string]: { number } },
}

-- 8.0 SANDBOX, the HUD and the warehouse picker (client/SandboxHud.luau, client/WarehouseUi.luau; the "Collection"
-- remote). Px at the HUD's scale 1 unless said.
--   MoneySize / IncomeSize   the money's text (money green, counting up) and the "+$X/min" line under it (green)
--   Chip / ChipText          the "📦 N in stock" chip under them (on a touch screen at least Ui.MinTouch screen px high)
--   TouchScale               the money block's smallest scale on a touch screen (it is never smaller than this)
--   StockKey                 the key that opens / closes the STOCK list (a computer)
--   StockPad                 8.3: the gamepad's button for it (an Enum.KeyCode name: the D-pad's ←; shared/SandboxPad.luau
--                            has the sandbox's D-pad map and why ↑ stays Roblox's)
--   Hints                    8.3, the first-time hints (shared/SandboxHints.luau, client/SandboxHintsUi.luau): a hint shows
--                            Delay s after what made it matter, at least Gap s after the hint before (one at a time), and
--                            waits while something covers the screen, looked at every Every s; the ⭐ FILL BEST hint
--                            once FillStock pieces that would earn wait in the stock beside a free stand. 8.9: the
--                            clipboard's and a visit's hints looked for every Look s (your clipboard out, where you
--                            stand: only until both are said); the FOR SALE sign's hint once PriceShown pieces of yours
--                            are on show
--   Toast / MaxToasts        the block's own toasts (only when client/Hud.luau's toasts are not there): seconds, how many
--   Picker                   the picker's card (Width × Height at most, Margin from the screen's edges), its tiles
--                            (Tile: the narrowest on a computer, TileTouch on a touch screen; Picture: the picture's
--                            height over the tile's width, PictureTouch on a touch screen), Gap between them, Button:
--                            a tile's buttons (a touch screen: Ui.MinTouch screen px at least)
--   MaxViews                 3D pictures (ViewportFrames) alive at once in the grid: only the tiles on screen get one,
--                            the others show the piece's emoji
--   MaxModels                the pieces' models kept built for the pictures (one a piece and variant), the oldest go
--   Models                   false: emoji only (no ViewportFrames at all)
--   Fallback                 only until shared/CollectionRules.luau answers (the server decides what is paid): Rarity
--                            the value from which a piece is uncommon, rare, epic, legendary; Sell the price's share of
--                            the piece's value at condition 0 and 1; IncomeShare the price's share it earns a minute
Config.SandboxHud = {
	MoneySize = 34,
	IncomeSize = 15,
	Chip = 32,
	ChipText = 14,
	TouchScale = 0.8,
	StockKey = "B",
	StockPad = "DPadLeft", -- 8.3: the gamepad's way to the STOCK list
	Hints = { Delay = 1.5, Gap = 6, Every = 0.5, FillStock = 5, Look = 1, PriceShown = 3 }, -- 8.3: the first-time hints (8.9: Look, PriceShown)
	Toast = 3,
	MaxToasts = 3,
	Picker = {
		Width = 900,
		Height = 620,
		Margin = 16,
		TouchMargin = 8,
		Tile = 160,
		TileTouch = 180,
		Picture = 0.6,
		PictureTouch = 0.42,
		Gap = 10,
		Button = 32,
	},
	MaxViews = 12,
	MaxModels = 24,
	Models = true,
	Fallback = { Rarity = { 100, 800, 1500, 3000 } :: { number }, Sell = { 0.5, 1 } :: { number }, IncomeShare = 0.008 },
}

-- 8.0 SANDBOX: the ZDC Sprinter (Config.Cars sprinter, Config.Sandbox.Van), a high-roof panel van you walk into. Its
-- measures in studs; the parts look (shared/SprinterLooks.luau, server/Vehicles.luau STYLES.sprinter), the Blender
-- model (design/blender-sprinter/, server/SprinterMesh.luau) and the moves' bed (Config.Moving.Beds.sprinter) use the
-- same. The van's frame: from the ground under its middle, -z its front, +x its right (the kerb side), +y up.
--   Width / Height / Length   the body (the mirrors stick out Mirror more on each side), ground to roof, bumper to
--                             bumper: x -4 … 4, y 0 … 10.4, z -11 … 11
--   Wheelbase                 between the axles, centred on the van's middle (z ±6.5: Vehicles builds every car's
--                             wheels round its middle); Track: the wheels' middles ±Track across
--   Clearance                 the chassis' bottom over the ground (Vehicles' style clearance); Wheel the radius
--   Cab                       the cab: the front Cab studs (z -11 … -4); its back wall (the bulkhead) Bay.Gap thick
--   Bay                       the cargo bay INSIDE: Width × Height × Length, its floor Floor over the ground (= Clearance
--                             + the 1.2 chassis: you stand on the chassis' top), from Gap behind the cab's back wall to
--                             the back doors at the van's back: x -3.3 … 3.3, y 2.4 … 10.0, z -3 … 11 (the closed doors'
--                             inner face at z 10.8). Moves' bed (from the chassis' middle, its floor at the chassis' top):
--                             Center { 0, 3.9 }, the room 6.6 × 7.6 × 13.8 less what the packing keeps off the walls
--   Doors                     the two back doors: they swing out Swing degrees round the body's back corners and lie
--                             flat against the sides (the walk-in way)
--   Slider                    the sliding door on the right: its opening from z Front, Width long, Height over the floor;
--                             it moves Out from the side and Back along it in Seconds; its prompt reaches Reach. It
--                             shuts itself when somebody takes the wheel
--   Step                      the fold-out step behind the back (out while the back is open): Top over the ground, Depth
--                             out, Width across; ground → Top → the floor: two rises of 1.2 a body walks up. SideStep: the
--                             same under the open sliding door (Depth out from the side)
--   Light                     the bay's ceiling light (on while the back or the side door is open)
Config.Sprinter = {
	Width = 8.0,
	Height = 10.4,
	Length = 22.0,
	Mirror = 0.8,
	Wheelbase = 13.0,
	Track = 3.45,
	Clearance = 1.2,
	Wheel = 1.2,
	Cab = 7.0,
	Bay = { Width = 6.6, Height = 7.6, Length = 14.0, Floor = 2.4, Gap = 1.0 },
	Doors = { Swing = 270 },
	Slider = { Front = -2.85, Width = 5.0, Height = 6.9, Out = 0.35, Back = 5.0, Seconds = 0.5, Reach = 8 },
	Step = { Top = 1.2, Depth = 1.4, Width = 4.6 },
	SideStep = { Top = 1.2, Depth = 1.2 },
	Light = { Range = 13, Brightness = 1.4, Color = { 255, 244, 222 } :: { number } },
}

-- 8.1 SANDBOX, the upgrades (the owner: "the money players earn needs something to buy"): bought at the UPGRADES desk
-- in your warehouse (server/Warehouse.luau builds it, client/UpgradeUi.luau is its window, server/Upgrades.luau decides
-- every purchase; shared/UpgradeRules.luau has the rules, tests/upgrades_test.luau and tests/upgrades_runtime_test.luau
-- check them). The levels are per player in the save (profile.sandboxUpgrades: Config.Upgrades and profile.upgrades are
-- the city's gun and car tracks). Each upgrade:
--   name, icon     its card's title and picture (an emoji)
--   max            its top level; prices: the price of each level (prices[n] buys level n)
--   step           what one level gives: warehouse (8.3) the next warehouse level (Config.Warehouse.Levels: its upgrade
--                  level k is warehouse level k + 1, a new player's Garage is 0); stands +step small display stands
--                  (from Config.Warehouse.MoreFrom: the level's big stands + these); lights the
--                  income × (1 + step) a level (compounding: CollectionRules' income, so the HUD, the stands' tags and
--                  the picker show it); engine the van's top speed + step a level (its SpeedMult attribute,
--                  client/Drive.luau); danny his walk + step a level (shared/MoveHelperBrain.luau trained)
-- (A bigger cargo bay was not done: the moves' packing, Config.Moving.Beds.sprinter, and the Sprinter's walk-in body
-- are one size; the engine is the safe van upgrade.)
-- The tuning (8.3 economy: saving up): a first haul on show earns about $40 – 50 a minute on 12 stands
-- (Config.Collection) and a move takes about 20 minutes, so the first level of each comes after a move or two, the top
-- ones after 10 – 15 hours of play; the lights, the engine and Danny cost $161,500 in all, More stands $52,000 and the
-- warehouse's levels $138,500 (8.3 economy: the Workshop after a move or two, the Big Warehouse, today's, after hours,
-- the Logistics Center the long goal): everything bought $352,000.
--   Order          the cards' order in the window
--   Flag           the save's mark: profile.sandboxUpgrades is read only from a real save written with it
--   Danny          the player attribute server/Upgrades.luau keeps Danny's training level in (the helper reads it)
--   WarehouseFlag  8.3: the save's mark of the warehouse level: a real save without it (from before 8.3) had today's
--                  warehouse, so it gets warehouse level 4 (UpgradeRules.fromSave); WarehouseAttribute the player
--                  attribute server/Upgrades.luau keeps their warehouse level (1 … 5) in (the client reads it)
export type SandboxUpgradeDef = { name: string, icon: string, max: number, step: number, prices: { number } }
Config.SandboxUpgrades = {
	Order = { "warehouse", "stands", "lights", "engine", "danny" } :: { string },
	List = {
		warehouse = { name = "ZDC Warehouse", icon = "🏭", max = 4, step = 1, prices = { 1000, 7500, 30000, 100000 } },
		stands = { name = "More stands", icon = "🏛️", max = 4, step = 2, prices = { 4000, 8000, 15000, 25000 } },
		lights = { name = "Showroom lights", icon = "💡", max = 5, step = 0.1, prices = { 1500, 4000, 12000, 30000, 75000 } },
		engine = { name = "Van engine", icon = "🚐", max = 3, step = 0.05, prices = { 1500, 5000, 15000 } },
		danny = { name = "Danny's training", icon = "🏃", max = 3, step = 0.1, prices = { 1500, 4000, 12000 } },
	} :: { [string]: SandboxUpgradeDef },
	Flag = "sandboxUpgradesKept",
	Danny = "DannyTraining",
	WarehouseFlag = "warehouseLevelKept",
	WarehouseAttribute = "WarehouseLevel",
}

-- 8.2 SANDBOX, the collection book (the owner: collectors want to know what they have found and what is still out
-- there). Every piece of the sandbox house's catalogue (shared/FurnitureLooks.luau Order without Walt's farm pieces: the
-- ordinary furniture and the collectibles) is unknown (a dark silhouette, "???") until a move brings one home
-- (Collection.add), then found: its name, its rarity's colour, how many came home, the best condition, its value.
-- shared/CollectionBookRules.luau has the rules (tests/collectionbook_test.luau), server/CollectionBook.luau keeps the
-- save (profile.collectionBook) and pays the milestones (tests/collectionbook_runtime_test.luau), client/CollectionBookUi.luau
-- is the book (the HUD's 📖 BOOK chip, the key).
--   Milestones   in the book's order: id, name, kind ("found": `need` pieces found; "furniture": every ordinary piece;
--                "collectibles": every collectible; "legendary": a legendary piece found) and its reward ($: paid once,
--                by the server, "BookMilestone")
--   Retired      8.4 review: a milestone's id an older server knows with another meaning → the milestone that took its
--                place ("collectibles": 8.2's $2,500 for its 12 collectibles; "collectibles24": the 24 now, $10,000). Paid
--                there, it stays paid in the save (an older server never pays it again) but is never paid or shown here;
--                paying the one that took its place marks it paid too (its pieces are in it)
--   Key          the key that opens and closes the book (a computer)
--   Pad          8.3: the gamepad's button for it (an Enum.KeyCode name: the D-pad's →; shared/SandboxPad.luau)
--   Flag         the save's mark: profile.collectionBook is read only from a real save written with it (an older real
--                save fills the book from its stock, and its milestones pay on the first join)
--   MaxCount     the most "brought home" a piece counts
--   Window       the book's card: Width × Height at most, Margin / TouchMargin from the screen's edges, Side its left
--                column (the progress and the milestones; SideTouch on a touch screen), Tile / TileTouch a card's
--                narrowest, Picture / PictureTouch the picture's height over a card's width, Gap between the cards
--   MaxViews     3D pictures (ViewportFrames) alive at once: only the cards on screen get one (a found piece in its
--                colours, an unknown one as a dark silhouette), the others show the emoji or "?"
--   MaxModels    the pieces' models kept built for the pictures (the oldest go)
--   Silhouette   an unknown piece's colour (RGB): its 3D picture tinted to it
export type BookMilestone = { id: string, name: string, kind: string, need: number?, reward: number }
Config.CollectionBook = {
	Milestones = {
		{ id = "found10", name = "Found 10 pieces", kind = "found", need = 10, reward = 250 },
		{ id = "found20", name = "Found 20 pieces", kind = "found", need = 20, reward = 500 },
		{ id = "furniture", name = "All the furniture", kind = "furniture", reward = 2000 },
		{ id = "collectibles24", name = "Found every collectible", kind = "collectibles", reward = 10000 }, -- (8.3: 24 collectibles now, was $2,500 for 12; 8.3 economy: $10,000; 8.4 review: so a new id, Retired)
		{ id = "legendary", name = "A legendary!", kind = "legendary", reward = 1500 },
	} :: { BookMilestone },
	Retired = { collectibles = "collectibles24" } :: { [string]: string }, -- 8.4 review
	Key = "C", -- (8.2 review: C for Collection; K stays the crew panel's, as the crew's texts say)
	Pad = "DPadRight", -- 8.3: the gamepad's way to the book (shared/SandboxPad.luau)
	Flag = "collectionBookKept",
	MaxCount = 1_000_000,
	Window = {
		Width = 980,
		Height = 640,
		Margin = 16,
		TouchMargin = 8,
		Side = 220,
		SideTouch = 196,
		Tile = 120,
		TileTouch = 128,
		Picture = 0.62,
		PictureTouch = 0.5,
		Gap = 8,
	},
	MaxViews = 16,
	MaxModels = 32,
	Silhouette = { 14, 15, 18 } :: { number },
}

-- 8.2 SANDBOX, the daily tasks (the owner: "daily tasks that bring players back"; the city's Config.Tasks and the phone's
-- TASKS app do not run in the sandbox). shared/SandboxTasks.luau picks and counts them (tests/sandboxtasks_test.luau),
-- server/SandboxTasks.luau keeps profile.sandboxTasks, counts what happens and pays (tests/sandboxtasks_runtime_test.luau),
-- client/SandboxTasksUi.luau is the TASKS panel (the key Key or the 📋 TASKS chip under the money).
-- Every UTC day a player gets Daily tasks from DailyPool and every UTC week (from Monday 00:00 UTC) one from WeeklyPool,
-- picked by the day's (the week's) number and the UserId: the same all day, new at 00:00 UTC; never two of one `group`
-- a day. A kind's `event` is what the server counts:
--   home      pieces that came home into your warehouse's stock (Collection: every new piece)
--   rare      … of them RareRank or rarer (Config.Collection's tiers: 3 is rare)
--   clean     a move finished with pieces home and nothing broken (everybody in its crew)
--   moves     a move finished with pieces home (everybody in its crew)
--   trips     the trips home of one move (`best`: the most in one move counts, not a sum)
--   shown     pieces on show at once (`best`)
--   sell      $ your pieces sold for
--   income    $ your display stands paid
--   upgrade   levels bought at the UPGRADES desk (never picked once every upgrade is at its top)
--   danny     Danny holds the other end of your `item` (the sofa) while you carry it
--   hotsell   8.3: pieces of today's hot kinds you sold (Config.Market)
--   hotincome 8.3: $ your hot pieces on show earned (their share of what the stands paid)
--   offer     8.3: offers of the showroom's visitors you accepted (Config.Visitors; never picked while they are off)
-- `text` is the title ({n} the target; `one` when it is 1), `target` the range it is picked from (in `step`s), `money`
-- the reward at the range's low end (its high end pays TopShare more, rounded to $10), `icon` its emoji.
--   AllDaily   the bonus for every daily done (its own CLAIM); a task done and not claimed when the day (the week)
--              turns is paid then
--   Key        the key that opens and closes the panel (a computer)
--   Pad        8.3: the gamepad's button for it (an Enum.KeyCode name: the D-pad's ↓; shared/SandboxPad.luau)
--   StateGap   s between two states to one player; CheckEvery: s between two looks for the reset at 00:00 UTC;
--              SaveDelay: s from a claim to its save (one save for a burst); DannyEvery: s between two looks whether
--              Danny holds the other end of your piece (only while a danny task is open)
--   Flag       the save's mark: profile.sandboxTasks is read only from a real save written with it
-- The tuning (8.3 economy): a first haul on show earns about $40 – 50 a minute (Config.Collection); the three dailies
-- and the bonus pay $660 – 950 (a quarter of an hour on show or so), the weekly $1,200 – 3,000.
export type SandboxTaskDef = {
	id: string,
	event: string,
	icon: string,
	text: string,
	one: string?,
	target: { number },
	step: number?,
	money: number,
	group: string?,
	best: boolean?,
	item: string?,
}
Config.SandboxTasks = {
	Daily = 3,
	AllDaily = 300,
	TopShare = 0.5,
	RareRank = 3,
	Key = "J",
	Pad = "DPadDown", -- 8.3: the gamepad's way to the TASKS panel (shared/SandboxPad.luau)
	StateGap = 0.5,
	CheckEvery = 10,
	SaveDelay = 5,
	DannyEvery = 1,
	Flag = "sandboxTasksKept",
	DailyPool = {
		{ id = "home", group = "home", event = "home", icon = "📦", text = "Bring {n} pieces home", target = { 8, 14 }, money = 120 },
		{ id = "rare", group = "home", event = "rare", icon = "💎", text = "Bring home {n} rare or better pieces", one = "Bring home a rare or better piece", target = { 1, 2 }, money = 150 },
		{ id = "clean", group = "move", event = "clean", icon = "✨", text = "Finish {n} moves with nothing broken", one = "Finish a move with nothing broken", target = { 1, 1 }, money = 200 },
		{ id = "trips", group = "move", event = "trips", best = true, icon = "🚐", text = "Make {n} trips home in one move", target = { 2, 3 }, money = 150 },
		{ id = "shown", event = "shown", best = true, icon = "🏛️", text = "Have {n} pieces on show at once", target = { 6, 10 }, money = 120 },
		{ id = "sell", group = "money", event = "sell", icon = "💰", text = "Sell pieces worth ${n}", target = { 150, 400 }, step = 50, money = 120 },
		{ id = "income", group = "money", event = "income", icon = "📈", text = "Earn ${n} from your stands", target = { 300, 800 }, step = 50, money = 150 },
		{ id = "upgrade", event = "upgrade", icon = "⬆️", text = "Buy {n} upgrades", one = "Buy an upgrade", target = { 1, 1 }, money = 150 },
		{ id = "danny", event = "danny", item = "sofa", icon = "🛋️", text = "Carry the sofa with Danny", target = { 1, 1 }, money = 120 },
		-- 8.3, the market (Config.Market): one of these a day at most
		{ id = "hotsell", group = "market", event = "hotsell", icon = "🔥", text = "Sell {n} hot items", one = "Sell a hot item", target = { 1, 2 }, money = 150 },
		{ id = "hotincome", group = "market", event = "hotincome", icon = "🔥", text = "Earn ${n} from hot items on show", target = { 100, 250 }, step = 50, money = 150 },
		{ id = "offer", event = "offer", icon = "🤝", text = "Accept {n} offers from visitors", one = "Accept an offer from a visitor", target = { 1, 1 }, money = 150 }, -- 8.3: Config.Visitors
	} :: { SandboxTaskDef },
	WeeklyPool = {
		{ id = "w_home", event = "home", icon = "📦", text = "Bring {n} pieces home", target = { 60, 90 }, step = 10, money = 1500 },
		{ id = "w_rare", event = "rare", icon = "💎", text = "Bring home {n} rare or better pieces", target = { 10, 20 }, step = 5, money = 1500 },
		{ id = "w_moves", event = "moves", icon = "🏠", text = "Finish {n} moves", target = { 5, 8 }, money = 1500 },
		{ id = "w_clean", event = "clean", icon = "✨", text = "Finish {n} moves with nothing broken", target = { 3, 5 }, money = 2000 },
		{ id = "w_income", event = "income", icon = "📈", text = "Earn ${n} from your stands", target = { 4000, 6000 }, step = 500, money = 1500 },
		{ id = "w_sell", event = "sell", icon = "💰", text = "Sell pieces worth ${n}", target = { 2000, 3000 }, step = 250, money = 1200 },
	} :: { SandboxTaskDef },
}

-- 8.2 SANDBOX, showing off (server/SandboxLeaders.luau; its rules shared/SandboxLeadersRules.luau, checked by
-- tests/sandboxleaders_test.luau and tests/sandboxleaders_runtime_test.luau). Roblox's player list shows every player's
-- money, income a minute and collection (the city's Level, Money and Deliveries columns go in the sandbox), and the
-- TOP MOVERS board at the crossroads ranks the server's players by what their collection is worth.
--   Every        s: a player's list columns are written at most this often (the changes in between wait for it)
--   BoardEvery   s: the board's rows are written at most this often
--   Rows         players on the board (the best ones)
--   Legendary    the collection tier (Config.Collection.Tiers) the board's LEGENDARY column counts
--   Stats        the player list's columns, in their order (the first sorts the list): the money (an IntValue), $ a
--                minute (a NumberValue, to a tenth), the collection's worth (an IntValue)
--   Board        the signboard: Corner studs east of Pražská's east edge and south of Depot Row's south edge (the
--                crossroads' south-east corner, off the shoulders, the lamps and the trees), its face Yaw (degrees,
--                SandboxMap's: 45 looks north-west, to the crossroads); the painted panel Width × Height studs, Lift
--                over the ground, Thick; the gable roof Over past the panel each side, Run deep each way from the
--                ridge, Rise high; PixelsPerStud and Range (studs) of its SurfaceGuis (one on each face)
--   AllTime      the best collection worth each player ever had, kept in the OrderedDataStore Store (key: the user
--                id): read when they join, written (UpdateAsync, only ever up) at most every Every s a player, never
--                from Studio unless Studio is true; every call in a pcall (no API access: the column shows this
--                session's best). On = false: no store, no ALL-TIME column
Config.SandboxLeaders = {
	Every = 1,
	BoardEvery = 2,
	Rows = 5,
	Legendary = "legendary",
	Stats = { Money = "💰 $", Income = "📈 $/min", Collection = "⭐ Collection" },
	Board = {
		Corner = { 26, 24 } :: { number },
		Yaw = 45,
		Width = 20,
		Height = 11.5,
		Lift = 2.6,
		Thick = 0.6,
		Roof = { Over = 2, Run = 2.2, Rise = 1.7 },
		PixelsPerStud = 40,
		Range = 260,
	},
	AllTime = { On = true, Store = "Sandbox_TopCollection", Every = 120, Studio = false },
}

-- 8.3 SANDBOX, the market (the owner: selling should be a decision, not a reflex). shared/Market.luau has the rules
-- (tests/market_test.luau), server/Collection.luau prices every sale and the stands' income with it, the STOCK list and
-- the picker show it (client/WarehouseUi.luau: the 🔥 / ❄ tags, the header's line, prices with the market in them).
-- Every UTC day, picked from the day's number alone (the same on every server and for everybody):
--   Hot               kinds are hot: they sell for × HotSell and earn × HotIncome on show; HotCollectibles of them are
--                     collectibles (a piece with its own rarity), the rest ordinary furniture
--   Cold              kinds of furniture are cold: they sell for × ColdSell
--   MinValue          the cheapest kind ($, its catalogue value) the market picks: the sandbox house's kinds (the
--                     catalogue without Walt's farm pieces) worth this or more (a new piece joins by itself)
-- And per player, kept in the save (profile.market, only from a real save written with Flag):
--   Drop / MaxDrop    every piece of a kind you sell lowers that kind's price for you by Drop, at most MaxDrop (a bulk
--                     sale's pieces one after the other)
--   Recover           s for one piece's Drop to come back; at 00:00 UTC all of it comes back
--   Salt              the picks' dice (a new salt: other days)
-- The tuning (8.3 economy): a piece sells for about a quarter of an hour of showing it (Config.Collection), so a hot
-- one sells for about 21 minutes' worth and earns a fifth more while it stays; a cold one is better kept on show until
-- tomorrow; selling eight radios at once pays the last few 40 % less, and 20 minutes later the next sells 5 % dearer
-- again.
Config.Market = {
	Hot = 3,
	HotCollectibles = 1,
	Cold = 1,
	HotSell = 1.4,
	HotIncome = 1.2,
	ColdSell = 0.7,
	MinValue = 100,
	Drop = 0.05,
	MaxDrop = 0.4,
	Recover = 1200,
	Salt = 8303,
	Flag = "marketKept",
}

-- 8.3 SANDBOX, the showroom's visitors (the owner: the warehouse should feel alive). A few customers walk in through the
-- roller door, stroll between the stands with pieces on show, stop at a piece ("Ooh, a gramophone!") and leave; now and
-- then one offers to buy a piece on show for more than its market price, and you ACCEPT or DECLINE on a small card.
-- shared/Visitors.luau has the rules (tests/visitors_test.luau), server/Visitors.luau walks them (server/Npcs.luau's
-- bodies; one loop for them all), server/VisitorOffers.luau prices and checks the offers (tests/visitoroffers_runtime_test.luau),
-- client/OfferCard.luau is the card.
--   On          false: no visitors (and the daily task "offer" is never picked)
--   Cap         visitors in the whole server at once; PerHall: in one warehouse at once, by its level (Config.Warehouse.Levels:
--               the Garage's one, the Workshop's two, three from the Warehouse on)
--   Group       the chances a group is 1, 2 or 3 visitors (they walk in Stagger s apart)
--   Near        studs round a warehouse's walls that count as its owner being at their warehouse
--   NearEvery   s between two groups while the owner is at their warehouse; AwayEvery: while away (at most every few
--               minutes); FirstWait: s from the owner coming (or the first piece going on show) to a group
--   Tick        s between two looks of the one loop (every hall, every visitor, the offers' clocks)
--   Stops       the pieces a visitor stops at (a range); Look: s at one; Talk: the chance it says something there
--   Walk        a visitor's pace (studs / s); Stuck: s without getting closer before a walk gives up; Life: s a visitor
--               stays at most
--   Clear       studs a standing visitor keeps from a player (one closer: it moves on; never a spot that close)
--   Cell        studs: the hall's walking grid (shared/Visitors.luau hall); Margin: studs a visitor's middle keeps from
--               the walls, the podiums and the desk; View: studs from a podium's edge it stands to look; DeskClear: studs
--               round the UPGRADES desk where no visitor stops (the player's spot at it)
--   DoorSide    studs from the door's middle a visitor walks in and out (beside the van's back, off the unloading lane;
--               at most the door's half less DoorEdge); Outside: { across, out } studs from the door's middle where it
--               comes from and goes (beside the van, from the street's side); Approach: studs outside the wall's face it
--               turns in towards the door (behind the van's back, past the bollards); Threshold: studs outside the door's
--               face it steps through
--   Offer       Chance: a visitor's chance (× its kind's chance) to offer at a piece it looks at, once each, only while
--               the owner is in the hall on foot within Reach studs; Every: s at least between two offers to one player;
--               Expire: s an offer stays open; the price: the piece's market price now × Min … Max, + Rare for each
--               rarity rank over common, + Hot for a hot kind (its market price is × HotSell already), + the kind's
--               pay, Top at most, rounded up to $5 (from $100) or $10 (from $1,000)
--   Kinds       who comes: id, title (the name tag's line and the toast's "The collector"), weight (how often), chance
--               (× Offer.Chance), pay (+ the offer's ×), names, look (shared/NpcLooks.luau's fields over a townsperson's)
-- The tuning (8.3 economy): a piece sells for about a quarter of an hour of showing it (Config.Collection); an offer
-- pays 10 – 50 % more (Top: a rarer piece's, a hot one's and a collector's offers are nearer the top, never over it),
-- so accepting one is worth it when another piece waits for the stand. At the warehouse a group comes about every
-- minute and an offer about every two (Every s apart at least).
export type VisitorKind = { id: string, title: string, weight: number, chance: number, pay: number, names: { string }, look: { [string]: any } }
Config.Visitors = {
	On = true,
	Cap = 6,
	PerHall = { 1, 2, 3, 3, 3 } :: { number },
	Group = { 0.5, 0.35, 0.15 } :: { number },
	Stagger = 1.6,
	Near = 30,
	NearEvery = { 35, 70 } :: { number },
	AwayEvery = { 180, 300 } :: { number },
	FirstWait = { 4, 9 } :: { number },
	Tick = 0.25,
	Stops = { 2, 4 } :: { number },
	Look = { 3, 6 } :: { number },
	Talk = 0.6,
	Walk = 6,
	Stuck = 2.5,
	Life = 180,
	Clear = 3,
	Cell = 1,
	Margin = 1.2,
	View = 2.2,
	DeskClear = 6,
	DoorSide = 9,
	DoorEdge = 2.5,
	Outside = { 12, 34 } :: { number },
	Approach = 3.5,
	Threshold = 1.5,
	Offer = {
		Chance = 0.25,
		Reach = 45,
		Every = 90,
		Expire = 30,
		Min = 1.1,
		Max = 1.5,
		Rare = 0.05,
		Hot = 0.1,
		Top = 1.5,
	},
	Kinds = {
		{ id = "tourist", title = "Tourist", weight = 4, chance = 0.6, pay = 0, names = { "Greta", "Hans", "Yuki", "Pierre", "Lena", "Marco" },
			look = { hat = "cap", hatColor = { 236, 92, 72 }, pants = { 196, 178, 140 }, shortSleeves = true, shoes = { 236, 236, 230 } } },
		{ id = "hiker", title = "Hiker", weight = 3, chance = 0.7, pay = 0, names = { "Sepp", "Anna", "Toni", "Heidi" },
			look = { hat = "beanie", hatColor = { 196, 58, 48 }, shirt = { 64, 120, 84 }, pants = { 120, 104, 78 }, boots = true, shoes = { 92, 62, 40 } } },
		{ id = "collector", title = "Collector", weight = 2, chance = 1.6, pay = 0.1, names = { "Mr. Whitcombe", "Mrs. Ashford", "Dr. Lindqvist" },
			look = { hat = "none", shirt = { 138, 106, 72 }, vest = { 112, 86, 58 }, tie = { 124, 36, 42 }, pants = { 84, 74, 62 }, hair = { 172, 172, 168 } } },
		{ id = "dealer", title = "Antique dealer", weight = 1, chance = 1.3, pay = 0.05, names = { "Mrs. Moretti", "Mr. Okafor" },
			look = { hat = "none", coat = { 52, 66, 58 }, shirt = { 226, 220, 204 }, tie = { 40, 40, 46 }, pants = { 50, 50, 56 } } },
	} :: { VisitorKind },
}

-- 8.7 SANDBOX, trading between players (the owner: "I'd like customers to be players too … I want selling to make
-- sense"). Another player is a buyer who wants a piece they lack (for their book, a legendary, a hot kind) and pays more
-- than the game would. shared/PlayerTradeRules.luau has the rules (tests/playertrade_test.luau), server/PlayerTrade.luau
-- decides every offer and sale (tests/playertrade_runtime_test.luau), client/TradeUi.luau is the composer, the price
-- picker and the buy question, client/OfferCard.luau the seller's card (a visitor's and a player's offers).
--   On          false: no trade prompts, every request refused
--   MinTimes    a price is at least this × the piece's value (its sell price to the game without the market:
--               CollectionRules.sell, its condition in it; the same every day, so a FOR SALE sign stays valid)
--   MaxTimes    … and at most this × it (money passed between friends' accounts stays bounded)
--   Fee         the ZDC fee: this share of the price is taken from the seller's side and disappears (a money sink)
--   Expire      s an offer stays open for the seller's answer
--   PerSeller   open offers one seller holds at most (a buyer holds one at a time)
--   Presets     the composer's and the picker's quick prices: × the value (clamped to the bounds)
--   StepShare   the −/+ step: the roundest of 1, 2, 5 × 10ⁿ at most this × the price shown (never under the value's;
--               $1 at least): 10 % a tap, so 10 × is a dozen taps past the 3 × preset
--   BigSale     $: a sale this big or bigger is told to the whole server in the chat (0: never)
--   Tick        s between two looks at the offers' clocks
--   PromptTag / SellerAttribute   the CollectionService tag and attribute (the seller's UserId) of the stands' prompts
--               for the other players ("Make an offer", "Buy $X"): client/TradePrompts.luau hides them from the seller
--   Ticket      8.7 review: s a use of a stand's "Make an offer" / "Buy $X" prompt holds good: the server keeps a ticket
--               (that seller, piece and stand, the stand's point) and SEND / BUY are taken only with one this fresh
--   Reach       8.7 review: studs from that stand's point the buyer may stand at SEND / BUY (the prompts' own reach is
--               Config.Warehouse.PromptDistance: room to step back from the stand while choosing a price)
--   Cooldown    8.7 review: s before a buyer may offer a seller again after their offer was declined or ran out (none
--               after a deal): a few accounts can't keep a seller's PerSeller slots full
--   CardArm     8.7 review: s the offer card (client/OfferCard.luau: a visitor's and a player's) takes no ACCEPT, DECLINE,
--               ESC or B after it opens or shows the next offer of its queue: a double click answers one offer, never
--               the next one unread (its buttons look off until then)
--   CardGap     8.7 review: s the card stays away between one offer answered and the next one shown (the switch seen)
-- The tuning: a piece sells to the game for about a quarter of an hour of showing it (Config.Collection); a player who
-- lacks it pays 1 – 10 × that, the seller keeps 92 % (at 2 × the game's price: 1.84 ×, so selling to a player makes
-- sense; at 1 × it is a loss of 8 %, so a sign at the game's price is pointless). A legendary sells to the game for
-- $1,100 – 1,400: at 2 × it is a big sale.
Config.PlayerTrade = {
	On = true,
	MinTimes = 1,
	MaxTimes = 10,
	Fee = 0.08,
	Expire = 45,
	PerSeller = 3,
	Presets = { 1, 1.5, 2, 3 } :: { number },
	StepShare = 0.1,
	BigSale = 2500,
	Tick = 0.5,
	PromptTag = "TradePrompt",
	SellerAttribute = "TradeSeller",
	Ticket = 120, -- 8.7 review
	Reach = 40,
	Cooldown = 60,
	CardArm = 0.6,
	CardGap = 0.25,
}

-- 8.3 SANDBOX, the PAINT shop (the owner: give players a way to make their van their own). A 🎨 Paint van prompt on your
-- own Sprinter while it stands at your plot's van spot opens the shop's window (client/VanPaintUi.luau; its 3D picture
-- client/VanPaintPreview.luau). server/VanPaint.luau sells, keeps what you own (profile.vanPaint: { owned, worn }, read
-- only from a real save written with Flag) and paints every van of yours as it comes out (PLAY, START, CAR) with
-- shared/VanLook.luau, for everybody to see; shared/VanPaintRules.luau has the rules (tests/vanpaint_test.luau,
-- tests/vanpaint_runtime_test.luau). Cosmetic only: the van's collision, cargo bay, doors and speed never change. Each
-- item is bought once and kept for good; wearing one you own is free.
--   Paints     the body colours in the window's order: id, name, color (RGB), price ($; 0 and no unlock: everybody's),
--              material (a Roblox material, the premium finishes; else SmoothPlastic), unlock (a collection book
--              milestone's id, Config.CollectionBook.Milestones: locked until the book has paid it), premium (the
--              window's gold frame). The first is the factory's: the van as built (its parts look in Config.Cars' colour,
--              the owner's Blender look in its own cream)
--   Liveries   the stripes: id, name, stripe (RGB, or "contrast": Contrast's light ink on a dark body, its dark ink on a
--              light one) that the ZDC band, the ZDC logo, the nose badge and the back doors' stripes take, material,
--              roof (a Roofs decoration on the high roof), price, unlock, premium as the paints'. The first is the
--              factory's (the ZDC red)
--   Roofs      a decoration on the flat high roof: its stripes along the van (x their middle, w their width, color their
--              own, else the livery's stripe) from z From to To (studs in the van's frame, -z its front: the flat roof
--              of both looks), Lift over the roof's top and Thick (thin parts, no collision, welded to the body)
--   Contrast   the "contrast" stripe: Light on a body darker than Threshold (its luminance, 0 … 255), else Dark
--   Finishes   the Blender look's finishes the paint takes (server/SprinterMesh.luau): finish → the prefix of the car
--              model's attributes (<prefix>Color, <prefix>Material, <prefix>Reflectance; none: the finish's own look)
--   Prompt     🎨 Paint van: Reach (studs), Home (studs: the van's middle this near its plot's vanSpot counts as parked
--              there), Still (studs a second: slower counts as standing), Every (s between two looks), At (its point in
--              the van's frame: the driver's side of the cargo box, clear of the doors' prompts)
--   Flag       the save's mark: profile.vanPaint is read only from a real save written with it
--   Window     the card: Width × Height at most (unscaled px), Preview the 3D picture's share of its width, Tile a
--              swatch's narrowest (TileTouch on a touch screen) and TileHeight its height; the 3D picture's camera: Yaw
--              (degrees from the front toward the right: below 0 the driver's side), Pitch (down onto the roof), Fov, and
--              Fill (the van's share of the picture)
-- The tuning (8.3 economy): the start money is $500 and a first haul on show earns about $40 – 50 a minute: a colour
-- comes after a move or two, a livery after an hour or so, Collector gold once the collection book found a legendary
-- ($5,000), Mirror chrome is the late flex ($50,000: tens of hours of play); everything costs $65,700.
export type VanPaintDef = {
	id: string,
	name: string,
	price: number,
	color: { number }?,
	stripe: any?, -- (a livery's: RGB or "contrast")
	material: string?,
	roof: string?,
	unlock: string?,
	premium: boolean?,
}
Config.VanPaint = {
	Paints = {
		{ id = "cream", name = "ZDC cream", color = { 232, 226, 210 }, price = 0 },
		{ id = "white", name = "Arctic white", color = { 241, 243, 245 }, price = 300 },
		{ id = "silver", name = "Silver grey", color = { 170, 175, 181 }, price = 400 },
		{ id = "graphite", name = "Graphite", color = { 66, 70, 76 }, price = 500 },
		{ id = "black", name = "Midnight black", color = { 27, 29, 33 }, price = 600 },
		{ id = "red", name = "Fire red", color = { 176, 32, 32 }, price = 500 },
		{ id = "orange", name = "Sunset orange", color = { 226, 112, 38 }, price = 500 },
		{ id = "yellow", name = "Taxi yellow", color = { 242, 190, 44 }, price = 500 },
		{ id = "forest", name = "Forest green", color = { 44, 98, 64 }, price = 600 },
		{ id = "glacier", name = "Glacier blue", color = { 118, 168, 212 }, price = 500 },
		{ id = "navy", name = "Navy blue", color = { 30, 50, 92 }, price = 600 },
		{ id = "gold", name = "Collector gold", color = { 214, 170, 62 }, material = "Metal", price = 5000, unlock = "legendary", premium = true },
		{ id = "chrome", name = "Mirror chrome", color = { 206, 212, 218 }, material = "Foil", price = 50000, premium = true },
	} :: { VanPaintDef },
	Liveries = {
		{ id = "zdc", name = "ZDC classic", stripe = { 179, 38, 30 }, price = 0 },
		{ id = "alpine", name = "Alpine", stripe = { 34, 110, 70 }, roof = "snow", price = 1200 },
		{ id = "racing", name = "Racing stripes", stripe = "contrast", roof = "racing", price = 1500 },
		{ id = "goldline", name = "Gold line", stripe = { 212, 170, 60 }, material = "Metal", roof = "pinstripe", price = 3000 },
	} :: { VanPaintDef },
	Roofs = {
		racing = { { x = -0.75, w = 0.9 }, { x = 0.75, w = 0.9 } },
		snow = { { x = 0, w = 5.8, color = { 244, 247, 250 } } },
		pinstripe = { { x = -2.7, w = 0.16 }, { x = 2.7, w = 0.16 } },
	} :: { [string]: { { x: number, w: number, color: { number }? } } },
	Roof = { From = -4.9, To = 10.6, Lift = 0.01, Thick = 0.05 },
	Contrast = { Light = { 244, 244, 238 } :: { number }, Dark = { 30, 32, 36 } :: { number }, Threshold = 150 },
	Finishes = { paint = "Paint", stripe = "Stripe" } :: { [string]: string },
	Prompt = { Reach = 8, Home = 12, Still = 1.5, Every = 0.5, At = { -4.6, 4.6, 4.0 } :: { number } },
	Flag = "vanPaintKept",
	Window = { Width = 880, Height = 470, Preview = 0.42, Tile = 92, TileTouch = 96, TileHeight = 70, Yaw = -38, Pitch = 26, Fov = 30, Fill = 0.92 },
}

-- 8.3 SANDBOX, the light (the owner: "it is too bright: in the house I cannot see my own character, and walking into the
-- warehouse is a flashbang"). Every light number of the sandbox, in one place. shared/SandboxLightRules.luau has the
-- rules; tests/sandboxlight_test.luau and tests/sandboxlight_runtime_test.luau hold every light to Caps.
--   Sky        the fixed warm afternoon outside (server/SandboxWorld.luau lighting(), as SandboxScenery.Light): Clock
--              (Lighting.ClockTime), Latitude (central Bohemia's 50° north; the Alps' 47 before), Brightness (the sun),
--              Exposure (the base ExposureCompensation: the eyes add their place's), Ambient (the light indoors and in the shade: the house's and the hall's fill),
--              Outdoor (OutdoorAmbient), ShiftTop / ShiftBottom (ColorShift_Top / _Bottom), Diffuse / Specular
--              (EnvironmentDiffuseScale / SpecularScale), Softness (ShadowSoftness); the Atmosphere: Air (its Color and
--              the fog's), Decay, Density, Offset, Glare, Haze; Fog (FogStart, FogEnd: only without an Atmosphere); the
--              grade SandboxGrade: Tint, Saturation, Contrast, Lift (its Brightness); Clouds; Sun (the sun's size, deg)
--   Places     the eyes (client/SandboxLight.luau): each place's look, eased in whenever you walk into it ("outdoors",
--              "house": the move's house inside, "warehouse": a plot's hall, "van": a Sprinter's walk-in bay):
--                Exposure   added to Sky.Exposure (Lighting.ExposureCompensation, stops; Roblox takes -3 … 3)
--                Bloom      the one BloomEffect: Intensity (0 … 1), Size (px, 0 … 56), Threshold (0.8 … 4: how bright a
--                           pixel must be to glow; over 1.5 only the Neon and the sun's glints, never a white wall)
--                Grade      the client's own ColorCorrection "SandboxEyes" over the server's SandboxGrade: Brightness,
--                           Contrast, Saturation (-1 … 1; 0 is no change) and Tint (white is no change)
--                Rays       the SunRays' Intensity (0 … 1; RaySpread its Spread); indoors none
--   Ease       s: the eyes reach 95 % of a new place's look in this long (never at once: no flash at a door)
--   Step       s: one easing step at most this long (a hitch never jumps the look)
--   Every      s between two looks at where you are (the easing writes every frame only while it moves)
--   LiteBloom  a phone's or a tablet's bloom: × this (client/DeviceBudget.luau lite)
--   House      the house's inside (server/HouseInterior.luau): Lamp (each room's ceiling light, a PointLight: Brightness,
--              Range, Color; a room longer than Long gets two; 8.5.2, the roomier big house: along a side longer than
--              twice Span a lamp each Span at most, never two closer than Apart: SandboxLightRules.lamps), Porch (the daylight through the front door: a
--              SurfaceLight's Brightness, Range, Color) and the Neon parts' colours: Glow (the ceiling lamps' discs),
--              Tube (the garage's), Window / BathWindow (the panes' daylight), Daylight (the porch's wall of daylight)
--   Warehouse  the hall (shared/WarehouseLayout.luau, server/WarehouseMesh.luau): Lamp (each of its hall lights, a
--              PointLight), Glow (their Neon discs), MeshGlow (the owner's Blender lamps, the finish "glow"); 8.3,
--              Levels: each warehouse level's lamps (Config.Warehouse.Levels: 1 the Garage … 5 the Logistics Center),
--              Brightness and Range over Lamp's (its Color): the lamps hang where the owner's Blender lamps do, lower
--              and closer together in a smaller hall (dimmer, shorter), higher in the Logistics centre (a longer reach
--              to its floor); level 4 is Lamp itself. tests/sandboxlight_test.luau holds every level to the Caps
--   Van       the Sprinter's walk-in bay (server/Vehicles.luau): Bay (its ceiling light while a door stands open)
--   Caps       what the tests hold the light to (the model: a light gives Brightness × (1 - (d / Range)²)² at d studs,
--              shared/SandboxLightRules.luau falloff; a sunlit face outside gets about 1.5):
--                Brightness / Range   one light at most
--                RoomLoad / HallLoad  Σ Brightness × Range of a house room's lights / of a hall's at most
--                Peak       the light at a face's height (HeadY over the floor) anywhere indoors, × 2^Exposure, at most
--                           (8.2's house: 2.15, its hall 2.39, the van 1.28: brighter than the sunlit meadow)
--                Floor      the least mean light on a room's or the hall's floor (not a cave either)
--                NeonArea   studs²: a Neon face bigger than this (a lamp looking down, a pane into a room) must be dim:
--                NeonLuma   its colour's luma (0 … 255) at most; a lamp's own small Neon (Glow, Tube, MeshGlow) GlowLuma
--                WallLuma   a house wall's plaster at most (a warm off-white, never a white)
--                Step       the most the exposure may change in one easing step (a 10 fps phone included)
Config.SandboxLight = {
	Sky = {
		Clock = 15.4,
		Latitude = 50, -- (central Bohemia's; 47 in the Alps: the same warm afternoon)
		Brightness = 1.8,
		Exposure = 0,
		Ambient = { 78, 72, 68 } :: { number },
		Outdoor = { 114, 110, 104 } :: { number },
		ShiftTop = { 56, 38, 16 } :: { number },
		ShiftBottom = { 12, 10, 8 } :: { number },
		Diffuse = 0.5,
		Specular = 0.45,
		Softness = 0.3,
		Air = { 200, 204, 212 } :: { number },
		Decay = { 132, 136, 150 } :: { number },
		Density = 0.26,
		Offset = 0.12,
		Glare = 0.4,
		Haze = 1.3,
		Fog = { 1200, 4000 } :: { number },
		Tint = { 255, 246, 232 } :: { number },
		Saturation = 0.06,
		Contrast = 0.12,
		Lift = 0,
		Clouds = { Cover = 0.42, Density = 0.45, Color = { 255, 250, 242 } :: { number } },
		Sun = 12,
	},
	Places = {
		outdoors = {
			Exposure = 0,
			Bloom = { Intensity = 0.3, Size = 20, Threshold = 1.5 },
			Grade = { Brightness = 0, Contrast = 0, Saturation = 0, Tint = { 255, 255, 255 } :: { number } },
			Rays = 0.04,
		},
		house = {
			Exposure = 0.15,
			Bloom = { Intensity = 0.2, Size = 14, Threshold = 1.9 },
			Grade = { Brightness = 0.01, Contrast = -0.03, Saturation = 0, Tint = { 255, 255, 255 } :: { number } },
			Rays = 0,
		},
		warehouse = {
			Exposure = 0.15,
			Bloom = { Intensity = 0.15, Size = 14, Threshold = 2.1 },
			Grade = { Brightness = 0, Contrast = -0.02, Saturation = 0, Tint = { 255, 255, 255 } :: { number } },
			Rays = 0,
		},
		van = {
			Exposure = 0.05,
			Bloom = { Intensity = 0.1, Size = 12, Threshold = 2.2 },
			Grade = { Brightness = 0.01, Contrast = -0.03, Saturation = 0, Tint = { 255, 255, 255 } :: { number } },
			Rays = 0,
		},
	},
	RaySpread = 0.4,
	Ease = 0.6,
	Step = 0.1,
	Every = 0.1,
	LiteBloom = 0.6,
	House = {
		Lamp = { Brightness = 0.5, Range = 24, Long = 28, Span = 36, Apart = 16, Color = { 255, 230, 196 } :: { number } },
		Porch = { Brightness = 0.45, Range = 12, Color = { 255, 246, 230 } :: { number } },
		Glow = { 220, 188, 148 } :: { number },
		Tube = { 196, 206, 218 } :: { number },
		Window = { 108, 134, 154 } :: { number },
		BathWindow = { 146, 162, 172 } :: { number },
		Daylight = { 168, 176, 172 } :: { number },
	},
	Warehouse = {
		Lamp = { Brightness = 0.8, Range = 34, Color = { 255, 240, 220 } :: { number } },
		Glow = { 226, 212, 186 } :: { number },
		MeshGlow = { 232, 216, 188 } :: { number },
		Levels = {
			{ Brightness = 0.45, Range = 22 },
			{ Brightness = 0.3, Range = 26 }, -- (8.3: the Workshop's 4 lamps, 10 apart under its trusses)
			{ Brightness = 0.6, Range = 28 },
			{ Brightness = 0.8, Range = 34 },
			{ Brightness = 0.8, Range = 38 },
		} :: { { Brightness: number, Range: number } },
	},
	Van = {
		Bay = { Brightness = 0.6, Range = 10, Color = { 255, 242, 220 } :: { number } },
	},
	Caps = {
		Brightness = 1,
		Range = 36,
		RoomLoad = 26,
		HallLoad = 170,
		Peak = 1,
		HeadY = 4.5,
		Floor = 0.15,
		NeonArea = 6,
		NeonLuma = 180,
		GlowLuma = 225,
		WallLuma = 220,
		Step = 0.08,
	},
}

-- 8.8 SANDBOX, the auction (design/auction/PLAN.md; the owner: a piece on show earns $/min, so selling it to the game,
-- about a quarter of an hour of its income, is pointless; he asked for "an auction in the finale"). Every Every s a round
-- of lots at the Auction House on Depot Row: before it each player consigns one piece at its desk; each lot runs
-- LotSeconds, players and the NPC collectors bid in steps, the top bid buys it. shared/AuctionRules.luau has the rules
-- (tests/auction_test.luau), shared/AuctionHouseLayout.luau the building (tests/auctionhouse_test.luau),
-- client/AuctionUi.luau the window. 8.8 is the groundwork: nothing is paid or moved yet (the server's part, the atomic
-- transfer and the payments, comes next), and with On false nothing of it shows: no building, no window, no request.
--   On          false: nothing (no Auction House on the map, no window, nothing sent)
--   Every       s from one round's start to the next (from 00:00 UTC + Offset: the same on every server); Close: s
--               before a start the consignments close (the lots are drawn up); Results: s the round's results stay up
--               after its last lot
--   MaxLots     lots a round at most (one a player: Config.Sandbox.MaxPlayers); the cheapest first, the best last
--   LotSeconds  s a lot runs; Gap: s between two lots; Snipe: a bid with less than Window s left puts the clock back to
--               Window s, at most Most s past the lot's planned end (a full round stays within 3 – 5 minutes)
--   Rarities    the rarities a player may consign (Config.Collection's tiers); a broken piece never
--   Reserve     × the piece's worth (its value × its condition): the lot opens there (rounded up to a step) and never
--               sells for less
--   Steps       { from $, step $ }: the next bid is always the price + the step of the price's band
--   (the fee)   the house keeps Config.PlayerTrade.Fee of a sale from the seller: one fee for the trades between players
--               and the auction (shared/PlayerTradeRules.luau fee: 8 %, rounded)
--   Collectors  the NPC bidders: Count of them a lot (their names drawn from Names); each one's max = the worth ×
--               Rarity[the piece's] × Hot or Cold (the day's market, shared/Market.luau) × a die in Spread, the keenest's
--               at least the opening price (every lot sells); one answers a bid after Delay s (a die), never later than
--               Last s before the lot's end, and none bids past its max
--   Salt        the collectors' dice (a lot's seed is its round, its place and its piece: the same lot plays the same)
--   Grand       the Grand Auction (later; hooks only): On, its daily start (Hour, UTC), Lots of the house's own (Items:
--               the exclusive legendaries' ids, none yet), Reserve × their worth
--   House       the building (shared/AuctionHouseLayout.luau): Spot, the middle of its front wall on the ground, looking
--               out (yaw as SandboxMap's spots; the one place to move it when the Jinočany village is built:
--               design/jinocany/plan.json keeps x 40 – 120 here for the Corner Drugstore); Width × Depth, Wall (the walls'
--               height over the floor), Roof (the ridge's rise), Door ({ width, height }), Budget (its parts at most),
--               Range (studs its signs are drawn from), Lamp (its hanging lamps' light)
--   Window      the window (client/AuctionUi.luau): Width × Height at most (unscaled px), Tile a consign tile's
--               narrowest (TileTouch on a touch screen), TileHeight its height
-- The tuning: a piece on show earns its value × its tier's income a minute (a legendary 1.5 %: $80 – 105), and the game
-- buys it for about a quarter of an hour of that (Config.Collection sell). At auction it opens at its worth: about 65
-- minutes of a legendary's income, 100 of an epic's, 125 of a rare's; the collectors usually go 5 – 25 % over (the rarer,
-- the keener), so after the fee a sale nets the seller five to eight times what the game pays. A player who wants the
-- piece must beat the keenest collector: a premium for the book, its milestones and the TOP MOVERS board. Rare is in: a
-- big move brings about 0.6 rares, 0.12 epics and 0.06 legendaries, so without rare most rounds would have no lot.
export type AuctionSpot = { x: number, y: number, z: number, yaw: number }
Config.Auction = {
	On = false,
	Every = 1800,
	Offset = 0,
	Close = 20,
	Results = 90,
	MaxLots = Config.Sandbox.MaxPlayers,
	LotSeconds = 45,
	Gap = 6,
	Snipe = { Window = 8, Most = 20 },
	Rarities = { "rare", "epic", "legendary" } :: { string },
	Reserve = 1,
	Steps = { { 0, 25 }, { 500, 50 }, { 1000, 100 }, { 2500, 200 }, { 5000, 250 }, { 10000, 500 }, { 25000, 1000 } } :: { { number } },
	Collectors = {
		Count = 3,
		Rarity = { rare = 1.05, epic = 1.1, legendary = 1.2 } :: { [string]: number },
		Hot = 1.15,
		Cold = 0.9,
		Spread = { 0.9, 1.2 } :: { number },
		Delay = { 1.5, 5 } :: { number },
		Last = 1,
		Names = { "Lady Fairbanks", "Mr. Okonkwo", "Madame Duval", "Dr. Lindgren", "Signor Bellini", "Mrs. Harrow" } :: { string },
	},
	Salt = 8808,
	Grand = { On = false, Hour = 19, Lots = 3, Reserve = 1.5, Items = {} :: { string } },
	House = {
		Spot = { x = 158, y = 0, z = -22, yaw = 0 } :: AuctionSpot,
		Width = 48,
		Depth = 32,
		Wall = 16,
		Roof = 9,
		Door = { 10, 10 } :: { number },
		Budget = 140,
		Range = 220,
		Lamp = { Brightness = 0.7, Range = 28, Color = { 255, 226, 180 } :: { number } },
	},
	Window = { Width = 720, Height = 430, Tile = 150, TileTouch = 168, TileHeight = 96 },
}

-- 8.9 SANDBOX, Jinočany (design/jinocany/NAVRH.md, plan.json): the village's looks. shared/VillageLooks.luau builds
-- the parts from these numbers (tests/villagelooks_test.luau, tools/village/preview.py); 8.9 step 1 is on the map
-- (server/VillageWorld.luau builds it: Config.VillageWorld).
-- Colours { r, g, b }; materials are Enum.Material's names.
--   Palette   every colour of the village: Render (the old houses' and the rows' walls: cream, ochre, light grey, pale
--             yellow, apricot), Modern (a new build's: white, light grey), Tiles (the clay roofs: red, brick red, brown,
--             dark brown), the window Frames (white, brown), the Doors, the Fences (wood, painted green, grey), the
--             chapel's walls and spire, the drugstore's, the D5's, the barrier's and Sýkorka's, the Crops (a field's
--             ground) and their Rows, each tree kind's trunk and crowns, the far view's
--   Budget    parts at most: a house of each kind (old; row: each house of a terraced body; modern), Rich (one of the six
--             houses to empty, a little richer: for a row, its group's parts at most Rich - row more), a tree, each
--             landmark kind, a field tile with its rows, the far view (Horizon), and Step1: all the parts VillageLooks
--             gives step 1's village (plan.json's step-1 houses, the rows in groups of four; the step-1 landmarks; the
--             fields; the tree lines, the orchard and the green's and the pond's trees; the far view: 1,863 today,
--             VillageLooks.census). The map holds SandboxScenery.Budget (2,500): Step1 leaves Kept for what stays or is
--             the map's own (tools/perf/sandbox_count.py's projection, 8.8's map: the roads 111 (Pražská, Depot Row,
--             the turnaround), the farmstead 130, the ground 23, the boundary 4, the lamps and the signpost 37, the
--             Auction House 101 once it is on: 406; and the village's new roads and lawns)
--   Chunk     studs: a piece's chunk is "<floor(x / Chunk)>_<floor(z / Chunk)>" of its house's or its own middle (one
--             Atomic model each, as SandboxScenery's trees); "ground" (field tiles) and "far" (the D5, the far view)
--             are big, kept on every client (Persistent)
--   Front     studs: a house's front wall this far in from its box's front edge (its eaves stay inside the box; the
--             door's face about 1.2 in from plan.json's door)
--   RowUnit   studs: one house of a terraced row along the street (plan.py's 18)
--   Countryside   9.5: the countryside's spots' looks (see there); Budget's cabin, lodge, mill and cottage their parts
--   Facing    the yaw each of plan.json's landmarks looks (SandboxMap's: 0 north, 90 west, 180 south, 270 east): the
--             chapel and the green to Hlavní, the pond to Pražská, the drugstore to Depot Row, the D5 to the village,
--             Sýkorka to its car park; Barrier: the barrier stands on plan.json's road Road, Inset studs in from its
--             west end, Deep deep, looking (Yaw) east
--   Trees     per kind: Height { min, max } studs, Wide and Tall (the crown's width and height × the tree's height),
--             Trunk (its thickness × the height)
--   Lines     studs between two trees of a Windbreak (Mix: its kinds, in turn at random) and of an Alley (fruit
--             trees); Orchard { across x, across z } between two rows, Edge studs in from its rect
--   Fields    a field's crop rows: one every Rows studs across it, at most MaxRows
--   Far       the far view: Reach (studs the far fields reach out of the Bounds)
export type VillageTree = { Height: { number }, Wide: number, Tall: number, Trunk: number }
export type VillageTreeLook = { Trunk: { number }, Crowns: { { number } } }
Config.Village = {
	Palette = {
		Render = { { 238, 226, 198 }, { 222, 186, 116 }, { 204, 204, 198 }, { 240, 224, 156 }, { 236, 208, 176 } } :: { { number } },
		Modern = { { 242, 242, 238 }, { 206, 208, 208 } } :: { { number } },
		Tiles = { { 172, 74, 52 }, { 150, 62, 46 }, { 122, 78, 58 }, { 98, 66, 52 } } :: { { number } },
		Plinth = { 128, 126, 120 } :: { number },
		Frames = { { 244, 242, 236 }, { 110, 76, 52 } } :: { { number } },
		Glass = { 62, 80, 94 } :: { number },
		Doors = { { 104, 70, 44 }, { 58, 84, 62 }, { 112, 44, 38 }, { 72, 60, 52 } } :: { { number } },
		Fences = { { 134, 98, 66 }, { 82, 110, 78 }, { 112, 112, 108 } } :: { { number } },
		Gate = { 92, 66, 46 } :: { number },
		Brick = { 152, 80, 60 } :: { number },
		Concrete = { 170, 168, 162 } :: { number },
		Trim = { 248, 246, 240 } :: { number },
		Anthracite = { 58, 62, 66 } :: { number },
		Larch = { 172, 124, 80 } :: { number },
		FlatRoof = { 96, 98, 100 } :: { number },
		Mailbox = { 46, 84, 58 } :: { number },
		Chapel = { { 246, 244, 236 }, { 236, 204, 112 } } :: { { number } },
		Spire = { { 96, 140, 120 }, { 70, 74, 80 } } :: { { number } },
		Slate = { 80, 84, 90 } :: { number },
		Stone = { 152, 150, 144 } :: { number },
		Iron = { 52, 54, 58 } :: { number },
		Gold = { 212, 172, 74 } :: { number },
		DarkWood = { 74, 52, 38 } :: { number },
		Bench = { 142, 102, 64 } :: { number },
		Notice = { 52, 82, 64 } :: { number },
		Hedge = { 62, 94, 48 } :: { number },
		Gravel = { 188, 178, 156 } :: { number },
		Water = { 62, 100, 106 } :: { number },
		Bank = { 106, 130, 66 } :: { number },
		Reeds = { 92, 116, 54 } :: { number },
		Shop = { Wall = { 236, 238, 236 }, Sign = { 30, 130, 122 }, Canopy = { 30, 130, 122 }, Glass = { 92, 124, 138 }, Door = { 70, 100, 112 } } :: { [string]: { number } },
		Asphalt = { 58, 58, 62 } :: { number },
		Line = { 236, 236, 228 } :: { number },
		Grass = { 110, 136, 64 } :: { number },
		NoiseWall = { { 112, 126, 116 }, { 98, 112, 104 } } :: { { number } },
		Rail = { 176, 178, 176 } :: { number },
		Barrier = { Red = { 200, 44, 40 }, White = { 244, 244, 240 }, Lamp = { 255, 150, 30 }, Post = { 210, 210, 206 } } :: { [string]: { number } },
		Hardware = { Hall = { 184, 188, 192 }, Roof = { 142, 146, 150 }, Sign = { 36, 82, 160 }, Door = { 120, 124, 128 }, Mesh = { 96, 110, 100 }, Bricks = { 168, 78, 56 }, Blocks = { 176, 174, 168 }, Tiles = { 160, 70, 50 }, Bags = { 222, 218, 206 }, Timber = { 206, 172, 120 }, Pallet = { 170, 136, 92 }, Sand = { 214, 190, 140 }, Gravel = { 150, 146, 140 } } :: { [string]: { number } },
		Crops = { rapeseed = { 226, 198, 46 }, wheat = { 212, 180, 98 }, ploughed = { 116, 88, 62 }, young = { 124, 156, 70 } } :: { [string]: { number } },
		Rows = { rapeseed = { 196, 176, 40 }, wheat = { 188, 156, 82 }, ploughed = { 92, 68, 48 }, young = { 104, 136, 58 } } :: { [string]: { number } },
		Trees = {
			linden = { Trunk = { 92, 80, 68 }, Crowns = { { 78, 116, 50 }, { 88, 124, 54 }, { 70, 106, 46 } } },
			oak = { Trunk = { 96, 78, 60 }, Crowns = { { 64, 98, 44 }, { 72, 104, 46 }, { 58, 90, 42 } } },
			birch = { Trunk = { 228, 224, 214 }, Crowns = { { 118, 158, 70 }, { 128, 166, 76 } } },
			poplar = { Trunk = { 110, 104, 92 }, Crowns = { { 84, 118, 56 }, { 94, 128, 60 } } },
			willow = { Trunk = { 104, 92, 76 }, Crowns = { { 132, 150, 92 }, { 120, 142, 84 } } },
			fruit = { Trunk = { 104, 80, 60 }, Crowns = { { 98, 138, 58 }, { 108, 146, 62 }, { 90, 128, 54 } } },
		} :: { [string]: VillageTreeLook },
		Far = { Meadow = { 104, 132, 62 }, Trees = { 60, 88, 46 }, Pylon = { 150, 152, 150 }, Wire = { 60, 62, 64 }, Wall = { 226, 220, 204 }, Roof = { 160, 72, 52 } } :: { [string]: { number } },
	},
	Budget = {
		old = 15,
		row = 15,
		modern = 15,
		Rich = 25,
		cabin = 32, -- 9.5 the countryside's spots (Countryside below: always as rich as they get, rich or not)
		lodge = 32,
		mill = 34,
		cottage = 28,
		tree = 2,
		chapel = 26,
		green = 40,
		pond = 26,
		shop = 20,
		motorway = 16,
		barrier = 14,
		hardware = 32,
		field = 11,
		Horizon = 140,
		Step1 = 1900,
		Kept = 600,
	} :: { [string]: number },
	Chunk = 128,
	Front = 1.5,
	RowUnit = 18,
	-- 9.5 the countryside's spots (VillageLooks.house's "cabin", "lodge", "mill" and "cottage": the Pond Cabin, the
	-- Forest Lodge, the Old Mill, the Orchard Cottage): Porch, the studs the cabin's veranda may reach past its box's
	-- front edge (into its front yard: everything else of a look is inside its box); Wheel, the studs the mill's water
	-- wheel and its chute reach past its box's right-hand side at most (seen from outside facing the front door: its
	-- stream runs there); their colours (Stain: the cabin's dark stained boards, Tar its roof; Logs, Shingles, Shutters,
	-- Bone: the lodge's; Stone, Boards: the mill's and the lodge's plinth; Whitewash, Band, Thatch, Terracotta, Doors,
	-- Flowers: the cottage's; Buoy and Lantern: the cabin's lifebuoy and its lantern by the door)
	Countryside = {
		Porch = 2.5,
		Wheel = 6,
		Stain = { { 84, 62, 46 }, { 72, 56, 44 }, { 96, 70, 50 } } :: { { number } },
		Tar = { { 58, 62, 60 }, { 70, 66, 62 }, { 56, 72, 62 } } :: { { number } },
		Logs = { { 120, 84, 54 }, { 108, 76, 50 }, { 134, 96, 62 } } :: { { number } },
		Shingles = { { 92, 74, 60 }, { 78, 66, 58 }, { 104, 82, 62 } } :: { { number } },
		Shutters = { { 58, 104, 70 }, { 46, 90, 62 } } :: { { number } },
		Bone = { 232, 220, 192 } :: { number },
		Stone = { { 170, 164, 150 }, { 156, 150, 138 }, { 178, 170, 154 } } :: { { number } },
		Boards = { 116, 86, 58 } :: { number },
		Whitewash = { { 244, 242, 234 }, { 238, 236, 226 } } :: { { number } },
		Band = { { 96, 112, 128 }, { 120, 104, 90 } } :: { { number } },
		Thatch = { { 182, 156, 98 }, { 168, 142, 88 } } :: { { number } },
		Terracotta = { { 176, 92, 60 }, { 164, 84, 56 } } :: { { number } },
		Doors = { { 74, 110, 150 }, { 70, 120, 84 }, { 150, 66, 52 } } :: { { number } },
		Flowers = { { 214, 54, 60 }, { 232, 120, 160 }, { 236, 178, 60 } } :: { { number } },
		Buoy = { 214, 50, 40 } :: { number },
		Lantern = { 255, 214, 150 } :: { number },
	},
	Facing = { chapel = 180, green = 180, pond = 90, shop = 0, motorway = 90, hardware = 180 } :: { [string]: number },
	Barrier = { Road = "Hornická", Inset = 8, Deep = 6, Yaw = 270 },
	Trees = {
		linden = { Height = { 28, 36 }, Wide = 0.62, Tall = 0.66, Trunk = 0.05 },
		oak = { Height = { 26, 34 }, Wide = 0.74, Tall = 0.6, Trunk = 0.06 },
		birch = { Height = { 26, 34 }, Wide = 0.36, Tall = 0.64, Trunk = 0.035 },
		poplar = { Height = { 38, 48 }, Wide = 0.22, Tall = 0.8, Trunk = 0.035 },
		willow = { Height = { 20, 26 }, Wide = 0.88, Tall = 0.66, Trunk = 0.07 },
		fruit = { Height = { 12, 16 }, Wide = 0.8, Tall = 0.64, Trunk = 0.07 },
	} :: { [string]: VillageTree },
	Lines = { Windbreak = 36, Alley = 26, Mix = { "linden", "oak", "linden", "birch", "poplar" } :: { string }, Orchard = { 36, 32 } :: { number }, Edge = 12 },
	Fields = { Rows = 16, MaxRows = 10 },
	Far = { Reach = 1200 },
}

-- 8.9 SANDBOX on the map; 9.4 the countryside (design/countryside/plan.py, plan.json): shared/VillageScenery.luau lays
-- shared/SandboxMap.luau's map (its six spots' houses, landmarks, fields, lawns, tree lines, woods, orchard and stream)
-- out with shared/VillageLooks.luau's and shared/CountryLooks.luau's art, server/VillageWorld.luau makes the parts
-- (tests/villageworld_test.luau), the D5's cars are client/VillageTraffic.luau's (this screen's only).
--   Lawns      a ground tile's colour and material by its kind (SandboxMap.Lawns: the forest's floor, a darker green
--              than the meadow)
--   Trees      a tree of a tree line, the orchard or a wood stands where the map's rules let it (SandboxScenery.treeRule:
--              off the roads and their 12 studs, the plots, the lots, the vans' ways; VillageScenery.treeRule: Keep studs
--              off a spot's box, a landmark's rect or the Auction House's site, its crown off a stream's water and out of a
--              wood's clearing); where they say no it moves off its spot, Step studs at a time across its line (then
--              along it), at most Nudge studs, else it is left out. Two crowns stay Apart × their radii apart
--   Shadow     a part throws a shadow only when it is a mass (solid, not a door nor a trunk: the walls, roofs, gables,
--              chimneys, the landmarks' bodies) or a tree's crown (the tree's shadow), Low studs tall at least (a
--              plinth's, a bench's shadow is hardly seen), and big enough for SandboxScenery.Shadow and RenderBudget's rule
--   Cars      the D5's cars (client/VillageTraffic.luau): Count in all, Speed studs/s (each its own share of Spread
--              more or less), Beyond studs past the Bounds they run on the far D5 (VillageLooks.horizon's) before they
--              go round again unseen; a car is a body (Size: width, height, length) and a cabin on it (Cabin, its
--              share of the length, a little narrower), in one of Colors; Lanes: the share of a carriageway's width
--              out from its middle each of its two lanes runs
export type VillageCars = { Count: number, Speed: number, Spread: number, Beyond: number, Size: { number }, Cabin: { number }, Lanes: number, Colors: { { number } } }
Config.VillageWorld = {
	Lawns = { forest = { Color = { 72, 104, 52 } :: { number }, Material = "LeafyGrass" } } :: { [string]: { Color: { number }, Material: string } },
	Trees = { Step = 4, Nudge = 12, Keep = 3, Apart = 0.85 },
	Shadow = { Low = 2 },
	Cars = {
		Count = 12,
		Speed = 76,
		Spread = 0.15,
		Beyond = 800,
		Size = { 6.4, 3.4, 14 },
		Cabin = { 0.55, 2.4 },
		Lanes = 0.25,
		Colors = { { 196, 32, 38 }, { 236, 236, 232 }, { 34, 38, 44 }, { 46, 84, 150 }, { 150, 154, 158 }, { 92, 120, 76 }, { 226, 176, 52 } },
	} :: VillageCars,
}

-- 9.4 SANDBOX, the countryside's art kit (shared/CountryLooks.luau, tests/countrylooks_test.luau): the six spots'
-- surroundings (the farm's barn, tractor, bales, paddock and muck heap; the fish pond; the lone house's garden; the
-- lodge's woodpile; the millrace's weir and footbridge; the orchard's beehives), the railway and its halt, the
-- hedges, fences and the stream. Nothing of a village (no street, no shop, no chapel); the houses themselves are
-- shared/VillageLooks.luau's.
--   Palette    the colours (RGB 0-255)
--   Budget     the most parts a landmark of each kind may give
--   Woods      a wood's trees (SandboxMap.Woods): on a grid Spacing apart, each moved up to Jitter studs, its kind
--              Mix's in turn at random (VillageLooks' trees)
--   Lines      a fence's posts at most Post studs apart, its rails at Rails' heights; a hedge Height high, Width wide
--   Streams    a stream's water Water over the ground (its top), its bed Bank wider each side, BankTop high; a tree's
--              crown keeps Clear studs off its water (VillageScenery.treeRule)
--   Far        the railway going on Rails studs past the Bounds at both ends (the far view)
Config.Country = {
	Palette = {
		Barn = { Wall = { 116, 60, 44 }, Trim = { 72, 42, 30 }, Roof = { 86, 84, 88 }, Door = { 88, 54, 36 }, Loft = { 58, 36, 26 } } :: { [string]: { number } },
		Tractor = { Body = { 186, 38, 32 }, Dark = { 52, 52, 56 }, Tyre = { 32, 32, 34 }, Hub = { 214, 176, 52 }, Glass = { 150, 180, 190 } } :: { [string]: { number } },
		Trailer = { Bed = { 120, 92, 64 }, Side = { 96, 112, 72 } } :: { [string]: { number } },
		Hay = { { 218, 190, 112 }, { 204, 176, 98 } } :: { { number } },
		Muck = { 78, 60, 44 } :: { number },
		Log = { 132, 96, 62 } :: { number },
		LogEnd = { 198, 162, 114 } :: { number },
		Stump = { 112, 84, 58 } :: { number },
		Steel = { 150, 154, 160 } :: { number },
		Fence = { 152, 118, 82 } :: { number },
		Post = { 104, 78, 54 } :: { number },
		Trough = { 120, 124, 128 } :: { number },
		Water = { 62, 104, 112 } :: { number },
		Bank = { 98, 118, 60 } :: { number },
		Bed = { 92, 84, 64 } :: { number },
		Reeds = { { 96, 120, 56 }, { 122, 136, 64 } } :: { { number } },
		Jetty = { 146, 110, 72 } :: { number },
		Boat = { 176, 72, 52 } :: { number },
		BoatInside = { 150, 118, 80 } :: { number },
		Bench = { 142, 102, 64 } :: { number },
		Iron = { 52, 54, 58 } :: { number },
		Stone = { 150, 148, 142 } :: { number },
		Foam = { 226, 236, 238 } :: { number },
		Ballast = { 128, 120, 108 } :: { number },
		Sleepers = { 88, 70, 56 } :: { number },
		Rail = { 150, 150, 152 } :: { number },
		Concrete = { 170, 168, 162 } :: { number },
		Opening = { 28, 28, 30 } :: { number },
		Platform = { 176, 174, 168 } :: { number },
		Edge = { 236, 236, 228 } :: { number },
		Shelter = { 168, 92, 70 } :: { number },
		ShelterRoof = { 62, 66, 72 } :: { number },
		Sign = { 34, 76, 150 } :: { number },
		Hives = { { 236, 196, 60 }, { 88, 140, 200 }, { 120, 168, 90 }, { 240, 236, 226 }, { 184, 96, 64 } } :: { { number } },
		HiveRoof = { 96, 96, 100 } :: { number },
		Hedge = { 58, 96, 46 } :: { number },
		Soil = { 104, 80, 58 } :: { number },
		Veg = { 92, 150, 62 } :: { number },
		Washing = { { 236, 236, 240 }, { 200, 60, 60 }, { 80, 120, 190 } } :: { { number } },
		Line = { 220, 220, 220 } :: { number },
	},
	Budget = {
		barn = 12,
		tractor = 20,
		bales = 12,
		paddock = 40,
		muckheap = 12,
		fishpond = 34,
		garden = 30,
		woodyard = 14,
		weir = 6,
		footbridge = 10,
		apiary = 16,
		railway = 10,
		halt = 14,
	} :: { [string]: number },
	Woods = { Spacing = 26, Jitter = 5, Mix = { "oak", "linden", "oak", "birch", "linden" } :: { string } },
	Lines = { Post = 24, Rails = { 1.5, 2.9 } :: { number }, Hedge = { Height = 3.4, Width = 2.6 } },
	Streams = { Water = 0.22, Bank = 1.5, BankTop = 0.12, Clear = 2 },
	Far = { Rails = 900 },
}

-- 8.3 SANDBOX, Roblox badges for the sandbox's milestones (the owner's guide: design/sandbox/BADGES.md).
-- server/SandboxBadges.luau only listens (the moves, the collection, the upgrades, the save, the TOP MOVERS board) and
-- awards a badge on the server when its milestone is reached; shared/SandboxBadgeRules.luau has the rules
-- (tests/sandboxbadges_test.luau, tests/sandboxbadges_runtime_test.luau). A badge is off until the owner makes it on
-- create.roblox.com and pastes its id here: an id of 0 is never awarded, and nothing errors.
--   Badges      key → { id, name, description }: id the Roblox badge's id (0: not set up yet); name and description
--               are what the owner types into Roblox's form (the admin panel's SANDBOX tab lists them)
--   Studio      true: awarded in Studio too (a test with real ids); false: nothing is awarded in Studio
--   Moves       the finished moves tenMoves wants (a move finished: done or late with pieces home, the crew's too)
--   Level       the warehouse level warehouse5 wants (Config.Warehouse.Levels: 5 the Logistics Center)
--   TopPlayers  the players topMover wants on the server (their saves loaded: a full server, Config.Sandbox.MaxPlayers)
--   TopEvery    s between two looks at the TOP MOVERS board (SandboxLeaders.rows)
--   Tries, Wait an award that errors is tried again Wait s later, Tries times in all
--   Flag        the save's mark: profile.sandboxMoves (the moves finished) is read only from a real save written with it
export type SandboxBadgeDef = { id: number, name: string, description: string }
Config.SandboxBadges = {
	Badges = {
		firstMove = { id = 0, name = "First Move", description = "Finish your first move." },
		tenMoves = { id = 0, name = "Seasoned Mover", description = "Finish 10 moves." },
		cleanMove = { id = 0, name = "Handle With Care", description = "Finish a move with nothing broken." },
		firstShow = { id = 0, name = "On Display", description = "Put a piece on a display stand in your warehouse." },
		firstSale = { id = 0, name = "First Sale", description = "Sell a piece from your collection." },
		hotSale = { id = 0, name = "Hot Seller", description = "Sell one of today's hot items." },
		legendary = { id = 0, name = "Legendary Find", description = "Bring home a legendary piece." },
		fullBook = { id = 0, name = "Completionist", description = "Find every piece in the collection book." },
		firstUpgrade = { id = 0, name = "Upgraded", description = "Buy your first upgrade." },
		warehouse5 = { id = 0, name = "Logistics Tycoon", description = "Grow your warehouse to level 5." },
		painted = { id = 0, name = "Fresh Paint", description = "Paint your van at the PAINT shop." },
		topMover = { id = 0, name = "Top Mover", description = "Top the TOP MOVERS board on a full server." },
		firstDeal = { id = 0, name = "First Deal", description = "Sell a piece to another player, or buy one from them." }, -- 8.7: trading
	} :: { [string]: SandboxBadgeDef },
	Studio = false,
	Moves = 10,
	Level = 5,
	TopPlayers = Config.Sandbox.MaxPlayers,
	TopEvery = 5,
	Tries = 3,
	Wait = 2,
	Flag = "sandboxMovesKept",
}

-- 8.3 SAVES (server/PlayerData.luau, shared/SaveGuard.luau; tests/saving_runtime_test.luau): how the save pipeline
-- writes, tries again and waits. Config.AutosaveSeconds, SaveLockWait and SaveLockStale (at the top) still hold.
--   Soon       s from a purchase (PlayerData.spend), a book milestone or pieces brought home to their save
--              (PlayerData.saveSoon: one save for a burst)
--   Gap        s at least from one player's write to their next one that can wait (a Soon save waits for it, the
--              autosave skips a player written this recently; a DataStore key takes one write in 6 s)
--   Tries      tries of a save that can wait (the autosave, a Soon save); FinalTries: of the last one (leaving, the
--              shutdown); LoadTries: of the load (then a live player is kicked: never played on a fresh profile)
--   Backoff    s before the next try: First × 2^(try − 1), at most Most
--   Reserve    UpdateAsync requests of the server's budget (DataStoreService:GetRequestBudgetForRequestType) kept for
--              the loads and the last saves: a save that can wait waits for the next round while the budget is under it
--   LeaveWait  a join waits for this server's own leave save of the same player (a rejoin within seconds) as long as
--              that save runs (8.4 review: in an outage it outlasts a fixed wait, and a join that stops waiting reads the
--              save from before it): at most the leave save's worst case (FinalTries tries, the Backoff between them, each
--              UpdateAsync up to Call s) and LeaveWait s more (a store that never answers)
--   Call       s one UpdateAsync may take in an outage (only that worst case counts it)
--   CloseWait  s the shutdown (game:BindToClose) waits for every save in flight (Roblox gives 30)
--   WarnBytes  a save this big (its JSON, SaveGuard's estimate) warns in the output; MaxBytes: a DataStore key's 4 MB
--              less a margin (the unknown keys kept from the loaded save are left out past it)
Config.Saving = {
	Soon = 3,
	Gap = 7,
	Tries = 3,
	FinalTries = 5,
	LoadTries = 4,
	Backoff = { First = 1, Most = 4 },
	Reserve = 8,
	LeaveWait = 10, -- (8.4 review: + the leave save's worst case, 1 + 2 + 4 + 4 + 5 × Call = 41 s: 51 s at most)
	Call = 6,
	CloseWait = 25,
	WarnBytes = 1_000_000,
	MaxBytes = 4_000_000,
}

-- 9.1, the drive pedals (the owner: "Add a drive pedal to the game … just visible pedals on PC, and on mobile as driving
-- buttons"): GAS (tall and narrow) and BRAKE (wider and shorter) at the lower right while you drive your car
-- (client/DrivePedals.luau, the pure rules shared/PedalRules.luau, the input client/Drive.luau setPedal). On a touch
-- screen they are held to drive (GAS forward; BRAKE brakes, then backs up, as S does; the thumbstick steers); with a
-- keyboard or a gamepad they show your feet (W / S, R2 / L2 part way) and a mouse may hold them too.
--   On             off: no pedals anywhere (the seat, the keys and the thumbstick drive as before)
--   Gas / Brake    { w, h } px at scale 1 (rubber Ribs across each: how many)
--   Gap            px between the two at scale 1; Clear: px they keep from everything else (screen px)
--   Margin         screen px from the screen's edges: Touch at the bottom right of a touch screen, Desk on a computer
--   Touch          a touch screen's scale: the HUD's (Ui.scaleFor) between Min and Max, then Shrink smaller at a time when
--                  no place is clear, while every side stays MinSide px (a finger's: Ui.MinTouch) or more
--   Desk           a computer's: the HUD's scale × Scale (compact), Shrink smaller at a time down to Min
--   TopShare       their top stays under this share of the screen's height (the lower part); ShrinkCost: px of way from
--                  their spot a smaller scale counts as, for each share of the biggest it loses; Weight: in the last
--                  resort (no clear place) covering the touch controls counts this many times a HUD group's px
--   Caption        px at scale 1 under them for a gamepad's R2 / L2 (the platform's picture, else the word)
--   Press          the press drawn (shared/PedalRules.luau look / ease): Depth px down at scale 1 (also the shadow's lip
--                  under the face at rest, which the press closes) and Squash the face's share shorter (it tips away),
--                  Shade the dark veil over it, Accent the red edge's px (resting, pressed), In / Out how fast it goes
--                  down and comes back (a share a second: quick, no bounce)
--   Face           the face's transparency: Rest, Pressed (more solid)
--   Rolling        studs/s: both held, the brake works while the car still rolls faster than this, then it stands
--   Check / Place  s between the looks at the seat, the HUD and the device / at where they go (the HUD's groups move)
Config.DrivePedals = {
	On = true,
	Gas = { 64, 120 },
	Brake = { 92, 88 },
	Ribs = { Gas = 6, Brake = 4 },
	Gap = 12,
	Clear = 8,
	Margin = { Touch = 10, Desk = 16 },
	Touch = { Min = 0.78, Max = 0.92, Shrink = 0.04, MinSide = 44 },
	Desk = { Scale = 0.62, Min = 0.4, Shrink = 0.06 },
	TopShare = 0.3,
	ShrinkCost = 600,
	Weight = 4,
	Caption = 18,
	Press = { Depth = 7, Squash = 0.1, Shade = 0.35, Accent = { 2, 5 }, In = 26, Out = 16 },
	Face = { Rest = 0.35, Pressed = 0.12 },
	Rolling = 1.5,
	Check = 0.1,
	Place = 0.5,
}

return Config
