--!strict
-- Bojová AI jednotky MÁG: jedna instance (brain) na mága v bitvě. BattleService ji volá každý tick simulace
-- (brain:update(dt)); mág tím přebírá svůj pohyb i útok místo výchozího „jdi k nejbližšímu a tluč“.
--
-- UTILITY AI: každých 0,2–0,4 s (náhodný posun) brain ohodnotí možné akce skóre 0–1 a vybere nejlepší,
-- s malou setrvačností pro aktuální akci:
--   attack   základní kouzlo na vybraný cíl (v dosahu)
--   strong   silné kouzlo: AoE do těžiště shluku nepřátel, řetěz, singularita, nebo dorážka cíle s nízkým HP
--   retreat  kiting: nepřítel na blízko je nebezpečný (nebo mág stojí v telegrafované ploše) → couvá šikmo
--   shield   bariéra při nízkém HP nebo hrozbě
--   blink    teleport, když je obklíčený
--   support  léčení spojence s nejnižším HP (od levelu 21)
--   approach přiblížení na optimální vzdálenost, když nemá cíl v dosahu
--   idle     krátká pauza, otočení k hrozbě
-- Výběr cíle je vážený (blízkost, nízké HP, nenávist k tomu, kdo mě zranil, typ nepřítele) s pamětí: cíl drží
-- 1,5 s, pokud není nový výrazně lepší; na změnu reaguje s reakční dobou podle levelu a občas „lidsky“ zaváhá.
-- Silná kouzla mají telegraf: krystal hole zesílí (světlo i velikost) a paže se zvedne, pak teprve výstřel.
-- Čísla: shared/Config/MageConfig.luau, kouzla: shared/Config/MageSpells.luau.
--
-- Poznámka k animaci castu: zvednutí paže se dělá přes C0 ramenního Motor6D RELATIVNĚ k uložené klidové póze
-- a po castu se C0 vrací přesně zpět (Transform každý snímek přepisuje animace idle, C0 ne). Zapečená póza
-- modelu tím zůstává.

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.MageConfig)
local Spells = require(Shared.Config.MageSpells)
local Rig = require(Shared.Rig)

local UP = Vector3.new(0, 1, 0)

-- Co brain dostává od BattleService: záznamy bojovníků (side, hp, maxHp, pos, range, speed, cooldown, timer,
-- clock, damage, model, slowUntil, slowFactor, shieldUntil, shieldReduction, kind) a pomocné funkce.
export type Context = {
	fighters: { any },
	parent: Instance,
	playerSide: number,
	attack: (f: any, target: any, mult: number) -> (), -- standardní zásah (pasivky, splash, efekt střely)
	damage: (target: any, amount: number) -> number,
	popNumber: (target: any, amount: number, color: Color3?) -> (),
	face: (f: any, target: Vector3) -> (),
	bounds: { center: Vector3, halfX: number, halfZ: number },
	hazards: () -> { { pos: Vector3, radius: number } },
	archetype: (f: any) -> string?,
}

type Cast = { spell: Spells.Spell, at: number, target: any?, point: Vector3? }

export type Brain = {
	ctx: Context,
	f: any,
	level: number,
	basic: Spells.Spell,
	spells: { Spells.Spell },
	cooldownReady: { [string]: number }, -- id → čas bitvy, kdy je kouzlo zase k dispozici
	mana: number,
	thinkIn: number,
	lastThinkAt: number,
	action: string,
	actionScore: number,
	target: any?,
	targetSince: number,
	pendingTarget: any?,
	pendingAt: number,
	hate: { [any]: number },
	lastPos: { [any]: Vector3 },
	velocity: { [any]: Vector3 },
	casting: Cast?,
	hesitateUntil: number,
	retreatStarted: number, -- kdy začalo aktuální couvání (couvá v krátkých dávkách, pak zase střílí)
	noRetreatUntil: number, -- po dávce couvání chvíli necouvá (jinak by kitoval donekonečna a nestřílel)
	strafeSign: number,
	shoulderRest: CFrame?,
	debugLabel: TextLabel?,
	update: (self: Brain, dt: number) -> (),
	onDamaged: (self: Brain, attacker: any) -> (),
	destroy: (self: Brain) -> (),
}

local MageBrain = {}
MageBrain.__index = MageBrain

-- ── Pomocné ─────────────────────────────────────────────────────────────────

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function lerpByLevel(level: number, a: number, b: number): number
	return a + (b - a) * math.clamp((level - 1) / 29, 0, 1)
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function neon(parent: Instance, size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): Part
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

local function fade(part: BasePart, duration: number, goal: { [string]: any })
	TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(part, duration + 0.1)
end

