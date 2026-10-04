--!strict
-- Zombie Delivery: the server. Builds the world, then wires the services together.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

-- Shift sprints (client/CameraRig.luau): Roblox's own Shift Lock would fight it.
StarterPlayer.EnableMouseLockOption = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local GunModels = require(Shared.GunModels)

local Server = script.Parent
local World = require(Server.World)
local PlayerData = require(Server.PlayerData)
local Vehicles = require(Server.Vehicles)
local Zombies = require(Server.Zombies)
local Jobs = require(Server.Jobs)
local Gun = require(Server.Gun)
local Items = require(Server.Items)
local Shops = require(Server.Shops)
local BanditCars = require(Server.BanditCars)
local Cargo = require(Server.Cargo)
local Npcs = require(Server.Npcs)
local Animals = require(Server.Animals)
local Admin = require(Server.Admin)
local DayNight = require(Server.DayNight)
local Traffic = require(Server.Traffic)
local Crew = require(Server.Crew)
local Ranking = require(Server.Ranking)

-- ── Collision groups ───────────────────────────────────────────────────────
-- Cars and zombies pass through each other (ramming and grabbing are computed, not physical), corpses only lie on
-- the ground, bullets fly through cars and corpses.
for _, name in { "Car", "Zombie", "Corpse", "Bullet", "EnemyCar" } do
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
-- The bandits' cars bump into your car and the world, the zombies and the corpses pass through, bullets hit them.
PhysicsService:CollisionGroupSetCollidable("EnemyCar", "Zombie", false)
PhysicsService:CollisionGroupSetCollidable("EnemyCar", "Corpse", false)

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
		carGuns = profile.carGuns,
		rep = profile.rep,
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
Zombies.onSteal = function(player, share)
	Jobs.steal(player, share)
end
BanditCars.onKill = function(player)
	Jobs.onKill(player)
end
BanditCars.onCarDamaged = function(player, amount)
	Jobs.onCarDamaged(player, amount)
end
BanditCars.onSteal = function(player, share)
	Jobs.steal(player, share)
end
BanditCars.wanted = Jobs.active
-- The bandits, gunners and soldiers only go after players on a job (or in its crew); zombies after everybody.
Zombies.hunts = Jobs.involved
Vehicles.onWrecked = function(player, car, reason)
	Zombies.releaseCar(car)
	if Jobs.active(player) then
		Jobs.onCarWrecked(player)
	else
		notice:FireClient(player, `{reason} Press CAR for a new one.`)
	end
end

-- Every service starts on its own: one that fails (see the Output) does not take the others down.
local function safely(name: string, start: () -> ())
	local ok, err = pcall(function()
		start()
	end)
	if not ok then
		warn(`[Server] {name} failed to start: {err}`)
	end
end
safely("PlayerData", PlayerData.start)
safely("Vehicles", Vehicles.start)
safely("Zombies", Zombies.start)
safely("Jobs", Jobs.start)
safely("Gun", Gun.start)
safely("Items", Items.start)
safely("Shops", Shops.start)
safely("BanditCars", BanditCars.start)
safely("Npcs", Npcs.start)
safely("Animals", Animals.start)
safely("Cargo", Cargo.start)
safely("Admin", Admin.start)
safely("DayNight", DayNight.start)
safely("Traffic", Traffic.start)
Crew.hasJob = Jobs.active
safely("Crew", Crew.start)
safely("Ranking", Ranking.start)
print("[Server] Zombie Delivery is running")

-- The car comes when the player presses PLAY on the start screen (and after every respawn).
local playing: { [Player]: boolean } = {}

local function giveCar(player: Player)
	-- The save may still be loading.
	local waited = 0
	while player.Parent and not PlayerData.get(player) and waited < 15 do
		waited += task.wait(0.5)
	end
	if player.Parent and playing[player] and not Vehicles.get(player) and PlayerData.get(player) then
		Vehicles.spawn(player, true, Jobs.vehicleFor(player))
	end
end

-- Aiming on foot: the clients raise the gun arm (client/ArmPose.luau) of every character marked Aiming, pointed
-- AimPitch up or down.
local function setAiming(player: Player, aiming: any, aimPitch: any)
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("Aiming", aiming == true)
	if type(aimPitch) == "number" and aimPitch == aimPitch then
		character:SetAttribute("AimPitch", math.clamp(aimPitch, -1.2, 1.2))
	end
end

local function handOf(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

-- Does the character hold this gun, still welded to the hand it has now? (Roblox can rebuild the body parts after
-- the spawn, when the avatar loads, and a reset breaks the joints in models inside the character.)
local function holds(character: Model, weapon: string): boolean
	local gun = character:FindFirstChild("HandGun")
	if not gun or gun:GetAttribute("Weapon") ~= weapon then
		return false
	end
	local hand = handOf(character)
	local weld = gun:FindFirstChildWhichIsA("WeldConstraint", true)
	if not hand or not weld then
		return false
	end
	local held: Instance? = weld.Part1
	return weld.Part0 == hand and held ~= nil and held.Parent == gun
end

local function buildHandGun(character: Model, hand: BasePart, weapon: string)
	local old = character:FindFirstChild("HandGun")
	if old then
		old:Destroy()
	end
	GunModels.build(weapon, hand, GunModels.gripOn(hand)).Parent = character
end

-- The gun you have equipped, in your hand (everybody sees it). Safe to call any time: it only builds when the gun
-- is missing, is the wrong one, or lost its hand.
local function ensureHandGun(player: Player)
	local character = player.Character
	if not character or not character:IsDescendantOf(workspace) then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hand = handOf(character)
	if not humanoid or humanoid.Health <= 0 or not hand then
		return
	end
	local profile = PlayerData.get(player)
	local weapon = if profile then profile.weapon else "pistol"
	if not holds(character, weapon) then
		buildHandGun(character, hand, weapon)
	end
end

-- A new gun equipped: the hand changes.
PlayerData.Changed:Connect(ensureHandGun)

local function onPlayer(player: Player)
	player.CharacterAppearanceLoaded:Connect(function()
		ensureHandGun(player)
	end)
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
-- The safety net: whatever happened at the spawn (a character that was there before this script got here, a hand
-- rebuilt when the avatar loaded, a reset), every player gets the gun back within a second.
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			ensureHandGun(player)
		end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	playing[player] = nil
	Zombies.clearOwner(player)
end)

Net.get("Aiming").OnServerEvent:Connect(setAiming)

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
	local err = Vehicles.spawn(player, false, Jobs.vehicleFor(player))
	if err then
		notice:FireClient(player, err)
	end
end)
