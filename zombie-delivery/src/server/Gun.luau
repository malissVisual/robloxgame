--!strict
-- The guns. The client says where it shoots (Fire, a point in the world), the server decides what fires
-- (Economy.fireMode), checks the fire rate, raycasts every pellet and deals the damage to zombies, bandits and bandit
-- cars (a head hit is a crit, the grenade launchers blow up; 3.1: a piercing gun's round goes on through more of them):
--   on foot      the gun in your hand
--   driver       the car gun on the roof, if the car has one (the turret turns to the target)
--   any seat     otherwise a one-handed gun (pistol, revolver, SMG) out of the side window; a two-handed gun does not
--                fire from a car at all (the shot is ignored, the client shows a hint)
-- Nobody shoots with full hands: a character carrying cargo (the Carrying attribute, server/Cargo.luau) cannot fire.
-- 3.9: on foot nothing fires while the gun is holstered (the Holstered attribute, server/CloseCombat.luau); in a car
-- seat the holster changes nothing.
-- Every shot that really fires is told to Gun.onShot (3.0: the quiet twist of a mission costs cargo condition per shot;
-- server/Jobs.luau sets it, Gun does not require Jobs).
-- 4.5: a player with the attribute AdminOneHit (server/Admin.luau) kills whatever a round hits.
-- 6.12.14: every part a round hits is handed to GunRange.shot first: a target on Lead & Co.'s lanes tips back and
-- springs up again (server/GunRange.luau; anything else: nothing happens there).

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
local GunRange = require(script.Parent.GunRange)

local Gun = {}

-- Set by server/Jobs.luau (Jobs.onShot): a player fired a shot (every trigger pull that passed the checks, once).
Gun.onShot = nil :: ((player: Player) -> ())?

local lastShot: { [Player]: number } = {}
local ONE_HIT = 1e6 -- 4.5: a round's damage with the admin's ONE-HIT KILLS (the player attribute AdminOneHit)
local rng = Random.new()

local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local spread = math.rad(degrees)
	local frame = CFrame.lookAt(Vector3.zero, direction)
	return (frame * CFrame.Angles(rng:NextNumber(-spread, spread), rng:NextNumber(-spread, spread), 0)).LookVector
end

-- One round hits `result`: the damage it deals (a blast, a zombie with its headshot, a bandit car). Returns the enemy
-- model a piercing round may go on through (nil: it stops here) and whether passing it is free (a body already dead).
-- from (3.1): the roof gun ("cargun") or a passenger's gun out of the window ("window"); the challenges count its kills.
type Hit = { Instance: Instance, Position: Vector3 } -- a RaycastResult, or a hit decided without a ray (latchedHit)
local function hitPart(player: Player, result: Hit, dir: Vector3, stats: Economy.WeaponStats, from: string?): (Model?, boolean)
	GunRange.shot(result.Instance) -- 6.12.14: a range target drops (nothing else does anything there)
	local hit = Net.get("Hit")
	if stats.splash > 0 then
		local blast = Instance.new("Explosion")
		blast.BlastPressure = 0
		blast.DestroyJointRadiusPercent = 0
		blast.BlastRadius = stats.splash
		blast.Position = result.Position
		blast.Parent = workspace
		local killed = Zombies.damageArea(result.Position, stats.splash, stats.damage, player, from)
		killed += BanditCars.damageArea(result.Position, stats.splash, stats.damage, player, from)
		hit:FireClient(player, result.Position, math.floor(stats.damage + 0.5), false, killed > 0)
		return nil, false
	end
	local zombie = Zombies.fromPart(result.Instance)
	if zombie then
		if zombie.dead then
			return zombie.model, true
		end
		-- A headshot kills on the spot (a brute takes four times the damage).
		local crit = result.Instance.Name == "Head" or result.Instance:GetAttribute("HeadPart") == true
		local damage = stats.damage
		if crit then
			damage = if zombie.kind == "brute" then stats.damage * Config.Horde.HeadshotMultiplier * 2 else zombie.humanoid.Health + 1
		end
		local killed = Zombies.damage(zombie, damage, player, { crit = crit, push = dir * 40, from = from })
		hit:FireClient(player, result.Position, math.floor(damage + 0.5), crit, killed)
		return zombie.model, false
	end
	local banditCar = BanditCars.fromPart(result.Instance)
	if banditCar then
		if banditCar.dead then
			return banditCar.npc.model, true
		end
		local destroyed = BanditCars.damage(banditCar, stats.damage, player, nil, from)
		hit:FireClient(player, result.Position, math.floor(stats.damage + 0.5), false, destroyed)
		return banditCar.npc.model, false
	end
	return nil, false
end

-- A zombie hanging on a car that the client aimed at (client/Shooting.luau sends the part): a hit without a ray. The
-- car runs on its driver's machine, so the server sees the car and the zombie welded to it a little behind, and a shot
-- out of the window starts right beside it: the server's ray would miss (or start inside it) what the player clearly
-- hit. Trusted only for a living zombie hanging on the car you sit in, or within the gun's range of you on foot.
local function latchedHit(aimed: any, car: Vehicles.Car?, root: BasePart, range: number): BasePart?
	if typeof(aimed) ~= "Instance" or not aimed:IsA("BasePart") then
		return nil
	end
	local zombie = Zombies.fromPart(aimed)
	if not zombie or zombie.dead or not zombie.car then
		return nil
	end
	if car then
		return if zombie.car == car then aimed else nil
	end
	if (zombie.root.Position - root.Position).Magnitude > range + 8 then
		return nil
	end
	-- On foot: not through a wall (4.0.4); the car it hangs on and the zombie itself do not count.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = root.Parent
	params.FilterDescendantsInstances = { character :: Instance, zombie.model, zombie.car.model }
	params.CollisionGroup = "Bullet"
	return if workspace:Raycast(root.Position, aimed.Position - root.Position, params) then nil else aimed
end

local function onFire(player: Player, target: any, aimed: any)
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
	if mode == "hand" and character and character:GetAttribute("Holstered") == true then
		return -- 3.9: the gun is away (B draws it; server/CloseCombat.luau)
	end
	local carGun = if mode == "cargun" and carGunId then Economy.findCarGun(carGunId) else nil
	local stats = if carGun then Economy.carGunStats(carGun.id, profile.upgrades) else Economy.weaponStats(profile.weapon, profile.upgrades)
	if player:GetAttribute("AdminOneHit") == true then
		-- 4.5, the admin's ONE-HIT KILLS (server/Admin.luau): every round kills what it hits.
		stats = table.clone(stats)
		stats.damage = ONE_HIT
	end
	-- The car seat's gun, for the challenges (Zombies.KillInfo): the roof gun, or a passenger's out of the window.
	local from = if mode == "cargun" or (mode == "window" and not driving) then mode else nil
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

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { character :: Model }
	if car then
		table.insert(exclude, car.model)
	end
	params.FilterDescendantsInstances = exclude
	params.CollisionGroup = "Bullet"
	-- 4.0.4: no shots through walls. The rays start at the muzzle (no more 2 studs further out, which could be on the
	-- far side of a wall you lean on), and a wall between you and the muzzle (a window point or the turret pressed
	-- against one) takes the shot.
	local blocked = workspace:Raycast(root.Position, origin - root.Position, params)
	if blocked then
		origin = root.Position
		target = blocked.Position
		direction = if (target - origin).Magnitude > 0.1 then (target - origin).Unit else direction
	end

	local look: { number } = if carGun then carGun.color else (Economy.findWeapon(profile.weapon) or Config.Weapons[1]).color
	local color = Color3.fromRGB(look[1], look[2], look[3])
	local tracer = Net.get("Tracer")
	local onCar = latchedHit(aimed, car, root, stats.range)
	if onCar then
		for _ = 1, stats.pellets do
			hitPart(player, { Instance = onCar, Position = onCar.Position }, direction, stats, from)
			tracer:FireAllClients(origin, onCar.Position, color, player.UserId)
		end
		return
	end
	-- 6.20: Steady Hand (Config.Skills) narrows a hand gun's spread (the hand, out of a window; never the roof gun)
	local spread = if mode == "cargun" then stats.spread else stats.spread * math.max(0, 1 - require(script.Parent.Skills).effect(player, "spread"))
	for _ = 1, stats.pellets do
		local dir = spreadDirection(direction, spread)
		-- 3.1: a piercing round (WeaponDef.pierce) goes on through that many more enemies, each taking the full
		-- damage; it stops at anything else (a wall, the ground) and the tracer ends at its last hit, else the range.
		local rayParams = params
		local left = if stats.splash > 0 then 0 else stats.pierce
		local start = origin
		local travel = stats.range
		local finish = origin + dir * stats.range
		for _ = 0, stats.pierce + 4 do -- bounded: a few dead bodies in the way may be passed for free
			local result = workspace:Raycast(start, dir * travel, rayParams)
			if not result then
				finish = start + dir * travel
				break
			end
			finish = result.Position
			local through, free = hitPart(player, result, dir, stats, from)
			if not through or (left <= 0 and not free) then
				break
			end
			if not free then
				left -= 1
			end
			if rayParams == params then
				-- The shared params stay as they are; this round gets its own copy that skips the ones it went through.
				rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = table.clone(exclude)
				rayParams.CollisionGroup = params.CollisionGroup
			end
			rayParams:AddToFilter(through)
			travel -= (result.Position - start).Magnitude
			start = result.Position
			if travel <= 0.5 then
				break
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
