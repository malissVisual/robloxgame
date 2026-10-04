--!strict
-- Bandit cars: a black pickup with two gunners in the bed comes after you during a job (Config tiers: chaseEvery,
-- chaseMax), chases you along the roads, rams you from the side and shoots at your car. Destroy it (guns, ramming,
-- mines, molotovs) for a reward.
--
-- The server drives them: the same movers as the players' cars (LinearVelocity + AngularVelocity on the chassis),
-- set every frame. The AI aims straight at you when it sees you, otherwise it follows the road that leads your way,
-- and backs up when it is stuck.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local PlayerData = require(script.Parent.PlayerData)

local Tuning = Config.BanditCar
local DEF = Tuning.car

type Bandit = {
	npc: Vehicles.NpcCar,
	target: Player,
	health: number,
	dead: boolean,
	born: number,
	speed: number, -- signed, along the nose
	waypoint: Vector3,
	nextThink: number,
	nextShot: number,
	nextSwipe: number,
	nextRammed: number,
	gun: number, -- which gunner fires next
	stuck: number, -- seconds without moving while trying to
	reverseUntil: number,
	sees: boolean, -- a clear line to the target
	lastHitBy: Player?,
}

local BanditCars = {}

local bandits: { Bandit } = {}
local rng = Random.new()
local folder: Instance = workspace

-- Set by Main.
BanditCars.onKill = function(_player: Player) end
BanditCars.onCarDamaged = function(_player: Player, _amount: number) end
BanditCars.onSteal = function(_player: Player, _share: number) end
-- Is the player still worth chasing (on a job)? When not, the bandits give up once they fall behind.
BanditCars.wanted = function(_player: Player): boolean
	return true
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function targetInfo(b: Bandit): (Vector3?, Vector3, Vehicles.Car?, Humanoid?)
	local car = Vehicles.seatedIn(b.target) or Vehicles.get(b.target)
	if car then
		return car.chassis.Position, car.chassis.AssemblyLinearVelocity, car, nil
	end
	local character = b.target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root.Position, root.AssemblyLinearVelocity, nil, humanoid
	end
	return nil, Vector3.zero, nil, nil
end

local function clearLine(from: Vector3, to: Vector3, targetModel: Instance?): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, workspace:FindFirstChild("Zombies") or folder }
	local result = workspace:Raycast(from, to - from, params)
	return result == nil or (targetModel ~= nil and result.Instance:IsDescendantOf(targetModel))
end

-- ── Life and death ─────────────────────────────────────────────────────────

local function remove(b: Bandit)
	b.dead = true
	local index = table.find(bandits, b)
	if index then
		table.remove(bandits, index)
	end
end

local function explode(b: Bandit, killer: Player?)
	if b.dead then
		return
	end
	remove(b)
	local npc = b.npc
	local blast = Instance.new("Explosion")
	blast.BlastPressure = 0
	blast.DestroyJointRadiusPercent = 0
	blast.BlastRadius = 10
	blast.Position = npc.chassis.Position
	blast.Parent = workspace
	npc.linear:Destroy()
	npc.angular.AngularVelocity = Vector3.zero
	for _, d in npc.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = d.Color:Lerp(Color3.new(0.08, 0.08, 0.08), 0.75)
		elseif d:IsA("SpotLight") then
			d:Destroy()
		end
	end
	local fire = Instance.new("Fire")
	fire.Size = 10
	fire.Heat = 12
	fire.Parent = npc.chassis
	npc.model:SetAttribute("Health", 0)
	if killer and killer.Parent then
		PlayerData.addMoney(killer, Tuning.Reward)
		local profile = PlayerData.get(killer)
		if profile then
			profile.kills += 1
		end
		Net.get("Reward"):FireClient(killer, npc.chassis.Position + Vector3.new(0, 6, 0), Tuning.Reward)
		Net.get("Notice"):FireClient(killer, `Bandit car destroyed! +${Tuning.Reward}`)
		BanditCars.onKill(killer)
	end
	task.delay(6, function()
		npc.model:Destroy()
	end)
end

-- Returns true when it blew up.
function BanditCars.damage(b: Bandit, amount: number, by: Player?): boolean
	if b.dead or amount <= 0 then
		return false
	end
	b.lastHitBy = by or b.lastHitBy
	b.health -= amount
	b.npc.model:SetAttribute("Health", math.max(0, math.ceil(b.health)))
	if b.health <= 0 then
		explode(b, b.lastHitBy)
		return true
	end
	return false
end

-- The bandit car a part belongs to (a hit of a gun).
function BanditCars.fromPart(part: Instance): Bandit?
	for _, b in bandits do
		if part:IsDescendantOf(b.npc.model) then
			return b
		end
	end
	return nil
end

-- Blasts and fires (grenade launcher, molotov, mine). Returns how many blew up.
function BanditCars.damageArea(center: Vector3, radius: number, damage: number, by: Player?): number
	local destroyed = 0
	for _, b in table.clone(bandits) do
		local distance = (b.npc.chassis.Position - center).Magnitude
		if distance <= radius + 4 then
			if BanditCars.damage(b, damage * (1 - 0.5 * math.clamp(distance / (radius + 4), 0, 1)), by) then
				destroyed += 1
			end
		end
	end
	return destroyed
