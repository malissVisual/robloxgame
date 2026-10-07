--!strict
-- 3.9: the gun away and the hands on foot. The server keeps the holster and checks every swing:
--   Holster (B)  the client says holstered or not; the character's Holstered attribute says it to everybody (the clients
--                hide the gun in the hand, client/ArmPose.luau) and server/Gun.luau fires no hand-gun shot while it is
--                set. Every spawn starts holstered. In a car seat it changes nothing (window shots, the car gun).
--                6.0: without a gun (a new courier: fists only) a draw is refused, the hands stay empty.
--                6.1: B goes through what you hold (server/Hand.luau): a draw makes the gun the hand (a loaded bag in
--                your hand is set down first, server/Cargo.luau), a holster goes back to the bag or the fists.
--   Melee (V)    alive, on foot, the hands free (no cargo) and the cooldown over (Config.Melee): a punch when
--                holstered, a strike with the gun when it is out. It hits the nearest living zombie or bandit in a short
--                cone in front of you (shared/Melee.luau), pushes it back, and the kill counts like any other (the
--                money, the challenges: cause "melee"). The character's MeleeAt (server time) and MeleeKind attributes
--                make every client swing your arm (client/ArmPose.luau).
--                6.7: with the Baseball Bat owned (profile.kit, Config.Melee.BatKit) the punch is a bat swing
--                (Melee.kindOf: its damage, cooldown, push and longer reach); MeleeKind says the gun's strike (Melee.pose)
--                and a bat is welded into the right hand for that swing only (showBat, Config.Melee.BatLook).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Melee = require(Shared.Melee)
local Net = require(Shared.Net)
local Zombies = require(script.Parent.Zombies)
local Hand = require(script.Parent.Hand) -- 6.1: what you hold
local PlayerData = require(script.Parent.PlayerData) -- 6.7: the bat is kit

local CloseCombat = {}

local lastSwing: { [Player]: number } = {}

-- 6.7: the bat in the right hand (R15 RightHand, R6 Right Arm) for one swing: a taped handle and a wooden barrel out of
-- the fist along the hand's forward axis (a hammer's grip), welded, massless and touching nothing; gone after the swing.
local function showBat(character: Model)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local old = character:FindFirstChild("MeleeBat")
	if old then
		old:Destroy()
	end
	local look = Config.Melee.BatLook
	local model = Instance.new("Model")
	model.Name = "MeleeBat"
	local fist = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 + 0.1, 0)
	local function piece(name: string, length: number, thick: number, from: number, color: { number }, material: Enum.Material)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(length, thick, thick)
		part.CFrame = fist * CFrame.new(0, 0, -(from + length / 2)) * CFrame.Angles(0, math.rad(90), 0) -- (its axis on -Z)
		part.Color = Color3.fromRGB(color[1], color[2], color[3])
		part.Material = material
		part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, true
		part.CastShadow = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end
	local grip = look.Length * 0.4
	piece("Handle", grip + 0.3, look.Handle, -0.3, look.Grip, Enum.Material.SmoothPlastic)
	piece("Barrel", look.Length - grip, look.Barrel, grip, look.Wood, Enum.Material.Wood)
	model.Parent = character
	task.delay(Config.Melee.SwingTime + look.Linger, function()
		model:Destroy()
	end)
end

-- The holster of a character (true: the gun is away). A new character starts holstered.
local function setHolstered(character: Model, holstered: boolean)
	character:SetAttribute("Holstered", holstered)
	if holstered then
		character:SetAttribute("Aiming", false) -- no empty hands held up
	end
end

local function onHolster(player: Player, holstered: any)
	if type(holstered) ~= "boolean" or not player.Character then
		return
	end
	Hand.holster(player, holstered) -- 6.1 (6.0: no gun to draw, fists only: Hand refuses the draw)
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
	local profile = PlayerData.get(player)
	local kind = Melee.kindOf(character:GetAttribute("Holstered") == true, profile ~= nil and Melee.hasBat(profile.kit)) -- 6.7: the bat
	local def = Melee.def(kind)
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < def.cooldown * 0.8 then
		return -- faster than the swing allows (a little slack for the network)
	end
	lastSwing[player] = now
	-- Everybody sees the arm swing (the kind first: the clients read it when MeleeAt changes). 6.7: the bat swings like
	-- the gun's strike (Melee.pose), with the bat in the hand.
	character:SetAttribute("MeleeKind", Melee.pose(kind))
	character:SetAttribute("MeleeAt", workspace:GetServerTimeNow())
	if kind == "bat" then
		showBat(character)
	end
	local range = Melee.reachOf(kind) -- 6.7: the bat reaches further

	local dir = swingDirection(direction, root)
	local from = root.Position
	local best: Zombies.Zombie? = nil
	local bestDistance = math.huge
	local sight = RaycastParams.new()
	sight.FilterType = Enum.RaycastFilterType.Exclude
	for _, z in Zombies.all() do
		if z.dead or not z.root.Parent then
			continue
		end
		local at = z.root.Position
		local distance = Melee.reach(from.X, from.Y, from.Z, dir.X, dir.Z, at.X, at.Y, at.Z, range)
		if distance and distance < bestDistance then
			-- Not through a wall, a door or a car: nothing solid between the two (only for the few in reach).
			sight.FilterDescendantsInstances = { character, z.model }
			if not workspace:Raycast(from, at - from, sight) then
				best, bestDistance = z, distance
			end
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
