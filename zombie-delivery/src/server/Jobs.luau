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
-- the payout and the owner +15 % per member (Economy.crewSplit). Each gets their own DeliveryResult with the whole
-- split; the crew breaks up when the job ends (Crew.disband). Jobs.crewStatus tells the members what the owner does.
--
-- 2.5: special jobs on the board (JobTypeDef.board: the Cash Transport, the Pizza Rush; the Winter Run) next to the
-- employers' ones (the City Clinic's Ambulance Run). A rush has a fixed clock (timeLimit); bandits want some cargo
-- more (banditBoost: roadblocks and chases that many times as often). At night (DayNight.nightFactor) the waves are
-- bigger and the pay higher (Config.DayNight). Driver levels (shared/Levels.luau): every finished or failed job gives
-- XP to the owner and the crew; danger levels and jobs above your level show on the board LOCKED, the server refuses
-- them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)
local BanditCars = require(script.Parent.BanditCars)
local PlayerData = require(script.Parent.PlayerData)
local Cargo = require(script.Parent.Cargo)
local DayNight = require(script.Parent.DayNight)
local Crew = require(script.Parent.Crew)

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
	crew: { [Player]: boolean }, -- everybody who rode in the owner's car during the job
	footSince: number?, -- handling cargo on foot at this stop since
	nextFoot: number,
	footWarned: boolean,
	lastStep: string,
	crewCount: number, -- paid crew members besides the owner (riders and invited), as last counted
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

local function payload(job: Job): { [string]: any }
	local offer = job.offer
	local stop = offer.stops[job.stop]
	local last = offer.stops[#offer.stops]
	local status = Cargo.status(job.cargo)
	local handling, step = Cargo.step(job.cargo)
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

local function finishOffer(tierIndex: number, stops: { Stop }, distance: number, cargo: string, customer: string, jobType: Config.JobTypeDef?, pieces: CargoInfo, extraPay: number): Offer
	local tier = JobsConfig.Tiers[tierIndex]
	local timeLimit = if jobType then jobType.timeLimit else nil
	local modifier: Config.ModifierDef? = nil
	if rng:NextNumber() < tier.modifierChance then
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
	return {
		tier = tierIndex,
		stops = stops,
		distance = distance,
		pay = Economy.jobPay(tier, distance, modifier and modifier.payMultiplier) + extraPay,
		time = timeLimit or (Economy.timeLimit(distance, modifier and modifier.timeMultiplier) + handling),
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
		boost = math.max(1, if jobType and jobType.banditBoost then jobType.banditBoost else 1),
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
	local roles = JobsConfig.People[jobType.id] or { giver = "townsperson", receiver = "townsperson" }
	local giver = personFrom(jobType.giver, roles.giver)
	local receiver = personFrom(jobType.receiver, roles.receiver)
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
	return finishOffer(jobType.tier, stops, routeLength(from.X, from.Z, stops), jobType.cargo, customer, jobType, pieces, jobType.payPerStop * #stops)
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

-- Everybody paid on this job besides the owner, still in the game: who rode in the owner's car during the job and
-- the invited crew members (each once).
local function crewOf(job: Job, owner: Player): { Player }
	local list = {}
	for rider in job.crew do
		if rider ~= owner and rider.Parent then
			table.insert(list, rider)
		end
	end
	for _, member in Crew.members(owner) do
		if member ~= owner and member.Parent and not table.find(list, member) then
			table.insert(list, member)
		end
	end
	return list
end

local function endJob(player: Player, job: Job, linger: boolean)
	jobs[player] = nil
	Cargo.finish(job.cargo, linger)
	Zombies.release(player) -- its zombies roam on, its bandits stand down
	Vehicles.setSpeedMultiplier(player, 1)
	Crew.disband(player) -- the crew breaks up with the job
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

local function startJob(player: Player, offer: Offer): boolean
	local jobType = offer.jobType
	if jobType and jobType.vehicle then
		-- The employer lends its vehicle, right next to you.
		local err = Vehicles.spawn(player, true, jobType.vehicle)
		if err then
			notice:FireClient(player, err)
			return false
		end
	elseif not Vehicles.get(player) then
		notice:FireClient(player, "Call your car first (CAR button).")
		return false
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
	local session = Cargo.begin(player, {
		kind = offer.kind,
		look = offer.look,
		piece = offer.piece,
		plural = offer.plural,
		total = offer.total,
		handles = handles,
		allowed = function(other: Player): boolean
			-- The owner, who rode along, and the invited crew.
			return other == player or crew[other] == true or isMember(player, other)
		end,
		changed = function()
			local current = jobs[player]
			if current then
				current.dirty = true
			end
		end,
	})
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
		footSince = nil,
		nextFoot = 0,
		footWarned = false,
		lastStep = "",
		crewCount = #Crew.members(player),
	}
	jobs[player] = job
	-- No pick-up: the vehicle starts loaded.
	if offer.stops[1].kind ~= "pickup" then
		Cargo.fill(session, offer.total)
	end
	Cargo.setStop(session, planOf(offer.stops[1]))
	Vehicles.setSpeedMultiplier(player, if offer.modifier then offer.modifier.speedMultiplier else 1)
	send(player)
	local text = if jobType then `{jobType.name}: {offer.stops[1].label}` else offer.stops[1].label
	if jobType and jobType.timeLimit then
		text ..= ` · {math.floor(offer.time / 60)}:{string.format("%02d", offer.time % 60)} on the clock!`
	elseif offer.boost > 1 then
		text ..= " · Every bandit in town wants this cargo!"
	end
	notice:FireClient(player, text)
	-- The invited crew hears about it too (their HUD follows the owner's job: server/Crew.luau, Jobs.crewStatus).
	for _, member in Crew.members(player) do
		notice:FireClient(member, `{player.DisplayName} took a job: {if jobType then jobType.name else offer.cargo}. Help them out!`)
	end
	return true
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
		startJob(player, offer)
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
	startJob(player, offer)
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
	local crew = crewOf(job, player) -- before endJob: it breaks the crew up
	endJob(player, job, true)
	local offer = job.offer
	local delivered = job.cargo.deliveredTotal
	local pay = Economy.cargoPay(offer.pay, delivered, offer.total)
	-- Finished at night: the pay is up (smoothly at dusk and dawn).
	local nightPay = Economy.nightScale(Config.DayNight.NightPay, DayNight.nightFactor())
	local night = DayNight.isNight()
	local payout = Economy.payout(pay, job.condition, job.endsAt - workspace:GetServerTimeNow(), offer.time, job.kills, nightPay)
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
		}, giveXp(member, xp)))
	end
