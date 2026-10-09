--!strict
-- The shops in the safe zone around the park. You walk in and use the prompt at the counter (it opens the shop on
-- your screen); the purchases are checked here, also that you really stand in that shop and that your driver level
-- (shared/Levels.luau) is high enough for what you buy (the level field of Config.Cars, Weapons and CarGuns).
--
--   Dead End Motors     cars, from the catalog at the sales counter (3.5: no lot of every car outside any more; a
--                       small showroom inside shows three of them, World.DealerSlots, each with a "Look" prompt that
--                       opens the catalog on it); every car needs a free car slot (Estate.carSlots: homes and garages
--                       add them; the employers' company cars take none). 3.4: a bought car goes into your garage:
--                       take it out there (server/Garages.luau)
--   Lead & Co.          guns (not the earned ones, Config.Weapons earned: an employer gives those; 6.7: nor the
--                       starter pistol, every profile has it), 6.7: the gun tracks of the "Upgrade" remote (Gun Damage,
--                       Fire Rate: for all your guns, moved here from Wrench Garage) and the Baseball Bat (Config.Kit
--                       shop "guns": the "Kit" remote)
--   Wrench Garage       upgrades (3.3: the car tracks for the equipped car), 3.5: the
--                       car's next STAGE (the "Upgrade" remote with id "stage": Config.Cars stages, its own look),
--                       paint jobs and car guns (one on the roof of the equipped car); 3.4: its repair bays are
--                       server/Repair.luau's (no free repairs any more); 4.6: GEAR for the equipped car (the "Gear"
--                       remote: buy it, from its level; install it in a free gear slot or remove it, free)
--   Last Stop Supplies  consumables (6.7: the car-only ones, Config.Items car, only to a player who owns a car:
--                       Economy.ownsCar); 5.0: personal gear (the "Kit" remote, Config.Kit: 6.0: the vests), yours
--                       for good (profile.kit, shared/Transport.luau; 6.7: no Thermal Jacket, 6.12.2: no Running Shoes
--                       any more). 6.12.2: the GEAR counter of the gear stall at the spawn (server/GearStall.luau)
--   ZDC Bags            6.6: the depot's bag kiosk (Map.Shops.bags, Config.BagShop; 6.12.2: the gear stall's BAGS counter):
--                       the five bags (Config.Kit pieces with `extra`, the same "Kit" remote: a bag is bought only
--                       here, the rest of the kit only at Last Stop Supplies); the Kit remote's ("use", bag id) picks
--                       the one in your hand (profile.activeBag), anywhere. 6.6: no backpacks any more
--   Depot Garage        3.4: the depot lot's garage terminal (server/Garages.luau: the starting van, company vehicles);
--                       it sells nothing (6.7: no shop window of its own in client/Hud.luau)
--   Job Board           the depot's job board
--
-- 5.0: you start on foot (profile.car nil): everything for "the equipped car" says you have no vehicle yet. The Old
-- Van is not sold here (Config.VanQuest: Earl sells it, server/VanQuest.luau); a first car bought here anyway is the one
-- you drive, parked on the road outside the dealer (you get in yourself).
--
-- 5.1, Spoke & Chain (Map.Shops.bikes, Config.BikeShop): the bikes (Config.Cars bike = true: the "Buy" remote's "car"
-- kind, at the bike shop, no garage slot needed) and the bike gear (Config.Gear bikeOnly: the "Gear" remote for your
-- bike, at the bike shop; the car gear stays at Wrench Garage, never on a bike). A bike on display for each one
-- (World.BikeSlots, a "Look" prompt). You may own bikes and cars: profile.car is the one CAR / MY BIKE brings,
-- profile.bike your bike of choice, profile.lastCar the car you got off. The "Equip" remote: ("bike", id) makes an
-- owned bike your bike of choice (and the one you ride, while you ride one); ("ride") gets you on your bike (the
-- phone's MY BIKE: it comes at once, server/Vehicles.luau); ("drive") back to your car (the phone's CALL CAR: the
-- chauffeur brings it). Not during a car job. No car upgrades, stages, paint or car guns on a bike.
-- 6.12.7: one shop, Dead End Motors: the bikes are its BIKES counter (Map.Shops.bikes: Kip, beside Sal's CARS
-- counter; its radius over the counter and the stands, Config.BikeShop), the display bikes on their stands behind its
-- front glass. The shop ids, the remotes and the checks are as before; Spoke & Chain's old building sells nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local TransportRules = require(Shared.Transport)
local VanQuestRules = require(Shared.VanQuest)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local PlayerData = require(script.Parent.PlayerData)
local Estate = require(script.Parent.Estate)
local Garages = require(script.Parent.Garages)
local Jobs = require(script.Parent.Jobs)
local CarCall = require(script.Parent.CarCall)
local Cargo = require(script.Parent.Cargo) -- 6.4: is the bag busy (no switching then)