-- Prstenec na zemi, který se roztáhne a zmizí.
local function groundRing(parent: Instance, position: Vector3, color: Color3, radius: number, duration: number)
	local ring = neon(parent, Vector3.new(0.3, 1, 1), CFrame.new(position + UP * 0.3) * CFrame.Angles(0, 0, math.rad(90)), color, 0.2, Enum.PartType.Cylinder)
	fade(ring, duration, { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 })
end

-- Paprsek mezi dvěma body (tenký Neon kvádr), zmizí.
local function beam(parent: Instance, a: Vector3, b: Vector3, color: Color3, width: number, duration: number)
	local length = (b - a).Magnitude
	if length < 0.1 then
		return
	end
	local segment = neon(parent, Vector3.new(width, width, length), CFrame.lookAt((a + b) / 2, b), color, 0)
	fade(segment, duration, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, length) })
end

-- Jiskry z bodu.
local function sparks(parent: Instance, position: Vector3, color: Color3, count: number, spread: number, height: number)
	for _ = 1, count do
		local angle = math.random() * math.pi * 2
		local distance = spread * (0.3 + math.random() * 0.7)
		local spark = neon(parent, Vector3.one * (0.3 + math.random() * 0.4), CFrame.new(position + UP), color, 0, Enum.PartType.Ball)
		fade(spark, 0.45 + math.random() * 0.35, {
			Position = position + Vector3.new(math.cos(angle) * distance, height * (0.4 + math.random() * 0.6), math.sin(angle) * distance),
			Transparency = 1,
			Size = Vector3.one * 0.1,
		})
	end
end

-- ── Vytvoření ───────────────────────────────────────────────────────────────

function MageBrain.new(ctx: Context, fighter: any, level: number): Brain
	local basic, spells = Spells.forLevel(level)
	local self: Brain = setmetatable({
		ctx = ctx,
		f = fighter,
		level = level,
		basic = basic,
		spells = spells,
		cooldownReady = {},
		mana = Config.Mana.Start,
		thinkIn = math.random() * Config.ThinkInterval[2], -- první myšlenka s náhodným posunem
		lastThinkAt = 0,
		action = "idle",
		actionScore = 0,
		target = nil,
		targetSince = 0,
		pendingTarget = nil,
		pendingAt = 0,
		hate = {},
		lastPos = {},
		velocity = {},
		casting = nil,
		hesitateUntil = 0,
		retreatStarted = -1,
		noRetreatUntil = 0,
		strafeSign = if math.random() < 0.5 then -1 else 1,
		shoulderRest = nil,
		debugLabel = nil,
	}, MageBrain) :: any
	local upperArm = fighter.model:FindFirstChild("RightUpperArm")
	local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder")
	if shoulder and shoulder:IsA("Motor6D") then
		self.shoulderRest = shoulder.C0
	end
	return self
end

-- Zranil mě: krátkodobá nenávist (vyprchává), kterou výběr cíle započítá.
function MageBrain.onDamaged(self: Brain, attacker: any)
	self.hate[attacker] = (self.hate[attacker] or 0) + Config.HateGain
end

function MageBrain.destroy(self: Brain)
	local label = self.debugLabel
	if label then
		local gui = label.Parent
		if gui then
			gui:Destroy()
		end
		self.debugLabel = nil
	end
end

-- ── Přehledy o bojišti ──────────────────────────────────────────────────────

local function enemiesOf(self: Brain): { any }
	local list = {}
	for _, other in self.ctx.fighters do
		if other.side ~= self.f.side and other.hp > 0 then
			table.insert(list, other)
		end
	end
	return list
end

local function alliesOf(self: Brain): { any }
	local list = {}
	for _, other in self.ctx.fighters do
		if other ~= self.f and other.side == self.f.side and other.hp > 0 then
			table.insert(list, other)
		end
	end
	return list
end

local function nearest(from: Vector3, list: { any }): (any?, number)
	local best, bestDist = nil, math.huge
	for _, other in list do
		local d = (flat(other.pos) - flat(from)).Magnitude
		if d < bestDist then
			best, bestDist = other, d
		end
	end
	return best, bestDist
end

-- Místo uvnitř plošiny (okraj s rezervou).
local function clampToArena(self: Brain, pos: Vector3): Vector3
	local b = self.ctx.bounds
	local m = Config.ArenaMargin
	return Vector3.new(
		math.clamp(pos.X, b.center.X - b.halfX + m, b.center.X + b.halfX - m),
		pos.Y,
		math.clamp(pos.Z, b.center.Z - b.halfZ + m, b.center.Z + b.halfZ - m)
	)
end

-- Telegrafovaná plocha nepřítele, ve které mág stojí (nebo nil).
local function hazardAt(self: Brain, pos: Vector3): { pos: Vector3, radius: number }?
	for _, hazard in self.ctx.hazards() do
		if (flat(hazard.pos) - flat(pos)).Magnitude <= hazard.radius + 1 then
			return hazard
		end
	end
	return nil