end

-- The job a kill counts for: the killer's own, the one of the crew they were invited into, the one of the car they
-- ride in, or the one they help on foot.
local function jobOwner(player: Player): Player?
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
	if job then
		job.kills += 1
		job.dirty = true
	end
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
	end
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
		if now - job.stealNotice > 4 then
			job.stealNotice = now
			notice:FireClient(player, if patient then "Bandits at the ambulance! Get the patient out of here!" else "Bandits at the bus! The kids are scared, get them out of here!")
		end
		loseCondition(player, job, share, if patient then "The bandits got to the ambulance. The patient didn't make it." else "The bandits scared the kids away!")
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
			local reason = if job.offer.kind == "patient" then "The crash was too much for the patient." else "The crash scared the kids away."
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
	job.dirty = true
	notice:FireClient(player, if stop.kind == "pickup" then `All loaded! Now: {nextStop.label}` else `Done! Next: {nextStop.label}`)
end

-- The next zombie wave around you and ahead of you. No room (too many of yours alive, or the server is full): it
-- waits a little and the number does not go up, so the waves never stack.
local function sendWave(player: Player, job: Job, tier: Config.TierDef, position: Vector3, heading: Vector3?, multiplier: number)
	local number = job.wave + 1
	local room = Economy.waveAlive(tier, multiplier) - Zombies.countFor(player, true) -- the roadblocks' bandits do not count
	local size = math.min(Economy.waveSize(tier, number, multiplier), room)
	local made = if size > 0 then Zombies.spawnAround(player, position, heading, size, tier.waveKinds) else 0
	if made <= 0 then
		job.waveIn = JobsConfig.WavePostpone
		return
	end
	job.wave = number
	job.waveIn = Economy.waveEvery(tier, multiplier) * rng:NextNumber(0.9, 1.1)
	job.dirty = true
	notice:FireClient(player, `WAVE {number} · {made} {if made == 1 then "zombie" else "zombies"}`)
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
				elseif offer.look == "pizza" and offer.jobType then `Too late! The pizza went cold and {offer.customer} gave up on you.`
				else `Too late! {offer.customer} gave up on you.`
			Jobs.fail(player, reason)
			continue
		end

		-- Everybody who rides in the owner's car is crew (they may carry the cargo, their kills count).
		if car then
			for _, rider in Vehicles.passengersOf(car) do
				job.crew[rider] = true
			end
		end
		local crewCount = #crewOf(job, player)
		if crewCount ~= job.crewCount then
			job.crewCount = crewCount
			job.dirty = true
		end
		Cargo.update(session, step)
		if not jobs[player] then
			continue
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
		if lastStop and not job.guards and tier.guardHorde > 0 and flatDistance < JobsConfig.GuardTriggerDistance then
			job.guards = true
			Zombies.spawnGuards(player, stop.park, Vector3.new(stop.address.nx, 0, stop.address.nz), tier.guardHorde, tier.kinds)
		end

		local multiplier = if modifier then modifier.spawnMultiplier else 1
		if Cargo.onFoot(session) then
			-- Handling the cargo on foot: a few come at you, far enough to put it down and shoot (G).
			local wave = Tuning.FootWaves[offer.tier] or Tuning.FootWaves[1]
			if not job.footSince then
				job.footSince = now
				job.nextFoot = now + Tuning.FootGrace
			end
			if wave.count > 0 and now >= job.nextFoot and not World.isSafe(stop.park) then
				job.nextFoot = now + wave.every / multiplier * rng:NextNumber(0.85, 1.15)
				if Zombies.countFor(player) < wave.max * multiplier then
					Zombies.spawnAround(player, stop.park, nil, wave.count, tier.kinds)
					if not job.footWarned then
						job.footWarned = true
						notice:FireClient(player, "They are coming for you! Put it down (G) to shoot.")
					end
				end
			end
		else
			job.footSince = nil
			if not World.isSafe(position) then
				-- The zombie waves: the clock runs only out here, never in the safe zone or on foot at a stop.
				job.waveIn -= step
				if job.waveIn <= 0 then
					sendWave(player, job, tier, position, heading, multiplier * nightWaves)
				end
			end
			-- Wanted cargo (banditBoost): the bandit cars and the roadblocks come that many times as often.
			local bandits = multiplier * offer.boost
			local driving = Vehicles.isDriving(player)
			if driving and tier.chaseEvery > 0 and now >= job.nextChase and not World.isSafe(position) then
				job.nextChase = now + tier.chaseEvery / bandits * rng:NextNumber(0.8, 1.2)
				if BanditCars.countFor(player) < tier.chaseMax and BanditCars.chase(player, position, heading) then
					notice:FireClient(player, "Bandits are on your tail! Shoot them or lose them!")
				end
			end
			if driving and tier.ambushEvery > 0 and now >= job.nextAmbush and not World.isSafe(position) then
				job.nextAmbush = now + tier.ambushEvery / bandits * rng:NextNumber(0.8, 1.2)
				ambush(player, position, heading, tier.ambushSize)
			end
		end

		-- The HUD's instruction changes with what you do (parking, getting out): send it when it does.
		local _, text = Cargo.step(session)
		if text ~= job.lastStep then
			job.dirty = true
		end
		if job.dirty then
			send(player)
		end
	end
