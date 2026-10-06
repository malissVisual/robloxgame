--!strict
-- 4.5: the admin's test buddies: NPC companions that play along with their owner (follow on foot, ride in the
-- owner's car as passengers, fight the zombies and bandits around them). Only the admin tools make them (server/Admin
-- commands "buddy", "buddyDismiss", "buddyMode"), so one person can test the co-op things alone.
--
--   * a buddy is an R15 courier (server/Npcs.luau's people: charcoal vest, red cap, a pistol in the hand) with a small
--     "BUDDY n" tag and a health bar. It lives in workspace.Npcs (the Npc collision group: it never pushes a car, the
--     bullets pass through it), its root is the server's (no jitter), it stands anchored and walks unanchored.
--   * follow: it walks (runs when far) to its place behind the owner (shared/BuddyBrain.luau), looks for a way round
--     (PathfindingService) when stuck, and appears at its place when stuck longer or left far behind. The owner in
--     their own car: it takes a free passenger seat (never the driver's, never one a player is getting into, and it
--     gives its seat up to a player at the door: Vehicles.yieldSeat); the owner out of the car: it gets out too.
--   * stay: it stands where it is. guard: it holds its spot, steps out a little toward an enemy, walks back.
--   * in every mode it shoots the nearest enemy in range with a clear line (zombies, the bandits on foot, bandit
--     cars), from the window too when it rides. Its kills pay nobody (Zombies.damage with no player), so a buddy is
--     no money tap. The zombies and the bandits on foot go after it like after a player on foot
--     (Zombies.extraTargets); bandit cars only after their player.
--   * it takes damage; at 0 it falls, and comes back near its owner Config.Buddy.RespawnSeconds later. When the owner
--     dies, the buddies wait; when the owner leaves, they are gone.
-- One throttled loop for all buddies (Config.Buddy.Tick), each buddy in its own pcall.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GunModels = require(Shared.GunModels)
local BuddyBrain = require(Shared.BuddyBrain)
local Npcs = require(script.Parent.Npcs)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)
local BanditCars = require(script.Parent.BanditCars)

local Buddy = {}

export type Mode = "follow" | "stay" | "guard"

type Mate = {
	owner: Player,
	number: number, -- its number on the tag (BUDDY n)
	model: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	body: { BasePart }, -- its own parts (massless while it rides)
	fill: Frame?, -- the health bar
	sitTrack: AnimationTrack?,
	dead: boolean,
	downAt: number, -- os.clock() when it fell (it comes back RespawnSeconds later)
	walking: boolean,
	running: boolean,
	ordered: Vector3?, -- where it was last sent
	orderedAt: number,
	lastPos: Vector3?,
	stuckFor: number,
	path: { Vector3 }?, -- a way round (PathfindingService)
	jumps: { boolean }?,
	pathIndex: number,
	pathGoal: Vector3?,
	pathing: boolean,
	seat: Seat?,
	car: Vehicles.Car?,
	seatCooldown: number, -- no seat before this (it just gave one up to a player)
	nextShot: number,
	home: Vector3?, -- guard: its spot
}

type Crew = { mode: Mode, mates: { Mate } }

type Foe = { zombie: Zombies.Zombie?, bandit: any?, position: Vector3, velocity: Vector3, model: Instance }

local cfg = Config.Buddy
local crews: { [Player]: Crew } = {}
local rng = Random.new()
local tracer = Net.get("Tracer")
local SIT = "rbxassetid://2506281703" -- Roblox's R15 sit
local BAR_RED = Color3.fromRGB(215, 74, 70)
local FALL_SECONDS = 3 -- a fallen buddy lies there this long

local PISTOL_COLOR = Color3.fromRGB(255, 230, 140)
for _, def in Config.Weapons do
	if def.id == "pistol" then
		PISTOL_COLOR = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	end
end

local SKINS = { { 241, 194, 160 }, { 176, 122, 84 }, { 255, 224, 196 } }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- ── The body ───────────────────────────────────────────────────────────────

