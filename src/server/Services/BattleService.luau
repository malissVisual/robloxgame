--!strict
-- Autobattler in the world. Both sides stand visible on their pads; when the battle starts they
-- teleport into the raised fight arena (FightArena.luau) and fight there at once.
-- The simulation runs on the server on plain data; models are only moved to match positions.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Units = require(Shared.Config.Units)
local Enemies = require(Shared.Config.Enemies)
local Enemy = require(Shared.Enemy)
local Rig = require(Shared.Rig)
local Synergy = require(Shared.Synergy)
local Spells = require(Shared.Config.Spells)
local Waves = require(Shared.Config.Waves)

local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Soldier = require(Shared.Soldier)

local PLAYER_SIDE, ENEMY_SIDE = 1, 2
local UP = Vector3.new(0, 1, 0)
local TELEPORT_OUT = 0.25 -- seconds of the flash on the pads before everybody vanishes
local TELEPORT_IN = 0.45 -- seconds of the flash in the arena before the fight starts

type Fighter = {
	side: number,
	tier: number, -- level
	coinMult: number, -- multiplier of the coins it drops when killed
	boss: boolean, -- a boss (percent-damage spells hurt it less)
	ability: string?, -- a boss's ability: "slam" | "summon" | "volley" | "heal" (from its look)
	abilityTimer: number, -- battle seconds until the ability fires again
	summoned: boolean, -- the Chief already called its reinforcements
	armor: number, -- takes this part less damage (a Tank in the front row)
	clock: number, -- battle time this fighter has lived (seconds; the battle speed counts in it)
	stunUntil: number, -- cannot act until this battle time (a boss slam)
	slowUntil: number, -- Frost Nova: acts at slowFactor speed until this battle time
	slowFactor: number,
	shieldUntil: number, -- Divine Shield: takes shieldReduction less damage until this battle time
	shieldReduction: number,
	passive: string?, -- your soldier's class passive (Units.Passives) ...
	passiveValue: number, -- ... and its strength (doubled when Ascended)
	shots: number, -- attacks made (Power Shot: every 3rd)
	dead: boolean, -- its death was handled (the model falls and fades)
	kind: string?, -- an enemy's kind (Config/Enemies)
	maxHp: number,
	hp: number,
	damage: number,
	range: number,
	cooldown: number,
	speed: number,
	splash: boolean,
	timer: number,
	pos: Vector3, -- on the ground
	spot: Vector3, -- where the fighter stands in the arena when the fight starts
	lift: number,
	color: Color3,
	model: Model,
}

local BattleService = {}

-- The battles that are running right now (for the spells and the battle speed).
export type Battle = {
	fighters: { Fighter },
	parent: Instance,
	numbers: boolean, -- show the damage numbers (a setting)
	speed: () -> number, -- the player's battle speed (1x / 2x), read every tick
	enemyPower: number,
	summonKind: string?, -- the mob a Chief boss summons
	summonTier: number,
	plot: Plots.Plot,
	onSummon: ((Fighter) -> ())?,
}
local active: { [Player]: Battle } = {}

-- The battle a fighter list belongs to (for popNumber's setting).
local numbersOn: { [any]: boolean } = {}

local function makeFighter(side: number, stats: Units.Stats, tier: number, color: Color3, lift: number, coinMult: number, pos: Vector3, model: Model): Fighter
	Soldier.showBar(model, side == PLAYER_SIDE)
	Soldier.setHp(model, 1)
	return {
		side = side,
		tier = tier,
		coinMult = coinMult,
		boss = false,
		ability = nil,
		abilityTimer = 0,
		summoned = false,
		armor = 0,
		clock = 0,
		stunUntil = 0,
		slowUntil = 0,
		slowFactor = 1,
		shieldUntil = 0,
		shieldReduction = 0,
		passive = nil,
		passiveValue = 0,
		shots = 0,
		dead = false,
		kind = nil,
		maxHp = stats.hp,
		hp = stats.hp,
		damage = stats.damage,
		range = stats.range,
		cooldown = stats.cooldown,
		speed = stats.speed,
		splash = stats.splash,
		timer = 0,
		pos = pos,
		spot = pos,
		lift = lift,
		color = color,
		model = model,
	}
end

-- A quick teleport flash: an expanding glowing ball and a light pillar in the fighter's color.
local function teleportFlash(f: Fighter, position: Vector3, parent: Instance)
	local center = position + UP * f.lift
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 1.5
	ball.Color = f.color:Lerp(Color3.new(1, 1, 1), 0.4)
	ball.Material = Enum.Material.Neon
	ball.Transparency = 0.2
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Position = center
	ball.Parent = parent
	TweenService:Create(ball, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 7, Transparency = 1 }):Play()

	local pillar = Instance.new("Part")
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(16, 2.2, 2.2) -- its axis is X: turned up below
	pillar.CFrame = CFrame.new(center + UP * 6) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Color = f.color
	pillar.Material = Enum.Material.Neon
	pillar.Transparency = 0.35
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Parent = parent
	TweenService:Create(pillar, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(16, 0.2, 0.2), Transparency = 1 }):Play()

	Debris:AddItem(ball, 0.6)
	Debris:AddItem(pillar, 0.6)
end

