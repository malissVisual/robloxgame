--!strict
-- 3.9: the gun away and the hands on foot. The server keeps the holster and checks every swing:
--   Holster (B)  the client says holstered or not; the character's Holstered attribute says it to everybody (the clients
--                hide the gun in the hand, client/ArmPose.luau) and server/Gun.luau fires no hand-gun shot while it is
--                set. Every spawn starts holstered. In a car seat it changes nothing (window shots, the car gun).
--   Melee (V)    alive, on foot, the hands free (no cargo) and the cooldown over (Config.Melee): a punch when
--                holstered, a strike with the gun when it is out. It hits the nearest living zombie or bandit in a short
--                cone in front of you (shared/Melee.luau), pushes it back, and the kill counts like any other (the
--                money, the challenges: cause "melee"). The character's MeleeAt (server time) and MeleeKind attributes
--                make every client swing your arm (client/ArmPose.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Melee = require(Shared.Melee)
local Net = require(Shared.Net)
local Zombies = require(script.Parent.Zombies)

local CloseCombat = {}

local lastSwing: { [Player]: number } = {}

-- The holster of a character (true: the gun is away). A new character starts holstered.
local function setHolstered(character: Model, holstered: boolean)
	character:SetAttribute("Holstered", holstered)
	if holstered then
		character:SetAttribute("Aiming", false) -- no empty hands held up
	end
end

local function onHolster(player: Player, holstered: any)
	local character = player.Character
	if type(holstered) ~= "boolean" or not character then
		return
	end
	setHolstered(character, holstered)
end

-- The direction of the swing along the ground: the client's (a unit vector, checked), else where the body faces.
local function swingDirection(direction: any, root: BasePart): Vector3
	local facing = root.CFrame.LookVector
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if typeof(direction) == "Vector3" and direction == direction and math.abs(direction.Magnitude - 1) < 0.05 then
		local wanted = Vector3.new(direction.X, 0, direction.Z)
		if wanted.Magnitude > 0.1 then
			flat = wanted
		end
	end
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

local function onMelee(player: Player, direction: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end
	if humanoid.SeatPart ~= nil or humanoid.Sit then
		return -- on foot only
	end
	if character:GetAttribute("Carrying") ~= nil then
		return -- the hands are full
	end
	local kind = Melee.kindOf(character:GetAttribute("Holstered") == true)
	local def = Melee.def(kind)
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < def.cooldown * 0.8 then
		return -- faster than the swing allows (a little slack for the network)
	end
	lastSwing[player] = now
	-- Everybody sees the arm swing (the kind first: the clients read it when MeleeAt changes).
	character:SetAttribute("MeleeKind", kind)
	character:SetAttribute("MeleeAt", workspace:GetServerTimeNow())

	local dir = swingDirection(direction, root)
	local from = root.Position
	local best: Zombies.Zombie? = nil
	local bestDistance = math.huge
	for _, z in Zombies.all() do
		if z.dead or not z.root.Parent then
			continue
		end
		local at = z.root.Position
		local distance = Melee.reach(from.X, from.Y, from.Z, dir.X, dir.Z, at.X, at.Y, at.Z)
		if distance and distance < bestDistance then
			best, bestDistance = z, distance
		end
	end
	if not best then
		return
	end
	local push = dir * def.push + Vector3.new(0, def.push * 0.4, 0)
	local killed = Zombies.damage(best, def.damage, player, { push = push, cause = "melee" })
	if not killed and not best.car and not best.root.Anchored then
		-- A stagger: a short shove back (a brute barely moves).
		local scale = math.max(1, best.def.scale)
		best.root.AssemblyLinearVelocity += dir * (def.push * 0.6 / scale) + Vector3.new(0, 4, 0)
	end
	Net.get("Hit"):FireClient(player, best.torso.Position, def.damage, false, killed)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		setHolstered(character, true)
	end)
	local character = player.Character
	if character and character:GetAttribute("Holstered") == nil then
		setHolstered(character, true)
	end
end

function CloseCombat.start()
	Net.get("Holster").OnServerEvent:Connect(onHolster)
	Net.get("Melee").OnServerEvent:Connect(onMelee)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

return CloseCombat
