--!strict
-- Delivery jobs. The job board offers one ordinary delivery of every danger level (★ … ★★★★) measured from where
-- the player is, and sometimes a special job without an employer (the Winter Run). The employers (Config.Employers)
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
}

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
}

-- What a DeliveryResult says about the XP (shared/Levels.luau), the owner's and every member's own.
type XpInfo = { xp: number, level: number, rank: string, levelUp: boolean }

type CargoSpot = { pile: { x: number, z: number }, park: { x: number, z: number }, facing: { x: number, z: number } }

local Jobs = {}

local offers: { [Player]: { Offer } } = {}
local jobs: { [Player]: Job } = {}
local rng = Random.new()

local jobRemote = Net.get("Job")
local resultRemote = Net.get("DeliveryResult")
local notice = Net.get("Notice")
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
local function addressAround(x: number, z: number, low: number, high: number, poiWeight: number, avoid: { Map.Address }): Map.Address?
	local fits: { Map.Address } = {}
	local closest: Map.Address? = nil
	local closestGap = math.huge
	for _, address in Map.addresses() do
		if table.find(avoid, address) or (address.poi and poiWeight <= 0) then
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
local function geometry(address: Map.Address): (Vector3, Vector3, Vector3)
	local spots = (Map :: any).CargoSpots :: { [string]: CargoSpot }?
	local id = placeIdOf(address)
	local spot = if id and spots then spots[id] else nil
	local top = World.RoadTop
	if spot then
		local park = Vector3.new(spot.park.x, top, spot.park.z)
		local pile = Vector3.new(spot.pile.x, top, spot.pile.z)
		local facing = Vector3.new(spot.facing.x, 0, spot.facing.z)
		if facing.Magnitude < 0.1 then
			facing = Vector3.new(park.X - pile.X, 0, park.Z - pile.Z)
		end
		return park, pile, if facing.Magnitude > 0.1 then facing.Unit else Vector3.new(0, 0, -1)
	end
	local park = Vector3.new(address.x, top, address.z)
	local outward = Vector3.new(address.nx, 0, address.nz)
	if outward.Magnitude < 0.5 then
		outward = Vector3.new(0, 0, -1) -- an open yard: the pile is beside the circle
	end
	outward = outward.Unit
	return park, park - outward * Tuning.PileOffset, outward
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

local function finishOffer(tierIndex: number, stops: { Stop }, distance: number, cargo: string, customer: string, jobType: Config.JobTypeDef?, pieces: CargoInfo, extraPay: number): Offer
	local tier = JobsConfig.Tiers[tierIndex]
	local timeLimit = if jobType then jobType.timeLimit else nil
	local modifier: Config.ModifierDef? = nil
	-- A mission is told as it is written: no random modifier.
	local mission = if jobType then jobType.mission else nil
	if not mission and rng:NextNumber() < tier.modifierChance then
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
	}
end

-- An ordinary delivery: a business that fits the danger level sends 1 – 3 pieces to somebody who needs them.
local function ordinaryOffer(from: Vector3, tierIndex: number): Offer?
	local tier = JobsConfig.Tiers[tierIndex]
	local businesses: { Config.BusinessDef } = {}
	for _, business in JobsConfig.Businesses do
		if table.find(business.tiers, tierIndex) then
			table.insert(businesses, business)
		end
	end
	if #businesses == 0 then
		businesses = JobsConfig.Businesses
	end
	local business = pick(businesses)
	local pickup = addressAround(from.X, from.Z, JobsConfig.PickupMinDistance, JobsConfig.PickupMaxDistance, 0, {})
	if not pickup then
		return nil
	end
	local drop = addressAround(pickup.x, pickup.z, tier.minDistance, tier.maxDistance, if tierIndex >= 3 then 3 else 0, { pickup })
	if not drop then
		return nil
	end
	-- At a far place its own person takes it.
	local placeId = placeIdOf(drop)
	local receiver = (placeId and JobsConfig.PlacePeople[placeId]) or pick(business.receivers)
	local count = rng:NextInteger(business.pieces[1], business.pieces[2] or business.pieces[1])
	local customer = if drop.poi then `{receiver.name}, {drop.name}` else receiver.name
	local stops: { Stop } = {
		newStop(pickup, "pickup", "carry", count, `PICK UP at the {business.place}, {pickup.name}`, business.giver),
		newStop(drop, "drop", "carry", count, `DELIVER to {receiver.name}, {drop.name}`, receiver),
	}
	local pieces: CargoInfo = { kind = business.kind, look = business.look, piece = business.piece, plural = business.plural, total = count }
	return finishOffer(tierIndex, stops, routeLength(from.X, from.Z, stops), business.cargo, customer, nil, pieces, Tuning.PayPerPiece * count)
end

