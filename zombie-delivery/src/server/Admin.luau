--!strict
-- The admin tools for testing (Config.Admin): unlock everything, money, any car or gun, teleport to any landmark,
-- start any job, finish the current stop, god mode, spawn enemies, a bandit car, clear the enemies, time of day,
-- heal. Admins (a Studio Play test, the owner of a user-owned place, Config.Admin.UserIds) get the player attribute
-- "Admin" (the client shows the panel, client/AdminPanel.luau); every command is checked here again.
--
-- Commands over the "Admin" remote (name, arg):
--   unlockAll                 every car (company ones too), every gun (earned ones too), every paint, 10 of each
--                             item, every employer's progress at the top (their rewards count as earned)
--   maxUpgrades               every upgrade track at its last level
--   money      amount         + money
--   car        car id         that car, now, next to you
--   weapon     weapon id      give it and put it in your hand
--   teleport   landmark id    you (and your car if you drive it) to a Map.Landmarks place
--   job        job type id    any Config.JobTypes id or "ordinary1" … "ordinary4" (Jobs.adminStart)
--   finishStop                the current stop is done (Jobs.adminFinishStop)
--   god        boolean?       toggle (or set) invulnerable: you and your car
--   spawn      kind | { kind, count }   enemies (Config.Zombies) near you
--   banditCar                 a bandit pickup chasing you
--   clear                     kill / remove the enemies around you and the ones after you
--   time       hour           Lighting.ClockTime
--   heal                      you and your car full

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)

local Server = script.Parent
local World = require(Server.World)
local PlayerData = require(Server.PlayerData)
local Vehicles = require(Server.Vehicles)
local Zombies = require(Server.Zombies)
local BanditCars = require(Server.BanditCars)
local Jobs = require(Server.Jobs)

local Admin = {}

local notice = Net.get("Notice")
local rng = Random.new()

local CLEAR_RADIUS = 350 -- "clear" kills every enemy this close
local MAX_SPAWN = 10 -- enemies per "spawn"
local GOD_FIELD = "AdminGod" -- the invisible ForceField of god mode (Humanoid:TakeDamage does nothing through it)

local god: { [Player]: boolean } = {}
local lastCommand: { [Player]: number } = {}
-- Bandit cars an admin called stay after them even without a job (BanditCars.wanted), until this time.
local chaseUntil: { [Player]: number } = {}

function Admin.isAdmin(player: Player): boolean
	if Config.Admin.InStudio and RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and player.UserId == game.CreatorId then
		return true
	end
	return table.find(Config.Admin.UserIds, player.UserId) ~= nil
end

-- ── Helpers ────────────────────────────────────────────────────────────────

local function say(player: Player, text: string)
	notice:FireClient(player, text)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function carName(id: string): string
	local def = Economy.findCar(id)
	return if def then def.name else id
end

-- ── Unlocks and money ──────────────────────────────────────────────────────