local function face(f: Fighter, target: Vector3)
	local p = f.pos + UP * f.lift
	local look = Vector3.new(target.X, p.Y, target.Z)
	if (look - p).Magnitude > 0.05 then
		f.model:PivotTo(CFrame.lookAt(p, look))
	end
end

local function nearestEnemy(from: Fighter, all: { Fighter }): Fighter?
	local best, bestDist = nil, math.huge
	local taunter: Fighter? = nil
	local taunterDist = math.huge
	for _, other in all do
		if other.side ~= from.side and other.hp > 0 then
			local d = (other.pos - from.pos).Magnitude
			if d < bestDist then
				best, bestDist = other, d
			end
			-- Bulwark: a Tank within its taunt range is attacked first.
			if other.passive == "taunt" and d <= other.passiveValue and d < taunterDist then
				taunter, taunterDist = other, d
			end
		end
	end
	return taunter or best
end

local function effect(from: Fighter, to: Fighter, parent: Instance)
	local a = from.pos + UP * from.lift
	local b = to.pos + UP * to.lift

	local function neon(size: Vector3, cf: CFrame, shape: Enum.PartType?, lifetime: number)
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf
		p.Color = from.color:Lerp(Color3.new(1, 1, 1), 0.3)
		p.Material = Enum.Material.Neon
		if shape then
			p.Shape = shape
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = parent
		Debris:AddItem(p, lifetime)
	end

	if from.side == ENEMY_SIDE then
		-- An enemy's attack is shown: an arrow or a glowing orb flies to the target, a melee hit swings a
		-- slash arc over it; then a small burst.
		local big = if from.boss then 1.6 else 1
		local burst = Instance.new("Part")
		burst.Shape = Enum.PartType.Ball
		burst.Material = Enum.Material.Neon
		burst.Anchored = true
		burst.CanCollide = false
		burst.CanQuery = false
		burst.CanTouch = false
		burst.CastShadow = false
		burst.Position = b
		burst.Transparency = 1
		burst.Size = Vector3.one * 0.8 * big
		burst.Parent = parent
		Debris:AddItem(burst, 0.6)
		local flight = 0
		if from.range > 10 then
			flight = math.clamp((b - a).Magnitude / 110, 0.08, 0.22)
			local shot = Instance.new("Part")
			shot.Anchored = true
			shot.CanCollide = false
			shot.CanQuery = false
			shot.CanTouch = false
			shot.CastShadow = false
			if from.splash then
				shot.Shape = Enum.PartType.Ball
				shot.Size = Vector3.one * 1.3 * big
				shot.Material = Enum.Material.Neon
				shot.Color = Color3.fromRGB(120, 255, 110)
				local light = Instance.new("PointLight")
				light.Color = shot.Color
				light.Range = 9
				light.Parent = shot
				burst.Color = shot.Color
			else
				shot.Size = Vector3.new(0.22, 0.22, 2.6) * big
				shot.Material = Enum.Material.Wood
				shot.Color = Color3.fromRGB(150, 105, 60)
				burst.Color = Color3.fromRGB(255, 235, 190)
			end
			local hand = a + UP * 0.6
			shot.CFrame = CFrame.lookAt(hand, b)
			shot.Parent = parent
			TweenService:Create(shot, TweenInfo.new(flight, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(b, b + (b - hand)) }):Play()
			Debris:AddItem(shot, flight + 0.02)
		else
			-- A slash arc sweeping over the target.
			burst.Color = Color3.fromRGB(255, 220, 170)
			local facing = CFrame.lookAt(b, Vector3.new(a.X, b.Y, a.Z))
			local arc = Instance.new("Part")
			arc.Size = Vector3.new(4.2 * big, 0.12, 0.7 * big)
			arc.Material = Enum.Material.Neon
			arc.Color = Color3.fromRGB(255, 240, 215)
			arc.Transparency = 0.15
			arc.Anchored = true
			arc.CanCollide = false
			arc.CanQuery = false
			arc.CanTouch = false
			arc.CastShadow = false
			arc.CFrame = facing * CFrame.new(0, 0.4, -1.2) * CFrame.Angles(0, 0, math.rad(55))
			arc.Parent = parent
			TweenService:Create(arc, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = facing * CFrame.new(0, 0.4, -1.2) * CFrame.Angles(0, 0, math.rad(-55)), Transparency = 1, Size = Vector3.new(5 * big, 0.05, 0.3 * big) }):Play()
			Debris:AddItem(arc, 0.25)
		end
		local grow = if from.splash then 5 else 2.6
		task.delay(flight, function()
			burst.Transparency = 0.2
			TweenService:Create(burst, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * grow * big, Transparency = 1 }):Play()
		end)
		return
	end

	if from.range > 10 then
		neon(Vector3.new(0.3, 0.3, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), nil, 0.1)
	end
	neon(Vector3.one * 1.6, CFrame.new(b), Enum.PartType.Ball, 0.12)
end