end

-- Nejlepší shluk nepřátel pro plošné kouzlo: střed a počet (předpověď podle rychlosti o `ahead` sekund).
local function bestCluster(self: Brain, enemies: { any }, radius: number, maxRange: number, ahead: number): (Vector3?, number)
	local bestCenter, bestCount = nil, 0
	for _, center in enemies do
		local predicted = center.pos + (self.velocity[center] or Vector3.zero) * ahead * Config.Lead.Factor
		if (flat(predicted) - flat(self.f.pos)).Magnitude > maxRange then
			continue
		end
		local count, sum = 0, Vector3.zero
		for _, other in enemies do
			local otherPredicted = other.pos + (self.velocity[other] or Vector3.zero) * ahead * Config.Lead.Factor
			if (flat(otherPredicted) - flat(predicted)).Magnitude <= radius then
				count += 1
				sum += otherPredicted
			end
		end
		if count > bestCount then
			bestCount = count
			bestCenter = sum / count
		end
	end
	return bestCenter, bestCount
end

local function spellReady(self: Brain, spell: Spells.Spell): boolean
	return (self.cooldownReady[spell.id] or 0) <= self.f.clock and self.mana >= spell.mana
end

local function spellOfKind(self: Brain, kind: string): Spells.Spell?
	for _, spell in self.spells do
		if spell.kind == kind and spellReady(self, spell) then
			return spell
		end
	end
	return nil
end

-- ── Výběr cíle ─────────────────────────────────────────────────────────────

local function targetScore(self: Brain, enemy: any, maxRange: number): number
	local w = Config.Target
	local dist = (flat(enemy.pos) - flat(self.f.pos)).Magnitude
	local proximity = clamp01(1 - dist / math.max(maxRange * 1.5, 1))
	local lowHp = clamp01(1 - enemy.hp / math.max(enemy.maxHp, 1))
	local hate = clamp01((self.hate[enemy] or 0) / 3)
	local archetype = self.ctx.archetype(enemy)
	local typePriority = (archetype and Config.TypePriority[archetype]) or 0.4
	return proximity * w.Proximity + lowHp * w.LowHp + hate * w.Hate + typePriority * w.Type
end

local function chooseTarget(self: Brain, enemies: { any })
	local clock = self.f.clock
	local current = self.target
	if current and current.hp <= 0 then
		current = nil
		self.target = nil
	end
	local maxRange = self.f.range
	local best, bestScore = nil, -1
	for _, enemy in enemies do
		local score = targetScore(self, enemy, maxRange)
		if score > bestScore then
			best, bestScore = enemy, score
		end
	end
	if not best then
		self.target = nil
		return
	end
	if not current then
		self.target = best -- bez cíle hned (i tak s reakční dobou při prvním castu přes think interval)
		self.targetSince = clock
		self.pendingTarget = nil
		return
	end
	if best == current then
		self.pendingTarget = nil
		return
	end
	-- Jiný cíl je lepší: drží aktuální aspoň TargetHold, pokud nový není výrazně lepší; a reaguje až po reakční době.
	local currentScore = targetScore(self, current, maxRange)
	local held = clock - self.targetSince < Config.TargetHold
	if held and bestScore < currentScore + Config.SwitchMargin then
		self.pendingTarget = nil
		return
	end
	if self.pendingTarget ~= best then
		self.pendingTarget = best
		self.pendingAt = clock + lerpByLevel(self.level, Config.ReactionTime.L1, Config.ReactionTime.L30)
		return
	end
	if clock >= self.pendingAt then
		self.target = best
		self.targetSince = clock
		self.pendingTarget = nil
	end
end

-- ── Cast (telegraf, výstřel, vyhodnocení) ──────────────────────────────────

local function weaponLights(self: Brain): { PointLight }
	local lights = {}
	local weapon = self.f.model:FindFirstChild("Weapon")
	if weapon then
		for _, piece in weapon:GetChildren() do
			local light = piece:FindFirstChildOfClass("PointLight")
			if light then
				table.insert(lights, light)
			end
		end
	end
	return lights
end

local function staffTip(self: Brain): Vector3
	local weapon = self.f.model:FindFirstChild("Weapon")
	local best: Vector3? = nil
	local topY = -math.huge
	if weapon then
		for _, piece in weapon:GetChildren() do
			if piece:IsA("BasePart") and piece.Name == "Piece" and piece.Position.Y > topY then
				topY = piece.Position.Y
				best = piece.Position
			end
		end
	end
	return best or (self.f.pos + UP * (self.f.lift + 1))
end

