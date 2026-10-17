--!strict
-- Zombie Delivery (Deliveros): the server. The imports out of the Workspace, the collision groups and the State,
-- then server/SandboxBoot.luau boots the game: the lobby, the runs, the warehouses. 10.5 (the owner: "only the sandbox
-- is the game now"): the old city game is gone (in git's history up to 10.4).

-- 8.0.2: the owner's Blender imports (Import 3D leaves each in the Workspace, its parts loose: the sandbox builds no
-- Marge's house, so nothing took ZDCHouseArt away and its pieces fell apart over the plots) leave the world first
-- thing, before physics can move a piece; their dressers find them in ServerStorage (FurnitureMesh, HouseMesh,
-- VanMesh, SprinterMesh, 8.2: WarehouseMesh, 8.9.1: FixtureMesh read the pieces where the importer put them, against
-- their markers).
pcall(function()
	for _, name in { "ZDCFurnitureArt", "ZDCHouseArt", "ZDCVanArt", "ZDCSprinterArt", "ZDCWarehouseArt", "ZDCFixtureArt" } do
		local art = workspace:FindFirstChild(name)
		if art then
			art.Parent = game:GetService("ServerStorage")
		end
	end
end)

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

-- Shift sprints (client/CameraRig.luau): Roblox's own Shift Lock would fight it.
StarterPlayer.EnableMouseLockOption = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Config = require(Shared.Config)
StarterPlayer.CharacterWalkSpeed = Config.Movement.Walk -- 3.7: the walk of client/CameraRig.luau (server/Cargo.luau falls back to it)

local Server = script.Parent
-- The same native courier and animation set for everyone, installed before the long world build/first spawn.
require(Server.CourierAvatar).start()
local PlayerData = require(Server.PlayerData)

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
		bike = profile.bike, -- 5.1: your bike of choice (the BIKES counter, the phone's MY BIKE)
		lastCar = profile.lastCar, -- 5.1: the car the phone's CALL CAR brings back
		weapons = profile.weapons,
		weapon = profile.weapon,
		upgrades = profile.upgrades,
		carUpgrades = profile.carUpgrades, -- 3.3: the car tracks per car (the garage shows the equipped car's)
		carHealth = profile.carHealth, -- 3.4: every parked car's share of health (the I window's cars tab)
		carGear = profile.carGear, -- 4.6: every car's gear, "owned" or "installed" (Wrench Garage's GEAR tab)
		items = profile.items,
		paints = profile.paints,
		carPaint = profile.carPaint,
		carGuns = profile.carGuns,
		rep = profile.rep,
		deliveries = profile.deliveries,
		kills = profile.kills,
		xp = profile.xp,
		streak = profile.streak, -- 4.7: good jobs in a row (the board, the CAREER window; 6.14: the HUD's ON A ROLL chip)
		shift = require(Server.Shift).view(player), -- 6.14: this session's shift (the HUD's SHIFT chip, client/GrindChips)
		licences = profile.licences, -- 4.7: the licences held (tier → true)
		licenceJobs = profile.licenceJobs, -- 4.7: good jobs counted toward each licence
		-- 5.0: the personal gear owned (Config.Kit ids → true; shared/Transport.luau). 6.23: with the bags bought this
		-- game (PlayerData.kitNow: profile.kit + profile.bags), and those bags alone as `bags`
		kit = PlayerData.kitNow(profile),
		bags = profile.bags, -- 6.23: the bags bought this game (never saved)
		-- 6.4: the bag in your hand (the server's answer: the choice, else the best one; nil without a bag)
		bag = (require(Shared.Transport).activeBag(profile.bags, profile.activeBag) or ({} :: any)).id,
		style = profile.style, -- 6.12: the cosmetics owned and worn (the phone's STYLE app)
		regulars = profile.regulars, -- 6.14: the deliveries for each business (the REGULARS app, the job lists' badges)
		skills = profile.skills, -- 6.20: the skills' ranks (CAREER's SKILLS tab; the points are the level's)
		phone = profile.phone, -- 5.0: Marge gave the phone (client/Phone.luau shows it)
	})
end

-- 4.2: the whole profile goes at most every 0.15 s per player. Every kill's money fires Changed, and a horde fight
-- sent the full state many times a second; the burst now goes as one, the last state always arrives.
local queueState: (Player) -> ()
do
	local sentAt: { [Player]: number } = {}
	local pending: { [Player]: boolean } = {}
	local function flush(player: Player)
		pending[player] = nil
		if player.Parent then
			sentAt[player] = os.clock()
			sendState(player)
		end
	end
	queueState = function(player: Player)
		if pending[player] then
			return
		end
		pending[player] = true
		local wait = (sentAt[player] or 0) + 0.15 - os.clock()
		if wait > 0 then
			task.delay(wait, flush, player)
		else
			task.defer(flush, player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		sentAt[player] = nil
		pending[player] = nil
	end)
end

-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md): server/SandboxBoot.luau starts the game (the lobby, the plots, the
-- warehouses, the collection, the runs; the State above for the client).
require(Server.SandboxBoot).start(queueState)
