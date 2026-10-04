--!strict
-- Zombie Delivery: the server. Builds the world, then wires the services together.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

-- Shift sprints (client/CameraRig.luau): Roblox's own Shift Lock would fight it.
StarterPlayer.EnableMouseLockOption = false

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
local BanditCars = require(Server.BanditCars)

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

-- The gun you have equipped, in your hand, the arm raised to aim (everybody sees it). You can shoot on foot too.
type GunPiece = { size: Vector3, offset: Vector3, color: Color3, material: Enum.Material }
local DARK = Color3.fromRGB(30, 30, 34)
local GUN_LOOKS: { [string]: { GunPiece } } = {
	pistol = { { size = Vector3.new(0.3, 0.45, 1.3), offset = Vector3.new(0, 0.15, -0.3), color = DARK, material = Enum.Material.Metal } },
	smg = {
		{ size = Vector3.new(0.35, 0.55, 2), offset = Vector3.new(0, 0.2, -0.6), color = DARK, material = Enum.Material.Metal },
		{ size = Vector3.new(0.25, 0.8, 0.35), offset = Vector3.new(0, -0.35, -0.5), color = Color3.fromRGB(60, 60, 64), material = Enum.Material.Metal },
	},
	shotgun = {
		{ size = Vector3.new(0.3, 0.35, 3.2), offset = Vector3.new(0, 0.2, -1.2), color = DARK, material = Enum.Material.Metal },
		{ size = Vector3.new(0.32, 0.5, 1.1), offset = Vector3.new(0, 0.05, 0.6), color = Color3.fromRGB(110, 70, 40), material = Enum.Material.Wood },
	},
	rifle = {
		{ size = Vector3.new(0.25, 0.3, 3.8), offset = Vector3.new(0, 0.2, -1.4), color = Color3.fromRGB(70, 60, 50), material = Enum.Material.Wood },
		{ size = Vector3.new(0.3, 0.3, 1.1), offset = Vector3.new(0, 0.55, -0.6), color = DARK, material = Enum.Material.Metal },
	},
	minigun = {
		{ size = Vector3.new(0.9, 0.9, 3), offset = Vector3.new(0, 0.3, -1.1), color = Color3.fromRGB(80, 80, 86), material = Enum.Material.DiamondPlate },
		{ size = Vector3.new(0.5, 0.7, 0.8), offset = Vector3.new(0, -0.3, 0), color = DARK, material = Enum.Material.Metal },
	},
	launcher = {
		{ size = Vector3.new(0.7, 0.7, 3), offset = Vector3.new(0, 0.35, -1), color = Color3.fromRGB(70, 90, 50), material = Enum.Material.Metal },
		{ size = Vector3.new(0.25, 0.6, 0.3), offset = Vector3.new(0, -0.2, -0.2), color = DARK, material = Enum.Material.Metal },
	},
}
local heldWeapon: { [Player]: string } = {}
local shoulderRest: { [Motor6D]: CFrame } = {}

-- Aiming on foot: the gun arm goes up (everybody sees it), and down again.
local function setAiming(player: Player, aiming: any)
	local character = player.Character
	local upper = character and character:FindFirstChild("RightUpperArm")
	local shoulder = upper and upper:FindFirstChild("RightShoulder")
	if not shoulder or not shoulder:IsA("Motor6D") then
		return
	end
	local rest = shoulderRest[shoulder]
	if not rest then
		rest = shoulder.C0
		shoulderRest[shoulder] = rest
		shoulder.Destroying:Connect(function()
			shoulderRest[shoulder] = nil
		end)
	end
	-- The arm goes up (and down) smoothly.
	local goal = if aiming == true then rest * CFrame.Angles(math.rad(85), 0, 0) else rest
	TweenService:Create(shoulder, TweenInfo.new(if aiming == true then 0.22 else 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = goal }):Play()
end

local function giveHandGun(player: Player, character: Model)
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	local profile = PlayerData.get(player)
	if not hand or not hand:IsA("BasePart") or not character.Parent then
		return
	end
	local old = character:FindFirstChild("HandGun")
	if old then
		old:Destroy()
	end
	local weapon = if profile then profile.weapon else "pistol"
	heldWeapon[player] = weapon
	local model = Instance.new("Model")
	model.Name = "HandGun"
	-- Along the arm: down at your side when walking, forward when the arm goes up to aim (Aiming).
	local grip = hand.CFrame * CFrame.new(0, -0.4, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	for _, piece in GUN_LOOKS[weapon] or GUN_LOOKS.pistol do
		local p = Instance.new("Part")
		p.Name = "GunPart"
		p.Size = piece.size
		p.Color = piece.color
		p.Material = piece.material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = grip * CFrame.new(piece.offset)
		local w = Instance.new("WeldConstraint")
		w.Part0 = hand
		w.Part1 = p
		w.Parent = p
		p.Parent = model
	end
	model.Parent = character
end

-- A new gun equipped: the hand changes.
PlayerData.Changed:Connect(function(player)
	local profile = PlayerData.get(player)
	local character = player.Character
	if profile and character and heldWeapon[player] ~= profile.weapon then
		task.spawn(giveHandGun, player, character)
	end
end)

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(giveHandGun, player, character)
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
	heldWeapon[player] = nil
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
