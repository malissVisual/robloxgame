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
local Config = require(Shared.Config)
local Map = require(Shared.Map)
StarterPlayer.CharacterWalkSpeed = Config.Movement.Walk -- 3.7: the walk of client/CameraRig.luau (server/Cargo.luau falls back to it)
local GunModels = require(Shared.GunModels)

local Server = script.Parent
-- The same native courier and animation set for everyone, installed before the long world build/first spawn.
require(Server.CourierAvatar).start()
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
local Buddy = require(Server.Buddy)
local DayNight = require(Server.DayNight)
local Traffic = require(Server.Traffic)
local Crew = require(Server.Crew)
local Ranking = require(Server.Ranking)
local Estate = require(Server.Estate)
local CarCall = require(Server.CarCall)
local Business = require(Server.Business)
local Missions = require(Server.Missions)
local Challenges = require(Server.Challenges)
local Garages = require(Server.Garages)
local Repair = require(Server.Repair)
local Explore = require(Server.Explore)
local Tutorial = require(Server.Tutorial)
local CloseCombat = require(Server.CloseCombat)
local Transport = require(Server.Transport)
local VanQuest = require(Server.VanQuest)
local KitWear = require(Server.KitWear)
local Fuel = require(Server.Fuel)
local Tasks = require(Server.Tasks) -- 6.12: the daily and weekly tasks

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
		streak = profile.streak, -- 4.7: good jobs in a row (the board, the CAREER window)
		licences = profile.licences, -- 4.7: the licences held (tier → true)
		licenceJobs = profile.licenceJobs, -- 4.7: good jobs counted toward each licence
		kit = profile.kit, -- 5.0: the personal gear owned (Config.Kit ids → true; shared/Transport.luau)
		-- 6.4: the bag in your hand (the server's answer: the choice, else the best owned; nil without a bag)
		bag = (require(Shared.Transport).activeBag(profile.kit, profile.activeBag) or ({} :: any)).id,
		style = profile.style, -- 6.12: the cosmetics owned and worn (the phone's STYLE app)
		phone = profile.phone, -- 5.0: Marge gave the phone (client/Phone.luau shows it)
		vanQuest = profile.vanQuest, -- 5.0: Earl's van (nil, "open", "done"; the phone's SHOP, the career road)
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

-- ── Wiring ─────────────────────────────────────────────────────────────────

PlayerData.Changed:Connect(queueState)

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
-- 3.1, the challenges' counters (server/Challenges.luau): how the kills happened, and what the jobs tell.
Zombies.onKillInfo = function(player, info)
	Challenges.onKill(player, { kind = info.kind, bandit = info.bandit, headshot = info.headshot, cause = info.cause, from = info.from })
	if not info.bandit then
		Tasks.note(player, "kill", 1, { night = DayNight.isNight() }) -- 6.12: a zombie (the night task: after dark)
	end
end
BanditCars.onKillInfo = function(player, info)
	Challenges.onKill(player, { car = true, cause = info.cause, from = info.from })
end
Jobs.onStat = Challenges.add
-- The bandits, gunners and soldiers only go after players on a job (or in its crew); zombies after everybody.
Zombies.hunts = Jobs.involved
Vehicles.onWrecked = function(player, car, reason)
	Zombies.releaseCar(car)
	if Jobs.active(player) then
		Jobs.onCarWrecked(player)
	else
		notice:FireClient(player, `{reason} Press CAR: it comes back badly damaged (a repair shop fixes it).`)
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
-- 6.13: Roblox's analytics (its hooks first: before any pay). Required inside `safely`: a module that fails to load
-- only means no analytics (the game reaches it through PlayerData.track / onMoney, which do nothing without it).
safely("Analytics", function()
	require(Server.Analytics).start()
end)
safely("Vehicles", Vehicles.start)
safely("Zombies", Zombies.start)
safely("Jobs", Jobs.start)
safely("JobQueue", require(Server.JobQueue).start) -- 6.12.8: the NEXT UP queue (+ QUEUE, ADD ALL)
safely("Gun", Gun.start)
safely("Items", Items.start)
safely("Shops", Shops.start)
safely("ShopClerks", require(Server.ShopClerks).start) -- 6.12.1: a clerk behind every shop counter
safely("BanditCars", BanditCars.start)
safely("Npcs", Npcs.start)
safely("Animals", Animals.start)
safely("Cargo", Cargo.start)
safely("Admin", Admin.start)
safely("DayNight", DayNight.start)
safely("Traffic", Traffic.start)
Crew.hasJob = Jobs.active
Crew.statusOf = Jobs.crewStatus
safely("Crew", Crew.start)
safely("Ranking", Ranking.start)
safely("Estate", Estate.start)
safely("CarCall", CarCall.start)
safely("Business", Business.start)
Jobs.onMissionComplete = Missions.onComplete
safely("Missions", Missions.start)
safely("Challenges", Challenges.start)
safely("Tasks", Tasks.start) -- 6.12: the daily and weekly tasks (the phone's TASKS app)
safely("Garages", Garages.start) -- 3.4: your cars in your garages, switched only there
safely("Repair", Repair.start) -- 3.4: the repair bays (no free repairs any more)
safely("Explore", Explore.start) -- 3.7: the map you discover
safely("Tutorial", Tutorial.start) -- 3.7: the first-day tutorial
safely("Hand", require(Server.Hand).start) -- 6.1: what you hold (fists / bag / gun: keys 1 / 2 / 3)
safely("CloseCombat", CloseCombat.start) -- 3.9: the holster (B) and the melee (V)
safely("Buddy", Buddy.start) -- 4.5: the admin's NPC companions
safely("Transport", Transport.start) -- 5.0: the kit's walk speed on the character (KitSpeed)
safely("VanQuest", VanQuest.start) -- 5.0: Earl's van, Marge's quest at level 4
safely("KitWear", KitWear.start) -- 5.0: the kit you own worn on your character, the phone in your hand
safely("Fuel", Fuel.start) -- 5.4: the tanks, the burn, the pumps, the jerry cans, the tow
safely("StyleWear", require(Server.StyleWear).start) -- 6.12: the cosmetics (the STYLE app), after KitWear and Vehicles
safely("Wheelie", require(Server.Wheelie).start) -- 6.10: the E-Scooter's wheelie, checked and shown to everybody
safely("Horn", require(Server.Horn).start) -- 6.12: H in the driver's seat, checked and sent to the players near the car
safely("Buses", require(Server.Buses).start) -- 5.5: the city buses (their stops: World's build list)
safely("Rental", require(Server.Rental).start) -- 5.6: ZDC RIDE, the free rental scooters and their docks
safely("ZipLines", require(Server.ZipLines).start) -- 5.6: the zip lines between the rooftops (the ladders, the rides)
print(`[Server] Zombie Delivery {Config.Version} is running`) -- (5.8.1: the version, to check that Studio has every file of it)
-- 5.7: the city is big (thousands of parts): without streaming every client loads all of it at once.
if not workspace.StreamingEnabled then
	warn("[Server] workspace.StreamingEnabled is off: turn it on in the place (Workspace → StreamingEnabled) or big parts of the city load on every client at once")
end

-- The car comes when the player presses PLAY on the start screen (and after every respawn).
local playing: { [Player]: boolean } = {}

local function giveCar(player: Player)
	-- The save may still be loading.
	local waited = 0
	while player.Parent and not PlayerData.get(player) and waited < 15 do
		waited += task.wait(0.5)
	end
	local profile = PlayerData.get(player)
	local carId = Jobs.vehicleFor(player)
	Jobs.returnLent(player) -- 5.0: a company vehicle of a job that is over does not stay with you
	-- 5.0: nobody to give a car to while you are on foot (no vehicle yet).
	if player.Parent and playing[player] and not Vehicles.get(player) and profile and (carId or profile.car) then
		Vehicles.spawn(player, true, carId)
	end
end

-- Aiming on foot: the clients raise the gun arm (client/ArmPose.luau) of every character marked Aiming, pointed
-- AimPitch up or down.
local function setAiming(player: Player, aiming: any, aimPitch: any)
	local character = player.Character
	if not character then
		return
	end
	-- 3.9: a holstered gun is not held up (server/CloseCombat.luau; the remotes come in order, a draw before its aim).
	character:SetAttribute("Aiming", aiming == true and character:GetAttribute("Holstered") ~= true)
	if type(aimPitch) == "number" and aimPitch == aimPitch then
		-- (rounded, and set only on a change: every set replicates to all clients)
		local pitch = math.round(math.clamp(aimPitch, -1.2, 1.2) * 50) / 50
		if character:GetAttribute("AimPitch") ~= pitch then
			character:SetAttribute("AimPitch", pitch)
		end
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
	if not profile then
		return -- (the save is still loading)
	end
	local weapon = profile.weapon
	if weapon == nil then
		-- 6.0: no gun (fists only): nothing in the hand, and the hands stay "holstered" (V punches; server/CloseCombat.luau
		-- refuses a draw without a gun).
		local old = character:FindFirstChild("HandGun")
		if old then
			old:Destroy()
		end
		if character:GetAttribute("Holstered") == false then
			character:SetAttribute("Holstered", true)
			character:SetAttribute("Aiming", false)
		end
		return
	end
	if not holds(character, weapon) then
		buildHandGun(character, hand, weapon)
	end
end

-- A new gun equipped: the hand changes.
PlayerData.Changed:Connect(ensureHandGun)

-- 4.0.4: dying on a job or a mission brings you back near where you fell (on the nearest road's sidewalk), not home
-- across the map: the job goes on. A spot is good for a short while after the death (the respawn wait).
local fellAt: { [Player]: { at: Vector3, time: number } } = {}
local RESPAWN_FOR = 30
local function respawnSpot(player: Player): CFrame?
	local fell = fellAt[player]
	if not fell or os.clock() - fell.time > RESPAWN_FOR or not Jobs.involved(player) then
		return nil
	end
	local x, z, dx, dz, width = Map.nearestRoad(fell.at.X, fell.at.Z)
	-- the sidewalk on the side the player fell on (not in the traffic)
	local side = if (fell.at.X - x) * -dz + (fell.at.Z - z) * dx >= 0 then 1 else -1
	local sx, sz = x - dz * side * (width / 2 + 4), z + dx * side * (width / 2 + 4)
	local position = Vector3.new(sx, Vehicles.groundY(sx, sz, fell.at.Y) + 3.5, sz)
	return CFrame.lookAt(position, position + Vector3.new(dx, 0, dz))
end
Estate.respawnAt = respawnSpot

local function onPlayer(player: Player)
	player.CharacterAppearanceLoaded:Connect(function()
		ensureHandGun(player)
	end)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				local root = character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					fellAt[player] = { at = root.Position, time = os.clock() }
				end
				PlayerData.track("died", player, Jobs.involved(player)) -- 6.13: DeathOnJob
			end)
		end
		if playing[player] then
			local spot = respawnSpot(player)
			if spot then
				local root = character:WaitForChild("HumanoidRootPart", 10)
				if root and player.Character == character then
					pcall(function()
						player:RequestStreamAroundAsync(spot.Position, 5)
					end)
					character:PivotTo(spot)
				end
			end
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
	fellAt[player] = nil
	Zombies.clearOwner(player)
end)

-- 5.7: rate limited; the last aim always arrives (Net.latest).
Net.get("Aiming").OnServerEvent:Connect(function(player, aiming, aimPitch)
	Net.latest(player, "Aiming", Config.Robust.Limits.Aiming, setAiming, aiming, aimPitch)
end)

Net.get("Play").OnServerEvent:Connect(function(player)
	if playing[player] then
		return
	end
	playing[player] = true
	-- The only Play listener (a PLAY queued during World.build reaches just the first one): the call's PLAY time and
	-- the trip home first, then the car (at the home garage when there is a home).
	-- 5.7: every step runs on its own (like `safely`): one that errors does not skip the rest, and it is warned. A
	-- failed PLAY clears `playing`, so a PLAY sent again runs it all again (each step is safe to run twice).
	local failed = false
	local function step(name: string, run: (Player) -> ())
		local ok, err = pcall(function()
			run(player)
		end)
		if not ok then
			failed = true
			warn(`[Server] PLAY for {player.Name}: {name} failed: {err}`)
		end
	end
	step("Analytics", function(who: Player) -- 6.13: the onboarding funnel's PressedPlay (inside step's pcall)
		PlayerData.track("onPlay", who)
	end)
	step("CarCall", CarCall.onPlay)
	step("Estate", Estate.onPlay)
	step("the car", giveCar)
	step("Tutorial", Tutorial.onPlay) -- 3.7: a new player's welcome (after StartDelay)
	step("VanQuest", VanQuest.onPlay) -- 5.0: Marge's text about Earl's van, when it is due
	if failed and player.Parent then
		playing[player] = nil
	end
end)

do
	local asked: { [Player]: number } = {}
	Net.get("RequestState").OnServerEvent:Connect(function(player)
		if os.clock() - (asked[player] or -1) < 0.5 then
			return -- (a client asks once on start; a flood would send the whole profile each time)
		end
		asked[player] = os.clock()
		queueState(player)
		Jobs.sendTo(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		asked[player] = nil
	end)
end

Net.get("SpawnCar").OnServerEvent:Connect(function(player)
	if CarCall.busy(player) then
		notice:FireClient(player, "Your car is already on the way.")
		return
	end
	Jobs.returnLent(player) -- 5.0: a company vehicle of a job that is over goes back first
	-- 5.0: on a foot job your own car is not part of the job: CAR calls it as usual.
	if Jobs.active(player) and not Jobs.isFoot(player) and Vehicles.get(player) then
		notice:FireClient(player, "Your car is still out there. Find it!")
		return
	end
	local err = Vehicles.spawn(player, false, Jobs.vehicleFor(player))
	if err then
		notice:FireClient(player, err)
	end
end)