end

-- ── Admin tools (server/Admin.luau) ────────────────────────────────────────

-- Start any job now, next to the player: a Config.JobTypes id (with its vehicle), or "ordinary" / "ordinary1" …
-- "ordinary4" (also "tier1" …) for a job-board delivery of that danger level. A running job is cancelled.
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
		offer = if jobType then jobOffer(from, jobType) else nil
	end
	if not offer then
		notice:FireClient(player, `Cannot start "{jobTypeId}" here (unknown job or a missing place).`)
		return false
	end
	return startJob(player, offer)
end

-- Finish the current stop at once (loaded / delivered / served); the next tick moves on to the next stop.
function Jobs.adminFinishStop(player: Player): boolean
	local job = jobs[player]
	if not job then
		return false
	end
	local done = Cargo.adminFinish(job.cargo)
	job.dirty = true
	return done
end

function Jobs.start()
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
		for _, other in jobs do
			other.crew[player] = nil
		end
	end)
	RunService.Heartbeat:Connect(update)
end

function Jobs.sendTo(player: Player)
	send(player)
end

-- What the invited crew sees of the owner's job (server/Crew.luau Crew.statusOf, wired in Main), or nil without one:
-- name, step (the current stop: what to do there), position (its circle, for the GPS), stars, endsAt; and more for
-- the HUD: hint (the owner's on-foot step), stage, stopIndex / stopCount, cargo, pay, delivered / total, wave,
-- timed.
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
	}
end

return Jobs