local function unlockAll(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	for _, car in Config.Cars do
		profile.cars[car.id] = true
	end
	for _, weapon in Config.Weapons do
		profile.weapons[weapon.id] = true
	end
	for _, paint in Config.Paints do
		profile.paints[paint.id] = true
	end
	for _, item in Config.Items do
		profile.items[item.id] = math.max(profile.items[item.id] or 0, math.min(10, item.max))
	end
	-- Every employer's jobs counted as done: their car and gun are "earned" in the windows too.
	for _, employer in Config.Employers do
		profile.rep[employer.id] = math.max(profile.rep[employer.id] or 0, employer.needed, employer.weaponAt or 0)
	end
	PlayerData.notify(player)
	say(player, "ADMIN: every car, gun, paint and employer reward unlocked, 10 of each item.")
end

local function maxUpgrades(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	for _, upgrade in Config.Upgrades do
		profile.upgrades[upgrade.id] = upgrade.maxLevel
	end
	PlayerData.notify(player)
	Vehicles.refreshStats(player)
	say(player, "ADMIN: every upgrade at its last level.")
end

local function money(player: Player, arg: any)
	local amount = if type(arg) == "number" and arg == arg then math.clamp(math.floor(arg), 1, 10_000_000) else 10_000
	PlayerData.addMoney(player, amount)
	say(player, `ADMIN: +{amount} money.`)
end

local function car(player: Player, arg: any)
	local def = if type(arg) == "string" then Economy.findCar(arg) else nil
	if not def then
		say(player, "ADMIN: unknown car.")
		return
	end
	local err = Vehicles.spawn(player, true, def.id)
	say(player, err or `ADMIN: here is the {def.name}.`)
end

local function weapon(player: Player, arg: any)
	local def = if type(arg) == "string" then Economy.findWeapon(arg) else nil
	if not def then
		say(player, "ADMIN: unknown gun.")
		return
	end
	PlayerData.giveWeapon(player, def.id, true)
	say(player, `ADMIN: {def.name} in your hand.`)
end

-- ── Teleport ───────────────────────────────────────────────────────────────

local function findLandmark(id: string): Map.Landmark?
	for _, landmark in Map.Landmarks do
		if landmark.id == id then
			return landmark
		end
	end
	return nil
end

-- How high the chassis rides above the ground under it (kept when the car is moved).
local function rideHeight(vehicle: Vehicles.Car): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { vehicle.model }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local origin = vehicle.chassis.Position
	local hit = workspace:Raycast(origin, Vector3.new(0, -30, 0), params)
	return if hit then math.clamp(origin.Y - hit.Position.Y, 1, 8) else 3
end

local function teleport(player: Player, arg: any)
	local landmark = if type(arg) == "string" then findLandmark(arg) else nil
	if not landmark then
		say(player, "ADMIN: unknown place.")
		return
	end
	local root = rootOf(player)
	local humanoid = humanoidOf(player)
	if not root or not humanoid then
		say(player, "ADMIN: you have no body right now.")
		return
	end
	-- A road next to the place (the shops' points are inside their buildings), facing along the road.
	local rx, rz, dx, dz = Map.nearestRoad(landmark.x, landmark.z)
	local along = Vector3.new(dx, 0, dz)
	if along:Dot(Vector3.new(landmark.x - rx, 0, landmark.z - rz)) < 0 then
		along = -along
	end

	local vehicle, driving = Vehicles.seatedIn(player)
	if vehicle and driving and vehicle.owner == player then
		local ground = Vector3.new(rx, World.RoadTop, rz)
		local height = rideHeight(vehicle)
		-- The client drives the car: it must have the ground there before the car arrives (StreamingEnabled).
		pcall(function()
			player:RequestStreamAroundAsync(ground, 5)
		end)
		if not vehicle.model.Parent or vehicle.owner ~= player then
			return
		end
		vehicle.model:PivotTo(CFrame.lookAt(ground + Vector3.new(0, height + 0.5, 0), ground + Vector3.new(0, height + 0.5, 0) + along))
		vehicle.chassis.AssemblyLinearVelocity = Vector3.zero
		vehicle.chassis.AssemblyAngularVelocity = Vector3.zero
		say(player, `ADMIN: {landmark.name} (with your {carName(vehicle.id)}).`)
		return
	end
	-- On foot (or riding along: get up first). A yard or a road at the place itself, else the road next to it.
	local x, z = rx, rz
	if landmark.kind == "employer" then
		-- The point is the WORK HERE board itself: stand a few studs off it, toward the road.
		local d = Vector3.new(rx - landmark.x, 0, rz - landmark.z)
		if d.Magnitude > 1 then
			local p = Vector3.new(landmark.x, 0, landmark.z) + d.Unit * math.min(8, d.Magnitude)
			x, z = p.X, p.Z
		end
	elseif Map.onRoad(landmark.x, landmark.z) then
		x, z = landmark.x, landmark.z
	end
	if humanoid.SeatPart then
		humanoid.Sit = false
		local seatWeld = humanoid.SeatPart:FindFirstChild("SeatWeld")
		if seatWeld then
			seatWeld:Destroy()
		end
		task.wait()
	end
	local character = player.Character
	if not character then
		return
	end
	local at = Vector3.new(x, World.RoadTop + 3.5, z)
	pcall(function()
		player:RequestStreamAroundAsync(at, 5)
	end)
	if player.Character ~= character or not character.Parent then
		return
	end
	character:PivotTo(CFrame.lookAt(at, at + along))
	root.AssemblyLinearVelocity = Vector3.zero
	say(player, `ADMIN: {landmark.name}.`)
end

-- ── Jobs ───────────────────────────────────────────────────────────────────

local function job(player: Player, arg: any)
	if type(arg) ~= "string" then
		return
	end
	-- Jobs.adminStart tells the player itself when it cannot.
	if Jobs.adminStart(player, arg) then
		local def = Economy.findJobType(arg)
		say(player, `ADMIN: job started: {if def then def.name else arg}.`)
	end
end

local function finishStop(player: Player)
	if not Jobs.active(player) then
		say(player, "ADMIN: no job running.")
		return
	end
	say(player, if Jobs.adminFinishStop(player) then "ADMIN: stop finished." else "ADMIN: nothing to finish at this stop.")
end

-- ── God mode and healing ───────────────────────────────────────────────────

local function shield(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local field = character:FindFirstChild(GOD_FIELD)
	if god[player] and not field then
		local new = Instance.new("ForceField")
		new.Name = GOD_FIELD
		new.Visible = false
		new.Parent = character
	elseif not god[player] and field then
		field:Destroy()
	end
end

local function heal(player: Player, quiet: boolean?)
	local humanoid = humanoidOf(player)
	if humanoid and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = humanoid.MaxHealth
	end
	local vehicle = Vehicles.get(player)
	if vehicle and vehicle.health < vehicle.stats.health then
		Vehicles.repair(vehicle, 1)
	end
	if not quiet then
		say(player, "ADMIN: you and your car are as good as new.")
	end
end

local function setGod(player: Player, arg: any)
	local on = if type(arg) == "boolean" then arg else not god[player]
	if on then
		god[player] = true
	else
		god[player] = nil
	end
	player:SetAttribute("God", on)
	shield(player)
	if on then
		heal(player, true)
	end
	say(player, if on then "ADMIN: god mode ON (you and your car)." else "ADMIN: god mode OFF.")
end

-- Every frame: god-mode players and their cars stay full (a car falling into the water is put back on a road).
local function keepGods()
	for player in god do
		if not player.Parent then
			god[player] = nil
			continue
		end
		heal(player, true)
		local vehicle = Vehicles.get(player)
		if vehicle and vehicle.chassis.Position.Y < -3 then
			local position = vehicle.chassis.Position
			local x, z, dx, dz = Map.nearestRoad(position.X, position.Z)
			local at = Vector3.new(x, World.RoadTop + 4, z)
			vehicle.model:PivotTo(CFrame.lookAt(at, at + Vector3.new(dx, 0, dz)))
			vehicle.chassis.AssemblyLinearVelocity = Vector3.zero
			vehicle.chassis.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

-- ── Enemies ────────────────────────────────────────────────────────────────

local function spawnEnemies(player: Player, arg: any)
	local kind: any, count: any = arg, 1
	if type(arg) == "table" then
		kind, count = arg.kind, arg.count
	end
	if type(kind) ~= "string" or not Config.Zombies[kind] then
		say(player, "ADMIN: unknown enemy.")
		return
	end
	count = if type(count) == "number" and count == count then math.clamp(math.floor(count), 1, MAX_SPAWN) else 1
	local root = rootOf(player)
	if not root then
		return
	end
	if World.isSafe(root.Position) then
		say(player, "ADMIN: enemies burn in the safe zone. Leave it first.")
		return
	end
	local made = 0
	for _ = 1, count do
		local spot = Zombies.findSpot(root.Position, nil, 30, 70)
		if not spot then
			-- No road around: a point on the nearest road a little away.
			local angle = rng:NextNumber(0, math.pi * 2)
			local x, z = Map.nearestRoad(root.Position.X + math.cos(angle) * 35, root.Position.Z + math.sin(angle) * 35)
			local guess = Vector3.new(x, World.RoadTop, z)
			if not World.isSafe(guess) and not Map.inWater(x, z) then
				spot = guess
			end
		end
		if spot and Zombies.spawn(kind, spot, player, false) then
			made += 1
		end
	end
	local name = Config.Zombies[kind].name
	say(player, if made > 0 then `ADMIN: {made} × {name} near you.` else "ADMIN: no room for more enemies here.")
end

local function banditCar(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local vehicle = Vehicles.seatedIn(player)
	local velocity = if vehicle then vehicle.chassis.AssemblyLinearVelocity else Vector3.zero
	local heading = if flat(velocity).Magnitude > 5 then velocity else root.CFrame.LookVector * 10
	chaseUntil[player] = os.clock() + Config.BanditCar.Lifetime
	if BanditCars.chase(player, root.Position, heading) then
		say(player, "ADMIN: a bandit pickup is coming after you.")
	else
		say(player, "ADMIN: no road for a bandit car here (not in the safe zone, not on the ice).")
	end
end

local function clear(player: Player)
	local root = rootOf(player)
	local killed = 0
	if root then
		for _, z in table.clone(Zombies.all()) do
			if not z.dead and (z.root.Position - root.Position).Magnitude <= CLEAR_RADIUS then
				if Zombies.damage(z, math.huge, nil) then
					killed += 1
				end
			end
		end
		killed += BanditCars.damageArea(root.Position, CLEAR_RADIUS, 1e9, nil)
	end
	-- The ones on their way to you, wherever they are.
	Zombies.clearOwner(player)
	BanditCars.clearFor(player)
	chaseUntil[player] = nil
	say(player, `ADMIN: enemies cleared ({killed} killed nearby).`)
end

-- ── World ──────────────────────────────────────────────────────────────────

local function setTime(player: Player, arg: any)
	if type(arg) ~= "number" or arg ~= arg then
		return
	end
	Lighting.ClockTime = math.clamp(arg, 0, 24) % 24
	say(player, string.format("ADMIN: the time is %02d:%02d.", math.floor(Lighting.ClockTime), math.floor(Lighting.ClockTime % 1 * 60)))
end

-- ── The remote ─────────────────────────────────────────────────────────────

local COMMANDS: { [string]: (Player, any) -> () } = {
	unlockAll = unlockAll,
	maxUpgrades = maxUpgrades,
	money = money,
	car = car,
	weapon = weapon,
	teleport = teleport,
	job = job,
	finishStop = finishStop,
	god = setGod,
	spawn = spawnEnemies,
	banditCar = banditCar,
	clear = clear,
	time = setTime,
	heal = function(player: Player)
		heal(player, false)
	end,
}

local function onCommand(player: Player, name: any, arg: any)
	if not Admin.isAdmin(player) then
		return
	end
	local command = if type(name) == "string" then COMMANDS[name] else nil
	if not command then
		say(player, "ADMIN: unknown command.")
		return
	end
	-- A double click does not run it twice.
	local now = os.clock()
	if lastCommand[player] and now - lastCommand[player] < 0.15 then
		return
	end
	lastCommand[player] = now
	local ok, err = pcall(function()
		command(player, arg)
	end)
	if not ok then
		warn(`[Admin] {name} failed: {err}`)
		say(player, `ADMIN: {name} failed (see the server Output).`)
	end
end

local function onPlayer(player: Player)
	if Admin.isAdmin(player) then
		player:SetAttribute("Admin", true)
	end
	player.CharacterAdded:Connect(function()
		-- God mode survives a respawn.
		task.defer(shield, player)
	end)
end

function Admin.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		god[player] = nil
		lastCommand[player] = nil
		chaseUntil[player] = nil
	end)
	Net.get("Admin").OnServerEvent:Connect(onCommand)
	RunService.Heartbeat:Connect(keepGods)

	-- Bandit cars an admin called keep chasing without a job (Main set BanditCars.wanted = Jobs.active before this).
	local wanted = BanditCars.wanted
	BanditCars.wanted = function(player: Player): boolean
		local untilTime = chaseUntil[player]
		return wanted(player) or (untilTime ~= nil and os.clock() < untilTime)
	end
end

return Admin
