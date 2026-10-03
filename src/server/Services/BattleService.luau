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
local MageUpgrades = require(Shared.MageUpgrades)
local MageTree = require(Shared.Config.MageTree) -- the Mage's merge-level tree: its passives are applied here
local Waves = require(Shared.Config.Waves)
local Net = require(Shared.Net)

local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local RiftKing = require(script.Parent.RiftKing)
local MageBrain = require(script.Parent.MageBrain)
local BattleFx = require(script.Parent.BattleFx)
local EnemyBrain = require(script.Parent.EnemyBrain)
local WaveMutators = require(script.Parent.WaveMutators)
local BattleSpells = require(script.Parent.BattleSpells) -- the player's spells, reinforcements, signatures, affixes, combo
local SpellConfig = require(Shared.Config.BattleSpells)
local Soldier = require(Shared.Soldier)
local Wizards = require(Shared.Config.Wizards) -- the wizard types: rarity stats and battle traits
local MageConfig = require(Shared.Config.MageConfig)

local PLAYER_SIDE, ENEMY_SIDE = 1, 2
local UP = Vector3.new(0, 1, 0)

type Fighter = {
	side: number,
	tier: number, -- level
	coinMult: number, -- multiplier of the coins it drops when killed
	boss: boolean, -- a boss (percent-damage spells hurt it less)
	ability: string?, -- a boss's ability: "slam" | "summon" | "volley" | "heal" (from its archetype), "riftking" = the final boss (RiftKing.luau)
	abilityTimer: number, -- battle seconds until the ability fires again
	summoned: boolean, -- the Chief already called its reinforcements
	armor: number, -- takes this part less damage (0 for everybody right now)
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
	brain: any?, -- a Mage's battle AI (MageBrain.luau): it takes over the fighter's movement and attacks
	ai: any?, -- an enemy's brain (EnemyBrain.luau): update(dt) → true handles the tick; onDamaged / onEvent / interrupt / destroy
	-- Events (see `emit` in the Battle): who hit this fighter last and when, and the edges already announced.
	lastHitBy: Fighter?,
	lastHitAt: number,
	killEmitted: boolean, -- "kill" / "allyDown" was emitted once
	hurtFlagged: boolean, -- "allyHurt" (under 40 % HP) was emitted once
	-- Temporary modifiers written by brains, boss abilities and wave twists.
	haste: number, -- multiplies the attack rate AND the movement (war cry, frenzy, enrage, swift)
	buffDamage: number, -- additive damage fraction while buffUntil > clock (frenzy, rally, gang up)
	buffUntil: number,
	hexFactor: number, -- multiplies the damage dealt while hexUntil > clock (a shaman's hex)
	hexUntil: number,
	taunt: number?, -- enemies of the other side within this many studs attack this fighter first (the Brute "wall")
	shieldHp: number, -- a bubble drained before hp in damage() (warded twist, wards)
	champion: boolean, -- the wave's champion (twist): the Mage prefers it
	boltStyle: string?, -- "execute" → the Mage's next fireball is bigger with a white core (effect() resets it)
	boltTint: Color3?, -- the Mage's next fireball color override (effect() resets it)
	baseLift: number, -- the lift at creation (the Overcharge hover restores it)
	tilt: number, -- radians of forward lean applied by face() (the Mage's glide; 0 for everybody else)
	bonusCoins: number, -- extra coin multiplier at death (treasure goblin, bounty)
	noReward: boolean, -- its death pays no coins (the treasure goblin escaped)
	-- The Mage's merge-level tree (Config/MageTree.luau): a mage's level and the state of its passives.
	mageLevel: number?, -- set for your mages only
	ascended: boolean?,
	hitCount: number, -- hits dealt (Focus: every 4th is doubled)
	hitStreak: number, -- hits in a row (Overload: 5 charge the next bolt) ...
	overloaded: boolean, -- ... which explodes into an area
	barrierUsed: boolean, -- the Emergency Barrier fired (once per battle)
	auraTimer: number, -- Healing Aura: seconds since its last pulse
	burnUntil: number, -- on fire (Smolder) until this battle time ...
	burnDps: number, -- ... losing this many HP per second ...
	burnBy: Fighter?, -- ... credited to this mage
	burnTick: number, -- seconds of burning not yet applied
	-- The wizard type (Config/Wizards.luau): its battle trait and the trait's counters.
	variant: string?,
	trait: string?,
	traitHits: number, -- hits dealt (Starfall: every 4th calls a star)
	traitTimer: number, -- seconds since the last Bloom heal
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

-- A telegraphed area that will hurt (data; the visuals are BattleFx.warningCircle / warningLane). The Mage's AI
-- steps out of these. `expires` is the battle clock when it stops mattering (Luau reserves the word `until`).
export type Hazard = { pos: Vector3, radius: number, expires: number, kind: string, source: Fighter? }

-- The battles that are running right now (for the spells and the battle speed).
export type Battle = {
	fighters: { Fighter },
	parent: Instance,
	numbers: boolean, -- show the damage numbers (a setting)
	speed: () -> number, -- the player's battle speed (1x / 2x), read every tick
	enemyPower: number,
	elite: boolean, -- an elite wave: summoned / spawned enemies glow golden too
	summonKind: string?, -- the mob a Chief boss summons
	summonTier: number,
	plot: Plots.Plot,
	onSummon: ((Fighter) -> ())?,
	rift: RiftKing.State?, -- the final boss's fight, while Grubnak — The Rift King is in this battle
	-- The battle clock and its scheduler: every state change runs on these (never task.delay), so 2x speed and the
	-- test stubs stay correct. `clock += dt` is the first thing step() does.
	clock: number,
	events: { { at: number, fn: () -> () } }, -- sorted by `at`; schedule(battle, delay, fn)
	movers: { (dt: number) -> boolean }, -- run every tick after the events; removed when they return false
	hazards: { Hazard }, -- pruned (expires <= clock) at the top of step()
	fx: Folder, -- "BattleFx" under plot.folder: telegraphs and pops; destroyed with the battle
	-- Events: forwarded to every living fighter's brain / ai (onEvent) and to the wave mutators. Catalogue:
	-- battleStart {}, battleEnd { won }, allyHurt { ally, fraction, attacker }, allyDown { victim, killer },
	-- kill { victim, killer }, lastEnemy { enemy }, hazard (the Hazard record), playerSpell { id, point },
	-- enemyCharging { brute, from, to, impactAt }, shamanCast { shaman, kind, until }, bossTelegraph { boss, ability, pos,
	-- radius, impactAt }, warcry { grunt }, focusFire { archers, target, at }, waveEvent { id, … }.
	emit: (name: string, payload: any) -> (),
	notify: (text: string) -> (), -- a short text for the player (options.notify)
	wave: number, -- options.wave (0 when unknown)
	lastEnemyFlagged: boolean,
	won: boolean?,
	spawnEnemy: ((kind: string, tier: number, pos: Vector3) -> Fighter)?, -- a new enemy mid-fight (a Chief's summon, an ambush)
	mutators: any?, -- the wave twists runtime (WaveMutators.luau), when any
	twists: { any }, -- the wave's twist definitions (Config/Mutators.luau)
	formation: string, -- the enemies' layout name (Config/Formations.luau; informational, see Plots.showEnemies)
	enemyCtx: any?, -- the enemy brains' shared context (EnemyBrain.Context), built in start()
	damageDealt: number, -- damage your side dealt to the enemies (the result screen)
	spells: any?, -- BattleSpells.luau: reinforcements, the player's meteor, the element wizards' signature spells
	pendingEnemies: number, -- enemies announced but not spawned yet (reinforcements): the wave is not beaten while any are
	groundAt: (Vector3) -> number, -- world y of the ground under a position (the arena's heightAt): fighters walk
	-- from their pads up the step onto the round platform and down again, so every tick snaps them to the ground
}
local active: { [Player]: Battle } = {}

-- Runs `fn` after `delay` battle seconds (drained at the top of step()).
local function schedule(battle: Battle, delay: number, fn: () -> ())
	local at = battle.clock + delay
	local events = battle.events
	local index = #events + 1
	while index > 1 and events[index - 1].at > at do
		index -= 1
	end
	table.insert(events, index, { at = at, fn = fn })
end

-- A per-tick callback (a moving telegraph, a strobe): kept while it returns true.
local function addMover(battle: Battle, fn: (dt: number) -> boolean)
	table.insert(battle.movers, fn)
end

-- Registers a telegraphed area for `duration` battle seconds and announces it ("hazard").
local function addHazard(battle: Battle, pos: Vector3, radius: number, duration: number, kind: string, source: Fighter?): Hazard
	local hazard: Hazard = { pos = pos, radius = radius, expires = battle.clock + duration, kind = kind, source = source }
	table.insert(battle.hazards, hazard)
	battle.emit("hazard", hazard)
	return hazard
end

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
		brain = nil,
		ai = nil,
		lastHitBy = nil,
		lastHitAt = 0,
		killEmitted = false,
		hurtFlagged = false,
		haste = 1,
		buffDamage = 0,
		buffUntil = 0,
		hexFactor = 1,
		hexUntil = 0,
		taunt = nil,
		shieldHp = 0,
		champion = false,
		boltStyle = nil,
		boltTint = nil,
		baseLift = lift,
		tilt = 0,
		bonusCoins = 0,
		noReward = false,
		mageLevel = nil,
		ascended = nil,
		hitCount = 0,
		hitStreak = 0,
		overloaded = false,
		barrierUsed = false,
		auraTimer = 0,
		burnUntil = 0,
		burnDps = 0,
		burnBy = nil,
		burnTick = 0,
		variant = nil,
		trait = nil,
		traitHits = 0,
		traitTimer = 0,
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
		local cf = CFrame.lookAt(p, look)
		if f.tilt ~= 0 then
			cf *= CFrame.Angles(f.tilt, 0, 0) -- a negative tilt leans the head into the motion
		end
		f.model:PivotTo(cf)
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
			-- A fighter with `taunt` set (the Brute "wall") draws attacks the same way.
			if other.taunt and d <= other.taunt and d < taunterDist then
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

	if from.passive == "splash" then
		-- The Mage: an ARCANE FIREBALL. The staff tilts toward the enemy, its crystal charges up for a moment
		-- (a growing purple glow at the tip), then a purple ball with a trail flies straight at the target and
		-- bursts over the splash area (its splash damage is in `step`).
		-- The brain can style the next shot: boltStyle "execute" = a 1.6x ball with a white core (a killing blow),
		-- boltTint = another ball color (the red "spite" shot). Both are read once and reset here.
		local style, tintOverride = from.boltStyle, from.boltTint
		from.boltStyle = nil
		from.boltTint = nil
		local execute = style == "execute"
		local PURPLE = tintOverride or Color3.fromRGB(190, 110, 255)
		local PALE = if execute then Color3.new(1, 1, 1) else Color3.fromRGB(235, 205, 255)
		local ballScale = if execute then 1.6 else 1
		local CHARGE = 0.4 -- seconds the crystal charges before the shot
		local tip: BasePart? = nil
		local weapon = from.model:FindFirstChild("Weapon")
		if weapon then
			local topY = -math.huge
			for _, piece in weapon:GetChildren() do
				if piece:IsA("BasePart") and piece.Name == "Piece" and piece.Position.Y > topY then
					topY = piece.Position.Y
					tip = piece
				end
			end
		end
		-- The mage raises the arm with the staff: the shoulder joint itself turns (no Roblox animation, so the legs
		-- and the body stay as they are), the staff points at the enemy, the shot kicks the arm back a little
		-- (recoil) and the arm comes down again after it.
		local RAISE = math.rad(80) -- the arm swings FORWARD (a negative angle took it up behind the head)
		local upperArm = from.model:FindFirstChild("RightUpperArm")
		local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder")
		if shoulder and shoulder:IsA("Motor6D") then
			local rest = shoulder.C0
			TweenService:Create(shoulder, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest * CFrame.Angles(RAISE, 0, 0) }):Play()
			task.delay(CHARGE, function()
				if not shoulder.Parent then
					return
				end
				TweenService:Create(shoulder, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest * CFrame.Angles(RAISE + math.rad(22), 0, 0) }):Play()
				task.delay(0.08, function()
					if shoulder.Parent then
						TweenService:Create(shoulder, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest * CFrame.Angles(RAISE, 0, 0) }):Play()
					end
				end)
				task.delay(0.35, function()
					if shoulder.Parent then
						TweenService:Create(shoulder, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = rest }):Play()
					end
				end)
			end)
		end
		local hand = from.model:FindFirstChild("RightHand")
		local grip = hand and hand:FindFirstChild("RightGrip")
		if grip and grip:IsA("Motor6D") then
			TweenService:Create(grip, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = CFrame.Angles(math.rad(-15), 0, 0) }):Play()
			task.delay(CHARGE + 0.35, function()
				if grip.Parent then
					TweenService:Create(grip, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = CFrame.new() }):Play()
				end
			end)
		end
		-- The charge: a glow welded to the crystal that grows and brightens.
		local charge = Instance.new("Part")
		charge.Shape = Enum.PartType.Ball
		charge.Size = Vector3.one * 0.4
		charge.Color = PALE
		charge.Material = Enum.Material.Neon
		charge.Transparency = 0.2
		charge.CanCollide = false
		charge.CanQuery = false
		charge.CanTouch = false
		charge.Massless = true
		charge.CastShadow = false
		local chargeLight = Instance.new("PointLight")
		chargeLight.Color = PURPLE
		chargeLight.Range = 4
		chargeLight.Brightness = 0.5
		chargeLight.Parent = charge
		if tip then
			charge.Anchored = false
			charge.CFrame = tip.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = tip
			weld.Part1 = charge
			weld.Parent = charge
		else
			charge.Anchored = true
			charge.CFrame = CFrame.new(a + UP * 1.2)
		end
		charge.Parent = parent
		TweenService:Create(charge, TweenInfo.new(CHARGE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.one * 2.2 }):Play()
		TweenService:Create(chargeLight, TweenInfo.new(CHARGE), { Range = 10, Brightness = 2 }):Play()
		Debris:AddItem(charge, CHARGE + 0.02)

		task.delay(CHARGE, function()
			if not parent.Parent then
				return
			end
			local start = if tip and tip.Parent then tip.Position else a + UP * 1.2
			local flight = math.clamp((b - start).Magnitude / 110, 0.08, 0.25)
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.one * 2.3 * ballScale
			ball.Color = PURPLE
			ball.Material = Enum.Material.Neon
			ball.Transparency = 0.1
			ball.Anchored = true
			ball.CanCollide = false
			ball.CanQuery = false
			ball.CanTouch = false
			ball.CastShadow = false
			ball.CFrame = CFrame.new(start)
			local core = Instance.new("Part")
			core.Shape = Enum.PartType.Ball
			core.Size = Vector3.one * 1.2 * ballScale
			core.Color = PALE
			core.Material = Enum.Material.Neon
			core.Anchored = true
			core.CanCollide = false
			core.CanQuery = false
			core.CanTouch = false
			core.CastShadow = false
			core.CFrame = CFrame.new(start)
			local light = Instance.new("PointLight")
			light.Color = PURPLE
			light.Range = 10
			light.Brightness = 1.6
			light.Parent = ball
			local sparkles = Instance.new("Sparkles")
			sparkles.SparkleColor = PALE
			sparkles.Parent = ball
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Position = Vector3.new(0, 1.0, 0)
			a1.Position = Vector3.new(0, -1.0, 0)
			a0.Parent = ball
			a1.Parent = ball
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(PALE, Color3.fromRGB(120, 40, 200))
			trail.Transparency = NumberSequence.new(0.15, 1)
			trail.Lifetime = 0.3
			trail.LightEmission = 1
			trail.Parent = ball
			ball.Parent = parent
			core.Parent = parent
			local info = TweenInfo.new(flight, Enum.EasingStyle.Linear)
			TweenService:Create(ball, info, { CFrame = CFrame.new(b) }):Play()
			TweenService:Create(core, info, { CFrame = CFrame.new(b) }):Play()
			Debris:AddItem(ball, flight + 0.02)
			Debris:AddItem(core, flight + 0.02)
			task.delay(flight, function()
				if not parent.Parent then
					return
				end
				-- The burst: a flash growing over the splash area, a ring on the floor and arcane sparks flying out.
				local radius = Balance.SplashRadius
				local flash = Instance.new("Part")
				flash.Shape = Enum.PartType.Ball
				flash.Size = Vector3.one * 2.3
				flash.Color = PALE
				flash.Material = Enum.Material.Neon
				flash.Transparency = 0.1
				flash.Anchored = true
				flash.CanCollide = false
				flash.CanQuery = false
				flash.CanTouch = false
				flash.CastShadow = false
				flash.CFrame = CFrame.new(b)
				flash.Parent = parent
				TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 1.3, Transparency = 1, Color = PURPLE }):Play()
				Debris:AddItem(flash, 0.35)
				local ring = Instance.new("Part")
				ring.Shape = Enum.PartType.Cylinder
				ring.Size = Vector3.new(0.3, 1, 1)
				ring.Color = PURPLE
				ring.Material = Enum.Material.Neon
				ring.Transparency = 0.2
				ring.Anchored = true
				ring.CanCollide = false
				ring.CanQuery = false
				ring.CanTouch = false
				ring.CastShadow = false
				ring.CFrame = CFrame.new(to.pos + UP * 0.3) * CFrame.Angles(0, 0, math.rad(90))
				ring.Parent = parent
				TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 }):Play()
				Debris:AddItem(ring, 0.4)
				for _ = 1, 10 do
					local angle = math.random() * math.pi * 2
					local distance = radius * (0.3 + math.random() * 0.6)
					local spark = Instance.new("Part")
					spark.Size = Vector3.new(0.25, 0.5, 0.25)
					spark.Color = if math.random() < 0.5 then PURPLE else PALE
					spark.Material = Enum.Material.Neon
					spark.Anchored = true
					spark.CanCollide = false
					spark.CanQuery = false
					spark.CanTouch = false
					spark.CastShadow = false
					spark.CFrame = CFrame.new(b) * CFrame.Angles(math.random() * 3, math.random() * 3, 0)
					spark.Parent = parent
					TweenService:Create(spark, TweenInfo.new(0.4 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Position = b + Vector3.new(math.cos(angle) * distance, 1 + math.random() * 3, math.sin(angle) * distance),
						Transparency = 1,
						Size = Vector3.one * 0.1,
					}):Play()
					Debris:AddItem(spark, 0.75)
				end
			end)
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
	if target.shieldHp > 0 then
		-- A bubble (warded enemies, wards): drained before the HP; it pops when it is used up.
		local absorbed = math.min(target.shieldHp, amount)
		target.shieldHp -= absorbed
		amount -= absorbed
		if target.shieldHp <= 0 then
			target.shieldHp = 0
			local parent = target.model.Parent
			if parent then
				BattleFx.shieldBreak(parent, target)
			end
		end
	end
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
	-- Temporary modifiers: a damage buff (frenzy, rally, gang up) and a hex (deals less).
	if f.buffUntil > f.clock then
		amount *= 1 + f.buffDamage
	end
	if f.hexUntil > f.clock then
		amount *= f.hexFactor
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