-- A special job's stops from its definition: the pick-ups (at a place, or homes around you), then the deliveries
-- (the last one at a place, or addresses on the way). The pieces are split over the pick-ups and over the drops.
local function jobOffer(from: Vector3, jobType: Config.JobTypeDef): Offer?
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
	return finishOffer(jobType.tier, stops, route, jobType.cargo, customer, jobType, pieces, jobType.payPerStop * #stops)
end

-- One card of the job board. A job above the player's level is shown LOCKED (locked, level): accepting it is refused.
local function describe(index: number, offer: Offer, playerLevel: number, nightPay: number): { [string]: any }
	local last = offer.stops[#offer.stops]
	local jobType = offer.jobType
	local vehicle = if jobType and jobType.vehicle then Economy.findCar(jobType.vehicle) else nil
	return {
		locked = offer.level > playerLevel,
		level = offer.level,
		special = jobType ~= nil, -- a special job (a board special: Cash Transport, Pizza Rush, Winter Run)
		timed = jobType ~= nil and jobType.timeLimit ~= nil, -- a rush: `time` is a fixed clock
		banditBoost = offer.boost, -- > 1: bandits want this cargo
		nightPay = if nightPay > 1.001 then nightPay else nil, -- it is night now: finished now, it pays this many times
		index = index,
		stars = offer.tier,
		tierName = JobsConfig.Tiers[offer.tier].name,
		cargo = offer.cargo,
		customer = offer.customer,
		first = offer.stops[1].label,
		address = last.address.name,
		district = last.address.district,
		stops = #offer.stops,
		position = last.park,
		distance = math.floor(offer.distance),
		pay = offer.pay,
		time = offer.time,
		modifier = info(offer.modifier),
		jobType = info(jobType),
		vehicle = if vehicle then vehicle.name else nil,
		pieces = offer.total,
		piece = offer.piece,
		piecesName = offer.plural,
		handling = offer.stops[1].mode,
		itemKind = offer.kind,
	}
end

function Jobs.makeOffers(player: Player)
	local from = playerPosition(player)
	local list: { Offer } = {}
	-- Board specials (JobTypeDef.board, or no employer: the Cash Transport, the Pizza Rush, the Winter Run): up to two
	-- of them, each with its chance (Config.Jobs.BoardSpecials), a different one each, locked ones included (the
	-- card says from which level).
	local boardJobs: { Config.JobTypeDef } = {}
	for _, jobType in Config.JobTypes do
		if Economy.onBoard(jobType) then
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
	-- One ordinary delivery of every danger level (the ones above your level locked).
	for tierIndex = 1, #JobsConfig.Tiers do
		local offer = ordinaryOffer(from, tierIndex)
		if offer then
			table.insert(list, offer)
		end
	end
	offers[player] = list
	local level = PlayerData.level(player)
	local nightPay = Economy.nightScale(Config.DayNight.NightPay, DayNight.nightFactor())
	local out = {}
	for index, offer in list do
		table.insert(out, describe(index, offer, level, nightPay))
	end
	Net.get("Offers"):FireClient(player, out)
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

local function endJob(player: Player, job: Job, linger: boolean)
	jobs[player] = nil
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

-- Starts the job. False and why not (no notice: the caller tells the player).
local function startJob(player: Player, offer: Offer): (boolean, string?)
	local jobType = offer.jobType
	if jobType and jobType.vehicle then
		-- The employer lends its vehicle, right next to you.
		local err = Vehicles.spawn(player, true, jobType.vehicle)
		if err then
			return false, err
		end
	elseif not Vehicles.get(player) then
		return false, "Call your car first (CAR button)."
	end
	offers[player] = nil
	local crew: { [Player]: boolean } = {}
	local handles = false
	for _, stop in offer.stops do
		if stop.mode == "carry" or stop.mode == "lead" then
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
	}
	jobs[player] = job
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

local function accept(player: Player, index: any)
	local list = offers[player]
	local offer = if list and type(index) == "number" then list[index] else nil
	if not offer then
		if jobs[player] then
			notice:FireClient(player, "Finish your current delivery first.")
		end
		return
	end
	if canTake(player, offer.level) then
		startOrTell(player, offer)
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
	local worked = job.kills > 0 or status.deliveredTotal > 0 or status.inCar > 0 or job.stop > 1
	local offer = job.offer
	local xp = if worked then Levels.jobXp(offer.tier, status.deliveredTotal, job.kills, DayNight.isNight(), false) else 0
	endJob(player, job, false)
	send(player)
	resultRemote:FireClient(player, withXp({ success = false, reason = reason, cargo = offer.cargo, stars = offer.tier }, giveXp(player, xp)))
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
	local driverTotal, share = Economy.crewSplit(payout.total, #crew)
	-- The split, for everybody's result: the owner first.
	local split = { { name = player.DisplayName, pay = driverTotal } }
	for _, member in crew do
		table.insert(split, { name = member.DisplayName, pay = share })
	end
	local xp = Levels.jobXp(offer.tier, delivered, job.kills, night, true)
	local profile = PlayerData.get(player)
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
				notice:FireClient(player, `{employer.name} gives you the {rewardCar.name}! Switch to it at the depot garage.`)
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
		crewBonus = driverTotal - payout.total,
		total = driverTotal,
		delivered = delivered, -- pieces that arrived
		pieces = offer.total, -- pieces of the job
		lost = job.cargo.lost,
		piece = offer.piece,
		piecesName = offer.plural,
		unlockedWeapon = unlockedWeapon,
		mission = missionResult, -- 3.0: { id, name, stars } of a mission
		coopPay = if offer.coop then coopPay else nil, -- a co-op mission: the pay × this for the crew
	}, giveXp(player, xp)))
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
	if not job then
		return
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
	if job and car then
		local modifier = job.offer.modifier
		local multiplier = if modifier then modifier.conditionMultiplier else 1
		job.condition = math.max(0, job.condition - amount / car.stats.health * JobsConfig.ConditionPerDamage * multiplier)
		job.dirty = true
	end
