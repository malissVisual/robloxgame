--!strict
-- Delivery jobs. The job board offers one job of every danger level (★ … ★★★) measured from where the player is;
-- an accepted job puts a destination on the map and a timer on the screen. Zombies keep coming while it runs
-- (more and nastier for more stars) and a horde waits at the door of 2★ / 3★ customers. Stopping in the
-- destination circle while driving delivers: pay × cargo condition, + speed bonus, + kill bonus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local CityGrid = require(Shared.CityGrid)
local Net = require(Shared.Net)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)
local PlayerData = require(script.Parent.PlayerData)

type Offer = {
	tier: number,
	address: CityGrid.Address,
	distance: number,
	pay: number,
	time: number,
	cargo: string,
	customer: string,
}

type Job = {
	offer: Offer,
	endsAt: number, -- workspace:GetServerTimeNow()
	condition: number, -- 0 … 1
	kills: number,
	guards: boolean, -- the horde at the door was spawned
	nextSpawn: number,
	dirty: boolean, -- condition / kills changed, send it
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
	local car = Vehicles.get(player)
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

local function payload(job: Job): { [string]: any }
	local offer = job.offer
	return {
		stars = offer.tier,
		cargo = offer.cargo,
		customer = offer.customer,
		address = offer.address.name,
		position = destination(offer),
		endsAt = job.endsAt,
		timeLimit = offer.time,
		condition = job.condition,
		kills = job.kills,
		pay = offer.pay,
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
	local addresses = CityGrid.addresses()
	for tierIndex, tier in Config.Jobs.Tiers do
		local fits = {}
		local closest: CityGrid.Address? = nil
		local closestGap = math.huge
		for _, address in addresses do
			local d = CityGrid.manhattan(from.X, from.Z, address.x, address.z)
			if d >= tier.minDistance and d <= tier.maxDistance then
				table.insert(fits, address)
			end
			local gap = if d < tier.minDistance then tier.minDistance - d else d - tier.maxDistance
			if gap < closestGap then
				closest, closestGap = address, gap
			end
		end
		local address = if #fits > 0 then fits[rng:NextInteger(1, #fits)] else closest
		if address then
			local distance = CityGrid.manhattan(from.X, from.Z, address.x, address.z)
			local cargoList = Config.Jobs.Cargo[tierIndex]
			local customers = Config.Jobs.Customers
			table.insert(list, {
				tier = tierIndex,
				address = address,
				distance = distance,
				pay = Economy.jobPay(tier, distance),
				time = Economy.timeLimit(distance),
				cargo = cargoList[rng:NextInteger(1, #cargoList)],
				customer = customers[rng:NextInteger(1, #customers)],
			})
		end
	end
	offers[player] = list
	local out = {}
	for index, offer in list do
		table.insert(out, {
			index = index,
			stars = offer.tier,
			cargo = offer.cargo,
			customer = offer.customer,
			address = offer.address.name,
			distance = math.floor(offer.distance),
			pay = offer.pay,
			time = offer.time,
		})
	end
	Net.get("Offers"):FireClient(player, out)
end

function Jobs.active(player: Player): boolean
	return jobs[player] ~= nil
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
	}
	send(player)
	notice:FireClient(player, `Deliver {offer.cargo} to {offer.customer}!`)
end

function Jobs.fail(player: Player, reason: string)
	if not jobs[player] then
		return
	end
	jobs[player] = nil
	send(player)
	resultRemote:FireClient(player, { success = false, reason = reason })
end

local function complete(player: Player, job: Job)
	jobs[player] = nil
	local offer = job.offer
	local payout = Economy.payout(offer.pay, job.condition, job.endsAt - workspace:GetServerTimeNow(), offer.time, job.kills)
	local profile = PlayerData.get(player)
	if profile then
		profile.deliveries += 1
	end
	PlayerData.addMoney(player, payout.total)
	send(player)
	resultRemote:FireClient(player, {
		success = true,
		cargo = offer.cargo,
		customer = offer.customer,
		stars = offer.tier,
		condition = job.condition,
		kills = job.kills,
		payout = payout,
	})
end

function Jobs.onKill(player: Player)
	local job = jobs[player]
	if job then
		job.kills += 1
		job.dirty = true
	end
end

function Jobs.onCarDamaged(player: Player, amount: number)
	local job = jobs[player]
	local car = Vehicles.get(player)
	if job and car then
		job.condition = math.max(0, job.condition - amount / car.stats.health * Config.Jobs.ConditionPerDamage)
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
			-- A few wandering zombies even without a job.
			local ambient = Config.Horde.Ambient
			if now >= (nextAmbient[player] or 0) and not World.isSafe(position) then
				nextAmbient[player] = now + ambient.every
				if Zombies.countFor(player) < ambient.max then
					Zombies.spawnAround(player, position, heading, ambient.count, ambient.kinds)
				end
			end
			continue
		end

		local offer = job.offer
		local tier = Config.Jobs.Tiers[offer.tier]
		if serverNow > job.endsAt then
			Jobs.fail(player, `Too late! {offer.customer} got eaten.`)
			continue
		end

		local target = destination(offer)
		local flat = Vector3.new(position.X - target.X, 0, position.Z - target.Z).Magnitude

		if not job.guards and tier.guardHorde > 0 and flat < Config.Jobs.GuardTriggerDistance then
			job.guards = true
			Zombies.spawnGuards(player, target, Vector3.new(offer.address.nx, 0, offer.address.nz), tier.guardHorde, tier.kinds)
		end

		if car and flat < Config.Jobs.DeliverRadius and Vehicles.isDriving(player) and Vehicles.speed(car) < Config.Jobs.DeliverMaxSpeed then
			complete(player, job)
			continue
		end

		if now >= job.nextSpawn and not World.isSafe(position) then
			job.nextSpawn = now + tier.spawnEvery
			local room = tier.maxZombies - Zombies.countFor(player)
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