-- EVERY damage path goes through here: the hit itself, the brains' onDamaged, and the "allyHurt" / "kill" / "allyDown"
-- events (each edge once per fighter). `source` is nil for the player's spells, storms and puddles. Returns the damage
-- really taken.
local P = MageTree.Passives
local SMOLDER_COLOR = Color3.fromRGB(255, 150, 60)
local MIRROR_COLOR = Color3.fromRGB(150, 230, 255)
local BARRIER_COLOR = Color3.fromRGB(120, 200, 255)
local OVERLOAD_COLOR = Color3.fromRGB(220, 130, 255)

-- `plain` = no tree passives (a reflected hit, an Overload explosion, a burn tick), so they never feed themselves.
local applyDamage: (battle: Battle, target: Fighter, amount: number, source: Fighter?, plain: boolean?) -> number
applyDamage = function(battle: Battle, target: Fighter, amount: number, source: Fighter?, plain: boolean?): number
	-- The Mage's tree (Config/MageTree.luau), the attacker's side: Archmage and Focus scale the hit.
	local tree = if source and not plain then source.mageLevel else nil
	if tree then
		local mage = source :: Fighter
		if MageTree.has(tree, "archmage") then
			amount *= 1 + P.archmage.Damage * (if mage.ascended then 2 else 1)
		end
		if MageTree.has(tree, "focus") then
			mage.hitCount += 1
			if mage.hitCount % P.focus.Every == 0 then
				amount *= P.focus.Mult
			end
		end
	end
	-- The target's side: MIRROR sends a ranged hit back to the shooter.
	if target.mageLevel and source and not plain and source.side ~= target.side and source.range >= P.mirror.MinRange and MageTree.has(target.mageLevel, "mirror") and math.random() < P.mirror.Chance then
		local parent = battle.parent
		BattleFx.beam(parent, target.pos + UP * target.lift, source.pos + UP * source.lift, MIRROR_COLOR, 0.35, 0.22)
		BattleFx.tint(target.model, MIRROR_COLOR, 0.3)
		popNumber(parent, source, applyDamage(battle, source, amount, target, true), MIRROR_COLOR)
		return 0
	end
	local taken = damage(target, amount)
	if source and source.side == PLAYER_SIDE and target.side == ENEMY_SIDE then
		battle.damageDealt += taken
	end
	if tree and taken > 0 and source and source.side ~= target.side then
		local mage = source :: Fighter
		if MageTree.has(tree, "smolder") then
			-- SMOLDER: the target burns (the ticks are in step()).
			target.burnUntil = math.max(target.burnUntil, target.clock + P.smolder.Time)
			target.burnDps = math.max(target.burnDps, target.maxHp * P.smolder.Dps)
			target.burnBy = mage
			BattleFx.tint(target.model, SMOLDER_COLOR, P.smolder.Time)
		end
		if MageTree.has(tree, "overload") then
			if mage.overloaded then
				-- OVERLOAD: this bolt explodes: everybody around the target takes the hit too.
				mage.overloaded = false
				local parent = battle.parent
				BattleFx.groundRing(parent, target.pos, OVERLOAD_COLOR, P.overload.Radius, 0.45)
				BattleFx.sparks(parent, target.pos + UP * target.lift, OVERLOAD_COLOR, 10, P.overload.Radius * 0.6, 4)
				for _, other in battle.fighters do
					if other ~= target and other.side == target.side and other.hp > 0 and (other.pos - target.pos).Magnitude <= P.overload.Radius then
						popNumber(parent, other, applyDamage(battle, other, taken * P.overload.Fraction, mage, true), OVERLOAD_COLOR)
					end
				end
			else
				mage.hitStreak += 1
				if mage.hitStreak >= P.overload.Hits then
					mage.hitStreak = 0
					mage.overloaded = true -- the next hit explodes
					BattleFx.tint(mage.model, OVERLOAD_COLOR, 0.6)
				end
			end
		end
	end
	-- EMERGENCY BARRIER: a mage dropping under half its HP shields itself once per battle.
	if target.mageLevel and not target.barrierUsed and target.hp > 0 and target.hp < target.maxHp * P.emergencyBarrier.Below and MageTree.has(target.mageLevel, "emergencyBarrier") then
		target.barrierUsed = true
		target.shieldUntil = math.max(target.shieldUntil, target.clock + P.emergencyBarrier.Time)
		target.shieldReduction = math.max(if target.shieldUntil > target.clock then target.shieldReduction else 0, P.emergencyBarrier.Reduction)
		BattleFx.tint(target.model, BARRIER_COLOR, P.emergencyBarrier.Time)
		BattleFx.pop(battle.parent, target.pos + UP * (target.lift * 2 + 1), "BARRIER", BARRIER_COLOR, 18)
	end
	target.lastHitBy = source
	target.lastHitAt = battle.clock
	if target.brain then
		target.brain:onDamaged(source, taken) -- a Mage remembers who hurt it and flinches
	end
	if target.ai and target.ai.onDamaged then
		target.ai:onDamaged(source, taken)
	end
	if target.side == PLAYER_SIDE and not target.hurtFlagged and target.hp > 0 and target.hp < 0.40 * target.maxHp then
		target.hurtFlagged = true
		battle.emit("allyHurt", { ally = target, fraction = target.hp / target.maxHp, attacker = source })
	end
	if target.hp <= 0 and not target.killEmitted then
		target.killEmitted = true
		battle.emit(if target.side == ENEMY_SIDE then "kill" else "allyDown", { victim = target, killer = source })
	end
	return taken
