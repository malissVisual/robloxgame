--!strict
-- The fight of Grubnak — The Rift King, the final boss (wave 100). BattleService hands the boss over to this module
-- every tick (RiftKing.update): it runs his four special attacks while the normal autobattle goes on around him.
--
-- Every attack is: GROUND WARNING (a bright border, a translucent fill, flat on the arena floor; it never hurts)
-- → DODGE WINDOW (the marked area is locked the moment it appears) → IMPACT (hits exactly the marked area, once
-- per target). Your soldiers in the area take a multiple of the boss's damage; your own character (you stand in
-- the arena and can run and jump) takes health points. All numbers: shared/Config/RiftKing.luau.
--
--   1. CRYSTAL VOLLEY   three crystals fly along arcs onto red circles (locked), area damage where they land
--   2. HAMMER SLAM      an orange cone in front of the boss (locked direction), the hammer comes down after 1 s
--   3. RIFT SHOCKWAVE   a wind-up, then a purple ring runs outward; only the moving ring hurts: jump over it
--   4. METEOR RAIN      red circles with safe gaps between them, purple crystal meteors land after 1.5 s
-- Below 30 % health the boss is ENRAGED: crystals glow brighter, the armor shows glowing cracks, cooldowns
-- shrink and attacks come in pairs (a shockwave is followed by a volley, a slam by meteors), every one with its
-- own full warning. Everything is driven by the battle clock (so the battle speed stretches it too) and lives in
-- one folder that RiftKing.cleanup removes when the boss dies or the battle ends.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.RiftKing)
local Net = require(Shared.Net)
local Rig = require(Shared.Rig)
local Plots = require(script.Parent.Plots)

local UP = Vector3.new(0, 1, 0)
local PURPLE = Color3.fromRGB(185, 90, 255)
local BRIGHT_PURPLE = Color3.fromRGB(225, 160, 255)
local RED = Color3.fromRGB(255, 60, 60)
local ORANGE = Color3.fromRGB(255, 140, 40)
local RING_SEGMENTS = 32

-- What BattleService gives the fight: the battle's fighters (its own Fighter records: side, hp, maxHp, pos, lift,
-- clock, stunUntil, damage, model), the two damage helpers and where effects go.
export type Context = {
	player: Player,
	plot: Plots.Plot,
	parent: Instance,
	fighters: { any },
	playerSide: number,
	damage: (target: any, amount: number) -> number,
	popNumber: (target: any, amount: number) -> (),
}

type Event = { at: number, fn: () -> () }
type Mover = (dt: number) -> boolean -- runs every tick until it returns false

export type State = {
	ctx: Context,
	boss: any,
	fx: Folder,
	alive: boolean,
	clock: number,
	busyUntil: number, -- the boss stands and casts until this battle time
	nextAttackAt: number,
	lastAttack: string?,
	comboNext: string?, -- enraged: the attack that follows right away
	enraged: boolean,
	lastHp: number,
	staggerUntil: number,
	hpSentAt: number,
	events: { Event },
	movers: { Mover },
}

local RiftKing = {}

-- ── Small helpers ───────────────────────────────────────────────────────────

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function groundY(state: State, position: Vector3): number
	return state.ctx.plot.arena.heightAt(position.Z)
end