-- A floating damage number above the target (white on enemies, red on your soldiers).
local numbersThisTick = 0
local function popNumber(parent: Instance, target: Fighter, amount: number, color: Color3?)
	if numbersOn[parent] == false or numbersThisTick >= 14 then
		return -- a busy fight: not every hit needs a number
	end
	numbersThisTick += 1
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one * 0.2
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = target.pos + UP * (target.lift + 2.5) + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
	anchor.Parent = parent
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(80, 30)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextSize = 20
	text.TextColor3 = color or (if target.side == ENEMY_SIDE then Color3.fromRGB(255, 240, 200) else Color3.fromRGB(255, 110, 100))
	text.TextStrokeColor3 = Color3.new(0, 0, 0)
	text.TextStrokeTransparency = 0.3
	text.Text = tostring(math.max(1, math.floor(amount + 0.5)))
	text.Parent = billboard
	TweenService:Create(billboard, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(text, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.8)
end

-- Returns the damage really taken (0 when blocked).
local function damage(target: Fighter, amount: number): number
	if target.passive == "block" and math.random() < target.passiveValue then
		return 0 -- Shield Wall: the hit is blocked
	end
	if target.shieldUntil > target.clock then
		amount *= 1 - target.shieldReduction -- Divine Shield
	end
	amount *= 1 - target.armor
	target.hp -= amount
	Soldier.setHp(target.model, target.hp / target.maxHp)
	return amount
end

-- The damage of one attack of `f` with its passives (Power Shot, Deadeye, Bloodlust, Banner).
local function attackDamage(f: Fighter, fighters: { Fighter }): number
	local amount = f.damage
	if f.passive == "volley" then
		f.shots += 1
		if f.shots % 3 == 0 then
			amount *= f.passiveValue
		end
	elseif f.passive == "crit" and math.random() < f.passiveValue then
		amount *= 2
	elseif f.passive == "rage" then
		amount *= 1 + f.passiveValue * (1 - math.clamp(f.hp / f.maxHp, 0, 1))
	end
	-- Banner: every Soldier with the inspire passive within 10 studs gives its bonus.
	if f.side == PLAYER_SIDE then
		for _, other in fighters do
			if other ~= f and other.side == PLAYER_SIDE and other.hp > 0 and other.passive == "inspire" and (other.pos - f.pos).Magnitude <= 10 then
				amount *= 1 + other.passiveValue
			end
		end
	end
	return amount
end

local bossAbility: (Battle, Fighter, number) -> () = function() end -- defined below (needs the spell effects)

local function step(battle: Battle, dt: number, onEnemyDeath: (Fighter) -> ())
	local fighters, effects = battle.fighters, battle.parent
	numbersThisTick = 0
	for _, f in fighters do
		if f.hp <= 0 then
			continue
		end
		f.clock += dt
		if f.stunUntil > f.clock then
			continue -- stunned by a boss slam
		end
		if f.boss and f.ability then
			f.abilityTimer -= dt
			if f.abilityTimer <= 0 then
				bossAbility(battle, f, dt)
			end
		end
		local rate = if f.slowUntil > f.clock then f.slowFactor else 1 -- Frost Nova slows down movement and attacks
		local target = nearestEnemy(f, fighters)
		if not target then
			continue
		end
		local delta = target.pos - f.pos
		local dist = delta.Magnitude
		if dist <= f.range + 1 then
			f.timer -= dt * rate
			if f.timer <= 0 then
				f.timer = f.cooldown
				local amount = attackDamage(f, fighters)
				local taken = damage(target, amount)
				popNumber(effects, target, taken)
				effect(f, target, effects)
				Rig.attack(f.model, battle.speed())
				-- Splash: the Mage's Arcane Burst (its passive value) or an enemy with splash.
				local splashFraction = if f.passive == "splash" then f.passiveValue elseif f.splash then Balance.SplashFraction else 0
				if splashFraction > 0 then
					for _, other in fighters do
						if other ~= target and other.side == target.side and other.hp > 0 then
							if (other.pos - target.pos).Magnitude <= Balance.SplashRadius then
								popNumber(effects, other, damage(other, amount * splashFraction))
							end
						end
					end
				end
			end
		else
			f.pos += delta.Unit * math.min(f.speed * dt * rate, dist - f.range)
		end
		Rig.setMoving(f.model, dist > f.range + 1) -- run to the target, stand while hitting
		face(f, target.pos)
	end
	for _, f in fighters do
		if f.hp <= 0 and not f.dead then
			f.dead = true
			-- An R15 fighter falls and fades (Rig.die); a block model just vanishes.
			if not Rig.die(f.model) then
				f.model:Destroy()
			end
			if f.side == ENEMY_SIDE then
				onEnemyDeath(f) -- the caller pays out the coins for the kill
			end
		end
	end
end

local function countAlive(fighters: { Fighter }, side: number): number
	local n = 0
	for _, f in fighters do
		if f.side == side and f.hp > 0 then
			n += 1
		end
	end
	return n
end

export type Options = {
	enemyPower: number, -- difficulty (and elite) multiplier of the enemies' HP and damage
	elite: boolean, -- an elite wave: golden enemies
	summonKind: string?, -- the mob a Chief boss summons (the phase's newest mob)
	summonTier: number,
}

-- Starts the battle. `plot.models` must be rendered from the current squad.
-- At the end sets `profile.battling = false` and calls onFinished.
-- `onKill(level, position, coinMult)` is called for every dead enemy (coins are paid per kill). The caller
-- handles the outcome (progress, drops) in `onFinished`.
function BattleService.start(player: Player, profile: PlayerData.Profile, plot: Plots.Plot, options: Options, onKill: (level: number, position: Vector3, coinMult: number) -> (), onFinished: (won: boolean) -> ())
	local fighters: { Fighter } = {}
	local enemyPower = options.enemyPower

	-- Only the squad fights; the merge board is just storage.
	local synergy = Synergy.compute(profile.squad)
	for i = 1, Balance.SquadSize do
		local id = Balance.SquadOffset + i
		local cell = profile.squad[i]
		local model = plot.models[id]
		if cell and model then
			local fighter = makeFighter(PLAYER_SIDE, Units.stats(cell.class, cell.tier, cell.ascended), cell.tier, Units.Classes[cell.class].color, Soldier.lift(cell.tier, cell.ascended), 1, Plots.slotGround(plot, id), model)
			-- The class passive (doubled for an Ascended soldier).
			local passiveId = Units.Classes[cell.class].passive
			fighter.passive = passiveId
			fighter.passiveValue = Units.Passives[passiveId].value * (if cell.ascended then 2 else 1)
			fighter.spot = plot.arena.spot(PLAYER_SIDE, i, Balance.SquadSize)
			-- Tactics: the front row (nearest to the enemies) has more HP, the back row hits harder;
			-- the squad's synergies make everybody stronger.
			local rowIndex = (i - 1) // Balance.SquadColumns
			local front = rowIndex == Balance.SquadSize // Balance.SquadColumns - 1 -- the row nearest to the enemies
			local back = rowIndex == 0 -- (the rows between have no row bonus)
			local power = 1
			-- The pad decides more: the middle column has more HP, the two outer columns (the lanes on the
			-- left / right) hit harder; ranged soldiers in the back row see further, a Tank in front takes less.
			local middle = (i - 1) % Balance.SquadColumns == 1
			fighter.maxHp *= power * synergy.hp * (if front then 1 + Balance.FrontRowHp else 1) * (if middle then 1 + Balance.CenterHp else 1)
			fighter.hp = fighter.maxHp
			fighter.damage *= power * synergy.damage * (if back then 1 + Balance.BackRowDamage else 1) * (if middle then 1 else 1 + Balance.FlankDamage)
			if Synergy.Roles[cell.class] == "Ranged" and back then
				fighter.range *= 1 + Balance.BackRangedRange
			end
			if cell.class == "Tank" and front then
				fighter.armor = Balance.FrontTankArmor
			end
			table.insert(fighters, fighter)
		end
	end

	-- The enemies are already standing in the wave preview (Plots.showEnemies).
	for i, e in plot.enemies do
		local pos = Plots.enemyGround(plot, i, #plot.enemies)
		local fighter = makeFighter(ENEMY_SIDE, Enemies.stats(e.kind, e.tier), e.tier, Enemies.Kinds[e.kind].color, Enemy.lift(e.kind, e.tier), Enemies.Kinds[e.kind].coins, pos, plot.enemyModels[i])
		fighter.spot = plot.arena.spot(ENEMY_SIDE, i, #plot.enemies)
		fighter.kind = e.kind
		fighter.boss = Enemies.Kinds[e.kind].boss == true
		if fighter.boss then
			-- The boss's look decides its ability.
			local look = Enemies.Kinds[e.kind].look
			fighter.ability = if look == "GoblinBrute" then "slam" elseif look == "GoblinChief" then "summon" elseif look == "GoblinArcher" then "volley" else "heal"
			fighter.abilityTimer = if fighter.ability == "slam" then Balance.BossSlamEvery elseif fighter.ability == "volley" then Balance.BossVolleyEvery elseif fighter.ability == "heal" then Balance.BossHealEvery else 1
		end
		fighter.maxHp *= enemyPower
		fighter.hp = fighter.maxHp
		fighter.damage *= enemyPower
		if options.elite then
			-- Elite enemies glow golden.
			local glow = Instance.new("Highlight")
			glow.FillColor = Color3.fromRGB(255, 200, 60)
			glow.FillTransparency = 0.7
			glow.OutlineColor = Color3.fromRGB(255, 220, 120)
			glow.OutlineTransparency = 0
			glow.Parent = fighter.model
		end
		table.insert(fighters, fighter)
	end

	local battle: Battle = {
		fighters = fighters,
		parent = plot.folder,
		numbers = profile.settings.numbers ~= false,
		speed = function()
			return profile.battleSpeed
		end,
		enemyPower = enemyPower,
		summonKind = options.summonKind,
		summonTier = options.summonTier,
		plot = plot,
		onSummon = nil,
	}
	numbersOn[plot.folder] = battle.numbers
	active[player] = battle

	task.spawn(function()
		-- Phase 1: everybody teleports from the pads into the arena (a flash on both ends) and the
		-- fight starts right away.
		if not (player.Parent and plot.folder.Parent) then
			active[player] = nil
			numbersOn[plot.folder] = nil
			return
		end
		for _, f in fighters do
			teleportFlash(f, f.pos, plot.folder)
		end
		task.wait(TELEPORT_OUT)
		for _, f in fighters do
			f.pos = f.spot
			face(f, f.spot + Vector3.new(0, 0, if f.side == PLAYER_SIDE then 10 else -10)) -- facing the other side
			teleportFlash(f, f.spot, plot.folder)
		end
		task.wait(TELEPORT_IN)

		-- Phase 2: the fight. The battle speed (1x / 2x) stretches every tick.
		local elapsed = 0
		while player.Parent and plot.folder.Parent and elapsed < Balance.BattleTimeLimit do
			task.wait(Balance.BattleTickRate)
			numbersOn[plot.folder] = profile.settings.numbers ~= false
			local dt = Balance.BattleTickRate * battle.speed()
			elapsed += dt
			step(battle, dt, function(enemy)
				onKill(enemy.tier, enemy.pos, enemy.coinMult)
			end)
			if countAlive(fighters, PLAYER_SIDE) == 0 or countAlive(fighters, ENEMY_SIDE) == 0 then
				break
			end
		end

		local won = countAlive(fighters, ENEMY_SIDE) == 0 and countAlive(fighters, PLAYER_SIDE) > 0
		active[player] = nil
		numbersOn[plot.folder] = nil
		profile.battling = false

		-- Remove leftover enemies and pads; refresh builds the preview of the next (or the same) wave.
		if plot.folder.Parent then
			Plots.clearEnemies(plot)
			Plots.resetSquad(plot) -- the battle moved / destroyed the squad's models
		end

		if player.Parent and plot.folder.Parent then
			onFinished(won)
		end
	end)
end

-- ── Spell effects ───────────────────────────────────────────────────────────

local function newPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): Part
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
	p.Parent = parent
	return p
end

-- Tweens a part to `goal` and removes it afterwards.
local function fade(part: BasePart, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	TweenService:Create(part, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(part, duration + 0.1)
end

-- A flat ring that expands on the floor and fades (a shockwave).
local function groundRing(parent: Instance, position: Vector3, color: Color3, radius: number, duration: number)
	local ring = newPart(parent, Vector3.new(0.3, 1, 1), CFrame.new(position + UP * 0.3) * CFrame.Angles(0, 0, math.rad(90)), color, 0.2, Enum.PartType.Cylinder)
	fade(ring, duration, { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 })
end

-- Small glowing bits that fly out (and up) from a point and fade.
local function sparks(parent: Instance, position: Vector3, color: Color3, count: number, spread: number, height: number)
	for _ = 1, count do
		local angle = math.random() * math.pi * 2
		local distance = spread * (0.3 + math.random() * 0.7)
		local size = 0.4 + math.random() * 0.5
		local spark = newPart(parent, Vector3.one * size, CFrame.new(position + UP), color, 0, Enum.PartType.Ball)
		fade(spark, 0.5 + math.random() * 0.4, {
			Position = position + Vector3.new(math.cos(angle) * distance, height * (0.4 + math.random() * 0.6), math.sin(angle) * distance),
			Transparency = 1,
			Size = Vector3.one * 0.1,
		})
	end
end

-- A jagged lightning bolt from `top` down to `bottom`.
local function lightning(parent: Instance, top: Vector3, bottom: Vector3, color: Color3, width: number)
	local points = { top }
	local segments = 6
	for i = 1, segments - 1 do
		points[#points + 1] = top:Lerp(bottom, i / segments) + Vector3.new((math.random() - 0.5) * 5, 0, (math.random() - 0.5) * 5)
	end
	points[#points + 1] = bottom
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		local segment = newPart(parent, Vector3.new(width, width, length), CFrame.lookAt((a + b) / 2, b), color, 0)
		fade(segment, 0.35, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, length) })
	end
end

-- Auto aim: the enemy whose surroundings (within `radius`) hold the most enemies; nil when none is alive.
local function bestEnemyCenter(fighters: { Fighter }, radius: number): Vector3?
	local best, bestScore = nil, 0
	for _, center in fighters do
		if center.side == ENEMY_SIDE and center.hp > 0 then
			local score = 0
			for _, other in fighters do
				if other.side == ENEMY_SIDE and other.hp > 0 and (Vector3.new(other.pos.X, 0, other.pos.Z) - Vector3.new(center.pos.X, 0, center.pos.Z)).Magnitude <= radius then
					score += 1 + other.hp / (other.maxHp * 1000) -- more enemies first, then the healthier group
				end
			end
			if score > bestScore then
				best, bestScore = center.pos, score
			end
		end
	end
	return best
end

-- Auto aim for the heal: where the most HP is missing among your soldiers (nil when nobody is hurt).
local function bestHealCenter(fighters: { Fighter }, radius: number): Vector3?
	local best, bestMissing = nil, 0.15
	for _, center in fighters do
		if center.side == PLAYER_SIDE and center.hp > 0 then
			local missing = 0
			for _, other in fighters do
				if other.side == PLAYER_SIDE and other.hp > 0 and (Vector3.new(other.pos.X, 0, other.pos.Z) - Vector3.new(center.pos.X, 0, center.pos.Z)).Magnitude <= radius then
					missing += 1 - other.hp / other.maxHp
				end
			end
			if missing > bestMissing then
				best, bestMissing = center.pos, missing
			end
		end
	end
	return best
end

-- A colored glow on a fighter for a while (frost, shield).
local function tint(f: Fighter, color: Color3, duration: number)
	if not f.model.Parent then
		return
	end
	local glow = Instance.new("Highlight")
	glow.Adornee = f.model
	glow.FillColor = color
	glow.FillTransparency = 0.55
	glow.OutlineColor = color
	glow.OutlineTransparency = 0.2
	glow.Parent = f.model
	Debris:AddItem(glow, duration)
end

-- Auto aim for the shield: where the most of your soldiers stand together.
local function bestAllyCenter(fighters: { Fighter }, radius: number): Vector3?
	local best, bestCount = nil, 0
	for _, center in fighters do
		if center.side == PLAYER_SIDE and center.hp > 0 then
			local count = 0
			for _, other in fighters do
				if other.side == PLAYER_SIDE and other.hp > 0 and (Vector3.new(other.pos.X, 0, other.pos.Z) - Vector3.new(center.pos.X, 0, center.pos.Z)).Magnitude <= radius then
					count += 1
				end
			end
			if count > bestCount then
				best, bestCount = center.pos, count
			end
		end
	end
	return best
end

local function bossFactor(f: Fighter): number
	return if f.boss then Balance.SpellBossFactor else 1
end

-- SMITE: a jagged lightning bolt from the sky on every enemy for a part of its max HP.
local function smiteSpell(battle: { fighters: { Fighter }, parent: Instance }, def: Spells.Def)
	numbersThisTick = 0
	local bolt = def.color
	for _, f in battle.fighters do
		if f.side == ENEMY_SIDE and f.hp > 0 then
			local amount = f.maxHp * (def.damage or 0) * bossFactor(f)
			damage(f, amount)
			popNumber(battle.parent, f, amount)
			lightning(battle.parent, f.pos + UP * 45, f.pos + UP * 0.5, bolt, 1.1)
			lightning(battle.parent, f.pos + UP * 45 + Vector3.new(3, 0, 2), f.pos + UP * 0.5, Color3.new(1, 1, 1), 0.4)
			groundRing(battle.parent, f.pos, bolt, 5, 0.4)
			sparks(battle.parent, f.pos, bolt, 8, 4, 5)
		end
	end
end

local FALL_TIME = 0.55 -- seconds the meteor needs to fall

-- METEOR: a telegraph on the floor, a burning fireball falls, then a shockwave and damage.
local function meteor(player: Player, battle: { fighters: { Fighter }, parent: Instance }, position: Vector3, radius: number, damageFraction: number)
	local parent = battle.parent
	local orange = Color3.fromRGB(255, 140, 50)

	-- The warning disc on the floor grows more solid while the meteor falls.
	local disc = newPart(parent, Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(position + UP * 0.2) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 70, 50), 0.8, Enum.PartType.Cylinder)
	fade(disc, FALL_TIME, { Transparency = 0.4 }, Enum.EasingStyle.Linear)

	-- The fireball comes down at an angle, growing, with fire on it.
	local ball = newPart(parent, Vector3.one * 3, CFrame.new(position + Vector3.new(-16, 55, -10)), orange, 0.05, Enum.PartType.Ball)
	local fire = Instance.new("Fire")
	fire.Size = 14
	fire.Heat = 10
	fire.Color = Color3.fromRGB(255, 160, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = ball
	fade(ball, FALL_TIME, { Position = position + UP * 1.5, Size = Vector3.one * 6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	task.delay(FALL_TIME, function()
		if active[player] ~= battle then
			return -- the battle is over
		end
		numbersThisTick = 0
		local flat = Vector3.new(position.X, 0, position.Z)

		-- Impact: two shockwaves, a flash, sparks and a scorch mark that fades slowly.
		groundRing(parent, position, orange, radius, 0.5)
		groundRing(parent, position, Color3.fromRGB(255, 230, 150), radius * 0.6, 0.35)
		local flash = newPart(parent, Vector3.one * 2, CFrame.new(position + UP * 1.5), Color3.fromRGB(255, 220, 140), 0.2, Enum.PartType.Ball)
		fade(flash, 0.45, { Size = Vector3.one * radius * 1.6, Transparency = 1 })
		sparks(parent, position, orange, 24, radius, 9)
		local scorch = newPart(parent, Vector3.new(0.15, radius * 1.4, radius * 1.4), CFrame.new(position + UP * 0.15) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 25, 20), 0.3, Enum.PartType.Cylinder)
		scorch.Material = Enum.Material.SmoothPlastic
		fade(scorch, 1.6, { Transparency = 1 }, Enum.EasingStyle.Linear)

		for _, f in battle.fighters do
			if f.side == ENEMY_SIDE and f.hp > 0 and (Vector3.new(f.pos.X, 0, f.pos.Z) - flat).Magnitude <= radius then
				local amount = f.maxHp * damageFraction * bossFactor(f)
				damage(f, amount)
				popNumber(parent, f, amount)
			end
		end
	end)
end

-- HEAL: green rings and a light column on the floor, and sparks rising from every healed soldier.
local function healSpell(battle: { fighters: { Fighter }, parent: Instance }, position: Vector3, def: Spells.Def)
	local radius = def.radius or 10
	local parent = battle.parent
	local green = def.color
	numbersThisTick = 0
	local flat = Vector3.new(position.X, 0, position.Z)

	groundRing(parent, position, green, radius, 0.7)
	task.delay(0.15, function()
		groundRing(parent, position, Color3.fromRGB(200, 255, 210), radius * 0.7, 0.55)
	end)
	local column = newPart(parent, Vector3.new(14, radius * 1.4, radius * 1.4), CFrame.new(position + UP * 7) * CFrame.Angles(0, 0, math.rad(90)), green, 0.6, Enum.PartType.Cylinder)
	fade(column, 0.8, { Transparency = 1, Size = Vector3.new(16, radius * 1.1, radius * 1.1) })

	for _, f in battle.fighters do
		if f.side == PLAYER_SIDE and f.hp > 0 and (Vector3.new(f.pos.X, 0, f.pos.Z) - flat).Magnitude <= radius then
			local amount = f.maxHp * (def.heal or 0)
			f.hp = math.min(f.maxHp, f.hp + amount)
			Soldier.setHp(f.model, f.hp / f.maxHp)
			popNumber(parent, f, amount, Color3.fromRGB(120, 255, 150))
			groundRing(parent, f.pos, green, 3, 0.5)
			sparks(parent, f.pos, green, 6, 1.5, 6)
		end
	end
end

-- FROST NOVA: ice on the floor, damage and a slow (they act at half speed) for the enemies around the target.
local function frostSpell(battle: { fighters: { Fighter }, parent: Instance }, position: Vector3, def: Spells.Def)
	local radius = def.radius or 10
	local parent = battle.parent
	local ice = def.color
	numbersThisTick = 0
	local flat = Vector3.new(position.X, 0, position.Z)

	groundRing(parent, position, ice, radius, 0.7)
	task.delay(0.12, function()
		groundRing(parent, position, Color3.new(0.9, 0.97, 1), radius * 0.65, 0.5)
	end)
	sparks(parent, position, Color3.new(0.9, 0.97, 1), 20, radius, 7)
	local column = newPart(parent, Vector3.new(12, radius * 1.3, radius * 1.3), CFrame.new(position + UP * 6) * CFrame.Angles(0, 0, math.rad(90)), ice, 0.55, Enum.PartType.Cylinder)
	fade(column, 0.7, { Transparency = 1, Size = Vector3.new(14, radius * 0.9, radius * 0.9) })

	for _, f in battle.fighters do
		if f.side == ENEMY_SIDE and f.hp > 0 and (Vector3.new(f.pos.X, 0, f.pos.Z) - flat).Magnitude <= radius then
			local amount = f.maxHp * (def.damage or 0) * bossFactor(f)
			damage(f, amount)
			popNumber(parent, f, amount, ice)
			f.slowUntil = f.clock + (def.slowTime or 4)
			f.slowFactor = def.slow or 0.5
			tint(f, ice, def.slowTime or 4)
			sparks(parent, f.pos, Color3.new(0.9, 0.97, 1), 6, 2, 4)
		end
	end
end

-- DIVINE SHIELD: golden rings, and the soldiers around the target take much less damage for a while.
local function shieldSpell(battle: { fighters: { Fighter }, parent: Instance }, position: Vector3, def: Spells.Def)
	local radius = def.radius or 10
	local parent = battle.parent
	local gold = def.color
	local flat = Vector3.new(position.X, 0, position.Z)

	groundRing(parent, position, gold, radius, 0.7)
	task.delay(0.15, function()
		groundRing(parent, position, Color3.fromRGB(255, 245, 200), radius * 0.7, 0.55)
	end)
	local column = newPart(parent, Vector3.new(14, radius * 1.4, radius * 1.4), CFrame.new(position + UP * 7) * CFrame.Angles(0, 0, math.rad(90)), gold, 0.6, Enum.PartType.Cylinder)
	fade(column, 0.8, { Transparency = 1, Size = Vector3.new(16, radius * 1.1, radius * 1.1) })

	for _, f in battle.fighters do
		if f.side == PLAYER_SIDE and f.hp > 0 and (Vector3.new(f.pos.X, 0, f.pos.Z) - flat).Magnitude <= radius then
			f.shieldUntil = f.clock + (def.shieldTime or 4)
			f.shieldReduction = def.reduction or 0.85
			tint(f, gold, def.shieldTime or 4)
			groundRing(parent, f.pos, gold, 3, 0.5)
			sparks(parent, f.pos, gold, 6, 1.5, 6)
		end
	end
end

-- ARMAGEDDON: several meteors, one after another, each on a random enemy.
local function armageddon(player: Player, battle: { fighters: { Fighter }, parent: Instance }, def: Spells.Def)
	for i = 1, def.strikes or 6 do
		task.delay((i - 1) * 0.4, function()
			if active[player] ~= battle then
				return
			end
			local alive: { Fighter } = {}
			for _, f in battle.fighters do
				if f.side == ENEMY_SIDE and f.hp > 0 then
					table.insert(alive, f)
				end
			end
			if #alive == 0 then
				return
			end
			local target = alive[math.random(1, #alive)].pos + Vector3.new((math.random() - 0.5) * 4, 0, (math.random() - 0.5) * 4)
			meteor(player, battle, target, def.radius or 7, def.damage or 0.1)
		end)
	end
end

-- Casts the spell `id` (Config/Spells.luau). `position` is the point on the arena floor the player aimed
-- at (the caller checked it is in range), or nil for AUTO AIM: the damage spells pick the biggest group of
-- enemies, the heal the group of your soldiers that lacks the most HP, the shield the biggest group of
-- your soldiers; the global spells need no aim. Returns (false, reason) when nothing happened (then the
-- spell is not used up), (false, nil) when there is no battle running.
function BattleService.spell(player: Player, id: string, position: Vector3?): (boolean, string?)
	local battle = active[player]
	local def = Spells.Defs[id]
	if not battle or not def then
		return false, nil
	end
	if id == "meteor" then
		local target = position or bestEnemyCenter(battle.fighters, def.radius or 9)
		if not target then
			return false, "No enemies to hit"
		end
		meteor(player, battle, target, def.radius or 9, def.damage or 0.12)
	elseif id == "heal" then
		local target = position or bestHealCenter(battle.fighters, def.radius or 10)
		if not target then
			return false, "Nobody needs healing"
		end
		healSpell(battle, target, def)
	elseif id == "smite" then
		smiteSpell(battle, def)
	elseif id == "frost" then
		local target = position or bestEnemyCenter(battle.fighters, def.radius or 10)
		if not target then
			return false, "No enemies to hit"
		end
		frostSpell(battle, target, def)
	elseif id == "shield" then
		local target = position or bestAllyCenter(battle.fighters, def.radius or 10)
		if not target then
			return false, "No characters to protect"
		end
		shieldSpell(battle, target, def)
	elseif id == "armageddon" then
		armageddon(player, battle, def)
	else
		return false, nil
	end
	return true, nil
end

-- ── Boss abilities ──────────────────────────────────────────────────────────
-- Every boss has one, decided by its look: a Brute SLAMS (damage + stun around it), a Chief SUMMONS mobs
-- at half HP, an Archer fires a VOLLEY at every soldier in range, a Shaman HEALS its whole wave.
bossAbility = function(battle: Battle, boss: Fighter, dt: number)
	local parent = battle.parent
	if boss.ability == "slam" then
		boss.abilityTimer = Balance.BossSlamEvery
		Rig.cast(boss.model, "jump")
		groundRing(parent, boss.pos, Color3.fromRGB(255, 120, 60), Balance.BossSlamRadius, 0.5)
		sparks(parent, boss.pos, Color3.fromRGB(200, 120, 60), 16, Balance.BossSlamRadius, 5)
		for _, f in battle.fighters do
			if f.side == PLAYER_SIDE and f.hp > 0 and (f.pos - boss.pos).Magnitude <= Balance.BossSlamRadius then
				local taken = damage(f, boss.damage * Balance.BossSlamDamage)
				popNumber(parent, f, taken)
				f.stunUntil = f.clock + Balance.BossSlamStun
				tint(f, Color3.fromRGB(255, 200, 90), Balance.BossSlamStun)
			end
		end
	elseif boss.ability == "volley" then
		boss.abilityTimer = Balance.BossVolleyEvery
		Rig.cast(boss.model, "lunge")
		for _, f in battle.fighters do
			if f.side == PLAYER_SIDE and f.hp > 0 and (f.pos - boss.pos).Magnitude <= boss.range + 4 then
				local taken = damage(f, boss.damage * Balance.BossVolleyDamage)
				popNumber(parent, f, taken)
				effect(boss, f, parent)
			end
		end
	elseif boss.ability == "heal" then
		boss.abilityTimer = Balance.BossHealEvery
		Rig.cast(boss.model, "cast")
		groundRing(parent, boss.pos, Color3.fromRGB(120, 255, 140), 12, 0.6)
		for _, f in battle.fighters do
			if f.side == ENEMY_SIDE and f.hp > 0 then
				local amount = f.maxHp * Balance.BossHealFraction
				f.hp = math.min(f.maxHp, f.hp + amount)
				Soldier.setHp(f.model, f.hp / f.maxHp)
				popNumber(parent, f, amount, Color3.fromRGB(120, 255, 150))
			end
		end
	elseif boss.ability == "summon" then
		boss.abilityTimer = 0.5 -- checked often: it fires once, at half HP
		if boss.summoned or boss.hp > boss.maxHp * Balance.BossSummonAt or not battle.summonKind then
			return
		end
		boss.summoned = true
		Rig.cast(boss.model, "cast")
		local kind = battle.summonKind :: string
		groundRing(parent, boss.pos, Color3.fromRGB(200, 90, 255), 8, 0.6)
		for i = 1, Balance.BossSummonCount do
			local angle = math.rad(60 + (i - 1) * 60)
			local pos = boss.pos + Vector3.new(math.cos(angle) * 5, 0, math.sin(angle) * 5)
			local model = Enemy.build(kind, battle.summonTier)
			model:PivotTo(CFrame.new(pos + UP * Enemy.lift(kind, battle.summonTier)))
			model.Parent = parent
			local fighter = makeFighter(ENEMY_SIDE, Enemies.stats(kind, battle.summonTier), battle.summonTier, Enemies.Kinds[kind].color, Enemy.lift(kind, battle.summonTier), Enemies.Kinds[kind].coins, pos, model)
			fighter.kind = kind
			fighter.maxHp *= battle.enemyPower
			fighter.hp = fighter.maxHp
			fighter.damage *= battle.enemyPower
			table.insert(battle.fighters, fighter)
			teleportFlash(fighter, pos, parent)
		end
	end
end

return BattleService