-- Telegraf: krystaly zesílí a zvětší se, paže se zvedne; po `duration` zpět.
local function telegraph(self: Brain, duration: number, strong: boolean)
	local t = Config.Telegraph
	for _, light in weaponLights(self) do
		local brightness, range = light.Brightness, light.Range
		TweenService:Create(light, TweenInfo.new(duration * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = brightness * (if strong then t.Brightness else 1.6), Range = range * (if strong then t.Range else 1.25) }):Play()
		local piece = light.Parent
		if piece and piece:IsA("BasePart") and strong then
			local size = piece.Size
			TweenService:Create(piece, TweenInfo.new(duration * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = size * t.Scale }):Play()
			task.delay(duration, function()
				if piece.Parent then
					TweenService:Create(piece, TweenInfo.new(0.3), { Size = size }):Play()
				end
			end)
		end
		task.delay(duration, function()
			if light.Parent then
				TweenService:Create(light, TweenInfo.new(0.3), { Brightness = brightness, Range = range }):Play()
			end
		end)
	end
	local upperArm = self.f.model:FindFirstChild("RightUpperArm")
	local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder")
	local rest = self.shoulderRest
	if shoulder and shoulder:IsA("Motor6D") and rest then
		local raise = CFrame.Angles(math.rad(Config.ArmRaise), 0, 0)
		TweenService:Create(shoulder, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest * raise }):Play()
		task.delay(duration, function()
			if not shoulder.Parent then
				return
			end
			-- Zpětný ráz a návrat do klidové pózy.
			TweenService:Create(shoulder, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest * CFrame.Angles(math.rad(Config.ArmRaise + 22), 0, 0) }):Play()
			task.delay(0.3, function()
				if shoulder.Parent then
					TweenService:Create(shoulder, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = rest }):Play()
				end
			end)
		end)
	end
end

local function castTime(self: Brain, spell: Spells.Spell): number
	return spell.castTime * (1 - 0.3 * clamp01((self.level - 1) / 29)) -- vyšší level sesílá rychleji
end

local function startCast(self: Brain, spell: Spells.Spell, target: any?, point: Vector3?)
	local duration = castTime(self, spell)
	self.mana -= spell.mana
	if spell.cooldown > 0 then
		self.cooldownReady[spell.id] = self.f.clock + spell.cooldown
	end
	self.casting = { spell = spell, at = self.f.clock + duration, target = target, point = point }
	telegraph(self, duration, not spell.basic)
	if point then
		self.ctx.face(self.f, point)
	elseif target then
		self.ctx.face(self.f, target.pos)
	end
	Rig.setMoving(self.f.model, false)
end