local function part(state: State, size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = state.fx
	return p
end

local function destroyAll(parts: { Instance })
	for _, p in parts do
		p:Destroy()
	end
	table.clear(parts)
end

local function schedule(state: State, delay: number, fn: () -> ())
	local at = state.clock + delay
	local events = state.events
	local index = #events + 1
	while index > 1 and events[index - 1].at > at do
		index -= 1
	end
	table.insert(events, index, { at = at, fn = fn })
end

local function addMover(state: State, mover: Mover)
	table.insert(state.movers, mover)
end

local function faceTowards(state: State, target: Vector3)
	local boss = state.boss
	local p = boss.pos + UP * boss.lift
	local look = Vector3.new(target.X, p.Y, target.Z)
	if (look - p).Magnitude > 0.05 and boss.model.Parent then
		boss.model:PivotTo(CFrame.lookAt(p, look))
	end
end

local function flash(state: State, color: Color3, duration: number)
	local model = state.boss.model
	if not model.Parent then
		return
	end
	local glow = Instance.new("Highlight")
	glow.Adornee = model
	glow.FillColor = color
	glow.FillTransparency = 0.5
	glow.OutlineColor = color
	glow.OutlineTransparency = 0.1
	glow.Parent = model
	Debris:AddItem(glow, duration)
end

-- Your characters standing in this plot's arena (every player, so a friend visiting your arena dodges too).
type Dodger = { player: Player, root: BasePart, humanoid: Humanoid }
local function playersInArena(state: State): { Dodger }
	local list: { Dodger } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and Plots.isInArena(state.ctx.plot, root.Position) then
			table.insert(list, { player = player, root = root, humanoid = humanoid })
		end
	end
	return list
end

-- Your soldiers that are alive.
local function soldiers(state: State): { any }
	local list = {}
	for _, f in state.ctx.fighters do
		if f.side == state.ctx.playerSide and f.hp > 0 then
			table.insert(list, f)
		end
	end
	return list
end

-- Where the boss aims: the characters in the arena first, then the soldiers (shuffled), as flat positions.
local function aimPoints(state: State): { Vector3 }
	local points: { Vector3 } = {}
	for _, d in playersInArena(state) do
		table.insert(points, flat(d.root.Position))
	end
	local troops = soldiers(state)
	for i = #troops, 2, -1 do
		local j = math.random(i)
		troops[i], troops[j] = troops[j], troops[i]
	end
	for _, f in troops do
		table.insert(points, flat(f.pos))
	end
	return points
end

-- Hits everything inside a circle once: soldiers for `soldierMult` x the boss's damage, characters for `playerHp`.
local function hitCircle(state: State, center: Vector3, radius: number, soldierMult: number, playerHp: number, stun: number?)
	local c = flat(center)
	for _, f in soldiers(state) do
		if (flat(f.pos) - c).Magnitude <= radius then
			local taken = state.ctx.damage(f, state.boss.damage * soldierMult)
			state.ctx.popNumber(f, taken)
			if stun then
				f.stunUntil = f.clock + stun
			end
		end
	end
	for _, d in playersInArena(state) do
		if (flat(d.root.Position) - c).Magnitude <= radius then
			d.humanoid:TakeDamage(playerHp)
		end
	end
end

-- The look of an impact: a shockwave ring, a flash and sparks.
local function impactFx(state: State, position: Vector3, radius: number, color: Color3)
	local y = groundY(state, position)
	local ring = part(state, Vector3.new(0.3, 1, 1), CFrame.new(position.X, y + 0.3, position.Z) * CFrame.Angles(0, 0, math.rad(90)), color, 0.2, Enum.PartType.Cylinder)
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = Vector3.new(0.3, radius * 2.2, radius * 2.2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.6)
	local burst = part(state, Vector3.one * 2, CFrame.new(position.X, y + 1.5, position.Z), color:Lerp(Color3.new(1, 1, 1), 0.5), 0.2, Enum.PartType.Ball)
	TweenService:Create(burst, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = Vector3.one * radius * 1.4, Transparency = 1 }):Play()
	Debris:AddItem(burst, 0.5)
	for _ = 1, 12 do
		local angle = math.random() * math.pi * 2
		local distance = radius * (0.3 + math.random() * 0.7)
		local shard = part(state, Vector3.new(0.3, 0.6, 0.3), CFrame.new(position.X, y + 1, position.Z) * CFrame.Angles(0, angle, 0), color, 0)
		TweenService:Create(shard, TweenInfo.new(0.5 + math.random() * 0.3, Enum.EasingStyle.Quad), {
			Position = Vector3.new(position.X + math.cos(angle) * distance, y + 2 + math.random() * 5, position.Z + math.sin(angle) * distance),
			Transparency = 1,
		}):Play()
		Debris:AddItem(shard, 0.9)
	end
end

-- ── Ground warnings (flat, a bright border and a translucent fill; they never hurt) ──

local function pulse(p: Part, from: number, to: number)
	TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = to }):Play()
	p.Transparency = from
end