end

-- A bandit roadblock on the road ahead of a moving car.
local function ambush(player: Player, position: Vector3, heading: Vector3?, size: number)
	if not heading then
		return
	end
	local flat = Vector3.new(heading.X, 0, heading.Z)
	if flat.Magnitude < 10 then
		return
	end
	local forward = flat.Unit
	local ahead = position + forward * JobsConfig.AmbushDistance
	local x, z, dx, dz = Map.nearestRoad(ahead.X, ahead.Z)
	local spot = Vector3.new(x, World.RoadTop, z)
	if Map.isSafe(x, z) or (spot - position).Magnitude < 100 then
		return
	end
	local along = Vector3.new(dx, 0, dz)
	if along:Dot(forward) < 0 then
		along = -along
	end
	Zombies.roadblock(player, spot, along, size)
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

local elapsed = 0

local function update(dt: number)
	elapsed += dt
	if elapsed < 0.2 then
		return
	end
	local step = elapsed
	elapsed = 0
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	-- Bigger and more frequent waves at night (Economy.waveSize / waveEvery / waveAlive take it like WANTED does).
	local nightWaves = Economy.nightScale(Config.DayNight.NightWaves, DayNight.nightFactor())
	for _, player in Players:GetPlayers() do
		local job = jobs[player]
		local car = Vehicles.get(player)
		local position = playerPosition(player)
		local heading = if car then car.chassis.AssemblyLinearVelocity else nil

		if not job then
			continue -- free roam: only the roaming zombies (server/Zombies.luau), no bandits
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
			continue
		end
		-- Spotless: the cargo got too damaged (car hits, bandits, shots).
		if spotlessFailed(player, job) then
			continue
		end
		-- 3.2, DUO: the partner must stay in the crew (they left it, or the game).
		if offer.duo then
			if #Crew.members(player) >= Config.Missions.Duo.MinCrew then
				job.duoTeamed = true
			elseif job.duoTeamed then
				Jobs.fail(player, "Your partner left.")
				continue
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
			continue
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
			continue
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
		if Cargo.onFoot(session) then
			footWave(player, job, tier, stop, now, multiplier)
		else
			roadEnemies(player, job, tier, position, heading, now, step, multiplier, nightWaves)
		end

		-- The HUD's instruction changes with what you do (parking, getting out): send it when it does.
		local _, text = stepOf(job)
		if text ~= job.lastStep then
			job.dirty = true
		end
		if job.dirty then
			send(player)
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
-- that danger level. A running job is cancelled.
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
	if tierText then
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

function Jobs.start()
	-- The quiet twist hears every shot (Gun does not require Jobs: no cycle).
	Gun.onShot = Jobs.onShot
	Net.get("RequestOffers").OnServerEvent:Connect(function(player)
		if not jobs[player] then
			Jobs.makeOffers(player)
		end
	end)
	Net.get("AcceptJob").OnServerEvent:Connect(accept)
	Net.get("AcceptEmployer").OnServerEvent:Connect(acceptEmployer)
	Net.get("CancelJob").OnServerEvent:Connect(function(player)
		Jobs.fail(player, "Delivery cancelled.")
	end)
	Players.PlayerRemoving:Connect(function(player)
		offers[player] = nil
		local job = jobs[player]
		if job then
			jobs[player] = nil
			Cargo.finish(job.cargo, false)
			Crew.disband(player)
		end
		DuoGates.clear(player)
		for _, other in jobs do
			other.crew[player] = nil
			other.members[player] = nil
			other.quietNotice[player] = nil
		end
	end)
	RunService.Heartbeat:Connect(update)
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
	}
end

return Jobs