-- The ground under (x, z) near height refY (a floor indoors, not the roof over it), else refY itself.
local function groundAt(x: number, z: number, refY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, name in { "Npcs", "Zombies", "Cars", "Traffic", "BanditCars", "Animals", "Loot", "Effects" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(Vector3.new(x, refY + 6, z), Vector3.new(0, -40, 0), params)
	if hit and hit.Normal.Y > 0.5 then
		return hit.Position.Y
	end
	return refY
end

-- The feet of a character (its root floats HipHeight over them).
local function feetY(root: BasePart, humanoid: Humanoid?): number
	return root.Position.Y - (if humanoid then humanoid.HipHeight else 2) - root.Size.Y / 2
end

local function courierLook(number: number): Npcs.Look
	return {
		name = `BUDDY {number}`,
		skin = SKINS[(number - 1) % #SKINS + 1],
		hair = { 40, 30, 24 },
		shirt = { 236, 236, 236 },
		pants = { 44, 46, 56 },
		vest = { 40, 42, 50 },
		hat = "cap",
		hatColor = { 215, 74, 70 },
		shoes = { 30, 30, 32 },
		boots = true,
		walkSpeed = cfg.Speed,
	}
end

-- The contract-style tag: small white caps and a thin health bar (named NameTag: Npcs.say hides it while it talks).
local function makeTag(head: BasePart, number: number): Frame
	local old = head:FindFirstChild("NameTag")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(110, 24)
	gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y * 0.5 + 0.9, 0)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.Size = UDim2.new(1, 0, 0, 14)
	label.BackgroundTransparency = 1
	label.Text = `BUDDY {number}`
	label.TextSize = 12
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.45
	label.Parent = gui
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, 17)
	back.Size = UDim2.fromOffset(40, 3)
	back.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BAR_RED
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = head
	return fill
end

local function setMassless(mate: Mate, on: boolean)
	for _, p in mate.body do
		if p.Parent then
			p.Massless = on
		end
	end
end

local function clearBody(mate: Mate)
	mate.model, mate.humanoid, mate.root, mate.fill, mate.sitTrack = nil, nil, nil, nil, nil
	mate.body = {}
	mate.seat, mate.car = nil, nil
	mate.walking, mate.running, mate.ordered, mate.lastPos = false, false, nil, nil
	mate.stuckFor, mate.path, mate.jumps, mate.pathGoal, mate.pathing = 0, nil, nil, nil, false
end

-- A new body for the buddy, standing at `at` (feet), facing `face`.
local function buildBody(mate: Mate, at: Vector3, face: Vector3)
	local look = flat(face - at)
	local frame = if look.Magnitude > 0.05 then CFrame.lookAt(at, at + look) else CFrame.new(at)
	local model = Npcs.spawn(courierLook(mate.number), frame)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if not humanoid or not root then
		Npcs.remove(model) -- (no R15 rig on this server: no buddy)
		error("no R15 body for the buddy")
	end
	model.Name = `Buddy{mate.number}`
	model:SetAttribute("Buddy", mate.owner.UserId)
	model:SetAttribute("Busy", true) -- Npcs' greeting leaves it alone
	humanoid.MaxHealth = cfg.Health
	humanoid.Health = cfg.Health
	local body: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(body, d)
		end
	end
	local hand = model:FindFirstChild("RightHand")
	if hand and hand:IsA("BasePart") then
		GunModels.build("pistol", hand, GunModels.gripOn(hand)).Parent = model
	end
	local head = model:FindFirstChild("Head")
	local fill: Frame? = if head and head:IsA("BasePart") then makeTag(head, mate.number) else nil
	humanoid.HealthChanged:Connect(function(health)
		if fill then
			fill.Size = UDim2.fromScale(math.clamp(health / cfg.Health, 0, 1), 1)
		end
	end)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local sitTrack: AnimationTrack? = nil
	if animator then
		local ok, track = pcall(function()
			local animation = Instance.new("Animation")
			animation.AnimationId = SIT
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Action
			sitTrack = track
		end
	end
	clearBody(mate)
	mate.model, mate.humanoid, mate.root, mate.fill, mate.sitTrack, mate.body = model, humanoid, root, fill, sitTrack, body
	mate.dead = false
	Npcs.pace(model, cfg.Speed)
end

-- ── Moving ─────────────────────────────────────────────────────────────────

local function stand(mate: Mate)
	local model = mate.model
	if model and mate.walking then
		Npcs.stop(model) -- (anchored where it is)
	end
	mate.walking, mate.ordered, mate.lastPos, mate.stuckFor = false, nil, nil, 0
	mate.path, mate.jumps, mate.pathGoal = nil, nil, nil
end

-- Appear standing at (x, z) on the ground near refY, facing `face`.
local function placeAt(mate: Mate, x: number, z: number, refY: number, face: Vector3?)
	local model, root, humanoid = mate.model, mate.root, mate.humanoid
	if not model or not root or not humanoid then
		return
	end
	mate.walking = true
	stand(mate)
	local position = Vector3.new(x, groundAt(x, z, refY) + humanoid.HipHeight + root.Size.Y / 2, z)
	local look = if face then flat(face - position) else flat(root.CFrame.LookVector)
	model:PivotTo(if look.Magnitude > 0.05 then CFrame.lookAt(position, position + look) else CFrame.new(position))
end

-- When stuck a moment: a way round, worked out in the background.
local function findPath(mate: Mate, goal: Vector3)
	local root, model = mate.root, mate.model
	if mate.pathing or not root or not model then
		return
	end
	mate.pathing = true
	local from = root.Position
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		mate.pathing = false
		if not ok or path.Status ~= Enum.PathStatus.Success or mate.model ~= model then
			return
		end
		local points: { Vector3 } = {}
		local jumps: { boolean } = {}
		for _, waypoint in path:GetWaypoints() do
			table.insert(points, waypoint.Position)
			table.insert(jumps, waypoint.Action == Enum.PathWaypointAction.Jump)
		end
		mate.path, mate.jumps, mate.pathIndex, mate.pathGoal = points, jumps, 2, goal
	end)
end

-- Walk (or run) toward `goal`: around a wall by a path when stuck, appearing there when stuck too long.
local function moveTo(mate: Mate, goal: Vector3, run: boolean, dt: number, now: number)
	local model, root, humanoid = mate.model, mate.root, mate.humanoid
	if not model or not root or not humanoid then
		return
	end
	local position = root.Position
	local last = mate.lastPos
	local moved = if last and mate.walking then flat(position - last).Magnitude else cfg.Speed * dt
	mate.lastPos = position
	mate.stuckFor = BuddyBrain.stuck(mate.stuckFor, moved, dt, true)
	if mate.stuckFor >= cfg.StuckSeconds then
		placeAt(mate, goal.X, goal.Z, goal.Y, nil)
		return
	end
	if mate.stuckFor >= cfg.StuckPath and not mate.path then
		findPath(mate, goal)
	end
	-- A way round: its next point (dropped once the goal has moved on).
	local target = goal
	local path, jumps, pathGoal = mate.path, mate.jumps, mate.pathGoal
	if path and jumps and pathGoal then
		if flat(goal - pathGoal).Magnitude > 12 or mate.pathIndex > #path then
			mate.path, mate.jumps, mate.pathGoal = nil, nil, nil
		else
			while mate.pathIndex <= #path and flat(path[mate.pathIndex] - position).Magnitude < 2.5 do
				mate.pathIndex += 1
			end
			if mate.pathIndex <= #path then
				target = path[mate.pathIndex]
				if jumps[mate.pathIndex] then
					humanoid.Jump = true
				end
			end
		end
	end
	if run ~= mate.running then
		mate.running = run
		Npcs.pace(model, if run then cfg.RunSpeed else cfg.Speed)
	end
	local ordered = mate.ordered
	if not mate.walking or not ordered or (target - ordered).Magnitude > 1.5 or now - mate.orderedAt > 3 then
		mate.walking = true
		mate.ordered, mate.orderedAt = target, now
		Npcs.walkTo(model, target, nil, 15, { through = true, near = 1 })
	end
end

-- Turn to face a point (standing: its root is anchored, the turn is instant).
local function faceTo(mate: Mate, point: Vector3)
	local root = mate.root
	if root and root.Anchored and not mate.seat then
		local look = flat(point - root.Position)
		if look.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
		end
	end
end

-- ── Seats ──────────────────────────────────────────────────────────────────

local function seatFree(seat: Seat): boolean
	return seat.Occupant == nil and seat:GetAttribute("Reserved") == nil
end

local function sitIn(mate: Mate, car: Vehicles.Car, seat: Seat)
	local model, root, humanoid = mate.model, mate.root, mate.humanoid
	if not model or not root or not humanoid then
		return
	end
	mate.walking = true
	stand(mate) -- (cancels the walk; anchored a moment)
	setMassless(mate, true) -- it does not change how the car drives
	root.Anchored = false
	model:PivotTo(seat.CFrame * CFrame.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))
	seat:Sit(humanoid)
	mate.seat, mate.car = seat, car
	local track = mate.sitTrack
	if track then
		track:Play(0.15)
	end
