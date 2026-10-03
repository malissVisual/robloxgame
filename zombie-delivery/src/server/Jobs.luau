--!strict
-- Delivery jobs. The job board offers one job of every danger level (★ … ★★★★) measured from where the player is.
-- Every job has two stops: first PICK UP the cargo (a shop or a warehouse not far away: stop in the circle and wait
-- while it is loaded), then DELIVER it (stop in the circle and hold out while it is unloaded).
-- the far ones go to the named places (the Military Base through the tunnel, the Radio Station, the Old Farm …) and
-- often carry a modifier (RUSH, FRAGILE, HEAVY LOAD, HORDE). An accepted job puts a destination on the map and a
-- timer on the screen. Zombies keep coming while it runs and a horde waits at the door. Stopping in the destination
-- circle while driving delivers: pay × cargo condition, + speed bonus, + kill bonus.
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

type Offer = {
	tier: number,
	pickup: Map.Address,
	pickupName: string,
	address: Map.Address,
	distance: number,
	pay: number,
	time: number,
	cargo: string,
	customer: string,
	modifier: Config.ModifierDef?,
}

type Job = {
	offer: Offer,
	endsAt: number, -- workspace:GetServerTimeNow()
	condition: number, -- 0 … 1
	kills: number,
	guards: boolean, -- the horde at the door was spawned
	nextSpawn: number,
	dirty: boolean, -- condition / kills changed, send it
	stage: string, -- pickup | deliver
	hold: number, -- seconds stood in the circle (loading / unloading)
}

local Jobs = {}

local offers: { [Player]: { Offer } } = {}
local jobs: { [Player]: Job } = {}
local nextAmbient: { [Player]: number } = {}
local rng = Random.new()

local jobRemote = Net.get("Job")
local resultRemote = Net.get("DeliveryResult")
local notice = Net.get("Notice")

local function playerPosition(player: Player): Vector3
	local car = Vehicles.seatedIn(player) or Vehicles.get(player)
	if car then
		return car.chassis.Position
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if rootPart then rootPart.Position else World.DepotSpawn
end

local function destination(offer: Offer): Vector3
	return Vector3.new(offer.address.x, World.RoadTop, offer.address.z)
end

local function pickupPosition(offer: Offer): Vector3
	return Vector3.new(offer.pickup.x, World.RoadTop, offer.pickup.z)
end

local function currentTarget(job: Job): Vector3
	return if job.stage == "pickup" then pickupPosition(job.offer) else destination(job.offer)
end

local function modifierInfo(modifier: Config.ModifierDef?): { [string]: string }?
	if not modifier then
		return nil
	end
	return { name = modifier.name, description = modifier.description }
end

local function payload(job: Job): { [string]: any }
	local offer = job.offer
	return {
		stars = offer.tier,
		cargo = offer.cargo,
		customer = offer.customer,
		address = offer.address.name,
		district = offer.address.district,
		position = currentTarget(job),
		destination = destination(offer),
		stage = job.stage,
		pickup = `{offer.pickupName}, {offer.pickup.name}`,
		progress = job.hold / (if job.stage == "pickup" then Config.Jobs.LoadTime else Config.Jobs.UnloadTime),
		endsAt = job.endsAt,
		timeLimit = offer.time,
		condition = job.condition,
		kills = job.kills,
		pay = offer.pay,
		modifier = modifierInfo(offer.modifier),
	}
end

local function send(player: Player)
	local job = jobs[player]
	jobRemote:FireClient(player, if job then payload(job) else nil)
	if job then
		job.dirty = false
	end
end