end

-- applyDamage plus the floating number (in `color` when given).
local function hurt(battle: Battle, target: Fighter, amount: number, source: Fighter?, color: Color3?): number
	local taken = applyDamage(battle, target, amount, source)
	popNumber(battle.parent, target, taken, color)
	return taken
end

-- Heals `target` by `amount` (clamped to its max HP) with a green number: a shaman's mend, a boss's heal.
local function heal(battle: Battle, target: Fighter, amount: number)
	if target.hp <= 0 then
		return
	end
	local before = target.hp
	target.hp = math.min(target.maxHp, target.hp + amount)
	Soldier.setHp(target.model, target.hp / target.maxHp)
	if target.hp - before > 0.5 then
		popNumber(battle.parent, target, target.hp - before, Color3.fromRGB(120, 255, 150))
	end
end

-- THE WIZARD TRAITS (Config/Wizards.luau): what the wizard type adds to every attack of its mage. `before` scales the
-- damage of the hit (Reap's crit, Rift's bonus); `after` runs once the hit landed (`taken` = the damage it did).
local T = Wizards.Traits
local CHILL_COLOR = Color3.fromRGB(150, 220, 255)
local function traitBefore(battle: Battle, f: Fighter, target: Fighter, amount: number): number
	local trait = f.trait
	if trait == "reap" and math.random() < T.reap.Chance then
		BattleFx.pop(battle.parent, target.pos + UP * (target.lift * 2 + 1.5), "CRIT", f.color:Lerp(Color3.new(1, 1, 1), 0.4), 18)
		return amount * T.reap.Mult
	elseif trait == "rift" then
		return amount * (1 + T.rift.Damage)
	end
	return amount