local Shops = {}

local notice = Net.get("Notice")
local openShop = Net.get("OpenShop")
local NO_CAR = `You don't have a vehicle yet. The Old Van: {Config.VanQuest.Where}.`
local ON_BIKE = "That's your bike: bikes take bike gear at Dead End Motors' BIKES counter, no car upgrades, paint or car guns. CALL CAR on your phone for your car."

-- 5.1: the cars of your own (not a company vehicle, not a bike) and the bikes you own, in Config.Cars' order.
local function owned(profile: PlayerData.Profile, bikes: boolean): { string }
	local list: { string } = {}
	for _, def in Config.Cars do
		if profile.cars[def.id] and not def.company and (def.bike == true) == bikes then
			table.insert(list, def.id)
		end
	end
	return list
end

-- 5.1: your bike of choice (profile.bike while you own it, else your first bike), nil without one.
local function myBike(profile: PlayerData.Profile): string?
	local chosen = profile.bike
	if chosen and profile.cars[chosen] and TransportRules.isBike(chosen) then
		return chosen
	end
	return owned(profile, true)[1]
end

-- 5.1: may the vehicle you drive change now? Not while a job runs in it (a foot or bike job's pieces are in the pack).
local function midJob(player: Player): boolean
	if Jobs.active(player) and not Jobs.isFoot(player) then
		notice:FireClient(player, "Finish your delivery first: the job's vehicle stays with you.")
		return true
	end
	return Jobs.vehicleFor(player) ~= nil
end


local function nearShop(player: Player, shop: string): boolean
	local info = Map.Shops[shop]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not info or not root then
		return false
	end
	return Vector3.new(root.Position.X - info.x, 0, root.Position.Z - info.z).Magnitude < Map.shopRadius(shop) -- (6.6: a kiosk's own)
end

local function refuse(player: Player, shop: string): boolean
	if nearShop(player, shop) then
		return false
	end
	notice:FireClient(player, `Go to {Map.Shops[shop].name} for that.`)
	return true
end

-- Is this above the player's driver level? Then it says so and refuses (true).
local function tooLow(player: Player, name: string, level: number?): boolean
	local mine = PlayerData.level(player)
	if level == nil or mine >= level then
		return false
	end
	notice:FireClient(player, `The {name} needs driver level {level} ({Levels.rank(level)}). You are level {mine}: deliveries give XP.`)
	return true
end

-- Every car you own needs a slot (server/Estate.luau: Config.Estate.BaseCarSlots + the garages of your homes and
-- garages). The company vehicles earned from employers do not take one, and the cars you have stay even when the
-- slots shrink (a garage sold): only buying needs a free slot. True (and a notice) when there is none.
local function noSlot(player: Player): boolean
	local used, slots = Estate.carsOwned(player), Estate.carSlots(player)
	if used < slots then
		return false
	end
	notice:FireClient(player, `No free garage slot ({used} cars, {slots} slots). Buy or rent a garage (ESTATE, H) first.`)
	return true
end

-- 3.4: the name of a garage of the player's (the first one in the list), for "it waits in your Rented Lockup".
local function aGarage(player: Player): string
	local profile = PlayerData.get(player)
	for _, def in Config.Estate.Properties do
		if profile and profile.properties[def.id] and def.garageSlots > 0 then
			return def.name
		end
	end
	return "garage"
end

-- 5.1: a bike at Spoke & Chain: its level and price, no garage slot. It becomes your bike of choice; when you have no
-- vehicle or ride a bike (and no car job runs) it is the one you ride, parked on the road outside the shop.
local function buyBike(player: Player, profile: PlayerData.Profile, def: Config.CarDef)
	if profile.cars[def.id] then
		notice:FireClient(player, `You already have the {def.name}. EQUIP it here, or MY BIKE on your phone.`)
		return
	end
	if refuse(player, "bikes") or tooLow(player, def.name, def.level) then
		return
	end
	if not PlayerData.spend(player, def.price, "Bike", def.id) then
		notice:FireClient(player, "Not enough money.")
		return
	end
	local first = myBike(profile) == nil
	profile.cars[def.id] = true
	profile.bike = def.id
	local ride = (profile.car == nil or TransportRules.isBike(profile.car)) and not (Jobs.active(player) and not Jobs.isFoot(player)) and not Jobs.vehicleFor(player)
	if ride then
		profile.car = def.id
	end
	PlayerData.notify(player)
	task.spawn(PlayerData.save, player) -- (a purchase: saved now)
	local parked = false
	if ride then
		local shop = Map.Shops.bikes
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local from = if root and root:IsA("BasePart") then root.Position else Vector3.new(shop.x, 0, shop.z)
		local x, z, dx, dz = Map.nearestRoad(from.X, from.Z)
		local spot = Vector3.new(x, Map.RoadTop, z)
		parked = Vehicles.placeAt(player, nil, CFrame.lookAt(spot, spot + Vector3.new(dx, 0, dz)), false) ~= nil
	end
	local where = if parked then "It is on the road outside: hop on." elseif ride then "MY BIKE on your phone brings it." else "Your car stays the one you drive: MY BIKE on your phone gets you on the bike."
	notice:FireClient(player, `🚲 The {def.name} is yours! {where}{if first then " The BIKE runs are on your board now." else ""}`)
	if first then
		Net.get("Tutorial"):FireClient(player, "message", { from = "Marge", text = Config.BikeShop.Bought })
	end
end

local function onBuy(player: Player, kind: any, id: any, amount: any)
	local profile = PlayerData.get(player)
	if not profile or type(id) ~= "string" then
		return
	end
	if kind == "car" then
		local def = Economy.findCar(id)
		if def and def.bike then
			buyBike(player, profile, def) -- 5.1: at Spoke & Chain
			return
		end
		if def and VanQuestRules.isQuestCar(id) and not profile.cars[id] then
			-- 5.0: sold privately (Earl's Used Wheels, Marge's quest), not here.
			notice:FireClient(player, `The {def.name} is not sold here. {Config.VanQuest.DealerNote}`)
			return
		end
		if not def or def.company or profile.cars[id] or refuse(player, "dealer") or tooLow(player, def.name, def.level) or noSlot(player) then
			return
		end
		if not PlayerData.spend(player, def.price, "Car", def.id) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		profile.cars[id] = true
		local riding = TransportRules.isBike(profile.car)
		if profile.car == nil or (riding and #owned(profile, false) == 1 and not (Jobs.active(player) and not Jobs.isFoot(player))) then
			-- 5.0: your first vehicle: it is the one you drive, parked on the road outside (you get in yourself; a
			-- running job's lent company vehicle stays out until the job is over). 5.1: your first car while you ride
			-- your bike too (the bike stays your bike of choice: MY BIKE).
			if riding then
				profile.bike = profile.car
			end
			profile.car = id
			PlayerData.notify(player)
			local parked = false
			if not Jobs.vehicleFor(player) then
				local shop = Map.Shops.dealer
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local from = if root and root:IsA("BasePart") then root.Position else Vector3.new(shop.x, 0, shop.z)
				local x, z, dx, dz = Map.nearestRoad(from.X, from.Z)
				local spot = Vector3.new(x, Map.RoadTop, z)
				parked = Vehicles.placeAt(player, nil, CFrame.lookAt(spot, spot + Vector3.new(dx, 0, dz)), false) ~= nil
			end
			notice:FireClient(player, if parked then `You bought the {def.name}! It is parked on the road outside: your first vehicle. The car jobs are on your board now.`
				else `You bought the {def.name}! Press CAR to call it.`)
			return
		end
		-- 3.4: it goes into your garage (cars are kept in garages): take it out there.
		notice:FireClient(player, `You bought the {def.name}! It waits in your {aGarage(player)}: take it out at the 🅿 GARAGE post there (E).`)
		PlayerData.notify(player)
	elseif kind == "weapon" then
		local def = Economy.findWeapon(id)
		if not def or profile.weapons[id] then
			return
		end
		if def.starter then
			-- 6.7: the starter pistol is not sold: every profile has it (one that somehow lacks it gets it back, free)
			PlayerData.giveWeapon(player, def.id)
			notice:FireClient(player, `The {def.name} is your starter gun: it's yours.`)
			return
		end
		if def.exclusive then
			-- 3.1: a reward nobody can buy (Config.Rewards).
			notice:FireClient(player, `The {def.name} is not for sale. It is a reward: you will know when you have earned it.`)
			return
		end
		if def.earned then
			-- Not for sale: an employer gives it to the couriers who work for them.
			local employer = Economy.findEmployer(def.earned)
			notice:FireClient(player, `The {def.name} is not for sale. Work for {if employer then employer.name else "its owner"} to earn it.`)
			return
		end
		if refuse(player, "guns") or tooLow(player, def.name, def.level) then
			return
		end
		if not PlayerData.spend(player, def.price, "Gun", def.id) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		profile.weapons[id] = true
		profile.weapon = id
		notice:FireClient(player, `{def.name} is yours, ready to fire!`)
		PlayerData.notify(player)
	elseif kind == "cargun" then
		-- A roof gun for the equipped car: it replaces the one there (no refund).
		local def = Economy.findCarGun(id)
		local carDef = if profile.car then Economy.findCar(profile.car) else nil
		if not def or refuse(player, "mechanic") then
			return
		end
		if not carDef then
			notice:FireClient(player, NO_CAR)
			return
		end
		if not Economy.canMount(carDef.id) then
			notice:FireClient(player, `The {carDef.name} can't carry a gun.`)
			return
		end
		if profile.carGuns[carDef.id] == def.id then
			notice:FireClient(player, `Your {carDef.name} already has the {def.name}.`)
			return
		end
		if tooLow(player, def.name, def.level) then
			return
		end
		if not PlayerData.spend(player, def.price, "CarGun", def.id) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		profile.carGuns[carDef.id] = def.id
		notice:FireClient(player, `{def.name} mounted on your {carDef.name}! The driver fires it.`)
		Vehicles.refreshGun(player)
		PlayerData.notify(player)
	elseif kind == "item" then
		local def = Economy.findItem(id)
		if not def or refuse(player, "supplies") then
			return
		end
		if not Economy.itemShown(def, profile.cars) then
			notice:FireClient(player, `The {def.name} is for a car: you don't have one yet.`) -- 6.7 (Config.Items car)
			return
		end
		local count =if type(amount) == "number" and amount == amount and math.abs(amount) < math.huge then math.clamp(math.floor(amount), 1, 10) else 1
		count = math.min(count, def.max - (profile.items[id] or 0))
		if count <= 0 then
			notice:FireClient(player, `You cannot carry more {def.name}s.`)
			return
		end
		if not PlayerData.spend(player, def.price * count, "Item", def.id) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		PlayerData.addItem(player, id, count)
	end
end

-- 5.1, the phone's MY BIKE ("ride"): your bike of choice becomes the vehicle you ride (your car is remembered for
-- CALL CAR) and comes to you (Vehicles.spawn: a bike at once, by the kerb). Again while on it: it comes again.
local function ride(player: Player, profile: PlayerData.Profile)
	local bikeId = myBike(profile)
	if not bikeId then
		notice:FireClient(player, `No bike yet: {Config.BikeShop.Shop} on {Config.BikeShop.Street} sells them from level {Config.Jobs.Bike.Level}.`)
		return
	end
	Jobs.returnLent(player)
	if profile.car ~= bikeId and midJob(player) then
		return
	end
	if CarCall.busy(player) then
		CarCall.cancel(player)
	end
	if profile.car and not TransportRules.isBike(profile.car) then
		profile.lastCar = profile.car
	end
	profile.car = bikeId
	profile.bike = bikeId
	PlayerData.notify(player)
	local err = Vehicles.spawn(player, false)
	if err then
		notice:FireClient(player, err)
	end
end

-- 5.1, the phone's CALL CAR ("drive"): back to your car (the one you got off, else your first car), brought by the
-- chauffeur like the CAR button. Riding it already: CAR as usual.
local function drive(player: Player, profile: PlayerData.Profile)
	local carId = profile.lastCar
	if not (carId and profile.cars[carId] and not TransportRules.isBike(carId)) then
		carId = if profile.car and not TransportRules.isBike(profile.car) then profile.car else owned(profile, false)[1]
	end
	if not carId then
		notice:FireClient(player, NO_CAR)
		return
	end
	Jobs.returnLent(player)
	if profile.car ~= carId and midJob(player) then
		return
	end
	if profile.car ~= carId then
		if CarCall.busy(player) then
			CarCall.cancel(player)
		end
		if TransportRules.isBike(profile.car) then
			profile.bike = profile.car
		end
		profile.car = carId
		profile.lastCar = carId
		PlayerData.notify(player)
	elseif CarCall.busy(player) then
		notice:FireClient(player, "Your car is already on the way.")
		return
	end
	local err = Vehicles.spawn(player, false)
	if err then
		notice:FireClient(player, err)
	end
end

-- 5.1: ("bike", id) at Spoke & Chain (or anywhere): an owned bike becomes your bike of choice, and the one you ride
-- when you ride a bike (a live one is swapped for it: MY BIKE's way).
local function equipBike(player: Player, profile: PlayerData.Profile, id: string)
	local def = Economy.findCar(id)
	if not def or not def.bike or not profile.cars[id] then
		return
	end
	profile.bike = id
	local riding = profile.car == nil or TransportRules.isBike(profile.car)
	if riding and profile.car ~= id and not midJob(player) then
		profile.car = id
		PlayerData.notify(player)
		local live = Vehicles.get(player)
		if live and TransportRules.isBike(live.id) then
			local err = Vehicles.spawn(player, false)
			if err then
				notice:FireClient(player, err)
			end
		end
		notice:FireClient(player, `🚲 You ride the {def.name} now.`)
		return
	end
	PlayerData.notify(player)
	notice:FireClient(player, if riding then `🚲 You ride the {def.name}.` else `🚲 The {def.name} is your bike: MY BIKE on your phone gets you on it.`)
end

local function onEquip(player: Player, kind: any, id: any)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if kind == "ride" then
		ride(player, profile) -- 5.1
		return
	elseif kind == "drive" then
		drive(player, profile) -- 5.1
		return
	end
	if type(id) ~= "string" then
		return
	end
	if (kind == "bike" or kind == "car") and TransportRules.isBike(id) then
		equipBike(player, profile, id) -- 5.1: bikes need no garage
	elseif kind == "car" and profile.cars[id] then
		-- 3.4: cars are switched only at a garage of yours (or the depot lot for the starting van).
		local err = Garages.take(player, id)
		if err then
			notice:FireClient(player, err)
		end
	elseif kind == "weapon" and profile.weapons[id] then
		profile.weapon = id
		PlayerData.notify(player)
	end
end

-- 3.5: the next stage of the equipped car (Config.Cars stages): its price, its driver level, not during a delivery
-- (the car is built again with its new look) nor while it is on a repair lift.
local function buyStage(player: Player, profile: PlayerData.Profile)
	local carDef = if profile.car then Economy.findCar(profile.car) else nil
	if not carDef then
		notice:FireClient(player, NO_CAR)
		return
	end
	if carDef.bike then
		notice:FireClient(player, ON_BIKE) -- 5.1
		return
	end
	if not Economy.canUpgrade(carDef.id) then
		notice:FireClient(player, "A company vehicle has no stages. Take one of your own cars out of your garage.")
		return
	end
	local levels = Economy.carLevels(profile.carUpgrades, carDef.id)
	local stage = Economy.stageOf(carDef.id, levels)
	local nextStage = Economy.stageDef(carDef.id, stage + 1)
	if not nextStage then
		notice:FireClient(player, `Your {Economy.carTitle(carDef.id, levels)} is at its last stage. More room needs a bigger vehicle (Dead End Motors).`)
		return
	end
	if tooLow(player, nextStage.name, nextStage.level) then
		return
	end
	if Jobs.active(player) then
		notice:FireClient(player, "Finish your delivery first: the mechanics rebuild the car.")
		return
	end
	local live = Vehicles.get(player)
	if live and live.repairing then
		notice:FireClient(player, "Your car is on the lift: wait for the repair first.")
		return
	end
	if not PlayerData.spend(player, nextStage.price, "Stage", carDef.id) then
		notice:FireClient(player, "Not enough money.")
		return
	end
	if CarCall.busy(player) then
		CarCall.cancel(player) -- the call ends (the car goes): CAR brings it again, rebuilt
	end
	levels.stage = stage + 1
	profile.carUpgrades[carDef.id] = levels
	local was = Economy.stageDef(carDef.id, stage)
	notice:FireClient(player, `Your {if was then was.name else carDef.name} is a {nextStage.name} now: {Economy.capacity(carDef.id, levels)} cargo slots.`)
	Vehicles.refreshStats(player)
	PlayerData.notify(player)
end

local function onUpgrade(player: Player, id: any)
	local profile = PlayerData.get(player)
	-- 6.7: the gun tracks (Gun Damage, Fire Rate) at Lead & Co.; the stages and the car tracks at Wrench Garage
	local gunTrack = type(id) == "string" and id ~= "stage" and Economy.findUpgrade(id) ~= nil and not Economy.isCarUpgrade(id)
	if not profile or type(id) ~= "string" or refuse(player, if gunTrack then "guns" else "mechanic") then
		return
	end
	if id == "stage" then
		buyStage(player, profile)
		return
	end
	-- 3.3: a car track upgrades the equipped car only (its own levels, its own price); a gun track all your guns.
	local carTrack = Economy.isCarUpgrade(id)
	local carDef = if profile.car then Economy.findCar(profile.car) else nil
	if carTrack and not carDef then
		notice:FireClient(player, NO_CAR)
		return
	end
	if carTrack and carDef and carDef.bike then
		notice:FireClient(player, ON_BIKE) -- 5.1
		return
	end
	if carTrack and (not carDef or not Economy.canUpgrade(carDef.id)) then
		local name = if carDef then carDef.name else "this vehicle"
		notice:FireClient(player, `The {name} is a company vehicle: it can't be upgraded. Take one of your own cars out of your garage.`)
		return
	end
	local levels = if carTrack and carDef then Economy.carLevels(profile.carUpgrades, carDef.id) else profile.upgrades
	local level = Economy.level(levels, id)
	local cost = Economy.upgradeCost(id, level)
	if not cost then
		return
	end
	-- 4.0: Tyres & Suspension 5 lowers the body, a rebuild of the car (like a stage): not in the middle of a job.
	if id == "handling" and level + 1 >= 5 and Jobs.active(player) then
		notice:FireClient(player, "Finish your delivery first: the mechanics lower the car.")
		return
	end
	if not PlayerData.spend(player, cost, "Upgrade", id) then
		notice:FireClient(player, "Not enough money.")
		return
	end
	if carTrack and carDef then
		levels[id] = level + 1
		profile.carUpgrades[carDef.id] = levels
		local def = Economy.findUpgrade(id)
		notice:FireClient(player, `{if def then def.name else id} level {level + 1} on your {carDef.name}.`)
	else
		profile.upgrades[id] = level + 1
	end
	Vehicles.refreshStats(player)
	PlayerData.notify(player)
end

-- 4.6, gear (Config.Gear) for the equipped car, at Wrench Garage: "buy" (its driver level and price; it goes into a
-- free gear slot at once, else it waits "owned"), "install" (an owned piece into a free slot), "remove" (back to
-- owned). Not on a company vehicle, not for a piece that does not fit the car, not during a delivery (the kit is
-- built again), and the trolley not while it is out of the car.
local GEAR_ACTIONS: { [string]: boolean } = { buy = true, install = true, remove = true }

local function onGear(player: Player, action: any, id: any)
	local profile = PlayerData.get(player)
	local gear = if type(id) == "string" then Economy.findGear(id) else nil
	-- 5.1: bike gear at Spoke & Chain for your bike (the one you ride, else your bike of choice); car gear at Wrench
	-- Garage for your car.
	local forBike = gear ~= nil and gear.bikeOnly == true
	if not profile or not gear or type(action) ~= "string" or not GEAR_ACTIONS[action] or refuse(player, if forBike then "bikes" else "mechanic") then
		return
	end
	local targetId = if forBike then myBike(profile) else profile.car
	local carDef = if targetId then Economy.findCar(targetId) else nil
	if forBike and TransportRules.isBike(profile.car) then
		carDef = Economy.findCar(profile.car :: string)
	end
	if not carDef then
		notice:FireClient(player, if forBike then `No bike yet: buy one here first.` else NO_CAR)
		return
	end
	if carDef.bike and not forBike then
		notice:FireClient(player, ON_BIKE)
		return
	end
	if not Economy.canUpgrade(carDef.id) then
		notice:FireClient(player, "A company vehicle comes with what its job needs: no gear. Take one of your own cars out of your garage.")
		return
	end
	if not Economy.gearFits(carDef.id, gear.id) then
		notice:FireClient(player, `The {gear.name} doesn't fit the {carDef.name}.`)
		return
	end
	if Jobs.active(player) then
		notice:FireClient(player, if forBike then "Finish your delivery first: the gear goes on between jobs." else "Finish your delivery first: the mechanics fit the gear between jobs.")
		return
	end
	local list: { [string]: string } = profile.carGear[carDef.id] or {}
	local now = Economy.gearState(profile.carGear, carDef.id, gear.id)
	local levels = Economy.carLevels(profile.carUpgrades, carDef.id)
	local slots = Economy.gearSlots(carDef.id, Economy.stageOf(carDef.id, levels))
	local used = Economy.gearUsed(profile.carGear, carDef.id)
	if action == "buy" then
		if now ~= nil then
			notice:FireClient(player, `Your {carDef.name} already has the {gear.name}.`)
			return
		end
		if tooLow(player, gear.name, gear.level) then
			return
		end
		if not PlayerData.spend(player, gear.price, "Gear", gear.id) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		local fits = used < slots
		list[gear.id] = if fits then "installed" else "owned"
		notice:FireClient(player, if fits then `The {gear.name} is installed on your {carDef.name} ({used + 1} / {slots} gear slots).`
			else `The {gear.name} is yours. Every gear slot of your {carDef.name} is taken: REMOVE a piece to install it.`)
	elseif action == "install" then
		if now ~= "owned" then
			return
		end
		if used >= slots then
			notice:FireClient(player, `No free gear slot on your {carDef.name} ({used} / {slots}): remove a piece first.`)
			return
		end
		list[gear.id] = "installed"
		notice:FireClient(player, `{gear.name} installed ({used + 1} / {slots} gear slots).`)
	else
		if now ~= "installed" then
			return
		end
		local live = Vehicles.get(player)
		if gear.id == "trolley" and live and live.id == carDef.id and live.model:GetAttribute("TrolleyOut") then
			notice:FireClient(player, "Stow the trolley in the car first (G at the open back).")
			return
		end
		list[gear.id] = "owned"
		notice:FireClient(player, `{gear.name} removed. It stays your {carDef.name}'s: INSTALL it again here any time, for free.`)
	end
	profile.carGear[carDef.id] = list
	Vehicles.refreshStats(player)
	PlayerData.notify(player)
end

local function onPaint(player: Player, id: any)
	local profile = PlayerData.get(player)
	local paint = if type(id) == "string" then Economy.findPaint(id) else nil
	if not profile or not paint or refuse(player, "mechanic") then
		return
	end
	local carId = profile.car
	if not carId then
		notice:FireClient(player, NO_CAR)
		return
	end
	if TransportRules.isBike(carId) then
		notice:FireClient(player, ON_BIKE) -- 5.1
		return
	end
	if not profile.paints[paint.id] then
		if paint.exclusive then
			notice:FireClient(player, `{paint.name} is not for sale. It is a reward.`)
			return
		end
		if not PlayerData.spend(player, paint.price, "Paint", paint.id) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		profile.paints[paint.id] = true
	end
	profile.carPaint[carId] = paint.id
	Vehicles.repaint(player)
	PlayerData.notify(player)
end

-- 6.4: ("use", bag id) makes an owned bag the one in your hand (profile.activeBag), anywhere (the KIT tab, the I
-- window's BAGS): refused while your bag holds pieces or lies on the ground (Cargo.bagBusy). A bag bought becomes the
-- one in use when your bag is empty and with you; else your choice stays (USE it later).
local function useBag(player: Player, def: Config.KitDef)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if not profile.kit[def.id] or not TransportRules.isBag(def) then
		notice:FireClient(player, `You don't have the {def.name}.`)
		return
	end
	local current = TransportRules.activeBag(profile.kit, profile.activeBag)
	if current and current.id == def.id then
		profile.activeBag = def.id
		notice:FireClient(player, `The {def.name} is already in use.`)
		return
	end
	if Cargo.bagBusy(player) then
		notice:FireClient(player, "Empty your bag first: deliver what's in it (or pick it up from the ground).")
		return
	end
	profile.activeBag = def.id
	PlayerData.notify(player)
	notice:FireClient(player, `{def.icon} The {def.name} is your bag now: {TransportRules.bagRoom(profile.kit, def.id)} light pieces.`)
end

-- 5.0, personal gear (Config.Kit) at Last Stop Supplies: ("buy", kit id): not owned yet, its driver level, its price.
-- Yours for good (profile.kit): the board, Cargo's hands and the walk read it (shared/Transport.luau). 6.6: a bag only at
-- ZDC Bags (Map.Shops.bags), everything else only at Last Stop Supplies. 6.7: the Baseball Bat only at Lead & Co.
-- (KitDef shop); a starter piece (the plastic bag) is never sold.
local function onKit(player: Player, action: any, id: any)
	local profile = PlayerData.get(player)
	local def = if type(id) == "string" then TransportRules.findKit(id) else nil
	if profile and def and action == "use" then
		useBag(player, def) -- 6.4 (not only at the counter)
		return
	end
	-- (6.7: each piece at its own shop, TransportRules.kitShop: a bag at ZDC Bags, the bat at Lead & Co., the rest at
	-- Last Stop Supplies)
	if not profile or action ~= "buy" or not def or refuse(player, TransportRules.kitShop(def)) then
		return
	end
	if profile.kit[def.id] then
		notice:FireClient(player, `You already have the {def.name}.`)
		return
	end
	if def.starter then
		-- 6.7: the plastic bag is every courier's from the start, never sold (a profile without it gets it back, free)
		PlayerData.giveKit(player, def.id)
		notice:FireClient(player, `The {def.name} is your starter: it's yours.`)
		return
	end
	if tooLow(player, def.name, def.level) then
		return
	end
	if not PlayerData.spend(player, def.price, "Kit", def.id) then
		notice:FireClient(player, "Not enough money.")
		return
	end
	-- 6.4: a bag bought goes into your hand at once while yours is empty and with you; else your bag stays as it is
	local inUse = TransportRules.activeBag(profile.kit, profile.activeBag)
	local switch = TransportRules.isBag(def) and not Cargo.bagBusy(player)
	if TransportRules.isBag(def) then
		profile.activeBag = if switch then def.id elseif inUse then inUse.id else nil
	end
	PlayerData.giveKit(player, def.id)
	notice:FireClient(player, `{def.icon} The {def.name} is yours! {def.description}`
		.. (if TransportRules.isBag(def) and not switch then " Empty your bag, then USE it (I → BAGS)." else ""))
end

-- 3.5, the showroom: three cars inside the dealership (World.DealerSlots), not every car on a lot. Each one is shown
-- at a stage of its own (the Old Van as a Long Cargo Van: what your van becomes), with a tag and a "Look" prompt that
-- opens the catalog on it. Every car is bought from the catalog (the sales counter, or any display car).
local SHOWROOM: { { car: string, stage: number } } = {
	{ car = "van", stage = 3 }, -- 4.0: the Long Cargo Van
	{ car = "boxtruck", stage = 0 },
	{ car = "rallyvan", stage = 0 },
}

local function buildShowroom()
	local folder = Instance.new("Folder")
	folder.Name = "Showroom"
	folder.Parent = workspace
	for index, entry in SHOWROOM do
		local def = Economy.findCar(entry.car)
		local slot = World.DealerSlots[index]
		if not def or not slot then
			continue
		end
		local model = Vehicles.displayModel(def, slot, entry.stage)
		model.Parent = folder
		local chassis = model.PrimaryPart :: BasePart
		local stage = Economy.stageDef(def.id, entry.stage)
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(190, 60)
		tag.StudsOffset = Vector3.new(0, 10, 0)
		tag.MaxDistance = 70
		tag.Parent = chassis
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		local price = if VanQuestRules.isQuestCar(def.id) then "SOLD PRIVATELY · ASK MARGE"
			elseif def.price > 0 then "$" .. def.price else "BUILD YOURS AT WRENCH GARAGE"
		local name = if stage and stage.name ~= def.name then `{stage.name} ({def.name}, stage {entry.stage})` else def.name
		label.Text = if def.level and def.level > 1 then `{name}\n{price} · LEVEL {def.level}+` else `{name}\n{price}`
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.fromRGB(255, 220, 120)
		label.TextStrokeTransparency = 0.2
		label.Parent = tag
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Look"
		prompt.ObjectText = def.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = chassis
		prompt.Triggered:Connect(function(player)
			openShop:FireClient(player, "dealer", def.id)
		end)
	end
end

-- 5.1, Spoke & Chain's display bikes (6.12.7: behind Dead End Motors' front glass): every bike of Config.Cars on a
-- stand of its own (World.BikeSlots, in their order), with a tag (its name, price and level) and a "Look" prompt that
-- opens the shop on it (the BIKES counter's window).
local function buildBikeDisplay()
	local folder = Instance.new("Folder")
	folder.Name = "BikeDisplay"
	folder.Parent = workspace
	local index = 0
	for _, def in Config.Cars do
		if not def.bike then
			continue
		end
		index += 1
		local slot = World.BikeSlots[index]
		if not slot then
			break
		end
		local ok, model = pcall(Vehicles.displayModel, def, slot, 0)
		local chassis = if ok and model then model.PrimaryPart else nil
		if not ok or not chassis then
			warn(`[Shops] no display bike {def.id}: {if ok then "no chassis" else model}`)
			continue
		end
		model.Parent = folder
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(150, 46)
		tag.StudsOffset = Vector3.new(0, 5, 0)
		tag.MaxDistance = 40
		tag.Parent = chassis
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = `{def.name}\n${def.price} · LEVEL {def.level or 1}+`
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.fromRGB(255, 220, 120)
		label.TextStrokeTransparency = 0.2
		label.Parent = tag
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Look"
		prompt.ObjectText = def.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = chassis
		prompt.Triggered:Connect(function(player)
			openShop:FireClient(player, "bikes", def.id)
		end)
	end
end

function Shops.start()
	for _, entry in World.ShopPrompts do
		entry.prompt.Triggered:Connect(function(player)
			if entry.shop == "depot" then
				Garages.open(player, "depot") -- 3.4: the depot lot's garage window
				return
			end
			openShop:FireClient(player, entry.shop, nil)
		end)
	end
	for _, entry in World.EmployerPrompts do
		entry.prompt.Triggered:Connect(function(player)
			openShop:FireClient(player, "employer", entry.employer)
		end)
	end
	buildShowroom()
	local ok, err = pcall(function()
		buildBikeDisplay() -- 5.1
	end)
	if not ok then
		warn(`[Shops] the display bikes failed: {err}`)
	end
	-- 5.7: every shop action is rate limited per player (Config.Robust.Limits; the extra clicks of a flood are dropped).
	local limits = Config.Robust.Limits
	local function limited(name: string, perSecond: number, handler: (Player, ...any) -> ()): (Player, ...any) -> ()
		return function(player: Player, ...: any)
			if Net.limit(player, name, perSecond) then
				handler(player, ...)
			end
		end
	end
	Net.get("Buy").OnServerEvent:Connect(limited("Buy", limits.Buy, onBuy))
	Net.get("Equip").OnServerEvent:Connect(limited("Equip", limits.Equip, onEquip))
	Net.get("Upgrade").OnServerEvent:Connect(onUpgrade)
	Net.get("Paint").OnServerEvent:Connect(limited("Paint", limits.Paint, onPaint))
	Net.get("Gear").OnServerEvent:Connect(limited("Gear", limits.Gear, onGear))
	Net.get("Kit").OnServerEvent:Connect(limited("Kit", limits.Kit, onKit)) -- 5.0
end

return Shops