-- A circle on the floor at `position` with `radius`: returns its parts (destroy them at the impact).
local function warningCircle(state: State, position: Vector3, radius: number, color: Color3): { Instance }
	local y = groundY(state, position)
	local turn = CFrame.Angles(0, 0, math.rad(90))
	local border = part(state, Vector3.new(0.28, radius * 2, radius * 2), CFrame.new(position.X, y + 0.2, position.Z) * turn, color, 0.05, Enum.PartType.Cylinder)
	local fill = part(state, Vector3.new(0.2, (radius - 0.35) * 2, (radius - 0.35) * 2), CFrame.new(position.X, y + 0.21, position.Z) * turn, color, 0.7, Enum.PartType.Cylinder)
	border:SetAttribute("Hazard", radius) -- the Mage's AI reads these and steps out of the circle
	pulse(fill, 0.7, 0.45)
	return { border, fill }
end

-- A cone (sector) on the floor from `origin`, pointing at `direction` (radians around Y, as in math.atan2 of x/z),
-- `halfAngle` radians to each side, `range` long: a fan of translucent slices plus bright edge lines and arc.
local function warningCone(state: State, origin: Vector3, direction: number, halfAngle: number, range: number, color: Color3): { Instance }
	local y = groundY(state, origin)
	local parts: { Instance } = {}
	local slices = 9
	local sliceHalf = halfAngle / slices
	local width = 2 * range * math.tan(sliceHalf) + 0.15
	for i = 1, slices do
		local a = direction - halfAngle + sliceHalf * (2 * i - 1)
		local mid = Vector3.new(origin.X + math.sin(a) * range / 2, y + 0.19, origin.Z + math.cos(a) * range / 2)
		local slice = part(state, Vector3.new(width, 0.18, range), CFrame.new(mid) * CFrame.Angles(0, a, 0), color, 0.7)
		pulse(slice, 0.7, 0.45)
		table.insert(parts, slice)
	end
	for _, a in { direction - halfAngle, direction + halfAngle } do
		local mid = Vector3.new(origin.X + math.sin(a) * range / 2, y + 0.22, origin.Z + math.cos(a) * range / 2)
		table.insert(parts, part(state, Vector3.new(0.3, 0.26, range), CFrame.new(mid) * CFrame.Angles(0, a, 0), color, 0.05))
	end
	local arcSegments = 10
	local step = (2 * halfAngle) / arcSegments
	for i = 1, arcSegments do
		local a = direction - halfAngle + step * (i - 0.5)
		local mid = Vector3.new(origin.X + math.sin(a) * range, y + 0.22, origin.Z + math.cos(a) * range)
		table.insert(parts, part(state, Vector3.new(range * step + 0.2, 0.26, 0.3), CFrame.new(mid) * CFrame.Angles(0, a, 0), color, 0.05))
	end
	return parts
end

-- Is this point inside the cone? (flat, radians)
local function inCone(origin: Vector3, direction: number, halfAngle: number, range: number, point: Vector3): boolean
	local d = flat(point) - flat(origin)
	local dist = d.Magnitude
	if dist > range or dist < 0.01 then
		return false
	end
	local a = math.atan2(d.X, d.Z)
	local diff = math.atan2(math.sin(a - direction), math.cos(a - direction))
	return math.abs(diff) <= halfAngle
end

-- ── The boss health bar (client) ────────────────────────────────────────────

local function sendHp(state: State, force: boolean?)
	if not force and state.clock - state.hpSentAt < Config.HpBarInterval then
		return
	end
	state.hpSentAt = state.clock
	local boss = state.boss
	local fraction = if state.alive and boss.hp > 0 then math.clamp(boss.hp / boss.maxHp, 0, 1) else 0
	if state.ctx.player.Parent then
		Net.get("BossHp"):FireClient(state.ctx.player, Config.Name, fraction, state.enraged)
	end
end

-- ── Enrage and stagger ──────────────────────────────────────────────────────