end

local function traitAfter(battle: Battle, f: Fighter, target: Fighter, amount: number, taken: number)
	local trait = f.trait
	if not trait or target.side == f.side then
		return
	end
	local parent = battle.parent
	local wiz = Wizards.Types[f.variant or Wizards.Default]
	if trait == "flow" then
		local brain = f.brain :: any
		if brain and type(brain.mana) == "number" then
			brain.mana = math.min(MageConfig.Mana.Max, brain.mana + T.flow.Mana)
		end
	elseif trait == "burn" and target.hp > 0 then
		target.burnUntil = math.max(target.burnUntil, target.clock + T.burn.Time)
		target.burnDps = math.max(target.burnDps, target.maxHp * T.burn.Dps)
		target.burnBy = f
		BattleFx.tint(target.model, wiz.color, T.burn.Time)
	elseif trait == "chill" and target.hp > 0 then
		local slowed = target.slowUntil > target.clock
		target.slowUntil = math.max(target.slowUntil, target.clock + T.chill.Time)
		target.slowFactor = math.min(if slowed then target.slowFactor else 1, T.chill.Factor)
		BattleFx.tint(target.model, CHILL_COLOR, T.chill.Time)
	elseif trait == "chain" then
		local best: Fighter? = nil
		local bestDist = T.chain.Radius
		for _, other in battle.fighters do
			if other ~= target and other.side == target.side and other.hp > 0 then
				local d = (other.pos - target.pos).Magnitude
				if d <= bestDist then
					best, bestDist = other, d
				end
			end
		end
		if best then
			BattleFx.beam(parent, target.pos + UP * target.lift, best.pos + UP * best.lift, wiz.color2, 0.25, 0.2)
			popNumber(parent, best, applyDamage(battle, best, amount * T.chain.Fraction, f, true), wiz.color2)
		end
	elseif trait == "reap" and taken > 0 then
		heal(battle, f, taken * T.reap.Lifesteal)
	elseif trait == "rift" and target.hp > 0 and math.random() < T.rift.Chance then
		target.stunUntil = math.max(target.stunUntil, target.clock + T.rift.Stun)
		BattleFx.tint(target.model, wiz.color2, T.rift.Stun)
		BattleFx.pop(parent, target.pos + UP * (target.lift * 2 + 1.5), "STUN", wiz.color2, 16)
	elseif trait == "starfall" then
		f.traitHits += 1
		if f.traitHits % T.starfall.Every == 0 then
			BattleFx.beam(parent, target.pos + UP * 30, target.pos, wiz.color2, 1.2, 0.3)
			BattleFx.groundRing(parent, target.pos, wiz.color, T.starfall.Radius, 0.5)
			BattleFx.sparks(parent, target.pos + UP, wiz.color2, 12, T.starfall.Radius * 0.6, 5)
			for _, other in battle.fighters do
				if other.side == target.side and other.hp > 0 and (other.pos - target.pos).Magnitude <= T.starfall.Radius then
					popNumber(parent, other, applyDamage(battle, other, amount * T.starfall.Mult, f, true), wiz.color2)
				end
			end
		end
	end
end

