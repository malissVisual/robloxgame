--!strict
-- The shops in the safe zone around the depot. You walk in and use the prompt at the counter (it opens the shop on
-- your screen); the purchases are checked here, also that you really stand in that shop and that your driver level
-- (shared/Levels.luau) is high enough for what you buy (the level field of Config.Cars, Weapons and CarGuns).
--
--   Dead End Motors     cars, from the catalog at the sales counter (3.5: no lot of every car outside any more; a
--                       small showroom inside shows three of them, World.DealerSlots, each with a "Look" prompt that
--                       opens the catalog on it); every car needs a free car slot (Estate.carSlots: homes and garages
--                       add them; the employers' company cars take none). 3.4: a bought car goes into your garage:
--                       take it out there (server/Garages.luau)
--   Lead & Co.          guns (not the earned ones, Config.Weapons earned: an employer gives those)
--   Wrench Garage       upgrades (3.3: the car tracks for the equipped car; the gun tracks for all guns), 3.5: the
--                       car's next STAGE (the "Upgrade" remote with id "stage": Config.Cars stages, its own look),
--                       paint jobs and car guns (one on the roof of the equipped car); 3.4: its repair bays are
--                       server/Repair.luau's (no free repairs any more)
--   Last Stop Supplies  consumables
--   Depot Garage        3.4: the depot lot's garage window (server/Garages.luau: the starting van, company vehicles)
--   Job Board           the depot's job board

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local PlayerData = require(script.Parent.PlayerData)
local Estate = require(script.Parent.Estate)
local Garages = require(script.Parent.Garages)
local Jobs = require(script.Parent.Jobs)
local CarCall = require(script.Parent.CarCall)

local Shops = {}

local notice = Net.get("Notice")
local openShop = Net.get("OpenShop")


local function nearShop(player: Player, shop: string): boolean
	local info = Map.Shops[shop]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not info or not root then
		return false
	end
	return Vector3.new(root.Position.X - info.x, 0, root.Position.Z - info.z).Magnitude < Map.ShopRadius
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

local function onBuy(player: Player, kind: any, id: any, amount: any)
	local profile = PlayerData.get(player)
	if not profile or type(id) ~= "string" then
		return
	end
	if kind == "car" then
		local def = Economy.findCar(id)
		if not def or def.company or profile.cars[id] or refuse(player, "dealer") or tooLow(player, def.name, def.level) or noSlot(player) then
			return
		end
		if not PlayerData.spend(player, def.price) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		profile.cars[id] = true
		-- 3.4: it goes into your garage (cars are kept in garages): take it out there.
		notice:FireClient(player, `You bought the {def.name}! It waits in your {aGarage(player)}: take it out at the 🅿 GARAGE post there (E).`)
		PlayerData.notify(player)
	elseif kind == "weapon" then
		local def = Economy.findWeapon(id)
		if not def or profile.weapons[id] then
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
		if not PlayerData.spend(player, def.price) then
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
		local carDef = Economy.findCar(profile.car)
		if not def or not carDef or refuse(player, "mechanic") then
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
		if not PlayerData.spend(player, def.price) then
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
		local count = if type(amount) == "number" then math.clamp(math.floor(amount), 1, 10) else 1
		count = math.min(count, def.max - (profile.items[id] or 0))
		if count <= 0 then
			notice:FireClient(player, `You cannot carry more {def.name}s.`)
			return
		end
		if not PlayerData.spend(player, def.price * count) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		PlayerData.addItem(player, id, count)
	end
end

local function onEquip(player: Player, kind: any, id: any)
	local profile = PlayerData.get(player)
	if not profile or type(id) ~= "string" then
		return
	end
	if kind == "car" and profile.cars[id] then
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
	local carDef = Economy.findCar(profile.car)
	if not carDef or not Economy.canUpgrade(carDef.id) then
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
	if not PlayerData.spend(player, nextStage.price) then
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
	if not profile or type(id) ~= "string" or refuse(player, "mechanic") then
		return
	end
	if id == "stage" then
		buyStage(player, profile)
		return
	end
	-- 3.3: a car track upgrades the equipped car only (its own levels, its own price); a gun track all your guns.
	local carTrack = Economy.isCarUpgrade(id)
	local carDef = Economy.findCar(profile.car)
	if carTrack and (not carDef or not Economy.canUpgrade(carDef.id)) then
		local name = if carDef then carDef.name else "this vehicle"
		notice:FireClient(player, `The {name} is a company vehicle: it can't be upgraded. Take one of your own cars out of your garage.`)
		return
	end
	-- 4.0: the Hand Trolley fits only the vans and trucks (CarDef.trolley).
	if carTrack and carDef and not Economy.upgradeFits(carDef.id, id) then
		local def = Economy.findUpgrade(id)
		notice:FireClient(player, `The {if def then def.name else id} doesn't fit the {carDef.name}: vans and trucks only.`)
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
	if not PlayerData.spend(player, cost) then
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

local function onPaint(player: Player, id: any)
	local profile = PlayerData.get(player)
	local paint = if type(id) == "string" then Economy.findPaint(id) else nil
	if not profile or not paint or refuse(player, "mechanic") then
		return
	end
	if not profile.paints[paint.id] then
		if paint.exclusive then
			notice:FireClient(player, `{paint.name} is not for sale. It is a reward.`)
			return
		end
		if not PlayerData.spend(player, paint.price) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		profile.paints[paint.id] = true
	end
	profile.carPaint[profile.car] = paint.id
	Vehicles.repaint(player)
	PlayerData.notify(player)
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
		local price = if def.price > 0 then "$" .. def.price else "BUILD YOURS AT WRENCH GARAGE"
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
	Net.get("Buy").OnServerEvent:Connect(onBuy)
	Net.get("Equip").OnServerEvent:Connect(onEquip)
	Net.get("Upgrade").OnServerEvent:Connect(onUpgrade)
	Net.get("Paint").OnServerEvent:Connect(onPaint)
end

return Shops