-- Vyhodnocení kouzla po castu. Cíl mohl mezitím zemřít nebo zmizet: pak se hledá náhradní, nebo kouzlo vyšumí.
local function resolve(self: Brain, cast: Cast)
	local f, ctx = self.f, self.ctx
	local spell = cast.spell
	local parent = ctx.parent
	if not parent.Parent or f.hp <= 0 then
		return
	end
	local enemies = enemiesOf(self)
	local tip = staffTip(self)

	if spell.kind == "bolt" then
		local target = cast.target
		if not target or target.hp <= 0 then
			target = nearest(f.pos, enemies)
		end
		if target and (flat(target.pos) - flat(f.pos)).Magnitude <= f.range + 3 then
			ctx.attack(f, target, spell.damage)
		end
	elseif spell.kind == "aoe" then
		local point = cast.point or (cast.target and cast.target.pos)
		if not point then
			return
		end
		local radius = spell.radius or 6
		-- Efekt: paprsek z krystalu, záblesk, prstenec a sloupy světla po okraji.
		beam(parent, tip, point + UP * 1.5, spell.color, 0.6, 0.25)
		groundRing(parent, point, spell.color, radius, 0.5)
		local flash = neon(parent, Vector3.one * 2, CFrame.new(point + UP * 1.5), spell.color2, 0.1, Enum.PartType.Ball)
		fade(flash, 0.4, { Size = Vector3.one * radius * 1.4, Transparency = 1, Color = spell.color })
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			local pillarPos = point + Vector3.new(math.cos(angle) * radius * 0.8, 4, math.sin(angle) * radius * 0.8)
			local pillar = neon(parent, Vector3.new(0.4, 8, 0.4), CFrame.new(pillarPos), spell.color2, 0.3)
			fade(pillar, 0.5, { Transparency = 1, Size = Vector3.new(0.1, 10, 0.1) })
		end
		sparks(parent, point, spell.color, 12, radius, 6)
		for _, enemy in enemies do
			if (flat(enemy.pos) - flat(point)).Magnitude <= radius then
				local taken = ctx.damage(enemy, f.damage * spell.damage)
				ctx.popNumber(enemy, taken)
				if spell.slow then
					enemy.slowUntil = enemy.clock + spell.slow.time
					enemy.slowFactor = spell.slow.factor
				end
			end
		end
	elseif spell.kind == "chain" then
		local target = cast.target
		if not target or target.hp <= 0 then
			target = nearest(f.pos, enemies)
		end
		if not target then
			return
		end
		local hit: { [any]: boolean } = {}
		local from = tip
		local current = target
		for _ = 1, (spell.jumps or 3) do
			if not current then
				break
			end
			hit[current] = true
			beam(parent, from, current.pos + UP * current.lift, spell.color, 0.5, 0.3)
			beam(parent, from, current.pos + UP * current.lift, spell.color2, 0.2, 0.3)
			sparks(parent, current.pos, spell.color, 5, 2, 3)
			ctx.popNumber(current, ctx.damage(current, f.damage * spell.damage))
			from = current.pos + UP * current.lift
			local nextTarget, nextDist = nil, math.huge
			for _, enemy in enemies do
				if not hit[enemy] then
					local d = (flat(enemy.pos) - flat(current.pos)).Magnitude
					if d <= (spell.radius or 9) and d < nextDist then
						nextTarget, nextDist = enemy, d
					end
				end
			end
			current = nextTarget
		end
	elseif spell.kind == "shield" then
		local shield = spell.shield
		if shield then
			f.shieldUntil = f.clock + shield.time
			f.shieldReduction = shield.reduction
			local sphere = neon(parent, Vector3.one * 6, CFrame.new(f.pos + UP * f.lift), spell.color, 0.6, Enum.PartType.Ball)
			local weld = Instance.new("WeldConstraint") -- bublina jede s mágem
			local root = f.model.PrimaryPart
			if root then
				sphere.Anchored = false
				sphere.Massless = true
				weld.Part0 = root
				weld.Part1 = sphere
				weld.Parent = sphere
			end
			TweenService:Create(sphere, TweenInfo.new(0.3), { Transparency = 0.75 }):Play()
			task.delay(shield.time - 0.3, function()
				if sphere.Parent then
					fade(sphere, 0.3, { Transparency = 1, Size = Vector3.one * 7 })
				end
			end)
			Debris:AddItem(sphere, shield.time + 0.1)
		end
	elseif spell.kind == "heal" then
		local allies = alliesOf(self)
		local best, bestFrac = nil, math.huge
		for _, ally in allies do
			local frac = ally.hp / math.max(ally.maxHp, 1)
			if frac < bestFrac and (flat(ally.pos) - flat(f.pos)).Magnitude <= (spell.radius or 30) then
				best, bestFrac = ally, frac
			end
		end
		if best and spell.heal then
			local amount = best.maxHp * spell.heal
			best.hp = math.min(best.maxHp, best.hp + amount)
			ctx.popNumber(best, amount, spell.color)
			beam(parent, tip, best.pos + UP * best.lift, spell.color, 0.4, 0.3)
			groundRing(parent, best.pos, spell.color, 4, 0.5)
			sparks(parent, best.pos, spell.color, 10, 2.5, 5)
		end
	elseif spell.kind == "blink" then
		local threat = nearest(f.pos, enemies)
		local away = if threat then (flat(f.pos) - flat(threat.pos)) else Vector3.new(0, 0, -1)
		if away.Magnitude < 0.1 then
			away = Vector3.new(0, 0, -1)
		end
		local destination = clampToArena(self, f.pos + away.Unit * (spell.blink or 12))
		local from = f.pos + UP * f.lift
		local flashA = neon(parent, Vector3.one * 2, CFrame.new(from), spell.color, 0.1, Enum.PartType.Ball)
		fade(flashA, 0.35, { Size = Vector3.one * 6, Transparency = 1 })
		f.pos = Vector3.new(destination.X, f.pos.Y, destination.Z)
		f.model:PivotTo(CFrame.new(f.pos + UP * f.lift) * (f.model:GetPivot() - f.model:GetPivot().Position))
		local flashB = neon(parent, Vector3.one * 2, CFrame.new(f.pos + UP * f.lift), spell.color2, 0.1, Enum.PartType.Ball)
		fade(flashB, 0.35, { Size = Vector3.one * 6, Transparency = 1 })
		sparks(parent, f.pos, spell.color, 8, 2, 4)
	elseif spell.kind == "pull" then
		local point = cast.point
		if not point then
			return
		end
		local radius = spell.radius or 10
		local core = neon(parent, Vector3.one * 1.5, CFrame.new(point + UP * 3), Color3.new(0.05, 0, 0.1), 0, Enum.PartType.Ball)
		fade(core, 0.8, { Size = Vector3.one * 5, Transparency = 1 })
		groundRing(parent, point, spell.color, radius, 0.7)
		for _, enemy in enemies do
			local toCenter = flat(point) - flat(enemy.pos)
			local d = toCenter.Magnitude
			if d <= radius then
				beam(parent, enemy.pos + UP * enemy.lift, point + UP * 3, spell.color2, 0.25, 0.4)
				if d > 1 then
					local step = math.min(spell.pull or 6, d - 1)
					enemy.pos += toCenter.Unit * step
				end
				ctx.popNumber(enemy, ctx.damage(enemy, f.damage * spell.damage))
			end
		end
	end
