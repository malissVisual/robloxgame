--!strict
-- Zombie Delivery: the server. Builds the city, then wires the services together and handles the shop.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)

local Server = script.Parent
local World = require(Server.World)
local PlayerData = require(Server.PlayerData)
local Vehicles = require(Server.Vehicles)
local Zombies = require(Server.Zombies)
local Jobs = require(Server.Jobs)
local Gun = require(Server.Gun)

-- ── Collision groups ───────────────────────────────────────────────────────
-- Cars and zombies pass through each other (ramming and grabbing are computed, not physical), corpses only lie on
-- the ground, bullets fly through cars and corpses.
for _, name in { "Car", "Zombie", "Corpse", "Bullet" } do
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end
PhysicsService:CollisionGroupSetCollidable("Car", "Zombie", false)
PhysicsService:CollisionGroupSetCollidable("Zombie", "Zombie", false)
PhysicsService:CollisionGroupSetCollidable("Corpse", "Car", false)
PhysicsService:CollisionGroupSetCollidable("Corpse", "Zombie", false)
PhysicsService:CollisionGroupSetCollidable("Corpse", "Corpse", false)
PhysicsService:CollisionGroupSetCollidable("Bullet", "Car", false)
PhysicsService:CollisionGroupSetCollidable("Bullet", "Corpse", false)

World.build()

local notice = Net.get("Notice")
local stateRemote = Net.get("State")

local function sendState(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	stateRemote:FireClient(player, {
		money = profile.money,
		cars = profile.cars,
		car = profile.car,
		weapons = profile.weapons,
		weapon = profile.weapon,
		upgrades = profile.upgrades,
		deliveries = profile.deliveries,
		kills = profile.kills,
	})
end

-- ── Wiring ─────────────────────────────────────────────────────────────────

PlayerData.Changed:Connect(sendState)

Zombies.onKill = function(player)
	Jobs.onKill(player)
end
Zombies.onCarDamaged = function(player, amount)
	Jobs.onCarDamaged(player, amount)
end
Vehicles.onWrecked = function(player, car)
	Zombies.releaseCar(car)
	Jobs.fail(player, "Your car was destroyed! The cargo is gone.")
	notice:FireClient(player, "Your car is wrecked. Press CAR for a new one.")
end

PlayerData.start()
Vehicles.start()
Zombies.start()
Jobs.start()
Gun.start()

-- Every new character gets its car (the first one right at the depot).
local function onCharacter(player: Player)
	task.wait(1)
	-- The save may still be loading.
	local waited = 0
	while player.Parent and not PlayerData.get(player) and waited < 15 do
		waited += task.wait(0.5)
	end
	if player.Parent and not Vehicles.get(player) and PlayerData.get(player) then
		Vehicles.spawn(player, true)
	end
end
local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		onCharacter(player)
	end)
	if player.Character then
		task.spawn(onCharacter, player)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	Zombies.clearOwner(player)
end)

Net.get("RequestState").OnServerEvent:Connect(function(player)
	sendState(player)
	Jobs.sendTo(player)
end)

Net.get("SpawnCar").OnServerEvent:Connect(function(player)
	if Jobs.active(player) and Vehicles.get(player) then
		notice:FireClient(player, "Your car is still out there. Find it!")
		return
	end
	local err = Vehicles.spawn(player)
	if err then
		notice:FireClient(player, err)
	end
end)

-- ── Shop (only in the depot) ───────────────────────────────────────────────

local function inDepot(player: Player): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return rootPart ~= nil and World.isSafe(rootPart.Position)
end

local function equipCar(player: Player, id: string)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.car = id
	PlayerData.notify(player)
	-- Swap the car right away, unless it is out on a job.
	if not Jobs.active(player) then
		local err = Vehicles.spawn(player, true)
		if err then
			notice:FireClient(player, err)
		end
	end
end

Net.get("Buy").OnServerEvent:Connect(function(player, kind: any, id: any)
	local profile = PlayerData.get(player)
	if not profile or type(id) ~= "string" then
		return
	end
	if not inDepot(player) then
		notice:FireClient(player, "Drive back to the depot to shop.")
		return
	end
	if kind == "car" then
		local def = Economy.findCar(id)
		if not def or profile.cars[id] then
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
		if not PlayerData.spend(player, def.price) then
			notice:FireClient(player, "Not enough money.")
			return
		end
		profile.weapons[id] = true
		profile.weapon = id
		notice:FireClient(player, `{def.name} mounted on your roof!`)
		PlayerData.notify(player)
	end
end)

Net.get("Equip").OnServerEvent:Connect(function(player, kind: any, id: any)
	local profile = PlayerData.get(player)
	if not profile or type(id) ~= "string" then
		return
	end
	if kind == "car" and profile.cars[id] and profile.car ~= id then
		if not inDepot(player) then
			notice:FireClient(player, "Drive back to the depot to change cars.")
			return
		end
		equipCar(player, id)
	elseif kind == "weapon" and profile.weapons[id] then
		profile.weapon = id
		PlayerData.notify(player)
	end
end)

Net.get("Upgrade").OnServerEvent:Connect(function(player, id: any)
	local profile = PlayerData.get(player)
	if not profile or type(id) ~= "string" then
		return
	end
	if not inDepot(player) then
		notice:FireClient(player, "Drive back to the depot to upgrade.")
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
end)
