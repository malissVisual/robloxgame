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
--     top of the board: light pieces only, never more than you carry (hands + backpack), a short walk Downtown or in
--     the Suburbs, its own pay and clock (JobRules.footPay / footTime). startJob needs no vehicle (Cargo's foot flow:
--     Info.foot, the pack); no waves, bandits or road events, now and then a stray walker (strayStep); a thermal
--     jacket slows the food's drain. The tutorial's first delivery is one (Jobs.startTutorialJob).
--   * "car": every other job. Without a vehicle of your own (profile.car nil) the ones in your own car are locked
--     "NEEDS A VEHICLE" (needsVehicle) and refused; the jobs that lend a company vehicle need their level (4+).

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
	-- a job that lends a company vehicle too). 5.1 adds "bike".
	mode: string,
}

-- 3.7: a player's job board: its offers (sorted, boardOrder) until refreshAt (workspace:GetServerTimeNow()).
-- 4.7: rerolled = the tiers rerolled on this board (once each).
type Board = { list: { Offer }, refreshAt: number, rerolled: { [number]: boolean } }

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

local function payload(job: Job): { [string]: any }
	local offer = job.offer
	local stop = offer.stops[job.stop]
	local last = offer.stops[#offer.stops]
	local status = Cargo.status(job.cargo)
	local handling, step = stepOf(job)
	job.lastStep = step
	return {
		stars = offer.tier,
		cargo = offer.cargo,
		customer = offer.customer,
		address = last.address.name,
		district = last.address.district,
		position = stop.park,
		stage = stop.kind,
		stopIndex = job.stop,
		stopCount = #offer.stops,
		stopLabel = stop.label,
		progress = if stop.mode == "serve" or stop.mode == "board" then status.progress else 0,
		endsAt = job.endsAt,
		timeLimit = offer.time,
		condition = job.condition,
		kills = job.kills,
		wave = job.wave, -- zombie waves so far
		pay = offer.pay,
		modifier = info(offer.modifier),
		jobType = info(offer.jobType),
		-- The cargo on foot (server/Cargo.luau).
		handling = handling, -- drive | carry | lead | board | serve
		step = step, -- what to do now
		inCar = status.inCar,
		delivered = status.delivered, -- handled at this stop: loaded at a pick-up, handed over at a drop
		needed = status.needed, -- for this stop
		total = status.total, -- pieces of the whole job
		deliveredTotal = status.deliveredTotal,
		lost = status.lost, -- stolen or wrecked
		carrying = status.carrying,
		person = status.person,
		pile = status.pile,
		looseAt = status.looseAt, -- a piece put down (G): pick it up again
		piece = offer.piece,
		pieces = offer.plural,
		itemKind = offer.kind,
		timed = offer.jobType ~= nil and offer.jobType.timeLimit ~= nil, -- a rush: a fixed clock
		banditBoost = offer.boost,
		night = DayNight.isNight(), -- the pay and the waves are up
		crewCount = job.crewCount,
		mission = missionInfo(job), -- 3.0: the mission (nil for any other job)
		-- 4.8: the cargo's rules, the food's freshness (0 … 1, nil when not food), the contract's lines for them and
		-- for the road event
		rules = offer.rules,
		freshness = if JobRules.hasRule(offer.rules, "food") then job.freshness else nil,
		ruleLine = JobRules.ruleLine(offer.rules, job.freshness, offer.mode ~= "foot" and cooled(job.owner)),
		eventLine = eventLine(job),
		-- 5.0: "foot" | "car"; on foot what rides in your backpack (and its room)
		mode = offer.mode,
		pack = if status.foot then status.pack else nil,
		packRoom = if status.foot then status.packRoom else nil,
	}
end

local function send(player: Player)
	local job = jobs[player]
	jobRemote:FireClient(player, if job then payload(job) else nil)
	if job then
		job.dirty = false
	end
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
	local spot = if id and spots then spots[id] else nil
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
local function ordinaryOffer(from: Vector3, tierIndex: number, easy: boolean?, role: string?): Offer?
	local tier = JobsConfig.Tiers[tierIndex]
	local choice = JobsConfig.Choice
	local businesses: { Config.BusinessDef } = {}
	for _, business in JobsConfig.Businesses do
		local handy = not easy or (not Cargo.isPeople(business.kind) and business.kind ~= "horse")
		if table.find(business.tiers, tierIndex) and handy then
			table.insert(businesses, business)
		end
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
		if easy then
			return nil
		end
		businesses = JobsConfig.Businesses
	end
	local business = pick(businesses)
	local pickupMax = if easy then math.max(JobsConfig.PickupMinDistance, JobsConfig.TutorialPickupMax) else JobsConfig.PickupMaxDistance
	local pickup = addressAround(from.X, from.Z, JobsConfig.PickupMinDistance, pickupMax, 0, {})
	if not pickup then
		return nil
	end
	local dropMin, dropMax = JobRules.window(role, tier.minDistance, tier.maxDistance)
	if easy then
		dropMin, dropMax = tier.minDistance, math.clamp(JobsConfig.TutorialDropMax, tier.minDistance, tier.maxDistance)
	end
	local drop = addressAround(pickup.x, pickup.z, dropMin, dropMax, if tierIndex >= 3 and not easy then 3 else 0, { pickup })
	if not drop then
		return nil
	end
	-- At a far place its own person takes it.
	local placeId = placeIdOf(drop)
	local receiver = (placeId and JobsConfig.PlacePeople[placeId]) or pick(business.receivers)
	local most = business.pieces[2] or business.pieces[1]
	local count = if role == "short" then business.pieces[1] elseif role == "bulk" then most else rng:NextInteger(business.pieces[1], most)
	if tierIndex == 1 then
		count = math.min(count, JobsConfig.EasyMaxPieces) -- 3.5: a ★ delivery fits the Rusty Van
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
		newStop(pickup, "pickup", "carry", count, `PICK UP at the {business.place}, {pickup.name}`, business.giver),
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
			local address = if n == 1 then addressAround(pickup.x, pickup.z, dropMin, dropMax, 0, avoid) else addressAround(at.x, at.z, gap[1], gap[2], 0, avoid)
			if not address then
				break
			end
			table.insert(avoid, address)
			local person = people[n]
			table.insert(multi, newStop(address, "drop", "carry", needs[n], `DELIVER to {person.name}, {address.name}`, person))
			names[n + 1] = person.name
			at = address
		end
		if #multi == drops + 1 then
			stops = multi
			dests = JobRules.destinations(needs, 2)
			destNames = names
			customer = `{people[1].name} & {drops - 1} more`
		else
			drops = 1
		end
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
	local payMultiplier = if role == "long" then choice.LongPay elseif role == "risky" then choice.RiskyPay else 1
	if payMultiplier ~= 1 then
		offer.pay = math.floor(offer.pay * payMultiplier / 5 + 0.5) * 5
	end
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
local function footOffer(from: Vector3, role: string?, room: number, tutorial: boolean?): Offer?
	local foot = JobsConfig.Foot
	local choice = JobsConfig.Choice
	local businesses: { Config.BusinessDef } = {}
	for _, business in JobsConfig.Businesses do
		if Tuning.LightLooks[business.look] and not Cargo.isPeople(business.kind) and (not tutorial or business.id == "post") then
			table.insert(businesses, business)
		end
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
	local function allow(address: Map.Address): boolean
		return not address.poi and foot.Districts[address.district] == true
	end
	local pickupMax = if tutorial then math.max(foot.PickupMax, JobsConfig.TutorialPickupMax) else foot.PickupMax
	local pickup = addressAround(from.X, from.Z, foot.PickupMin, pickupMax, 0, {}, allow)
	if pickup and Map.manhattan(from.X, from.Z, pickup.x, pickup.z) > pickupMax then
		-- (none that close, the depot's safe zone has no addresses: a little farther, not always the same one)
		pickup = addressAround(from.X, from.Z, foot.PickupMin, pickupMax + foot.PickupWiden, 0, {}, allow)
	end
	if not pickup then
		return nil
	end
	local dropMin, dropMax = JobRules.window(role, foot.MinDistance, foot.MaxDistance)
	if tutorial then
		dropMin, dropMax = foot.MinDistance, math.max(foot.MinDistance, foot.TutorialDrop)
	end
	local drop = addressAround(pickup.x, pickup.z, dropMin, dropMax, 0, { pickup }, allow)
	if not drop then
		return nil
	end
	local receiver = pick(business.receivers)
	local most = business.pieces[2] or business.pieces[1]
	local wanted = if role == "short" then business.pieces[1] elseif role == "bulk" then most else rng:NextInteger(business.pieces[1], most)
	local count = if tutorial then math.max(1, math.min(JobsConfig.TutorialPieces, room)) else JobRules.footPieces(wanted, room)
	local words = foot.TutorialCargo
	local cargoName = if tutorial then words.cargo else business.cargo
	local pieces: CargoInfo = if tutorial
		then { kind = words.kind, look = words.look, piece = words.piece, plural = words.plural, total = count }
		else { kind = business.kind, look = business.look, piece = business.piece, plural = business.plural, total = count }
	local stops: { Stop } = {
		newStop(pickup, "pickup", "carry", count, if tutorial then `PICK UP the letters at the {business.place}, {pickup.name}` else `PICK UP at the {business.place}, {pickup.name}`, business.giver),
		newStop(drop, "drop", "carry", count, `DELIVER to {receiver.name}, {drop.name}`, receiver),
	}
	local forced = if role == "risky" then riskyModifier(1) else nil
	local offer = finishOffer(1, stops, routeLength(from.X, from.Z, stops), cargoName, receiver.name, nil, pieces, 0, tutorial or role == "short", forced)
	offer.mode = "foot"
	offer.role = role
	offer.level = 1 -- always open: the board's ON FOOT section
	offer.boost = 1 -- no bandits on foot
	-- Its own pay and clock (the walk, not the drive).
	local handling = 0
	for _, stop in stops do
		handling += Economy.handlingTime(stop.mode, stop.needed)
	end
	local modifier = offer.modifier
	local roleMult = if role == "long" then choice.LongPay elseif role == "risky" then choice.RiskyPay else 1
	offer.pay = JobRules.footPay(offer.distance, count, roleMult * (if modifier then modifier.payMultiplier else 1))
	offer.time = JobRules.footTime(offer.distance, handling, if modifier then modifier.timeMultiplier else nil)
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

-- 5.0: a job done in your own car (not on foot, no company vehicle lent) while you own no vehicle yet.
local function needsVehicle(player: Player, offer: Offer): boolean
	local jobType = offer.jobType
	local profile = PlayerData.get(player)
	return offer.mode ~= "foot" and not (jobType and jobType.vehicle) and profile ~= nil and profile.car == nil
end

-- 3.4: the cargo slots a job needs, what the vehicle that would do it holds and that vehicle's name: the company
-- vehicle the job lends, else the player's equipped car (3.5: at its stage). 5.0: on foot the pieces you carry
-- (Transport: hands and backpack); no vehicle yet: 0.
local function slotsFor(player: Player, offer: Offer): (number, number, string)
	local jobType = offer.jobType
	local need = Economy.cargoNeed(if jobType then jobType.load else "carry", offer.total)
	if offer.mode == "foot" then
		local room = Transport.footOf(player).room
		return offer.total, room, if room > Config.Cargo.HandsMax then "backpack" else "hands"
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
	if (jobType and jobType.vehicle) or not profile or not carId or offer.mode == "foot" then
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
		return JobsConfig.Foot.NeedsVehicle
	end
	if offer.mode == "foot" then
		local _, room = slotsFor(player, offer)
		if offer.total <= room then
			return nil
		end
		return `This job has {offer.total} {offer.plural}: you carry {room}. A bigger backpack (Last Stop Supplies) carries more.`
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
	local perStud = if offer.mode == "foot" then 1 / math.max(1, JobsConfig.Foot.Speed) else JobsConfig.TimePerStud -- (5.0: a walk)
	local slower = math.max(0, extra) * perStud * (if modifier then modifier.timeMultiplier else 1)
	return math.max(0, offer.distance + extra), offer.time + math.floor(slower + 0.5)
end

-- One card of the job board. A job above the player's level is shown LOCKED (locked, level): accepting it is refused.
-- 3.4: so is a job with more pieces than the car holds (slots, capacity, carName, tooBig). 3.7: `index` is the offer's
-- id (AcceptJob sends it back), its distance and time are from where the player is now (fromHere).
local function describe(offer: Offer, from: Vector3, playerLevel: number, nightPay: number, player: Player): { [string]: any }
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
		lockText, lockButton = JobsConfig.Foot.NeedsVehicle, JobsConfig.Foot.NeedsVehicleButton
	end
	return {
		mode = offer.mode, -- 5.0: "foot" (the board's ON FOOT section) | "car"
		needsVehicle = if noVehicle then true else nil,
		locked = offer.level > playerLevel or noLicence,
		lockReason = if offer.level > playerLevel then "level" elseif noLicence then "licence" elseif noVehicle then "vehicle" else nil,
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
		drops = if offer.dests then #offer.stops - 1 else nil,
	}
end

-- 3.7: the board's order: ★ on top, then ★★, ★★★, ★★★★ (the specials at their stars, the locked ones in their place);
-- at the same stars the lower driver level first, the ordinary delivery before a special; else as they were made.
-- 5.0: the ON FOOT jobs on top.
local function boardOrder(a: Offer, b: Offer): boolean
	local aFoot, bFoot = a.mode == "foot", b.mode == "foot"
	if aFoot ~= bFoot then
		return aFoot
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
-- (its level and its licence), else one to show what is locked.
local function tierOffers(player: Player, from: Vector3, tierIndex: number): { Offer }
	local out: { Offer } = {}
	local open = PlayerData.level(player) >= JobsConfig.Tiers[tierIndex].level and hasLicence(player, tierIndex)
	local roles: { string } = if open then JobRules.roles(function(): number
		return rng:NextNumber()
	end) else { "short" }
	for _, role in roles do
		local offer = ordinaryOffer(from, tierIndex, nil, role)
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
	for index = 1, math.max(1, JobsConfig.Foot.Offers) do
		local offer = footOffer(from, footRoles[(index - 1) % #footRoles + 1], room)
		if offer then
			table.insert(list, offer)
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
	local board: Board = { list = list, refreshAt = workspace:GetServerTimeNow() + math.max(10, JobsConfig.RefreshSeconds), rerolled = {} }
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
	for _, offer in board.list do
		table.insert(out, describe(offer, from, level, nightPay, player))
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
	-- 5.0: what you carry on foot (the ON FOOT section's "HANDS 2 / BACKPACK 3") and whether you have a vehicle.
	local foot = Transport.footOf(player)
	local carry = { hands = Config.Cargo.HandsMax, room = foot.room, pack = math.max(0, foot.room - Config.Cargo.HandsMax), speed = foot.speedMult }
	local hasCar = profile ~= nil and profile.car ~= nil
	Net.get("Offers"):FireClient(player, out, board.refreshAt, { tiers = tiers, streak = if profile then profile.streak else 0, foot = carry, hasCar = hasCar })
end

-- A new board now, sent to the player (3.7: the client cannot ask for this; RequestOffers sends the current board).
function Jobs.makeOffers(player: Player)
	sendBoard(player, makeBoard(player))
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
			if offer.jobType ~= nil or offer.tier ~= tierIndex or offer.mode == "foot" then -- (5.0: the foot jobs stay)
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
	}
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
	Vehicles.setSpeedMultiplier(player, 1)
	-- 3.0: the crew stays together (no Crew.disband): the next mission is one START away.
	-- A company vehicle goes back; your own car comes to you.
	local jobType = job.offer.jobType
	if jobType and jobType.vehicle then
		local car = Vehicles.get(player)
		if car and car.id == jobType.vehicle then
			task.delay(2, function()
				if player.Parent and not jobs[player] then
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
	local foot = offer.mode == "foot" -- 5.0: no vehicle at all
	if foot then
		-- (your car, if you have one, stays where it is: it takes no part)
	elseif needsVehicle(player, offer) then
		return false, JobsConfig.Foot.NeedsVehicle
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
	cargoInfo.dests = offer.dests
	cargoInfo.destNames = offer.destNames
	-- 5.0, on foot: no vehicle; the pieces over the hands ride in the owner's pack (the backpack's room).
	cargoInfo.foot = if foot then true else nil
	cargoInfo.pack = if foot then Transport.packRoomOf(player) else nil
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
		nextStray = os.clock() + JobsConfig.Foot.StrayEvery * rng:NextNumber(0.8, 1.2),
	}
	jobs[player] = job
	placeDocks(player, offer)
	-- No pick-up: the vehicle starts loaded.
	if offer.stops[1].kind ~= "pickup" then
		Cargo.fill(session, offer.total)
	end
	Cargo.setStop(session, planOf(offer.stops[1]))
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

-- AcceptJob: the offer with that id (3.7) on the player's board. Taken from where the player is now (fromHere: the
-- same pay, more time for a longer drive to it); once started it leaves the board (the rest stay until refreshAt).
local function accept(player: Player, id: any)
	if jobs[player] then
		notice:FireClient(player, "Finish your current delivery first.")
		return
	end
	local board = boards[player.UserId]
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
	if takeOffer(player, taken) then
		local at = table.find(board.list, offer)
		if at then
			table.remove(board.list, at)
		end
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
	-- right after accepting gives none.
	local status = Cargo.status(job.cargo)
	local worked = job.kills > 0 or status.deliveredTotal > 0 or status.inCar > 0 or status.pack > 0 or job.stop > 1 -- (5.0: the pack)
	local offer = job.offer
	local xp = if worked then Levels.jobXp(offer.tier, status.deliveredTotal, job.kills, DayNight.isNight(), false) else 0
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

local function complete(player: Player, job: Job)
	local crew = crewOf(job, player) -- before endJob: the riders' seats and the members as they are now
	-- The mission's credit goes to who is there at the finish (in the car or near the owner), not who stayed home.
	local present: { Player } = {}
	for _, member in crew do
		if withOwner(player, member) then
			table.insert(present, member)
		end
	end
	local timeLeft = job.endsAt - workspace:GetServerTimeNow()
	endJob(player, job, true)
	local offer = job.offer
	local delivered = job.cargo.deliveredTotal
	-- A co-op mission pays more for every crew member besides the owner (everybody's share grows with it).
	local coopPay = if offer.coop then Economy.coopPay(#crew) else 1
	local pay = Economy.cargoPay(math.floor(offer.pay * coopPay + 0.5), delivered, offer.total)
	-- Finished at night: the pay is up (smoothly at dusk and dawn).
	local nightPay = Economy.nightScale(Config.DayNight.NightPay, DayNight.nightFactor())
	local night = DayNight.isNight()
	-- The gunner twist: a kill from a passenger seat counts GunnerKillBonus times in the kill bonus.
	local payout = Economy.payout(pay, job.condition, timeLeft, offer.time, Economy.paidKills(job.kills, job.gunnerKills), nightPay)
	-- A mission is rated (1 – 3 stars): the cargo's condition and the clock left.
	local stars = Missions.rate(job.condition, if offer.time > 0 then math.max(0, timeLeft) / offer.time else 0)
	local missionResult = if offer.mission
		then { id = offer.mission, name = if offer.jobType then offer.jobType.name else offer.mission, stars = stars }
		else nil
	-- 4.7: an ordinary or special job (not a mission) is rated ★ … ★★★ (JobRules.rate): the pay × the rating plus the
	-- owner's streak of good jobs, the XP × the rating; a good one counts toward the owner's licences.
	local profile = PlayerData.get(player)
	-- 4.8: food is rated and paid by its freshness too (JobRules.freshPay: the pay × FreshPayMin … 1).
	local freshness = if JobRules.hasRule(offer.rules, "food") then job.freshness else nil
	local rating = if offer.mission then nil else JobRules.rate(job.condition, if offer.time > 0 then math.max(0, timeLeft) / offer.time else 0, job.wrecked, job.cargo.lost, freshness)
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
	local driverTotal, share = Economy.crewSplit(payTotal, #crew)
	-- The split, for everybody's result: the owner first.
	local split = { { name = player.DisplayName, pay = driverTotal } }
	for _, member in crew do
		table.insert(split, { name = member.DisplayName, pay = share })
	end
	local xp = Levels.jobXp(offer.tier, delivered, job.kills, night, true)
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
				notice:FireClient(player, `{employer.person} gives you the {weapon.name}! Pick it on the weapon bar (Q).`)
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
	send(player)
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
	resultRemote:FireClient(player, withXp({
		employer = employerInfo,
		success = true,
		cargo = offer.cargo,
		customer = offer.customer,
		stars = offer.tier,
		condition = job.condition,
		kills = job.kills,
		payout = payout, -- with nightBonus
		night = night,
		crew = split, -- { { name, pay } }: everybody paid on this job, the owner first
		riders = #crew, -- crew members besides you
		crewBonus = driverTotal - payTotal,
		total = driverTotal,
		delivered = delivered, -- pieces that arrived
		pieces = offer.total, -- pieces of the job
		lost = job.cargo.lost,
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
	tellDelivered(player, true) -- 3.7: Jobs.onDelivered, after the pay
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

local function loseCondition(player: Player, job: Job, share: number, reason: string)
	job.condition = math.max(0, job.condition - share)
	job.dirty = true
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
	if not job or job.offer.mode == "foot" then
		return -- (5.0: a foot job's cargo is not in the car)
	end
	job.wrecked = true -- 4.7: the rating
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
	if job and car and job.offer.mode ~= "foot" then -- (5.0: a foot job's cargo is not in the car)
		local modifier = job.offer.modifier
		local multiplier = if modifier then modifier.conditionMultiplier else 1
		-- 4.8: a fragile cargo hit at speed loses more; Ratchet Straps cut every loss from driving (JobRules.damageLoss).
		local velocity = car.chassis.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local base = amount / car.stats.health * JobsConfig.ConditionPerDamage * multiplier
		job.condition = math.max(0, job.condition - JobRules.damageLoss(job.offer.rules, base, speed, Vehicles.hasGear(car, "straps")))
		job.dirty = true
		local now = os.clock()
		if JobRules.hasRule(job.offer.rules, "fragile") and speed >= JobsConfig.CargoRules.HitSpeed and now - job.ruleNotice >= JobsConfig.CargoRules.NoticeEvery then
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
	Cargo.setStop(job.cargo, planOf(nextStop))
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
	elseif lastStop and not job.guards and tier.guardHorde > 0 then
		job.guards = true
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
	local foot = JobsConfig.Foot
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
local SURVIVOR_NAMES = { "Jake", "Rosa", "Old Mike", "Priya", "Dmitri", "Hannah", "Carlos", "June", "Wes", "Lena" }

-- Every tick of a job with cargo rules: the food's freshness drains once it is picked up (a Cooler Box slows it), and
-- a fragile cargo or passengers in the moving car feel the jolts (hard braking, bumps: JobRules.jolt / joltLoss, the
-- Ratchet Straps cut it). Passengers who had enough end the job like the bandits do (loseCondition).
local function cargoRulesStep(player: Player, job: Job, car: Vehicles.Car?, step: number, now: number)
	local offer = job.offer
	local rules = offer.rules
	if #rules == 0 then
		return
	end
	local status = Cargo.status(job.cargo)
	if JobRules.hasRule(rules, "food") and job.freshness > 0 and (status.inCar > 0 or status.carrying ~= nil or job.stop > 1) then
		local shown = math.floor(job.freshness * 100 + 0.5)
		local warm = if offer.mode == "foot" then Transport.warmOf(player) else nil -- 5.0: a thermal jacket
		job.freshness = math.max(0, job.freshness - JobRules.freshDrain(offer.tier, step, car ~= nil and Vehicles.hasGear(car, "cooler"), warm))
		if math.floor(job.freshness * 100 + 0.5) ~= shown then
			job.dirty = true
		end
	end
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
		job.condition = math.max(0, job.condition - loss)
		job.dirty = true
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
local function addOnPossible(player: Player, job: Job): boolean
	local offer = job.offer
	local stop = offer.stops[job.stop]
	local car = Vehicles.get(player)
	if offer.dests or offer.mission or not stop or stop.kind ~= "drop" or stop.mode ~= "carry" or job.cargo.built or not car then
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
	Cargo.setStop(job.cargo, planOf(extra), true)
	blockStop(job)
	endEvent(player, job, `ADD-ON taken: pick up one more {offer.piece} from {addOn.giver} at {addOn.address.name} (+${addOn.pay}, +{seconds} s).`)
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
		takeAddOn(player, job, addOn)
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
	local tier = JobsConfig.Tiers[offer.tier]
	local modifier = offer.modifier
	local session = job.cargo
	if serverNow > job.endsAt then
		local reason = if offer.kind == "patient" then "Too late! The patient couldn't wait any longer."
			elseif offer.kind == "survivor" then "Too late! The survivors couldn't hold out any longer."
			elseif offer.look == "pizza" and offer.jobType then `Too late! The pizza went cold and {offer.customer} gave up on you.`
			else `Too late! {offer.customer} gave up on you.`
		Jobs.fail(player, reason)
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

	local stop = offer.stops[job.stop]
	local lastStop = job.stop == #offer.stops

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

	local flatDistance = Vector3.new(position.X - stop.park.X, 0, position.Z - stop.park.Z).Magnitude
	spawnHordes(player, job, tier, stop, lastStop, flatDistance)

	local multiplier = if modifier then modifier.spawnMultiplier else 1
	if offer.twists.defend and lastStop and not job.defendDone then
		defendStep(player, job, tier, stop, position, now, step, multiplier * nightWaves)
	end
	local foot = offer.mode == "foot"
	if foot then
		strayStep(player, job, position, now) -- 5.0: no waves, no bandits on foot
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
	job.cargo.deliveredTotal = math.max(job.cargo.deliveredTotal, job.offer.total)
	complete(player, job)
	return true
end

function Jobs.start()
	-- The quiet twist hears every shot (Gun does not require Jobs: no cycle).
	Gun.onShot = Jobs.onShot
	-- 3.7: opening the board sends the current offers; new ones only when they expired (or there were none yet).
	Net.get("RequestOffers").OnServerEvent:Connect(function(player)
		if not jobs[player] then
			sendBoard(player, boardOf(player))
		end
	end)
	Net.get("AcceptJob").OnServerEvent:Connect(accept)
	Net.get("RerollTier").OnServerEvent:Connect(reroll) -- 4.7
	roadEventRemote.OnServerEvent:Connect(answerRoadEvent) -- 4.8: the add-on's Y / NO
	Net.get("AcceptEmployer").OnServerEvent:Connect(acceptEmployer)
	Net.get("CancelJob").OnServerEvent:Connect(function(player)
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
	return {
		name = if offer.jobType then offer.jobType.name else `{offer.cargo} → {offer.customer}`,
		step = stop.label,
		hint = job.lastStep,
		position = stop.park,
		stars = offer.tier,
		endsAt = job.endsAt,
		stage = stop.kind,
		stopIndex = job.stop,
		stopCount = #offer.stops,
		cargo = offer.cargo,
		pay = offer.pay,
		delivered = job.cargo.deliveredTotal,
		total = offer.total,
		wave = job.wave,
		timed = offer.jobType ~= nil and offer.jobType.timeLimit ~= nil,
		crewCount = job.crewCount, -- paid besides the owner: the invited crew and whoever rode along
		mission = missionInfo(job),
		mode = offer.mode, -- 5.0
	}
end

return Jobs