local function enrage(state: State)
	state.enraged = true
	local model = state.boss.model
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			if item:GetAttribute("RiftCrystal") then
				-- Brighter crystals, each with its own light.
				item.Color = BRIGHT_PURPLE
				if not item:FindFirstChildOfClass("PointLight") then
					local light = Instance.new("PointLight")
					light.Color = BRIGHT_PURPLE
					light.Range = 8
					light.Brightness = 1.6
					light.Shadows = false
					light.Parent = item
				end
			elseif item:GetAttribute("RiftArmor") then
				-- Glowing cracks over the armor plates: thin purple lines welded on the plate.
				for i = 1, 3 do
					local crack = Instance.new("Part")
					crack.Name = "Crack" .. i
					crack.Size = Vector3.new(0.08, item.Size.Y * (0.35 + math.random() * 0.4), 0.06)
					crack.Color = BRIGHT_PURPLE
					crack.Material = Enum.Material.Neon
					crack.CanCollide = false
					crack.CanQuery = false
					crack.CanTouch = false
					crack.Massless = true
					crack.CastShadow = false
					local x = (math.random() - 0.5) * item.Size.X * 0.8
					local yOff = (math.random() - 0.5) * item.Size.Y * 0.3
					crack.CFrame = item.CFrame * CFrame.new(x, yOff, -item.Size.Z / 2 - 0.02) * CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * 50))
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = item
					weld.Part1 = crack
					weld.Parent = crack
					crack.Parent = model
				end
			end
		end
	end
	flash(state, BRIGHT_PURPLE, 0.8)
	impactFx(state, state.boss.pos, 8, PURPLE)
	if state.ctx.player.Parent then
		Net.get("Notice"):FireClient(state.ctx.player, "GRUBNAK IS ENRAGED!")
	end
	sendHp(state, true)
end

local function stagger(state: State)
	state.staggerUntil = state.clock + Config.StaggerTime
	state.busyUntil = math.max(state.busyUntil, state.clock + Config.StaggerTime)
	flash(state, Color3.new(1, 1, 1), 0.35)
	-- A step back, away from the nearest soldier.
	local boss = state.boss
	local nearest, best = nil, math.huge
	for _, f in soldiers(state) do
		local d = (flat(f.pos) - flat(boss.pos)).Magnitude
		if d < best then
			nearest, best = f, d
		end
	end
	if nearest and best > 0.1 then
		local away = (flat(boss.pos) - flat(nearest.pos)).Unit * 2
		boss.pos = Vector3.new(boss.pos.X + away.X, boss.pos.Y, boss.pos.Z + away.Z)
		boss.model:PivotTo(CFrame.new(boss.pos + UP * boss.lift) * (boss.model:GetPivot() - boss.model:GetPivot().Position))
	end
end

-- ── The four attacks ────────────────────────────────────────────────────────

local function startVolley(state: State)
	local cfg = Config.Volley
	local boss = state.boss
	-- The circles are locked now and never overlap (two circles apart by their diameter), so one target can be
	-- inside one circle at most and every circle has a way out.
	local targets: { Vector3 } = {}
	local function farEnough(p: Vector3): boolean
		for _, t in targets do
			if (t - p).Magnitude < cfg.Radius * 2 then
				return false
			end
		end
		return true
	end
	for _, p in aimPoints(state) do
		if #targets >= cfg.Count then
			break
		end
		if farEnough(p) then
			table.insert(targets, p)
		end
	end
	local tries = 0
	while #targets < cfg.Count and tries < 40 do
		tries += 1
		local angle = math.random() * math.pi * 2
		local p = flat(boss.pos) + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (6 + math.random() * 10)
		if farEnough(p) then
			table.insert(targets, p)
		end
	end
	faceTowards(state, targets[1])
	Rig.cast(boss.model, "cast")
	local orb = boss.model:FindFirstChild("RiftOrb") :: BasePart?
	local start = if orb then orb.Position else boss.pos + UP * boss.lift * 1.5
	for i, target in targets do
		local y = groundY(state, target)
		local landing = Vector3.new(target.X, y, target.Z)
		local warning = warningCircle(state, landing, cfg.Radius, RED)
		-- The crystal: an arc from the orb to the circle, spinning as it flies.
		local lateral = Vector3.new(math.cos(i * 2.1), 0, math.sin(i * 2.1)) * 5
		local control = (start + landing) / 2 + UP * cfg.ArcHeight + lateral
		local crystal = part(state, Vector3.new(0.9, 1.8, 0.9), CFrame.new(start), PURPLE, 0)
		local trail = Instance.new("Trail")
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.9, 0)
		a1.Position = Vector3.new(0, -0.9, 0)
		a0.Parent = crystal
		a1.Parent = crystal
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(PURPLE)
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Lifetime = 0.35
		trail.Parent = crystal
		local t = 0
		addMover(state, function(dt)
			t = math.min(1, t + dt / cfg.WarningTime)
			local pos = start:Lerp(control, t):Lerp(control:Lerp(landing + UP * 0.9, t), t) -- quadratic Bezier
			crystal.CFrame = CFrame.new(pos) * CFrame.Angles(t * 9, i, t * 6)
			return t < 1 and crystal.Parent ~= nil
		end)
		schedule(state, cfg.WarningTime, function()
			destroyAll(warning)
			crystal:Destroy()
			impactFx(state, landing, cfg.Radius, PURPLE)
			hitCircle(state, landing, cfg.Radius, cfg.Damage, cfg.PlayerDamage)
		end)
	end
	state.busyUntil = state.clock + cfg.Busy