end

-- Within `reach` of a point (the landmines).
function BanditCars.near(position: Vector3, reach: number): boolean
	for _, b in bandits do
		if (b.npc.chassis.Position - position).Magnitude < reach then
			return true
		end
	end
	return false
end

function BanditCars.countFor(player: Player): number
	local n = 0
	for _, b in bandits do
		if b.target == player then
			n += 1
		end
	end
	return n
end

-- ── Spawning ───────────────────────────────────────────────────────────────

-- A bandit pickup on the road behind the player, coming after them.
function BanditCars.chase(player: Player, position: Vector3, heading: Vector3?): boolean
	local back = if heading and flat(heading).Magnitude > 5 then -flat(heading).Unit else Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
	for _ = 1, 4 do
		local guess = position + back * Tuning.SpawnBehind + Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(-40, 40))
		local x, z, dx, dz = Map.nearestRoad(guess.X, guess.Z)
		local spot = Vector3.new(x, World.RoadTop + 0.5, z)
		if Map.isSafe(x, z) or Map.onIce(x, z) or (flat(spot - position)).Magnitude < 110 then
			continue
		end
		local along = Vector3.new(dx, 0, dz)
		if along:Dot(position - spot) < 0 then
			along = -along
		end
		local npc = Vehicles.buildNpc(DEF, CFrame.lookAt(spot, spot + along))
		npc.model.Name = "Bandit Pickup"
		npc.model:SetAttribute("Bandit", true)
		npc.model:SetAttribute("Health", DEF.health)
		npc.model:SetAttribute("MaxHealth", DEF.health)
		npc.model.Parent = folder
		local mass = npc.chassis.AssemblyMass
		npc.linear.MaxForce = mass * 160
		npc.angular.MaxTorque = mass * 6000
		pcall(function()
			npc.chassis:SetNetworkOwner(nil)
		end)
		table.insert(bandits, {
			npc = npc,
			target = player,
			health = DEF.health,
			dead = false,
			born = os.clock(),
			speed = 0,
			waypoint = position,
			nextThink = 0,
			nextShot = os.clock() + 2,
			nextSwipe = 0,
			nextRammed = 0,
			gun = 1,
			stuck = 0,
			reverseUntil = 0,
			sees = false,
			lastHitBy = nil,
		})
		return true
	end
	return false
end

function BanditCars.clearFor(player: Player)
	for _, b in table.clone(bandits) do
		if b.target == player then
			remove(b)
			b.npc.model:Destroy()
		end
	end
end

-- ── Driving and shooting ───────────────────────────────────────────────────

-- Where to go: straight at the target when it is in sight (or close), else along the road that leads its way.
local function think(b: Bandit, targetPosition: Vector3, targetVelocity: Vector3, targetModel: Instance?)
	local position = b.npc.chassis.Position
	local distance = flat(targetPosition - position).Magnitude
	b.sees = clearLine(position + Vector3.new(0, 3, 0), targetPosition + Vector3.new(0, 2, 0), targetModel)
	if b.sees or distance < 50 then
		b.waypoint = targetPosition + flat(targetVelocity) * math.clamp(distance / 80, 0, 0.6)
		return
	end
	local x, z, dx, dz = Map.nearestRoad(position.X, position.Z)
	local along = Vector3.new(dx, 0, dz)
	if along:Dot(targetPosition - position) < 0 then
		along = -along
	end
	b.waypoint = Vector3.new(x, position.Y, z) + along * 40
end

local function shoot(b: Bandit, targetPosition: Vector3, targetVelocity: Vector3, car: Vehicles.Car?, humanoid: Humanoid?)
	local npc = b.npc
	local gun = npc.guns[b.gun]
	b.gun = b.gun % math.max(1, #npc.guns) + 1
	local from = if gun then gun.Position else npc.chassis.Position + Vector3.new(0, 5, 0)
	local aim = targetPosition + Vector3.new(0, 1.5, 0)
	local relative = flat(targetVelocity - npc.chassis.AssemblyLinearVelocity).Magnitude
	local chance = Tuning.Accuracy * math.clamp(1 - relative / 90, 0.35, 1)
	local tracer = Net.get("Tracer")
	local color = Color3.fromRGB(255, 80, 60)
	-- The roof gun turns with them.
	local localTarget = npc.chassis.CFrame:PointToObjectSpace(aim)
	npc.turret.C0 = npc.turretBase * CFrame.Angles(0, math.atan2(-localTarget.X, -localTarget.Z), 0)
	if rng:NextNumber() < chance then
		tracer:FireAllClients(from, aim, color, 0)
		if car then
			Vehicles.damage(car, Tuning.ShotDamage, "The bandits shot your car to pieces!")
			BanditCars.onCarDamaged(car.owner, Tuning.ShotDamage)
		elseif humanoid then
			humanoid:TakeDamage(Tuning.ShotDamage)
		end
	else
		tracer:FireAllClients(from, aim + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-1, 4), rng:NextNumber(-6, 6)), color, 0)
	end
