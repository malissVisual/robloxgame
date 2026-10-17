--!strict
-- 10.x danger: a run's bat (server/RunDanger.luau: its Tool's click). 10.5: only this is left of the city's close
-- combat (its holster, B, and its fists and gun strikes, V, went with the guns): CloseCombat.swing checks every swing
-- as they did.
--   CloseCombat.swing(player, kind, direction?, held?)   one swing of `kind` (Config.Melee.Kinds: the run's "bat"):
--                alive, on foot, the hands free (no piece carried) and the cooldown over (Config.Melee). It hits the
--                nearest living zombie in a short cone in front of you (shared/Melee.luau), not through a wall, pushes it
--                back, and the kill counts like any other (cause "melee"). The character's MeleeAt (server time) and
--                MeleeKind attributes make every client swing your arm (client/ArmPose.luau); a bat not `held` already is
--                welded into the right hand for that swing only (showBat, Config.Melee.BatLook). True when it swung.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Melee = require(Shared.Melee)
local Net = require(Shared.Net)
local Zombies = require(script.Parent.Zombies)

local CloseCombat = {}

local lastSwing: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any -- (a player who left goes with them)

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

function CloseCombat.swing(player: Player, kind: string, direction: any, held: boolean?): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return false
	end
	if humanoid.SeatPart ~= nil or humanoid.Sit then
		return false -- on foot only
	end
	if character:GetAttribute("Carrying") ~= nil then
		return false -- the hands are full
	end
	local def = Melee.def(kind)
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < def.cooldown * 0.8 then
		return false -- faster than the swing allows (a little slack for the network)
	end
	lastSwing[player] = now
	-- Everybody sees the arm swing (the kind first: the clients read it when MeleeAt changes). 6.7: the bat swings like
	-- the gun's strike (Melee.pose), with the bat in the hand.
	character:SetAttribute("MeleeKind", Melee.pose(kind))
	character:SetAttribute("MeleeAt", workspace:GetServerTimeNow())
	if kind == "bat" and not held then
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
		return true
	end
	local push = dir * def.push + Vector3.new(0, def.push * 0.4, 0)
	local damage = def.damage
	local killed = Zombies.damage(best, damage, player, { push = push, cause = "melee" })
	if not killed and not best.car and not best.root.Anchored then
		-- A stagger: a short shove back (a brute barely moves).
		local scale = math.max(1, best.def.scale)
		best.root.AssemblyLinearVelocity += dir * (def.push * 0.6 / scale) + Vector3.new(0, 4, 0)
	end
	Net.get("Hit"):FireClient(player, best.torso.Position, damage, false, killed)
	return true
end

return CloseCombat