end

-- ── Rozhodování ─────────────────────────────────────────────────────────────

local function think(self: Brain)
	local f, ctx = self.f, self.ctx
	local clock = f.clock
	local since = math.max(clock - self.lastThinkAt, 0.05)
	self.lastThinkAt = clock
	local enemies = enemiesOf(self)

	-- Rychlosti nepřátel (předstih střelby) a vyprchávání nenávisti.
	for _, enemy in enemies do
		local last = self.lastPos[enemy]
		self.velocity[enemy] = if last then (enemy.pos - last) / since else Vector3.zero
		self.lastPos[enemy] = enemy.pos
	end
	for who, value in self.hate do
		local decayed = value - Config.HateDecay * since
		if decayed <= 0 or who.hp <= 0 then
			self.hate[who] = nil
		else
			self.hate[who] = decayed
		end
	end

	chooseTarget(self, enemies)
	local target = self.target
	local range = f.range
	local U = Config.Utility
	local nearestEnemy, nearestDist = nearest(f.pos, enemies)
	local dangerCount = 0
	for _, enemy in enemies do
		if (flat(enemy.pos) - flat(f.pos)).Magnitude <= Config.KiteDistance then
			dangerCount += 1
		end
	end
	local hpFrac = f.hp / math.max(f.maxHp, 1)
	local hazard = hazardAt(self, f.pos)
	local targetDist = if target then (flat(target.pos) - flat(f.pos)).Magnitude else math.huge

	-- Skóre akcí.
	local scores: { [string]: number } = {}
	scores.idle = U.IdleScore
	scores.attack = if target and targetDist <= range then U.AttackBase + 0.15 * clamp01(1 - targetDist / range) else 0
	scores.approach = if target and targetDist > range then U.ApproachBase else 0
	-- Kiting v dávkách: couvá nejvýš RetreatBurst sekund, pak RetreatPause sekund couvat nechce (střílí), jinak by
	-- před rychlými nepřáteli utíkal donekonečna. Telegrafovaná plocha nebo nízké HP dávky přebíjejí.
	scores.retreat = 0
	if hazard then
		scores.retreat = U.HazardRetreat
	elseif nearestEnemy and nearestDist < Config.KiteDistance then
		scores.retreat = U.RetreatBase + 0.3 * clamp01(1 - nearestDist / Config.KiteDistance)
		local inBurst = self.action == "retreat" and self.retreatStarted >= 0 and clock - self.retreatStarted <= Config.RetreatBurst
		if self.action == "retreat" and not inBurst and hpFrac > 0.4 then
			self.noRetreatUntil = clock + Config.RetreatPause
		end
		if clock < self.noRetreatUntil and hpFrac > 0.4 and not inBurst then
			scores.retreat *= 0.3
		end
	end
	local shieldSpell = spellOfKind(self, "shield")
	scores.shield = if shieldSpell and (hpFrac < U.ShieldBelowHp or (dangerCount >= 2 and hpFrac < 0.6)) then U.ShieldScore else 0
	local blinkSpell = spellOfKind(self, "blink")
	scores.blink = if blinkSpell and dangerCount >= Config.SurroundedCount then U.BlinkScore else 0
	-- Silné kouzlo: AoE / singularita do shluku, řetěz, nebo dorážka.
	local strongSpell: Spells.Spell? = nil
	local strongPoint: Vector3? = nil
	scores.strong = 0
	for _, spell in self.spells do
		if not spellReady(self, spell) then
			continue
		end
		local score = 0
		local point: Vector3? = nil
		if spell.kind == "aoe" or spell.kind == "pull" then
			local center, count = bestCluster(self, enemies, spell.radius or 6, range, castTime(self, spell))
			if center and count >= 2 then
				score = math.min(0.9, 0.3 + U.StrongPerEnemy * count)
				point = center
			elseif center and count == 1 and target and target.hp <= f.damage * spell.damage and spell.kind == "aoe" then
				score = U.StrongFinish
				point = target.pos
			end
			if spell.kind == "pull" and count < 3 then
				score = 0 -- singularita se vyplatí až na větší skupinu
			end
		elseif spell.kind == "chain" then
			local _, count = bestCluster(self, enemies, spell.radius or 9, range, 0)
			if count >= 2 then
				score = math.min(0.85, 0.25 + 0.18 * count)
			elseif target and target.hp <= f.damage * spell.damage then
				score = U.StrongFinish
			end
		end
		if score > scores.strong then
			scores.strong = score
			strongSpell = spell
			strongPoint = point
		end
	end
	local healSpell = spellOfKind(self, "heal")
	local lowAlly, lowFrac = nil, 1
	if healSpell then
		for _, ally in alliesOf(self) do
			local frac = ally.hp / math.max(ally.maxHp, 1)
			if frac < lowFrac then
				lowAlly, lowFrac = ally, frac
			end
		end
	end
	scores.support = if healSpell and lowAlly and lowFrac < U.SupportBelowHp then U.SupportBase + 0.4 * (1 - lowFrac) else 0

	-- Setrvačnost a výběr.
	if scores[self.action] then
		scores[self.action] += U.Inertia
	end
	local bestAction, bestScore = "idle", -1
	for name, score in scores do
		if score > bestScore then
			bestAction, bestScore = name, score
		end
	end

	-- „Lidská“ chyba: zaváhání, nebo AoE mířené kousek vedle. Vyšší level chybuje méně.
	local mistake = math.random() < lerpByLevel(self.level, Config.MistakeChance.L1, Config.MistakeChance.L30)
	if mistake and bestAction ~= "retreat" then
		if bestAction == "strong" and strongPoint then
			local angle = math.random() * math.pi * 2
			local err = Config.AimError * (1 - clamp01((self.level - 1) / 29))
			strongPoint = (strongPoint :: Vector3) + Vector3.new(math.cos(angle) * err, 0, math.sin(angle) * err)
		else
			self.hesitateUntil = clock + Config.Hesitation[1] + math.random() * (Config.Hesitation[2] - Config.Hesitation[1])
		end
	end

	if bestAction == "retreat" and self.action ~= "retreat" then
		self.retreatStarted = clock
	end
	self.action = bestAction
	self.actionScore = math.min(bestScore, 1)

	-- Kouzla se zahájí hned; ostatní akce provádí act().
	if bestAction == "strong" and strongSpell then
		-- Předstih s malou chybou: AoE míří tam, kde shluk bude, ne kde je.
		local point = strongPoint
		if point then
			local angle = math.random() * math.pi * 2
			point = point + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (math.random() * Config.Lead.Error)
		end
		startCast(self, strongSpell, target, point)
	elseif bestAction == "shield" and shieldSpell then
		startCast(self, shieldSpell, nil, nil)
	elseif bestAction == "blink" and blinkSpell then
		startCast(self, blinkSpell, nil, nil)
	elseif bestAction == "support" and healSpell then
		startCast(self, healSpell, lowAlly, nil)
	end

	-- Debug nad hlavou.
	local debugOn = Config.Debug or workspace:GetAttribute("MageDebug") == true
	if debugOn then
		local label = self.debugLabel
		if not label then
			local head = f.model:FindFirstChild("Head")
			if head then
				local gui = Instance.new("BillboardGui")
				gui.Name = "MageDebug"
				gui.Size = UDim2.fromOffset(220, 44)
				gui.StudsOffset = Vector3.new(0, 4.5, 0)
				gui.AlwaysOnTop = true
				gui.Adornee = head
				gui.Parent = head
				label = Instance.new("TextLabel")
				local made = label :: TextLabel
				made.Size = UDim2.fromScale(1, 1)
				made.BackgroundTransparency = 0.4
				made.BackgroundColor3 = Color3.new(0, 0, 0)
				made.TextColor3 = Color3.fromRGB(220, 200, 255)
				made.Font = Enum.Font.Code
				made.TextSize = 13
				made.TextWrapped = true
				made.Parent = gui
				self.debugLabel = made
			end
		end
		if label then
			local targetName = if target then (target.kind or "soldier") else "-"
			label.Text = string.format("%s %.2f → %s\nmana %d  hp %d%%  L%d", bestAction, self.actionScore, targetName, math.floor(self.mana), math.floor(hpFrac * 100), self.level)
		end
	elseif self.debugLabel then
		self:destroy()
	end