end

-- Is this point inside the box of a car (grown by reach)?
local function inBox(cframe: CFrame, size: Vector3, point: Vector3, reach: number): boolean
	local p = cframe:PointToObjectSpace(point)
	return math.abs(p.X) < size.X / 2 + reach and math.abs(p.Z) < size.Z / 2 + reach and math.abs(p.Y) < 8
end

local function drive(b: Bandit, dt: number, now: number)
	local npc = b.npc
	local chassis = npc.chassis
	local targetPosition, targetVelocity, car, humanoid = targetInfo(b)
	local position = chassis.Position

	-- Gone too far, lived too long, the target is gone: vanish.
	local distance = if targetPosition then flat(targetPosition - position).Magnitude else math.huge
	local givenUp = not BanditCars.wanted(b.target) and distance > 120
	if givenUp or not b.target.Parent or distance > Tuning.DespawnDistance or position.Y < -7 or (now - b.born > Tuning.Lifetime and distance > 200) then
		remove(b)
		npc.model:Destroy()
		return
	end
	if not targetPosition then
		npc.linear.PlaneVelocity = Vector2.zero
		npc.angular.AngularVelocity = Vector3.zero
		return
	end
	local targetModel: Instance? = if car then car.model elseif humanoid then humanoid.Parent else nil
	if now >= b.nextThink then
		b.nextThink = now + 0.25
		think(b, targetPosition, targetVelocity, targetModel)
	end

	-- Steering toward the waypoint.
	local look = flat(chassis.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		return
	end
	look = look.Unit
	local toward = flat(b.waypoint - position)
	local desired = if toward.Magnitude > 0.5 then toward.Unit else look
	local cross = look.X * desired.Z - look.Z * desired.X
	local angle = math.atan2(cross, look:Dot(desired))
	local yaw = math.clamp(-angle * 2.5, -DEF.turn, DEF.turn)

	-- Speed: race when far, match when close, slow in sharp turns, back up when stuck.
	local actual = chassis.AssemblyLinearVelocity:Dot(look)
	local target = if distance > 140 then Tuning.CatchUpSpeed else DEF.maxSpeed
	if distance < 40 then
		target = math.min(target, flat(targetVelocity).Magnitude + 12)
	end
	if math.abs(angle) > 1.1 then
		target = math.min(target, 30)
	end
	if now < b.reverseUntil then
		target = -22
		yaw = -yaw
	elseif b.speed > 15 and math.abs(actual) < 4 then
		b.stuck += dt
		if b.stuck > 1.2 then
			b.stuck = 0
			b.reverseUntil = now + 1.4
		end
	else
		b.stuck = 0
	end
	if math.abs(b.speed) > math.abs(actual) + 10 then
		b.speed = actual + (if b.speed > 0 then 10 else -10)
	end
	local rate = if math.sign(target) ~= math.sign(b.speed) then DEF.accel * 2 else DEF.accel
	b.speed = if b.speed < target then math.min(b.speed + rate * dt, target) else math.max(b.speed - rate * dt, target)
	local velocity = look * b.speed
	npc.linear.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	local grip = math.clamp(math.abs(b.speed) / 12, 0, 1)
	npc.angular.AngularVelocity = Vector3.new(0, yaw * grip * (if b.speed >= 0 then 1 else -1), 0)

	-- Alongside your car they reach over and take your cargo.
	if car and distance < 16 then
		BanditCars.onSteal(b.target, Tuning.StealPerSecond * dt)
	end

	-- Shooting.
	if b.sees and distance < Tuning.Range and now >= b.nextShot then
		b.nextShot = now + Tuning.FireEvery * rng:NextNumber(0.8, 1.2)
		shoot(b, targetPosition, targetVelocity, car, humanoid)
	end

	-- Contact with a player's car: they swipe you, you ram them.
	for _, playerCar in Vehicles.all() do
		if not inBox(playerCar.chassis.CFrame, playerCar.size, position, npc.size.X / 2 + 1) then
			continue
		end
		local relative = flat(playerCar.chassis.AssemblyLinearVelocity - chassis.AssemblyLinearVelocity).Magnitude
		if playerCar.owner == b.target and now >= b.nextSwipe then
			b.nextSwipe = now + 1.2
			Vehicles.damage(playerCar, Tuning.SwipeDamage, "The bandits rammed your car to pieces!")
			BanditCars.onCarDamaged(playerCar.owner, Tuning.SwipeDamage)
		end
		if relative > 25 and now >= b.nextRammed then
			b.nextRammed = now + 0.6
			if BanditCars.damage(b, relative * Tuning.RamDamagePerSpeed * playerCar.stats.ramPower, playerCar.owner) then
				return
			end
		end
	end
end

function BanditCars.start()
	folder = Instance.new("Folder")
	folder.Name = "BanditCars"
	folder.Parent = workspace
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, b in table.clone(bandits) do
			if not b.dead then
				drive(b, dt, now)
			end
		end
	end)
	Players.PlayerRemoving:Connect(BanditCars.clearFor)
end

return BanditCars