end

-- Out of the seat (the owner got out, a player wants it, the car is gone): it stands at its door outside.
local function getOut(mate: Mate)
	local seat, car = mate.seat, mate.car
	mate.seat, mate.car = nil, nil
	local root, humanoid = mate.root, mate.humanoid
	local track = mate.sitTrack
	if track then
		track:Stop(0.15)
	end
	if seat then
		local seatWeld = seat:FindFirstChild("SeatWeld")
		if seatWeld then
			seatWeld:Destroy()
		end
	end
	if humanoid then
		humanoid.Sit = false
	end
	setMassless(mate, false)
	if not root then
		return
	end
	local spot = root.Position
	if car and seat and car.chassis.Parent then
		local index = seat:GetAttribute("Door")
		local door = car.doors[if type(index) == "number" then index else 1]
		if door then
			spot = (car.chassis.CFrame * CFrame.new(door.side * (car.size.X / 2 + 4), 0, door.z)).Position
		end
	end
	placeAt(mate, spot.X, spot.Z, spot.Y, nil)
end

-- ── Fighting ───────────────────────────────────────────────────────────────

-- The nearest enemy within reach: the people (bandits, gunners, soldiers) only when they go after the owner.
local function nearestFoe(position: Vector3, reach: number, hunted: boolean): Foe?
	local best: Foe? = nil
	local bestDistance = reach
	for _, z in Zombies.all() do
		if z.dead or not z.root.Parent or (z.def.jobOnly and not hunted) then
			continue
		end
		local d = (z.root.Position - position).Magnitude
		if d < bestDistance then
			bestDistance = d
			best = { zombie = z, position = z.root.Position, velocity = z.root.AssemblyLinearVelocity, model = z.model :: Instance }
		end
	end
	local bandit, chassis = BanditCars.nearest(position, bestDistance)
	if bandit and chassis then
		best = { bandit = bandit, position = chassis.Position + Vector3.new(0, 1.5, 0), velocity = chassis.AssemblyLinearVelocity, model = bandit.npc.model :: Instance }
	end
	return best
