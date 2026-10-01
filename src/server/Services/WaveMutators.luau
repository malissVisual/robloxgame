--!strict
-- The wave TWISTS at runtime (their definitions and every number: shared/Config/Mutators.luau). BattleService creates
-- one WaveMutators per battle: `applyTo(fighter)` gives one enemy its twist stats and looks (called for every enemy
-- of the wave and for every enemy spawned mid-fight), `onStart()` builds the in-world cues (the blood moon, the storm
-- clouds, the toxic puddles, the enrage bar), `step(dt)` runs the timed twists on the battle clock (regen, puddles,
-- storms, the ambush, the enrage timer, the treasure goblin's escape, the totems' healing, the champion's HP bar),
-- `onDeath(f)` handles the volatile blasts and the treasure goblin's bonus drop, `cleanup()` removes everything.
--
-- Rules: everything that hurts runs on the battle clock (ctx.schedule / step), never task.delay; every mid-fight area
-- has a floor telegraph (ctx.fx.warningCircle) plus a data hazard (ctx.addHazard, what the Mage avoids) ≥ 1.2 s ahead;
-- the player's character is hurt only inside marked areas (puddles, storm circles, volatile blasts). The BossHp bar is
-- shared: the Rift King wins, then the enrage timer, then the champion.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mutators = require(Shared.Config.Mutators)
local Enemies = require(Shared.Config.Enemies)

local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.new(1, 1, 1)
local FOREVER = 1e6 -- "permanent" durations for marks and buffs (battles last 90 s)

-- What the runtime gets from BattleService. Fighters are BattleService's plain records.
export type Ctx = {
	plot: any,
	fighters: { any },
	playerSide: number,
	enemySide: number,
	parent: Instance, -- plot.folder (rings, sparks)
	fx: any, -- BattleFx
	fxFolder: Instance, -- battle.fx: telegraphs, world cues (destroyed with the battle)
	groundY: (pos: Vector3) -> number,
	damage: (target: any, amount: number, source: any?) -> number, -- applyDamage (no floating number)
	hurt: (target: any, amount: number, source: any?, color: Color3?) -> number, -- applyDamage + the number
	popNumber: (target: any, amount: number, color: Color3?) -> (),
	heal: (target: any, amount: number) -> (),
	addHazard: (pos: Vector3, radius: number, duration: number, kind: string, source: any?) -> (),
	schedule: (delay: number, fn: () -> ()) -> (),
	addMover: (fn: (dt: number) -> boolean) -> (),
	emit: (name: string, payload: any) -> (),
	notify: (text: string) -> (),
	spawnEnemy: (kind: string, tier: number, pos: Vector3) -> any,
	hitPlayers: (center: Vector3, radius: number, hp: number) -> (),
	sendBossHp: (name: string, fraction: number, enraged: boolean) -> (),
	flash: (f: any, pos: Vector3) -> (), -- the teleport flash (the treasure goblin's escape)
	riftActive: () -> boolean, -- the Rift King owns the BossHp bar
	archetype: (f: any) -> string?,
	clock: () -> number,
	wave: number,
	summonKind: string?,
	summonTier: number,
	enemyPower: number,
	rng: Random, -- seeded by the wave (puddle and storm positions)
}

type Puddle = { pos: Vector3, radius: number, part: BasePart, bubbleIn: number, pops: { [any]: number } }

export type State = {
	battle: any,
	twists: { Mutators.Def },
	ctx: Ctx,
	bonusDrop: boolean, -- the treasure goblin was caught
	cleaned: boolean,
	applied: { [any]: boolean }, -- fighters that got their twist stats
	parts: { Instance }, -- everything built in the world (destroyed in cleanup)
	initialEnemies: number, -- combat enemies at the start (the ambush's half-dead trigger)
	deaths: number,
	-- Timers (battle clock).
	puddles: { Puddle },
	puddlePlayersAt: number,
	regenAt: { [any]: number }, -- next green mote / heal tick per enemy
	totemAt: number,
	stormAt: number,
	ambushAt: number,
	ambushDone: boolean,
	enrageEndsAt: number,
	enrageBarAt: number,
	enrageWarned: boolean,
	enraged: boolean,
	championBarAt: number,
	champion: any?,
	treasureGone: boolean,
}

local WaveMutators = {}
WaveMutators.__index = WaveMutators

local function has(self: State, id: string): Mutators.Def?
	return Mutators.has(self.twists, id)
end

local function flatDist(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- A combat enemy: on the enemy side, alive, not a totem or the treasure goblin.
local function isCombatEnemy(self: State, f: any): boolean
	if f.side ~= self.ctx.enemySide or f.hp <= 0 then
		return false
	end
	local archetype = self.ctx.archetype(f)
	return archetype ~= "Totem" and archetype ~= "Treasure"
end

local function keep(self: State, instance: Instance): Instance
	table.insert(self.parts, instance)
	return instance
end

-- A permanent haste on a fighter: the enemy brain keeps a base haste and recomputes from it, so both move together.
local function permanentHaste(f: any, factor: number)
	f.haste *= factor
	if f.ai and f.ai.hasteBase then
		f.ai.hasteBase *= factor
	end
end

local function scaleHp(f: any, factor: number)
	local fraction = if f.maxHp > 0 then f.hp / f.maxHp else 1
	f.maxHp *= factor
	f.hp = f.maxHp * fraction
end

local function highlight(model: Instance, fill: Color3, fillTransparency: number, outline: Color3): Highlight
	local glow = Instance.new("Highlight")
	glow.FillColor = fill
	glow.FillTransparency = fillTransparency
	glow.OutlineColor = outline
	glow.OutlineTransparency = 0
	glow.Parent = model
	return glow
end

local function enrageOne(self: State, f: any)
	local E = Mutators.Defs.enrage
	f.damage *= 1 + E.Damage
	permanentHaste(f, E.Haste)
	highlight(f.model, E.color, 0.6, E.color)
end

function WaveMutators.new(battle: any, twists: { Mutators.Def }, ctx: Ctx): State
	local self: State = {
		battle = battle,
		twists = twists,
		ctx = ctx,
		bonusDrop = false,
		cleaned = false,
		applied = {},
		parts = {},
		initialEnemies = 0,
		deaths = 0,
		puddles = {},
		puddlePlayersAt = 0,
		regenAt = {},
		totemAt = 0,
		stormAt = math.huge,
		ambushAt = math.huge,
		ambushDone = false,
		enrageEndsAt = math.huge,
		enrageBarAt = 0,
		enrageWarned = false,
		enraged = false,
		championBarAt = 0,
		champion = nil,
		treasureGone = false,
	}
	return setmetatable(self, WaveMutators) :: any
end

-- ── Per-enemy stats and looks ───────────────────────────────────────────────

function WaveMutators.applyTo(self: State, f: any)
	if self.cleaned or self.applied[f] or f.side ~= self.ctx.enemySide then
		return
	end
	self.applied[f] = true
	local fx = self.ctx.fx
	local archetype = self.ctx.archetype(f)
	local combat = archetype ~= "Totem" and archetype ~= "Treasure"

	local swift = has(self, "swift")
	if swift and combat then
		permanentHaste(f, swift.Haste)
		-- A white trail at the feet.
		local root = f.model.PrimaryPart
		if root then
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Position = Vector3.new(-0.6, -f.lift + 0.4, 0)
			a1.Position = Vector3.new(0.6, -f.lift + 0.4, 0)
			a0.Parent = root
			a1.Parent = root
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(WHITE)
			trail.Transparency = NumberSequence.new(0.3, 1)
			trail.Lifetime = 0.4
			trail.LightEmission = 0.8
			trail.Parent = root
		end
	end

	local shielded = has(self, "shielded")
	if shielded and combat then
		local fraction = if self.ctx.wave >= shielded.LateWave then shielded.LateFraction else shielded.Fraction
		f.shieldHp = fraction * f.maxHp
		fx.tint(f.model, shielded.color, shielded.TintTime)
	end

	local frenzy = has(self, "frenzy")
	if frenzy and combat then
		permanentHaste(f, if f.boss then frenzy.BossHaste else frenzy.Haste)
		scaleHp(f, frenzy.Hp)
		local glow = highlight(f.model, frenzy.color, frenzy.PulseFrom, frenzy.color)
		TweenService:Create(glow, TweenInfo.new(frenzy.PulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { FillTransparency = frenzy.PulseTo }):Play()
	end

	local swarm = has(self, "swarm")
	if swarm and combat then
		scaleHp(f, swarm.Hp)
		f.damage *= swarm.Damage
		f.bonusCoins += swarm.Coins - 1
	end

	local champion = has(self, "champion")
	if champion and f.champion then
		scaleHp(f, champion.Hp)
		f.damage *= champion.Damage
		f.armor = math.max(f.armor, champion.Armor)
		f.bonusCoins += champion.Coins - 1
		if f.ai then
			f.ai.cooldownFactor = champion.CooldownFactor
		end
		local model = f.model
		if not model:GetAttribute("ChampionScaled") then
			-- (the wave preview may have scaled the model already; the lift grows either way)
			pcall(function()
				model:ScaleTo(model:GetScale() * champion.Size)
			end)
			model:SetAttribute("ChampionScaled", true)
		end
		f.lift *= champion.Size
		f.baseLift = f.lift
		highlight(model, champion.color, 0.7, Color3.fromRGB(255, 90, 60))
		local previewTag = model:FindFirstChild("ChampionTag", true)
		if previewTag then
			previewTag:Destroy() -- the wave preview's tag: one CHAMPION label in the fight, not two stacked
		end
		fx.mark(model, "CHAMPION", champion.color, FOREVER)
		self.champion = f
	end

	if self.enraged and combat then
		enrageOne(self, f) -- a late arrival in an enraged wave is enraged too
	end
end

-- ── World cues ──────────────────────────────────────────────────────────────

local function buildPuddles(self: State)
	local P = Mutators.Defs.poison
	local ctx = self.ctx
	local center = ctx.plot.arena.center
	local count = if ctx.wave >= P.LateWave then P.LateCount else P.Count
	local spots: { Vector3 } = {}
	for _, f in ctx.fighters do
		table.insert(spots, f.spot or f.pos)
	end
	for _ = 1, count do
		local best: Vector3? = nil
		local bestScore = -math.huge
		for _ = 1, 40 do
			local candidate = Vector3.new(center.X + ctx.rng:NextNumber(-P.BandX, P.BandX), center.Y, center.Z + ctx.rng:NextNumber(P.BandZMin, P.BandZMax))
			-- The smallest distance to another puddle (scaled to its gap) or a start spot: the farther the better.
			local score = math.huge
			for _, other in self.puddles do
				score = math.min(score, flatDist(candidate, other.pos) / P.MinGap)
			end
			for _, spot in spots do
				score = math.min(score, flatDist(candidate, spot) / P.SpotGap)
			end
			if score > bestScore then
				best, bestScore = candidate, score
			end
			if score >= 1 then
				break -- far enough from everything
			end
		end
		if best then
			local y = ctx.groundY(best)
			local part = ctx.fx.newPart(ctx.fxFolder, Vector3.new(0.3, P.Radius * 2, P.Radius * 2), CFrame.new(best.X, y, best.Z) * CFrame.Angles(0, 0, math.rad(90)), P.color, P.PulseFrom, Enum.PartType.Cylinder)
			TweenService:Create(part, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = P.PulseTo }):Play()
			local rim = ctx.fx.newPart(ctx.fxFolder, Vector3.new(0.2, P.Radius * 2 + 0.6, P.Radius * 2 + 0.6), CFrame.new(best.X, y - 0.05, best.Z) * CFrame.Angles(0, 0, math.rad(90)), P.color:Lerp(Color3.new(0, 0, 0), 0.4), 0.3, Enum.PartType.Cylinder)
			keep(self, part)
			keep(self, rim)
			table.insert(self.puddles, { pos = Vector3.new(best.X, y, best.Z), radius = P.Radius, part = part, bubbleIn = ctx.rng:NextNumber(0, P.BubbleEvery), pops = {} })
		end
	end
end

-- The data hazards the Mage walks around: one per puddle, placed once for the whole battle (the puddles never move,
-- and a re-added hazard would read as a new danger to the Mage).
local function puddleHazards(self: State)
	local P = Mutators.Defs.poison
	for _, puddle in self.puddles do
		self.ctx.addHazard(puddle.pos, puddle.radius, P.HazardTime, "puddle", nil)
	end
end

local function buildMoon(self: State)
	local R = Mutators.Defs.regen
	local ctx = self.ctx
	local center = ctx.plot.arena.center
	local moon = ctx.fx.newPart(ctx.fxFolder, Vector3.one * R.MoonSize, CFrame.new(center + Vector3.new(0, R.MoonHeight, 36)), R.color, 0.1, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = R.color
	light.Range = 40
	light.Brightness = 1.5
	light.Parent = moon
	keep(self, moon)
	-- A faint halo ring.
	local halo = ctx.fx.newPart(ctx.fxFolder, Vector3.new(0.4, R.MoonSize * 1.8, R.MoonSize * 1.8), CFrame.new(center + Vector3.new(0, R.MoonHeight, 36)) * CFrame.Angles(0, math.rad(90), 0), R.color, 0.75, Enum.PartType.Cylinder)
	keep(self, halo)
end

local function buildClouds(self: State)
	local S = Mutators.Defs.storm
	local ctx = self.ctx
	local center = ctx.plot.arena.center
	for i, x in { -25, 0, 25 } do
		local cloud = ctx.fx.newPart(ctx.fxFolder, Vector3.new(S.CloudSize, 2, S.CloudSize), CFrame.new(center + Vector3.new(x, S.CloudHeight + (i % 2) * 2, 5)), Color3.fromRGB(80, 84, 96), S.CloudTransparency)
		cloud.Material = Enum.Material.SmoothPlastic
		TweenService:Create(cloud, TweenInfo.new(6 + i, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = cloud.Position + Vector3.new(4, 0, 0) }):Play()
		keep(self, cloud)
	end
end

function WaveMutators.onStart(self: State)
	if self.cleaned then
		return
	end
	local ctx = self.ctx
	local clock = ctx.clock()
	for _, f in ctx.fighters do
		if isCombatEnemy(self, f) then
			self.initialEnemies += 1
		end
	end
	if self.champion then
		ctx.emit("waveEvent", { id = "champion", fighter = self.champion })
	end
	for _, f in ctx.fighters do
		if f.side == ctx.enemySide and f.hp > 0 and ctx.archetype(f) == "Treasure" then
			ctx.emit("waveEvent", { id = "treasure", fighter = f })
		end
	end
	if has(self, "poison") then
		buildPuddles(self)
		puddleHazards(self)
	end
	if has(self, "regen") then
		buildMoon(self)
	end
	local storm = has(self, "storm")
	if storm then
		buildClouds(self)
		self.stormAt = clock + storm.FirstAt
	end
	local ambush = has(self, "ambush")
	if ambush then
		self.ambushAt = clock + ambush.At
	end
	local enrage = has(self, "enrage")
	if enrage then
		self.enrageEndsAt = clock + (if ctx.wave >= enrage.LateWave then enrage.LateTime else enrage.Time)
	end
end

-- ── The timed twists ────────────────────────────────────────────────────────

local function stepPuddles(self: State, dt: number)
	local P = Mutators.Defs.poison
	local ctx = self.ctx
	local clock = ctx.clock()
	local hitPlayers = clock >= self.puddlePlayersAt
	if hitPlayers then
		self.puddlePlayersAt = clock + 0.5
	end
	for _, puddle in self.puddles do
		puddle.bubbleIn -= dt
		if puddle.bubbleIn <= 0 then
			puddle.bubbleIn = P.BubbleEvery
			local offset = Vector3.new(ctx.rng:NextNumber(-0.6, 0.6) * puddle.radius, 0.3, ctx.rng:NextNumber(-0.6, 0.6) * puddle.radius)
			local bubble = ctx.fx.newPart(ctx.fxFolder, Vector3.one * 0.7, CFrame.new(puddle.pos + offset), P.color:Lerp(WHITE, 0.3), 0.3, Enum.PartType.Ball)
			ctx.fx.fade(bubble, 0.7, { Position = puddle.pos + offset + UP * 3, Transparency = 1, Size = Vector3.one * 1.2 })
		end
		if hitPlayers then
			ctx.hitPlayers(puddle.pos, puddle.radius, P.PlayerDps * 0.5)
		end
		for _, f in ctx.fighters do
			if f.hp > 0 and flatDist(f.pos, puddle.pos) <= puddle.radius then
				-- The damage is collected per victim and paid as ONE hit per PayEvery seconds (with its green number):
				-- a per-tick hit would flood the Mage's reaction layer (fury, flinch) with chip damage.
				local acc = (puddle.pops[f] or 0) + f.maxHp * P.Dps * dt
				if acc >= f.maxHp * P.Dps * P.PayEvery then
					local taken = ctx.damage(f, acc, nil)
					ctx.popNumber(f, taken, P.color)
					acc = 0
				end
				puddle.pops[f] = acc
				if not (f.slowUntil > f.clock and f.slowFactor < P.Slow) then
					f.slowFactor = P.Slow
					f.slowUntil = f.clock + 0.3
				end
			end
		end
	end
end

local function stepRegen(self: State, dt: number)
	local R = Mutators.Defs.regen
	local ctx = self.ctx
	local clock = ctx.clock()
	local motes = 0
	for _, f in ctx.fighters do
		if f.side == ctx.enemySide and f.hp > 0 and f.hp < f.maxHp and clock >= f.lastHitAt + R.Delay then
			local at = self.regenAt[f] or clock
			if clock >= at then
				-- Paid once a second (a green number and a few motes), so a regenerating goblin is obvious.
				self.regenAt[f] = clock + R.MoteEvery
				ctx.heal(f, f.maxHp * R.Rate * R.MoteEvery)
				if motes < R.MotesPerTick then
					motes += 1
					ctx.fx.sparks(ctx.parent, f.pos, Mutators.Defs.totems.color, 3, 1.2, 3)
				end
			end
		else
			self.regenAt[f] = nil
		end
	end
end

local function stepTotems(self: State)
	local T = Mutators.Defs.totems
	local ctx = self.ctx
	local clock = ctx.clock()
	if clock < self.totemAt then
		return
	end
	self.totemAt = clock + T.PulseEvery
	for _, totem in ctx.fighters do
		if totem.side == ctx.enemySide and totem.hp > 0 and ctx.archetype(totem) == "Totem" then
			ctx.fx.groundRing(ctx.parent, totem.pos, T.color, T.Radius, 0.9)
			for _, f in ctx.fighters do
				if isCombatEnemy(self, f) and f.hp < f.maxHp and flatDist(f.pos, totem.pos) <= T.Radius then
					ctx.heal(f, f.maxHp * T.Rate * T.PulseEvery)
				end
			end
		end
	end
end

local function strike(self: State)
	local S = Mutators.Defs.storm
	local ctx = self.ctx
	local pool: { any } = {}
	local wantEnemy = ctx.rng:NextNumber() < S.EnemyBias
	for _, f in ctx.fighters do
		if f.hp > 0 and ((wantEnemy and isCombatEnemy(self, f)) or (not wantEnemy and f.side == ctx.playerSide)) then
			table.insert(pool, f)
		end
	end
	if #pool == 0 then
		for _, f in ctx.fighters do
			if f.hp > 0 then
				table.insert(pool, f)
			end
		end
	end
	if #pool == 0 then
		return
	end
	local target = pool[ctx.rng:NextInteger(1, #pool)]
	local pos = Vector3.new(target.pos.X, target.pos.Y, target.pos.Z) -- locked: the circle does not follow
	local groundY = ctx.groundY(pos)
	local parts = ctx.fx.warningCircle(ctx.fxFolder, pos, S.Radius, S.color, groundY)
	ctx.addHazard(pos, S.Radius, S.Warning, "storm", nil)
	ctx.emit("waveEvent", { id = "storm", pos = pos, at = ctx.clock() + S.Warning })
	ctx.schedule(S.Warning, function()
		for _, part in parts do
			part:Destroy()
		end
		if self.cleaned then
			return
		end
		ctx.fx.lightning(ctx.parent, pos + UP * 45, pos + UP * 0.5, S.color, 1.2)
		ctx.fx.lightning(ctx.parent, pos + UP * 45 + Vector3.new(2, 0, 3), pos + UP * 0.5, WHITE, 0.5)
		ctx.fx.groundRing(ctx.parent, pos, S.color, S.Radius, 0.45)
		ctx.fx.sparks(ctx.parent, pos, WHITE, 10, S.Radius * 0.6, 6)
		for _, f in ctx.fighters do
			if f.hp > 0 and flatDist(f.pos, pos) <= S.Radius then
				ctx.hurt(f, f.maxHp * (if f.boss then S.BossDamage else S.Damage), nil, S.color)
			end
		end
		ctx.hitPlayers(pos, S.Radius, S.PlayerDamage)
	end)
end

local function stepStorm(self: State)
	local S = Mutators.Defs.storm
	local clock = self.ctx.clock()
	if clock >= self.stormAt then
		self.stormAt = clock + (if self.ctx.wave >= S.LateWave then S.LateEvery else S.Every)
		strike(self)
	end
end

local function ambush(self: State)
	local A = Mutators.Defs.ambush
	local ctx = self.ctx
	self.ambushDone = true
	local kind = ctx.summonKind
	if not kind then
		return
	end
	local center = ctx.plot.arena.center
	local points = { center + Vector3.new(-A.SideX, 0, A.SideZ), center + Vector3.new(A.SideX, 0, A.SideZ) }
	local count = if ctx.wave >= A.CountWaves[2] then A.Count[3] elseif ctx.wave >= A.CountWaves[1] then A.Count[2] else A.Count[1]
	local parts: { Instance } = {}
	for _, point in points do
		for _, part in ctx.fx.warningCircle(ctx.fxFolder, point, A.Radius, A.color, ctx.groundY(point)) do
			table.insert(parts, part)
		end
		ctx.addHazard(point, A.Radius, A.Warning, "ambush", nil)
	end
	ctx.notify("AMBUSH!")
	ctx.emit("waveEvent", { id = "ambush", points = points, at = ctx.clock() + A.Warning })
	ctx.schedule(A.Warning, function()
		for _, part in parts do
			part:Destroy()
		end
		if self.cleaned then
			return
		end
		for i = 1, count do
			local point = points[(i - 1) % 2 + 1]
			local pos = point + Vector3.new(0, 0, ((i - 1) // 2) * 3)
			ctx.spawnEnemy(kind, ctx.summonTier, pos)
		end
	end)
end

local function stepAmbush(self: State)
	if self.ambushDone then
		return
	end
	local A = Mutators.Defs.ambush
	if self.ctx.clock() >= self.ambushAt or (self.initialEnemies > 0 and self.deaths >= self.initialEnemies * A.HalfDead) then
		ambush(self)
	end
end

local function enrageAll(self: State)
	local ctx = self.ctx
	self.enraged = true
	for _, f in ctx.fighters do
		if isCombatEnemy(self, f) then
			enrageOne(self, f)
		end
	end
	ctx.notify("ENRAGED!")
	ctx.fx.groundRing(ctx.parent, ctx.plot.arena.center + Vector3.new(0, 0, 10), Mutators.Defs.enrage.color, 30, 0.8)
	if not ctx.riftActive() then
		ctx.sendBossHp("", 0, false)
	end
end

local function stepEnrage(self: State)
	local E = Mutators.Defs.enrage
	local ctx = self.ctx
	if self.enraged then
		return
	end
	local clock = ctx.clock()
	local remaining = self.enrageEndsAt - clock
	if remaining <= 0 then
		enrageAll(self)
		return
	end
	if remaining <= E.WarnAt and not self.enrageWarned then
		self.enrageWarned = true
		ctx.notify(string.format("Enrage in %d seconds!", E.WarnAt))
	end
	if clock >= self.enrageBarAt and not ctx.riftActive() then
		self.enrageBarAt = clock + E.BarEvery
		local total = if ctx.wave >= E.LateWave then E.LateTime else E.Time
		ctx.sendBossHp(string.format("ENRAGE IN %ds", math.ceil(remaining)), math.clamp(remaining / total, 0.01, 1), remaining <= E.WarnAt)
	end
end

local function stepChampion(self: State)
	local C = Mutators.Defs.champion
	local ctx = self.ctx
	local champion = self.champion
	if not champion or has(self, "enrage") or ctx.riftActive() then
		return -- the bar belongs to the enrage timer / the Rift King
	end
	local clock = ctx.clock()
	if clock < self.championBarAt then
		return
	end
	self.championBarAt = clock + C.BarEvery
	if champion.hp <= 0 then
		ctx.sendBossHp("", 0, false)
		self.champion = nil
		return
	end
	local def = Enemies.Kinds[champion.kind]
	ctx.sendBossHp("CHAMPION · " .. (if def then def.label else "Goblin"), champion.hp / champion.maxHp, false)
end

local function stepTreasure(self: State)
	if self.treasureGone then
		return
	end
	local T = Mutators.Defs.treasure
	local ctx = self.ctx
	if ctx.clock() < T.EscapeAt then
		return
	end
	for _, f in ctx.fighters do
		if f.side == ctx.enemySide and f.hp > 0 and ctx.archetype(f) == "Treasure" then
			-- Gone: no coins, no kill event (the death loop only removes the record).
			self.treasureGone = true
			f.noReward = true
			f.killEmitted = true
			f.hp = 0
			ctx.flash(f, f.pos)
			ctx.fx.pop(ctx.fxFolder, f.pos + UP * (f.lift + 2), "BYE!", T.color, 24)
			f.model:Destroy()
			ctx.notify("The treasure goblin escaped!")
		end
	end
end

function WaveMutators.step(self: State, dt: number)
	if self.cleaned then
		return
	end
	if #self.puddles > 0 then
		stepPuddles(self, dt)
	end
	if has(self, "regen") then
		stepRegen(self, dt)
	end
	if has(self, "totems") then
		stepTotems(self)
	end
	if has(self, "storm") then
		stepStorm(self)
	end
	if has(self, "ambush") then
		stepAmbush(self)
	end
	if has(self, "enrage") then
		stepEnrage(self)
	end
	if has(self, "treasure") then
		stepTreasure(self)
	end
	if self.champion then
		stepChampion(self)
	end
end

-- ── Deaths ──────────────────────────────────────────────────────────────────

local function explode(self: State, f: any)
	local V = Mutators.Defs.volatile
	local ctx = self.ctx
	local pos = f.pos
	local center = pos + UP * math.max(1, f.lift)
	-- The warning: the body glows orange and a ball swells over it for Delay seconds.
	if f.model.Parent then
		local glow = highlight(f.model, V.color, 0.3, V.color)
		Debris:AddItem(glow, V.Delay + 0.1)
	end
	local ball = ctx.fx.newPart(ctx.fxFolder, Vector3.one * 1.5, CFrame.new(center), V.color, 0.3, Enum.PartType.Ball)
	ctx.fx.fade(ball, V.Delay, { Size = Vector3.one * 4.5, Transparency = 0.05 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local parts = ctx.fx.warningCircle(ctx.fxFolder, pos, V.Radius, V.color, ctx.groundY(pos))
	ctx.addHazard(pos, V.Radius, V.Delay, "volatile", nil)
	local damage = f.damage
	ctx.schedule(V.Delay, function()
		for _, part in parts do
			part:Destroy()
		end
		if self.cleaned then
			return
		end
		ctx.fx.groundRing(ctx.parent, pos, V.color, V.Radius, 0.45)
		local flash = ctx.fx.newPart(ctx.parent, Vector3.one * 2, CFrame.new(center), Color3.fromRGB(255, 230, 160), 0.1, Enum.PartType.Ball)
		ctx.fx.fade(flash, 0.35, { Size = Vector3.one * V.Radius * 1.8, Transparency = 1 })
		ctx.fx.sparks(ctx.parent, pos, V.color, 14, V.Radius, 6)
		for _, other in ctx.fighters do
			if other.hp > 0 and other ~= f and flatDist(other.pos, pos) <= V.Radius then
				if other.side == ctx.playerSide then
					ctx.hurt(other, damage * V.SquadMult, nil, V.color)
				elseif ctx.archetype(other) ~= "Totem" then
					ctx.hurt(other, other.maxHp * V.EnemyFraction, nil, V.color) -- chains through the next death
				end
			end
		end
		ctx.hitPlayers(pos, V.Radius, V.PlayerDamage)
	end)
end

function WaveMutators.onDeath(self: State, f: any)
	if self.cleaned or f.side ~= self.ctx.enemySide then
		return
	end
	local archetype = self.ctx.archetype(f)
	if archetype == "Treasure" then
		if not f.noReward then
			self.bonusDrop = true
			self.ctx.notify("Treasure goblin caught — bonus drop!")
			self.ctx.fx.sparks(self.ctx.parent, f.pos, Mutators.Defs.treasure.color, 16, 3, 6)
			self.ctx.fx.pop(self.ctx.fxFolder, f.pos + UP * (f.lift + 2), "JACKPOT!", Mutators.Defs.treasure.color, 28)
		end
		return
	end
	if archetype == "Totem" then
		return
	end
	self.deaths += 1
	if has(self, "volatile") and not f.noReward then
		explode(self, f)
	end
end

function WaveMutators.onEvent(_self: State, _name: string, _payload: any)
	-- Nothing yet: the twists read the battle directly in step() / onDeath().
end

function WaveMutators.cleanup(self: State)
	if self.cleaned then
		return
	end
	self.cleaned = true
	for _, part in self.parts do
		part:Destroy()
	end
	table.clear(self.parts)
	table.clear(self.puddles)
	if (has(self, "enrage") or self.champion) and not self.ctx.riftActive() then
		self.ctx.sendBossHp("", 0, false)
	end
end

return WaveMutators
