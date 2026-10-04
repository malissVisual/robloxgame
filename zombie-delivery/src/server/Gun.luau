--!strict
-- The guns. The client says where it shoots (Fire, a point in the world), the server decides what fires
-- (Economy.fireMode), checks the fire rate, raycasts every pellet and deals the damage to zombies, bandits and bandit
-- cars (a head hit is a crit, the grenade launchers blow up):
--   on foot      the gun in your hand
--   driver       the car gun on the roof, if the car has one (the turret turns to the target)
--   any seat     otherwise a one-handed gun (pistol, revolver, SMG) out of the side window; a two-handed gun does not
--                fire from a car at all (the shot is ignored, the client shows a hint)
-- Nobody shoots with full hands: a character carrying cargo (the Carrying attribute, server/Cargo.luau) cannot fire.
-- Every shot that really fires is told to Gun.onShot (3.0: the quiet twist of a mission costs cargo condition per shot;
-- server/Jobs.luau sets it, Gun does not require Jobs).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)
local BanditCars = require(script.Parent.BanditCars)
local PlayerData = require(script.Parent.PlayerData)

local Gun = {}

-- Set by server/Jobs.luau (Jobs.onShot): a player fired a shot (every trigger pull that passed the checks, once).
Gun.onShot = nil :: ((player: Player) -> ())?

local lastShot: { [Player]: number } = {}
local rng = Random.new()

local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local spread = math.rad(degrees)
	local frame = CFrame.lookAt(Vector3.zero, direction)
	return (frame * CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)).LookVector
end

local function onFire(player: Player, target: any)
	if typeof(target) ~= "Vector3" or target ~= target then
		return
	end
	local car, driving, seatPart = Vehicles.seatedIn(player)
	local profile = PlayerData.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not profile or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if character and character:GetAttribute("Carrying") ~= nil then
		return -- the hands are full (a crate, a horse's rope): put it down first
	end
	-- What fires: the car gun (the server's own record of what is on this car), a gun out of the window, or nothing.
	local carGunId = if car and driving then car.gunId else nil
	local mode = Economy.fireMode(seatPart ~= nil, driving, profile.weapon, carGunId)
	if not mode or (mode ~= "hand" and not car) then
		return -- a two-handed gun in a car seat
	end
	local carGun = if mode == "cargun" and carGunId then Economy.findCarGun(carGunId) else nil
	local stats = if carGun then Economy.carGunStats(carGun.id, profile.upgrades) else Economy.weaponStats(profile.weapon, profile.upgrades)
	local now = os.clock()
	if lastShot[player] and now - lastShot[player] < stats.interval * 0.8 then
		return -- faster than the gun can fire (a little slack for the network)
	end
	lastShot[player] = now
	-- The calm zombies nearby hear it (server/Zombies.luau, Config.Horde.Roam.gunHearing).
	Zombies.noise(player, root.Position)
	local onShot = Gun.onShot
	if onShot then
		task.spawn(onShot, player)
	end

	local origin: Vector3
	if car and carGun then
		Vehicles.aim(car, target)
		origin = (car.chassis.CFrame * car.turretBase).Position + Vector3.new(0, 1, 0)
	elseif car and seatPart then
		origin = Vehicles.windowPoint(car, seatPart) -- leaning out of the side window
	else
		origin = root.Position + Vector3.new(0, 1.5, 0) -- on foot, from the hand
	end
	local toTarget = target - origin
	local direction = if toTarget.Magnitude > 1 then toTarget.Unit else root.CFrame.LookVector
	origin += direction * 2

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { character :: Model }
	if car then
		table.insert(exclude, car.model)
	end
	params.FilterDescendantsInstances = exclude
	params.CollisionGroup = "Bullet"

	local look: { number } = if carGun then carGun.color else (Economy.findWeapon(profile.weapon) or Config.Weapons[1]).color
	local color = Color3.fromRGB(look[1], look[2], look[3])
	local tracer = Net.get("Tracer")
	local hit = Net.get("Hit")
	for _ = 1, stats.pellets do
		local dir = spreadDirection(direction, stats.spread)
		local result = workspace:Raycast(origin, dir * stats.range, params)
		local finish = if result then result.Position else origin + dir * stats.range
		if result then
			local zombie = Zombies.fromPart(result.Instance)
			if stats.splash > 0 then
				local blast = Instance.new("Explosion")
				blast.BlastPressure = 0
				blast.DestroyJointRadiusPercent = 0
				blast.BlastRadius = stats.splash
				blast.Position = result.Position
				blast.Parent = workspace
				local killed = Zombies.damageArea(result.Position, stats.splash, stats.damage, player)
				killed += BanditCars.damageArea(result.Position, stats.splash, stats.damage, player)
				hit:FireClient(player, result.Position, math.floor(stats.damage + 0.5), false, killed > 0)
			elseif zombie then
				-- A headshot kills on the spot (a brute takes four times the damage).
				local crit = result.Instance.Name == "Head" or result.Instance:GetAttribute("HeadPart") == true
				local damage = stats.damage
				if crit then
					damage = if zombie.kind == "brute" then stats.damage * Config.Horde.HeadshotMultiplier * 2 else zombie.humanoid.Health + 1
				end
				local killed = Zombies.damage(zombie, damage, player, { crit = crit, push = dir * 40 })
				hit:FireClient(player, result.Position, math.floor(damage + 0.5), crit, killed)
			else
				local banditCar = BanditCars.fromPart(result.Instance)
				if banditCar then
					local destroyed = BanditCars.damage(banditCar, stats.damage, player)
					hit:FireClient(player, result.Position, math.floor(stats.damage + 0.5), false, destroyed)
				end
			end
		end
		tracer:FireAllClients(origin, finish, color, player.UserId)
	end
end

function Gun.start()
	Net.get("Fire").OnServerEvent:Connect(onFire)
	Players.PlayerRemoving:Connect(function(player)
		lastShot[player] = nil
	end)
end

return Gun
