--!strict
-- Zombie Delivery (Deliveros): the server. The imports out of the Workspace, the collision groups and the State,
-- then server/SandboxBoot.luau boots the game: the lobby, the runs, the warehouses. 10.6 (the owner: "only the sandbox
-- is the game now"): the old city game is gone (in git's history up to 10.5).

-- 8.0.2: the owner's Blender imports (Import 3D leaves each in the Workspace, its parts loose: the sandbox builds no
-- Marge's house, so nothing took ZDCHouseArt away and its pieces fell apart over the plots) leave the world first
-- thing, before physics can move a piece; their dressers find them in ServerStorage (FurnitureMesh, HouseMesh,
-- SprinterMesh, 8.2: WarehouseMesh, 8.9.1: FixtureMesh read the pieces where the importer put them, against their
-- markers). 10.6: the old ZDC Van's ZDCVanArt has no dresser any more (the city's van went): it only leaves the world.
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
StarterPlayer.CharacterWalkSpeed = Config.Movement.Walk -- 3.7: the walk of client/CameraRig.luau

local Server = script.Parent
-- The same native courier and animation set for everyone, installed before the long world build/first spawn.
require(Server.CourierAvatar).start()
local PlayerData = require(Server.PlayerData)

-- ── Collision groups ───────────────────────────────────────────────────────
-- The vans and the zombies pass through each other, corpses only lie on the ground. (10.6: the city's bullets and its
-- bandits' cars went with their groups.)
for _, name in { "Car", "Zombie", "Corpse" } do
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end
PhysicsService:CollisionGroupSetCollidable("Car", "Zombie", false)
PhysicsService:CollisionGroupSetCollidable("Zombie", "Zombie", false)
PhysicsService:CollisionGroupSetCollidable("Corpse", "Car", false)
PhysicsService:CollisionGroupSetCollidable("Corpse", "Zombie", false)
PhysicsService:CollisionGroupSetCollidable("Corpse", "Corpse", false)

local stateRemote = Net.get("State")

-- The State: the money (the client's money line, its windows and sounds), all the client reads of the save (10.6: the
-- start screen, the save slots and the courier you make use the Slots remote).
local function sendState(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	stateRemote:FireClient(player, { money = profile.money })
end

-- 4.2: the State goes at most every 0.15 s per player. Every kill's money fires Changed, and a horde fight sent it
-- many times a second; the burst now goes as one, the last state always arrives.
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