end

local function startSlam(state: State)
	local cfg = Config.Slam
	local boss = state.boss
	local points = aimPoints(state)
	local target = points[1] or (flat(boss.pos) + Vector3.new(0, 0, -8))
	local d = flat(target) - flat(boss.pos)
	local direction = if d.Magnitude > 0.1 then math.atan2(d.X, d.Z) else 0 -- locked now
	local halfAngle = math.rad(cfg.HalfAngle)
	faceTowards(state, target)
	Rig.cast(boss.model, "cast") -- both arms up: the hammer is raised
	local origin = boss.pos
	local warning = warningCone(state, origin, direction, halfAngle, cfg.Range, ORANGE)
	schedule(state, cfg.WarningTime, function()
		destroyAll(warning)
		Rig.cast(boss.model, "slash")
		local hitPoint = Vector3.new(origin.X + math.sin(direction) * cfg.Range * 0.45, origin.Y, origin.Z + math.cos(direction) * cfg.Range * 0.45)
		impactFx(state, hitPoint, cfg.Range * 0.5, ORANGE)
		for _, f in soldiers(state) do
			if inCone(origin, direction, halfAngle, cfg.Range, f.pos) then
				state.ctx.popNumber(f, state.ctx.damage(f, boss.damage * cfg.Damage))
				f.stunUntil = f.clock + cfg.Stun
			end
		end
		for _, dodger in playersInArena(state) do
			if inCone(origin, direction, halfAngle, cfg.Range, dodger.root.Position) then
				dodger.humanoid:TakeDamage(cfg.PlayerDamage)
			end
		end
	end)
	state.busyUntil = state.clock + cfg.Busy
	if state.enraged then
		state.comboNext = "meteors"
	end
end

