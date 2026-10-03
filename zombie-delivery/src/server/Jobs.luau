--!strict
-- Delivery jobs. The job board offers one ordinary delivery of every danger level (★ … ★★★★) measured from where
-- the player is, and one special job (Config.JobTypes): the Ice Cream Route and Moving Day lend you a company
-- vehicle, the Winter Run goes through the tunnel and over the frozen lake to the Ski Lodge.
--
-- A job is a list of stops: usually PICK UP (stop in the circle and hold still while it is loaded), then DELIVER
-- (hold still while it is unloaded, under fire). The enemies keep coming: a few zombies and, from ★★ up, bandit
-- roadblocks ahead of you. Far jobs often carry a modifier (RUSH, FRAGILE, HEAVY LOAD, WANTED).
--
-- Crew: friends riding in the car's passenger seats help (their kills count) and get paid too: every passenger gets
-- half of the payout and the driver +15 % per passenger (Economy.crewSplit).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)
local PlayerData = require(script.Parent.PlayerData)

type Stop = {
	address: Map.Address,
	kind: string, -- pickup | drop
	hold: number, -- seconds to stand still there
	label: string,
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
}

type Job = {
	offer: Offer,
	endsAt: number, -- workspace:GetServerTimeNow()
	condition: number, -- 0 … 1
	kills: number,
	stop: number, -- index into offer.stops
	hold: number, -- seconds stood in the circle
	guards: boolean, -- the horde at the last stop was spawned
	nextSpawn: number,
	nextAmbush: number,
	dirty: boolean, -- something changed, send it
}

local Jobs = {}

local offers: { [Player]: { Offer } } = {}
local jobs: { [Player]: Job } = {}
local nextAmbient: { [Player]: number } = {}
local rng = Random.new()

local jobRemote = Net.get("Job")
local resultRemote = Net.get("DeliveryResult")
local notice = Net.get("Notice")
local JobsConfig = Config.Jobs

local function playerPosition(player: Player): Vector3
	local car = Vehicles.seatedIn(player) or Vehicles.get(player)
	if car then
		return car.chassis.Position
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if rootPart then rootPart.Position else World.DepotSpawn
end

local function stopPosition(stop: Stop): Vector3
	return Vector3.new(stop.address.x, World.RoadTop, stop.address.z)
end

local function info(def: { name: string, description: string }?): { [string]: string }?
	if not def then
		return nil
	end
	return { name = def.name, description = def.description }
end

