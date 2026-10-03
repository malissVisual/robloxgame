--!strict
-- Zombie Delivery: the server. Builds the world, then wires the services together.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Server = script.Parent
local World = require(Server.World)
local PlayerData = require(Server.PlayerData)
local Vehicles = require(Server.Vehicles)
local Zombies = require(Server.Zombies)
local Jobs = require(Server.Jobs)
local Gun = require(Server.Gun)
local Items = require(Server.Items)
local Shops = require(Server.Shops)

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
		items = profile.items,
		paints = profile.paints,
		carPaint = profile.carPaint,
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
Vehicles.onWrecked = function(player, car, reason)
	Zombies.releaseCar(car)
	Jobs.fail(player, `{reason} The cargo is gone.`)
	notice:FireClient(player, "Your car is wrecked. Press CAR for a new one.")
end

PlayerData.start()
Vehicles.start()
Zombies.start()
Jobs.start()
Gun.start()
Items.start()
Shops.start()

-- The car comes when the player presses PLAY on the start screen (and after every respawn).
local playing: { [Player]: boolean } = {}

local function giveCar(player: Player)
	-- The save may still be loading.
	local waited = 0
	while player.Parent and not PlayerData.get(player) and waited < 15 do
		waited += task.wait(0.5)
	end
	if player.Parent and playing[player] and not Vehicles.get(player) and PlayerData.get(player) then
		Vehicles.spawn(player, true)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		if playing[player] then
			task.wait(1)
			giveCar(player)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	playing[player] = nil
	Zombies.clearOwner(player)
end)

Net.get("Play").OnServerEvent:Connect(function(player)
	if playing[player] then
		return
	end
	playing[player] = true
	giveCar(player)
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