local function startShockwave(state: State)
	local cfg = Config.Shockwave
	local boss = state.boss
	Rig.cast(boss.model, "cast")
	-- The wind-up: a pulsing purple glow at the boss's feet (not a damage area: it only says "something comes").
	local y = groundY(state, boss.pos)
	local glow = part(state, Vector3.new(0.25, 7, 7), CFrame.new(boss.pos.X, y + 0.2, boss.pos.Z) * CFrame.Angles(0, 0, math.rad(90)), PURPLE, 0.6, Enum.PartType.Cylinder)
	pulse(glow, 0.6, 0.25)
	schedule(state, cfg.WindUp, function()
		glow:Destroy()
		Rig.cast(boss.model, "jump")
		local origin = Vector3.new(boss.pos.X, groundY(state, boss.pos), boss.pos.Z) -- the ring runs from here
		impactFx(state, origin, 4, PURPLE)
		-- The ring: RING_SEGMENTS blocks on a circle that grows every tick. Only the band it covers hurts.
		local segments: { Part } = {}
		for i = 1, RING_SEGMENTS do
			segments[i] = part(state, Vector3.new(1, 0.7, cfg.Thickness), CFrame.new(origin), PURPLE, 0.1)
		end
		local hit: { [any]: boolean } = {}
		local radius = 1
		addMover(state, function(dt)
			local previous = radius
			radius = math.min(cfg.MaxRadius, radius + cfg.Speed * dt)
			local segmentLength = 2 * math.pi * radius / RING_SEGMENTS + 0.15
			for i, seg in segments do
				local a = (i / RING_SEGMENTS) * math.pi * 2
				seg.Size = Vector3.new(segmentLength, 0.7, cfg.Thickness)
				seg.CFrame = CFrame.new(origin.X + math.sin(a) * radius, origin.Y + 0.35, origin.Z + math.cos(a) * radius) * CFrame.Angles(0, a, 0)
			end
			-- Anything the band crossed since the last tick is hit once; the inside of the ring never hurts.
			local inner, outer = previous - cfg.Thickness / 2, radius + cfg.Thickness / 2
			for _, f in soldiers(state) do
				local d = (flat(f.pos) - flat(origin)).Magnitude
				if not hit[f] and d >= inner and d <= outer then
					hit[f] = true
					state.ctx.popNumber(f, state.ctx.damage(f, boss.damage * cfg.Damage))
				end
			end
			for _, dodger in playersInArena(state) do
				local d = (flat(dodger.root.Position) - flat(origin)).Magnitude
				if not hit[dodger.player] and d >= inner and d <= outer then
					hit[dodger.player] = true -- one pass of the ring, one chance: a jump over it is a clean dodge
					local floorY = groundY(state, dodger.root.Position)
					local height = dodger.root.Position.Y - dodger.root.Size.Y / 2 - floorY
					local jumpState = dodger.humanoid:GetState()
					local airborne = height > cfg.JumpHeight or jumpState == Enum.HumanoidStateType.Jumping or jumpState == Enum.HumanoidStateType.Freefall
					if not airborne then
						dodger.humanoid:TakeDamage(cfg.PlayerDamage)
					end
				end
			end
			if radius >= cfg.MaxRadius then
				for _, seg in segments do
					TweenService:Create(seg, TweenInfo.new(0.3), { Transparency = 1 }):Play()
					Debris:AddItem(seg, 0.35)
				end
				return false
			end
			return true
		end)
	end)
	state.busyUntil = state.clock + cfg.WindUp + 0.5
	if state.enraged then
		state.comboNext = "volley"
	end
end