function Jobs.makeOffers(player: Player)
	local from = playerPosition(player)
	local list: { Offer } = {}
	local addresses = Map.addresses()
	local jobsConfig = Config.Jobs
	for tierIndex, tier in Config.Jobs.Tiers do
		-- The pickup: an ordinary address not far from the player.
		local pickups = {}
		local nearestPickup: Map.Address? = nil
		local nearestGap = math.huge
		for _, address in addresses do
			if address.poi then
				continue
			end
			local d = Map.manhattan(from.X, from.Z, address.x, address.z)
			if d >= jobsConfig.PickupMinDistance and d <= jobsConfig.PickupMaxDistance then
				table.insert(pickups, address)
			end
			local gap = math.abs(d - jobsConfig.PickupMinDistance)
			if gap < nearestGap then
				nearestPickup, nearestGap = address, gap
			end
		end
		local pickup = if #pickups > 0 then pickups[rng:NextInteger(1, #pickups)] else nearestPickup
		if not pickup then
			continue
		end
		local leg = Map.manhattan(from.X, from.Z, pickup.x, pickup.z)
		local fits = {}
		local closest: Map.Address? = nil
		local closestGap = math.huge
		for _, address in addresses do
			if address == pickup then
				continue
			end
			local d = Map.manhattan(pickup.x, pickup.z, address.x, address.z)
			if d >= tier.minDistance and d <= tier.maxDistance then
				table.insert(fits, address)
				-- The named places are the stars of the far jobs.
				if address.poi and tierIndex >= 3 then
					table.insert(fits, address)
					table.insert(fits, address)
				end
			end
			local gap = if d < tier.minDistance then tier.minDistance - d else d - tier.maxDistance
			if gap < closestGap then
				closest, closestGap = address, gap
			end
		end
		local address = if #fits > 0 then fits[rng:NextInteger(1, #fits)] else closest
		if address then
			local distance = leg + Map.manhattan(pickup.x, pickup.z, address.x, address.z)
			local modifier: Config.ModifierDef? = nil
			if rng:NextNumber() < tier.modifierChance then
				local modifiers = Config.Jobs.Modifiers
				modifier = modifiers[rng:NextInteger(1, #modifiers)]
			end
			local cargoList = Config.Jobs.Cargo[tierIndex]
			local customers = Config.Jobs.Customers
			local places = jobsConfig.PickupPlaces
			table.insert(list, {
				tier = tierIndex,
				pickup = pickup,
				pickupName = places[rng:NextInteger(1, #places)],
				address = address,
				distance = distance,
				pay = Economy.jobPay(tier, distance, modifier and modifier.payMultiplier),
				time = Economy.timeLimit(distance, modifier and modifier.timeMultiplier) + jobsConfig.LoadTime + jobsConfig.UnloadTime,
				cargo = cargoList[rng:NextInteger(1, #cargoList)],
				customer = if address.poi then address.name else customers[rng:NextInteger(1, #customers)],
				modifier = modifier,
			})
		end
	end
	offers[player] = list
	local out = {}
	for index, offer in list do
		table.insert(out, {
			index = index,
			stars = offer.tier,
			tierName = Config.Jobs.Tiers[offer.tier].name,
			cargo = offer.cargo,
			customer = offer.customer,
			address = offer.address.name,
			district = offer.address.district,
			pickup = `{offer.pickupName}, {offer.pickup.name}`,
			position = destination(offer),
			distance = math.floor(offer.distance),
			pay = offer.pay,
			time = offer.time,
			modifier = modifierInfo(offer.modifier),
		})
	end
	Net.get("Offers"):FireClient(player, out)
end

function Jobs.active(player: Player): boolean
	return jobs[player] ~= nil
end

local function endJob(player: Player)
	jobs[player] = nil
	Vehicles.setSpeedMultiplier(player, 1)
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
	if not Vehicles.get(player) then
		notice:FireClient(player, "Call your car first (CAR button).")
		return
	end
	offers[player] = nil
	jobs[player] = {
		offer = offer,
		endsAt = workspace:GetServerTimeNow() + offer.time,
		condition = 1,
		kills = 0,
		guards = false,
		nextSpawn = os.clock() + 3,
		dirty = false,
		stage = "pickup",
		hold = 0,
	}
	Vehicles.setSpeedMultiplier(player, if offer.modifier then offer.modifier.speedMultiplier else 1)
	send(player)
	notice:FireClient(player, `Pick up {offer.cargo} at the {offer.pickupName}!`)
end

function Jobs.fail(player: Player, reason: string)
	if not jobs[player] then
		return
	end
	endJob(player)
	send(player)
	resultRemote:FireClient(player, { success = false, reason = reason })
end

local function complete(player: Player, job: Job, car: Vehicles.Car)
	endJob(player)
	local offer = job.offer
	local payout = Economy.payout(offer.pay, job.condition, job.endsAt - workspace:GetServerTimeNow(), offer.time, job.kills)
	local crew = Vehicles.passengersOf(car)
	local driverTotal, share = Economy.crewSplit(payout.total, #crew)
	local profile = PlayerData.get(player)
	if profile then
		profile.deliveries += 1
	end
	PlayerData.addMoney(player, driverTotal)
	send(player)
	local result = {
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
	}
	resultRemote:FireClient(player, result)
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
		job.condition = math.max(0, job.condition - amount / car.stats.health * Config.Jobs.ConditionPerDamage * multiplier)
		job.dirty = true
	end
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
			-- A few wandering zombies even without a job (not for passengers: the driver's zombies are enough).
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
		local tier = Config.Jobs.Tiers[offer.tier]
		local modifier = offer.modifier
		if serverNow > job.endsAt then
			Jobs.fail(player, `Too late! {offer.customer} got eaten.`)
			continue
		end

		local target = currentTarget(job)
		local flat = Vector3.new(position.X - target.X, 0, position.Z - target.Z).Magnitude

		if job.stage == "deliver" and not job.guards and tier.guardHorde > 0 and flat < Config.Jobs.GuardTriggerDistance then
			job.guards = true
			Zombies.spawnGuards(player, target, Vector3.new(offer.address.nx, 0, offer.address.nz), tier.guardHorde, tier.kinds)
		end

		-- Loading / unloading: stand (almost) still in the circle.
		local holding = car ~= nil and flat < Config.Jobs.DeliverRadius and Vehicles.isDriving(player) and Vehicles.speed(car) < Config.Jobs.HoldMaxSpeed
		if holding and car then
			job.hold += 0.2
			job.dirty = true
			local needed = if job.stage == "pickup" then Config.Jobs.LoadTime else Config.Jobs.UnloadTime
			if job.hold >= needed then
				if job.stage == "pickup" then
					job.stage = "deliver"
					job.hold = 0
					notice:FireClient(player, `Loaded! Now deliver it to {offer.customer}.`)
				else
					complete(player, job, car)
					continue
				end
			end
		elseif job.hold > 0 then
			job.hold = 0
			job.dirty = true
		end

		if now >= job.nextSpawn and not World.isSafe(position) then
			local spawnMultiplier = if modifier then modifier.spawnMultiplier else 1
			job.nextSpawn = now + tier.spawnEvery / spawnMultiplier
			local room = math.floor(tier.maxZombies * spawnMultiplier) - Zombies.countFor(player)
			if room > 0 then
				Zombies.spawnAround(player, position, heading, math.min(room, tier.spawnCount), tier.kinds)
			end
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