end

-- ── Provedení akce (každý tick) ─────────────────────────────────────────────

local function moveTowards(self: Brain, goal: Vector3, dt: number, speedFactor: number)
	local f = self.f
	local rate = if f.slowUntil > f.clock then f.slowFactor else 1
	local delta = flat(goal) - flat(f.pos)
	local dist = delta.Magnitude
	if dist < 0.05 then
		Rig.setMoving(f.model, false)
		return
	end
	local stepLength = math.min(f.speed * dt * rate * speedFactor, dist)
	local next = clampToArena(self, f.pos + delta.Unit * stepLength)
	f.pos = Vector3.new(next.X, f.pos.Y, next.Z)
	Rig.setMoving(f.model, true)
end

local function act(self: Brain, dt: number)
	local f, ctx = self.f, self.ctx
	local target = self.target
	local action = self.action
	local enemies = enemiesOf(self)
	local nearestEnemy, nearestDist = nearest(f.pos, enemies)
	local range = f.range
	local optimalLow, optimalHigh = range * Config.OptimalRange[1], range * Config.OptimalRange[2]

	if action == "retreat" then
		-- Pryč od hrozby (nebo ze středu telegrafované plochy), šikmo do strany; u okraje otočí stranu.
		local hazard = hazardAt(self, f.pos)
		local threatPos = if hazard then hazard.pos elseif nearestEnemy then nearestEnemy.pos else nil
		if threatPos then
			local away = flat(f.pos) - flat(threatPos)
			if away.Magnitude < 0.1 then
				away = Vector3.new(0, 0, -1)
			end
			local angle = math.rad(Config.StrafeAngle) * self.strafeSign
			local dir = CFrame.Angles(0, angle, 0):VectorToWorldSpace(away.Unit)
			local goal = f.pos + dir * 6
			local clamped = clampToArena(self, goal)
			if (flat(clamped) - flat(goal)).Magnitude > 0.5 then
				self.strafeSign = -self.strafeSign -- u okraje couvá na druhou stranu
			end
			moveTowards(self, clamped, dt, 1)
			ctx.face(f, if target then target.pos else threatPos)
			-- Střílí i při couvání: když je základní kouzlo připravené a cíl v dosahu, otočí se a vystřelí.
			if target and not hazard and (flat(target.pos) - flat(f.pos)).Magnitude <= range + 1 then
				local rate = if f.slowUntil > f.clock then f.slowFactor else 1
				f.timer -= dt * rate
				if f.timer <= 0 then
					f.timer = f.cooldown
					startCast(self, self.basic, target, nil)
				end
			end
		else
			Rig.setMoving(f.model, false)
		end
		return
	end

	if action == "approach" and target then
		moveTowards(self, target.pos, dt, 1)
		ctx.face(f, target.pos)
		return
	end

	if action == "attack" and target then
		local dist = (flat(target.pos) - flat(f.pos)).Magnitude
		-- Drží optimální vzdálenost: moc daleko → krok blíž, moc blízko → pomalu šikmo zpět.
		if dist > optimalHigh and dist > range * 0.95 then
			moveTowards(self, target.pos, dt, 1)
		elseif dist < optimalLow then
			local away = flat(f.pos) - flat(target.pos)
			if away.Magnitude > 0.1 then
				local dir = CFrame.Angles(0, math.rad(Config.StrafeAngle) * self.strafeSign, 0):VectorToWorldSpace(away.Unit)
				moveTowards(self, f.pos + dir * 4, dt, 0.5)
			end
		else
			Rig.setMoving(f.model, false)
		end
		ctx.face(f, target.pos)
		-- Základní kouzlo v tempu útoku mága.
		local rate = if f.slowUntil > f.clock then f.slowFactor else 1
		f.timer -= dt * rate
		if f.timer <= 0 and dist <= range + 1 then
			f.timer = f.cooldown
			startCast(self, self.basic, target, nil)
		end
		return
	end

	-- idle a vše ostatní: stojí, dívá se na hrozbu.
	Rig.setMoving(f.model, false)
	if target then
		ctx.face(f, target.pos)
	elseif nearestEnemy and nearestDist < math.huge then
		ctx.face(f, nearestEnemy.pos)
	end
end

-- Jeden tick bitvy pro mága: regenerace, dokončení castu, zaváhání, rozhodnutí v intervalu, akce.
function MageBrain.update(self: Brain, dt: number)
	local f = self.f
	if f.hp <= 0 then
		return
	end
	self.mana = math.min(Config.Mana.Max, self.mana + Config.Mana.Regen * dt)

	local cast = self.casting
	if cast then
		if f.clock >= cast.at then
			self.casting = nil
			resolve(self, cast)
		else
			Rig.setMoving(f.model, false)
			local look = cast.point or (cast.target and cast.target.hp > 0 and cast.target.pos)
			if look then
				self.ctx.face(f, look)
			end
		end
		return
	end
	if f.clock < self.hesitateUntil then
		Rig.setMoving(f.model, false)
		return
	end
	self.thinkIn -= dt
	if self.thinkIn <= 0 then
		self.thinkIn = Config.ThinkInterval[1] + math.random() * (Config.ThinkInterval[2] - Config.ThinkInterval[1])
		think(self)
		if self.casting then
			return
		end
	end
	act(self, dt)
end

return MageBrain