-- One attack of `f` on `target` (× `mult`): the damage with the passives, the hit effect, the swing animation and the
-- splash (the Mage's Arcane Burst or an enemy with splash). Used by the step loop and by the Mage brains.
local function performAttack(battle: Battle, f: Fighter, target: Fighter, mult: number?)
	local fighters, effects = battle.fighters, battle.parent
	local amount = attackDamage(f, fighters) * (mult or 1)
	if f.trait then
		amount = traitBefore(battle, f, target, amount)
	end
	local crit = f.mageLevel ~= nil and target.side ~= f.side and math.random() < SpellConfig.Crit.Chance
	if crit then
		-- CRITICAL HIT (Config/BattleSpells): double damage, a gold number and "CRIT!".
		amount *= SpellConfig.Crit.Mult
		BattleFx.pop(effects, target.pos + UP * (target.lift * 2 + 2), "CRIT!", SpellConfig.Crit.Color, 22)
	end
	local execute = f.boltStyle == "execute" -- the Mage's killing blow: a gold number (effect() resets the style)
	local taken = applyDamage(battle, target, amount, f)
	popNumber(effects, target, taken, if execute or crit then Color3.fromRGB(255, 215, 90) else nil)
	if f.trait then
		traitAfter(battle, f, target, amount, taken)
	end
	effect(f, target, effects)
	Rig.attack(f.model, battle.speed())
	if f.side == ENEMY_SIDE and f.buffUntil > f.clock and f.buffDamage > 0 then
		-- A buffed goblin (gang up, frenzy, rally) hits with extra orange sparks: 2 per 10 % of bonus.
		BattleFx.sparks(effects, target.pos, Color3.fromRGB(255, 140, 40), math.min(8, math.floor(f.buffDamage / 0.1 + 0.5) * 2), 2, 3)
	end
	local splashFraction = if f.passive == "splash" then f.passiveValue elseif f.splash then Balance.SplashFraction else 0
	if splashFraction > 0 then
		for _, other in fighters do
			if other ~= target and other.side == target.side and other.hp > 0 then
				if (other.pos - target.pos).Magnitude <= Balance.SplashRadius then
					popNumber(effects, other, applyDamage(battle, other, amount * splashFraction, f))
				end
			end
		end
	end
end

-- A new enemy in the middle of the fight (a Chief's summon, an ambush, reinforcements): built, scaled by the enemy
-- power, golden when the wave is elite, given its brain and the wave twists' stats, and flashed in at `pos`.
local function spawnEnemy(battle: Battle, kind: string, tier: number, pos: Vector3): Fighter
	local def = Enemies.Kinds[kind]
	local model = Enemy.build(kind, tier)
	model:PivotTo(CFrame.new(pos + UP * Enemy.lift(kind, tier)))
	model.Parent = battle.parent
	local fighter = makeFighter(ENEMY_SIDE, Enemies.stats(kind, tier), tier, def.color, Enemy.lift(kind, tier), def.coins, pos, model)
	fighter.kind = kind
	fighter.boss = def.boss == true
	local waveHp, waveDamage = Balance.waveScale(battle.wave) -- the wave curve (Balance.WaveHp / WaveDamage)
	fighter.maxHp *= battle.enemyPower * waveHp * (if fighter.boss then Balance.BossHp else 1) -- bosses: long, not deadly
	fighter.hp = fighter.maxHp
	fighter.damage *= battle.enemyPower * waveDamage * (if fighter.boss then Balance.BossDamage else 1)
	if battle.elite then
		local glow = Instance.new("Highlight")
		glow.FillColor = Color3.fromRGB(255, 200, 60)
		glow.FillTransparency = 0.7
		glow.OutlineColor = Color3.fromRGB(255, 220, 120)
		glow.OutlineTransparency = 0
		glow.Parent = fighter.model
	end
	if battle.enemyCtx and def.archetype ~= "RiftKing" then
		fighter.ai = EnemyBrain.new(battle.enemyCtx, fighter, def.archetype, fighter.boss)
	end
	local mutators = battle.mutators
	if mutators and mutators.applyTo then
		mutators:applyTo(fighter)
	end
	table.insert(battle.fighters, fighter)
	teleportFlash(fighter, pos, battle.parent)
	return fighter
end

local function step(battle: Battle, dt: number, onEnemyDeath: (Fighter) -> ())
	local fighters = battle.fighters
	battle.clock += dt
	numbersThisTick = 0
	BattleFx.resetTick()
	-- Expired telegraphs go away; due events run; movers get their tick.
	local hazards = battle.hazards
	for i = #hazards, 1, -1 do
		if hazards[i].expires <= battle.clock then
			table.remove(hazards, i)
		end
	end
	local events = battle.events
	while events[1] and events[1].at <= battle.clock do
		local event = table.remove(events, 1) :: { at: number, fn: () -> () }
		event.fn()
	end
	local movers = battle.movers
	for i = #movers, 1, -1 do
		if not movers[i](dt) then
			table.remove(movers, i)
		end
	end
	local mutators = battle.mutators
	if mutators and mutators.step then
		mutators:step(dt) -- the wave twists: puddles, storms, regen, the ambush, the enrage timer …
	end
	if battle.spells then
		BattleSpells.step(battle.spells, dt) -- reinforcements and the element wizards' signature spells
	end
	-- The Mage tree's passives that tick: enemies on fire (Smolder) and the Healing Aura's pulses.
	for _, f in fighters do
		if f.hp <= 0 then
			continue
		end
		if f.burnUntil > f.clock then
			f.burnTick += dt
			if f.burnTick >= 0.5 then
				local dps = f.burnDps * (if f.boss then Balance.BossPercentDamage else 1) -- (a part of max HP: less on a boss)
				popNumber(battle.parent, f, applyDamage(battle, f, dps * f.burnTick, f.burnBy, true), SMOLDER_COLOR)
				f.burnTick = 0
			end
		end
		if f.trait == "bloom" then
			-- BLOOM (the Verdant Mage): every few seconds the most hurt ally nearby is healed.
			f.traitTimer += dt
			if f.traitTimer >= T.bloom.Every then
				f.traitTimer = 0
				local best: Fighter? = nil
				local bestFrac = 1
				for _, ally in fighters do
					if ally.side == f.side and ally.hp > 0 and (ally.pos - f.pos).Magnitude <= T.bloom.Radius then
						local frac = ally.hp / ally.maxHp
						if frac < bestFrac then
							best, bestFrac = ally, frac
						end
					end
				end
				if best then
					local wiz = Wizards.Types.Verdant
					BattleFx.beam(battle.parent, f.pos + UP * f.lift, best.pos + UP * best.lift, wiz.color2, 0.2, 0.3)
					heal(battle, best, best.maxHp * T.bloom.Heal)
				end
			end
		end
		if f.mageLevel and MageTree.has(f.mageLevel, "healAura") then
			f.auraTimer += dt
			if f.auraTimer >= 1 then
				for _, ally in fighters do
					if ally.side == f.side and ally.hp > 0 and ally.hp < ally.maxHp and (ally.pos - f.pos).Magnitude <= P.healAura.Radius then
						heal(battle, ally, ally.maxHp * P.healAura.Rate * f.auraTimer)
					end
				end
				f.auraTimer = 0
			end
		end
	end
	for _, f in fighters do
		if f.hp <= 0 then
			continue
		end
		f.clock += dt
		local groundY = battle.groundAt(f.pos)
		if math.abs(groundY - f.pos.Y) > 0.01 then
			f.pos = Vector3.new(f.pos.X, groundY, f.pos.Z) -- up the step onto the platform (and down past its edge)
		end
		if f.ability == "riftking" and battle.rift then
			if RiftKing.update(battle.rift, dt) then
				continue -- the Rift King is casting one of his four attacks (RiftKing.luau moves and hits for him)
			end
		end
		if f.stunUntil > f.clock then
			continue -- stunned by a boss slam
		end
		if f.brain then
			f.brain:update(dt) -- a Mage thinks for itself (MageBrain.luau): targets, reactions, spells
			continue
		end
		if f.ai and f.ai:update(dt) then
			continue -- an enemy brain (EnemyBrain.luau) handled this tick (a wind-up, a charge, a scurry …)
		end
		if f.boss and f.ability and not f.ai then
			-- Deprecated fallback for a boss without an enemy brain (every boss but the Rift King has one, so this
			-- runs only when EnemyBrain refused the kind): the simple instant abilities.
			f.abilityTimer -= dt
			if f.abilityTimer <= 0 then
				bossAbility(battle, f, dt)
			end
		end
		local rate = (if f.slowUntil > f.clock then f.slowFactor else 1) * f.haste -- slows and hastes scale movement and attacks
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
				performAttack(battle, f, target)
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
			if not f.killEmitted then
				-- A death outside applyDamage (a scripted kill, an escape) still counts once.
				f.killEmitted = true
				battle.emit(if f.side == ENEMY_SIDE then "kill" else "allyDown", { victim = f, killer = f.lastHitBy })
			end
			local mutators = battle.mutators
			if mutators and mutators.onDeath then
				mutators:onDeath(f) -- volatile blasts, the treasure goblin's bonus (needs f.pos / f.damage)
			end
			if battle.spells then
				BattleSpells.onDeath(battle.spells, f) -- the combo (its coins), the boss's fall, explosive / splitter enemies
			end
			if f.side == ENEMY_SIDE and not f.noReward then
				onEnemyDeath(f) -- the caller pays out the coins for the kill
			end
			if f.ability == "riftking" and battle.rift then
				RiftKing.cleanup(battle.rift) -- every warning, crystal and ring goes away with him
				battle.rift = nil
			end
			if f.brain then
				f.brain:destroy()
			end
			if f.ai and f.ai.destroy then
				f.ai:destroy()
			end
		end
	end
	-- The last enemy standing is announced once (the Mage's FINISH).
	if not battle.lastEnemyFlagged then
		local last: Fighter? = nil
		local count = 0
		for _, f in fighters do
			if f.side == ENEMY_SIDE and f.hp > 0 then
				count += 1
				last = f
			end
		end
		if count == 1 and last then
			battle.lastEnemyFlagged = true
			battle.emit("lastEnemy", { enemy = last })
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
	notify: ((text: string) -> ())?, -- a short text for the player (brains and twists announce things with it)
	wave: number?, -- the wave number (twists scale with it)
	twists: { any }?, -- the wave's twists (Mutators.forWave; GameService passes them)
	formation: string?, -- the enemies' layout (Waves.formation; "line" when missing)
}

export type Result = {
	bonusDrop: boolean, -- an extra drop earned in the fight (the treasure goblin)
	damage: number, -- damage your side dealt to the enemies (the result screen)
	duration: number, -- battle seconds the fight took
}

-- Starts the battle. `plot.models` must be rendered from the current squad.
-- At the end sets `profile.battling = false` and calls onFinished(won, result).
-- `onKill(level, position, coinMult)` is called for every dead enemy (coins are paid per kill). The caller
-- handles the outcome (progress, drops) in `onFinished`.
function BattleService.start(player: Player, profile: PlayerData.Profile, plot: Plots.Plot, options: Options, onKill: (level: number, position: Vector3, coinMult: number) -> (), onFinished: (won: boolean, result: Result) -> ())
	local fighters: { Fighter } = {}
	local enemyPower = options.enemyPower
	local waveHp, waveDamage = Balance.waveScale(options.wave) -- the wave curve: how long and how hard the fight is

	-- Only the squad fights; the merge board is just storage.
	local synergy = Synergy.compute(profile.squad)
	local boosts = MageUpgrades.multipliers(profile.mageUpgrades) -- the account's Mage upgrades (every mage)
	local mages: { { fighter: Fighter, level: number } } = {}
	for i = 1, Balance.SquadSize do
		local id = Balance.SquadOffset + i
		local cell = profile.squad[i]
		local model = plot.models[id]
		if cell and model then
			local wiz = Wizards.of(cell) -- the wizard type: its color, its rarity's stats and its trait
			local fighter = makeFighter(PLAYER_SIDE, Units.stats(cell.class, cell.tier, cell.ascended), cell.tier, wiz.color, Soldier.lift(cell.tier, cell.ascended), 1, Plots.slotGround(plot, id), model)
			fighter.variant = wiz.id
			fighter.trait = wiz.trait
			-- The class passive (doubled for an Ascended soldier).
			local passiveId = Units.Classes[cell.class].passive
			fighter.passive = passiveId
			fighter.passiveValue = Units.Passives[passiveId].value * (if cell.ascended then 2 else 1)
			fighter.spot = fighter.pos -- nobody is teleported: the six start the fight on their pads and walk
			fighter.mageLevel = cell.tier -- the merge-level tree (Config/MageTree.luau): its passives read this
			fighter.ascended = cell.ascended == true
			-- The squad's synergies make everybody stronger; the pad a soldier stands on gives nothing (it only
			-- decides which enemies it meets first).
			local rarityStats = Wizards.rarityOf(cell).stats
			fighter.maxHp *= synergy.hp * boosts.hp * rarityStats
			fighter.hp = fighter.maxHp
			fighter.damage *= synergy.damage * boosts.damage * rarityStats
			fighter.cooldown *= boosts.cooldown
			fighter.timer = math.min(fighter.timer, fighter.cooldown)
			table.insert(fighters, fighter)
			if cell.class == "Mage" then
				table.insert(mages, { fighter = fighter, level = cell.tier })
			end
		end
	end

	-- The enemies are already standing in the wave preview (Plots.showEnemies, one row); they start the fight
	-- right there and walk toward your squad, nobody is teleported.
	for i, e in plot.enemies do
		local pos = Plots.enemyGround(plot, i, #plot.enemies)
		local fighter = makeFighter(ENEMY_SIDE, Enemies.stats(e.kind, e.tier), e.tier, Enemies.Kinds[e.kind].color, Enemy.lift(e.kind, e.tier), Enemies.Kinds[e.kind].coins, pos, plot.enemyModels[i])
		fighter.spot = pos
		fighter.kind = e.kind
		fighter.champion = e.champion == true -- the CHAMPION twist (its stats come from mutators:applyTo)
		fighter.boss = Enemies.Kinds[e.kind].boss == true
		if fighter.boss then
			-- The boss's archetype decides its ability.
			local archetype = Enemies.Kinds[e.kind].archetype
			if archetype == "RiftKing" then
				fighter.ability = "riftking" -- the final boss: its own fight (RiftKing.luau), never the simple abilities
				fighter.abilityTimer = math.huge
			else
				fighter.ability = if archetype == "Brute" then "slam" elseif archetype == "Chief" then "summon" elseif archetype == "Archer" then "volley" else "heal"
				fighter.abilityTimer = if fighter.ability == "slam" then Balance.BossSlamEvery elseif fighter.ability == "volley" then Balance.BossVolleyEvery elseif fighter.ability == "heal" then Balance.BossHealEvery else 1
			end
		end
		fighter.maxHp *= enemyPower * waveHp * (if fighter.boss then Balance.BossHp else 1) -- bosses: long, not deadly
		fighter.hp = fighter.maxHp
		fighter.damage *= enemyPower * waveDamage * (if fighter.boss then Balance.BossDamage else 1)
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

	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "BattleFx"
	fxFolder.Parent = plot.folder
	local slowmoUntil, slowmoSpeed = 0, 1 -- (real clock) the fight runs at slowmoSpeed until then

	local battle: Battle = {
		fighters = fighters,
		parent = plot.folder,
		numbers = profile.settings.numbers ~= false,
		speed = function()
			if os.clock() < slowmoUntil then
				return slowmoSpeed -- a boss's slow-motion death (BattleSpells)
			end
			return profile.battleSpeed
		end,
		enemyPower = enemyPower,
		elite = options.elite == true,
		summonKind = options.summonKind,
		summonTier = options.summonTier,
		plot = plot,
		onSummon = nil,
		rift = nil,
		clock = 0,
		events = {},
		movers = {},
		hazards = {},
		fx = fxFolder,
		emit = function() end, -- set below (needs `battle`)
		notify = options.notify or function() end,
		wave = options.wave or 0,
		lastEnemyFlagged = false,
		won = nil,
		spawnEnemy = nil,
		mutators = nil,
		twists = options.twists or {},
		formation = options.formation or "line",
		enemyCtx = nil,
		groundAt = function(pos: Vector3): number
			return plot.arena.heightAt(pos)
		end,
		damageDealt = 0,
		spells = nil,
		pendingEnemies = 0,
	}
	battle.emit = function(name: string, payload: any)
		for _, f in fighters do
			if f.hp > 0 then
				if f.brain and f.brain.onEvent then
					f.brain:onEvent(name, payload)
				end
				if f.ai and f.ai.onEvent then
					f.ai:onEvent(name, payload)
				end
			end
		end
		local mutators = battle.mutators
		if mutators and mutators.onEvent then
			mutators:onEvent(name, payload)
		end
	end
	numbersOn[plot.folder] = battle.numbers
	active[player] = battle

	-- The telegraphed areas the Mage steps out of: the battle's data hazards plus the Rift King's warning parts
	-- (RiftKingFx children with the "Hazard" attribute).
	local function hazardList(): { { pos: Vector3, radius: number, kind: string? } }
		local list = {}
		for _, hazard in battle.hazards do
			table.insert(list, { pos = hazard.pos, radius = hazard.radius, kind = hazard.kind })
		end
		local fx = plot.folder:FindFirstChild("RiftKingFx")
		if fx then
			for _, part in fx:GetChildren() do
				local radius = part:GetAttribute("Hazard")
				if type(radius) == "number" and part:IsA("BasePart") then
					table.insert(list, { pos = part.Position, radius = radius, kind = "rift" })
				end
			end
		end
		return list
	end
	local function groundY(pos: Vector3): number
		return plot.arena.heightAt(pos) + 0.2
	end
	-- The brains keep their goals inside this square, inscribed in the round platform (its corners are on the edge).
	local arenaHalf = math.floor(plot.arena.radius * 0.7)
	local arenaBounds = { center = plot.arena.center, halfX = arenaHalf, halfZ = arenaHalf }
	local function archetypeOf(f: Fighter): string?
		return if f.kind and Enemies.Kinds[f.kind] then Enemies.Kinds[f.kind].archetype else nil
	end

	-- The enemy brains (EnemyBrain.luau) share one context: the fighters, the damage / heal helpers, the visuals,
	-- the telegraph data, the scheduler and the arena bounds. Every enemy but the Rift King gets a brain.
	local enemyCtx: EnemyBrain.Context = {
		fighters = fighters,
		playerSide = PLAYER_SIDE,
		parent = plot.folder,
		fx = BattleFx,
		fxFolder = fxFolder,
		groundY = groundY,
		attack = function(f, target, mult)
			performAttack(battle, f, target, mult)
		end,
		hurt = function(target, amount, source)
			return hurt(battle, target, amount, source)
		end,
		heal = function(target, amount)
			heal(battle, target, amount)
		end,
		face = face,
		bounds = arenaBounds,
		emit = battle.emit,
		addHazard = function(pos, radius, duration, kind, source)
			addHazard(battle, pos, radius, duration, kind, source)
		end,
		schedule = function(delay, fn)
			schedule(battle, delay, fn)
		end,
		addMover = function(fn)
			addMover(battle, fn)
		end,
		notify = battle.notify,
		spawnEnemy = function(kind, tier, pos)
			return spawnEnemy(battle, kind, tier, pos)
		end,
		hitPlayers = function(center, radius, hp)
			BattleFx.hitPlayers(plot, center, radius, hp)
		end,
		clock = function()
			return battle.clock
		end,
		speed = battle.speed,
		wave = battle.wave,
		archetype = archetypeOf,
		summonKind = options.summonKind,
		summonTier = options.summonTier,
		flags = {},
	}
	battle.enemyCtx = enemyCtx
	battle.spawnEnemy = function(kind, tier, pos)
		return spawnEnemy(battle, kind, tier, pos)
	end
	for _, f in fighters do
		if f.side == ENEMY_SIDE then
			local archetype = archetypeOf(f)
			if archetype and archetype ~= "RiftKing" then
				f.ai = EnemyBrain.new(enemyCtx, f, archetype, f.boss)
			end
		end
	end

	-- The wave's twists (WaveMutators.luau): every enemy gets its twist stats once its brain exists (a later spawn gets
	-- them in spawnEnemy); the world cues appear with the teleport-in flash (onStart). The BossHp bar is sent from here
	-- and left to the Rift King while he fights.
	local mutatorCtx: WaveMutators.Ctx = {
		plot = plot,
		fighters = fighters,
		playerSide = PLAYER_SIDE,
		enemySide = ENEMY_SIDE,
		parent = plot.folder,
		fx = BattleFx,
		fxFolder = fxFolder,
		groundY = groundY,
		damage = function(target, amount, source)
			return applyDamage(battle, target, amount, source)
		end,
		hurt = function(target, amount, source, color)
			return hurt(battle, target, amount, source, color)
		end,
		popNumber = function(target, amount, color)
			popNumber(plot.folder, target, amount, color)
		end,
		heal = function(target, amount)
			heal(battle, target, amount)
		end,
		addHazard = function(pos, radius, duration, kind, source)
			addHazard(battle, pos, radius, duration, kind, source)
		end,
		schedule = function(delay, fn)
			schedule(battle, delay, fn)
		end,
		addMover = function(fn)
			addMover(battle, fn)
		end,
		emit = battle.emit,
		notify = battle.notify,
		spawnEnemy = function(kind, tier, pos)
			return spawnEnemy(battle, kind, tier, pos)
		end,
		hitPlayers = function(center, radius, hp)
			BattleFx.hitPlayers(plot, center, radius, hp)
		end,
		sendBossHp = function(name, fraction, enraged)
			if player.Parent then
				Net.get("BossHp"):FireClient(player, name, fraction, enraged)
			end
		end,
		flash = function(f, pos)
			teleportFlash(f, pos, plot.folder)
		end,
		riftActive = function()
			return battle.rift ~= nil
		end,
		archetype = archetypeOf,
		clock = function()
			return battle.clock
		end,
		wave = battle.wave,
		summonKind = options.summonKind,
		summonTier = options.summonTier,
		enemyPower = enemyPower,
		rng = Random.new(battle.wave * 7919 + 101),
	}
	local mutators = WaveMutators.new(battle, battle.twists, mutatorCtx)
	battle.mutators = mutators
	for _, f in fighters do
		if f.side == ENEMY_SIDE then
			mutators:applyTo(f)
		end
	end

	-- The fight's extra action (BattleSpells.luau): reinforcements, the player's meteor, the signature spells.
	local twistIds: { string } = {}
	for _, def in battle.twists do
		if type(def) == "table" and type(def.id) == "string" then
			table.insert(twistIds, def.id)
		end
	end
	battle.spells = BattleSpells.new({
		fighters = fighters,
		playerSide = PLAYER_SIDE,
		enemySide = ENEMY_SIDE,
		parent = plot.folder,
		fx = BattleFx,
		fxFolder = fxFolder,
		groundY = groundY,
		damage = function(target, amount, source)
			return applyDamage(battle, target, amount, source, true)
		end,
		popNumber = function(target, amount, color)
			popNumber(plot.folder, target, amount, color)
		end,
		heal = function(target, amount)
			heal(battle, target, amount)
		end,
		schedule = function(delay, fn)
			schedule(battle, delay, fn)
		end,
		addMover = function(fn)
			addMover(battle, fn)
		end,
		addHazard = function(pos, radius, duration, kind, source)
			addHazard(battle, pos, radius, duration, kind, source)
		end,
		emit = battle.emit,
		notify = battle.notify,
		spawnEnemy = function(kind, tier, pos)
			return spawnEnemy(battle, kind, tier, pos)
		end,
		hold = function(count)
			battle.pendingEnemies = math.max(0, battle.pendingEnemies + count)
		end,
		archetype = archetypeOf,
		clock = function()
			return battle.clock
		end,
		center = plot.arena.center,
		arenaRadius = plot.arena.radius,
		feel = function(data)
			if player.Parent then
				Net.get("BattleFeel"):FireClient(player, data) -- camera shakes, the combo counter, the boss banner
			end
		end,
		slowmo = function(speed, seconds)
			slowmoSpeed = speed
			slowmoUntil = os.clock() + seconds
		end,
		scaleModel = function(f, scale)
			pcall(function()
				f.model:ScaleTo(f.model:GetScale() * scale)
			end)
			f.lift *= scale
		end,
		wave = battle.wave,
		boss = battle.wave > 0 and battle.wave % Balance.PhaseLength == 0,
		twists = twistIds,
		random = Random.new(battle.wave * 104729 + 7),
	})

	-- Every Mage gets a brain (MageBrain.luau) with its own context (the Mage is the source of its damage): the
	-- battle's fighters, the damage helpers, the visuals (BattleFx), the events, the clock and the arena bounds.
	local center = plot.arena.center
	for _, entry in mages do
		local mage = entry.fighter
		local brainContext: MageBrain.Context = {
			fighters = fighters,
			parent = plot.folder,
			playerSide = PLAYER_SIDE,
			self = mage,
			fx = BattleFx,
			attack = function(f, target, mult)
				performAttack(battle, f, target, mult)
			end,
			damage = function(target, amount)
				return applyDamage(battle, target, amount, mage)
			end,
			popNumber = function(target, amount, color)
				popNumber(plot.folder, target, amount, color)
			end,
			face = face,
			bounds = arenaBounds,
			hazards = hazardList,
			archetype = function(f)
				return if f.kind and Enemies.Kinds[f.kind] then Enemies.Kinds[f.kind].archetype else nil
			end,
			emit = battle.emit,
			clock = function()
				return battle.clock
			end,
			addHazard = function(pos, radius, duration, kind, source)
				addHazard(battle, pos, radius, duration, kind, source)
			end,
			schedule = function(delay, fn)
				schedule(battle, delay, fn)
			end,
			groundY = groundY,
		}
		mage.brain = MageBrain.new(brainContext, mage, entry.level)
	end
	for _, f in fighters do
		if f.ability == "riftking" then
			local riftFighter = f
			battle.rift = RiftKing.new({
				player = player,
				plot = plot,
				parent = plot.folder,
				fighters = fighters,
				playerSide = PLAYER_SIDE,
				damage = function(target, amount)
					return applyDamage(battle, target, amount, riftFighter)
				end,
				popNumber = function(target, amount)
					popNumber(plot.folder, target, amount)
				end,
			}, f)
		end
	end

	task.spawn(function()
		-- Phase 1: no teleport. Everybody starts where it stands (your six on their pads, the wave in its row),
		-- turns to the other side and the fight starts right away: both sides walk up onto the round platform.
		if not (player.Parent and plot.folder.Parent) then
			active[player] = nil
			numbersOn[plot.folder] = nil
			return
		end
		for _, f in fighters do
			face(f, f.pos + Vector3.new(0, 0, if f.side == PLAYER_SIDE then 10 else -10)) -- facing the other side
		end
		battle.emit("battleStart", {})
		mutators:onStart() -- the twists' world cues (moon, clouds, puddles, the enrage bar)

		-- Phase 2: the fight. The battle speed (1x / 2x) stretches every tick.
		local elapsed = 0
		local limit = if battle.wave > 0 and battle.wave % Balance.PhaseLength == 0 then Balance.BossBattleTimeLimit else Balance.BattleTimeLimit
		while player.Parent and plot.folder.Parent and elapsed < limit do
			task.wait(Balance.BattleTickRate)
			numbersOn[plot.folder] = profile.settings.numbers ~= false
			local dt = Balance.BattleTickRate * battle.speed()
			elapsed += dt
			step(battle, dt, function(enemy)
				onKill(enemy.tier, enemy.pos, enemy.coinMult * math.max(0, 1 + enemy.bonusCoins)) -- twists change a kill's coins (champion, swarm)
			end)
			if countAlive(fighters, PLAYER_SIDE) == 0 or (countAlive(fighters, ENEMY_SIDE) == 0 and battle.pendingEnemies == 0) then
				break
			end
		end

		local won = countAlive(fighters, ENEMY_SIDE) == 0 and battle.pendingEnemies == 0 and countAlive(fighters, PLAYER_SIDE) > 0
		battle.won = won
		battle.emit("battleEnd", { won = won })
		if battle.rift then
			RiftKing.cleanup(battle.rift) -- the battle ended with the boss still up (time ran out, the squad fell)
			battle.rift = nil
		end
		for _, f in fighters do
			if f.brain and f.hp > 0 then
				f.brain:destroy() -- restores the hover / runes of a Mage that is still up
			end
			if f.ai and f.hp > 0 then
				f.ai:destroy() -- telegraphs, runes and stars of the enemies still standing
			end
			if f.side == ENEMY_SIDE and f.hp > 0 and f.model.Parent then
				-- Enemies still standing after a loss / time-out: the preview ones go with Plots.clearEnemies below, but
				-- the ones spawned mid-fight (a Chief's summon, an ambush) live in plot.folder and would stay forever.
				f.model:Destroy()
			end
		end
		mutators:cleanup() -- the twists' cues and the shared HP bar (before the fx folder goes)
		table.clear(battle.events)
		table.clear(battle.movers)
		table.clear(battle.hazards)
		active[player] = nil
		numbersOn[plot.folder] = nil
		profile.battling = false

		-- Remove leftover enemies and pads; refresh builds the preview of the next (or the same) wave.
		-- The telegraphs and pops go with the battle (the Mage's victory pose was drawn before this).
		task.delay(if won then 1.5 else 0, function()
			fxFolder:Destroy()
		end)
		if plot.folder.Parent then
			Plots.clearEnemies(plot)
			Plots.resetSquad(plot) -- the battle moved / destroyed the squad's models
		end

		if player.Parent and plot.folder.Parent then
			onFinished(won, { bonusDrop = mutators.bonusDrop, damage = battle.damageDealt, duration = battle.clock })
		end
	end)
end

-- ── Spell effects ───────────────────────────────────────────────────────────
-- The part helpers live in BattleFx (shared with the brains); these are thin aliases.

local groundRing = BattleFx.groundRing
local sparks = BattleFx.sparks

-- A colored glow on a fighter for a while (a boss's stun).
-- The player's spell `id` (Config/BattleSpells.PlayerSpells: the round buttons / keys 1-4 during a fight), aimed at
-- `point` (nil, or a point outside the arena: it aims itself). Returns (cast, REAL seconds until it is ready, so the
-- client's cooldown ring matches at 2x speed too). (false, nil) when there is no fight.
function BattleService.castSpell(player: Player, id: string, point: Vector3?): (boolean, number?)
	local battle = active[player]
	if not battle or not battle.spells or battle.won ~= nil or not SpellConfig.PlayerSpells[id] then
		return false, nil
	end
	local ok, wait = BattleSpells.castPlayer(battle.spells, id, point)
	return ok, wait / math.max(1, battle.speed())
end

local function tint(f: Fighter, color: Color3, duration: number)
	BattleFx.tint(f.model, color, duration)
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
				hurt(battle, f, boss.damage * Balance.BossSlamDamage, boss)
				f.stunUntil = f.clock + Balance.BossSlamStun
				tint(f, Color3.fromRGB(255, 200, 90), Balance.BossSlamStun)
			end
		end
	elseif boss.ability == "volley" then
		boss.abilityTimer = Balance.BossVolleyEvery
		Rig.cast(boss.model, "lunge")
		for _, f in battle.fighters do
			if f.side == PLAYER_SIDE and f.hp > 0 and (f.pos - boss.pos).Magnitude <= boss.range + 4 then
				hurt(battle, f, boss.damage * Balance.BossVolleyDamage, boss)
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
			spawnEnemy(battle, kind, battle.summonTier, boss.pos + Vector3.new(math.cos(angle) * 5, 0, math.sin(angle) * 5))
		end
	end
end

return BattleService
