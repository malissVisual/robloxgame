--!strict
-- The shops in the safe zone around the depot. You walk in and use the prompt at the counter (it opens the shop on
-- your screen); the purchases are checked here, also that you really stand in that shop and that your driver level
-- (shared/Levels.luau) is high enough for what you buy (the level field of Config.Cars, Weapons and CarGuns).
--
--   Dead End Motors     cars (the showroom models have their own prompts)
--   Lead & Co.          guns (not the earned ones, Config.Weapons earned: an employer gives those)
--   Wrench Garage       upgrades, paint jobs and car guns (one on the roof of the equipped car; free repairs inside)
--   Last Stop Supplies  consumables
--   Depot Garage        switch between your cars
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
local Jobs = require(script.Parent.Jobs)

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

local function equipCar(player: Player, id: string)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.car = id
	PlayerData.notify(player)
	-- Swap the car right away, unless it is out on a job.
	if Jobs.active(player) then
		notice:FireClient(player, "Your new car comes after this delivery.")
		return
	end
	local err = Vehicles.spawn(player, true)
	if err then
		notice:FireClient(player, err)
	end
end

local function onBuy(player: Player, kind: any, id: any, amount: any)
	local profile = PlayerData.get(player)
	if not profile or type(id) ~= "string" then
		return
	end
	if kind == "car" then
		local def = Economy.findCar(id)
		if not def or def.company or profile.cars[id] or refuse(player, "dealer") or tooLow(player, def.name, def.level) then
			return
		end
		if not PlayerData.spend(player, def.price) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		profile.cars[id] = true
		notice:FireClient(player, `You bought the {def.name}!`)
		equipCar(player, id)
	elseif kind == "weapon" then
		local def = Economy.findWeapon(id)
		if not def or profile.weapons[id] then
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
	if kind == "car" and profile.cars[id] and profile.car ~= id then
		if not nearShop(player, "depot") and not nearShop(player, "dealer") then
			notice:FireClient(player, "Switch cars at the depot garage.")
			return
		end
		equipCar(player, id)
	elseif kind == "weapon" and profile.weapons[id] then
		profile.weapon = id
		PlayerData.notify(player)
	end
end

local function onUpgrade(player: Player, id: any)
	local profile = PlayerData.get(player)
	if not profile or type(id) ~= "string" or refuse(player, "mechanic") then
		return
	end
	local level = Economy.level(profile.upgrades, id)
	local cost = Economy.upgradeCost(id, level)
	if not cost then
		return
	end
	if not PlayerData.spend(player, cost) then
		notice:FireClient(player, "Not enough money.")
		return
	end
	profile.upgrades[id] = level + 1
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

-- The showroom: every car on its spot with a price tag and a prompt.
local function buildShowroom()
	local folder = Instance.new("Folder")
	folder.Name = "Showroom"
	folder.Parent = workspace
	local index = 0
	for _, def in Config.Cars do
		if def.company then
			continue -- the job board lends those
		end
		index += 1
		local slot = World.DealerSlots[index]
		if not slot then
			break
		end
		local model = Vehicles.displayModel(def, slot)
		model.Parent = folder
		local chassis = model.PrimaryPart :: BasePart
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(170, 50)
		tag.StudsOffset = Vector3.new(0, 9, 0)
		tag.MaxDistance = 90
		tag.Parent = chassis
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		local price = if def.price > 0 then "$" .. def.price else "FREE"
		label.Text = if def.level and def.level > 1 then `{def.name}\n{price} · LEVEL {def.level}+` else `{def.name}\n{price}`
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