end

-- A clear line from `from` to the foe (walls stop it; cars and bodies do not, like the players' bullets).
local function clearShot(from: Vector3, foe: Foe, exclude: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(exclude)
	local zombies = workspace:FindFirstChild("Zombies")
	if zombies then
		table.insert(list, zombies)
	end
	params.FilterDescendantsInstances = list
	params.CollisionGroup = "Bullet"
	local result = workspace:Raycast(from, foe.position - from, params)
	return result == nil or result.Instance:IsDescendantOf(foe.model)
end

-- One shot (a tracer everybody sees; the damage pays nobody). Returns whether it fired.
local function fire(mate: Mate, from: Vector3, sight: Vector3, foe: Foe, exclude: { Instance }): boolean
	if not clearShot(sight, foe, exclude) then
		return false
	end
	local aim = foe.position
	if rng:NextNumber() < BuddyBrain.hitChance(flat(foe.velocity).Magnitude) then
		tracer:FireAllClients(from, aim, PISTOL_COLOR, 0)
		local z = foe.zombie
		if z then
			Zombies.damage(z, cfg.Damage, nil, { cause = "buddy" })
		elseif foe.bandit then
			BanditCars.damage(foe.bandit, cfg.Damage, nil, "gun")
		end
	else
		tracer:FireAllClients(from, aim + Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(-1, 3), rng:NextNumber(-5, 5)), PISTOL_COLOR, 0)
	end
	return true
end

-- Every FireEvery: the nearest enemy in range takes a shot, on foot or out of the window.
local function fight(mate: Mate, foe: Foe?, now: number)
	local root, model = mate.root, mate.model
	if not foe or not root or not model or now < mate.nextShot then
		return
	end
	local exclude: { Instance } = { model }
	local character = mate.owner.Character
	if character then
		table.insert(exclude, character)
	end
	local from: Vector3
	local sight: Vector3
	local seat, car = mate.seat, mate.car
	if seat and car then
		from = Vehicles.windowPoint(car, seat)
		sight = from
		table.insert(exclude, car.model)
	else
		faceTo(mate, foe.position)
		sight = root.Position + Vector3.new(0, 1.5, 0)
		local gun = model:FindFirstChild("HandGun")
		local muzzle = gun and gun:FindFirstChild("Muzzle", true)
		from = if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else sight
	end
	if fire(mate, from, sight, foe, exclude) then
		mate.nextShot = now + cfg.FireEvery * rng:NextNumber(0.85, 1.15)
	else
		mate.nextShot = now + 0.3 -- no line: look again soon
	end
end

-- ── Life and death ─────────────────────────────────────────────────────────

local function fall(mate: Mate, now: number)
	if mate.seat then
		getOut(mate)
	end
	mate.walking = true
	stand(mate)
	mate.dead = true
	mate.downAt = now
	local root, model = mate.root, mate.model
	if root and model then
		-- On its back on the ground.
		local y = groundAt(root.Position.X, root.Position.Z, root.Position.Y - 2)
		local look = flat(root.CFrame.LookVector)
		local at = Vector3.new(root.Position.X, y + 0.6, root.Position.Z)
		local frame = if look.Magnitude > 0.05 then CFrame.lookAt(at, at + look) else CFrame.new(at)
		model:PivotTo(frame * CFrame.Angles(-math.pi / 2, 0, 0))
		local head = model:FindFirstChild("Head")
		local tag = head and head:FindFirstChild("NameTag")
		local label = tag and tag:FindFirstChild("Name")
		if label and label:IsA("TextLabel") then
			label.Text = `BUDDY {mate.number} · DOWN`
			label.TextColor3 = Color3.fromRGB(170, 170, 176)
		end
	end
end

local function removeBody(mate: Mate)
	if mate.seat then
		getOut(mate)
	end
	local model = mate.model
	clearBody(mate)
	if model then
		Npcs.remove(model)
	end
end

-- The owner's root and humanoid, alive (else nil).
local function ownerBody(owner: Player): (BasePart?, Humanoid?)
	local character = owner.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root, humanoid
	end
	return nil, nil
end

-- Buddy k of n: its place round the owner, on the ground near the owner's feet.
local function placeOf(k: number, n: number, root: BasePart, humanoid: Humanoid): Vector3
	local look = root.CFrame.LookVector
	local x, z = BuddyBrain.place(k, n, root.Position.X, root.Position.Z, look.X, look.Z)
	return Vector3.new(x, feetY(root, humanoid), z)
end

-- ── The loop ───────────────────────────────────────────────────────────────

-- The owner sits in their own car: into a free passenger seat (or to the car first); none free: it waits.
local function ride(mate: Mate, car: Vehicles.Car, dt: number, now: number)
	local root = mate.root
	if not root then
		return
	end
	if car.wrecked or car.chauffeured or car.repairing or now < mate.seatCooldown then
		stand(mate)
		return
	end
	local free: { boolean } = {}
	for i, seat in car.passengers do
		free[i] = seatFree(seat)
	end
	local index = BuddyBrain.pickSeat(free)
	local seat = if index then car.passengers[index] else nil
	if not seat then
		stand(mate)
		return
	end
	local distance = (seat.Position - root.Position).Magnitude
	if BuddyBrain.boarding(distance, Vehicles.speed(car), mate.stuckFor) == "sit" then
		sitIn(mate, car, seat)
		return
	end
	-- To its door, outside the car.
	local door = car.doors[(seat:GetAttribute("Door") :: number?) or 1]
	local side = if door then door.side else 1
	local at = (car.chassis.CFrame * CFrame.new(side * (car.size.X / 2 + 2.5), 0, if door then door.z else 0)).Position
	moveTo(mate, Vector3.new(at.X, root.Position.Y, at.Z), distance > cfg.RunFrom, dt, now)
end

local function stepMate(mate: Mate, crew: Crew, k: number, n: number, foe: Foe?, dt: number, now: number)
	local owner = mate.owner
	local ownerRoot, ownerHumanoid = ownerBody(owner)
	if mate.dead then
		if mate.model and now - mate.downAt >= FALL_SECONDS then
			removeBody(mate)
		end
		if now - mate.downAt >= cfg.RespawnSeconds and ownerRoot and ownerHumanoid then
			local ok, err = pcall(function()
				buildBody(mate, placeOf(k, n, ownerRoot, ownerHumanoid), ownerRoot.Position)
			end)
			if not ok then
				mate.downAt = now -- (tried again a respawn later)
				warn(`[Buddy] {err}`)
			end
		end
		return
	end
	local model, root, humanoid = mate.model, mate.root, mate.humanoid
	if not model or not root or not humanoid or not model.Parent then
		-- Its body is gone (removed by something else): it comes back like a fallen one.
		clearBody(mate)
		mate.dead, mate.downAt = true, now - FALL_SECONDS
		return
	end
	if humanoid.Health <= 0 then
		fall(mate, now)
		return
	end

	-- Riding: still in the owner's car? (out when the owner got out, the car is gone, or a wreck threw it out)
	local ownerCar = Vehicles.seatedIn(owner)
	if ownerCar and ownerCar.owner ~= owner then
		ownerCar = nil -- riding in somebody else's car: the buddies do not take its seats
	end
	local seat = mate.seat
	if seat then
		if humanoid.SeatPart ~= seat or not seat.Parent or mate.car ~= ownerCar then
			getOut(mate)
		else
			fight(mate, foe, now)
			return
		end
	end

	if crew.mode == "follow" and ownerCar then
		ride(mate, ownerCar, dt, now)
		fight(mate, foe, now)
		return
	end
	local riding = ownerRoot ~= nil and Vehicles.seatedIn(owner) ~= nil
	local position = root.Position
	local placeX, placeZ, ownerX, ownerZ = nil, nil, nil, nil
	local refY = position.Y
	if ownerRoot and ownerHumanoid and not riding then
		local place = placeOf(k, n, ownerRoot, ownerHumanoid)
		placeX, placeZ, ownerX, ownerZ = place.X, place.Z, ownerRoot.Position.X, ownerRoot.Position.Z
		refY = place.Y
	end
	local home = mate.home
	local decision = BuddyBrain.decide({
		mode = crew.mode,
		x = position.X,
		z = position.Z,
		moving = mate.walking,
		ownerX = ownerX,
		ownerZ = ownerZ,
		placeX = placeX,
		placeZ = placeZ,
		homeX = if home then home.X else nil,
		homeZ = if home then home.Z else nil,
		enemyX = if foe then foe.position.X else nil,
		enemyZ = if foe then foe.position.Z else nil,
	})
	if decision.action == "teleport" then
		placeAt(mate, decision.x, decision.z, if crew.mode == "guard" and home then home.Y else refY, if ownerRoot then ownerRoot.Position else nil)
	elseif decision.action == "move" then
		moveTo(mate, Vector3.new(decision.x, if crew.mode == "guard" and home then home.Y else refY, decision.z), decision.run, dt, now)
	else
		stand(mate)
	end
	fight(mate, foe, now)
end

local function step(dt: number)
	local now = os.clock()
	for owner, crew in crews do
		if not owner.Parent then
			continue
		end
		local ok, hunted = pcall(Zombies.hunts, owner)
		local people = ok and hunted == true
		local n = #crew.mates
		for k, mate in crew.mates do
			local fine, err = pcall(function()
				local root = mate.root
				local foe = if root and not mate.dead then nearestFoe(root.Position, cfg.Range, people) else nil
				stepMate(mate, crew, k, n, foe, dt, now)
			end)
			if not fine then
				warn(`[Buddy] {err}`)
			end
		end
	end
end

-- ── The admin's commands ───────────────────────────────────────────────────

-- Makes `count` buddies for the owner (capped); returns how many the owner has now.
function Buddy.spawn(owner: Player, count: number?): number
	if not owner.Parent then
		return 0
	end
	local crew = crews[owner]
	if not crew then
		crew = { mode = "follow", mates = {} }
		crews[owner] = crew
	end
	local mates = crew.mates
	local add = BuddyBrain.allowed(#mates, count)
	local root, humanoid = ownerBody(owner)
	for _ = 1, add do
		-- The lowest free number (BUDDY 1, 2, 3).
		local number = 1
		local used = true
		while used do
			used = false
			for _, m in mates do
				if m.number == number then
					used = true
					number += 1
					break
				end
			end
		end
		local mate: Mate = {
			owner = owner,
			number = number,
			body = {},
			dead = true,
			downAt = -math.huge,
			walking = false,
			running = false,
			orderedAt = 0,
			stuckFor = 0,
			pathIndex = 1,
			pathing = false,
			seatCooldown = 0,
			nextShot = 0,
		}
		table.insert(mates, mate)
		if root and humanoid then
			local ok, err = pcall(function()
				buildBody(mate, placeOf(#mates, #mates, root, humanoid), root.Position)
			end)
			if ok then
				local body = mate.root
				if crew.mode == "guard" and body then
					mate.home = Vector3.new(body.Position.X, feetY(body, mate.humanoid), body.Position.Z)
				end
				local model = mate.model
				if model then
					Npcs.say(model, "Ready when you are.", 2)
				end
			else
				warn(`[Buddy] {err}`)
				table.remove(mates, table.find(mates, mate) or #mates)
				break
			end
		end
		-- (the owner dead or not spawned yet: it comes as soon as they are, see stepMate)
	end
	return #mates
end

-- Removes the owner's buddies.
function Buddy.dismiss(owner: Player)
	local crew = crews[owner]
	crews[owner] = nil
	if not crew then
		return
	end
	for _, mate in crew.mates do
		pcall(removeBody, mate)
	end
end

-- follow: with you (on foot, and into your car); stay: where they stand (they still fight); guard: they stand and
-- fight anything that comes near, and run back to their spot.
function Buddy.setMode(owner: Player, mode: Mode)
	local crew = crews[owner]
	if not crew or not BuddyBrain.validMode(mode) then
		return
	end
	crew.mode = mode
	for _, mate in crew.mates do
		local root = mate.root
		mate.home = if mode == "guard" and root and not mate.dead
			then Vector3.new(root.Position.X, feetY(root, mate.humanoid), root.Position.Z)
			else nil
		if mode ~= "follow" and mate.seat then
			pcall(getOut, mate) -- stay / guard: out of the car, right here
		end
		local model = mate.model
		if model and not mate.dead then
			Npcs.say(model, if mode == "follow" then "Right behind you." elseif mode == "stay" then "Holding here." else "Guarding this spot.", 2)
		end
	end
end

-- How many buddies the owner has.
function Buddy.count(owner: Player): number
	local crew = crews[owner]
	return if crew then #crew.mates else 0
end

-- The buddies on foot, alive, for the zombies and the bandits (Zombies.extraTargets).
local function targets(): { Zombies.ExtraTarget }
	local list: { Zombies.ExtraTarget } = {}
	for owner, crew in crews do
		for _, mate in crew.mates do
			local root, humanoid = mate.root, mate.humanoid
			if not mate.dead and root and humanoid and humanoid.Health > 0 and not humanoid.SeatPart and root.Parent then
				table.insert(list, { position = root.Position, velocity = root.AssemblyLinearVelocity, humanoid = humanoid, player = owner })
			end
		end
	end
	return list
end

-- A player at the door wants the seat a buddy sits in (Vehicles.yieldSeat): the buddy gets out.
local function yieldSeat(seat: Seat): boolean
	for _, crew in crews do
		for _, mate in crew.mates do
			if mate.seat == seat then
				getOut(mate)
				mate.seatCooldown = os.clock() + 3
				return true
			end
		end
	end
	return false
end

function Buddy.start()
	Zombies.extraTargets = targets
	Vehicles.yieldSeat = yieldSeat
	Players.PlayerRemoving:Connect(Buddy.dismiss)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < cfg.Tick then
			return
		end
		local elapsed = math.min(acc, 1)
		acc = 0
		if next(crews) == nil then
			return
		end
		step(elapsed)
	end)
end

return Buddy