local function payload(job: Job): { [string]: any }
	local offer = job.offer
	local stop = offer.stops[job.stop]
	local last = offer.stops[#offer.stops]
	return {
		stars = offer.tier,
		cargo = offer.cargo,
		customer = offer.customer,
		address = last.address.name,
		district = last.address.district,
		position = stopPosition(stop),
		stage = stop.kind,
		stopIndex = job.stop,
		stopCount = #offer.stops,
		stopLabel = stop.label,
		progress = job.hold / math.max(stop.hold, 0.1),
		endsAt = job.endsAt,
		timeLimit = offer.time,
		condition = job.condition,
		kills = job.kills,
		pay = offer.pay,
		modifier = info(offer.modifier),
		jobType = info(offer.jobType),
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

local function routeLength(fromX: number, fromZ: number, stops: { Stop }): number
	local total = 0
	local x, z = fromX, fromZ
	for _, stop in stops do
		total += Map.manhattan(x, z, stop.address.x, stop.address.z)
		x, z = stop.address.x, stop.address.z
	end
	return total
end

local function finishOffer(tierIndex: number, stops: { Stop }, distance: number, cargo: string, customer: string, jobType: Config.JobTypeDef?): Offer
	local tier = JobsConfig.Tiers[tierIndex]
	local modifier: Config.ModifierDef? = nil
	if rng:NextNumber() < tier.modifierChance then
		modifier = pick(JobsConfig.Modifiers)
	end
	local holds = 0
	for _, stop in stops do
		holds += stop.hold
	end
	local pay = Economy.jobPay(tier, distance, modifier and modifier.payMultiplier)
	if jobType then
		pay += jobType.payPerStop * jobType.stops
	end
	return {
		tier = tierIndex,
		stops = stops,
		distance = distance,
		pay = pay,
		time = Economy.timeLimit(distance, modifier and modifier.timeMultiplier) + holds,
		cargo = cargo,
		customer = customer,
		jobType = jobType,
		modifier = modifier,
	}
end

local function ordinaryOffer(from: Vector3, tierIndex: number): Offer?
	local tier = JobsConfig.Tiers[tierIndex]
	local pickup = addressAround(from.X, from.Z, JobsConfig.PickupMinDistance, JobsConfig.PickupMaxDistance, 0, {})
	if not pickup then
		return nil
	end
	local drop = addressAround(pickup.x, pickup.z, tier.minDistance, tier.maxDistance, if tierIndex >= 3 then 3 else 0, { pickup })
	if not drop then
		return nil
	end
	local place = pick(JobsConfig.PickupPlaces)
	local customer = if drop.poi then drop.name else pick(JobsConfig.Customers)
	local stops: { Stop } = {
		{ address = pickup, kind = "pickup", hold = JobsConfig.LoadTime, label = `PICK UP at the {place}, {pickup.name}` },
		{ address = drop, kind = "drop", hold = JobsConfig.UnloadTime, label = `DELIVER to {customer}, {drop.name}` },
	}
	return finishOffer(tierIndex, stops, routeLength(from.X, from.Z, stops), pick(JobsConfig.Cargo[tierIndex]), customer, nil)
end

local function specialOffer(from: Vector3, jobType: Config.JobTypeDef): Offer?
	local stops: { Stop } = {}
	local customer = "Many customers"
	if jobType.id == "icecream" then
		-- Four stops one after another, starting not far away.
		local avoid: { Map.Address } = {}
		local x, z = from.X, from.Z
		for n = 1, jobType.stops do
			local address = addressAround(x, z, if n == 1 then 150 else 120, if n == 1 then 450 else 300, 0, avoid)
			if not address then
				return nil
			end
			table.insert(avoid, address)
			table.insert(stops, { address = address, kind = "drop", hold = jobType.unloadTime, label = `SELL ICE CREAM ({n}/{jobType.stops}) at {address.name}` })
			x, z = address.x, address.z
		end
	elseif jobType.id == "moving" then
		local house = addressAround(from.X, from.Z, 200, 600, 0, {})
		if not house then
			return nil
		end
		local newHome = addressAround(house.x, house.z, 500, 1100, 0, { house })
		if not newHome then
			return nil
		end
		customer = "The Novak family"
		table.insert(stops, { address = house, kind = "pickup", hold = jobType.loadTime, label = `LOAD THE FURNITURE at {house.name}` })
		table.insert(stops, { address = newHome, kind = "drop", hold = jobType.unloadTime, label = `UNLOAD at the new home, {newHome.name}` })
	else
		local place = if jobType.place then placeAddress(jobType.place) else nil
		local pickup = addressAround(from.X, from.Z, JobsConfig.PickupMinDistance, JobsConfig.PickupMaxDistance, 0, {})
		if not place or not pickup then
			return nil
		end
		customer = place.name
		table.insert(stops, { address = pickup, kind = "pickup", hold = jobType.loadTime, label = `PICK UP the {jobType.cargo}, {pickup.name}` })
		table.insert(stops, { address = place, kind = "drop", hold = jobType.unloadTime, label = `DELIVER to the {place.name}` })
	end
	return finishOffer(jobType.tier, stops, routeLength(from.X, from.Z, stops), jobType.cargo, customer, jobType)
end

local function describe(index: number, offer: Offer): { [string]: any }
	local last = offer.stops[#offer.stops]
	local jobType = offer.jobType
	local vehicle = if jobType and jobType.vehicle then Economy.findCar(jobType.vehicle) else nil
	return {
		index = index,
		stars = offer.tier,
		tierName = JobsConfig.Tiers[offer.tier].name,
		cargo = offer.cargo,
		customer = offer.customer,
		first = offer.stops[1].label,
		address = last.address.name,
		district = last.address.district,
		stops = #offer.stops,
		position = stopPosition(last),
		distance = math.floor(offer.distance),
		pay = offer.pay,
		time = offer.time,
		modifier = info(offer.modifier),
		jobType = info(jobType),
		vehicle = if vehicle then vehicle.name else nil,
	}
end

function Jobs.makeOffers(player: Player)
	local from = playerPosition(player)
	local list: { Offer } = {}
	local special = specialOffer(from, pick(Config.JobTypes))
	if special then
		table.insert(list, special)
	end
	for tierIndex = 1, #JobsConfig.Tiers do
		local offer = ordinaryOffer(from, tierIndex)
		if offer then
			table.insert(list, offer)
		end
	end
	offers[player] = list
	local out = {}
	for index, offer in list do
		table.insert(out, describe(index, offer))
	end
	Net.get("Offers"):FireClient(player, out)
end

-- ── Running a job ──────────────────────────────────────────────────────────

function Jobs.active(player: Player): boolean
	return jobs[player] ~= nil
end

local function endJob(player: Player, job: Job)
	jobs[player] = nil
	Vehicles.setSpeedMultiplier(player, 1)
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

local function accept(player: Player, index: any)
	if jobs[player] then
		notice:FireClient(player, "Finish your current delivery first.")
		return
	end
	local list = offers[player]
	if not list or type(index) ~= "number" then
		return
	end
	local offer = list[index]
	if not offer then
		return
	end
	local jobType = offer.jobType
	if jobType and jobType.vehicle then
		-- The company lends its vehicle, right next to you.
		local err = Vehicles.spawn(player, true, jobType.vehicle)
		if err then
			notice:FireClient(player, err)
			return
		end
	elseif not Vehicles.get(player) then
		notice:FireClient(player, "Call your car first (CAR button).")
		return
	end
	offers[player] = nil
	jobs[player] = {
		offer = offer,
		endsAt = workspace:GetServerTimeNow() + offer.time,
		condition = 1,
		kills = 0,
		stop = 1,
		hold = 0,
		guards = false,
		nextSpawn = os.clock() + 3,
		nextAmbush = os.clock() + 12,
		dirty = false,
	}
	Vehicles.setSpeedMultiplier(player, if offer.modifier then offer.modifier.speedMultiplier else 1)
	send(player)
	notice:FireClient(player, if jobType then `{jobType.name}: {offer.stops[1].label}` else offer.stops[1].label)
end

function Jobs.fail(player: Player, reason: string)
	local job = jobs[player]
	if not job then
		return
	end
	endJob(player, job)
	send(player)
	resultRemote:FireClient(player, { success = false, reason = reason })
end

local function complete(player: Player, job: Job, car: Vehicles.Car)
	local crew = Vehicles.passengersOf(car)
	endJob(player, job)
	local offer = job.offer
	local payout = Economy.payout(offer.pay, job.condition, job.endsAt - workspace:GetServerTimeNow(), offer.time, job.kills)
	local driverTotal, share = Economy.crewSplit(payout.total, #crew)
	local profile = PlayerData.get(player)
	if profile then
		profile.deliveries += 1
	end
	PlayerData.addMoney(player, driverTotal)
	send(player)
	resultRemote:FireClient(player, {
		success = true,
		cargo = offer.cargo,
		customer = offer.customer,
		stars = offer.tier,
		condition = job.condition,
		kills = job.kills,
		payout = payout,
		crew = #crew,
		crewBonus = driverTotal - payout.total,
		total = driverTotal,
	})
	for _, rider in crew do
		local riderProfile = PlayerData.get(rider)
		if riderProfile then
			riderProfile.deliveries += 1
		end
		PlayerData.addMoney(rider, share)
		resultRemote:FireClient(rider, { success = true, rider = true, driver = player.DisplayName, cargo = offer.cargo, customer = offer.customer, stars = offer.tier, total = share })
	end
end

-- The job a kill counts for: the killer's own, or the one of the car they ride in.
local function jobOwner(player: Player): Player?
	if jobs[player] then
		return player
	end
	local car, driving = Vehicles.seatedIn(player)
	if car and not driving and jobs[car.owner] then
		return car.owner
	end
	return nil
end

function Jobs.onKill(player: Player)
	local owner = jobOwner(player)
	local job = owner and jobs[owner]
	if job then
		job.kills += 1
		job.dirty = true
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

local elapsed = 0

local function update(dt: number)
	elapsed += dt
	if elapsed < 0.2 then
		return
	end
	elapsed = 0
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local job = jobs[player]
		local car = Vehicles.get(player)
		local position = playerPosition(player)
		local heading = if car then car.chassis.AssemblyLinearVelocity else nil

		if not job then
			-- A few enemies around even without a job (not for passengers: the driver's are enough).
			local ambient = Config.Horde.Ambient
			local ridingCar, driving = Vehicles.seatedIn(player)
			local passenger = ridingCar ~= nil and not driving
			if not passenger and now >= (nextAmbient[player] or 0) and not World.isSafe(position) then
				nextAmbient[player] = now + ambient.every
				if Zombies.countFor(player) < ambient.max then
					Zombies.spawnAround(player, position, heading, ambient.count, ambient.kinds)
				end
			end
			continue
		end

		local offer = job.offer
		local tier = JobsConfig.Tiers[offer.tier]
		local modifier = offer.modifier
		if serverNow > job.endsAt then
			Jobs.fail(player, `Too late! {offer.customer} gave up on you.`)
			continue
		end

		local stop = offer.stops[job.stop]
		local target = stopPosition(stop)
		local flat = Vector3.new(position.X - target.X, 0, position.Z - target.Z).Magnitude
		local lastStop = job.stop == #offer.stops

		if lastStop and not job.guards and tier.guardHorde > 0 and flat < JobsConfig.GuardTriggerDistance then
			job.guards = true
			Zombies.spawnGuards(player, target, Vector3.new(stop.address.nx, 0, stop.address.nz), tier.guardHorde, tier.kinds)
		end

		-- Loading / unloading: stand (almost) still in the circle.
		local holding = car ~= nil and flat < JobsConfig.DeliverRadius and Vehicles.isDriving(player) and Vehicles.speed(car) < JobsConfig.HoldMaxSpeed
		if holding and car then
			job.hold += 0.2
			job.dirty = true
			if job.hold >= stop.hold then
				if lastStop then
					complete(player, job, car)
					continue
				end
				job.stop += 1
				job.hold = 0
				local nextStop = offer.stops[job.stop]
				notice:FireClient(player, if stop.kind == "pickup" then `Loaded! Now: {nextStop.label}` else `Done! Next: {nextStop.label}`)
			end
		elseif job.hold > 0 then
			job.hold = 0
			job.dirty = true
		end

		local multiplier = if modifier then modifier.spawnMultiplier else 1
		if now >= job.nextSpawn and not World.isSafe(position) then
			job.nextSpawn = now + tier.spawnEvery / multiplier
			local room = math.floor(tier.maxZombies * multiplier) - Zombies.countFor(player)
			if room > 0 then
				Zombies.spawnAround(player, position, heading, math.min(room, tier.spawnCount), tier.kinds)
			end
		end
		if tier.ambushEvery > 0 and now >= job.nextAmbush and not World.isSafe(position) then
			job.nextAmbush = now + tier.ambushEvery / multiplier * rng:NextNumber(0.8, 1.2)
			ambush(player, position, heading, tier.ambushSize)
		end

		if job.dirty then
			send(player)
		end
	end
end

function Jobs.start()
	Net.get("RequestOffers").OnServerEvent:Connect(function(player)
		if not jobs[player] then
			Jobs.makeOffers(player)
		end
	end)
	Net.get("AcceptJob").OnServerEvent:Connect(accept)
	Net.get("CancelJob").OnServerEvent:Connect(function(player)
		Jobs.fail(player, "Delivery cancelled.")
	end)
	Players.PlayerRemoving:Connect(function(player)
		offers[player] = nil
		jobs[player] = nil
		nextAmbient[player] = nil
	end)
	RunService.Heartbeat:Connect(update)
end

function Jobs.sendTo(player: Player)
	send(player)
end

return Jobs