local function startMeteors(state: State)
	local cfg = Config.Meteors
	local boss = state.boss
	local count = if state.enraged then cfg.EnragedCount else cfg.Count
	local center = state.ctx.plot.arena.center
	local minDistance = cfg.Radius * 2 + cfg.Gap -- between two circle centers: a safe path stays between them
	local chosen: { Vector3 } = {}
	local function accept(p: Vector3): boolean
		if math.abs(p.X - center.X) > 32 or math.abs(p.Z - center.Z) > 30 then
			return false -- off the platform
		end
		for _, other in chosen do
			if (other - p).Magnitude < minDistance then
				return false
			end
		end
		table.insert(chosen, p)
		return true
	end
	-- First where the targets stand (a little off, so running is what saves you), then random spots around.
	for _, p in aimPoints(state) do
		if #chosen >= count then
			break
		end
		accept(p + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3))
	end
	local tries = 0
	while #chosen < count and tries < 60 do
		tries += 1
		local angle = math.random() * math.pi * 2
		local distance = 5 + math.random() * 20
		accept(flat(boss.pos) + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
	end
	Rig.cast(boss.model, "cast")
	for i, p in chosen do
		local y = groundY(state, p)
		local landing = Vector3.new(p.X, y, p.Z)
		local warning = warningCircle(state, landing, cfg.Radius, RED)
		schedule(state, cfg.WarningTime - cfg.FallTime, function()
			-- The meteor: a big crystal falling straight down, with a light.
			local top = landing + UP * 45
			local meteor = part(state, Vector3.new(1.8, 3.4, 1.8), CFrame.new(top) * CFrame.Angles(0, i, 0), PURPLE, 0)
			local light = Instance.new("PointLight")
			light.Color = PURPLE
			light.Range = 12
			light.Brightness = 1.5
			light.Parent = meteor
			local t = 0
			addMover(state, function(dt)
				t = math.min(1, t + dt / cfg.FallTime)
				meteor.CFrame = CFrame.new(top:Lerp(landing + UP * 1.5, t * t)) * CFrame.Angles(0, i + t * 4, 0)
				return t < 1 and meteor.Parent ~= nil
			end)
			schedule(state, cfg.FallTime, function()
				meteor:Destroy()
			end)
		end)
		schedule(state, cfg.WarningTime, function()
			destroyAll(warning)
			impactFx(state, landing, cfg.Radius, PURPLE)
			hitCircle(state, landing, cfg.Radius, cfg.Damage, cfg.PlayerDamage)
		end)
	end
	state.busyUntil = state.clock + cfg.Busy
end

local ATTACKS = { "volley", "slam", "shockwave", "meteors" }

local function startAttack(state: State, name: string)
	state.lastAttack = name
	if name == "volley" then
		startVolley(state)
	elseif name == "slam" then
		startSlam(state)
	elseif name == "shockwave" then
		startShockwave(state)
	else
		startMeteors(state)
	end
	local cooldown = Config.AttackCooldown * (if state.enraged then Config.EnrageCooldownFactor else 1)
	-- A combination (enraged) follows right after the current attack; otherwise the cooldown applies.
	state.nextAttackAt = state.busyUntil + (if state.comboNext then 0.2 else cooldown)
end

local function pickAttack(state: State): string
	local options = {}
	for _, name in ATTACKS do
		if name ~= state.lastAttack then
			table.insert(options, name)
		end
	end
	return options[math.random(#options)]
end

-- ── The interface for BattleService ─────────────────────────────────────────

function RiftKing.new(ctx: Context, boss: any): State
	local fx = Instance.new("Folder")
	fx.Name = "RiftKingFx"
	fx.Parent = ctx.parent
	local state: State = {
		ctx = ctx,
		boss = boss,
		fx = fx,
		alive = true,
		clock = 0,
		busyUntil = 0,
		nextAttackAt = Config.FirstAttackAfter,
		lastAttack = nil,
		comboNext = nil,
		enraged = false,
		lastHp = boss.hp,
		staggerUntil = 0,
		hpSentAt = -1,
		events = {},
		movers = {},
	}
	sendHp(state, true)
	return state
end

-- One battle tick for the boss. Returns true while the boss is busy with an attack (then BattleService skips
-- his walking and his normal hammer hit this tick).
function RiftKing.update(state: State, dt: number): boolean
	if not state.alive then
		return false
	end
	local boss = state.boss
	state.clock += dt
	sendHp(state)

	-- A big hit staggers him; low health enrages him.
	if state.lastHp - boss.hp >= boss.maxHp * Config.StaggerFraction and state.clock >= state.staggerUntil then
		stagger(state)
	end
	state.lastHp = boss.hp
	if not state.enraged and boss.hp <= boss.maxHp * Config.EnrageAt then
		enrage(state)
	end

	-- Due events (impacts, meteors appearing) and the things that move every tick (crystals, the ring).
	while state.alive and state.events[1] and state.events[1].at <= state.clock do
		local event = table.remove(state.events, 1) :: Event
		event.fn()
	end
	for i = #state.movers, 1, -1 do
		local mover = state.movers[i]
		if not mover(dt) then
			table.remove(state.movers, i)
		end
	end

	-- The next special attack, when he is free and there is somebody to aim at.
	if state.clock >= state.busyUntil and state.clock >= state.nextAttackAt and (#soldiers(state) > 0 or #playersInArena(state) > 0) then
		local name = state.comboNext or pickAttack(state)
		state.comboNext = nil
		startAttack(state, name)
	end
	return state.clock < state.busyUntil
end

-- The boss died or the battle ended: every warning, projectile and ring goes away, the health bar hides.
function RiftKing.cleanup(state: State)
	if not state.alive then
		return
	end
	state.alive = false
	table.clear(state.events)
	table.clear(state.movers)
	sendHp(state, true)
	state.fx:Destroy()
end

return RiftKing
