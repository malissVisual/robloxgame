--!strict
-- Delivery jobs. The job board offers ordinary deliveries of every danger level (★ … ★★★★; 4.7: three each) measured from
-- where the player is, and sometimes a special job without an employer (the Winter Run). The employers (Config.Employers)
-- give their own special job at their board and lend their vehicle.
--
-- A job is a list of stops. At every stop you drive into the circle, then handle the cargo (server/Cargo.luau):
-- get out, carry the pieces from the giver to the back of the vehicle (or lead the horses, or wait while the kids
-- walk in), and at the drop take them out and carry them to the receiver. An ordinary delivery is something a
-- business would really send (Config.Jobs.Businesses: the pharmacy's medicine boxes to the doctor, the bakery's
-- bread sacks to the camp cook ...), 1 – 3 pieces. Every piece handled on foot adds time to the clock.
--
-- The enemies keep coming: zombie WAVES (Config tiers wave*: bigger and more often the higher the danger, the first
-- one Config.Jobs.FirstWave s after you accept) and, from ★★ up, bandit roadblocks and bandit cars on the road; at
-- the stops a few come at you on foot (Config.Cargo.FootWaves), bandits among them. The waves wait while you are in
-- the safe zone or handle the cargo on foot. Bandits only ever go after players on a job (Zombies.hunts); without a
-- job only the roaming zombies are around (server/Zombies.luau). Bandits at the car steal pieces, a wreck ruins some
-- (the rest moves to the next car). The pay scales with the pieces delivered and their condition.
--
-- Crew: friends who ride in the owner's car, and the players the owner invited into the job (server/Crew.luau
-- Crew.members), help (their kills count, they may carry the cargo) and get paid too: every crew member gets half of
-- the payout and the owner +15 % per member (Economy.crewSplit), Config.Crew.MaxMembers paid at most (the invited
-- first). A rider stays on the job while they stay with it (pruneRiders: in the car or within Config.Crew.RiderRange).
-- Each gets their own DeliveryResult with the whole split. Since 3.0 the crew stays together after the job (friends
-- play mission after mission; server/Crew.luau breaks it up when they leave, are kicked or quit). Jobs.crewStatus
-- tells the members what the owner does.
--
-- 2.5: special jobs on the board (JobTypeDef.board: the Cash Transport, the Pizza Rush; the Winter Run) next to the
-- employers' ones (the City Clinic's Ambulance Run). A rush has a fixed clock (timeLimit); bandits want some cargo
-- more (banditBoost: roadblocks and chases that many times as often). At night (DayNight.nightFactor) the waves are
-- bigger and the pay higher (Config.DayNight). Driver levels (shared/Levels.luau): every finished or failed job gives
-- XP to the owner and the crew; danger levels and jobs above your level show on the board LOCKED, the server refuses
-- them.
--
-- 3.0, the missions (shared/Missions.luau, server/Missions.luau checks and calls Jobs.startMission): a mission is a
-- special job with the giver's and receiver's looks of its own, no random modifier, the pay × its twists
-- (Missions.twistPay) and the twists (Config.Missions):
--   defend    at the last drop nothing is unloaded (Cargo.setBlocked) until somebody of the job held the area on foot
--             within DefendRadius of the receiver for defendTime s (leaving pauses it); waves come around the stop
--   lift      heavy pieces: carried alone you walk slowly (server/Cargo.luau, Info.lift)
--   quiet     every shot of the job's people costs QuietCost condition (server/Gun.luau Gun.onShot → Jobs.onShot)
--   guarded   a horde waits at every stop, not only at the last one
--   night     it starts only at night (Jobs.startMission)
--   gunner    kills from the passenger seats of the owner's car count GunnerKillBonus times in the kill bonus
--   spotless  below SpotlessFail condition the mission fails at once
--   hunted    the bandits come HuntedBoost times as often (a ★ mission gets the ★★ bandits)
-- A co-op mission pays × Economy.coopPay and its enemies are × Economy.coopEnemies of the crew (riders and members
-- besides the owner, crewOf: MaxMembers at most), recounted when the crew changes. Done: the rating (Missions.rate)
-- goes into the result and to Jobs.onMissionComplete (server/Missions.luau pays the rewards and saves the stars) with
-- the crew who are there at the finish.
--
-- 3.1, the challenges (server/Challenges.luau): Jobs.onStat (wired in Main) hears the waves that came, a HOLD OUT won,
-- the pieces delivered (and the people boarded, the horses) for the owner and the crew with them, and at a mission's
-- finish co-op, night, 3 stars, a rush and a NO SHOOTING mission without a shot for who was there.
--
-- 3.2, the DUO missions (MissionDef.duo, Config.Missions.Duo; server/Missions.luau checks the crew at START): the
-- mission fails ("Your partner left.") when the invited crew drops below MinCrew after it had them. Their twists:
--   pair      heavy pieces only move with two (server/Cargo.luau, Info.pair: no job mate within PairRange, no pick-up)
--   switches  the gated stop (the last drop, or every pick-up with MissionDef.gates = "pickup") gets two levers
--             (server/DuoGates.luau) and stays blocked (Cargo.setBlocked) until two different players of the job
--             pulled them together; with defend at the same drop both must be done (blockStop).
--
-- 3.4, cargo capacity: a job's pieces carried or led by hand (Economy.cargoNeed) must fit the vehicle that does it:
-- the company vehicle a special job lends, else your equipped car at its stage (3.5, Economy.capacity). The board
-- shows a job too big for your car locked ("NEEDS N SLOTS · your Old Van holds 2") and accepting it is refused
-- (slotsShort). The ordinary deliveries of the dangerous levels are sometimes bulk orders (Config.Jobs.BulkChance /
-- BulkExtra): more pieces, more pay, a bigger car. 3.5: a ★ delivery carries at most Config.Jobs.EasyMaxPieces (the
-- Rusty Van's 2 slots).
--
-- 3.7, the board on a timer: a player's offers stay put (boards, by UserId: leaving and coming back does not reroll
-- them) and are made again only every Config.Jobs.RefreshSeconds. Opening the board (RequestOffers) sends the current
-- ones and when the next ones come (refreshAt); when that time comes the server makes new ones and pushes them
-- (refreshBoards, never during a job). There is no other way to new offers: an accepted offer just leaves the board,
-- and cancelling it does not bring a new board. The board is sorted ★ → ★★★★ (boardOrder: the specials at their
-- stars, the locked ones too); AcceptJob sends the offer's id (Offer.id), so a new board or a taken offer never makes
-- it take another one. An offer keeps its pay while you move about; its clock grows by the longer drive when you take
-- it from farther away (fromHere). Jobs.startTutorialJob gives a new player an easy first delivery the same way
-- (takeOffer), and Jobs.onDelivered tells server/Tutorial.luau how a job ended.
--
-- 4.7, real jobs (shared/JobRules.luau, Config.Jobs Choice / Rating / Licences):
--   * A choice: every danger level the driver may take offers three ordinary deliveries, each a trade-off (Offer.role,
--     JobRules.roles: SHORT & SAFE always, then two of LONG HAUL, RISKY, BULK ORDER; ordinaryOffer). A tier the driver
--     may not take yet shows one, locked. REROLL (Net "RerollTier", reroll): that tier's ordinary offers made again for
--     Choice.RerollFee × its stars, once per tier until the board refreshes (Board.rerolled).
--   * Every ordinary and special job (never a mission: it has its own rating) is rated ★ … ★★★ when it is done
--     (JobRules.rate: the clock left, the cargo's condition, a wreck on the way (Job.wrecked), pieces lost); the pay
--     and the XP follow (JobRules.ratedPay / ratedXp) with the owner's streak of good jobs (profile.streak, reset by
--     a ★ or a failed job). The result says why (DeliveryResult rating).
--   * Licences: the board's ★★★ and ★★★★ ordinary deliveries (and the Winter Run, a board special without a level of
--     its own) need the tier's licence (licenceTier, hasLicence): its level AND enough good jobs at the tier below
--     (profile.licenceJobs, counted for the owner of a rated job). The locked tier says "LICENCE 3 / 5".
--
-- 4.8, cargo with rules, multi-drop and road events (shared/JobRules.luau, Config.Jobs CargoRules / MultiDrop /
-- RoadEvents):
--   * Offer.rules (applyRules, from the cargo's look, kind and business; never a mission or the tutorial's delivery):
--     fragile (hard braking, bumps and hits at speed cost condition, "CAREFUL — FRAGILE"), food (Job.freshness drains
--     once picked up, a Cooler Box slows it; the contract shows "Fresh 82%", the rating and the pay take it), heavy
--     (Cargo.Info.heavy: by hand alone very slow, the trolley or a crew mate at the normal pace), cash (the bandits
--     come more: banditBoost ≥ CashBoost), people (bumps make them complain). Ratchet Straps (gear) × StrapsLoss on
--     every condition loss from driving (cargoRulesStep, Jobs.onCarDamaged).
--   * Multi-drop (ordinaryOffer): a ★★★ / ★★★★ board delivery may go to 2 – 3 customers one after the other; every
--     piece is labelled for its customer (Offer.dests / destNames → Cargo.Info), Take out picks theirs, the wrong one
--     is refused; the extra drops pay MultiDrop.PayPerStop each.
--   * Road events (eventsStep, at most one a job, never the tutorial's or a mission): a survivor waving by the road
--     (stop next to them, they ride along until the depot's safe zone: lifts, paid even after the job), a side
--     pick-up offered on the HUD (Net "RoadEvent", Y: one more piece before the drop, takeAddOn), a blocked street
--     ahead (a roadblock).
--
-- 5.0, from the bottom (Config.Jobs.Foot, shared/Transport.luau, server/Transport.luau): every offer has a `mode`.
--   * "foot": the board's ON FOOT section (footOffer, Foot.Offers of them through JobRules.roles), always open, on
--     top of the board: light pieces only, never more than you carry (hands + bag), a short walk Downtown or in
--     the Suburbs, its own pay and clock (JobRules.footPay / footTime). startJob needs no vehicle (Cargo's foot flow:
--     Info.foot, the pack); no waves, bandits or road events, now and then a stray walker (strayStep); a thermal
--     bag slows the food's drain (6.7: the jacket is gone). The tutorial's first delivery is one (Jobs.startTutorialJob).
--   * "car": every other job. Without a vehicle of your own (profile.car nil) the ones in your own car are locked
--     "NEEDS A VEHICLE" (needsVehicle) and refused; the jobs that lend a company vehicle need their level (4+).
--     5.1: a bike is not a car: riding one (profile.car a bike) they are locked "CALL YOUR CAR" (or NEEDS A VEHICLE).
--   * 5.1, "bike": the board's BIKE section (footOffer with Config.Jobs.Bike, Bike.Offers of them) from Bike.Level:
--     light pieces, a longer ride (Downtown, the Suburbs, the Harbor), never more than your bike holds (Transport.bikeOf:
--     its room + its bike gear + your bag), JobRules.footPay / footTime with the Bike numbers, a ★ job's XP +
--     Bike.XpBonus. Locked without a bike ("NEEDS A BIKE", Spoke & Chain) and while your car is the one you drive
--     ("RIDE YOUR BIKE": the phone's MY BIKE). Cargo's light flow like a foot job (Info.foot), the pack is the bike's
--     whole room (riding stows everything); no waves, bandits or road events, Bike.Stray* walkers. A foot job may be
--     done on a bike too (riding stows the hands: its pack is your whole room then).
--   * 6.6, one carrying item and the bike's own bag: no backpack any more. On foot your room is the hands + your bag;
--     on a bike run (or a foot run while your bike is your vehicle) the bike's own bag (Cargo.Info.rack: its rack,
--     basket or box with its bike gear, Transport.bikeBagOf) + your bag. Every light piece fits every bag, so a
--     bouquet or a cake is offered and stacked like a pizza (5.3's "does not fit a backpack" limits are gone).
--
-- 5.2, several orders at once (Config.Jobs.Orders, shared/JobRules.luau's orders): still one Job a player, now with
-- its orders (Job.orders: Order = its own offer, clock, stops, pieces, state open / done / failed, pay and rating; a
-- job of one order is what every job was before).
--   * Stacking: while a stackable run is on (JobRules.stackable: an ordinary board delivery on foot, on a bike, or ★ /
--     ★★ in a car; never a mission, a special, an employer's job, DUO, the Freight Run or the tutorial's) ACCEPT on the
--     board adds an order of the same mode (addOrder) when the free room takes its pieces (orderRoomOf: hands +
--     bag, the bike + its gear + the bag, the car + its gear; minus what the open orders still hold or pick
--     up) and fewer than Orders.Max[mode] are open. Its stops go at the end of the job's list (Job.offer.stops, so
--     the indices never move); the board shows + ADD ORDER or why not (NO ROOM (3/4 slots), ORDERS FULL (2/2)).
--   * Any order of stops (Job.free: an ordinary delivery; the other jobs go stop after stop as before): the current
--     stop (Job.stop) is the open stop whose circle you are at, else the pinned order's nearest (the phone's ORDERS
--     app: Net "PinOrder"), else the nearest (JobRules.nextOpenStop); a stop half handled stays (Cargo.engaged). A
--     pick-up is open until it is done; a drop once its order picked everything up and its pieces are with you. Every
--     piece knows its order and its drop (Cargo Plan.dests).
--   * Clocks: every order has its own (its offer's, from when it was taken). One that runs out fails alone (its pieces
--     go back, its stops are skipped, the streak resets, a notice); the job ends when no order is open.
--   * Pay: every order is paid and rated when its last drop is done (payOrder: money, XP, the 4.7 rating, the streak,
--     the licences, the crew's shares, its own DeliveryResult; `midJob` while others go on). The waves, the bandits
--     and the road events stay the job's; 4.8's add-on is an order of its own (addOnOrder).
--   * The payload adds `orders` (every order: its stops, clock, pay, pinned), `ordersLine` ("+2 ORDERS"), `stack`
--     (may the board add one now, the room) and `carried` (every piece you carry: order, look, name, where, its
--     customer); its other fields are the focused order's (the one of the current stop).
--
-- 5.3, real places, the bag and the newspaper round (shared/Deliveries.luau, shared/Bag.luau, Config.Jobs Places /
-- Round, the businesses' `to` / `hours` / `peak`). The helpers are required inside the functions (this module's
-- top-level locals are at the -O0 limit).
--   * An ordinary delivery (ordinaryOffer, footOffer) starts at its business's storefront (Map.Venues: the nearest
--     one, within Places.CarReach by car, the light job's PickupMax + PickupWiden on foot / by bike): "PICK UP at
--     Luigi's Pizza, Ash St", the cook / clerk in the doorway (Stop.personAt). It goes to a home's door (B2C: a Suburbs
--     house, a downtown apartment) or another storefront / the Harbor (B2B: their own person takes it), as the
--     business's `to` says; only the businesses open at this hour (the bakery in the morning …) are offered, the
--     evening peak pays more (Offer.peak, the board's chip). The businesses without a storefront (the lab) and
--     without `to` (the bank's gold, the warehouse's fuel to the far places) work as before.
--   * At a home (Stop.door) the receiver is inside: you knock when you come up (server/Cargo.luau), the door opens and
--     they step out; now and then nobody is home (Stop.nobody, Places.NobodyHome): "Leave at the door".
--   * The bag: the payload's `carried` says where each piece is (hands, bag, rack: 6.6 the bike's bag, pack: a round's
--     satchel, vehicle) and where it goes (`place`), the payload's `rack` the bike's bag's room (client/BagUi.luau).
--   * The newspaper round (footOffer "round", in the morning: Config.Jobs.Round): the bundle at The Daily Undead (one
--     E: it goes into the satchel, 6.6: Cargo.Info.satchel), a paper to every door on one or two streets
--     (Deliveries.round: Stop.toss, "Toss newspaper" from Round.TossRange), its own pay and clock (JobRules.roundPay /
--     roundTime), the tip for no paper in the bushes (Cargo.missesOf, JobRules.roundTip) in payOrder. One order on its
--     own (never stacked).
--
-- 5.7, a better whole game:
--   * startJob's second half (after jobs[player] = job) runs in a pcall: a failure ends the job, sends the empty job,
--     tells the player and warns. A job whose tick fails Config.Jobs.TickFails times in a row ends (Jobs.fail).
--   * Foot and bike runs get life (server/RunEvents.luau, Config.Jobs.FootEvents): a runner, a survivor's tip or a
--     locked gate on about one run in four, a few walkers at about one drop in five.
--   * The step up to a car (Config.Jobs.CarStep, JobRules.carStep*): a ★ board delivery in your own car takes 3 – 4
--     pieces (as many as the car holds now: tierOffers' room) and gives +40 XP.
--   * The board refills: every offer taken (Board.taken) gets a new one of its kind after the run, made from where
--     the player is then (Jobs.refillBoard, deferred from endJob).
--   * A DeliveryResult says its `mode`: client/Hud.luau shows a foot or bike run as a toast and a float.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Missions = require(Shared.Missions)
local Net = require(Shared.Net)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)
local BanditCars = require(script.Parent.BanditCars)
local PlayerData = require(script.Parent.PlayerData)
local Cargo = require(script.Parent.Cargo)
local DayNight = require(script.Parent.DayNight)
local Crew = require(script.Parent.Crew)
local Gun = require(script.Parent.Gun)
local DuoGates = require(script.Parent.DuoGates)
local Npcs = require(script.Parent.Npcs)
local Freight = require(Shared.Freight)
local JobRules = require(Shared.JobRules)
local Transport = require(script.Parent.Transport) -- 5.0: what you carry on foot (the kit)

type Stop = {
	address: Map.Address,
	kind: string, -- pickup | drop
	mode: string, -- carry | lead | board | serve
	needed: number, -- pieces handled here
	hold: number, -- serve: seconds to hold still in the circle
	keep: number, -- serve: pieces left in the vehicle afterwards
	label: string,
	park: Vector3, -- the circle
	pile: Vector3, -- where the person and the cargo are
	facing: Vector3,
	person: Config.PersonDef?,
	staging: { Vector3 }?, -- 4.0, pallet: where the pallets wait / are set down (Cargo.Plan.staging)
	dock: string?, -- 4.0, pallet: its Map.FreightDocks hub (pick-up) or Map.ReceivingDocks id (drop): placeDocks
	-- 5.3, real places (shared/Deliveries.luau; newStop fills them from the address's spot, Cargo.Plan the same):
	personAt: Vector3?, -- a storefront's cook / clerk in the doorway
	door: Vector3?, -- a home's door (knock: the receiver opens)
	nobody: boolean?, -- nobody home: leave it at the door (Places.NobodyHome)
	toss: boolean?, -- a newspaper round's door
	bundle: boolean?, -- the round's pick-up: the whole bundle at once
}

type Offer = {
	tier: number,
	stops: { Stop },
	distance: number,
	pay: number,
	time: number,
	cargo: string,
	customer: string,
	jobType: Config.JobTypeDef?,
	modifier: Config.ModifierDef?,
	kind: string, -- the Carrying kind of a piece
	look: string, -- the model of a piece
	piece: string,
	plural: string,
	total: number, -- pieces in the whole job
	level: number, -- the driver level it needs (Economy.jobLevel)
	boost: number, -- bandits want this cargo: roadblocks and chases this many times as often (1 = normal)
	-- 3.0, the missions (empty / nil / false for every other job):
	mission: string?, -- the mission id (shared/Missions.luau)
	twists: { [string]: boolean }, -- the job type's twists (Config.Missions.Twists)
	coop: boolean, -- a co-op mission: pay and enemies grow with the crew
	defendTime: number, -- defend: seconds to hold out at the last drop
	-- 3.2, the DUO missions:
	duo: boolean, -- only with a crew: fails when the partner leaves
	gates: string?, -- switches: "drop" (the last drop) | "pickup" (every pick-up), nil without the twist
	-- 3.7, the board on a timer:
	id: number, -- the board's id of the offer (AcceptJob sends it), 0 off the board
	approach: number, -- the drive (manhattan) to the first stop from where it was offered: `distance` and `time` count it
	role: string?, -- 4.7: the board's trade-off of an ordinary delivery (short | long | risky | bulk), nil otherwise
	-- 4.8:
	rules: { string }, -- the cargo's rules (JobRules.cargoRules: fragile, food, heavy, cash, people); none on a mission or the tutorial's
	dests: { number }?, -- multi-drop: the stop every piece goes to (JobRules.destinations), nil for one drop
	destNames: { [number]: string }?, -- multi-drop: the customer at each of those stops
	tutorial: boolean, -- the tutorial's first delivery (no road events)
	-- 5.0: how it is done: "foot" (the board's ON FOOT section: no vehicle, Config.Jobs.Foot) or "car" (every other job;
	-- a job that lends a company vehicle too). 5.1: "bike" (the board's BIKE section: Config.Jobs.Bike).
	mode: string,
	-- 5.3: a newspaper round (footOffer's "round": the bundle, a paper at every door; never stacked) and the evening
	-- peak's pay multiplier it was offered with (Config.Jobs.Businesses peak; the board's chip)
	round: boolean?,
	peak: number?,
}

-- 5.1: the numbers of a light job: Config.Jobs.Foot or Config.Jobs.Bike (footOffer, strayStep; JobRules.LightRules).
type LightJob = {
	Pieces: { number },
	PickupMin: number,
	PickupMax: number,
	PickupWiden: number,
	MinDistance: number,
	MaxDistance: number,
	Districts: { [string]: boolean },
	BasePay: number,
	PayPerStud: number,
	PayPerPiece: number,
	PayMin: number,
	PayMax: number,
	PayTop: number,
	TimeBase: number,
	Speed: number,
	StrayEvery: number,
	StrayChance: number,
	StrayMax: number,
	StrayDistance: { number },
}

-- 3.7: a player's job board: its offers (sorted, boardOrder) until refreshAt (workspace:GetServerTimeNow()).
-- 4.7: rerolled = the tiers rerolled on this board (once each).
-- 5.7: taken = the offers taken from it since (Jobs.refillBoard puts a new one of each kind in their place after the run).
type Board = { list: { Offer }, refreshAt: number, rerolled: { [number]: boolean }, footNote: string?, taken: { Offer }? }

type Job = {
	offer: Offer,
	endsAt: number, -- workspace:GetServerTimeNow()
	condition: number, -- 0 … 1
	kills: number,
	stop: number, -- index into offer.stops
	guards: boolean, -- the horde at the last stop was spawned
	wave: number, -- zombie waves so far
	waveIn: number, -- seconds of driving until the next one (counts down only while the waves are not paused)
	nextAmbush: number,
	nextChase: number,
	dirty: boolean, -- something changed, send it
	badPayload: boolean?, -- 5.4.1: its payload failed once (warned; a short one goes instead)
	stealNotice: number, -- when "they are stealing" was last said
	stealMeter: number, -- a full one = a piece stolen
	cargo: Cargo.Session,
	crew: { [Player]: boolean }, -- who rode in the owner's car during the job and stays with it (pruneRiders)
	members: { [Player]: boolean }, -- the invited crew at the last tick (who leaves it stops riding along too)
	footSince: number?, -- handling cargo on foot at this stop since
	nextFoot: number,
	footWarned: boolean,
	lastStep: string,
	crewCount: number, -- paid crew members besides the owner (riders and invited), as last counted
	-- 3.0, the missions' twists:
	enemyScale: number, -- co-op: the enemies × this (Economy.coopEnemies of crewCount), 1 otherwise
	gunnerKills: number, -- gunner: kills from the passenger seats of the owner's car
	guarded: { [number]: boolean }, -- guarded: the stops whose horde was spawned
	defendLeft: number?, -- defend: seconds still to hold out (nil = not started)
	defendDone: boolean,
	defendInside: boolean, -- somebody holds the area right now
	defendWho: string, -- the receiver's name (the HUD's hint)
	defendWave: number,
	nextDefendWave: number,
	quietNotice: { [Player]: number }, -- quiet: when the shooter was last warned
	-- 3.1, the challenges' counters (Jobs.onStat):
	shots: number, -- shots of the job's people (counted on a quiet mission: NO SHOOTING finished without one)
	piecesCounted: number, -- the delivered pieces already told to Jobs.onStat
	-- 3.2, the DUO missions:
	owner: Player,
	allowed: (Player) -> boolean, -- who handles the cargo and pulls the levers: the owner and the crew
	duoTeamed: boolean, -- the crew had MinCrew members (from then on fewer fails the mission)
	gateClosed: boolean, -- switches: this stop's gate is still shut (server/DuoGates.luau)
	gatePulled: number, -- switches: levers down right now (the HUD)
	wrecked: boolean, -- 4.7: the car was wrecked on this job (the rating)
	-- 4.8, cargo with rules:
	freshness: number, -- food: 1 … 0 (JobRules.freshDrain once it is picked up)
	lastSpeed: number, -- the car's flat speed at the last tick (the jolts: JobRules.jolt) …
	joltCar: Vehicles.Car?, -- … of this car (a new car after a wreck is no jolt)
	joltAt: number, -- os.clock(): no jolt counts before this (CargoRules.JoltCooldown)
	ruleNotice: number, -- os.clock() of the last CAREFUL notice
	-- 4.8, the road event (JobRules.pickEvent): at most one a job
	event: string?, -- "survivor" | "addon" | "roadblock" still to come or running; nil: none (or over)
	eventAt: number, -- it comes after this many seconds of driving (driven)
	eventTries: number,
	driven: number, -- seconds driven out of the safe zone on this job
	eventState: string?, -- "waving" (a survivor by the road) | "asked" (an add-on waits for Y), nil before
	eventUntil: number, -- os.clock(): the survivor gives up / the add-on is gone
	eventSpot: Vector3?, -- where the survivor waits
	eventNpc: Model?,
	eventName: string,
	addOn: AddOn?,
	nextStray: number, -- 5.0, a foot job: os.clock() of the next chance of a stray walker (Config.Jobs.Foot)
	-- 5.2, several orders at once:
	orders: { Order },
	nextOrder: number,
	free: boolean, -- the stops in any order (an ordinary delivery); false: one after the other, as before
	stopsDone: { [number]: boolean }, -- free: the stops done (or skipped: a failed order's, a drop with nothing left)
	pinned: number?, -- the order the GPS follows (the phone's ORDERS app)
	switchAt: number, -- os.clock(): the current stop may change again after this (Orders.SwitchEvery)
	killsPaid: number, -- the kills already paid with an order
	tickFails: number?, -- 5.7: the server ticks in a row that failed (Config.Jobs.TickFails of them: Jobs.fail)
}

-- 5.2: one order of a job. `offer` is its own (pay, clock, cargo, customer, pieces, rules); the job's offer is the
-- first order's with every order's stops (`stops`: indices into it).
type Order = {
	id: number,
	offer: Offer,
	endsAt: number,
	stops: { number },
	pieces: number,
	state: string, -- "open" | "done" | "failed"
	paid: number, -- what the owner got for it
	rating: number?, -- its stars (4.7), once paid
	freshness: number, -- 4.8: food, 1 … 0 once picked up
	wrecked: boolean, -- 4.7: a wreck while its pieces were in the car (5.2 review: a job of one order: while it was open)
	condition: number, -- 5.2 review: its cargo's own condition, 0 … 1 (hits while its pieces were in the car)
	addOn: boolean, -- 5.2 review: a road event's side pick-up: ★ pay and XP, no rating, no streak, no licence progress
}

-- 4.8: a side pick-up offered by a road event (one more piece from `giver` at `address`, `distance` from you).
type AddOn = { address: Map.Address, pay: number, giver: string, distance: number }

-- What a DeliveryResult says about the XP (shared/Levels.luau), the owner's and every member's own.
type XpInfo = { xp: number, level: number, rank: string, levelUp: boolean }

type CargoSpot = { pile: { x: number, z: number }, park: { x: number, z: number }, facing: { x: number, z: number } }

local Jobs = {}

local boards: { [number]: Board } = {} -- 3.7: by UserId, so leaving and coming back does not reroll the board
local nextOfferId = 0
local jobs: { [Player]: Job } = {}
local rng = Random.new()
-- 4.8: a survivor picked up by the road (a road event) rides along until the depot's safe zone, also after the job.
type Lift = { name: string, bonus: number, untilAt: number }
local lifts: { [Player]: Lift } = {}

local jobRemote = Net.get("Job")
local resultRemote = Net.get("DeliveryResult")
local notice = Net.get("Notice")
local roadEventRemote = Net.get("RoadEvent") -- 4.8: the add-on's card (client/RoadEventUi.luau) and its answer
local JobsConfig = Config.Jobs
local Tuning = Config.Cargo

local function playerPosition(player: Player): Vector3
	local car = Vehicles.seatedIn(player) or Vehicles.get(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart and not Vehicles.seatedIn(player) then
		return rootPart.Position -- on foot: where you stand, not where the car is parked
	end
	if car then
		return car.chassis.Position
	end
	return if rootPart then rootPart.Position else World.DepotSpawn
end

local function info(def: { name: string, description: string }?): { [string]: string }?
	if not def then
		return nil
	end
	return { name = def.name, description = def.description }
end

local function article(noun: string): string
	local first = string.lower(string.sub(noun, 1, 1))
	return if string.find("aeiou", first, 1, true) then "an " .. noun else "a " .. noun
end

-- A job type's twists (Config.Missions.Twists ids), empty for most.
local function twistList(jobType: Config.JobTypeDef?): { string }
	local list: { string } = if jobType and jobType.twists then jobType.twists else {}
	return list
end

-- The defend twist holding out right now: the HUD's hint ("HOLD OUT 0:23 · …"), else nil.
local function defendHint(job: Job): string?
	local left = job.defendLeft
	if not left or job.defendDone then
		return nil
	end
	local clock = Economy.clock(left)
	if job.defendInside then
		return `HOLD OUT {clock} · keep them off {job.defendWho}!`
	end
	return `HOLD OUT {clock} · get back to {job.defendWho} on foot!`
end

-- What to do now (Cargo.step), the defend countdown instead while holding out, then (3.2) the twin-lever gate while it
-- is shut and you are at the stop.
local function stepOf(job: Job): (string, string)
	local handling, step = Cargo.step(job.cargo)
	local gate = if job.gateClosed and handling ~= "drive" then DuoGates.hint(job.owner) else nil
	return handling, defendHint(job) or gate or step
end

-- The mission part of the job payload and of Jobs.crewStatus, nil for every other job: id, name, campaign, number,
-- twists, coop, defendLeft (seconds, while holding out), and for the HUD crew, coopPay, gunnerKills.
local function missionInfo(job: Job): { [string]: any }?
	local offer = job.offer
	local id = offer.mission
	if not id then
		return nil
	end
	local def = Missions.find(id)
	local jobType = offer.jobType
	local twists: { string } = {}
	for _, twist in twistList(jobType) do
		table.insert(twists, twist)
	end
	local holding = job.defendLeft ~= nil and not job.defendDone
	return {
		id = id,
		name = if jobType then jobType.name else id,
		campaign = if def then def.campaign else nil,
		number = if def then def.number else nil,
		twists = twists,
		coop = offer.coop,
		defendLeft = if holding then math.max(0, math.ceil(job.defendLeft or 0)) else nil,
		defendHolding = if holding then job.defendInside else nil, -- somebody is in the area (the clock runs)
		crew = job.crewCount,
		coopPay = if offer.coop then Economy.coopPay(job.crewCount) else nil,
		gunnerKills = if offer.twists.gunner then job.gunnerKills else nil,
		duo = if offer.duo then true else nil, -- 3.2: a DUO mission
		gatePulled = if job.gateClosed then job.gatePulled else nil, -- 3.2: switches, the gate shut: levers down (0 – 2)
	}
end

-- 4.8: is a Cooler Box installed on the player's car now (gear: food keeps fresh longer)?
local function cooled(player: Player): boolean
	local car = Vehicles.get(player)
	return car ~= nil and Vehicles.hasGear(car, "cooler")
end

-- 4.8: the contract's line of the road event (a survivor waving or aboard, an add-on waiting for Y), else nil.
local function eventLine(job: Job): string?
	local lift = lifts[job.owner]
	if job.eventState == "waving" then
		return "🙋 Somebody is waving by the road ahead: stop next to them to give them a lift"
	elseif job.eventState == "asked" and job.addOn then
		return `ADD-ON offered: +${job.addOn.pay} · Y to take it`
	elseif lift then
		return `🙋 {lift.name} aboard: drop them at the depot (+${lift.bonus})`
	end
	return nil
end

-- ── 5.2: the orders ─────────────────────────────────────────────────────────

local OrdersConfig = JobsConfig.Orders

-- The order a stop of the job belongs to (the first one when none says so).
local function orderAt(job: Job, index: number): Order
	for _, order in job.orders do
		if table.find(order.stops, index) then
			return order
		end
	end
	return job.orders[1]
end

local function orderById(job: Job, id: number): Order?
	for _, order in job.orders do
		if order.id == id then
			return order
		end
	end
	return nil
end

local function openOrders(job: Job): { Order }
	local out: { Order } = {}
	for _, order in job.orders do
		if order.state == "open" then
			table.insert(out, order)
		end
	end
	return out
end

-- The focused order: the current stop's. Job.endsAt follows its clock (the crew strip, the HUD).
local function focusOrder(job: Job): Order
	local order = orderAt(job, job.stop)
	job.endsAt = order.endsAt
	return order
end

-- What every open order still holds or will pick up: its pieces less the delivered and the lost ones.
local function outstanding(job: Job): { number }
	local out: { number } = {}
	for _, order in job.orders do
		if order.state == "open" then
			table.insert(out, math.max(0, order.pieces - Cargo.deliveredOf(job.cargo, order.id) - Cargo.lostOf(job.cargo, order.id)))
		end
	end
	return out
end

-- The stops as JobRules sees them (their kind and order, done, where) and the pieces with you by the stop they go to.
local function stopStates(job: Job): ({ JobRules.StopState }, { [number]: number })
	local states: { JobRules.StopState } = {}
	for index, stop in job.offer.stops do
		local order = orderAt(job, index)
		table.insert(states, { kind = stop.kind, order = order.id, done = job.stopsDone[index] == true or order.state ~= "open", x = stop.park.X, z = stop.park.Z })
	end
	return states, Cargo.withYou(job.cargo)
end

-- Is every other stop of its order done (the last one: the horde waiting there)?
local function lastOfOrder(job: Job, index: number): boolean
	for _, other in orderAt(job, index).stops do
		if other ~= index and not job.stopsDone[other] then
			return false
		end
	end
	return true
end

-- The cargo rules of the open orders together (they share the vehicle: the jolts, the hits).
local function rulesNow(job: Job): { string }
	if #job.orders <= 1 then
		return job.offer.rules
	end
	local out: { string } = {}
	for _, order in job.orders do
		if order.state == "open" then
			for _, rule in order.offer.rules do
				if not table.find(out, rule) then
					table.insert(out, rule)
				end
			end
		end
	end
	return out
end

-- The danger of the run now: the highest tier of its open orders (the waves, the bandits).
local function tierNow(job: Job): number
	local tier = job.offer.tier
	for _, order in job.orders do
		if order.state == "open" then
			tier = math.max(tier, order.offer.tier)
		end
	end
	return tier
end

-- The payload's `orders`: every order with its stops (done, open, the current one), clock, pay and pieces.
local function ordersInfo(job: Job, focus: Order): { { [string]: any } }
	local states, withYou = stopStates(job)
	local out: { { [string]: any } } = {}
	for _, order in job.orders do
		local mine = order.offer
		local stops: { { [string]: any } } = {}
		for _, index in order.stops do
			local stop = job.offer.stops[index]
			table.insert(stops, {
				kind = stop.kind,
				label = stop.label,
				done = job.stopsDone[index] == true or (not job.free and index < job.stop),
				open = if job.free then JobRules.stopOpen(states, index, withYou) == "open" else index == job.stop,
				current = index == job.stop,
			})
		end
		table.insert(out, {
			id = order.id,
			title = if mine.jobType then `{mine.jobType.name}: {mine.cargo}` else `{mine.cargo} → {mine.customer}`,
			cargo = mine.cargo,
			customer = mine.customer,
			pay = mine.pay,
			paid = if order.state == "done" then order.paid else nil,
			rating = order.rating,
			endsAt = order.endsAt,
			state = order.state,
			stars = mine.tier,
			mode = mine.mode,
			pieces = order.pieces,
			delivered = Cargo.deliveredOf(job.cargo, order.id),
			stops = stops,
			pinned = job.pinned == order.id,
			focused = order == focus,
		})
	end
	return out
end

-- The payload's `carried`: every piece you carry (hands, pack, vehicle) with its order and its customer.
local function carriedInfo(job: Job): { { [string]: any } }
	local out: { { [string]: any } } = {}
	for _, entry in Cargo.carried(job.cargo) do
		local customer = entry.owner
		local dest = entry.dest
		local stop = if dest then job.offer.stops[dest] else nil
		if not customer and stop and stop.person then
			customer = stop.person.name
		end
		local order = orderById(job, entry.order)
		if not customer and order then
			customer = order.offer.customer
		end
		table.insert(out, { order = entry.order, look = entry.look, name = entry.name, where = entry.where, dest = customer, place = if stop then stop.address.name else nil })
	end
	return out
end

-- (set below, with the board: may the board add an order to this run now, and the room)
local stackInfo: (Player, Job) -> { [string]: any }?

local function payload(job: Job): { [string]: any }
	local offer = job.offer
	local stop = offer.stops[job.stop]
	-- 5.2: the focused order (the current stop's): its cargo, customer, clock, pay, pieces and rules.
	local order = focusOrder(job)
	local mine = order.offer
	local last = offer.stops[order.stops[#order.stops]] or offer.stops[#offer.stops]
	local status = Cargo.status(job.cargo)
	local handling, step = stepOf(job)
	job.lastStep = step
	local open = #openOrders(job)
	return {
		stars = mine.tier,
		cargo = mine.cargo,
		customer = mine.customer,
		address = last.address.name,
		district = last.address.district,
		position = stop.park,
		stage = stop.kind,
		stopIndex = table.find(order.stops, job.stop) or 1, -- (5.2: of the focused order's stops)
		stopCount = #order.stops,
		stopLabel = stop.label,
		progress = if stop.mode == "serve" or stop.mode == "board" then status.progress else 0,
		endsAt = order.endsAt,
		timeLimit = mine.time,
		condition = if job.free then order.condition else job.condition, -- (5.2 review: the focused order's)
		kills = job.kills,
		wave = job.wave, -- zombie waves so far
		pay = mine.pay,
		modifier = info(mine.modifier),
		jobType = info(mine.jobType),
		-- The cargo on foot (server/Cargo.luau).
		handling = handling, -- drive | carry | lead | board | serve
		step = step, -- what to do now
		inCar = status.inCar,
		delivered = status.delivered, -- handled at this stop: loaded at a pick-up, handed over at a drop
		needed = status.needed, -- for this stop
		total = order.pieces, -- pieces of the (focused) order
		deliveredTotal = Cargo.deliveredOf(job.cargo, order.id),
		lost = Cargo.lostOf(job.cargo, order.id), -- stolen or wrecked
		carrying = status.carrying,
		person = status.person,
		pile = status.pile,
		looseAt = status.looseAt, -- a piece put down (G): pick it up again
		piece = mine.piece,
		pieces = mine.plural,
		itemKind = mine.kind,
		timed = mine.jobType ~= nil and mine.jobType.timeLimit ~= nil, -- a rush: a fixed clock
		banditBoost = offer.boost,
		night = DayNight.isNight(), -- the pay and the waves are up
		crewCount = job.crewCount,
		mission = missionInfo(job), -- 3.0: the mission (nil for any other job)
		-- 4.8: the cargo's rules, the food's freshness (0 … 1, nil when not food), the contract's lines for them and
		-- for the road event
		rules = mine.rules,
		freshness = if JobRules.hasRule(mine.rules, "food") then order.freshness else nil,
		ruleLine = JobRules.ruleLine(mine.rules, order.freshness, offer.mode == "car" and cooled(job.owner)),
		eventLine = eventLine(job),
		-- 5.0: "foot" | "car" (5.1: | "bike"); on foot what rides over your hands (6.6: your bag, the bike's bag) and its room
		mode = offer.mode,
		pack = if status.foot then status.pack or 0 else nil,
		packRoom = if status.foot then status.packRoom or 0 else nil,
		rack = if status.foot and (status.rack or 0) > 0 then status.rack else nil, -- 5.3: of packRoom, the bike's bag (6.6)
		bagRoom = if status.foot then status.bagRoom else nil, -- 6.6: of packRoom, your bag's (client/BagUi.luau)
		-- 5.2: every order, the HUD's "+2 ORDERS", what the board may add now, and every piece you carry
		focus = order.id,
		orders = ordersInfo(job, order),
		ordersLine = if open > 1 then `+{open - 1} {if open == 2 then "ORDER" else "ORDERS"} · all of them on your phone: ORDERS` else nil,
		stack = stackInfo(job.owner, job),
		carried = carriedInfo(job),
	}
end

local function send(player: Player)
	local job = jobs[player]
	if not job then
		jobRemote:FireClient(player, nil)
		return
	end
	-- 5.4.1: a payload that fails never leaves the job unseen (the HUD OFF DUTY, the board refusing): a short one goes,
	-- the error goes to the Output once per job.
	local ok, data = pcall(payload, job)
	if not ok then
		if not job.badPayload then
			job.badPayload = true
			warn(`[Jobs] the job payload failed (a short one is sent): {data}`)
		end
		local offer = job.offer
		local stop = offer.stops[job.stop]
		data = {
			stars = offer.tier,
			cargo = offer.cargo,
			customer = offer.customer,
			pay = offer.pay,
			endsAt = job.endsAt,
			step = if stop then stop.label else nil,
			stage = if stop then stop.kind else nil,
			position = if stop then stop.park else nil,
			mode = offer.mode,
		}
	end
	jobRemote:FireClient(player, data)
	job.dirty = false
end

-- ── Offers ─────────────────────────────────────────────────────────────────

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- An address `low` … `high` (manhattan) from a point, or the closest one to that band. poiWeight > 0 lets the
-- named places in (that many times as likely).
-- 5.0: `allow` (a foot job: its districts) leaves the others out, the closest one too.
local function addressAround(x: number, z: number, low: number, high: number, poiWeight: number, avoid: { Map.Address }, allow: ((Map.Address) -> boolean)?): Map.Address?
	local fits: { Map.Address } = {}
	local closest: Map.Address? = nil
	local closestGap = math.huge
	for _, address in Map.addresses() do
		if table.find(avoid, address) or (address.poi and poiWeight <= 0) or (allow and not allow(address)) then
			continue
		end
		local d = Map.manhattan(x, z, address.x, address.z)
		if d >= low and d <= high then
			for _ = 1, if address.poi then poiWeight else 1 do
				table.insert(fits, address)
			end
		end
		local gap = if d < low then low - d else d - high
		if gap < closestGap then
			closest, closestGap = address, gap
		end
	end
	return if #fits > 0 then pick(fits) else closest
end

local function placeAddress(id: string): Map.Address?
	local name: string? = nil
	for _, place in Map.Places do
		if place.id == id then
			name = place.name
		end
	end
	for _, address in Map.addresses() do
		if address.poi and address.name == name then
			return address
		end
	end
	return nil
end

local function placeIdOf(address: Map.Address): string?
	if not address.poi then
		return nil
	end
	for _, place in Map.Places do
		if place.name == address.name then
			return place.id
		end
	end
	return nil
end

-- Where the vehicle parks, where the cargo and the person are, which way they face. A far place has its cargo spot
-- (Map.CargoSpots); an ordinary address parks on the road and the pile is on the sidewalk toward the building.
-- 4.3: on the real ground, not the flat road level: a raised lot or a yard over the road level put the circle, the
-- pile, the person and the HUD's waypoint under the ground. It looks down from 8 studs over `near` (the road level),
-- so a canopy, a bay roof or a sign over the spot is never taken for the ground.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local function onGround(x: number, z: number, near: number?): Vector3
	local base = near or World.RoadTop
	local skip: { Instance } = {}
	for _, name in { "Cars", "Zombies", "Npcs", "Animals", "Effects", "Loot", "Showroom", "Equipment", "Cargo" } do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(skip, child)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(x, base + 8, z), Vector3.new(0, -20, 0), groundParams)
	return Vector3.new(x, if hit and hit.Normal.Y > 0.6 then hit.Position.Y else base, z)
end

local function geometry(address: Map.Address): (Vector3, Vector3, Vector3)
	local spots = (Map :: any).CargoSpots :: { [string]: CargoSpot }?
	local id = placeIdOf(address)
	-- 5.3: a storefront's or a home's address (shared/Deliveries.luau) has its own spot: the park at the curb, the pile at
	-- the door.
	local spot = require(Shared.Deliveries).spotOf(address) or (if id and spots then spots[id] else nil)
	if spot then
		local park = onGround(spot.park.x, spot.park.z)
		local pile = onGround(spot.pile.x, spot.pile.z, park.Y)
		local facing = Vector3.new(spot.facing.x, 0, spot.facing.z)
		if facing.Magnitude < 0.1 then
			facing = Vector3.new(park.X - pile.X, 0, park.Z - pile.Z)
		end
		return park, pile, if facing.Magnitude > 0.1 then facing.Unit else Vector3.new(0, 0, -1)
	end
	local park = onGround(address.x, address.z)
	local outward = Vector3.new(address.nx, 0, address.nz)
	if outward.Magnitude < 0.5 then
		outward = Vector3.new(0, 0, -1) -- an open yard: the pile is beside the circle
	end
	outward = outward.Unit
	local pile = park - outward * Tuning.PileOffset
	return park, onGround(pile.X, pile.Z, park.Y), outward
end

-- "Rocco, the dock foreman" → Rocco, title "Dock foreman".
local function personFrom(text: string, role: string): Config.PersonDef
	local name, title = string.match(text, "^(.-),%s*(.+)$")
	if name and title then
		title = string.gsub(title, "^the%s+", "")
		return { name = name, title = string.upper(string.sub(title, 1, 1)) .. string.sub(title, 2), role = role }
	end
	return { name = text, title = nil, role = role }
end

local function newStop(address: Map.Address, kind: string, mode: string, needed: number, label: string, person: Config.PersonDef?): Stop
	local park, pile, facing = geometry(address)
	-- 5.3: a storefront's person stands in its doorway; a home's receiver is behind its door (sometimes nobody is in).
	local spot = require(Shared.Deliveries).spotOf(address)
	local clerk = if spot then spot.clerk else nil
	local home = spot ~= nil and spot.kind == "home" and kind == "drop"
	return {
		address = address,
		kind = kind,
		mode = mode,
		needed = needed,
		hold = 0,
		keep = 0,
		label = label,
		park = park,
		pile = pile,
		facing = facing,
		person = person,
		staging = nil,
		dock = nil,
		personAt = if clerk then Vector3.new(clerk.x, pile.Y, clerk.z) else nil,
		door = if home and spot then Vector3.new(spot.door.x, pile.Y, spot.door.z) else nil,
		nobody = if home then rng:NextNumber() < JobsConfig.Places.NobodyHome else nil,
	}
end

local function routeLength(fromX: number, fromZ: number, stops: { Stop }): number
	local total = 0
	local x, z = fromX, fromZ
	for _, stop in stops do
		total += Map.manhattan(x, z, stop.address.x, stop.address.z)
		x, z = stop.address.x, stop.address.z
	end
	return total
end

type CargoInfo = { kind: string, look: string, piece: string, plural: string, total: number }

-- 3.2: where a switches mission's gate stands (MissionDef.gates): "pickup" or "drop" (the default).
local function gatesOf(mission: string?): string
	local def = if mission then Missions.find(mission) else nil
	return if def and def.gates == "pickup" then "pickup" else "drop"
end

-- `plain` (3.7, the tutorial's delivery; 4.7, the board's SHORT & SAFE one): never a random modifier. `forced` (4.7,
-- the board's RISKY one): this modifier.
local function finishOffer(tierIndex: number, stops: { Stop }, distance: number, cargo: string, customer: string, jobType: Config.JobTypeDef?, pieces: CargoInfo, extraPay: number, plain: boolean?, forced: Config.ModifierDef?): Offer
	local tier = JobsConfig.Tiers[tierIndex]
	local timeLimit = if jobType then jobType.timeLimit else nil
	local modifier: Config.ModifierDef? = if timeLimit then nil else forced
	-- A mission is told as it is written: no random modifier.
	local mission = if jobType then jobType.mission else nil
	if not modifier and not mission and not plain and rng:NextNumber() < tier.modifierChance then
		-- A rush keeps its fixed clock: no modifier that changes the time or the car's speed.
		local choices: { Config.ModifierDef } = {}
		for _, candidate in JobsConfig.Modifiers do
			if not timeLimit or (candidate.timeMultiplier == 1 and candidate.speedMultiplier == 1) then
				table.insert(choices, candidate)
			end
		end
		if #choices > 0 then
			modifier = pick(choices)
		end
	end
	-- The time on foot: every piece handled, every serve stop held.
	local handling = 0
	for _, stop in stops do
		handling += if stop.mode == "serve" then stop.hold else Economy.handlingTime(stop.mode, stop.needed)
	end
	-- The twists (the missions): they pay more (Missions.twistPay); hunted cargo draws the bandits; holding out at
	-- the last drop gets its time on the clock.
	local twists: { [string]: boolean } = {}
	for _, twist in twistList(jobType) do
		twists[twist] = true
	end
	local defendTime = if twists.defend and jobType then math.max(5, jobType.defendTime or 30) else 0
	local basePay = Economy.jobPay(tier, distance, modifier and modifier.payMultiplier) + extraPay
	local pay = if jobType and next(twists) then math.floor(basePay * Missions.twistPay(jobType) / 5 + 0.5) * 5 else basePay
	-- A rush runs on its fixed clock; one with a fixed drop (a mission taken anywhere: the pick-up near you, the drop
	-- where it is) never gets less than the ordinary clock for its route.
	local clock = if timeLimit
		then (if jobType and jobType.dropAt then math.max(timeLimit, Economy.timeLimit(distance) + handling) else timeLimit)
		else Economy.timeLimit(distance, modifier and modifier.timeMultiplier) + handling
	local boost = math.max(1, if jobType and jobType.banditBoost then jobType.banditBoost else 1)
	if twists.hunted then
		boost *= Config.Missions.HuntedBoost
	end
	return {
		tier = tierIndex,
		stops = stops,
		distance = distance,
		pay = pay,
		time = clock + defendTime,
		cargo = cargo,
		customer = customer,
		jobType = jobType,
		modifier = modifier,
		kind = pieces.kind,
		look = pieces.look,
		piece = pieces.piece,
		plural = pieces.plural,
		total = pieces.total,
		level = Economy.jobLevel(jobType, tierIndex),
		boost = boost,
		mission = mission,
		twists = twists,
		coop = jobType ~= nil and jobType.coop == true,
		defendTime = defendTime,
		duo = jobType ~= nil and jobType.duo == true,
		gates = if twists.switches then gatesOf(mission) else nil,
		id = 0,
		approach = 0,
		role = nil,
		rules = {},
		dests = nil,
		destNames = nil,
		tutorial = false,
		mode = "car",
	}
end

-- 4.8: an offer's cargo rules (JobRules.cargoRules), never a mission's; cash makes the bandits come more where the
-- tier has them (the board shows BANDITS WANT IT).
local function applyRules(offer: Offer, business: string?)
	if offer.mission then
		return
	end
	offer.rules = JobRules.cargoRules(offer.kind, offer.look, business)
	local tier = JobsConfig.Tiers[offer.tier]
	if JobRules.hasRule(offer.rules, "cash") and tier and (tier.ambushEvery > 0 or tier.chaseEvery > 0) then
		offer.boost = math.max(offer.boost, JobsConfig.CargoRules.CashBoost)
	end
end

-- 4.7, the board's RISKY delivery: one of the tier's Config.Jobs.Choice.RiskyModifiers.
local function riskyModifier(tierIndex: number): Config.ModifierDef?
	local ids = JobsConfig.Choice.RiskyModifiers[tierIndex] or {}
	if #ids == 0 then
		return nil
	end
	return Economy.findModifier(pick(ids))
end

-- An ordinary delivery: a business that fits the danger level sends 1 – 3 pieces to somebody who needs them.
-- 3.7, `easy` (the tutorial's first delivery, Jobs.startTutorialJob): carried pieces only (no people, no horses), at
-- most Config.Jobs.TutorialPieces, the pick-up within TutorialPickupMax, the drop within TutorialDropMax of it, never
-- a bulk order or a modifier. (5.0: the tutorial's delivery is on foot, footOffer; `easy` is kept for a car one.)
-- 4.7, `role` (the board's choice, Config.Jobs.Choice): short = the drop in the near band, the fewest pieces, no
-- modifier, no bulk; long = the far band, × LongPay; risky = a RiskyModifiers modifier, the bandits want it (×
-- RiskyBoost where the tier has bandits), × RiskyPay; bulk = a business that sends several, its most pieces + the
-- tier's BulkExtra. Without a role (the tutorial, the admin's "ordinaryN") it is made as before 4.7.
-- 5.7, `room`: what the player's own car holds now; a ★ delivery takes Config.Jobs.CarStep's pieces up to it
-- (JobRules.carStepPieces: at least the Rusty Van's EasyMaxPieces).
local function ordinaryOffer(from: Vector3, tierIndex: number, easy: boolean?, role: string?, room: number?): Offer?
	local Deliveries = require(Shared.Deliveries) -- 5.3 (required here: Jobs keeps its top-level locals)
	local tier = JobsConfig.Tiers[tierIndex]
	local choice = JobsConfig.Choice
	local hour = DayNight.hour()
	local pickupMax = if easy then math.max(JobsConfig.PickupMinDistance, JobsConfig.TutorialPickupMax) else JobsConfig.PickupMaxDistance
	local dropMin, dropMax = JobRules.window(role, tier.minDistance, tier.maxDistance)
	if easy then
		dropMin, dropMax = tier.minDistance, math.clamp(JobsConfig.TutorialDropMax, tier.minDistance, tier.maxDistance)
	end
	-- 5.3: the business's storefront nearest to you (within Places.CarReach, else the nearest at all; 5.3 review: the
	-- tutorial's within its pick-up reach first); nil for a business without one (an address near you as before).
	local function venueNear(business: Config.BusinessDef): Map.Venue?
		return (if easy then Deliveries.venueFor(business, from.X, from.Z, pickupMax, nil) else nil)
			or Deliveries.venueFor(business, from.X, from.Z, JobsConfig.Places.CarReach, nil)
			or Deliveries.venueFor(business, from.X, from.Z, math.huge, nil)
	end
	local businesses: { Config.BusinessDef } = {}
	local near: { Config.BusinessDef } = {} -- (the tutorial's: a storefront within its pick-up reach)
	for _, business in JobsConfig.Businesses do
		local handy = not easy or (not Cargo.isPeople(business.kind) and business.kind ~= "horse")
		-- 5.3: only a business open at this hour (the bakery in the morning …). 5.3 review: and one that delivers
		-- somewhere in this tier's range from its storefront (no ★ ice cream to a home 1,700 studs away).
		local venue = if handy then venueNear(business) else nil
		if table.find(business.tiers, tierIndex) and handy and Deliveries.open(business, hour)
			and Deliveries.reaches(business, if venue then venue.park.x else from.X, if venue then venue.park.z else from.Z, dropMin, dropMax, nil) then
			table.insert(businesses, business)
			if easy and venue and Map.manhattan(from.X, from.Z, venue.park.x, venue.park.z) <= pickupMax then
				table.insert(near, business)
			end
		end
	end
	if #near > 0 then
		businesses = near
	end
	if role == "bulk" then
		-- the ones that send more than one piece (if there are any)
		local several: { Config.BusinessDef } = {}
		for _, business in businesses do
			if (business.pieces[2] or business.pieces[1]) > 1 then
				table.insert(several, business)
			end
		end
		if #several > 0 then
			businesses = several
		end
	end
	if #businesses == 0 then
		return nil -- (5.3 review: never a business of another tier or a closed one, nor one with nowhere to go)
	end
	local business = pick(businesses)
	local venue = venueNear(business)
	local pickup = if venue then Deliveries.venueAddress(venue) else addressAround(from.X, from.Z, JobsConfig.PickupMinDistance, pickupMax, 0, {})
	if not pickup then
		return nil
	end
	-- 5.3: where it goes: a home's door or another storefront (the business's `to`), else an address as before. The
	-- person there: a home's resident (5.5, shared/Residents.luau: "Jana Nováková" at "Apt 4C, 40 6th Ave"), the
	-- storefront's own (B2B), the Harbor's foreman, a far place's own, else one of the business's receivers.
	local poiWeight = if tierIndex >= 3 and not easy then 3 else 0
	local function dropNear(x: number, z: number, low: number, high: number, avoid: { Map.Address }): (Map.Address?, Config.PersonDef?)
		if business.to then
			local target = Deliveries.dropFor(business, x, z, low, high, avoid, function(): number
				return rng:NextNumber()
			end, nil)
			if target then
				return target.address, target.person
			end
			return nil, nil
		end
		local address = addressAround(x, z, low, high, poiWeight, avoid)
		local placeId = if address then placeIdOf(address) else nil
		return address, if placeId then JobsConfig.PlacePeople[placeId] else nil
	end
	local drop, own = dropNear(pickup.x, pickup.z, dropMin, dropMax, { pickup })
	if not drop then
		return nil
	end
	local receiver = own or pick(business.receivers)
	local most = business.pieces[2] or business.pieces[1]
	local count = if role == "short" then business.pieces[1] elseif role == "bulk" then most else rng:NextInteger(business.pieces[1], most)
	if tierIndex == 1 then
		-- 3.5: a ★ delivery fits the Rusty Van. 5.7: the step up to a car: 3 – 4 pieces, as many as your car holds.
		count = if easy then math.min(count, JobsConfig.EasyMaxPieces) else JobRules.carStepPieces(role, rng:NextNumber(), room)
	end
	if easy then
		count = math.max(1, math.min(count, JobsConfig.TutorialPieces))
	end
	-- 3.4: a bulk order now and then on the dangerous levels: more pieces (3.5: a later stage or a bigger car).
	-- 4.7: the BULK ORDER always, the short and the risky one never, the long one by chance as before.
	local extra = JobsConfig.BulkExtra[tierIndex]
	local bulkChance = if role == "bulk" then 1 elseif role == "short" or role == "risky" then 0 else (JobsConfig.BulkChance[tierIndex] or 0)
	if not easy and extra and extra[2] > 0 and rng:NextNumber() < bulkChance then
		count += rng:NextInteger(extra[1], extra[2])
	end
	local customer = if drop.poi then `{receiver.name}, {drop.name}` else receiver.name
	local stops: { Stop } = {
		newStop(pickup, "pickup", "carry", count, if venue then `PICK UP at {pickup.name}` else `PICK UP at the {business.place}, {pickup.name}`, business.giver),
		newStop(drop, "drop", "carry", count, `DELIVER to {receiver.name}, {drop.name}`, receiver),
	}
	-- 4.8, multi-drop (a board delivery of ★★★ / ★★★★, never SHORT & SAFE or the tutorial's): 2 … 3 customers one after
	-- the other (MultiDrop.Gap apart), every piece labelled for its customer (Offer.dests, destNames).
	local drops = if role and role ~= "short" and not easy then JobRules.dropCount(tierIndex, count, #business.receivers, rng:NextNumber(), rng:NextNumber()) else 1
	local dests: { number }?, destNames: { [number]: string }? = nil, nil
	if drops > 1 then
		local people = table.clone(business.receivers)
		for i = #people, 2, -1 do
			local j = rng:NextInteger(1, i)
			people[i], people[j] = people[j], people[i]
		end
		local needs = Economy.splitPieces(count, drops)
		local multi: { Stop } = { stops[1] }
		local names: { [number]: string } = {}
		local avoid: { Map.Address } = { pickup }
		local at = pickup
		local gap = JobsConfig.MultiDrop.Gap
		for n = 1, drops do
			local address: Map.Address?, there: Config.PersonDef? = nil, nil
			if n == 1 then
				address, there = dropNear(pickup.x, pickup.z, dropMin, dropMax, avoid)
			else
				address, there = dropNear(at.x, at.z, gap[1], gap[2], avoid)
			end
			if not address then
				break
			end
			table.insert(avoid, address)
			local person = there or people[n]
			table.insert(multi, newStop(address, "drop", "carry", needs[n], `DELIVER to {person.name}, {address.name}`, person))
			names[n + 1] = person.name
			at = address
		end
		if #multi == drops + 1 then
			stops = multi
			dests = JobRules.destinations(needs, 2)
			destNames = names
			customer = `{names[2]} & {drops - 1} more`
		else
			drops = 1
		end
	end
	if easy then
		stops[#stops].nobody = nil -- (the tutorial's first delivery: somebody is home)
	end
	local pieces: CargoInfo = { kind = business.kind, look = business.look, piece = business.piece, plural = business.plural, total = count }
	local forced = if role == "risky" then riskyModifier(tierIndex) else nil
	local offer = finishOffer(tierIndex, stops, routeLength(from.X, from.Z, stops), business.cargo, customer, nil, pieces, Tuning.PayPerPiece * count + JobRules.multiDropPay(drops), easy or role == "short", forced)
	offer.role = role
	offer.dests = dests
	offer.destNames = destNames
	if not easy then
		applyRules(offer, business.id) -- 4.8 (the tutorial's delivery stays simple)
	end
	-- 5.3: the evening peak (pizzas, burgers, noodles) pays more.
	local payMultiplier = (if role == "long" then choice.LongPay elseif role == "risky" then choice.RiskyPay else 1) * Deliveries.peak(business, hour)
	if payMultiplier ~= 1 then
		offer.pay = math.floor(offer.pay * payMultiplier / 5 + 0.5) * 5
	end
	offer.peak = if Deliveries.peak(business, hour) > 1 then Deliveries.peak(business, hour) else nil
	if role == "risky" and (tier.ambushEvery > 0 or tier.chaseEvery > 0) then
		offer.boost = math.max(offer.boost, choice.RiskyBoost)
	end
	return offer
end

-- 5.0, an ON FOOT job (Config.Jobs.Foot): a business that sends a light look (Config.Cargo.LightLooks) sends 1 – 3
-- pieces (never more than `room`, what you carry: Transport.handsRoom) from an address near you to one a short walk
-- on, Downtown or in the Suburbs only. A ★ job inside (tier 1) with `mode = "foot"`: its own pay and clock
-- (JobRules.footPay / footTime), level 1, no bandits, only the food rule (the others are about driving). `role` as on
-- the board (short / long / risky / bulk: JobRules.roles); `tutorial` (the first day's delivery): the post office's
-- letters (Foot.TutorialCargo), Config.Jobs.TutorialPieces of them, the drop on the same street (TutorialDrop).
-- 5.1, `bike`: a BIKE job instead (Config.Jobs.Bike's numbers, `mode = "bike"`, its level): Bike.Pieces by `room`
-- (what your bike holds), a longer ride.
-- 5.3: from the business's storefront nearest to you (within PickupMax + PickupWiden) to a home's door or another
-- storefront (shared/Deliveries.luau), only the businesses open at this hour (6.6: every light look fits your bag and
-- the bike's, so no smaller count for a bouquet or a cake). `role` "round": the
-- newspaper round instead (Config.Jobs.Round: the bundle at The Daily Undead, one paper to every door on one or two
-- streets, JobRules.roundPay / roundTime).
local function footOffer(from: Vector3, role: string?, room: number, tutorial: boolean?, bike: boolean?): Offer?
	local Deliveries = require(Shared.Deliveries)
	local foot: LightJob = if bike then JobsConfig.Bike else JobsConfig.Foot
	local choice = JobsConfig.Choice
	local hour = DayNight.hour()
	local mode = if bike then "bike" else "foot"
	local reach = foot.PickupMax + foot.PickupWiden
	local function allow(address: Map.Address): boolean
		return not address.poi and foot.Districts[address.district] == true
	end
	if role == "round" then
		-- 5.3, the newspaper round: the bundle at the print shop, a paper (an apartment entrance: its subscribers') to
		-- every door of one or two streets near it.
		local round = JobsConfig.Round
		local venue = Map.venuesOf(round.Business)[1]
		local business: Config.BusinessDef? = nil
		for _, entry in JobsConfig.Businesses do
			if entry.id == round.Business then
				business = entry
			end
		end
		if not venue or not business or Map.manhattan(from.X, from.Z, venue.park.x, venue.park.z) > reach then
			return nil
		end
		local doors = Deliveries.round(venue, if bike then round.BikeReach else round.FootReach, function(): number
			return rng:NextNumber()
		end, allow, if bike then round.BikeRoute else round.FootRoute) -- (5.3 review: a route of a walk / a ride)
		if #doors == 0 then
			return nil
		end
		local pickup = Deliveries.venueAddress(venue)
		local stops: { Stop } = { newStop(pickup, "pickup", "carry", 0, `PICK UP the papers at {pickup.name}`, business.giver) }
		stops[1].bundle = true
		local needs: { number } = {}
		local names: { [number]: string } = {}
		local streets: { string } = {}
		for n, door in doors do
			local address = Deliveries.homeAddress(door.home)
			-- (the subscriber by their address: the FOR tag, the bag; nobody comes out, Cargo's toss)
			local stop = newStop(address, "drop", "carry", door.papers, `TOSS the paper at {address.name}`, { name = address.name, title = "Subscriber", role = "townsperson" })
			stop.toss, stop.door, stop.nobody = true, nil, nil
			table.insert(stops, stop)
			needs[n] = door.papers
			names[n + 1] = address.name
			if not table.find(streets, door.home.street) then
				table.insert(streets, door.home.street)
			end
		end
		local papers = 0
		for _, count in needs do
			papers += count
		end
		stops[1].needed = papers
		local pieces: CargoInfo = { kind = business.kind, look = business.look, piece = business.piece, plural = business.plural, total = papers }
		local offer = finishOffer(1, stops, routeLength(from.X, from.Z, stops), "Morning papers", `{#doors} doors on {table.concat(streets, " & ")}`, nil, pieces, 0, true, nil)
		local walk = math.max(0, offer.distance - Map.manhattan(from.X, from.Z, pickup.x, pickup.z))
		offer.mode = mode
		offer.role = "round"
		offer.round = true
		offer.level = if bike then JobsConfig.Bike.Level else 1
		offer.boost = 1
		offer.dests = JobRules.destinations(needs, 2)
		offer.destNames = names
		offer.pay = JobRules.roundPay(papers, walk, bike)
		offer.time = JobRules.roundTime(offer.distance, #doors, bike)
		offer.rules = {}
		return offer
	end
	local dropMin, dropMax = JobRules.window(role, foot.MinDistance, foot.MaxDistance)
	if tutorial then
		dropMin, dropMax = foot.MinDistance, math.max(foot.MinDistance, JobsConfig.Foot.TutorialDrop)
	end
	-- The businesses that may send this run: open now, a light look you have room for, a storefront within `within`
	-- (5.3 review: and somewhere to go from it in this run's range).
	local function gather(within: number): { Config.BusinessDef }
		local found: { Config.BusinessDef } = {}
		for _, business in JobsConfig.Businesses do
			local light = Tuning.LightLooks[business.look] and not Cargo.isPeople(business.kind)
			if tutorial then
				if light and business.id == "post" then
					table.insert(found, business)
				end
			elseif light and Deliveries.open(business, hour) and room >= 1 then
				local venue = Deliveries.venueFor(business, from.X, from.Z, within, allow)
				if (#Map.venuesOf(business.id) == 0 or venue ~= nil)
					and Deliveries.reaches(business, if venue then venue.park.x else from.X, if venue then venue.park.z else from.Z, dropMin, dropMax, allow) then
					table.insert(found, business)
				end
			end
		end
		return found
	end
	local businesses = gather(reach)
	if #businesses == 0 and not tutorial then
		-- 5.3 review: every storefront near you is shut (the Suburbs at night): the nearest open one, up to twice as far.
		reach *= 2
		businesses = gather(reach)
	end
	if role == "bulk" then
		local several: { Config.BusinessDef } = {}
		for _, business in businesses do
			if (business.pieces[2] or business.pieces[1]) > 1 then
				table.insert(several, business)
			end
		end
		if #several > 0 then
			businesses = several
		end
	end
	if #businesses == 0 then
		return nil
	end
	local business = pick(businesses)
	local pickupMax = if tutorial then math.max(foot.PickupMax, JobsConfig.TutorialPickupMax) else foot.PickupMax
	local venue = Deliveries.venueFor(business, from.X, from.Z, if tutorial then math.huge else reach, allow)
	local pickup = if venue then Deliveries.venueAddress(venue) else addressAround(from.X, from.Z, foot.PickupMin, pickupMax, 0, {}, allow)
	if pickup and not venue and Map.manhattan(from.X, from.Z, pickup.x, pickup.z) > pickupMax then
		-- (none that close, the depot's safe zone has no addresses: a little farther, not always the same one)
		pickup = addressAround(from.X, from.Z, foot.PickupMin, pickupMax + foot.PickupWiden, 0, {}, allow)
	end
	-- 5.0: addressAround falls back to the closest address at any distance: out in the country (far from Downtown and
	-- the Suburbs) there is no foot job at all, not a walk across the map.
	if pickup and not venue and Map.manhattan(from.X, from.Z, pickup.x, pickup.z) > pickupMax + foot.PickupWiden then
		pickup = nil
	end
	if not pickup then
		return nil
	end
	local drop: Map.Address? = nil
	local own: Config.PersonDef? = nil
	if business.to then
		local target = Deliveries.dropFor(business, pickup.x, pickup.z, dropMin, dropMax, { pickup }, function(): number
			return rng:NextNumber()
		end, allow)
		if target then
			drop, own = target.address, target.person
		end
	else
		drop = addressAround(pickup.x, pickup.z, dropMin, dropMax, 0, { pickup }, allow)
	end
	if not drop then
		return nil
	end
	local receiver = own or pick(business.receivers)
	local most = business.pieces[2] or business.pieces[1]
	local wanted = if role == "short" then business.pieces[1] elseif role == "bulk" then most else rng:NextInteger(business.pieces[1], most)
	if bike then
		-- 5.1: a bike's run is sized by the bike (Bike.Pieces, never more than it holds), not by the business.
		local band = foot.Pieces
		wanted = if role == "short" then band[1] elseif role == "bulk" then band[2] else rng:NextInteger(band[1], band[2])
	end
	local count = if tutorial then math.max(1, math.min(JobsConfig.TutorialPieces, room)) else JobRules.footPieces(wanted, room, foot)
	local words = JobsConfig.Foot.TutorialCargo
	local cargoName = if tutorial then words.cargo else business.cargo
	local pieces: CargoInfo = if tutorial
		then { kind = words.kind, look = words.look, piece = words.piece, plural = words.plural, total = count }
		else { kind = business.kind, look = business.look, piece = business.piece, plural = business.plural, total = count }
	local stops: { Stop } = {
		newStop(pickup, "pickup", "carry", count, if tutorial then `PICK UP the letters at {pickup.name}` elseif venue then `PICK UP at {pickup.name}` else `PICK UP at the {business.place}, {pickup.name}`, business.giver),
		newStop(drop, "drop", "carry", count, `DELIVER to {receiver.name}, {drop.name}`, receiver),
	}
	if tutorial then
		stops[2].nobody = nil -- (the first delivery: somebody is home)
	end
	local forced = if role == "risky" then riskyModifier(1) else nil
	local offer = finishOffer(1, stops, routeLength(from.X, from.Z, stops), cargoName, receiver.name, nil, pieces, 0, tutorial or role == "short", forced)
	offer.mode = mode
	offer.role = role
	offer.level = if bike then JobsConfig.Bike.Level else 1 -- always open: the board's ON FOOT section (5.1: BIKE from its level)
	offer.boost = 1 -- no bandits on foot (nor on a bike)
	-- Its own pay and clock (the walk, not the drive).
	local handling = 0
	for _, stop in stops do
		handling += Economy.handlingTime(stop.mode, stop.needed)
	end
	local modifier = offer.modifier
	local roleMult = if role == "long" then choice.LongPay elseif role == "risky" then choice.RiskyPay else 1
	local peak = if tutorial then 1 else Deliveries.peak(business, hour) -- 5.3: the evening peak
	offer.pay = JobRules.footPay(offer.distance, count, roleMult * peak * (if modifier then modifier.payMultiplier else 1), foot)
	offer.time = JobRules.footTime(offer.distance, handling, if modifier then modifier.timeMultiplier else nil, foot)
	offer.peak = if peak > 1 then peak else nil
	if not tutorial then
		-- 4.8: of the cargo's rules only the food's freshness counts on foot (the jolts are a vehicle's).
		applyRules(offer, business.id)
		offer.rules = if JobRules.hasRule(offer.rules, "food") then { "food" } else {}
	end
	return offer
end

-- 4.0, the Freight Run (JobTypeDef load "pallet"): 1 … items pallets from a loading dock of its hub (shared/Map.luau
-- FreightDocks[pickupAt]) to the receiving dock of one of its dropChoices (Map.ReceivingDocks): the truck's circle in
-- the dock's bay, the foreman on the dock, the pallets on the dock floor (Stop.staging); at the drop the person by the
-- pad, the pallets set down on the pad. Pays its stops and PalletPay a pallet.
--
-- The dock and the pad are taken when the job starts (placeDocks), one no running Freight Run uses (docksInUse:
-- "warehouse:2:1" = the hub, the dock, the row; "market:1:1" = a receiving pad), so two runs never share the staging
-- spots and the "Lift pallet" prompts. All of them busy: a second row (DockRow out on the dock floor toward its edge,
-- PadRow beside the pad away from the receiver); all of those busy too: the first one's second row, shared.
local docksInUse: { [string]: Player } = {}
local DockRow = 13.5
local PadRow = 5

-- The first free dock of `count` at `id` (by number, then row): its number, its row and its docksInUse key.
local function freeDock(id: string, count: number): (number, number, string)
	for row = 1, 2 do
		for n = 1, count do
			local key = `{id}:{n}:{row}`
			if not docksInUse[key] then
				return n, row, key
			end
		end
	end
	return 1, 2, `{id}:1:2`
end

-- Gives back the docks and pads `player`'s job took (all of them, or those at `id`).
local function freeDocks(player: Player, id: string?)
	for taken, who in docksInUse do
		if who == player and (id == nil or string.sub(taken, 1, #id + 1) == `{id}:`) then
			docksInUse[taken] = nil
		end
	end
end

-- Puts a Freight Run's stop at dock `n` (a pick-up: its bay, its staging spots, "(dock n)") or at its receiving pad
-- (a drop: the pad's spots), in row `row`.
local function dockStop(stop: Stop, n: number, row: number)
	local id = stop.dock or ""
	local hub = Map.FreightDocks[id]
	local receiving = Map.ReceivingDocks[id]
	local staging: { Vector3 } = {}
	if stop.kind == "pickup" and hub then
		local dock = hub.docks[n]
		local floor = Map.WalkTop + hub.height
		stop.park = Vector3.new(dock.park.x, World.RoadTop, dock.park.z)
		stop.facing = Vector3.new(dock.facing.x, 0, dock.facing.z).Unit
		local shift = if row > 1 then stop.facing * DockRow else Vector3.zero
		for _, spot in dock.staging do
			table.insert(staging, Vector3.new(spot.x, floor, spot.z) + shift)
		end
		stop.label = `{(string.gsub(stop.label, "%s*%(dock %d+%)$", ""))} (dock {n})`
	elseif receiving then
		local first, last = receiving.spots[1], receiving.spots[#receiving.spots]
		local side = Vector3.new(last.z - first.z, 0, first.x - last.x)
		side = if side.Magnitude > 0.1 then side.Unit else Vector3.xAxis
		local away = Vector3.new(receiving.receiver.x - (first.x + last.x) / 2, 0, receiving.receiver.z - (first.z + last.z) / 2)
		if side:Dot(away) > 0 then
			side = -side
		end
		local shift = if row > 1 then side * PadRow else Vector3.zero
		for _, spot in receiving.spots do
			table.insert(staging, Vector3.new(spot.x, Map.WalkTop, spot.z) + shift)
		end
	end
	stop.staging = staging
end

local function freightOffer(from: Vector3, jobType: Config.JobTypeDef): Offer?
	local hubId = jobType.pickupAt or "warehouse"
	local hub = Map.FreightDocks[hubId]
	local pickup = placeAddress(hubId)
	local choices: { string } = {}
	local listed: { string } = jobType.dropChoices or {}
	for _, id in listed do
		if Map.ReceivingDocks[id] and placeAddress(id) then
			table.insert(choices, id)
		end
	end
	if not hub or not pickup or #hub.docks == 0 or #choices == 0 then
		return nil
	end
	local dropId = pick(choices)
	local drop = placeAddress(dropId) :: Map.Address
	local receiving = Map.ReceivingDocks[dropId]
	local count = rng:NextInteger(1, math.max(1, jobType.items))
	local roles = JobsConfig.People[jobType.id] or { giver = "foreman", receiver = "worker" }
	local giver = personFrom(jobType.giver, jobType.giverRole or roles.giver)
	local receiver = JobsConfig.FreightReceivers[dropId] or personFrom(jobType.receiver, jobType.receiverRole or roles.receiver)
	-- The pick-up: the dock's bay, the foreman and the pallets up on the dock floor.
	-- (The dock free now; placeDocks takes one when the job starts.)
	local floor = Map.WalkTop + hub.height
	local label = string.gsub(jobType.pickupLabel, "%s+AT$", "")
	local load = newStop(pickup, "pickup", "pallet", count, `{label} at {pickup.name}`, giver)
	load.pile = Vector3.new(hub.giver.x, floor, hub.giver.z)
	load.dock = hubId
	local dockNumber, dockRow = freeDock(hubId, #hub.docks)
	dockStop(load, dockNumber, dockRow)
	load.hold = jobType.loadTime
	-- The drop: the place's circle, the person by the pad, the pad.
	local unload = newStop(drop, "drop", "pallet", count, `{jobType.dropLabel} {drop.name}`, receiver)
	unload.dock = dropId
	dockStop(unload, 1, 1)
	local middle = Vector3.zero
	for _, spot in receiving.spots do
		middle += Vector3.new(spot.x, Map.WalkTop, spot.z)
	end
	middle /= math.max(1, #receiving.spots)
	unload.pile = Vector3.new(receiving.receiver.x, Map.WalkTop, receiving.receiver.z)
	local toward = Vector3.new(middle.X - unload.pile.X, 0, middle.Z - unload.pile.Z)
	if toward.Magnitude > 0.1 then
		unload.facing = toward.Unit
	end
	unload.hold = jobType.unloadTime
	local stops: { Stop } = { load, unload }
	local kind = Tuning.Kinds.pallet or Tuning.Kinds.crate
	local pieces: CargoInfo = { kind = jobType.itemKind, look = kind.look, piece = kind.piece, plural = kind.plural, total = count }
	return finishOffer(jobType.tier, stops, routeLength(from.X, from.Z, stops), jobType.cargo, `{receiver.name}, {drop.name}`, jobType, pieces, jobType.payPerStop * #stops + Tuning.PalletPay * count)
end

-- A special job's stops from its definition: the pick-ups (at a place, or homes around you), then the deliveries
-- (the last one at a place, or addresses on the way). The pieces are split over the pick-ups and over the drops.
local function jobOffer(from: Vector3, jobType: Config.JobTypeDef): Offer?
	if jobType.load == "pallet" then
		return freightOffer(from, jobType)
	end
	local stops: { Stop } = {}
	local avoid: { Map.Address } = {}
	local x, z = from.X, from.Z
	-- The looks: the job type's own (the missions), else Config.Jobs.People, else townspeople.
	local roles = JobsConfig.People[jobType.id] or { giver = "townsperson", receiver = "townsperson" }
	local giver = personFrom(jobType.giver, jobType.giverRole or roles.giver)
	local receiver = personFrom(jobType.receiver, jobType.receiverRole or roles.receiver)
	local loads = Economy.splitPieces(jobType.items, jobType.pickups)
	-- A rush (a fixed clock) stays in reach: the pick-up close by, the drop a short drive on.
	local rush = jobType.timeLimit ~= nil
	for n = 1, jobType.pickups do
		local low = if n == 1 then (if rush then 100 else 120) else 90
		local high = if n == 1 then (if rush then 350 else 450) else 280
		local address = if jobType.pickupAt then placeAddress(jobType.pickupAt) else addressAround(x, z, low, high, 0, avoid)
		if not address then
			return nil
		end
		table.insert(avoid, address)
		local count = if jobType.pickups > 1 then ` ({n}/{jobType.pickups})` else ""
		-- "LOAD THE CASH AT" + " at First Zombie Bank": one "at" is enough.
		local label = string.gsub(jobType.pickupLabel, "%s+AT$", "")
		local stop = newStop(address, "pickup", jobType.load, loads[n], `{label}{count} at {address.name}`, giver)
		stop.hold = jobType.loadTime
		table.insert(stops, stop)
		x, z = address.x, address.z
	end
	local drops = Economy.splitPieces(jobType.items, jobType.drops)
	for n = 1, jobType.drops do
		local last = n == jobType.drops
		local low = if jobType.drops > 1 then 150 elseif rush then 300 else 450
		local high = if jobType.drops > 1 then 450 elseif rush then 800 else 1100
		local address = if last and jobType.dropAt then placeAddress(jobType.dropAt) else addressAround(x, z, low, high, 0, avoid)
		if not address then
			return nil
		end
		table.insert(avoid, address)
		local count = if jobType.drops > 1 then ` ({n}/{jobType.drops})` else ""
		local serve = jobType.unload == "serve"
		local stop = newStop(address, "drop", jobType.unload, drops[n], `{jobType.dropLabel} {address.name}{count}`, if serve then nil else receiver)
		stop.hold = jobType.unloadTime
		if serve then
			-- The truck empties evenly over the serve stops.
			local before = Economy.serveLeft(jobType.items, jobType.drops, n - 1)
			stop.keep = Economy.serveLeft(jobType.items, jobType.drops, n)
			stop.needed = before - stop.keep
		end
		table.insert(stops, stop)
		x, z = address.x, address.z
	end
	local customer = "Customers"
	local employer = if jobType.employer then Economy.findEmployer(jobType.employer) else nil
	if employer then
		customer = employer.name
	elseif jobType.dropAt then
		customer = stops[#stops].address.name
	end
	local kind = Tuning.Kinds[jobType.itemKind] or Tuning.Kinds.crate
	local pieces: CargoInfo = { kind = jobType.itemKind, look = kind.look, piece = kind.piece, plural = kind.plural, total = jobType.items }
	-- A mission starts wherever START was pressed: the drive to its first stop counts (pay and clock) for at most
	-- the board's pick-up distance, nothing for coming from across the map.
	local route = routeLength(from.X, from.Z, stops)
	if jobType.mission then
		local first = stops[1].address
		route -= math.max(0, Map.manhattan(from.X, from.Z, first.x, first.z) - JobsConfig.PickupMaxDistance)
	end
	local offer = finishOffer(jobType.tier, stops, route, jobType.cargo, customer, jobType, pieces, jobType.payPerStop * #stops)
	applyRules(offer, nil) -- 4.8: a special's cargo has its rules too (not a mission's)
	return offer
end

-- 5.0: a job done in your own car (not on foot, no company vehicle lent) while you own no vehicle yet. 5.1: nor a
-- bike job; riding your bike (profile.car a bike) counts as no car.
local function needsVehicle(player: Player, offer: Offer): boolean
	local jobType = offer.jobType
	local profile = PlayerData.get(player)
	return offer.mode == "car" and not (jobType and jobType.vehicle) and profile ~= nil and (profile.car == nil or Transport.riding(player))
end

-- 5.1: does the player own a car of their own (not a company vehicle, not a bike)?
local function ownsCar(player: Player): boolean
	local profile = PlayerData.get(player)
	if profile then
		for id, owned in profile.cars do
			local def = Economy.findCar(id)
			if owned and def and not def.company and not def.bike then
				return true
			end
		end
	end
	return false
end

-- 5.1: the board's words for a car job needsVehicle refuses: on your bike with a car of your own, "CALL YOUR CAR";
-- else "NEEDS A VEHICLE" (the Old Van at level 4).
local function vehicleLock(player: Player): (string, string)
	if Transport.riding(player) and ownsCar(player) then
		return JobsConfig.Bike.NeedsCar, JobsConfig.Bike.NeedsCarButton
	end
	return JobsConfig.Foot.NeedsVehicle, JobsConfig.Foot.NeedsVehicleButton
end

-- 5.1: why a BIKE job is not for this player now (its text and the board's button), or nil: no bike of your own
-- (Spoke & Chain), or your car is the one you drive (the phone's MY BIKE switches).
local function bikeLock(player: Player, offer: Offer): (string?, string?)
	if offer.mode ~= "bike" then
		return nil, nil
	end
	local bikeId = Transport.bikeOf(player)
	if not bikeId then
		return JobsConfig.Bike.NeedsBike, JobsConfig.Bike.NeedsBikeButton
	elseif not Transport.riding(player) then
		return JobsConfig.Bike.RideBike, JobsConfig.Bike.RideBikeButton
	end
	return nil, nil
end

-- 3.4: the cargo slots a job needs, what the vehicle that would do it holds and that vehicle's name: the company
-- vehicle the job lends, else the player's equipped car (3.5: at its stage). 5.0: on foot the pieces you carry
-- (Transport: hands and bag); no vehicle yet: 0.
local function slotsFor(player: Player, offer: Offer): (number, number, string)
	local jobType = offer.jobType
	local need = Economy.cargoNeed(if jobType then jobType.load else "carry", offer.total)
	if offer.round then
		return 1, 1, "newspaper satchel" -- 5.3: the round's bundle goes into its own satchel
	end
	if offer.mode == "foot" then
		local room = Transport.footOf(player).room
		return offer.total, room, if room > Config.Cargo.HandsMax then "hands and bag" else "hands"
	elseif offer.mode == "bike" then
		-- 5.1: what your bike holds with its bike gear and your bag.
		local bikeId, bike = Transport.bikeOf(player)
		local def = if bikeId then Economy.findCar(bikeId) else nil
		return offer.total, if bike then bike.room else 0, if def then def.name else "bike"
	end
	if jobType and jobType.vehicle then
		local lent = Economy.findCar(jobType.vehicle)
		return need, Economy.capacity(jobType.vehicle, {}), if lent then lent.name else jobType.vehicle
	end
	local profile = PlayerData.get(player)
	local carId = if profile then profile.car else Config.Cars[1].id
	if not carId then
		return need, 0, "no vehicle"
	end
	local def = Economy.findCar(carId)
	-- 4.6: a Roof Rack on it takes one more light piece (Economy.capacity with the gear and the cargo's look).
	local gear = if profile then Economy.installedGear(profile.carGear, carId) else {}
	return need, Economy.capacity(carId, if profile then Economy.carLevels(profile.carUpgrades, carId) else {}, gear, offer.look), if def then def.name else "car"
end

-- 4.6: has the car that would do this job the Hand Trolley installed (gear; a lent company vehicle has none)?
local function trolleyFor(player: Player, offer: Offer): boolean
	local jobType = offer.jobType
	local profile = PlayerData.get(player)
	local carId = if profile then profile.car else nil
	if (jobType and jobType.vehicle) or not profile or not carId or offer.mode ~= "car" then
		return false
	end
	return Economy.installedGear(profile.carGear, carId).trolley == true
end

-- 4.8: the board's tip for a heavy cargo (by hand alone very slow), nil otherwise.
local function heavyTip(player: Player, offer: Offer): string?
	if not JobRules.hasRule(offer.rules, "heavy") then
		return nil
	end
	if trolleyFor(player, offer) then
		return "Heavy: put it on your hand trolley (a normal pace), or lift it with a crew mate."
	end
	return "Heavy: by hand alone you barely walk. A hand trolley (gear at Wrench Garage) or a crew mate lifting with you helps."
end

-- 4.0: a Freight Run's pallets, how many the player's equipped car takes at its stage (Freight.palletsOf) and its name.
local function palletsFor(player: Player, offer: Offer): (number, number, string)
	local profile = PlayerData.get(player)
	local carId = if profile then profile.car else Config.Cars[1].id
	if not carId then
		return offer.total, 0, "no vehicle" -- 5.0
	end
	local def = Economy.findCar(carId)
	local stage = Economy.stageOf(carId, if profile then Economy.carLevels(profile.carUpgrades, carId) else nil)
	return offer.total, Freight.palletsOf(carId, stage), if def then def.name else "car"
end

-- 3.4: why the player's car is too small for this job, or nil when it fits. 4.0: a Freight Run needs a vehicle that
-- takes its pallets. 5.0: a car job needs a vehicle; a foot job no more pieces than you carry.
local function slotsShort(player: Player, offer: Offer): string?
	if needsVehicle(player, offer) then
		return (vehicleLock(player))
	end
	local noBike = bikeLock(player, offer)
	if noBike then
		return noBike -- 5.1
	end
	if offer.round then
		return nil -- 5.3: the newspaper satchel takes the bundle
	end
	if offer.mode == "bike" then
		local _, room, name = slotsFor(player, offer)
		if offer.total <= room then
			return nil
		end
		return `This job has {offer.total} {offer.plural}: your {name}'s bag and yours hold {room}. Bike gear at Spoke & Chain (a basket, panniers) holds more.`
	end
	if offer.mode == "foot" then
		local _, room = slotsFor(player, offer)
		if offer.total <= room then
			return nil
		end
		return `This job has {offer.total} {offer.plural}: you carry {room}. A bigger bag (ZDC Bags at the depot) carries more.`
	end
	if Freight.isPallet(offer.kind) then
		local pallets, takes, carName = palletsFor(player, offer)
		if pallets <= takes then
			return nil
		end
		local text = Freight.lockText(pallets, carName, takes)
		return text
	end
	local need, holds, name = slotsFor(player, offer)
	if need <= holds then
		return nil
	end
	local profile = PlayerData.get(player)
	local carId = (if profile then profile.car else nil) or Config.Cars[1].id
	local stage = Economy.stageOf(carId, if profile then Economy.carLevels(profile.carUpgrades, carId) else nil)
	return `This job needs {need} cargo slots: your {name} holds {holds}. {Economy.roomAdvice(carId, stage, need)}`
end

-- 4.7: the licence tier an offer needs (Config.Jobs.Licences), nil when none: the board's ordinary deliveries and a
-- board special without a level of its own (the Winter Run). Never a mission or an employer's job (they have their
-- own levels).
local function licenceTier(offer: Offer): number?
	local jobType = offer.jobType
	if offer.mission or (jobType and (jobType.level ~= nil or jobType.mission ~= nil or (jobType.employer ~= nil and not jobType.board))) then
		return nil
	end
	return if JobRules.licence(offer.tier) then offer.tier else nil
end

-- 4.7: may the player take the board's jobs of this tier (a tier without a licence: yes)? A licence earned (its level
-- and its jobs) is marked held from then on (profile.licences).
local function hasLicence(player: Player, tierIndex: number): boolean
	local def = JobRules.licence(tierIndex)
	if not def then
		return true
	end
	local profile = PlayerData.get(player)
	if not profile then
		return false
	end
	local key = tostring(tierIndex)
	if profile.licences[key] then
		return true
	end
	if JobRules.hasLicence(tierIndex, PlayerData.level(player), profile.licences, profile.licenceJobs) then
		profile.licences[key] = true
		return true
	end
	return false
end

-- 4.7: what the board and the result say about a tier's licence: { tier, stars, have, need, level, atStars, held }.
local function licenceInfo(player: Player, tierIndex: number): { [string]: any }?
	local def = JobRules.licence(tierIndex)
	local profile = PlayerData.get(player)
	if not def or not profile then
		return nil
	end
	local have, need = JobRules.progress(tierIndex, profile.licenceJobs)
	return {
		tier = tierIndex,
		stars = string.rep("★", JobsConfig.Tiers[tierIndex].stars),
		have = have,
		need = need,
		level = def.level,
		atStars = string.rep("★", JobsConfig.Tiers[def.atTier].stars),
		held = profile.licences[tostring(tierIndex)] == true,
	}
end

-- 4.7: why a tier's licence is missing, in words.
local function licenceText(info: { [string]: any }): string
	return `{info.stars} jobs need the {info.stars} LICENCE: driver level {info.level} and {info.need} jobs rated ★★ or better at {info.atStars} or harder ({info.have} / {info.need} done).`
end

-- 3.7: the drive from `from` to the offer's first stop (manhattan, like the route).
local function approachFrom(from: Vector3, offer: Offer): number
	local first = offer.stops[1].address
	return Map.manhattan(from.X, from.Z, first.x, first.z)
end

-- 3.7: a board offer waits up to Config.Jobs.RefreshSeconds while you move about: its distance and its clock taken
-- from `from`. The pay stays what the board promised (moving about never makes it pay more); the clock gets the time
-- of the longer drive to the first stop when you are farther from it than where it was offered (the job's own time
-- rule, Economy.timeLimit's TimePerStud × the modifier's), and never less than it was offered with.
local function fromHere(offer: Offer, from: Vector3): (number, number)
	local extra = approachFrom(from, offer) - offer.approach
	local modifier = offer.modifier
	local perStud = if offer.mode == "foot" then 1 / math.max(1, JobsConfig.Foot.Speed)
		elseif offer.mode == "bike" then 1 / math.max(1, JobsConfig.Bike.Speed)
		else JobsConfig.TimePerStud -- (5.0: a walk; 5.1: a ride)
	local slower = math.max(0, extra) * perStud * (if modifier then modifier.timeMultiplier else 1)
	return math.max(0, offer.distance + extra), offer.time + math.floor(slower + 0.5)
end

-- ── 5.2: adding orders to a run ────────────────────────────────────────────

-- Only pieces carried by hand (no horses, people or pallets), at every stop?
local function carriedOnly(offer: Offer): boolean
	if Cargo.isPeople(offer.kind) or offer.kind == "horse" or Freight.isPallet(offer.kind) then
		return false
	end
	for _, stop in offer.stops do
		if stop.mode ~= "carry" then
			return false
		end
	end
	return true
end

local function isStackable(offer: Offer): boolean
	return JobRules.stackable({
		mode = offer.mode,
		tier = offer.tier,
		special = offer.jobType ~= nil,
		mission = offer.mission ~= nil,
		tutorial = offer.tutorial,
		duo = offer.duo,
		carried = carriedOnly(offer),
		round = offer.round == true, -- 5.3: a newspaper round is one order on its own
	})
end

-- Do the job's stops go in any order? An ordinary delivery's do; a special's, a mission's and the tutorial's go one
-- after the other, as before.
local function freeMode(offer: Offer): boolean
	return offer.jobType == nil and offer.mission == nil and not offer.tutorial
end

-- May this run take more orders (stops in any order, every open order stackable)?
local function runStacks(job: Job): boolean
	if not job.free then
		return false
	end
	for _, order in job.orders do
		if order.state == "open" and not isStackable(order.offer) then
			return false
		end
	end
	return true
end

-- What the player can take on a run of this mode: hands + bag on foot, the bike's bag + its gear + your bag, the car +
-- its gear (slotsFor). 5.2 review: kit bought during the run grows it, so every slot the board counts can be carried:
-- 6.6, bike gear (or getting on your bike on a foot run) the bike's bag (`job`: the run's Cargo.Info.rack); a bag is
-- Cargo's own (bagSync). It never shrinks: what is in it stays.
local function orderRoomOf(player: Player, offer: Offer, job: Job?): number
	local room: number
	if offer.mode == "foot" then
		room = Transport.footOf(player).room
	elseif offer.mode == "bike" then
		local _, bike = Transport.bikeOf(player)
		room = if bike then bike.room else 0
	else
		local _, holds = slotsFor(player, offer)
		return holds
	end
	local info = if job then job.cargo.info else nil
	if info and info.foot then
		-- (as startJob: the bike's own bag on a bike run, or a foot run while you ride; 6.6)
		local onBike = offer.mode == "bike" or Transport.riding(player)
		local rack = require(Shared.Bag).rack(offer.mode, onBike, Transport.bikeBagOf(player))
		if rack > (info.rack or 0) then
			info.rack = rack
			info.changed()
		end
	end
	return room
end

local function sum(list: { number }): number
	local n = 0
	for _, value in list do
		n += value
	end
	return n
end

local MODE_WORDS: { [string]: string } = { foot = "on-foot", bike = "bike", car = "car" }

-- May this offer go onto the player's run now? (true) or (false, the board's button, why in words).
local function stackCheck(player: Player, job: Job, offer: Offer): (boolean, string?, string?)
	local mode = job.offer.mode
	local words = MODE_WORDS[mode] or mode
	if not runStacks(job) then
		return false, "FINISH YOUR RUN", "This run takes no more orders (a special, a mission, a paper round or a ★★★ job): finish it first."
	elseif not isStackable(offer) then
		return false, "ONE AT A TIME", "Specials, missions, paper rounds and ★★★ or harder jobs are never added to a run: finish yours first."
	elseif offer.mode ~= mode then
		return false, `{string.upper(words)} ORDERS ONLY`, `Only other {words} runs can be added to your {words} run.`
	end
	local room = orderRoomOf(player, offer, job)
	local taken = outstanding(job)
	local used = sum(taken)
	local open = #openOrders(job)
	local max = JobRules.ordersMax(mode)
	local free = JobRules.orderRoom(room, taken)
	local ok, why = JobRules.canAddOrder(mode, open, offer.total, free)
	-- (6.6: every light piece fits your bag and the bike's: 5.3's "don't go in a backpack" room check is gone)
	if ok then
		return true, nil, nil
	end
	local text = if why == "full" then `You have {open} orders on the go: {max} at most on a {words} run. Deliver one first.`
		else `This order has {offer.total} {offer.plural}: your orders take {used} of your {room} slots, {free} left.`
	return false, JobRules.orderButton(why, used, room, open, max), text
end

stackInfo = function(player: Player, job: Job): { [string]: any }?
	if not job.free then
		return nil
	end
	local room = orderRoomOf(player, job.offer, job)
	local taken = outstanding(job)
	return {
		can = runStacks(job), -- the board may add orders (+ ADD ORDER)
		open = #taken,
		max = JobRules.ordersMax(job.offer.mode),
		room = room,
		used = sum(taken),
		free = JobRules.orderRoom(room, taken),
		mode = job.offer.mode,
	}
end

-- One card of the job board. A job above the player's level is shown LOCKED (locked, level): accepting it is refused.
-- 3.4: so is a job with more pieces than the car holds (slots, capacity, carName, tooBig). 3.7: `index` is the offer's
-- id (AcceptJob sends it back), its distance and time are from where the player is now (fromHere).
-- 5.2: `run`, the player's run that takes more orders: the card says + ADD ORDER (addOrder) or why not (orderButton,
-- orderText: NO ROOM (3/4 slots), ORDERS FULL (2/2), another kind of run).
local function describe(offer: Offer, from: Vector3, playerLevel: number, nightPay: number, player: Player, run: Job?): { [string]: any }
	local last = offer.stops[#offer.stops]
	local jobType = offer.jobType
	local vehicle = if jobType and jobType.vehicle then Economy.findCar(jobType.vehicle) else nil
	local need, holds, carName = slotsFor(player, offer)
	local distance, time = fromHere(offer, from)
	local tooBig = need > holds
	-- 4.0: a Freight Run is locked by pallets ("NEEDS N PALLETS", the board's lockText / lockButton), its slots are
	-- the pallets' (Config.Cargo.PalletSlots each).
	local lockText: string?, lockButton: string? = nil, nil
	local pallets = Freight.isPallet(offer.kind)
	if pallets then
		local count, takes, name = palletsFor(player, offer)
		need, holds, carName = count * Tuning.PalletSlots, takes * Tuning.PalletSlots, name
		tooBig = count > takes
		if tooBig then
			lockText, lockButton = Freight.lockText(count, name, takes)
		end
	end
	-- 4.7: the licence (the level first: a tier above your level says LEVEL).
	local licence = licenceTier(offer)
	local noLicence = licence ~= nil and offer.level <= playerLevel and not hasLicence(player, licence)
	local roleInfo = JobRules.roleInfo(offer.role)
	-- 5.0: a car job while you own no vehicle: locked like a job too big for the car ("NEEDS A VEHICLE").
	local noVehicle = needsVehicle(player, offer)
	if noVehicle then
		tooBig = true
		lockText, lockButton = vehicleLock(player)
	end
	-- 5.1: a BIKE job without a bike, or while your car is the one you drive.
	local bikeText, bikeButton = bikeLock(player, offer)
	if bikeText then
		tooBig = true
		lockText, lockButton = bikeText, bikeButton
	end
	local stackOk, stackButton, stackText = false, nil, nil
	if run then
		stackOk, stackButton, stackText = stackCheck(player, run, offer)
	end
	return {
		mode = offer.mode, -- 5.0: "foot" (the board's ON FOOT section) | "car"; 5.1: "bike" (the BIKE section)
		needsVehicle = if noVehicle then true else nil,
		needsBike = if bikeText then true else nil, -- 5.1
		locked = offer.level > playerLevel or noLicence,
		lockReason = if offer.level > playerLevel then "level" elseif noLicence then "licence" elseif noVehicle then "vehicle" elseif bikeText then "bike" else nil,
		licence = if noLicence and licence then licenceInfo(player, licence) else nil,
		role = offer.role, -- 4.7: the trade-off (short | long | risky | bulk) and its words
		roleName = if roleInfo then roleInfo.name else nil,
		roleIcon = if roleInfo then roleInfo.icon else nil,
		roleWhy = if roleInfo then roleInfo.why else nil,
		level = offer.level,
		slots = need,
		capacity = holds,
		carName = carName,
		tooBig = tooBig,
		lockText = lockText,
		lockButton = lockButton,
		pallets = if pallets then offer.total else nil,
		tip = Freight.trolleyTip(offer.kind, offer.total, offer.stops[1].mode, trolleyFor(player, offer)) or heavyTip(player, offer), -- 4.0: "a hand trolley helps" (4.6: or "use yours"; 4.8: heavy)
		special = jobType ~= nil, -- a special job (a board special: Cash Transport, Pizza Rush, Winter Run)
		timed = jobType ~= nil and jobType.timeLimit ~= nil, -- a rush: `time` is a fixed clock
		banditBoost = offer.boost, -- > 1: bandits want this cargo
		nightPay = if nightPay > 1.001 then nightPay else nil, -- it is night now: finished now, it pays this many times
		index = offer.id,
		stars = offer.tier,
		tierName = JobsConfig.Tiers[offer.tier].name,
		cargo = offer.cargo,
		customer = offer.customer,
		first = offer.stops[1].label,
		address = last.address.name,
		district = last.address.district,
		stops = #offer.stops,
		position = last.park,
		distance = math.floor(distance),
		pay = offer.pay,
		time = time,
		modifier = info(offer.modifier),
		jobType = info(jobType),
		vehicle = if vehicle then vehicle.name else nil,
		pieces = offer.total,
		piece = offer.piece,
		piecesName = offer.plural,
		handling = offer.stops[1].mode,
		itemKind = offer.kind,
		rules = offer.rules, -- 4.8: the cargo's rules (ids) and what they ask, the drops of a multi-drop delivery
		rulesText = JobRules.rulesText(offer.rules),
		drops = if offer.dests and not offer.round then #offer.stops - 1 else nil,
		peak = offer.peak, -- 5.3: the evening peak's pay multiplier (the board's chip)
		round = if offer.round then true else nil, -- 5.3: a newspaper round (its doors: `stops` - 1)
		addOrder = if stackOk then true else nil, -- 5.2
		orderButton = stackButton,
		orderText = stackText,
	}
end

-- 3.7: the board's order: ★ on top, then ★★, ★★★, ★★★★ (the specials at their stars, the locked ones in their place);
-- at the same stars the lower driver level first, the ordinary delivery before a special; else as they were made.
-- 5.0: the ON FOOT jobs on top. 5.1: then the BIKE jobs.
local MODE_ORDER: { [string]: number } = { foot = 1, bike = 2, car = 3 }
local function boardOrder(a: Offer, b: Offer): boolean
	local aMode, bMode = MODE_ORDER[a.mode] or 3, MODE_ORDER[b.mode] or 3
	if aMode ~= bMode then
		return aMode < bMode
	end
	if a.tier ~= b.tier then
		return a.tier < b.tier
	end
	if a.level ~= b.level then
		return a.level < b.level
	end
	local aSpecial, bSpecial = a.jobType ~= nil, b.jobType ~= nil
	if aSpecial ~= bSpecial then
		return bSpecial
	end
	return a.id < b.id
end

-- An offer on the board: its id and the drive to it from where it was offered.
local function stamp(offer: Offer, from: Vector3)
	nextOfferId += 1
	offer.id = nextOfferId
	offer.approach = approachFrom(from, offer)
end

-- 4.7: one tier's ordinary deliveries: one of every trade-off (JobRules.roles) when the player may take the tier
-- (its level and its licence), else one to show what is locked. 5.7, `only`: just one offer of that role (Jobs.refillBoard).
local function tierOffers(player: Player, from: Vector3, tierIndex: number, only: string?): { Offer }
	local out: { Offer } = {}
	local open = PlayerData.level(player) >= JobsConfig.Tiers[tierIndex].level and hasLicence(player, tierIndex)
	local roles: { string } = if open then JobRules.roles(function(): number
		return rng:NextNumber()
	end) else { "short" }
	if only and open then
		roles = { only }
	end
	-- 5.7: a ★ delivery takes as many pieces as your own car holds now (Config.Jobs.CarStep).
	local room: number? = nil
	local profile = PlayerData.get(player)
	local carId = if profile then profile.car else nil
	if tierIndex == 1 and profile and carId and not Transport.riding(player) then
		room = Economy.capacity(carId, Economy.carLevels(profile.carUpgrades, carId), Economy.installedGear(profile.carGear, carId))
	end
	for _, role in roles do
		local offer = ordinaryOffer(from, tierIndex, nil, role, room)
		if offer then
			table.insert(out, offer)
		end
	end
	return out
end

-- A new board for the player, from where they are now: up to two board specials and (4.7) three ordinary deliveries
-- of every danger level open to them (one of a locked one), sorted (boardOrder), each with its id; it stays until
-- refreshAt (Config.Jobs.RefreshSeconds).
local function makeBoard(player: Player): Board
	local from = playerPosition(player)
	local list: { Offer } = {}
	-- Board specials (JobTypeDef.board, or no employer: the Cash Transport, the Pizza Rush, the Winter Run): up to two
	-- of them, each with its chance (Config.Jobs.BoardSpecials), a different one each, locked ones included (the
	-- card says from which level).
	local boardJobs: { Config.JobTypeDef } = {}
	local level = PlayerData.level(player)
	for _, jobType in Config.JobTypes do
		if jobType.load == "pallet" then
			-- 4.0: the Freight Run is on every board from its level (locked "NEEDS N PALLETS" without a truck for it).
			if level >= Economy.jobLevel(jobType, jobType.tier) then
				local freight = jobOffer(from, jobType)
				if freight then
					table.insert(list, freight)
				end
			end
		elseif Economy.onBoard(jobType) then
			table.insert(boardJobs, jobType)
		end
	end
	for _, chance in JobsConfig.BoardSpecials do
		if #boardJobs == 0 or rng:NextNumber() >= chance then
			continue
		end
		local jobType = table.remove(boardJobs, rng:NextInteger(1, #boardJobs)) :: Config.JobTypeDef
		local special = jobOffer(from, jobType)
		if special then
			table.insert(list, special)
		end
	end
	-- 5.0: the ON FOOT section, always open: a choice of Foot.Offers (JobRules.roles), for what you carry.
	local room = Transport.footOf(player).room
	local footRoles = JobRules.roles(function(): number
		return rng:NextNumber()
	end)
	-- 5.3: in the morning a newspaper round too (Config.Jobs.Round), on foot and by bike.
	local rounds = require(Shared.Deliveries).inHours(JobsConfig.Round.Hours, DayNight.hour())
	local walks = 0
	for index = 1, math.max(1, JobsConfig.Foot.Offers) + (if rounds then 1 else 0) do
		local offer = footOffer(from, if rounds and index == 1 then "round" else footRoles[(index - (if rounds then 2 else 1)) % #footRoles + 1], room)
		if offer then
			table.insert(list, offer)
			walks += 1
		end
	end
	-- 5.3 review: no run on foot because the storefronts near you are shut (looked up to twice as far): the board says
	-- where to go instead.
	local footNote: string? = nil
	if walks == 0 then
		local foot = JobsConfig.Foot
		if require(Shared.Deliveries).closedNear(from.X, from.Z, (foot.PickupMax + foot.PickupWiden) * 2, DayNight.hour(), nil) then
			footNote = JobsConfig.Places.ClosedNote
		end
	end
	-- 5.1: the BIKE section from Bike.Level: a choice of Bike.Offers for what your bike holds (shown locked without a
	-- bike: sized for the smallest one).
	if level >= JobsConfig.Bike.Level then
		local _, bike = Transport.bikeOf(player)
		local bikeRoom = if bike then bike.room else JobsConfig.Bike.Pieces[1]
		local bikeRoles = JobRules.roles(function(): number
			return rng:NextNumber()
		end)
		-- (6.6: every light piece fits the bike's bag and yours: the bike's whole room, and the round)
		for index = 1, math.max(1, JobsConfig.Bike.Offers) + (if rounds then 1 else 0) do
			local offer = footOffer(from, if rounds and index == 1 then "round" else bikeRoles[(index - (if rounds then 2 else 1)) % #bikeRoles + 1], bikeRoom, nil, true)
			if offer then
				table.insert(list, offer)
			end
		end
	end
	-- 4.7: the ordinary deliveries of every danger level (tierOffers: a choice of three, one locked).
	for tierIndex = 1, #JobsConfig.Tiers do
		for _, offer in tierOffers(player, from, tierIndex) do
			table.insert(list, offer)
		end
	end
	for _, offer in list do
		stamp(offer, from)
	end
	table.sort(list, boardOrder)
	local board: Board = { list = list, refreshAt = workspace:GetServerTimeNow() + math.max(10, JobsConfig.RefreshSeconds), rerolled = {}, footNote = footNote }
	boards[player.UserId] = board
	return board
end

-- The player's board as it is now: the current one, or a new one when it expired (or there was none yet).
local function boardOf(player: Player): Board
	local board = boards[player.UserId]
	if not board or workspace:GetServerTimeNow() >= board.refreshAt then
		board = makeBoard(player)
	end
	return board
end

-- Sends the board (Net "Offers": the cards, and when the next offers come: refreshAt, server time).
local function sendBoard(player: Player, board: Board)
	local from = playerPosition(player)
	local level = PlayerData.level(player)
	local nightPay = Economy.nightScale(Config.DayNight.NightPay, DayNight.nightFactor())
	local out = {}
	local current = jobs[player]
	local run = if current and runStacks(current) then current else nil -- 5.2: a run that takes more orders
	for _, offer in board.list do
		table.insert(out, describe(offer, from, level, nightPay, player, run))
	end
	-- 4.7: every tier's REROLL (its fee, used already) and whether it is open, the licence of a locked one.
	local tiers = {}
	for index, tier in JobsConfig.Tiers do
		local open = level >= tier.level and hasLicence(player, index)
		table.insert(tiers, {
			stars = tier.stars,
			name = tier.name,
			fee = JobRules.rerollFee(tier.stars),
			rerolled = board.rerolled[index] == true,
			open = open,
			level = tier.level,
			licence = if open then nil else licenceInfo(player, index),
		})
	end
	local profile = PlayerData.get(player)
	-- 5.0: what you carry on foot (the ON FOOT section's "HANDS 2 / BAG 4") and whether you have a vehicle.
	local foot = Transport.footOf(player)
	local carry = { hands = Config.Cargo.HandsMax, room = foot.room, pack = math.max(0, foot.room - Config.Cargo.HandsMax), speed = foot.speedMult }
	local hasCar = profile ~= nil and profile.car ~= nil
	-- 5.1: your bike (its name, what it holds with its gear and your bag) and whether you ride it now.
	local bikeId, bike = Transport.bikeOf(player)
	local bikeDef = if bikeId then Economy.findCar(bikeId) else nil
	local bikeInfo = if bikeDef and bike then { id = bikeDef.id, name = bikeDef.name, room = bike.room, riding = Transport.riding(player) } else nil
	Net.get("Offers"):FireClient(player, out, board.refreshAt, { tiers = tiers, streak = if profile then profile.streak else 0, foot = carry, hasCar = hasCar, ownsCar = ownsCar(player), bike = bikeInfo, bikeLevel = JobsConfig.Bike.Level, run = if run then stackInfo(player, run) else nil, footNote = board.footNote })
end

-- A new board now, sent to the player (3.7: the client cannot ask for this; RequestOffers sends the current board).
function Jobs.makeOffers(player: Player)
	sendBoard(player, makeBoard(player))
end

-- 5.7: after a run the board is not stale: every offer taken from it (Board.taken) gets a new one of its kind in its
-- place (the same section and danger level, the same trade-off), made from where the player is now; the other offers
-- stay until refreshAt. A board about to expire waits for refreshBoards. Pushed to the player (open or not).
function Jobs.refillBoard(player: Player)
	local board = boards[player.UserId]
	local taken = if board then board.taken else nil
	if not board or not taken or jobs[player] or not player.Parent then
		return
	end
	board.taken = nil
	if workspace:GetServerTimeNow() >= board.refreshAt - 5 then
		return
	end
	local from = playerPosition(player)
	local added = 0
	for _, old in taken do
		local role = if old.round then "round" else old.role
		local fresh: Offer? = nil
		if old.mode == "foot" then
			fresh = footOffer(from, role, Transport.footOf(player).room)
		elseif old.mode == "bike" then
			local _, bike = Transport.bikeOf(player)
			fresh = footOffer(from, role, if bike then bike.room else JobsConfig.Bike.Pieces[1], nil, true)
		elseif old.jobType == nil and old.mission == nil and not old.tutorial then
			fresh = tierOffers(player, from, old.tier, role or "short")[1]
		end
		if fresh then
			stamp(fresh, from)
			table.insert(board.list, fresh)
			added += 1
		end
	end
	if added > 0 then
		table.sort(board.list, boardOrder)
		sendBoard(player, board)
	end
end

-- 4.7, REROLL (Net "RerollTier", tier): that tier's ordinary offers on the player's board made again, for
-- Choice.RerollFee × its stars, once per tier until the board refreshes. Not during a job, not a tier the player may
-- not take; the specials stay. The board is sent again either way.
local function reroll(player: Player, tierIndex: any)
	if type(tierIndex) ~= "number" or tierIndex ~= tierIndex or tierIndex % 1 ~= 0 or tierIndex < 1 or tierIndex > #JobsConfig.Tiers then
		return
	end
	if jobs[player] then
		notice:FireClient(player, "Finish your current delivery first.")
		return
	end
	local board = boards[player.UserId]
	if not board or workspace:GetServerTimeNow() >= board.refreshAt then
		sendBoard(player, boardOf(player))
		return
	end
	local tier = JobsConfig.Tiers[tierIndex]
	local stars = string.rep("★", tier.stars)
	local fee = JobRules.rerollFee(tier.stars)
	if board.rerolled[tierIndex] then
		notice:FireClient(player, `The {stars} jobs were rerolled already. New ones come with the next board.`)
	elseif PlayerData.level(player) < tier.level or not hasLicence(player, tierIndex) then
		notice:FireClient(player, `The {stars} jobs are locked for you: nothing to reroll.`)
	elseif not PlayerData.spend(player, fee) then
		notice:FireClient(player, `A reroll of the {stars} jobs costs ${fee}.`)
	else
		board.rerolled[tierIndex] = true
		local from = playerPosition(player)
		local list: { Offer } = {}
		for _, offer in board.list do
			if offer.jobType ~= nil or offer.tier ~= tierIndex or offer.mode ~= "car" then -- (5.0: the foot jobs stay; 5.1: the bike jobs)
				table.insert(list, offer)
			end
		end
		for _, offer in tierOffers(player, from, tierIndex) do
			stamp(offer, from)
			table.insert(list, offer)
		end
		table.sort(list, boardOrder)
		board.list = list
		notice:FireClient(player, `New {stars} jobs on the board (-${fee}).`)
	end
	sendBoard(player, board)
end

-- 3.7: every second (update): a board whose time is up gets new offers, pushed to its player (open or not, so the
-- board shows them at once). Not during a job: the first tick after it. Boards of players who left go when they expire.
local function refreshBoards(now: number)
	local here: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		here[player.UserId] = true
		local board = boards[player.UserId]
		if board and now >= board.refreshAt and not jobs[player] then
			sendBoard(player, makeBoard(player))
		end
	end
	for userId, board in boards do
		if not here[userId] and now >= board.refreshAt then
			boards[userId] = nil
		end
	end
end

-- ── Running a job ──────────────────────────────────────────────────────────

function Jobs.active(player: Player): boolean
	return jobs[player] ~= nil
end

-- 5.0: is the player's job an on-foot one (their own car may still be called: it is not needed for the job)? 5.1: a
-- bike job too (its pieces ride in the pack, not in the bike: MY BIKE may bring the bike again).
function Jobs.isFoot(player: Player): boolean
	local job = jobs[player]
	return job ~= nil and job.offer.mode ~= "car"
end

-- 5.0: a company vehicle lent for a job that is over stays with nobody: when the player has one out but no job lends
-- it any more (a respawn, the CAR button after the job), it goes back. True when it went.
function Jobs.returnLent(player: Player): boolean
	local car = Vehicles.get(player)
	if not car or not car.lent then
		return false
	end
	local job = jobs[player]
	local jobType = job and job.offer.jobType
	if jobType and jobType.vehicle == car.id then
		return false
	end
	Vehicles.remove(player)
	return true
end

local function planOf(stop: Stop): Cargo.Plan
	local person = stop.person
	return {
		stage = stop.kind,
		mode = stop.mode,
		needed = stop.needed,
		park = stop.park,
		pile = stop.pile,
		facing = stop.facing,
		person = if person then Cargo.look(person.role, person.name, person.title) else nil,
		hold = stop.hold,
		keep = stop.keep,
		staging = stop.staging,
		-- 5.3, real places
		personAt = stop.personAt,
		door = stop.door,
		nobody = stop.nobody,
		toss = stop.toss,
		bundle = stop.bundle,
		place = stop.address.name,
	}
end

-- 5.2: a new order of the job: its offer, its stops (indices into the job's offer), its clock from now.
local function newOrder(job: Job, offer: Offer, stops: { number }): Order
	job.nextOrder += 1
	local order: Order = {
		id = job.nextOrder,
		offer = offer,
		endsAt = workspace:GetServerTimeNow() + offer.time,
		stops = stops,
		pieces = offer.total,
		state = "open",
		paid = 0,
		rating = nil,
		freshness = 1,
		wrecked = false,
		condition = 1,
		addOn = false,
	}
	table.insert(job.orders, order)
	return order
end

-- 5.2: where the pieces made at the pick-up `index` go (the order's drop, or 4.8's multi-drop customers) and the
-- customers' names for their FOR tags (a multi-drop delivery, or several orders on the run). Nil on a job whose stops
-- go one after the other or with several pick-ups: any drop of the order takes them.
local function destsFor(job: Job, order: Order, index: number): ({ number }?, { [number]: string }?)
	local offer = job.offer
	local pickups = 0
	local drops: { number } = {}
	for _, at in order.stops do
		if offer.stops[at].kind == "drop" then
			table.insert(drops, at)
		else
			pickups += 1
		end
	end
	if not job.free or pickups ~= 1 or #drops == 0 then
		return nil, nil
	end
	local dests: { number } = {}
	local own = order.offer.dests -- (4.8: the order's own stop numbers, 2 … its last)
	if own then
		for n, rel in own do
			dests[n] = order.stops[rel] or drops[#drops]
		end
	else
		for n = 1, offer.stops[index].needed do
			dests[n] = drops[1]
		end
	end
	if not own and #job.orders <= 1 then
		return dests, nil
	end
	local names: { [number]: string } = {}
	for _, at in drops do
		local person = offer.stops[at].person
		names[at] = if person then person.name else order.offer.customer
	end
	return dests, names
end

-- 5.2: the Plan of the job's stop `index` for Cargo: its number and order, the order's cargo, where its pieces go.
local function planFor(job: Job, index: number): Cargo.Plan
	local stop = job.offer.stops[index]
	local plan = planOf(stop)
	local order = orderAt(job, index)
	local mine = order.offer
	plan.index = index
	plan.order = order.id
	plan.kind, plan.look, plan.name = mine.kind, mine.look, mine.piece
	plan.heavy = if JobRules.hasRule(mine.rules, "heavy") then JobsConfig.CargoRules.HeavyCarrySpeed else nil
	if stop.kind == "pickup" then
		plan.dests, plan.destNames = destsFor(job, order, index)
	end
	return plan
end

-- 5.2: an order added to a run (the board's + ADD ORDER, a road event's add-on): its stops go at the end of the job's
-- list (a copy: the board's offer shares it), its pieces count in the job's total.
local function appendOrder(job: Job, offer: Offer): Order
	local stops = table.clone(job.offer.stops)
	local indices: { number } = {}
	for _, stop in offer.stops do
		table.insert(stops, stop)
		table.insert(indices, #stops)
	end
	job.offer.stops = stops
	job.offer.total += offer.total
	job.cargo.info.total += offer.total
	job.dirty = true
	return newOrder(job, offer, indices)
end

-- Is `player` in the crew `owner` invited into the job (server/Crew.luau)?
local function isMember(owner: Player, player: Player): boolean
	return table.find(Crew.members(owner), player) ~= nil
end

-- Everybody paid on this job besides the owner, still in the game: the invited crew members, then who rode in the
-- owner's car and stayed with it (each once), Config.Crew.MaxMembers at most (the pay, co-op and its enemies).
local function crewOf(job: Job, owner: Player): { Player }
	local list = {}
	for _, member in Crew.members(owner) do
		if member ~= owner and member.Parent and not table.find(list, member) then
			table.insert(list, member)
		end
	end
	for rider in job.crew do
		if #list >= Config.Crew.MaxMembers then
			break
		end
		if rider ~= owner and rider.Parent and not table.find(list, rider) then
			table.insert(list, rider)
		end
	end
	return list
end

-- ── 3.1: the challenges' counters (server/Challenges.luau, wired in Main) ───

-- Set by Main: count a stat (shared/Challenges.luau Counters) for a player. Never blocks the job (task.spawn).
Jobs.onStat = nil :: ((player: Player, stat: string, amount: number) -> ())?

local function stat(player: Player, name: string, amount: number)
	local hook = Jobs.onStat
	if hook and amount > 0 then
		task.spawn(hook, player, name, amount)
	end
end

-- 3.7, set by server/Tutorial.luau: a job of `player` ended, told to the owner only (not the crew). `ok` true when it
-- was delivered and paid (complete, also when only part of the cargo arrived), false when it failed or was cancelled
-- (Jobs.fail: the clock, the cargo gone, GIVE UP). Every job the player owns: the board's, an employer's, a mission,
-- the tutorial's (one job at a time, so the one that ends is the one started). Not called when the owner leaves the
-- game with it or an admin start replaces it. Never blocks the job (task.spawn).
Jobs.onDelivered = nil :: ((player: Player, ok: boolean) -> ())?

local function tellDelivered(player: Player, ok: boolean)
	local hook = Jobs.onDelivered
	if hook then
		task.spawn(hook, player, ok)
	end
end

-- Is `who` with the owner: in the owner's car, or within Config.Crew.RiderRange of them (on foot or in a car of their
-- own following along)?
local function withOwner(owner: Player, who: Player): boolean
	local car = Vehicles.seatedIn(who)
	if car and car.owner == owner then
		return true
	end
	local a, b = playerPosition(owner), playerPosition(who)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude <= Config.Crew.RiderRange
end

-- The same stat for the owner and the crew who are with them now (crewOf, withOwner: like the finish's `present`, not
-- who stayed home).
local function statCrew(owner: Player, job: Job, name: string, amount: number)
	stat(owner, name, amount)
	for _, member in crewOf(job, owner) do
		if withOwner(owner, member) then
			stat(member, name, amount)
		end
	end
end

-- Who rode along stays on the job only while they are with it (withOwner): not on a job of their own or in another
-- crew, not far off, and not after leaving the owner's crew (or being taken out of it). Every tick.
local function pruneRiders(player: Player, job: Job)
	local members: { [Player]: boolean } = {}
	for _, member in Crew.members(player) do
		members[member] = true
	end
	for rider in job.crew do
		local leader = Crew.ownerOf(rider)
		local leftCrew = job.members[rider] and not members[rider]
		if not rider.Parent or jobs[rider] or (leader and leader ~= player) or leftCrew or not withOwner(player, rider) then
			job.crew[rider] = nil
		end
	end
	job.members = members
end

-- 4.8: the road event of a job is over: the survivor still waving goes, the add-on's card closes. `text`: told.
local function endEvent(player: Player, job: Job, text: string?)
	local npc = job.eventNpc
	if npc then
		job.eventNpc = nil
		Npcs.remove(npc)
	end
	if job.eventState == "asked" and player.Parent then
		roadEventRemote:FireClient(player, nil)
	end
	job.event = nil
	job.eventState = nil
	job.eventSpot = nil
	job.addOn = nil
	job.dirty = true
	if text then
		notice:FireClient(player, text)
	end
end

local function endJob(player: Player, job: Job, linger: boolean)
	jobs[player] = nil
	endEvent(player, job, nil) -- 4.8
	freeDocks(player) -- 4.0: its loading dock and receiving pad
	Cargo.finish(job.cargo, linger)
	DuoGates.clear(player) -- 3.2: the twin-lever gate, if any
	Zombies.release(player) -- its zombies roam on, its bandits stand down
	require(script.Parent.RunEvents).finish(player) -- 5.7: a survivor still calling, a locked gate
	task.defer(Jobs.refillBoard, player) -- 5.7: new offers where the taken ones were (after the result)
	Vehicles.setSpeedMultiplier(player, 1)
	-- 3.0: the crew stays together (no Crew.disband): the next mission is one START away.
	-- A company vehicle goes back; your own car comes to you. 5.0: without a car of your own the lent one just goes
	-- (Vehicles.spawn would refuse with "no vehicle yet" and leave it with you) unless a new job lends the same one.
	local jobType = job.offer.jobType
	if jobType and jobType.vehicle then
		local car = Vehicles.get(player)
		if car and car.id == jobType.vehicle then
			task.delay(2, function()
				if not player.Parent or Vehicles.get(player) ~= car then
					return
				end
				local profile = PlayerData.get(player)
				if profile and profile.car == nil then
					if Jobs.vehicleFor(player) ~= car.id then
						Vehicles.remove(player)
					end
				elseif not jobs[player] then
					Vehicles.spawn(player, true)
				end
			end)
		end
	end
end

-- The names of a job's twists ("HOT ZONE + HUNTED"), "" without any.
local function twistNames(offer: Offer): string
	local names: { string } = {}
	local jobType = offer.jobType
	for _, twist in twistList(jobType) do
		local twistInfo = Config.Missions.Twists[twist]
		if twistInfo then
			table.insert(names, twistInfo.name)
		end
	end
	return table.concat(names, " + ")
end

-- 3.2: the stop is blocked (Cargo.setBlocked) while a defend is still to hold there or its twin-lever gate is shut
-- (at the same last drop both count). The reason goes as setBlocked's third argument for a Cargo that takes one
-- (stream C's `reason`); FALLBACK: called untyped, so a Cargo.setBlocked(session, blocked) without it ignores it.
local function blockStop(job: Job)
	local offer = job.offer
	local defending = offer.twists.defend == true and job.stop == #offer.stops and not job.defendDone
	local blocked = defending or job.gateClosed
	local reason = if defending then "Hold out first! Nothing gets unloaded until the area is safe."
		elseif job.gateClosed then "Pull both levers together first! One of you on each lever."
		else nil
	local setBlocked: any = Cargo.setBlocked
	setBlocked(job.cargo, blocked, reason)
end

-- 3.2, switches: does the job's stop `index` have a twin-lever gate?
local function gatedStop(offer: Offer, index: number): boolean
	local stop = offer.stops[index]
	if not offer.gates or not stop then
		return false
	end
	if offer.gates == "pickup" then
		return stop.kind == "pickup"
	end
	return index == #offer.stops
end

-- 3.2, switches: the gate of the job's current stop (server/DuoGates.luau), built when the job gets to it; the one of
-- the stop before goes.
local function placeGate(player: Player, job: Job)
	DuoGates.clear(player)
	job.gateClosed = false
	job.gatePulled = 0
	if not gatedStop(job.offer, job.stop) then
		return
	end
	local stop = job.offer.stops[job.stop]
	job.gateClosed = true
	DuoGates.build(player, tostring(job.stop), stop.pile, stop.facing, job.allowed, function()
		local current = jobs[player]
		if current then
			current.dirty = true
		end
	end)
end

-- 4.0: a Freight Run takes its loading dock and its receiving pad now (freeDock, dockStop; given back by endJob). The
-- stops are copied first: the board's offer shares them.
local function placeDocks(player: Player, offer: Offer)
	local stops = table.clone(offer.stops)
	for index, original in stops do
		local id = original.dock
		local hub = if id then Map.FreightDocks[id] else nil
		if id and (hub or Map.ReceivingDocks[id]) then
			local stop = table.clone(original)
			local n, row, key = freeDock(id, if hub and stop.kind == "pickup" then #hub.docks else 1)
			if not docksInUse[key] then
				docksInUse[key] = player
			end
			dockStop(stop, n, row)
			stops[index] = stop
		end
	end
	offer.stops = stops
end

-- Starts the job. False and why not (no notice: the caller tells the player).
local function startJob(player: Player, offer: Offer): (boolean, string?)
	local jobType = offer.jobType
	local foot = offer.mode == "foot" or offer.mode == "bike" -- 5.0: no vehicle at all (5.1: the bike's room is the pack)
	local bikeText = bikeLock(player, offer)
	if bikeText then
		return false, bikeText -- 5.1: no bike, or your car is the one you drive
	elseif foot then
		-- (your car, if you have one, stays where it is: it takes no part)
	elseif needsVehicle(player, offer) then
		return false, (vehicleLock(player))
	elseif jobType and jobType.vehicle then
		-- The employer lends its vehicle, right next to you.
		local err = Vehicles.spawn(player, true, jobType.vehicle)
		if err then
			return false, err
		end
	else
		local car = Vehicles.get(player)
		if not car then
			return false, "Call your car first (CAR button)."
		end
		-- 3.4: still in the company vehicle of the last job (endJob brings your own car 2 s later): the job was
		-- checked against your equipped car (slotsShort, Missions), so that one does it, right here.
		local profile = PlayerData.get(player)
		if profile and car.id ~= profile.car then
			local err = Vehicles.spawn(player, true)
			if err then
				return false, err
			end
		end
	end
	local crew: { [Player]: boolean } = {}
	local handles = false
	for _, stop in offer.stops do
		if not foot and (stop.mode == "carry" or stop.mode == "lead" or stop.mode == "pallet") then -- (4.0: pallets on a jack)
			handles = true
		end
	end
	local job: Job
	local function allowed(other: Player): boolean
		-- The owner, who rode along, and the invited crew.
		return other == player or crew[other] == true or isMember(player, other)
	end
	local cargoInfo: Cargo.Info = {
		kind = offer.kind,
		look = offer.look,
		piece = offer.piece,
		plural = offer.plural,
		total = offer.total,
		handles = handles,
		allowed = allowed,
		changed = function()
			local current = jobs[player]
			if current then
				current.dirty = true
			end
		end,
		lift = offer.twists.lift == true,
	}
	-- 3.2, the pair twist (stream C: Cargo.Info.pair). FALLBACK: set untyped, so a Cargo.Info without the field still
	-- type-checks; once it has it this can be a plain field above.
	cargoInfo.pair = offer.twists.pair == true
	-- 4.8: a heavy cargo is slow by hand alone; a multi-drop delivery's pieces are labelled for their customers.
	cargoInfo.heavy = if JobRules.hasRule(offer.rules, "heavy") then JobsConfig.CargoRules.HeavyCarrySpeed else nil
	-- 6.0: a fragile cargo (the rule, the FRAGILE modifier) is never thrown at a door (server/Cargo.luau).
	cargoInfo.fragile = if JobRules.hasRule(offer.rules, "fragile") or (offer.modifier ~= nil and offer.modifier.id == "fragile") then true else nil
	cargoInfo.dests = offer.dests
	cargoInfo.destNames = offer.destNames
	-- 5.0, on foot: no vehicle; the pieces over the hands ride in the owner's pack. 6.6: your bag (Cargo's session, the
	-- active bag's room) and, on a bike run or a foot run while your bike is your vehicle, the bike's own bag (its rack,
	-- basket or box with its bike gear: a pickup goes onto it while the bike is within reach, getting on it loads your
	-- hands onto it). A newspaper round's bundle goes into its satchel.
	cargoInfo.foot = if foot then true else nil
	local riding = Transport.riding(player)
	local rack = require(Shared.Bag).rack(offer.mode, riding, Transport.bikeBagOf(player))
	cargoInfo.rack = if foot and rack > 0 then rack else nil
	cargoInfo.satchel = if foot and offer.round then offer.total else nil
	local session = Cargo.begin(player, cargoInfo)
	local crewCount = #Crew.members(player)
	local members: { [Player]: boolean } = {}
	for _, member in Crew.members(player) do
		members[member] = true
	end
	job = {
		offer = offer,
		endsAt = workspace:GetServerTimeNow() + offer.time,
		condition = 1,
		kills = 0,
		stop = 1,
		guards = false,
		wave = 0,
		waveIn = JobsConfig.FirstWave,
		-- Wanted cargo (banditBoost): the first roadblock and the first chase come sooner too.
		nextAmbush = os.clock() + 12 / offer.boost,
		nextChase = os.clock() + 20 / offer.boost,
		dirty = false,
		stealNotice = 0,
		stealMeter = 0,
		cargo = session,
		crew = crew,
		members = members,
		footSince = nil,
		nextFoot = 0,
		footWarned = false,
		lastStep = "",
		crewCount = crewCount,
		enemyScale = if offer.coop then Economy.coopEnemies(crewCount) else 1,
		gunnerKills = 0,
		guarded = {},
		defendLeft = nil,
		defendDone = false,
		defendInside = false,
		defendWho = "the receiver",
		defendWave = 0,
		nextDefendWave = 0,
		quietNotice = {},
		shots = 0,
		piecesCounted = 0,
		owner = player,
		allowed = allowed,
		duoTeamed = crewCount >= Config.Missions.Duo.MinCrew,
		gateClosed = false,
		gatePulled = 0,
		wrecked = false,
		freshness = 1,
		lastSpeed = 0,
		joltCar = nil,
		joltAt = 0,
		ruleNotice = 0,
		-- 4.8: never on the tutorial's delivery or a mission (5.0: nor on foot)
		event = if offer.tutorial or offer.mission or foot then nil else JobRules.pickEvent(rng:NextNumber(), rng:NextNumber()),
		eventAt = JobRules.eventAfter(rng:NextNumber()),
		eventTries = 0,
		driven = 0,
		eventState = nil,
		eventUntil = 0,
		eventSpot = nil,
		eventNpc = nil,
		eventName = "",
		addOn = nil,
		nextStray = os.clock() + (if offer.mode == "bike" then JobsConfig.Bike else JobsConfig.Foot).StrayEvery * rng:NextNumber(0.8, 1.2),
		orders = {},
		nextOrder = 0,
		free = freeMode(offer),
		stopsDone = {},
		pinned = nil,
		switchAt = 0,
		killsPaid = 0,
	}
	jobs[player] = job
	-- 5.7: everything after this runs in a pcall: an error here must not strand the player with a half-made job (the
	-- 5.4.1 kind of bug). On failure the job ends, the HUD hears it, the player is told and the Output warned.
	local ok, err = pcall(function()
		placeDocks(player, offer)
		-- 5.2: the first order. A run that may take more keeps the order's own offer (its stops, pieces, pay) apart from
		-- the job's, which gets the stops of the orders added later; a job of stops one after the other is its only order.
		local all: { number } = {}
		for index in offer.stops do
			table.insert(all, index)
		end
		newOrder(job, if job.free then table.clone(offer) else offer, all)
		-- No pick-up: the vehicle starts loaded.
		if offer.stops[1].kind ~= "pickup" then
			Cargo.fill(session, offer.total)
		end
		Cargo.setStop(session, planFor(job, 1))
		-- Defend: the last drop unloads only after holding out (a job of one drop: from the start). 3.2, switches: the
		-- first stop's gate if it has one.
		placeGate(player, job)
		blockStop(job)
		Vehicles.setSpeedMultiplier(player, if offer.modifier then offer.modifier.speedMultiplier else 1)
		send(player)
		local title = if jobType then jobType.name else ""
		if offer.mission then
			local twists = twistNames(offer)
			title = `MISSION: {title}{if twists ~= "" then ` ({twists})` else ""}{if offer.duo then " · DUO" elseif offer.coop then " · CO-OP" else ""}`
		end
		local text = if jobType then `{title}: {offer.stops[1].label}` else offer.stops[1].label
		if jobType and jobType.timeLimit then
			text ..= ` · {math.floor(offer.time / 60)}:{string.format("%02d", offer.time % 60)} on the clock!`
		elseif offer.boost > 1 then
			text ..= " · Every bandit in town wants this cargo!"
		end
		notice:FireClient(player, text)
		-- The invited crew hears about it too (their HUD follows the owner's job: server/Crew.luau, Jobs.crewStatus).
		for _, member in Crew.members(player) do
			if offer.mission then
				notice:FireClient(member, `{title} with {player.DisplayName}. Help them out!`)
			else
				notice:FireClient(member, `{player.DisplayName} took a job: {if jobType then jobType.name else offer.cargo}. Help them out!`)
			end
		end
		require(script.Parent.RunEvents).begin(player, offer.mode, offer.tutorial, offer.mission) -- 5.7: life on foot
	end)
	if not ok then
		warn(`[Jobs] startJob failed for {player.Name}: {err}`)
		if jobs[player] == job then
			endJob(player, job, false)
		end
		send(player)
		notice:FireClient(player, "That job could not start. Pick another one from the board.")
		return false, nil
	end
	return true, nil
end

-- startJob for the job board and the employers: a refusal is told to the player.
local function startOrTell(player: Player, offer: Offer): boolean
	local ok, err = startJob(player, offer)
	if not ok and err then
		notice:FireClient(player, err)
	end
	return ok
end

-- Can this player take a job of their own now? (Not with one running, not in somebody else's crew, not above their
-- level.) Says why not.
local function canTake(player: Player, level: number): boolean
	if jobs[player] then
		notice:FireClient(player, "Finish your current delivery first.")
		return false
	end
	local owner = Crew.ownerOf(player)
	if owner and owner ~= player then
		notice:FireClient(player, `You are in {owner.DisplayName}'s crew. Help with their job, or leave the crew (K) to take your own.`)
		return false
	end
	if level > PlayerData.level(player) then
		notice:FireClient(player, `Locked: this job needs level {level} ({Levels.rank(level)}). Deliver more to level up!`)
		return false
	end
	return true
end

-- Takes an offer the way the job board does (3.7: the tutorial's delivery too): the checks (canTake, slotsShort) and
-- startJob, every refusal told to the player.
local function takeOffer(player: Player, offer: Offer): boolean
	if not canTake(player, offer.level) then
		return false
	end
	-- 4.7: the ★★★ / ★★★★ board jobs need their licence.
	local licence = licenceTier(offer)
	if licence and not hasLicence(player, licence) then
		local info = licenceInfo(player, licence)
		notice:FireClient(player, if info then `Locked: {licenceText(info)}` else "Locked: this job needs a licence.")
		return false
	end
	local short = slotsShort(player, offer)
	if short then
		notice:FireClient(player, short)
		return false
	end
	return startOrTell(player, offer)
end

-- 5.2: an offer added to the player's run as another order (the board's + ADD ORDER): the board's checks (its level,
-- its licence, what it needs: slotsShort) and the run's (stackCheck: a run that takes more, the same mode, a free order
-- slot and the room). Its clock starts now. False (and told) when it may not.
local function addOrder(player: Player, job: Job, offer: Offer): boolean
	if offer.level > PlayerData.level(player) then
		notice:FireClient(player, `Locked: this job needs level {offer.level} ({Levels.rank(offer.level)}). Deliver more to level up!`)
		return false
	end
	local licence = licenceTier(offer)
	if licence and not hasLicence(player, licence) then
		notice:FireClient(player, "Locked: this job needs a licence.")
		return false
	end
	local short = slotsShort(player, offer)
	if short then
		notice:FireClient(player, short)
		return false
	end
	local ok, _, why = stackCheck(player, job, offer)
	if not ok then
		notice:FireClient(player, why or "Finish your current delivery first.")
		return false
	end
	local order = appendOrder(job, offer)
	local open = #openOrders(job)
	local text = `ORDER ADDED ({open} on the go): {offer.cargo} for {offer.customer}, ${offer.pay} · {Economy.clock(offer.time)} on its clock. {offer.stops[1].label}`
	notice:FireClient(player, text)
	for _, member in Crew.members(player) do
		notice:FireClient(member, `{player.DisplayName} took another order: {offer.cargo}. Help them out!`)
	end
	job.switchAt = 0
	send(player)
	return order ~= nil
end

-- AcceptJob: the offer with that id (3.7) on the player's board. Taken from where the player is now (fromHere: the
-- same pay, more time for a longer drive to it); once started it leaves the board (the rest stay until refreshAt).
-- 5.2: on a run that takes more orders it is added to it (addOrder).
local function accept(player: Player, id: any)
	local job = jobs[player]
	local board = boards[player.UserId]
	if job and not runStacks(job) then
		notice:FireClient(player, "Finish your current delivery first.")
		if board then
			sendBoard(player, board) -- (5.2 review: the board hid the row on + ADD ORDER: it comes back as it is)
		end
		return
	end
	if type(id) ~= "number" or not board then
		return
	end
	local offer: Offer? = nil
	for _, candidate in board.list do
		if candidate.id == id then
			offer = candidate
			break
		end
	end
	if not offer then
		-- Taken already, or the board got new offers meanwhile: the board as it is now.
		notice:FireClient(player, "That job is no longer on the board.")
		sendBoard(player, boardOf(player))
		return
	end
	local taken = table.clone(offer)
	taken.distance, taken.time = fromHere(offer, playerPosition(player))
	if if job then addOrder(player, job, taken) else takeOffer(player, taken) then
		local at = table.find(board.list, offer)
		if at then
			table.remove(board.list, at)
		end
		-- 5.7: a new one of its kind comes in its place after the run (Jobs.refillBoard).
		local list = board.taken or {}
		table.insert(list, offer)
		board.taken = list
		if job then
			sendBoard(player, board) -- (5.2: the other rows' + ADD ORDER / NO ROOM follow the room left)
		end
	elseif job then
		sendBoard(player, board) -- (5.2 review: refused: the row the board hid on + ADD ORDER comes back, and why not)
	end
end

-- Work for an employer: taken at their board.
local function acceptEmployer(player: Player, employerId: any)
	if type(employerId) ~= "string" then
		return
	end
	local employer = Economy.findEmployer(employerId)
	local spot = Map.EmployerSpots[employerId]
	local position = playerPosition(player)
	if not employer or not spot or Vector3.new(position.X - spot.x, 0, position.Z - spot.z).Magnitude > Map.EmployerRadius + 20 then
		return
	end
	local jobType = Economy.findJobType(employer.jobType)
	if not canTake(player, Economy.jobLevel(jobType, if jobType then jobType.tier else 1)) then
		return
	end
	local offer = jobType and jobOffer(position, jobType)
	if not offer then
		notice:FireClient(player, "No work right now, try again.")
		return
	end
	startOrTell(player, offer)
end

-- XP for a job (Levels.jobXp, PlayerData.addXp): what the DeliveryResult says about it.
local function giveXp(player: Player, amount: number): XpInfo
	local level, levelUp = PlayerData.addXp(player, amount)
	return { xp = amount, level = level, rank = Levels.rank(level), levelUp = levelUp }
end

-- The result table with the XP fields added.
local function withXp(result: { [string]: any }, xp: XpInfo): { [string]: any }
	result.xp = xp.xp
	result.level = xp.level
	result.rank = xp.rank
	result.levelUp = xp.levelUp
	return result
end

function Jobs.fail(player: Player, reason: string)
	local job = jobs[player]
	if not job then
		return
	end
	local crew = crewOf(job, player)
	-- A failed job still gives a share of the XP (Config.Levels.XpFailed), once something was done: a job cancelled
	-- right after accepting gives none. 5.2 review: only for the orders still open (JobRules.failedWork: their pieces
	-- handed over, the kills no order paid); something done is a stop of theirs or a piece of theirs with you (a job of
	-- stops one after the other: a piece in the car or the pack, a stop passed, as before).
	local status = Cargo.status(job.cargo)
	local kills = math.max(0, job.kills - job.killsPaid)
	local withYou = Cargo.ordersWithYou(job.cargo)
	local work: { JobRules.OrderWork } = {}
	for _, order in job.orders do
		local progress = status.inCar > 0 or status.pack > 0 or job.stop > 1 -- (5.0: the pack)
		if job.free then
			progress = (withYou[order.id] or 0) > 0
			for _, index in order.stops do
				progress = progress or job.stopsDone[index] == true
			end
		end
		table.insert(work, { id = order.id, open = order.state == "open", delivered = Cargo.deliveredOf(job.cargo, order.id), progress = progress })
	end
	local delivered, worked = JobRules.failedWork(work, kills)
	-- 5.2: every order still open fails with it (the ones paid stay paid); the card names the focused one.
	local offer = focusOrder(job).offer
	for _, order in job.orders do
		if order.state == "open" then
			order.state = "failed"
		end
	end
	local xp = if worked then Levels.jobXp(offer.tier, delivered, kills, DayNight.isNight(), false) else 0
	endJob(player, job, false)
	send(player)
	-- 4.7: a failed job (not a mission) ends the streak of good jobs.
	local profile = PlayerData.get(player)
	local streakLost = 0
	if profile and not offer.mission and profile.streak > 0 then
		streakLost = profile.streak
		profile.streak = 0
	end
	resultRemote:FireClient(player, withXp({
		success = false,
		reason = reason,
		cargo = offer.cargo,
		stars = offer.tier,
		streakLost = if streakLost > 0 then streakLost else nil,
	}, giveXp(player, xp)))
	for _, member in crew do
		resultRemote:FireClient(member, withXp({
			success = false,
			rider = true,
			driver = player.DisplayName,
			reason = `{player.DisplayName}'s delivery failed: {reason}`,
			cargo = offer.cargo,
			stars = offer.tier,
		}, giveXp(member, xp)))
	end
	tellDelivered(player, false) -- 3.7: Jobs.onDelivered
end

-- 5.2: the board as it is now, sent again while the player is on a run that takes more orders (its + ADD ORDER and
-- NO ROOM buttons follow the orders). Not a new board: the one they have, until it expires.
local function resendBoard(player: Player)
	local board = boards[player.UserId]
	local job = jobs[player]
	if board and job and runStacks(job) and workspace:GetServerTimeNow() < board.refreshAt then
		sendBoard(player, board)
	end
end

-- The crew paid with an order and who of them is there at its finish (in the car or near the owner): the mission's
-- credit goes to them, not to who stayed home.
local function crewNow(job: Job, player: Player): ({ Player }, { Player })
	local crew = crewOf(job, player) -- (before endJob: the riders' seats and the members as they are now)
	local present: { Player } = {}
	for _, member in crew do
		if withOwner(player, member) then
			table.insert(present, member)
		end
	end
	return crew, present
end

-- 5.2: one order paid (it was split out of 3.0 – 4.8's complete): its pay by the pieces that arrived and their
-- condition, the clock it had left, the kills since the last order paid, the night; its rating, the owner's streak and
-- licences, the employer's reward, the XP; the crew's shares; its DeliveryResult (`midJob` while other orders go on:
-- client/Hud.luau shows it as a toast); a mission's stars and rewards. `final`: the job ended with it (endJob first).
local function payOrder(player: Player, job: Job, order: Order, crew: { Player }, present: { Player }, final: boolean)
	local offer = order.offer
	local session = job.cargo
	local timeLeft = order.endsAt - workspace:GetServerTimeNow()
	local delivered = Cargo.deliveredOf(session, order.id)
	local lost = Cargo.lostOf(session, order.id)
	-- The kills no order paid yet (5.2 review: an add-on leaves them to the run's real orders, unless it is the last).
	local kills = if order.addOn and not final then 0 else math.max(0, job.kills - job.killsPaid)
	job.killsPaid += kills
	-- 5.2 review: on a run of several orders each one's own cargo condition (a job of one order: the job's, as before).
	local condition = if job.free then order.condition else job.condition
	order.state = "done"
	for _, index in order.stops do
		job.stopsDone[index] = true
	end
	if job.pinned == order.id then
		job.pinned = nil
	end
	-- A co-op mission pays more for every crew member besides the owner (everybody's share grows with it).
	local coopPay = if offer.coop then Economy.coopPay(#crew) else 1
	local pay = Economy.cargoPay(math.floor(offer.pay * coopPay + 0.5), delivered, order.pieces)
	-- Finished at night: the pay is up (smoothly at dusk and dawn).
	local nightPay = Economy.nightScale(Config.DayNight.NightPay, DayNight.nightFactor())
	local night = DayNight.isNight()
	-- The gunner twist: a kill from a passenger seat counts GunnerKillBonus times in the kill bonus.
	local payout = Economy.payout(pay, condition, timeLeft, offer.time, Economy.paidKills(kills, job.gunnerKills), nightPay)
	-- A mission is rated (1 – 3 stars): the cargo's condition and the clock left.
	local stars = Missions.rate(condition, if offer.time > 0 then math.max(0, timeLeft) / offer.time else 0)
	local missionResult = if offer.mission
		then { id = offer.mission, name = if offer.jobType then offer.jobType.name else offer.mission, stars = stars }
		else nil
	-- 4.7: an ordinary or special job (not a mission) is rated ★ … ★★★ (JobRules.rate): the pay × the rating plus the
	-- owner's streak of good jobs, the XP × the rating; a good one counts toward the owner's licences.
	local profile = PlayerData.get(player)
	-- 4.8: food is rated and paid by its freshness too (JobRules.freshPay: the pay × FreshPayMin … 1).
	local freshness = if JobRules.hasRule(offer.rules, "food") then order.freshness else nil
	-- (5.2 review: a road event's add-on is not rated: no streak step, no licence progress)
	local rating = if offer.mission or order.addOn then nil else JobRules.rate(condition, if offer.time > 0 then math.max(0, timeLeft) / offer.time else 0, order.wrecked, lost, freshness)
	local payTotal = payout.total
	local freshCut = 0
	if freshness then
		payTotal = math.floor(payout.total * JobRules.freshPay(freshness) + 0.5)
		freshCut = payTotal - payout.total
	end
	local ratingInfo: { [string]: any }? = nil
	if rating then
		local streak = JobRules.nextStreak(if profile then profile.streak else 0, rating.stars)
		local total, ratingPart, streakPart = JobRules.ratedPay(payTotal, rating.stars, streak)
		payTotal = total
		if profile then
			profile.streak = streak
			JobRules.countJob(profile.licenceJobs, offer.tier, rating.stars)
		end
		order.rating = rating.stars
		ratingInfo = {
			stars = rating.stars,
			checks = rating.checks, -- { { text, ok } }: why
			ratingPay = ratingPart, -- + or − money
			streak = streak,
			streakBonus = if rating.stars >= 2 then JobRules.streakBonus(streak) else 0,
			streakPay = streakPart,
			freshness = freshness, -- 4.8: food: its freshness (0 … 1) and what it took off the pay (≤ 0)
			freshPay = if freshness then freshCut else nil,
		}
	end
	if offer.round then
		-- 5.3, the newspaper round: the tip for no paper in the bushes (a line in the rating's checks).
		payTotal += JobRules.roundTip(Cargo.missesOf(session, order.id))
		if ratingInfo then
			table.insert(ratingInfo.checks, JobRules.roundCheck(Cargo.missesOf(session, order.id)))
		end
	end
	-- 6.7: the Courier Vest: the customer tips a share of the pay (Config.Kit tips; every delivery but a mission)
	if not offer.mission then
		local tip = JobRules.kitTip(payTotal, Transport.tipShareOf(player))
		if tip > 0 then
			payTotal += tip
			if ratingInfo then
				table.insert(ratingInfo.checks, JobRules.kitTipCheck(tip))
			end
		end
	end
	local driverTotal, share = Economy.crewSplit(payTotal, #crew)
	order.paid = driverTotal
	-- The split, for everybody's result: the owner first.
	local split = { { name = player.DisplayName, pay = driverTotal } }
	for _, member in crew do
		table.insert(split, { name = member.DisplayName, pay = share })
	end
	local xp = Levels.jobXp(offer.tier, delivered, kills, night, true)
	if offer.mode == "bike" then
		xp = JobRules.bikeXp(xp) -- 5.1
	elseif JobRules.carStep(offer.mode, offer.tier, offer.jobType ~= nil or offer.mission ~= nil) and not order.addOn then
		xp = JobRules.carStepXp(xp) -- 5.7: the step up to a car
	end
	if rating then
		xp = JobRules.ratedXp(xp, rating.stars)
	end
	local employerInfo: { [string]: any }? = nil
	local unlockedWeapon: string? = nil
	if profile then
		profile.deliveries += 1
		-- Work for an employer: after enough jobs their gun and their vehicle are yours.
		local employer = if offer.jobType and offer.jobType.employer then Economy.findEmployer(offer.jobType.employer) else nil
		if employer then
			local done = (profile.rep[employer.id] or 0) + 1
			profile.rep[employer.id] = done
			local unlocked: string? = nil
			local rewardCar = Economy.findCar(employer.reward)
			if rewardCar and not profile.cars[rewardCar.id] and done >= employer.needed then
				PlayerData.giveCar(player, rewardCar.id)
				unlocked = rewardCar.name
				notice:FireClient(player, `{employer.name} gives you the {rewardCar.name}! It needs no garage slot: take it out at the depot lot or one of your garages.`)
			end
			local weapon = if employer.weapon then Economy.findWeapon(employer.weapon) else nil
			if weapon and done >= (employer.weaponAt or employer.needed) and not profile.weapons[weapon.id] then
				PlayerData.giveWeapon(player, weapon.id)
				unlockedWeapon = weapon.name
				notice:FireClient(player, `{employer.person} gives you the {weapon.name}! Pick it on the weapon bar (T).`)
			end
			employerInfo = {
				name = employer.name,
				done = done,
				needed = employer.needed,
				reward = if rewardCar then rewardCar.name else "",
				unlocked = unlocked,
				weapon = if weapon then weapon.name else nil,
				weaponAt = employer.weaponAt,
				unlockedWeapon = unlockedWeapon,
			}
		end
	end
	PlayerData.addMoney(player, driverTotal)
	if final then
		send(player)
	else
		job.dirty = true
	end
	local ownerXp = giveXp(player, xp)
	-- 4.7: the licences after the XP (a level-up may open one): earned now, else the next one's progress.
	if ratingInfo and profile then
		for _, def in Config.Jobs.Licences do
			local key = tostring(def.tier)
			if profile.licences[key] then
				continue
			end
			local earned = hasLicence(player, def.tier)
			local info = licenceInfo(player, def.tier)
			if info then
				info.earned = earned
				ratingInfo.licence = info
			end
			if earned then
				notice:FireClient(player, `{string.rep("★", def.tier)} LICENCE earned: the {JobsConfig.Tiers[def.tier].name} jobs are on your board.`)
			end
			break
		end
	end
	-- 5.2: an order done while others go on (the HUD shows it as a toast, not the result window).
	local left = #openOrders(job)
	local orderInfo = if final and #job.orders <= 1 then nil else { id = order.id, left = left }
	resultRemote:FireClient(player, withXp({
		employer = employerInfo,
		success = true,
		mode = offer.mode, -- 5.7: a foot or bike run shows as a toast and a float (client/Hud.luau showResult)
		midJob = if final then nil else true,
		order = orderInfo,
		cargo = offer.cargo,
		customer = offer.customer,
		stars = offer.tier,
		condition = condition,
		kills = kills,
		payout = payout, -- with nightBonus
		night = night,
		crew = split, -- { { name, pay } }: everybody paid on this job, the owner first
		riders = #crew, -- crew members besides you
		crewBonus = driverTotal - payTotal,
		total = driverTotal,
		delivered = delivered, -- pieces that arrived
		pieces = order.pieces, -- pieces of the order
		lost = lost,
		piece = offer.piece,
		piecesName = offer.plural,
		unlockedWeapon = unlockedWeapon,
		mission = missionResult, -- 3.0: { id, name, stars } of a mission
		coopPay = if offer.coop then coopPay else nil, -- a co-op mission: the pay × this for the crew
		rating = ratingInfo, -- 4.7: { stars, checks, ratingPay, streak, streakBonus, streakPay, licence? } (not a mission)
	}, ownerXp))
	for _, member in crew do
		local memberProfile = PlayerData.get(member)
		if memberProfile then
			memberProfile.deliveries += 1
		end
		PlayerData.addMoney(member, share)
		resultRemote:FireClient(member, withXp({
			success = true,
			rider = true,
			mode = offer.mode, -- 5.7
			midJob = if final then nil else true,
			order = orderInfo,
			driver = player.DisplayName,
			cargo = offer.cargo,
			customer = offer.customer,
			stars = offer.tier,
			night = night,
			crew = split,
			total = share,
			mission = missionResult,
			rating = if rating then { stars = rating.stars } else nil, -- 4.7: the owner's rating of the job
		}, giveXp(member, xp)))
	end
	local missionId = offer.mission
	-- 3.1: the missions' counters for who finished it (the owner and the crew there), before the rewards check them.
	if missionId then
		local finishers = table.clone(present)
		table.insert(finishers, 1, player)
		local timed = offer.jobType ~= nil and offer.jobType.timeLimit ~= nil
		local quiet = offer.twists.quiet == true and job.shots == 0
		for _, who in finishers do
			if #finishers > 1 then
				stat(who, "coopMissions", 1)
			end
			if night then
				stat(who, "nightMissions", 1)
			end
			if stars >= 3 then
				stat(who, "perfect", 1)
			end
			if timed then
				stat(who, "rushes", 1)
			end
			if quiet then
				stat(who, "quietMissions", 1)
			end
		end
	end
	-- The mission's rewards and stars (server/Missions.luau), after the pay: the owner and everybody paid with them.
	local onMission = Jobs.onMissionComplete
	if missionId and onMission then
		local ok, err = pcall(function()
			onMission(player, missionId, stars, present)
		end)
		if not ok then
			warn(`[Jobs] onMissionComplete failed: {err}`)
		end
	end
end

-- The job is done: its last open order paid (5.2: the earlier ones were paid as they were done), the job over.
local function complete(player: Player, job: Job)
	local last: Order? = nil
	for _, order in job.orders do
		if order.state == "open" then
			last = order
		end
	end
	local crew, present = crewNow(job, player)
	endJob(player, job, true)
	if last then
		payOrder(player, job, last, crew, present, true)
	else
		send(player)
	end
	tellDelivered(player, true) -- 3.7: Jobs.onDelivered, after the pay
end

-- 5.2: an order done while others go on: paid now, the run goes on.
local function settleOrder(player: Player, job: Job, order: Order)
	local crew, present = crewNow(job, player)
	payOrder(player, job, order, crew, present, false)
	resendBoard(player)
end

-- 5.2: one order failed while others go on (its clock ran out, nothing of it is left): its pieces go back, its stops
-- are skipped, the streak of good jobs ends (4.7), a notice and a short card (no XP). The run goes on.
local function failOrder(player: Player, job: Job, order: Order, reason: string)
	local offer = order.offer
	order.state = "failed"
	for _, index in order.stops do
		job.stopsDone[index] = true
	end
	if job.pinned == order.id then
		job.pinned = nil
	end
	Cargo.dropOrder(job.cargo, order.id)
	local profile = PlayerData.get(player)
	local streakLost = 0
	if profile and not offer.mission and not order.addOn and profile.streak > 0 then -- (5.2 review: not for an add-on)
		streakLost = profile.streak
		profile.streak = 0
	end
	resultRemote:FireClient(player, {
		success = false,
		midJob = true,
		order = { id = order.id, left = #openOrders(job) },
		reason = reason,
		cargo = offer.cargo,
		customer = offer.customer,
		stars = offer.tier,
		streakLost = if streakLost > 0 then streakLost else nil,
	})
	local text = `ORDER LOST · {offer.cargo} for {offer.customer}: {reason}{if streakLost > 0 then " Your streak is over." else ""}`
	notice:FireClient(player, text)
	for _, member in Crew.members(player) do
		notice:FireClient(member, text)
	end
	job.dirty = true
	resendBoard(player)
end

-- The job a player is on right now: their own, the one of the crew they were invited into, or the one of the car they
-- ride in.
local function currentOwner(player: Player): Player?
	if jobs[player] then
		return player
	end
	local crewOwner = Crew.ownerOf(player)
	if crewOwner and jobs[crewOwner] then
		return crewOwner
	end
	local car, driving = Vehicles.seatedIn(player)
	if car and not driving and jobs[car.owner] then
		return car.owner
	end
	return nil
end

-- The job a kill counts for: currentOwner, or the one they rode along on and help on foot.
local function jobOwner(player: Player): Player?
	local current = currentOwner(player)
	if current then
		return current
	end
	for owner, job in jobs do
		if job.crew[player] then
			return owner
		end
	end
	return nil
end

-- On a job, or in the crew of one (the people go after them: Zombies.hunts).
function Jobs.involved(player: Player): boolean
	return jobOwner(player) ~= nil
end

-- 5.5: on a mission (their own or their crew's)? The city bus does not take them (server/Buses.luau).
function Jobs.onMission(player: Player): boolean
	local owner = jobOwner(player)
	local job = if owner then jobs[owner] else nil
	return job ~= nil and job.offer.mission ~= nil
end

function Jobs.onKill(player: Player)
	local owner = jobOwner(player)
	local job = owner and jobs[owner]
	if owner and job then
		job.kills += 1
		job.dirty = true
		-- The gunner twist: a kill from a passenger seat of the owner's car (never the driver's).
		if job.offer.twists.gunner then
			local car, driving = Vehicles.seatedIn(player)
			if car and not driving and car.owner == owner then
				job.gunnerKills += 1
			end
		end
	end
end

-- Spotless: below Config.Missions.SpotlessFail the mission fails at once. True when it failed.
local function spotlessFailed(player: Player, job: Job): boolean
	if not job.offer.twists.spotless or job.condition >= Config.Missions.SpotlessFail or jobs[player] ~= job then
		return false
	end
	Jobs.fail(player, `SPOTLESS failed: the cargo is down to {math.floor(job.condition * 100)} % (it had to stay above {math.floor(Config.Missions.SpotlessFail * 100 + 0.5)} %).`)
	return true
end

-- A shot by anybody (server/Gun.luau Gun.onShot). The quiet twist: every shot of the job's people (the owner, the
-- crew, whoever sits in the owner's car now: currentOwner, not who rode along once) costs cargo condition; the
-- dynamite goes off at 0.
function Jobs.onShot(player: Player)
	local owner = currentOwner(player)
	local job = owner and jobs[owner]
	if not owner or not job or not job.offer.twists.quiet then
		return
	end
	job.shots += 1
	job.condition = math.max(0, job.condition - Config.Missions.QuietCost)
	job.dirty = true
	local now = os.clock()
	if now - (job.quietNotice[player] or 0) > 2.5 then
		job.quietNotice[player] = now
		notice:FireClient(player, `Careful! Dynamite! Every shot costs {math.floor(Config.Missions.QuietCost * 100 + 0.5)} % of the cargo.`)
	end
	if job.condition <= 0 then
		Jobs.fail(owner, "BOOM! The dynamite went off. No shooting meant NO SHOOTING.")
		return
	end
	spotlessFailed(owner, job)
end

-- The company vehicle the job lent (CAR brings it back after a wreck), or nil for your own car.
function Jobs.vehicleFor(player: Player): string?
	local job = jobs[player]
	local jobType = job and job.offer.jobType
	return if jobType then jobType.vehicle else nil
end

-- The cargo loses `share` of its condition: the job's (the HUD, a mission's twists) and, 5.2 review, each open order's
-- whose pieces ride in the vehicle (JobRules.ordersHit: on a run of several orders one not picked up yet keeps its
-- own). With a `reason` the job fails at 0 (people: they had enough) and a spotless mission below its line; without one
-- (a hit, a jolt of a crate) it only counts.
local function loseCondition(player: Player, job: Job, share: number, reason: string?)
	job.condition = math.max(0, job.condition - share)
	job.dirty = true
	local work: { JobRules.OrderWork } = {}
	for _, order in job.orders do
		table.insert(work, { id = order.id, open = order.state == "open", delivered = 0, progress = false })
	end
	for _, id in JobRules.ordersHit(work, Cargo.ordersWithYou(job.cargo, true), job.free) do
		local order = orderById(job, id)
		if order then
			order.condition = math.max(0, order.condition - share)
		end
	end
	if not reason then
		return
	end
	if job.condition <= 0 then
		Jobs.fail(player, reason)
		return
	end
	spotlessFailed(player, job)
end

-- Bandits next to the car carry the cargo off, piece by piece (the kids and a patient only get scared).
function Jobs.steal(player: Player, share: number)
	local job = jobs[player]
	if not job or Cargo.status(job.cargo).inCar == 0 then
		return
	end
	local now = os.clock()
	if Cargo.isPeople(job.offer.kind) then
		local patient = job.offer.kind == "patient"
		local survivor = job.offer.kind == "survivor"
		if now - job.stealNotice > 4 then
			job.stealNotice = now
			notice:FireClient(player, if patient then "Bandits at the ambulance! Get the patient out of here!"
				elseif survivor then "Bandits at the car! The survivors are panicking, get them out of here!"
				else "Bandits at the bus! The kids are scared, get them out of here!")
		end
		loseCondition(player, job, share, if patient then "The bandits got to the ambulance. The patient didn't make it."
			elseif survivor then "The bandits dragged the survivors off!"
			else "The bandits scared the kids away!")
		return
	end
	if now - job.stealNotice > 4 then
		job.stealNotice = now
		notice:FireClient(player, "The bandits are stealing your cargo! Get away or shoot them!")
	end
	job.stealMeter += share * Tuning.StealPieceRate
	if job.stealMeter >= 1 then
		job.stealMeter -= 1
		local name = Cargo.steal(job.cargo)
		if name then
			notice:FireClient(player, `A bandit grabbed {article(name)} from the back!`)
		end
	end
end

-- A wrecked car does not end the job: some pieces are ruined, the rest go into the next car (press CAR).
function Jobs.onCarWrecked(player: Player)
	local job = jobs[player]
	if not job or job.offer.mode ~= "car" then
		return -- (5.0: a foot job's cargo is not in the car; 5.1: nor a bike job's)
	end
	job.wrecked = true -- 4.7: the rating
	-- 5.2 review: the orders whose pieces are in the car (a job of one order: it, as before), before the crash ruins any.
	local work: { JobRules.OrderWork } = {}
	for _, order in job.orders do
		table.insert(work, { id = order.id, open = order.state == "open", delivered = 0, progress = false })
	end
	for _, id in JobRules.ordersHit(work, Cargo.ordersWithYou(job.cargo, true), job.free) do
		local order = orderById(job, id)
		if order then
			order.wrecked = true
		end
	end
	notice:FireClient(player, "Your car is wrecked! Press CAR and keep going, the clock is ticking.")
	if Cargo.isPeople(job.offer.kind) then
		if Cargo.status(job.cargo).inCar > 0 then
			local reason = if job.offer.kind == "patient" then "The crash was too much for the patient."
				elseif job.offer.kind == "survivor" then "The crash was too much for the survivors."
				else "The crash scared the kids away."
			loseCondition(player, job, Config.BanditCar.WreckCargoLoss, reason)
		end
		return
	end
	local lost = Cargo.wreck(job.cargo, Config.BanditCar.WreckCargoLoss)
	if lost > 0 then
		notice:FireClient(player, `The crash ruined {if lost == 1 then article(job.offer.piece) else `{lost} {job.offer.plural}`}.`)
	end
end

function Jobs.onCarDamaged(player: Player, amount: number)
	local job = jobs[player]
	local car = Vehicles.get(player)
	if job and car and job.offer.mode == "car" then -- (5.0: a foot job's cargo is not in the car; 5.1: nor a bike job's)
		local modifier = job.offer.modifier
		local multiplier = if modifier then modifier.conditionMultiplier else 1
		-- 4.8: a fragile cargo hit at speed loses more; Ratchet Straps cut every loss from driving (JobRules.damageLoss).
		local velocity = car.chassis.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local base = amount / car.stats.health * JobsConfig.ConditionPerDamage * multiplier
		local rules = rulesNow(job) -- (5.2: every open order's)
		loseCondition(player, job, JobRules.damageLoss(rules, base, speed, Vehicles.hasGear(car, "straps")), nil)
		local now = os.clock()
		if JobRules.hasRule(rules, "fragile") and speed >= JobsConfig.CargoRules.HitSpeed and now - job.ruleNotice >= JobsConfig.CargoRules.NoticeEvery then
			job.ruleNotice = now
			notice:FireClient(player, "CAREFUL — FRAGILE! Every hit at speed breaks more of the cargo.")
		end
	end
end

-- A bandit roadblock on the road ahead of a moving car. 4.8: true when it was set up (a blocked street, the road
-- event, may have no bandits: size 0).
local function ambush(player: Player, position: Vector3, heading: Vector3?, size: number): boolean
	if not heading then
		return false
	end
	local flat = Vector3.new(heading.X, 0, heading.Z)
	if flat.Magnitude < 10 then
		return false
	end
	local forward = flat.Unit
	local ahead = position + forward * JobsConfig.AmbushDistance
	local x, z, dx, dz = Map.nearestRoad(ahead.X, ahead.Z)
	local spot = Vector3.new(x, World.RoadTop, z)
	if Map.isSafe(x, z) or (spot - position).Magnitude < 100 then
		return false
	end
	local along = Vector3.new(dx, 0, dz)
	if along:Dot(forward) < 0 then
		along = -along
	end
	Zombies.roadblock(player, spot, along, size)
	return true
end

-- Pieces the pick-ups after the current stop will still add.
local function futurePieces(job: Job): number
	local n = 0
	for index = job.stop + 1, #job.offer.stops do
		local stop = job.offer.stops[index]
		if stop.kind == "pickup" then
			n += stop.needed
		end
	end
	return n
end

local function advance(player: Player, job: Job)
	local offer = job.offer
	local stop = offer.stops[job.stop]
	job.stop += 1
	job.footSince = nil
	if stop.dock and stop.kind == "pickup" then
		freeDocks(player, stop.dock) -- 4.0: loaded, the loading dock is free for the next Freight Run
	end
	local nextStop = offer.stops[job.stop]
	Cargo.setStop(job.cargo, planFor(job, job.stop))
	-- Defend: the last drop unloads only after holding out there. 3.2, switches: this stop's gate if it has one.
	placeGate(player, job)
	blockStop(job)
	job.dirty = true
	local gate = if job.gateClosed then " · 🎛 TWIN SWITCHES: pull both levers there together!" else ""
	notice:FireClient(player, if stop.kind == "pickup" then `All loaded! Now: {nextStop.label}{gate}` else `Done! Next: {nextStop.label}{gate}`)
end

-- The next zombie wave around you and ahead of you. No room (too many of yours alive, or the server is full): it
-- waits a little and the number does not go up, so the waves never stack.
local function sendWave(player: Player, job: Job, tier: Config.TierDef, position: Vector3, heading: Vector3?, multiplier: number)
	local number = job.wave + 1
	-- Co-op: the wave and the cap of the alive ones grow with the crew (job.enemyScale), not how often they come.
	local scale = job.enemyScale
	local room = Economy.waveAlive(tier, multiplier * scale) - Zombies.countFor(player, true) -- the roadblocks' bandits do not count
	local size = math.min(math.floor(Economy.waveSize(tier, number, multiplier) * scale + 0.5), room)
	local made = if size > 0 then Zombies.spawnAround(player, position, heading, size, tier.waveKinds) else 0
	if made <= 0 then
		job.waveIn = JobsConfig.WavePostpone
		return
	end
	job.wave = number
	job.waveIn = Economy.waveEvery(tier, multiplier) * rng:NextNumber(0.9, 1.1)
	job.dirty = true
	statCrew(player, job, "waves", 1)
	notice:FireClient(player, `WAVE {number} · {made} {if made == 1 then "zombie" else "zombies"}`)
end

-- Tells the owner and the invited crew.
local function tellJob(player: Player, text: string)
	notice:FireClient(player, text)
	for _, member in Crew.members(player) do
		notice:FireClient(member, text)
	end
end

-- The hordes waiting at the stops: the last one's (the tier's guardHorde), and with the guarded twist one at every
-- stop (Economy.guardedHorde), spawned when the owner gets within GuardTriggerDistance. Co-op: × job.enemyScale.
local function spawnHordes(player: Player, job: Job, tier: Config.TierDef, stop: Stop, lastStop: boolean, flatDistance: number)
	if flatDistance >= JobsConfig.GuardTriggerDistance then
		return
	end
	local outward = Vector3.new(stop.address.nx, 0, stop.address.nz)
	if job.offer.twists.guarded then
		if job.guarded[job.stop] then
			return
		end
		job.guarded[job.stop] = true
		job.guards = job.guards or lastStop
		local count = Economy.guardedHorde(tier, job.enemyScale)
		if lastStop then
			count = math.max(count, math.floor(tier.guardHorde * job.enemyScale + 0.5))
		end
		Zombies.spawnGuards(player, stop.park, outward, count, tier.kinds)
		tellJob(player, `HOT ZONE! {count} of them are waiting at the stop.`)
	elseif lastStop and not job.guarded[job.stop] and tier.guardHorde > 0 then
		-- (5.2: every order's last drop has its horde: guarded by stop)
		job.guards = true
		job.guarded[job.stop] = true
		Zombies.spawnGuards(player, stop.park, outward, math.floor(tier.guardHorde * job.enemyScale + 0.5), tier.kinds)
	end
end

-- Does somebody of the job (the owner, the invited crew, whoever rode along) stand on foot, alive, within the
-- defend radius of `at`?
local function holdingArea(player: Player, job: Job, at: Vector3): boolean
	local people = crewOf(job, player)
	table.insert(people, player)
	for _, who in people do
		local character = who.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 and humanoid.SeatPart == nil then
			if Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z).Magnitude <= Config.Missions.DefendRadius then
				return true
			end
		end
	end
	return false
end

-- The defend twist at the last drop (Cargo.setBlocked holds the unloading): it starts when the owner (or somebody of
-- the job on foot) gets within DefendRadius of the receiver; the clock runs while somebody holds the area on foot;
-- a wave comes around the stop every DefendWaveEvery s meanwhile. Held long enough: the unloading goes on.
local function defendStep(player: Player, job: Job, tier: Config.TierDef, stop: Stop, position: Vector3, now: number, step: number, multiplier: number)
	local tuning = Config.Missions
	local inside = holdingArea(player, job, stop.pile)
	if job.defendLeft == nil then
		local near = Vector3.new(position.X - stop.pile.X, 0, position.Z - stop.pile.Z).Magnitude <= tuning.DefendRadius
		if not inside and not near then
			return
		end
		job.defendLeft = job.offer.defendTime
		job.defendWho = if stop.person then stop.person.name else "the receiver"
		job.nextDefendWave = now + 3
		job.dirty = true
		tellJob(player, `HOLD OUT! Keep {job.defendWho} safe for {Economy.clock(job.offer.defendTime)}: stay on foot within {tuning.DefendRadius} studs.`)
	end
	local before = math.ceil(job.defendLeft or 0)
	if inside ~= job.defendInside then
		job.defendInside = inside
		job.dirty = true
	end
	if not inside then
		return -- leaving the area pauses the clock (and the waves: they do not pile up for nobody)
	end
	local left = (job.defendLeft or 0) - step
	job.defendLeft = left
	if math.ceil(left) ~= before then
		job.dirty = true
	end
	if now >= job.nextDefendWave and left > 2 then
		job.nextDefendWave = now + tuning.DefendWaveEvery * rng:NextNumber(0.9, 1.1)
		local number = job.defendWave + 1
		local room = Economy.waveAlive(tier, multiplier * job.enemyScale) - Zombies.countFor(player, true)
		local size = math.min(math.floor(Economy.waveSize(tier, number, multiplier) * job.enemyScale + 0.5), room)
		local made = 0
		for _ = 1, math.max(0, size) do
			local spot = Zombies.findSpot(stop.park, nil, 55, 110)
			if spot and Zombies.spawn(Economy.pickKind(tier.waveKinds, rng:NextNumber()), spot, player, false) then
				made += 1
			end
		end
		if made > 0 then
			job.defendWave = number
			statCrew(player, job, "waves", 1)
			tellJob(player, `HOLD THE LINE! {made} {if made == 1 then "zombie" else "zombies"} coming at you`)
		end
	end
	if left <= 0 then
		job.defendDone = true
		job.dirty = true
		statCrew(player, job, "defends", 1) -- HOLD OUT won
		blockStop(job)
		tellJob(player, if job.gateClosed then "The area is safe! Now pull both levers together to open the gate!" else "The area is safe! Unload, quick!")
	end
end

-- On foot at a stop: a few come at you, far enough to put it down and shoot (G). Co-op: more of them.
local function footWave(player: Player, job: Job, tier: Config.TierDef, stop: Stop, now: number, multiplier: number)
	local wave = Tuning.FootWaves[job.offer.tier] or Tuning.FootWaves[1]
	if not job.footSince then
		job.footSince = now
		job.nextFoot = now + Tuning.FootGrace
	end
	if wave.count > 0 and now >= job.nextFoot and not World.isSafe(stop.park) then
		job.nextFoot = now + wave.every / multiplier * rng:NextNumber(0.85, 1.15)
		if Zombies.countFor(player) < wave.max * multiplier * job.enemyScale then
			Zombies.spawnAround(player, stop.park, nil, math.max(1, math.floor(wave.count * job.enemyScale + 0.5)), tier.kinds)
			if not job.footWarned then
				job.footWarned = true
				notice:FireClient(player, "They are coming for you! Put it down (G) to shoot.")
			end
		end
	end
end

-- 5.0, a foot job: no waves, no bandits. While you walk out of the safe zone, now and then (Foot.StrayEvery ± 20 %,
-- StrayChance) a single walker comes from StrayDistance studs away, StrayMax of yours alive at most.
local function strayStep(player: Player, job: Job, position: Vector3, now: number)
	local foot: LightJob = if job.offer.mode == "bike" then JobsConfig.Bike else JobsConfig.Foot -- (5.1: its own walkers)
	if now < job.nextStray then
		return
	end
	job.nextStray = now + foot.StrayEvery * rng:NextNumber(0.8, 1.2)
	if World.isSafe(position) or rng:NextNumber() >= foot.StrayChance or Zombies.countFor(player) >= foot.StrayMax then
		return
	end
	local spot = Zombies.findSpot(position, nil, foot.StrayDistance[1], foot.StrayDistance[2])
	if spot then
		Zombies.spawn("walker", spot, player, false)
	end
end

-- On the road: the zombie waves (paused in the safe zone), the bandit cars and the roadblocks.
local function roadEnemies(player: Player, job: Job, tier: Config.TierDef, position: Vector3, heading: Vector3?, now: number, step: number, multiplier: number, nightWaves: number)
	local offer = job.offer
	job.footSince = nil
	if not World.isSafe(position) then
		-- The zombie waves: the clock runs only out here, never in the safe zone or on foot at a stop.
		job.waveIn -= step
		if job.waveIn <= 0 then
			sendWave(player, job, tier, position, heading, multiplier * nightWaves)
		end
	end
	-- Wanted cargo (banditBoost, the hunted twist): the bandit cars and the roadblocks come that many times as often.
	-- Hunted on a ★ job (no bandits there): the ★★ bandits.
	local bandits = multiplier * offer.boost
	local banditTier = if offer.twists.hunted and tier.chaseEvery <= 0 then JobsConfig.Tiers[2] or tier else tier
	local driving = Vehicles.isDriving(player)
	if driving and banditTier.chaseEvery > 0 and now >= job.nextChase and not World.isSafe(position) then
		job.nextChase = now + banditTier.chaseEvery / bandits * rng:NextNumber(0.8, 1.2)
		if BanditCars.countFor(player) < banditTier.chaseMax and BanditCars.chase(player, position, heading) then
			notice:FireClient(player, "Bandits are on your tail! Shoot them or lose them!")
		end
	end
	if driving and banditTier.ambushEvery > 0 and now >= job.nextAmbush and not World.isSafe(position) then
		job.nextAmbush = now + banditTier.ambushEvery / bandits * rng:NextNumber(0.8, 1.2)
		ambush(player, position, heading, math.max(1, math.floor(banditTier.ambushSize * job.enemyScale + 0.5)))
	end
end

-- The crew changed (riders, members): co-op scales the enemies with it, and says so.
local function recount(player: Player, job: Job)
	local crewCount = #crewOf(job, player)
	if crewCount == job.crewCount then
		return
	end
	job.crewCount = crewCount
	job.dirty = true
	if job.offer.coop then
		job.enemyScale = Economy.coopEnemies(crewCount)
		tellJob(player, `CO-OP: crew of {crewCount + 1} · pay × {string.format("%.2f", Economy.coopPay(crewCount))} · enemies × {string.format("%.2f", job.enemyScale)}`)
	end
end

-- ── 4.8: cargo with rules and road events ──────────────────────────────────

local Rules = JobsConfig.CargoRules
local Events = JobsConfig.RoadEvents
local SURVIVOR_NAMES = { "Jake", "Rosa", "Old Mike", "Polly", "Dean", "Hannah", "Carlos", "June", "Wes", "Lena" }

-- Every tick of a job with cargo rules: the food's freshness drains once it is picked up (a Cooler Box slows it), and
-- a fragile cargo or passengers in the moving car feel the jolts (hard braking, bumps: JobRules.jolt / joltLoss, the
-- Ratchet Straps cut it). Passengers who had enough end the job like the bandits do (loseCondition).
-- 6.4: on a foot or bike run, a hard landing or a bite knocks the fragile pieces with you (Cargo.footKnock: not those in
-- the Padded Messenger Bag in your hand): each order hit loses JobRules.knockLoss of its condition.
local function cargoRulesStep(player: Player, job: Job, car: Vehicles.Car?, step: number, now: number)
	local offer = job.offer
	if offer.mode ~= "car" then
		local knock, hit = Cargo.footKnock(job.cargo, now)
		local share = JobRules.knockLoss(knock, false)
		if share > 0 then
			-- (6.4 review: on a free run of several orders only the orders hit lose it, as loseCondition does)
			if not job.free then
				job.condition = math.max(0, job.condition - share)
			end
			job.dirty = true
			for id in hit do
				local order = orderById(job, id)
				if order then
					order.condition = math.max(0, order.condition - share)
				end
			end
			notice:FireClient(player, `CAREFUL — FRAGILE! {if knock == "fall" then "That fall" else "That hit"} cost {math.floor(share * 100 + 0.5)}% of the cargo. A padded bag keeps it safe.`)
			spotlessFailed(player, job) -- (6.4 review: a spotless mission fails at once, as after any other loss)
		end
	end
	local rules = rulesNow(job)
	if #rules == 0 then
		return
	end
	local status = Cargo.status(job.cargo)
	-- 5.2: every open order's food has its own freshness, draining once that order was picked up (5.2 review: or once
	-- a piece of it is with you, in the vehicle, the hands or the pack, as before 5.2).
	local withYou: { [number]: number }? = nil
	for _, order in job.orders do
		if order.state ~= "open" or not JobRules.hasRule(order.offer.rules, "food") or order.freshness <= 0 then
			continue
		end
		local picked = false
		if job.free then
			withYou = withYou or Cargo.ordersWithYou(job.cargo)
			picked = ((withYou :: { [number]: number })[order.id] or 0) > 0
			for _, index in order.stops do
				local stop = offer.stops[index]
				if stop.kind == "pickup" and (job.stopsDone[index] or (index == job.stop and status.carrying ~= nil)) then
					picked = true
				end
			end
		else
			picked = status.inCar > 0 or status.carrying ~= nil or job.stop > 1
		end
		if not picked then
			continue
		end
		local shown = math.floor(order.freshness * 100 + 0.5)
		-- 6.4: the thermal bag in your hand for this order's pieces in it (on foot, on a bike; 6.7: no jacket any more)
		local warm = if offer.mode ~= "car" then Cargo.bagWarm(job.cargo, order.id) else nil
		order.freshness = math.max(0, order.freshness - JobRules.freshDrain(order.offer.tier, step, car ~= nil and Vehicles.hasGear(car, "cooler"), warm))
		if math.floor(order.freshness * 100 + 0.5) ~= shown then
			job.dirty = true
		end
	end
	job.freshness = focusOrder(job).freshness
	local fragile, people = JobRules.hasRule(rules, "fragile"), JobRules.hasRule(rules, "people")
	if not car or not (fragile or people) then
		return
	end
	local velocity = car.chassis.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local before = if job.joltCar == car then job.lastSpeed else speed
	job.lastSpeed, job.joltCar = speed, car
	if status.inCar <= 0 or car.wrecked or not Vehicles.isDriving(player) or now < job.joltAt then
		return
	end
	local jolt = JobRules.jolt(before, speed, step)
	local loss = JobRules.joltLoss(rules, jolt, Vehicles.hasGear(car, "straps"))
	if loss <= 0 then
		return
	end
	job.joltAt = now + Rules.JoltCooldown
	local share = math.max(1, math.floor(loss * 100 + 0.5))
	if now - job.ruleNotice >= Rules.NoticeEvery then
		job.ruleNotice = now
		notice:FireClient(player, if fragile then `CAREFUL — FRAGILE! {if jolt == "bump" then "That bump" else "Hard braking"} cost {share}% of the cargo.`
			else `The passengers complain about the bump! -{share}% condition.`)
	end
	if people then
		loseCondition(player, job, loss, "The passengers had enough of your driving and got out.")
	else
		loseCondition(player, job, loss, nil)
	end
end

-- 4.8, a survivor picked up by the road: paid in the depot's safe zone (in the car with them), gone after SurvivorKeep.
local function liftStep(player: Player, now: number)
	local lift = lifts[player]
	if not lift then
		return
	end
	if now > lift.untilAt then
		lifts[player] = nil
		notice:FireClient(player, `{lift.name} got out and went their own way.`)
		return
	end
	local car = Vehicles.seatedIn(player)
	if car and car.owner == player and World.isSafe(car.chassis.Position) then
		lifts[player] = nil
		PlayerData.addMoney(player, lift.bonus)
		notice:FireClient(player, `{lift.name} is safe at the depot! +${lift.bonus}`)
		local job = jobs[player]
		if job then
			job.dirty = true
		end
	end
end

-- The survivor event: somebody waving by the road SurvivorAhead studs ahead (Npcs, spawned off the tick). False: no
-- spot now (try again later).
local function startSurvivor(player: Player, job: Job, position: Vector3, heading: Vector3?, now: number): boolean
	if lifts[player] or not heading then
		return false
	end
	local flat = Vector3.new(heading.X, 0, heading.Z)
	if flat.Magnitude < 10 then
		return false
	end
	local ahead = position + flat.Unit * Events.SurvivorAhead
	local x, z, dx, dz, width = Map.nearestRoad(ahead.X, ahead.Z)
	if Map.isSafe(x, z) then
		return false
	end
	local side = Vector3.new(-dz, 0, dx)
	local edge = Vector3.new(x, 0, z) + side * (width / 2 + 2.5)
	local spot = onGround(edge.X, edge.Z)
	local name = pick(SURVIVOR_NAMES)
	job.eventState = "waving"
	job.eventSpot = spot
	job.eventName = name
	job.eventUntil = now + Events.SurvivorWait
	job.dirty = true
	task.spawn(function()
		local npc = Npcs.spawn(Npcs.look("townsperson", name, "Survivor"), CFrame.lookAt(spot, spot - side))
		if jobs[player] ~= job or job.eventState ~= "waving" then
			Npcs.remove(npc)
			return
		end
		job.eventNpc = npc
		Npcs.say(npc, "Hey! Over here! Please, take me with you!")
		Npcs.gesture(npc)
	end)
	notice:FireClient(player, `Somebody is waving by the road ahead! Stop next to them for a lift to the depot (+${JobRules.survivorBonus(job.offer.tier)}).`)
	return true
end

-- The survivor waits: the car stopped next to them, they hop in (a Lift until the depot); too long or driven off, they
-- give up.
local function survivorStep(player: Player, job: Job, car: Vehicles.Car?, position: Vector3, now: number)
	local spot = job.eventSpot
	if not spot then
		endEvent(player, job, nil)
		return
	end
	local gap = Vector3.new(position.X - spot.X, 0, position.Z - spot.Z).Magnitude
	if car and Vehicles.isDriving(player) and gap <= Events.SurvivorReach and Vehicles.speed(car) <= JobsConfig.HoldMaxSpeed then
		local name = job.eventName
		local bonus = JobRules.survivorBonus(job.offer.tier)
		lifts[player] = { name = name, bonus = bonus, untilAt = now + Events.SurvivorKeep }
		endEvent(player, job, `{name} hopped in! Drop them at the depot's safe zone for +${bonus} (after the job is fine).`)
		return
	end
	if now > job.eventUntil or gap > Events.SurvivorAhead * 2.5 then
		endEvent(player, job, if gap > Events.SurvivorAhead * 2.5 then nil else "The survivor gave up waiting.")
	end
end

-- 4.8, may the add-on go in front of the stop you drive to now? A drop of carried pieces you have not reached yet, a
-- delivery of one drop customer per piece (not multi-drop, not a mission), and room in the car for one more.
-- 5.2: on a run of stops in any order the add-on is an order of its own: room in the car for one more piece (what the
-- open orders hold or pick up counts) and an order slot left (Orders.Max).
local function addOnPossible(player: Player, job: Job): boolean
	local offer = job.offer
	local stop = offer.stops[job.stop]
	local car = Vehicles.get(player)
	if offer.mission or not stop or stop.kind ~= "drop" or stop.mode ~= "carry" or not car then
		return false
	end
	if job.free then
		local free = JobRules.orderRoom(Vehicles.capacity(car, offer.look), outstanding(job))
		return JobRules.canAddOrder(offer.mode, #openOrders(job), 1, free)
	end
	if offer.dests or job.cargo.built then
		return false
	end
	return JobRules.addOnFits(Cargo.remaining(job.cargo), futurePieces(job), Vehicles.capacity(car, offer.look))
end

-- The add-on event: a side pick-up near you, offered on the HUD (RoadEvent → client/RoadEventUi.luau) for AddOnAnswer s.
local function askAddOn(player: Player, job: Job, position: Vector3, now: number): boolean
	if not addOnPossible(player, job) then
		return false
	end
	local avoid: { Map.Address } = {}
	for _, stop in job.offer.stops do
		table.insert(avoid, stop.address)
	end
	local span = Events.AddOnDistance
	local address = addressAround(position.X, position.Z, span[1], span[2], 0, avoid)
	if not address or Map.isSafe(address.x, address.z) then
		return false
	end
	local distance = math.floor(Map.manhattan(position.X, position.Z, address.x, address.z))
	local addOn: AddOn = { address = address, pay = Events.AddOnPay, giver = pick(Events.AddOnGivers), distance = distance }
	job.addOn = addOn
	job.eventState = "asked"
	job.eventUntil = now + Events.AddOnAnswer
	job.dirty = true
	roadEventRemote:FireClient(player, {
		kind = "addon",
		pay = addOn.pay,
		title = `ADD-ON: +${addOn.pay}`,
		text = `One more {job.offer.piece} from {addOn.giver}, {distance} m off your route ({address.name}), before the drop.`,
		endsAt = workspace:GetServerTimeNow() + Events.AddOnAnswer,
	})
	return true
end

-- The add-on taken: its pick-up goes in front of the stop you drive to (Cargo.setStop replace), the last drop takes
-- one more piece, the pay and the clock grow.
local function takeAddOn(player: Player, job: Job, addOn: AddOn)
	local offer = job.offer
	local giver: Config.PersonDef = { name = addOn.giver, title = "Side pick-up", role = "townsperson" }
	local extra = newStop(addOn.address, "pickup", "carry", 1, `ADD-ON: PICK UP at {addOn.address.name}`, giver)
	local stops = table.clone(offer.stops)
	local last = table.clone(stops[#stops])
	last.needed += 1
	stops[#stops] = last
	table.insert(stops, job.stop, extra)
	offer.stops = stops
	offer.total += 1
	job.cargo.info.total += 1
	offer.pay += addOn.pay
	local seconds = math.floor(addOn.distance * 2 * JobsConfig.TimePerStud + Economy.handlingTime("carry", 1) * 2 + 0.5)
	offer.time += seconds
	job.endsAt += seconds
	-- (5.2: the job's only order, whose offer this is: its stops, pieces and clock)
	local order = job.orders[1]
	order.endsAt += seconds
	order.pieces += 1
	table.insert(order.stops, #order.stops + 1)
	Cargo.setStop(job.cargo, planFor(job, job.stop), true)
	blockStop(job)
	endEvent(player, job, `ADD-ON taken: pick up one more {offer.piece} from {addOn.giver} at {addOn.address.name} (+${addOn.pay}, +{seconds} s).`)
end

-- 5.2: the add-on on a run of stops in any order: an order of its own (one piece from the giver to the customer of the
-- drop you drive to), its own pay and clock (the trip there and back and Orders.AddOnTime).
local function addOnOrder(player: Player, job: Job, addOn: AddOn)
	local mine = focusOrder(job).offer
	local target = job.offer.stops[job.stop]
	local giver: Config.PersonDef = { name = addOn.giver, title = "Side pick-up", role = "townsperson" }
	local receiver = target.person
	local who = if receiver then receiver.name else mine.customer
	local seconds = OrdersConfig.AddOnTime + math.floor(addOn.distance * 2 * JobsConfig.TimePerStud + Economy.handlingTime("carry", 1) * 2 + 0.5)
	local offer = table.clone(mine)
	offer.stops = {
		newStop(addOn.address, "pickup", "carry", 1, `ADD-ON: PICK UP at {addOn.address.name}`, giver),
		newStop(target.address, "drop", "carry", 1, `ADD-ON: DELIVER to {who}, {target.address.name}`, receiver),
	}
	offer.total = 1
	offer.pay = addOn.pay
	offer.time = seconds
	offer.customer = who
	offer.dests = nil
	offer.destNames = nil
	offer.id = 0
	offer.role = nil
	-- 5.2 review: a side pick-up, not a job of the focused order's tier: ★ pay and XP (AddOnPay), no rating, streak or
	-- licence progress (payOrder), and losing it costs no streak (failOrder).
	offer.tier = 1
	appendOrder(job, offer).addOn = true
	endEvent(player, job, `ADD-ON taken: one more {offer.piece} from {addOn.giver} at {addOn.address.name} for {who} (+${addOn.pay}, {Economy.clock(seconds)} on its clock).`)
	resendBoard(player)
end

-- RoadEvent from the client: ("accept") or ("decline") the add-on on the HUD.
local function answerRoadEvent(player: Player, answer: any)
	if answer ~= "accept" and answer ~= "decline" then
		return
	end
	local job = jobs[player]
	local addOn = job and job.addOn
	if not job or not addOn or job.eventState ~= "asked" then
		roadEventRemote:FireClient(player, nil)
		return
	end
	if answer == "decline" then
		endEvent(player, job, nil)
	elseif os.clock() > job.eventUntil or not addOnPossible(player, job) then
		endEvent(player, job, "Too late for that side pick-up.")
	else
		if job.free then
			addOnOrder(player, job, addOn) -- 5.2
		else
			takeAddOn(player, job, addOn)
		end
	end
end

-- The blocked street: a roadblock on the road ahead (the tier's bandits with it; a ★ job's has none).
local function blockStreet(player: Player, job: Job, position: Vector3, heading: Vector3?): boolean
	local tier = JobsConfig.Tiers[job.offer.tier]
	local size = if tier.ambushEvery > 0 then math.max(1, math.floor(tier.ambushSize * job.enemyScale * 0.6 + 0.5)) else 0
	if not ambush(player, position, heading, size) then
		return false
	end
	endEvent(player, job, if size > 0 then "BLOCKED STREET ahead, bandits at the barricade! Find a way round." else "BLOCKED STREET ahead! Find a way round.")
	return true
end

-- Every tick: the job's road event (JobRules.pickEvent) after its seconds of driving out of the safe zone; a survivor
-- waiting, an add-on not answered in time.
local function eventsStep(player: Player, job: Job, car: Vehicles.Car?, position: Vector3, heading: Vector3?, step: number, now: number)
	local kind = job.event
	if not kind then
		return
	end
	if job.eventState == "waving" then
		survivorStep(player, job, car, position, now)
		return
	elseif job.eventState == "asked" then
		if now > job.eventUntil then
			endEvent(player, job, nil)
		end
		return
	end
	if not car or not Vehicles.isDriving(player) or World.isSafe(position) then
		return
	end
	job.driven += step
	if job.driven < job.eventAt then
		return
	end
	-- (an add-on waits until you drive to a drop: it goes in front of it)
	local target = job.offer.stops[job.stop]
	if kind == "addon" and target and target.kind ~= "drop" then
		return
	end
	local started = if kind == "survivor" then startSurvivor(player, job, position, heading, now)
		elseif kind == "addon" then askAddOn(player, job, position, now)
		else blockStreet(player, job, position, heading)
	if not started then
		job.eventTries += 1
		job.eventAt = job.driven + Events.Retry
		if job.eventTries >= Events.Tries then
			job.event = nil
		end
	end
end

local elapsed = 0
local boardElapsed = 0

local lastUpdateWarn = -math.huge

-- ── 5.2: the stops in any order ────────────────────────────────────────────

-- Why an order's customer gave up when its clock ran out.
local function lateReason(offer: Offer): string
	return if offer.kind == "patient" then "Too late! The patient couldn't wait any longer."
		elseif offer.kind == "survivor" then "Too late! The survivors couldn't hold out any longer."
		elseif offer.look == "pizza" and offer.jobType then `Too late! The pizza went cold and {offer.customer} gave up on you.`
		else `Too late! {offer.customer} gave up on you.`
end

-- Every order's clock: one that ran out fails (the last open one fails the job, as a job's clock always did). True
-- when the job ended.
local function ordersClock(player: Player, job: Job, serverNow: number): boolean
	for _, order in job.orders do
		if order.state ~= "open" or serverNow <= order.endsAt then
			continue
		end
		if #openOrders(job) <= 1 then
			Jobs.fail(player, lateReason(order.offer))
			return true
		end
		failOrder(player, job, order, lateReason(order.offer))
	end
	return jobs[player] ~= job
end

-- Is an order over: every drop of it done, or everything picked up and none of its pieces left (stolen, wrecked)?
local function orderOver(job: Job, order: Order): boolean
	local dropsDone, pickupsDone = true, true
	for _, index in order.stops do
		if not job.stopsDone[index] then
			if job.offer.stops[index].kind == "drop" then
				dropsDone = false
			else
				pickupsDone = false
			end
		end
	end
	return dropsDone or (pickupsDone and Cargo.remainingFor(job.cargo, order.id) == 0)
end

-- The orders that are over are paid (what arrived) or fail (nothing arrived); the last one ends the job. True when
-- the job ended.
local function closeOrders(player: Player, job: Job): boolean
	for _, order in table.clone(job.orders) do
		if order.state ~= "open" or not orderOver(job, order) then
			continue
		end
		local delivered = Cargo.deliveredOf(job.cargo, order.id)
		if #openOrders(job) <= 1 then
			if delivered <= 0 then
				Jobs.fail(player, "All of your cargo is gone!")
			else
				local allDone = true
				for _, index in order.stops do
					allDone = allDone and job.stopsDone[index] == true
				end
				if not allDone then
					notice:FireClient(player, "Nothing left to deliver. You get paid for what arrived.")
				end
				complete(player, job)
			end
			return true
		end
		if delivered > 0 then
			settleOrder(player, job, order)
		else
			failOrder(player, job, order, "All of its cargo is gone.")
		end
	end
	return jobs[player] ~= job
end

-- The current stop becomes the job's stop `index` (Cargo's Plan with it). `after`: the one left was done (its people
-- stay a moment, "Done! Next: …").
local function switchStop(player: Player, job: Job, index: number, after: boolean)
	job.stop = index
	job.footSince = nil
	job.switchAt = os.clock() + OrdersConfig.SwitchEvery
	Cargo.setStop(job.cargo, planFor(job, index), not after)
	blockStop(job)
	job.dirty = true
	if after then
		notice:FireClient(player, `Next: {job.offer.stops[index].label}`)
	end
end

-- Every tick of a run of stops in any order (Job.free): the current stop done, the drops left with nothing to bring,
-- the orders that are over (paid or failed), then the stop the GPS shows (JobRules.nextOpenStop: the circle you are
-- at, the pinned order, the nearest; a stop half handled stays). True when the job ended.
local function freeStep(player: Player, job: Job, position: Vector3, now: number): boolean
	local session = job.cargo
	local doneHere = job.stopsDone[job.stop] == true
	if not doneHere and Cargo.stopDone(session) then
		job.stopsDone[job.stop] = true
		doneHere = true
		job.dirty = true
	end
	local states, withYou = stopStates(job)
	for index in states do
		if index ~= job.stop and JobRules.stopOpen(states, index, withYou) == "empty" then
			job.stopsDone[index] = true -- (its pieces were stolen or wrecked: nothing to bring there)
		end
	end
	if closeOrders(player, job) then
		return true
	end
	if not doneHere and (Cargo.engaged(session) or now < job.switchAt) then
		return false
	end
	states, withYou = stopStates(job)
	local target = JobRules.nextOpenStop(states, withYou, { x = position.X, z = position.Z }, job.pinned, if doneHere then nil else job.stop)
	if target and target ~= job.stop then
		switchStop(player, job, target, doneHere)
	end
	return false
end

-- One player's tick of update (below): the job's timer, crew, cargo, waves and bandits.
local function updatePlayer(player: Player, step: number, now: number, serverNow: number, nightWaves: number)
	local job = jobs[player]
	local car = Vehicles.get(player)
	local position = playerPosition(player)
	local heading = if car then car.chassis.AssemblyLinearVelocity else nil

	liftStep(player, now) -- 4.8: a survivor aboard, with a job or without

	if not job then
		return -- free roam: only the roaming zombies (server/Zombies.luau), no bandits
	end

	local offer = job.offer
	local tier = JobsConfig.Tiers[tierNow(job)] or JobsConfig.Tiers[offer.tier] -- (5.2: the hardest open order's)
	local modifier = offer.modifier
	local session = job.cargo
	-- 5.2: every order's own clock (a job of one order: its clock, as before).
	if ordersClock(player, job, serverNow) then
		return
	end
	-- Spotless: the cargo got too damaged (car hits, bandits, shots).
	if spotlessFailed(player, job) then
		return
	end
	-- 3.2, DUO: the partner must stay in the crew (they left it, or the game).
	if offer.duo then
		if #Crew.members(player) >= Config.Missions.Duo.MinCrew then
			job.duoTeamed = true
		elseif job.duoTeamed then
			Jobs.fail(player, "Your partner left.")
			return
		end
	end

	-- Everybody who rides in the owner's car is crew (they may carry the cargo, their kills count) while they
	-- stay with it.
	pruneRiders(player, job)
	if car then
		for _, rider in Vehicles.passengersOf(car) do
			job.crew[rider] = true
		end
	end
	recount(player, job)
	if session.info.foot then
		orderRoomOf(player, offer, job) -- 5.2 review: bike gear bought during the run grows the bike's bag now (6.6)
	end
	Cargo.update(session, step)
	-- 3.1: the pieces delivered since the last tick (any, the people who board, the horses).
	if session.deliveredTotal > job.piecesCounted then
		local pieces = session.deliveredTotal - job.piecesCounted
		job.piecesCounted = session.deliveredTotal
		statCrew(player, job, "pieces", pieces)
		if offer.kind == "horse" then
			statCrew(player, job, "horses", pieces)
		elseif Cargo.isPeople(offer.kind) then
			statCrew(player, job, "passengers", pieces)
		end
	end
	if not jobs[player] then
		return
	end
	-- 3.2, switches: the gate's levers (the HUD), and the stop goes on once it is open.
	if job.gateClosed then
		local pulled = DuoGates.pulled(player)
		if pulled ~= job.gatePulled then
			job.gatePulled = pulled
			job.dirty = true
		end
		if DuoGates.isOpen(player) then
			job.gateClosed = false
			job.dirty = true
			blockStop(job)
			local here = offer.stops[job.stop]
			tellJob(player, if here.kind == "pickup" then "The gate is open! Load up, partners!" else "The gate is open! Unload, quick!")
		end
	end

	local stop: Stop
	local lastStop: boolean
	if job.free then
		-- 5.2: the stops in any order, the orders paid as they are done.
		if freeStep(player, job, position, now) then
			return
		end
		stop = job.offer.stops[job.stop]
		lastStop = lastOfOrder(job, job.stop)
	else
		stop = offer.stops[job.stop]
		lastStop = job.stop == #offer.stops
		-- The last stop done, or nothing left anywhere to deliver (stolen, wrecked): what arrived is paid, nothing
		-- arrived fails.
		local done = Cargo.stopDone(session)
		local finished = done and lastStop
		if finished or Cargo.remaining(session) + futurePieces(job) == 0 then
			if session.deliveredTotal <= 0 then
				Jobs.fail(player, "All of your cargo is gone!")
			else
				if not finished then
					notice:FireClient(player, "Nothing left to deliver. You get paid for what arrived.")
				end
				complete(player, job)
			end
			return
		end
		if done then
			advance(player, job)
			stop = offer.stops[job.stop]
			lastStop = job.stop == #offer.stops
		end
	end

	local flatDistance = Vector3.new(position.X - stop.park.X, 0, position.Z - stop.park.Z).Magnitude
	spawnHordes(player, job, tier, stop, lastStop, flatDistance)

	local multiplier = if modifier then modifier.spawnMultiplier else 1
	if offer.twists.defend and lastStop and not job.defendDone then
		defendStep(player, job, tier, stop, position, now, step, multiplier * nightWaves)
	end
	local foot = offer.mode == "foot" or offer.mode == "bike"
	if foot then
		strayStep(player, job, position, now) -- 5.0: no waves, no bandits on foot (5.1: nor on a bike job)
		require(script.Parent.RunEvents).step(player, position, stop, job.stop, step) -- 5.7: a runner, a survivor, a gate, walkers at a drop
	elseif Cargo.onFoot(session) then
		footWave(player, job, tier, stop, now, multiplier)
	else
		roadEnemies(player, job, tier, position, heading, now, step, multiplier, nightWaves)
	end
	-- 4.8: the cargo's rules (freshness, jolts) and the road event. (5.0: on foot no vehicle takes part.)
	cargoRulesStep(player, job, if foot then nil else car, step, now)
	if jobs[player] ~= job then
		return
	end
	eventsStep(player, job, car, position, heading, step, now)

	-- The HUD's instruction changes with what you do (parking, getting out): send it when it does.
	local _, text = stepOf(job)
	if text ~= job.lastStep then
		job.dirty = true
	end
	if job.dirty then
		send(player)
	end
end

local function update(dt: number)
	elapsed += dt
	if elapsed < 0.2 then
		return
	end
	local step = elapsed
	elapsed = 0
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	-- 3.7: the boards' timers, once a second.
	boardElapsed += step
	if boardElapsed >= 1 then
		boardElapsed = 0
		refreshBoards(serverNow)
	end
	-- Bigger and more frequent waves at night (Economy.waveSize / waveEvery / waveAlive take it like WANTED does).
	local nightWaves = Economy.nightScale(Config.DayNight.NightWaves, DayNight.nightFactor())
	for _, player in Players:GetPlayers() do
		-- 4.2: one player's error must not stop everybody else's timers, waves and cargo (warned once a minute).
		local ok, err = pcall(updatePlayer :: any, player, step, now, serverNow, nightWaves)
		if not ok and now - lastUpdateWarn > 60 then
			lastUpdateWarn = now
			warn(`[Jobs] update failed for {player.Name}: {err}`)
		end
		-- 5.7: a job whose tick keeps failing ends (Config.Jobs.TickFails in a row) instead of stranding its player.
		local job = jobs[player]
		if job then
			job.tickFails = if ok then 0 else (job.tickFails or 0) + 1
			if (job.tickFails or 0) >= JobsConfig.TickFails then
				warn(`[Jobs] {player.Name}'s job failed {JobsConfig.TickFails} ticks in a row: it ends ({err})`)
				local failed, why = pcall(function()
					Jobs.fail(player, "Something went wrong with this delivery. Take another one from the board.")
				end)
				if not failed then
					warn(`[Jobs] the failing job could not end cleanly: {why}`)
					if jobs[player] == job then
						pcall(endJob, player, job, false)
					end
					pcall(send, player)
				end
			end
		end
	end
end

-- ── Missions (shared/Missions.luau, server/Missions.luau) ───────────────────

-- Set by Main: a mission was finished (the owner, the mission id, the rating 1 – 3, everybody paid with the owner).
Jobs.onMissionComplete = nil :: ((owner: Player, missionId: string, stars: number, members: { Player }) -> ())?

-- A mission's offer from where the player is (its stops, the pay × the twists, its clock), marked as the mission.
local function missionOffer(player: Player, def: Config.JobTypeDef): Offer?
	local offer = jobOffer(playerPosition(player), def)
	if offer then
		offer.mission = def.mission or def.id
		offer.rules = {} -- 4.8: a mission is told as it is written
	end
	return offer
end

-- Start a mission for the player now (server/Missions.luau checked that it is open and the level). Refused with a
-- job running, in somebody else's crew, or a night mission by day. False and why not (the caller tells the player).
function Jobs.startMission(player: Player, def: Config.JobTypeDef): (boolean, string?)
	if jobs[player] then
		return false, "Finish your current delivery first."
	end
	local owner = Crew.ownerOf(player)
	if owner and owner ~= player then
		return false, `You are in {owner.DisplayName}'s crew: your crew leader picks the mission.`
	end
	if table.find(twistList(def), "night") and not DayNight.isNight() then
		return false, "Come back after dark: this one only works at night."
	end
	local offer = missionOffer(player, def)
	if not offer then
		return false, "No route for this mission from here, try again."
	end
	return startJob(player, offer)
end

-- ── Admin tools (server/Admin.luau) ────────────────────────────────────────

-- Start any job now, next to the player: a Config.JobTypes id (with its vehicle), a mission id (shared/Missions.luau,
-- no locks, no night check), or "ordinary" / "ordinary1" … "ordinary4" (also "tier1" …) for a job-board delivery of
-- that danger level, 5.0: "foot" for an ON FOOT one. A running job is cancelled.
function Jobs.adminStart(player: Player, jobTypeId: string): boolean
	if type(jobTypeId) ~= "string" then
		return false
	end
	local current = jobs[player]
	if current then
		endJob(player, current, false)
		send(player)
	end
	local from = playerPosition(player)
	local offer: Offer? = nil
	local tierText = string.match(jobTypeId, "^ordinary(%d?)$") or string.match(jobTypeId, "^tier(%d)$")
	if jobTypeId == "foot" then
		offer = footOffer(from, nil, Transport.footOf(player).room)
	elseif jobTypeId == "round" then
		offer = footOffer(from, "round", Transport.footOf(player).room) -- 5.3: the newspaper round, any hour
	elseif tierText then
		local tierIndex = math.clamp(tonumber(tierText) or rng:NextInteger(1, #JobsConfig.Tiers), 1, #JobsConfig.Tiers)
		offer = ordinaryOffer(from, tierIndex)
		if offer and not Vehicles.get(player) then
			Vehicles.spawn(player, true)
		end
	else
		local jobType = Economy.findJobType(jobTypeId)
		local mission = Missions.find(jobTypeId)
		offer = if jobType then jobOffer(from, jobType) elseif mission then missionOffer(player, mission) else nil
	end
	if not offer then
		notice:FireClient(player, `Cannot start "{jobTypeId}" here (unknown job or a missing place).`)
		return false
	end
	return startOrTell(player, offer)
end

-- Finish the current stop at once (loaded / delivered / served); the next tick moves on to the next stop.
function Jobs.adminFinishStop(player: Player): boolean
	local job = jobs[player]
	if not job then
		return false
	end
	-- Defend: held out at once.
	if job.offer.twists.defend and job.stop == #job.offer.stops and not job.defendDone then
		job.defendDone = true
	end
	-- 3.2, switches: the gate opened at once.
	if job.gateClosed then
		DuoGates.forceOpen(player)
		job.gateClosed = false
	end
	blockStop(job)
	local done = Cargo.adminFinish(job.cargo)
	job.dirty = true
	return done
end

-- 4.8: a road event ("survivor" | "addon" | "roadblock") on the current job at once (the next tick driving out of the
-- safe zone; an add-on once you drive to a drop). False without a job of your own or with an unknown kind.
function Jobs.adminRoadEvent(player: Player, kind: any): boolean
	local job = jobs[player]
	if not job or (kind ~= "survivor" and kind ~= "addon" and kind ~= "roadblock") then
		return false
	end
	endEvent(player, job, nil)
	job.event = kind
	job.eventAt = job.driven
	job.eventTries = 0
	return true
end

-- 4.5: the whole job done at once, paid like a finished one (every piece counted as delivered; the condition and the
-- clock as they are now; a mission is rated and rewarded). False without a job of your own.
function Jobs.adminComplete(player: Player): boolean
	local job = jobs[player]
	if not job then
		return false
	end
	if job.gateClosed then
		DuoGates.forceOpen(player)
		job.gateClosed = false
	end
	-- 5.2: every open order, each paid as it is (its pieces counted as delivered); the last one ends the job.
	local session = job.cargo
	session.deliveredTotal = math.max(session.deliveredTotal, job.offer.total)
	local open = openOrders(job)
	for index, order in open do
		session.deliveredBy[order.id] = math.max(Cargo.deliveredOf(session, order.id), order.pieces)
		if index < #open then
			settleOrder(player, job, order)
		end
	end
	complete(player, job)
	return true
end

function Jobs.start()
	-- The quiet twist hears every shot (Gun does not require Jobs: no cycle).
	Gun.onShot = Jobs.onShot
	-- 3.7: opening the board sends the current offers; new ones only when they expired (or there were none yet).
	-- (5.7: Net.latest rate limits these two, Config.Robust.Limits; a burst of board requests is answered once)
	Net.get("RequestOffers").OnServerEvent:Connect(function(player)
		Net.latest(player, "RequestOffers", Config.Robust.Limits.RequestOffers, function()
			local job = jobs[player]
			if not job or runStacks(job) then -- (5.2: a run that takes more orders shows the board too)
				sendBoard(player, boardOf(player))
			end
		end)
	end)
	-- 5.2: the phone's ORDERS app pins an order (its id; nil: none): the GPS follows it.
	Net.get("PinOrder").OnServerEvent:Connect(function(player, pinned)
		Net.latest(player, "PinOrder", Config.Robust.Limits.PinOrder, function(_, id: any)
			local job = jobs[player]
			if not job or (id ~= nil and type(id) ~= "number") then
				return
			end
			local order = if type(id) == "number" then orderById(job, id) else nil
			job.pinned = if order and order.state == "open" then order.id else nil
			job.switchAt = 0
			job.dirty = true
		end, pinned)
	end)
	Net.get("AcceptJob").OnServerEvent:Connect(accept)
	Net.get("RerollTier").OnServerEvent:Connect(reroll) -- 4.7
	roadEventRemote.OnServerEvent:Connect(answerRoadEvent) -- 4.8: the add-on's Y / NO
	Net.get("AcceptEmployer").OnServerEvent:Connect(acceptEmployer)
	Net.get("CancelJob").OnServerEvent:Connect(function(player)
		if not Net.limit(player, "CancelJob", Config.Robust.Limits.CancelJob) then return end -- 5.7
		Jobs.fail(player, "Delivery cancelled.")
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- 3.7: the board (boards, by UserId) stays until it expires (refreshBoards): coming back does not reroll it.
		local job = jobs[player]
		if job then
			jobs[player] = nil
			freeDocks(player)
			endEvent(player, job, nil) -- 4.8: a survivor still waving goes
			Cargo.finish(job.cargo, false)
			Crew.disband(player)
		end
		require(script.Parent.RunEvents).finish(player) -- 5.7
		lifts[player] = nil
		DuoGates.clear(player)
		for _, other in jobs do
			other.crew[player] = nil
			other.members[player] = nil
			other.quietNotice[player] = nil
		end
	end)
	RunService.Heartbeat:Connect(update)
end

-- 3.7: the tutorial's first job (server/Tutorial.luau): the easiest offer near the player, started as if accepted
-- from the board (takeOffer). False when the player has a job already or no offer could be made. 5.0: ON FOOT (a new
-- player has no vehicle): the post office's letters, Config.Jobs.TutorialPieces of them (what the hands hold), the
-- pick-up close by and the drop on the same street (footOffer tutorial), the shortest of TutorialTries. No road
-- events, no cargo rules, no modifier. It does not touch the job board.
function Jobs.startTutorialJob(player: Player): boolean
	if jobs[player] then
		return false
	end
	local from = playerPosition(player)
	local room = Transport.footOf(player).room
	local best: Offer? = nil
	for _ = 1, math.max(1, JobsConfig.TutorialTries) do
		local offer = footOffer(from, nil, room, true)
		if offer and (not best or offer.distance < best.distance) then
			best = offer
		end
	end
	if not best then
		return false
	end
	best.tutorial = true -- 4.8: no road events on it
	return takeOffer(player, best)
end

function Jobs.sendTo(player: Player)
	send(player)
end

-- What the invited crew sees of the owner's job (server/Crew.luau Crew.statusOf, wired in Main), or nil without one:
-- name, step (the current stop: what to do there), position (its circle, for the GPS), stars, endsAt; and more for
-- the HUD: hint (the owner's on-foot step, the defend countdown), stage, stopIndex / stopCount, cargo, pay,
-- delivered / total, wave, timed; mission (3.0, as in the job payload) on a mission.
function Jobs.crewStatus(owner: Player): { [string]: any }?
	local job = jobs[owner]
	if not job then
		return nil
	end
	local offer = job.offer
	local stop = offer.stops[job.stop]
	local order = focusOrder(job) -- 5.2: the focused order's (the current stop's)
	local mine = order.offer
	return {
		name = if mine.jobType then mine.jobType.name else `{mine.cargo} → {mine.customer}`,
		step = stop.label,
		hint = job.lastStep,
		position = stop.park,
		stars = mine.tier,
		endsAt = order.endsAt,
		stage = stop.kind,
		stopIndex = table.find(order.stops, job.stop) or 1,
		stopCount = #order.stops,
		cargo = mine.cargo,
		pay = mine.pay,
		delivered = Cargo.deliveredOf(job.cargo, order.id),
		total = order.pieces,
		orders = #openOrders(job), -- 5.2
		wave = job.wave,
		timed = offer.jobType ~= nil and offer.jobType.timeLimit ~= nil,
		crewCount = job.crewCount, -- paid besides the owner: the invited crew and whoever rode along
		mission = missionInfo(job),
		mode = offer.mode, -- 5.0
	}
end

return Jobs
