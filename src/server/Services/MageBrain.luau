--!strict
-- Bojová AI jednotky MÁG: jedna instance (brain) na mága v bitvě. BattleService ji volá každý tick simulace
-- (brain:update(dt)); mág tím přebírá svůj pohyb i útok místo výchozího „jdi k nejbližšímu a tluč“.
--
-- UTILITY AI (páteř): každých 0,2–0,4 s (náhodný posun) brain ohodnotí možné akce skóre 0–1 a vybere nejlepší,
-- s malou setrvačností pro aktuální akci:
--   attack   základní kouzlo na vybraný cíl (v dosahu); mág při tom STOJÍ (žádné pobíhání)
--   strong   silné kouzlo: AoE do těžiště shluku nepřátel, řetěz, singularita, nebo dorážka cíle s nízkým HP
--   repel    obklíčený: odražení — nepřátelé odletí a jsou chvíli omráčení (hýbou se ONI, ne mág; od levelu 5)
--   escape   stojí v telegrafované ploše nepřítele (kruh bosse, dráha Bruta) → vystoupí z ní nejkratší cestou
--   shield   bariéra při nízkém HP nebo hrozbě
--   blink    teleport pryč, když je obklíčený a odražení není k dispozici (od levelu 26)
--   support  léčení spojence s nejnižším HP (od levelu 21)
--   approach jde dopředu jen tehdy, když NIKDO není v dosahu; zastaví, jakmile někoho v dosahu má
--   idle     krátká pauza, otočení k hrozbě, občas gesto (fidget)
-- Mág tedy nikdy necouvá do davu ani netancuje sem a tam. Pohyb mají jen: approach (nikdo v dosahu), escape
-- (telegraf), hop (≤ 1× za 8 s, 5 studů kolmo na dráhu Bruta) a blink. Nic jiného mágem nehne.
--
-- REAKCE (vrstva nad páteří): BattleService posílá události (brain:onEvent) a zásahy (brain:onDamaged); brain je
-- sbírá do schránky (inbox), každý tick ji vyprázdní a má JEDEN reakční slot: vyšší priorita vytlačí nižší,
-- stejná/nižší se zahodí (Config.Reactions.Priority). Emotivní reakce jsou okamžité, DOVEDNOSTNÍ (hop, podražení,
-- protikouzlo, strážce, kombo) čekají reakční dobu levelu (ReactionTime: L1 0,6 s → L30 0,15 s) – mág levelu 1
-- hop přes 0,8 s nájezd nestihne, od levelu ~10 ano. Běžící SILNÝ cast se nikdy nepřeruší (čekající dovednost
-- vydrží ≤ 0,4 s, pak propadne); ZÁKLADNÍ střelu hop/protikouzlo zruší (vyšumí).
--   1 FLINCH & SPITE   zásah: krystal rudě blikne, rameno škubne, „!“; útočník v dosahu → další střela dřív a rudá
--   2 FURY → OVERCHARGE zásahy/zabití/zranění spojenců plní Zuřivost; na 100 OVERCHARGE 6 s: vznáší se, runy
--                      obíhají, krystal září, střílí rychleji a levněji; končí prstencem
--   3 AVENGER          padl spojenec: hůl nahoru a PRÁSK do země, „NO!“, vrah označen MARKED, nenávist +3,
--                      další silné kouzlo zdarma a +50 %
--   4 GUARDIAN         spojenec do 14 studů pod 40 % (od L5, cd 10 s): zlatý paprsek + prstenec; má-li štít
--                      s allyCast, sešle ho NA spojence, jinak Ward (−25 % poškození na 2 s)
--   5 FLOURISH         zabití: otočka holí, jiskry, hláška (1 ze 3); 2+ zabití do 0,5 s → „DOUBLE!“/„TRIPLE!“
--   6 CHARGE ALERT     Brute nabíhá (enemyCharging) dráhou do 3 studů od mága: oranžové „!“, ARCANE HOP (od L8,
--                      cd 8 s) 5 studů KOLMO na dráhu s 3 stíny; jinak štít. Dráha končí u spojence a Brute
--                      v dosahu → TRIP BOLT (cd 5 s): rychlá slabší střela, Brute zpomalen na 50 % 1,2 s
--   7 CLUSTER PUNISH   každé AoE/pull/chain má po celý cast zaměřovač na zemi, krystaly dvakrát pulznou
--   8 COUNTER-SPELL    šaman sesílá / boss léčí (do dosahu + 3, cd 6 s): okamžitá střela s přerušením →
--                      „SILENCED!“ bílý paprsek
--   9 LAST STAND       HP < 30 % (1× za bitvu): rudé praskliny pod nohama, krystal stroboskop, −50 % poškození 4 s
--  10 FINISH           poslední nepřítel pod 35 % v dosahu (1× za bitvu): 0,5 s cast, velká bílá střela ×1,5,
--                      „FINISH!“; obecně smrtící střela = bílá koule a zlaté číslo
--  11 COMBO            kouzlo hráče (meteor/mráz) v dosahu a připravené AoE → sešle ho do STEJNÉHO bodu +25 %,
--                      „COMBO!“; SHATTER: AoE/řetěz na ≥ 2 zpomalené → ×1,3, „SHATTER!“
--  12 REPEL            viz výše (kouzlo druhu repel: arcanePush L5, shockwave L18)
--  13 SALUTE & FIDGETS začátek bitvy: zvednutí hole + prstenec; nuda: pomalá otočka holí / jiskra krystalu;
--                      nová hrozba na zemi: „!“; výhra: vítězná póza + hláška; události vlny: „BEHIND US!“ …
-- Hlášky: 1 na mága za 0,8 s (výstražná „!“ limit obchází), 6 na tick (BattleFx). Barvy: fialová = cast,
-- červená = bolest/vztek, zlatá = ochrana, bílá = poprava/přerušení, oranžová = nebezpečí zblízka, azurová = kombo.
--
-- ROZHRANÍ pro BattleService (duck-typed): MageBrain.new(ctx, fighter, level); brain:update(dt);
-- brain:onDamaged(attacker?, amount); brain:onEvent(name, payload); brain:destroy().
-- Výběr cíle je vážený (blízkost, nízké HP, nenávist, typ nepřítele, nepřítel právě sesílá, šampion) s pamětí:
-- cíl drží 1,5 s, pokud není nový výrazně lepší; na změnu reaguje s reakční dobou podle levelu a občas zaváhá.
-- Čísla: shared/Config/MageConfig.luau, kouzla: shared/Config/MageSpells.luau. Vizuály: ctx.fx (BattleFx) – brain
-- NESMÍ přidávat vlastní require (testovací harness odřízne hlavičku u `local UP`); vše stavové běží na hodinách
-- bitvy (f.clock), task.delay jen pro čistou grafiku (stub v testech ho nikdy nespustí).
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
local Tree = require(Shared.Config.MageTree) -- the merge-level tree: Blood Mana, the Archmage's cooldowns, the piercing bolt
local Rig = require(Shared.Rig)

local UP = Vector3.new(0, 1, 0)

-- Barevný jazyk reakcí.
local RED = Color3.fromRGB(255, 80, 70)
local GOLD = Color3.fromRGB(255, 215, 90)
local WHITE = Color3.fromRGB(245, 248, 255)
local ORANGE = Color3.fromRGB(255, 150, 50)
local CYAN = Color3.fromRGB(110, 230, 255)
local PURPLE = Color3.fromRGB(190, 110, 255)
local VIOLET_RED = Color3.fromRGB(220, 60, 130)

-- Co brain dostává od BattleService: záznamy bojovníků (side, hp, maxHp, pos, range, speed, cooldown, timer,
-- clock, damage, lift, baseLift, model, slowUntil, slowFactor, shieldUntil, shieldReduction, stunUntil, kind,
-- ai, champion, boltStyle, boltTint) a pomocné funkce.
export type Context = {
	fighters: { any },
	parent: Instance,
	playerSide: number,
	self: any, -- záznam tohoto mága
	fx: any, -- BattleFx (sdílené vizuály); v testech tabulka prázdných funkcí
	attack: (f: any, target: any, mult: number) -> (), -- standardní zásah (pasivky, splash, efekt střely)
	damage: (target: any, amount: number) -> number, -- poškození se zdrojem = tento mág (události, nenávist)
	popNumber: (target: any, amount: number, color: Color3?) -> (),
	face: (f: any, target: Vector3) -> (),
	bounds: { center: Vector3, halfX: number, halfZ: number },
	hazards: () -> { { pos: Vector3, radius: number, kind: string? } }, -- kind "puddle" = trvalá plocha (obchází se, nehlásí se)
	archetype: (f: any) -> string?,
	emit: (name: string, payload: any) -> (),
	clock: () -> number,
	addHazard: (pos: Vector3, radius: number, duration: number, kind: string, source: any?) -> (),
	schedule: (delay: number, fn: () -> ()) -> (),
	groundY: (pos: Vector3) -> number,
}

type Cast = {
	spell: Spells.Spell,
	at: number,
	target: any?,
	point: Vector3?,
	mult: number, -- násobek poškození (kombo, mstitel, podražení, poprava)
	interrupt: boolean?, -- protikouzlo: po zásahu přeruší cast cíle
	trip: any?, -- podražení: tento Brute bude zpomalen
	allyTarget: any?, -- štít / ward seslaný na spojence
	execute: boolean?, -- poprava: velká bílá střela
	reticle: Instance?, -- zaměřovač na zemi (zničen při vyhodnocení)
}

type CastOptions = {
	castTime: number?,
	mult: number?,
	interrupt: boolean?,
	trip: any?,
	allyTarget: any?,
	execute: boolean?,
}

type Reaction = { name: string, endsAt: number, data: any }
type Pending = { name: string, payload: any, readyAt: number, priority: number }

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
	shoulderRest: CFrame?,
	debugLabel: TextLabel?,
	lastLook: Vector3?,
	lookGoal: Vector3?, -- where the mage wants to face (tracking)
	facing: Vector3, -- where it faces now (flat unit vector, turned toward lookGoal at Config.TurnRate)
	blinkReadyAt: number, -- the blink dodge's cooldown
	-- Reakce.
	inbox: { { name: string, payload: any, at: number } },
	reaction: Reaction?,
	pending: Pending?,
	reactionCooldown: { [string]: number },
	reactionBusyUntil: number, -- po hopu chvíli stojí
	fury: number,
	furyIdleSince: number,
	overchargeUntil: number,
	runeRing: any?,
	hover: number,
	glide: number,
	glideTarget: number,
	glideSparkAt: number,
	castHand: string,
	castCount: number,
	pushes: { { enemy: any, dir: Vector3, left: number, speed: number } },
	hopUntil: number,
	hopFrom: Vector3?,
	hopTo: Vector3?,
	hopLook: Vector3?,
	hopAfterimages: number,
	hopReadyAt: number,
	guardianReadyAt: number,
	counterReadyAt: number,
	tripReadyAt: number,
	lastStandUsed: boolean,
	finishUsed: boolean,
	lastEnemy: any?,
	multiKill: { count: number, endsAt: number },
	avengerBonus: boolean,
	fidgetAt: number,
	lastPopAt: number,
	knownHazards: number,
	strobeNext: number,
	update: (self: Brain, dt: number) -> (),
	onDamaged: (self: Brain, attacker: any?, amount: number?) -> (),
	onEvent: (self: Brain, name: string, payload: any) -> (),
	destroy: (self: Brain) -> (),
}

local MageBrain = {}
MageBrain.__index = MageBrain

-- Pseudo-kouzlo Strážce bez štítu v repertoáru: Ward (−Reduction poškození spojenci na Time sekund).
local WARD: Spells.Spell = {
	id = "ward",
	label = "Guardian Rune",
	era = 0,
	minLevel = 0,
	kind = "ward",
	mana = 0,
	cooldown = 0,
	castTime = Config.Reactions.Guardian.CastTime,
	damage = 0,
	color = GOLD,
	color2 = WHITE,
}

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

local function pick(list: { string }): string
	return list[math.random(1, #list)]
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

-- Vzdálenost bodu od úsečky a–b (v půdorysu).
local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local p, s, e = flat(point), flat(a), flat(b)
	local ab = e - s
	local length2 = ab.X * ab.X + ab.Z * ab.Z
	if length2 < 0.0001 then
		return (p - s).Magnitude
	end
	local ap = p - s
	local t = clamp01((ap.X * ab.X + ap.Z * ab.Z) / length2)
	return (p - (s + ab * t)).Magnitude
end

-- ── Vytvoření ───────────────────────────────────────────────────────────────

function MageBrain.new(ctx: Context, fighter: any, level: number): Brain
	local basic, spells = Spells.forLevel(level)
	if fighter.baseLift == nil then
		fighter.baseLift = fighter.lift
	end
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
		shoulderRest = nil,
		debugLabel = nil,
		lastLook = nil,
		lookGoal = nil,
		facing = Vector3.new(0, 0, 1),
		blinkReadyAt = 0,
		inbox = {},
		reaction = nil,
		pending = nil,
		reactionCooldown = {},
		reactionBusyUntil = 0,
		fury = 0,
		furyIdleSince = 0,
		overchargeUntil = 0,
		runeRing = nil,
		hover = 0,
		glide = 0, -- 0 … 1: how far the mage is in its gliding pose (MageConfig.Glide)
		glideTarget = 0,
		glideSparkAt = 0,
		castHand = "R", -- the bolts alternate hands (the client's gesture)
		castCount = 0,
		pushes = {}, -- enemies being knocked back (a repel): they slide away over a moment instead of teleporting
		hopUntil = 0,
		hopFrom = nil,
		hopTo = nil,
		hopLook = nil,
		hopAfterimages = 0,
		hopReadyAt = 0,
		guardianReadyAt = 0,
		counterReadyAt = 0,
		tripReadyAt = 0,
		lastStandUsed = false,
		finishUsed = false,
		lastEnemy = nil,
		multiKill = { count = 0, endsAt = 0 },
		avengerBonus = false,
		fidgetAt = Config.Reactions.Fidget[1] + math.random() * (Config.Reactions.Fidget[2] - Config.Reactions.Fidget[1]),
		lastPopAt = -10,
		knownHazards = 0,
		strobeNext = 0,
	}, MageBrain) :: any
	local upperArm = fighter.model:FindFirstChild("RightUpperArm")
	local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder")
	if shoulder and shoulder:IsA("Motor6D") then
		self.shoulderRest = shoulder.C0
	end
	return self
end

-- Zranil mě: krátkodobá nenávist (vyprchává), kterou výběr cíle započítá, a událost „hit“ pro reakce.
-- `attacker` může být nil (kouzlo hráče, bouře, louže). Malé zranění bez útočníka (oděrka z louže) reakce nespouští:
-- Fury a škubnutí patří k opravdovým zásahům, ne k chip damage.
function MageBrain.onDamaged(self: Brain, attacker: any?, amount: number?)
	if attacker then
		self.hate[attacker] = (self.hate[attacker] or 0) + Config.HateGain
	elseif (amount or 0) < Config.Reactions.ChipFraction * self.f.maxHp then
		return
	end
	table.insert(self.inbox, { name = "hit", payload = { attacker = attacker, amount = amount or 0 }, at = self.f.clock })
end

local victory: (self: Brain) -> () -- níže (potřebuje pop)

-- Událost bitvy (BattleService.emit). Ukládá se do schránky a zpracuje v nejbližším update; konec bitvy hned
-- (po něm už update nepřijde).
function MageBrain.onEvent(self: Brain, name: string, payload: any)
	if name == "kill" and payload and payload.killer == self.f and Tree.has(self.level, "bloodMana") then
		-- BLOOD MANA (tree level 8): a kill refunds mana and hurries every cooldown.
		local B = Tree.Passives.bloodMana
		self.mana = math.min(Config.Mana.Max, self.mana + B.Mana)
		for id, ready in self.cooldownReady do
			self.cooldownReady[id] = ready - B.Cooldown
		end
	end
	if name == "battleEnd" then
		if payload and payload.won and self.f.hp > 0 then
			victory(self)
		end
		return
	end
	table.insert(self.inbox, { name = name, payload = payload, at = self.f.clock })
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
	local ring = self.runeRing
	if ring then
		ring.destroy()
		self.runeRing = nil
	end
	local cast = self.casting
	if cast and cast.reticle then
		cast.reticle:Destroy()
		cast.reticle = nil
	end
	self.hover = 0
	self.glide = 0
	self.f.model:SetAttribute("Glide", 0)
	self.f.tilt = 0
	self.f.lift = self.f.baseLift
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

-- Moving or standing: the rig's animation state and the glide target (the Mage floats while it moves, see
-- tickVisuals / MageConfig.Glide).
local function setGlide(self: Brain, moving: boolean)
	Rig.setMoving(self.f.model, moving)
	self.glideTarget = if moving then 1 else 0
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

local function insideArena(self: Brain, pos: Vector3): boolean
	local b = self.ctx.bounds
	local m = Config.ArenaMargin
	return math.abs(pos.X - b.center.X) <= b.halfX - m and math.abs(pos.Z - b.center.Z) <= b.halfZ - m
end

-- Telegrafovaná plocha nepřítele, ve které mág stojí (nebo nil).
local function hazardAt(self: Brain, pos: Vector3): { pos: Vector3, radius: number, kind: string? }?
	for _, hazard in self.ctx.hazards() do
		if (flat(hazard.pos) - flat(pos)).Magnitude <= hazard.radius + 1 then
			return hazard
		end
	end
	return nil
end

-- Dá se nepřítel odhodit / přitáhnout? Totemy (stojí, rychlost 0) a Grubnak (jeho útoky řídí RiftKing.luau) ne;
-- zranění dostanou i tak.
local function movable(self: Brain, enemy: any): boolean
	return (enemy.speed or 0) > 0 and enemy.ability ~= "riftking" and self.ctx.archetype(enemy) ~= "Totem"
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

local function isOvercharged(self: Brain): boolean
	return self.overchargeUntil > self.f.clock
end

local function skillDelay(self: Brain): number
	if not Config.Reactions.SkillDelay then
		return 0
	end
	return lerpByLevel(self.level, Config.ReactionTime.L1, Config.ReactionTime.L30)
end

-- Otočení k bodu (pamatuje si ho kvůli vznášení, které model každý tick přepivotuje).
-- Where the mage should face; the body turns there smoothly (turnStep, every tick).
local function look(self: Brain, point: Vector3)
	self.lastLook = point
	self.lookGoal = point
end

-- Turns the body toward lookGoal at most Config.TurnRate rad/s and faces it there (also refreshes the pose when
-- the lift or the lean changed).
local function turnStep(self: Brain, dt: number)
	local f = self.f
	local goal = self.lookGoal
	if goal then
		local want = flat(goal - f.pos)
		if want.Magnitude > 0.05 then
			want = want.Unit
			local current = self.facing
			local angle = math.acos(math.clamp(current.X * want.X + current.Z * want.Z, -1, 1))
			local maxStep = Config.TurnRate * dt
			if angle <= maxStep or angle < 1e-3 then
				self.facing = want
			else
				-- Rotate around the up axis by maxStep toward `want` (the side from the cross product).
				local sign = if current.X * want.Z - current.Z * want.X >= 0 then 1 else -1
				local a = maxStep * sign
				local c, sn = math.cos(a), math.sin(a)
				self.facing = Vector3.new(current.X * c - current.Z * sn, 0, current.X * sn + current.Z * c).Unit
			end
		end
	end
	self.ctx.face(f, f.pos + self.facing * 10)
end

-- ── Hlášky a reakční slot ───────────────────────────────────────────────────

-- Krátký text nad hlavou: 1 za PopRate na mága; výstražné „!“ (alert) smí dřív, ale ne víc než ~2× tak často.
local function pop(self: Brain, text: string, color: Color3, size: number?, alert: boolean?)
	local f = self.f
	local gap = Config.Reactions.PopRate * (if alert then 0.5 else 1)
	if f.clock - self.lastPopAt < gap then
		return
	end
	self.lastPopAt = f.clock
	self.ctx.fx.pop(self.ctx.parent, f.pos + UP * (f.lift + 3.2), text, color, size)
end

-- Obsadí reakční slot: vyšší priorita vytlačí běžící nižší, stejná/nižší se zahodí. Vrací, zda reakce běží.
local function startReaction(self: Brain, name: string, duration: number, data: any?): boolean
	local priority = Config.Reactions.Priority[name] or 1
	local running = self.reaction
	if running and running.endsAt > self.f.clock and (Config.Reactions.Priority[running.name] or 1) >= priority then
		return false
	end
	self.reaction = { name = name, endsAt = self.f.clock + duration, data = data }
	return true
end

local function reactionFree(self: Brain): boolean
	local running = self.reaction
	return not running or running.endsAt <= self.f.clock
end

-- Dovednostní reakce čeká reakční dobu levelu; jen jedna najednou, vyšší priorita přepíše nižší.
local function queueSkill(self: Brain, name: string, payload: any)
	local priority = Config.Reactions.Priority[name] or 1
	local pending = self.pending
	if pending and pending.priority > priority then
		return
	end
	self.pending = { name = name, payload = payload, readyAt = self.f.clock + skillDelay(self), priority = priority }
end

-- ── Tělo: rameno, krystaly, hůl ─────────────────────────────────────────────

local function shoulderOf(self: Brain): Motor6D?
	local upperArm = self.f.model:FindFirstChild("RightUpperArm")
	local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder")
	if shoulder and shoulder:IsA("Motor6D") and self.shoulderRest then
		return shoulder
	end
	return nil
end

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
	local shoulder = shoulderOf(self)
	local rest = self.shoulderRest
	if shoulder and rest then
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

-- Škubnutí ramene dozadu a zpět (zásah).
local function shoulderJerk(self: Brain)
	local shoulder = shoulderOf(self)
	local rest = self.shoulderRest
	if not (shoulder and rest) or self.casting then
		return
	end
	TweenService:Create(shoulder, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest * CFrame.Angles(math.rad(-15), 0, 0) }):Play()
	task.delay(0.12, function()
		if shoulder.Parent then
			TweenService:Create(shoulder, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = rest }):Play()
		end
	end)
end

-- Hůl nahoru a PRÁSK do země (Mstitel).
local function shoulderSlam(self: Brain)
	local shoulder = shoulderOf(self)
	local rest = self.shoulderRest
	if not (shoulder and rest) then
		return
	end
	TweenService:Create(shoulder, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest * CFrame.Angles(math.rad(Config.ArmRaise), 0, 0) }):Play()
	task.delay(0.3, function()
		if not shoulder.Parent then
			return
		end
		TweenService:Create(shoulder, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = rest * CFrame.Angles(math.rad(-20), 0, 0) }):Play()
		task.delay(0.15, function()
			if shoulder.Parent then
				TweenService:Create(shoulder, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = rest }):Play()
			end
		end)
	end)
end

local function castTime(self: Brain, spell: Spells.Spell): number
	local duration = spell.castTime * (1 - 0.3 * clamp01((self.level - 1) / 29)) -- vyšší level sesílá rychleji
	if isOvercharged(self) then
		duration *= Config.Reactions.Overcharge.CastFactor
	end
	return duration
end

-- Zrušení rozdělaného castu (hop / protikouzlo přeruší základní střelu): zaměřovač pryč, mana propadá.
local function cancelCast(self: Brain)
	local cast = self.casting
	if not cast then
		return
	end
	if cast.reticle then
		cast.reticle:Destroy()
	end
	self.casting = nil
end

local function startCast(self: Brain, spell: Spells.Spell, target: any?, point: Vector3?, opts: CastOptions?)
	local f, ctx = self.f, self.ctx
	local o: CastOptions = opts or {}
	cancelCast(self)
	local duration = o.castTime or castTime(self, spell)
	local mult = o.mult or 1
	local cost = spell.mana * (if isOvercharged(self) then Config.Reactions.Overcharge.ManaFactor else 1)
	if self.avengerBonus and not spell.basic and spell.mana > 0 then
		-- Mstitel: další silné kouzlo zdarma a silnější.
		self.avengerBonus = false
		cost = 0
		mult *= 1 + Config.Reactions.Avenger.DamageBonus
	end
	self.mana -= cost
	if spell.cooldown > 0 then
		-- ARCHMAGE (tree level 16): shorter cooldowns (doubled when Ascended).
		local factor = if Tree.has(self.level, "archmage") then 1 - Tree.Passives.archmage.Cooldown * (if f.ascended then 2 else 1) else 1
		self.cooldownReady[spell.id] = f.clock + spell.cooldown * factor
	end
	local cast: Cast = {
		spell = spell,
		at = f.clock + duration,
		target = target,
		point = point,
		mult = mult,
		interrupt = o.interrupt,
		trip = o.trip,
		allyTarget = o.allyTarget,
		execute = o.execute,
		reticle = nil,
	}
	-- CLUSTER PUNISH: plošná kouzla mají po celý cast zaměřovač na zemi a krystaly dvakrát pulznou.
	if spell.kind == "aoe" or spell.kind == "pull" or spell.kind == "chain" then
		local at = point or (target and target.pos)
		if at then
			local radius = if spell.kind == "chain" then 2 else (spell.radius or 6)
			cast.reticle = ctx.fx.reticle(ctx.parent, at, radius, spell.color, ctx.groundY(at))
			ctx.fx.crystalFlash(f.model, spell.color2, 0.15, 2)
			task.delay(0.25, function()
				if f.hp > 0 and f.model.Parent then
					ctx.fx.crystalFlash(f.model, spell.color2, 0.15, 2)
				end
			end)
		end
	end
	self.casting = cast
	-- The client animates the gesture of this cast (client/MageAnimator.luau): kind, how long the wind-up is
	-- (the spell fires at its end) and which hand; the bolts alternate hands.
	if spell.kind == "bolt" then
		self.castHand = if self.castHand == "R" then "L" else "R"
	end
	self.castCount += 1
	f.model:SetAttribute("Cast", string.format("%s|%.2f|%s", spell.kind, duration, self.castHand))
	f.model:SetAttribute("CastId", self.castCount)
	telegraph(self, duration, not spell.basic)
	if point then
		look(self, point)
	elseif target then
		look(self, target.pos)
	end
	setGlide(self, false)
end

-- ── Zuřivost a Overcharge ───────────────────────────────────────────────────

local function endOvercharge(self: Brain)
	local ring = self.runeRing
	if ring then
		ring.destroy()
		self.runeRing = nil
	end
	self.overchargeUntil = 0
	groundRing(self.ctx.parent, self.f.pos, self.basic.color, Config.Reactions.Overcharge.EndRing, 0.7)
end

local function startOvercharge(self: Brain)
	local f, ctx = self.f, self.ctx
	local O = Config.Reactions.Overcharge
	self.overchargeUntil = f.clock + O.Duration
	self.fury = 0
	if self.runeRing then
		self.runeRing.destroy()
	end
	self.runeRing = ctx.fx.runeRing(ctx.parent, self.basic.color, O.RuneCount, O.RuneRadius)
	ctx.fx.crystalFlash(f.model, self.basic.color, O.Duration, 3)
	sparks(ctx.parent, f.pos, self.basic.color, 10, 2.5, 5)
	pop(self, pick(Config.Lines.overcharge), self.basic.color, 30, true)
end

local function addFury(self: Brain, amount: number)
	local F = Config.Reactions.Fury
	self.furyIdleSince = self.f.clock
	if isOvercharged(self) then
		return
	end
	self.fury = math.min(F.Max, self.fury + amount)
	if self.fury >= F.Max then
		startOvercharge(self)
	end
end

-- ── Vyhodnocení kouzla po castu ─────────────────────────────────────────────
-- Cíl mohl mezitím zemřít nebo zmizet: pak se hledá náhradní, nebo kouzlo vyšumí.

local function resolve(self: Brain, cast: Cast)
	local f, ctx = self.f, self.ctx
	local spell = cast.spell
	local parent = ctx.parent
	if cast.reticle then
		cast.reticle:Destroy()
		cast.reticle = nil
	end
	if not parent.Parent or f.hp <= 0 then
		return
	end
	local enemies = enemiesOf(self)
	local tip = staffTip(self)
	local mult = cast.mult
	local C = Config.Reactions.Combo

	if spell.kind == "bolt" then
		local target = cast.target
		if not target or target.hp <= 0 then
			target = nearest(f.pos, enemies)
		end
		if target and (flat(target.pos) - flat(f.pos)).Magnitude <= f.range + Config.Reactions.Counter.ExtraRange then
			if cast.execute then
				f.boltStyle = "execute"
			end
			ctx.attack(f, target, spell.damage * mult)
			if spell.pierce and spell.pierce > 1 then
				-- SUN RAY (tree level 7): the bolt goes on into the enemies standing behind the target (up to 10 studs
				-- further, 3 to the side), one per extra pierce.
				local dir = flat(target.pos - f.pos)
				if dir.Magnitude > 0.01 then
					dir = dir.Unit
					local extra = spell.pierce - 1
					for _, other in enemies do
						if extra <= 0 then
							break
						end
						if other ~= target and other.hp > 0 then
							local v = flat(other.pos - target.pos)
							local along = v:Dot(dir)
							if along > 0 and along <= 10 and (v - dir * along).Magnitude <= 3 then
								local taken = ctx.damage(other, f.damage * spell.damage * mult)
								ctx.popNumber(other, taken, spell.color)
								if ctx.fx.beam then
									ctx.fx.beam(ctx.parent, target.pos + UP * target.lift, other.pos + UP * other.lift, spell.color, 0.35, 0.2)
								end
								extra -= 1
							end
						end
					end
				end
			end
			if cast.trip and target == cast.trip then
				-- TRIP BOLT: Brute v nájezdu zpomalen.
				local CA = Config.Reactions.ChargeAlert
				target.slowUntil = target.clock + CA.TripTime
				target.slowFactor = CA.TripSlow
				pop(self, "!", ORANGE, 24, true)
			end
			if cast.interrupt and target.ai and target.ai.interrupt and target.ai:interrupt() then
				-- COUNTER-SPELL: cast cíle vyšuměl.
				beam(parent, tip, target.pos + UP * target.lift, WHITE, 0.5, 0.3)
				sparks(parent, target.pos, WHITE, 6, 2, 3)
				pop(self, pick(Config.Lines.counter), WHITE, 24, true)
			end
		end
	elseif spell.kind == "aoe" then
		local point = cast.point or (cast.target and cast.target.pos)
		if not point then
			return
		end
		local radius = spell.radius or 6
		local victims = {}
		local slowed = 0
		for _, enemy in enemies do
			if (flat(enemy.pos) - flat(point)).Magnitude <= radius then
				table.insert(victims, enemy)
				if enemy.slowUntil > enemy.clock then
					slowed += 1
				end
			end
		end
		-- SHATTER: zpomalení nepřátelé se rozbijí.
		local shatter = slowed >= C.ShatterMin
		if shatter then
			mult *= 1 + C.ShatterBonus
		end
		-- Efekt: paprsek z krystalu, záblesk, prstenec a sloupy světla po okraji.
		beam(parent, tip, point + UP * 1.5, spell.color, 0.6, 0.25)
		groundRing(parent, point, spell.color, radius, 0.5)
		if shatter then
			groundRing(parent, point, WHITE, radius * 1.2, 0.6)
			pop(self, pick(Config.Lines.shatter), CYAN, 26, true)
		end
		local flash = neon(parent, Vector3.one * 2, CFrame.new(point + UP * 1.5), spell.color2, 0.1, Enum.PartType.Ball)
		fade(flash, 0.4, { Size = Vector3.one * radius * 1.4, Transparency = 1, Color = spell.color })
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			local pillarPos = point + Vector3.new(math.cos(angle) * radius * 0.8, 4, math.sin(angle) * radius * 0.8)
			local pillar = neon(parent, Vector3.new(0.4, 8, 0.4), CFrame.new(pillarPos), spell.color2, 0.3)
			fade(pillar, 0.5, { Transparency = 1, Size = Vector3.new(0.1, 10, 0.1) })
		end
		sparks(parent, point, spell.color, 12, radius, 6)
		for _, enemy in victims do
			local taken = ctx.damage(enemy, f.damage * spell.damage * mult)
			ctx.popNumber(enemy, taken)
			if spell.slow then
				enemy.slowUntil = enemy.clock + spell.slow.time
				enemy.slowFactor = spell.slow.factor
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
		-- Nejdřív řetěz naplánovat (kvůli SHATTER), pak udeřit.
		local hit: { [any]: boolean } = {}
		local chainList = {}
		local current = target
		for _ = 1, (spell.jumps or 3) do
			if not current then
				break
			end
			hit[current] = true
			table.insert(chainList, current)
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
		local slowed = 0
		for _, victim in chainList do
			if victim.slowUntil > victim.clock then
				slowed += 1
			end
		end
		if slowed >= C.ShatterMin then
			mult *= 1 + C.ShatterBonus
			groundRing(parent, target.pos, WHITE, 5, 0.6)
			pop(self, pick(Config.Lines.shatter), CYAN, 26, true)
		end
		local from = tip
		for _, victim in chainList do
			beam(parent, from, victim.pos + UP * victim.lift, spell.color, 0.5, 0.3)
			beam(parent, from, victim.pos + UP * victim.lift, spell.color2, 0.2, 0.3)
			sparks(parent, victim.pos, spell.color, 5, 2, 3)
			ctx.popNumber(victim, ctx.damage(victim, f.damage * spell.damage * mult))
			from = victim.pos + UP * victim.lift
		end
	elseif spell.kind == "shield" or spell.kind == "ward" then
		-- Bariéra na sobě, nebo (Strážce) na spojenci: štít s allyCast / Ward.
		local who = cast.allyTarget or f
		if who.hp <= 0 then
			return
		end
		local G = Config.Reactions.Guardian
		local shield = spell.shield
		if shield then
			who.shieldUntil = who.clock + shield.time
			who.shieldReduction = shield.reduction
		else
			who.shieldUntil = who.clock + G.Time
			who.shieldReduction = G.Reduction
		end
		local time = if shield then shield.time else G.Time
		local color = if cast.allyTarget then GOLD else spell.color
		if cast.allyTarget then
			-- Zlatý paprsek z krystalu, prstenec a zlatý nádech na spojenci.
			beam(parent, tip, who.pos + UP * who.lift, GOLD, 0.45, 0.35)
			groundRing(parent, who.pos, GOLD, 4, 0.5)
			ctx.fx.tint(who.model, GOLD, G.Time)
		end
		local sphere = neon(parent, Vector3.one * 6, CFrame.new(who.pos + UP * who.lift), color, 0.6, Enum.PartType.Ball)
		local root = who.model.PrimaryPart
		if root then
			local weld = Instance.new("WeldConstraint") -- bublina jede s nositelem
			sphere.Anchored = false
			sphere.Massless = true
			weld.Part0 = root
			weld.Part1 = sphere
			weld.Parent = sphere
		end
		TweenService:Create(sphere, TweenInfo.new(0.3), { Transparency = 0.75 }):Play()
		task.delay(time - 0.3, function()
			if sphere.Parent then
				fade(sphere, 0.3, { Transparency = 1, Size = Vector3.one * 7 })
			end
		end)
		Debris:AddItem(sphere, time + 0.1)
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
		f.model:SetAttribute("Blink", ((f.model:GetAttribute("Blink") :: number?) or 0) + 1) -- the client flashes the aura
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
				if d > 1 and movable(self, enemy) then
					local step = math.min(spell.pull or 6, d - 1)
					enemy.pos += toCenter.Unit * step
				end
				ctx.popNumber(enemy, ctx.damage(enemy, f.damage * spell.damage * mult))
			end
		end
	elseif spell.kind == "repel" then
		-- REPEL: a crisp, HOLLOW shockwave (a ring of thin shards racing outward along the floor, nothing filled
		-- that hides the fight), a small flash at the mage, and the enemies in range SLIDE back over 0.25 s (see
		-- tickVisuals: self.pushes) with a short dust puff each; they are stunned for a moment and take damage.
		local radius = spell.radius or 7
		local push = spell.push or 8
		local SEGMENTS = 18
		local groundY = f.pos.Y + 0.25
		for i = 1, SEGMENTS do
			local angle = (i / SEGMENTS) * math.pi * 2
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local start = Vector3.new(f.pos.X, groundY, f.pos.Z) + dir * 1.2
			local shard = neon(parent, Vector3.new(0.12, 0.25, 1.1), CFrame.lookAt(start, start + Vector3.new(-dir.Z, 0, dir.X)), if i % 2 == 0 then spell.color else spell.color2, 0.25)
			local goal = Vector3.new(f.pos.X, groundY, f.pos.Z) + dir * radius
			fade(shard, 0.3, { CFrame = CFrame.lookAt(goal, goal + Vector3.new(-dir.Z, 0, dir.X)), Size = Vector3.new(0.06, 0.12, 2.2), Transparency = 1 })
		end
		local flash = neon(parent, Vector3.one * 1.6, CFrame.new(f.pos + UP * (f.lift * 0.8)), spell.color2, 0.45, Enum.PartType.Ball)
		fade(flash, 0.18, { Size = Vector3.one * 3.6, Transparency = 1 })
		for _, enemy in enemies do
			local away = flat(enemy.pos) - flat(f.pos)
			local d = away.Magnitude
			if d <= radius then
				if movable(self, enemy) then
					if d < 0.1 then
						local angle = math.random() * math.pi * 2
						away = Vector3.new(math.cos(angle), 0, math.sin(angle))
					end
					table.insert(self.pushes, { enemy = enemy, dir = away.Unit, left = push, speed = push / 0.25 })
					enemy.stunUntil = math.max(enemy.stunUntil or 0, enemy.clock + (spell.stun or 0.6) + 0.25)
					sparks(parent, enemy.pos, spell.color, 3, 1.2, 1.5)
				end
				ctx.popNumber(enemy, ctx.damage(enemy, f.damage * spell.damage * mult))
			end
		end
	end
end

-- ── Reakce ──────────────────────────────────────────────────────────────────

-- 1 FLINCH & SPITE: zásah.
local function flinch(self: Brain, attacker: any?)
	local f, ctx = self.f, self.ctx
	local R = Config.Reactions.Flinch
	if (self.reactionCooldown.flinch or 0) > f.clock then
		return
	end
	if not startReaction(self, "flinch", R.Duration) then
		return
	end
	self.reactionCooldown.flinch = f.clock + R.Cooldown
	ctx.fx.crystalFlash(f.model, RED, R.Duration, 2.5)
	shoulderJerk(self)
	pop(self, "!", RED, 24, true)
	-- Oplátka: útočník v dosahu → další střela dřív a rudá.
	if attacker and attacker.hp > 0 and (flat(attacker.pos) - flat(f.pos)).Magnitude <= f.range and f.timer > 0.4 then
		f.timer -= R.SnapShot
		f.boltTint = RED
	end
end

-- 5 FLOURISH: zabití (a násobné zabití).
local function flourish(self: Brain)
	local f, ctx = self.f, self.ctx
	local R = Config.Reactions
	local mk = self.multiKill
	if f.clock < mk.endsAt then
		mk.count += 1
	else
		mk.count = 1
	end
	mk.endsAt = f.clock + R.MultiKillWindow
	if mk.count >= 2 then
		pop(self, Config.Lines.multi[math.min(mk.count - 1, #Config.Lines.multi)], GOLD, 28, true)
		sparks(ctx.parent, f.pos, GOLD, 10, 3, 3)
		addFury(self, R.Fury.PerMultiKill)
	end
	if not startReaction(self, "flourish", 0.35) then
		return
	end
	if not self.casting then
		ctx.fx.staffSpin(f.model, 0.35)
	end
	sparks(ctx.parent, staffTip(self), self.basic.color, 6, 1.2, 2)
	if math.random() < 1 / 3 then
		pop(self, pick(Config.Lines.kill), WHITE, 22)
	end
end

-- 3 AVENGER: padl spojenec.
local function avenger(self: Brain, killer: any?)
	local f, ctx = self.f, self.ctx
	local A = Config.Reactions.Avenger
	if not startReaction(self, "avenger", A.Duration, killer) then
		return
	end
	shoulderSlam(self)
	groundRing(ctx.parent, f.pos, VIOLET_RED, A.Ring, 0.6)
	ctx.fx.crystalFlash(f.model, RED, A.Duration, 2.5)
	pop(self, pick(Config.Lines.allyDown), RED, 28, true)
	if killer and killer.hp > 0 then
		ctx.fx.mark(killer.model, "MARKED", RED, A.MarkTime)
		ctx.fx.tint(killer.model, RED, 1)
		self.hate[killer] = (self.hate[killer] or 0) + A.HateBonus
		self.target = killer
		self.targetSince = f.clock
		self.pendingTarget = nil
		look(self, killer.pos)
	end
	self.avengerBonus = true
end

-- 9 LAST STAND: pod 30 % HP, jednou za bitvu.
local function lastStand(self: Brain)
	local f, ctx = self.f, self.ctx
	local L = Config.Reactions.LastStand
	self.lastStandUsed = true
	startReaction(self, "lastStand", 1, nil)
	self.strobeNext = f.clock
	f.shieldUntil = f.clock + L.Duration
	f.shieldReduction = L.Reduction
	-- Rudé praskliny od nohou.
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2 + math.random() * 0.4
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local crack = neon(ctx.parent, Vector3.new(0.3, 0.12, 3.2), CFrame.new(f.pos + dir * 1.8 + UP * 0.15) * CFrame.Angles(0, -angle, 0), RED, 0.1)
		fade(crack, L.Duration, { Transparency = 1 })
	end
	groundRing(ctx.parent, f.pos, RED, 5, 0.5)
	pop(self, pick(Config.Lines.lastStand), RED, 30, true)
	addFury(self, L.FuryBonus)
end

-- 10 FINISH: poprava posledního nepřítele.
local function finish(self: Brain, enemy: any)
	local f = self.f
	local Fi = Config.Reactions.Finish
	if not startReaction(self, "finish", Fi.CastTime) then
		return
	end
	self.finishUsed = true
	pop(self, pick(Config.Lines.finish), WHITE, 30, true)
	self.ctx.fx.crystalFlash(f.model, WHITE, Fi.CastTime, 3)
	startCast(self, self.basic, enemy, nil, { castTime = Fi.CastTime, mult = Fi.Mult, execute = true })
end

-- 13 SALUTE: začátek bitvy.
local function salute(self: Brain)
	local f, ctx = self.f, self.ctx
	if not startReaction(self, "fidget", Config.Reactions.Salute) then
		return
	end
	Rig.raise(f.model, Config.Reactions.Salute)
	ctx.fx.crystalFlash(f.model, self.basic.color, Config.Reactions.Salute, 2)
	groundRing(ctx.parent, f.pos, self.basic.color, 4, 0.6)
end

-- Vítězná póza (konec vyhrané bitvy).
victory = function(self: Brain)
	local f, ctx = self.f, self.ctx
	Rig.raise(f.model, Config.Reactions.Victory)
	groundRing(ctx.parent, f.pos, PURPLE, 6, 0.8)
	sparks(ctx.parent, f.pos, PURPLE, 12, 3, 6)
	ctx.fx.crystalFlash(f.model, PURPLE, Config.Reactions.Victory, 2.5)
	self.lastPopAt = -10
	pop(self, pick(Config.Lines.victory), PURPLE, 26, true)
end

-- Gesto z nudy: pomalá otočka holí nebo jiskra krystalu.
local function fidget(self: Brain, lookAt: Vector3?)
	local f, ctx = self.f, self.ctx
	local Fd = Config.Reactions.Fidget
	self.fidgetAt = f.clock + Fd[1] + math.random() * (Fd[2] - Fd[1])
	if not startReaction(self, "fidget", 0.8) then
		return
	end
	if math.random() < 0.5 then
		ctx.fx.staffSpin(f.model, 0.8)
	else
		ctx.fx.crystalFlash(f.model, self.basic.color, 0.4, 2)
		sparks(ctx.parent, staffTip(self), self.basic.color, 4, 0.8, 1.5)
	end
	if lookAt then
		look(self, lookAt)
	end
end

-- BLINK DODGE: a melee enemy is about to reach the mage → it teleports away, to the spot that is farthest from
-- every enemy, preferring the other side of the attacker and staying within shooting range; it lands looking back.
local function blinkDodge(self: Brain, threat: any): boolean
	local f, ctx = self.f, self.ctx
	local B = Config.Reactions.BlinkDodge
	local enemies = enemiesOf(self)
	local here = flat(f.pos)
	local fromThreat = here - flat(threat.pos)
	fromThreat = if fromThreat.Magnitude > 0.05 then fromThreat.Unit else Vector3.new(0, 0, -1)
	local best: Vector3? = nil
	local bestScore = -math.huge
	for ring = 1, 2 do
		local center = if ring == 1 then flat(threat.pos) else here
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			local candidate = Vector3.new(center.X + math.cos(a) * B.Distance, f.pos.Y, center.Z + math.sin(a) * B.Distance)
			if not insideArena(self, candidate) or hazardAt(self, candidate) then
				continue
			end
			local flatCandidate = flat(candidate)
			local closest = math.huge
			for _, e in enemies do
				closest = math.min(closest, (flat(e.pos) - flatCandidate).Magnitude)
			end
			local side = flatCandidate - flat(threat.pos)
			local sideUnit = if side.Magnitude > 0.05 then side.Unit else nil
			local other = if sideUnit then -(sideUnit.X * fromThreat.X + sideUnit.Z * fromThreat.Z) else 0 -- 1 = right across the attacker
			local score = math.min(closest, 16) + other * B.OtherSide - (if closest > f.range + 2 then B.OutOfRange else 0)
			if score > bestScore then
				best, bestScore = candidate, score
			end
		end
	end
	if not best then
		return false
	end
	if self.casting and self.casting.spell.basic then
		cancelCast(self)
	end
	local parent = ctx.parent
	local color, color2 = self.basic.color, self.basic.color2
	local from = f.pos + UP * f.lift
	ctx.fx.afterimage(parent, f.pos, f.lift, color)
	fade(neon(parent, Vector3.one * 1.8, CFrame.new(from), color, 0.15, Enum.PartType.Ball), 0.3, { Size = Vector3.one * 5, Transparency = 1 })
	sparks(parent, f.pos, color, 6, 2, 2.5)
	f.pos = Vector3.new(best.X, f.pos.Y, best.Z)
	local to = f.pos + UP * f.lift
	fade(neon(parent, Vector3.one * 4, CFrame.new(to), color2, 0.2, Enum.PartType.Ball), 0.3, { Size = Vector3.one * 1, Transparency = 1 })
	groundRing(parent, f.pos, color, 3.5, 0.35)
	-- Lands looking straight back at the attacker.
	local back = flat(threat.pos - f.pos)
	if back.Magnitude > 0.05 then
		self.facing = back.Unit
	end
	look(self, threat.pos)
	f.model:SetAttribute("Blink", ((f.model:GetAttribute("Blink") :: number?) or 0) + 1)
	self.castCount += 1
	f.model:SetAttribute("Cast", "blink|0.12|R")
	f.model:SetAttribute("CastId", self.castCount)
	local cooldown = B.CooldownLow + (B.CooldownTop - B.CooldownLow) * clamp01((self.level - 1) / 15)
	self.blinkReadyAt = f.clock + cooldown
	self.reactionBusyUntil = math.max(self.reactionBusyUntil, f.clock + B.Recover)
	self.action = "blink"
	setGlide(self, false)
	pop(self, pick(Config.Lines.dodge), color2, 20, false)
	return true
end

-- Is a melee enemy about to reach the mage? (The knockback answers first when it is ready.)
local function tryDodge(self: Brain): boolean
	local f = self.f
	local B = Config.Reactions.BlinkDodge
	if self.level < B.MinLevel or f.clock < self.blinkReadyAt or self.hopUntil > 0 or #self.pushes > 0 then
		return false
	end
	if self.casting and not self.casting.spell.basic then
		return false -- a strong spell (or the knockback itself) is being cast
	end
	local threat, threatDist = nil, math.huge
	for _, e in enemiesOf(self) do
		if (e.range or 0) <= B.MeleeRange and (e.stunUntil or 0) <= e.clock then
			local d = (flat(e.pos) - flat(f.pos)).Magnitude
			if d <= B.Trigger and d < threatDist then
				threat, threatDist = e, d
			end
		end
	end
	if not threat then
		return false
	end
	local repel = spellOfKind(self, "repel")
	if repel and spellReady(self, repel) then
		return false
	end
	return blinkDodge(self, threat)
end

-- 6 ARCANE HOP: 5 studů kolmo na dráhu Bruta (ke středu arény; při shodě dál od Bruta), se stíny.
local function hop(self: Brain, brute: any, from: Vector3, to: Vector3)
	local f = self.f
	local CA = Config.Reactions.ChargeAlert
	local dir = flat(to - from)
	if dir.Magnitude < 0.1 then
		return
	end
	dir = dir.Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local a = f.pos + side * CA.HopDistance
	local b = f.pos - side * CA.HopDistance
	local okA, okB = insideArena(self, a), insideArena(self, b)
	local choice: Vector3
	if okA ~= okB then
		choice = if okA then a else b
	else
		local threat = if brute then flat(brute.pos) else flat(from)
		local da, db = (flat(a) - threat).Magnitude, (flat(b) - threat).Magnitude
		if math.abs(da - db) > 0.5 then
			choice = if da > db then a else b
		else
			local center = self.ctx.bounds.center
			choice = if (flat(a) - flat(center)).Magnitude <= (flat(b) - flat(center)).Magnitude then a else b
		end
	end
	if not startReaction(self, "chargeAlert", CA.HopTime + CA.HopRecover) then
		return -- běží důležitější reakce (Mstitel, Last Stand)
	end
	if self.casting and self.casting.spell.basic then
		cancelCast(self)
	end
	self.hopFrom = f.pos
	self.hopTo = clampToArena(self, choice)
	self.hopUntil = f.clock + CA.HopTime
	self.hopReadyAt = f.clock + CA.HopCooldown
	self.hopAfterimages = 0
	self.hopLook = if brute then brute.pos else to
	self.reactionBusyUntil = self.hopUntil + CA.HopRecover
	pop(self, pick(Config.Lines.hop), ORANGE, 24, true)
end

local function hopTick(self: Brain)
	local f, ctx = self.f, self.ctx
	local CA = Config.Reactions.ChargeAlert
	local from, to = self.hopFrom, self.hopTo
	if not (from and to) then
		self.hopUntil = 0
		return
	end
	local t = clamp01(1 - (self.hopUntil - f.clock) / CA.HopTime)
	if f.clock >= self.hopUntil then
		t = 1 -- poslední tick: dosedne přesně na cíl
		self.hopUntil = 0
	end
	local pos = from:Lerp(to, t)
	f.pos = Vector3.new(pos.X, f.pos.Y, pos.Z)
	setGlide(self, true)
	local step = 1 / math.max(CA.Afterimages - 1, 1)
	if self.hopAfterimages < CA.Afterimages and t >= self.hopAfterimages * step - 0.001 then
		ctx.fx.afterimage(ctx.parent, f.pos, f.lift, self.basic.color)
		self.hopAfterimages += 1
	end
	if self.hopLook then
		look(self, self.hopLook)
	end
	if t >= 1 then
		setGlide(self, false)
	end
end

-- Dovednostní reakce, jejíž reakční doba uplynula.
local function fireSkill(self: Brain, pending: Pending)
	local f = self.f
	local name, payload = pending.name, pending.payload
	local CA = Config.Reactions.ChargeAlert
	if name == "chargeAlert" then
		local brute = payload.brute
		if brute and brute.hp <= 0 then
			return
		end
		if payload.mode == "hop" then
			hop(self, brute, payload.from, payload.to)
		elseif payload.mode == "trip" and brute then
			if (flat(brute.pos) - flat(f.pos)).Magnitude <= f.range + Config.Reactions.Counter.ExtraRange and startReaction(self, "chargeAlert", 0.3) then
				self.tripReadyAt = f.clock + CA.TripCooldown
				startCast(self, self.basic, brute, nil, { castTime = 0.15, mult = CA.TripMult, trip = brute })
			end
		end
	elseif name == "counter" then
		local caster = payload.caster
		if caster and caster.hp > 0 and (flat(caster.pos) - flat(f.pos)).Magnitude <= f.range + Config.Reactions.Counter.ExtraRange and startReaction(self, "counter", Config.Reactions.Counter.CastTime + 0.2) then
			self.counterReadyAt = f.clock + Config.Reactions.Counter.Cooldown
			self.ctx.fx.crystalFlash(f.model, WHITE, 0.3, 3)
			startCast(self, self.basic, caster, nil, { castTime = Config.Reactions.Counter.CastTime, interrupt = true })
		end
	elseif name == "guardian" then
		local ally = payload.ally
		local G = Config.Reactions.Guardian
		if ally and ally.hp > 0 and ally ~= f and (flat(ally.pos) - flat(f.pos)).Magnitude <= G.Range and startReaction(self, "guardian", G.CastTime + 0.3) then
			self.guardianReadyAt = f.clock + G.Cooldown
			local shieldSpell: Spells.Spell? = nil
			for _, spell in self.spells do
				if spell.kind == "shield" and spell.allyCast and spellReady(self, spell) then
					shieldSpell = spell
					break
				end
			end
			self.ctx.fx.crystalFlash(f.model, GOLD, G.CastTime, 2.5)
			startCast(self, shieldSpell or WARD, ally, nil, { castTime = G.CastTime, allyTarget = ally })
		end
	elseif name == "combo" then
		local point: Vector3? = payload.point
		local spell: Spells.Spell? = payload.spell
		if point and spell and spellReady(self, spell) and (flat(point) - flat(f.pos)).Magnitude <= f.range and startReaction(self, "combo", 0.4) then
			pop(self, pick(Config.Lines.combo), CYAN, 28, true)
			startCast(self, spell, nil, point, { mult = 1 + Config.Reactions.Combo.Bonus })
		end
	end
end

-- Schránka událostí → reakce.
local function drainInbox(self: Brain)
	local f = self.f
	local inbox = self.inbox
	if #inbox == 0 then
		return
	end
	self.inbox = {}
	local R = Config.Reactions
	for _, event in inbox do
		local name, payload = event.name, event.payload
		if name == "hit" then
			addFury(self, R.Fury.PerHit)
			flinch(self, payload.attacker)
		elseif name == "kill" then
			if payload.killer == f then
				addFury(self, R.Fury.PerKill)
				flourish(self)
			end
		elseif name == "allyHurt" then
			local ally = payload.ally
			if ally and ally ~= f then
				addFury(self, R.Fury.PerAllyHurt)
				local G = R.Guardian
				if self.level >= G.MinLevel and self.guardianReadyAt <= f.clock and ally.hp > 0 and (flat(ally.pos) - flat(f.pos)).Magnitude <= G.Range then
					pop(self, pick(Config.Lines.allyHurt), GOLD, 24)
					queueSkill(self, "guardian", { ally = ally })
				end
			end
		elseif name == "allyDown" then
			if payload.victim ~= f then
				avenger(self, payload.killer)
			end
		elseif name == "enemyCharging" then
			local brute, from, to = payload.brute, payload.from, payload.to
			if from and to then
				local CA = R.ChargeAlert
				if distanceToSegment(f.pos, from, to) <= CA.HopTrigger then
					pop(self, "!", ORANGE, 26, true)
					if self.level >= CA.HopMinLevel and self.hopReadyAt <= f.clock then
						queueSkill(self, "chargeAlert", { mode = "hop", brute = brute, from = from, to = to })
					else
						local shieldSpell = spellOfKind(self, "shield")
						if shieldSpell and not (self.casting and not self.casting.spell.basic) then
							startCast(self, shieldSpell, nil, nil)
						end
					end
				elseif brute and self.tripReadyAt <= f.clock and (flat(brute.pos) - flat(f.pos)).Magnitude <= f.range then
					for _, ally in alliesOf(self) do
						if (flat(ally.pos) - flat(to)).Magnitude <= CA.AllyTrigger then
							pop(self, "!", ORANGE, 24, true)
							queueSkill(self, "chargeAlert", { mode = "trip", brute = brute, from = from, to = to })
							break
						end
					end
				end
			end
		elseif name == "shamanCast" or (name == "bossTelegraph" and payload.ability == "heal") then
			local caster = if name == "shamanCast" then payload.shaman else payload.boss
			if caster and caster.hp > 0 and self.counterReadyAt <= f.clock and (flat(caster.pos) - flat(f.pos)).Magnitude <= f.range + R.Counter.ExtraRange then
				queueSkill(self, "counter", { caster = caster })
			end
		elseif name == "lastEnemy" then
			self.lastEnemy = payload.enemy
		elseif name == "playerSpell" then
			local point: Vector3? = payload.point
			if point and (flat(point) - flat(f.pos)).Magnitude <= f.range then
				for _, spell in self.spells do
					if (spell.kind == "aoe" or spell.kind == "pull") and spellReady(self, spell) then
						queueSkill(self, "combo", { point = point, spell = spell, until_ = f.clock + R.Combo.Window })
						break
					end
				end
			end
		elseif name == "battleStart" then
			salute(self)
		elseif name == "waveEvent" then
			local id = payload.id
			local lines = Config.Lines[id]
			if lines then
				pop(self, pick(lines), if id == "ambush" then ORANGE else WHITE, 26, true)
			end
			local at: Vector3? = nil
			if payload.fighter then
				at = payload.fighter.pos
			elseif payload.points and payload.points[1] then
				at = payload.points[1]
			elseif payload.pos then
				at = payload.pos
			end
			if at then
				look(self, at)
			end
		end
	end
end

-- Čekající dovednost: po reakční době se spustí, pokud neběží silný cast (ten počká ≤ 0,4 s, pak propadá).
local function tickPending(self: Brain)
	local pending = self.pending
	if not pending then
		return
	end
	local clock = self.f.clock
	if clock < pending.readyAt then
		return
	end
	local cast = self.casting
	if cast and not cast.spell.basic then
		if clock - pending.readyAt > 0.4 then
			self.pending = nil
		end
		return
	end
	if pending.name == "combo" and pending.payload.until_ and clock > pending.payload.until_ then
		self.pending = nil
		return
	end
	self.pending = nil
	fireSkill(self, pending)
end

-- Vizuály každý tick: vznášení při Overcharge, runy, konec Overcharge, stroboskop Last Standu, vyprchávání Zuřivosti.
local function tickVisuals(self: Brain, dt: number)
	local f, ctx = self.f, self.ctx
	-- Enemies knocked back by a repel slide away (ease out: fast first, slowing).
	for i = #self.pushes, 1, -1 do
		local p = self.pushes[i]
		local enemy = p.enemy
		if enemy.hp <= 0 or p.left <= 0.01 then
			table.remove(self.pushes, i)
		else
			local step = math.min(p.left, math.max(p.speed * dt * (0.4 + 1.2 * p.left / (p.speed * 0.25)), 0.05))
			local next = clampToArena(self, enemy.pos + p.dir * step)
			enemy.pos = Vector3.new(next.X, enemy.pos.Y, next.Z)
			p.left -= step
			ctx.face(enemy, enemy.pos - p.dir)
		end
	end
	local O = Config.Reactions.Overcharge
	local F = Config.Reactions.Fury
	if self.overchargeUntil > 0 and f.clock >= self.overchargeUntil then
		endOvercharge(self)
	end
	local wantHover = if isOvercharged(self) then O.Hover else 0
	local changed = false
	if self.hover ~= wantHover then
		local step = O.Hover / O.HoverTime * dt
		if math.abs(wantHover - self.hover) <= step then
			self.hover = wantHover
		else
			self.hover += if wantHover > self.hover then step else -step
		end
		changed = true
	end
	-- GLIDE: while the mage moves it floats up a little, leans into the motion and bobs (a mage, not a jogger);
	-- a few arcane sparks trail under it. It lifts off and settles smoothly.
	local G = Config.Glide
	if self.glide ~= self.glideTarget then
		local step = dt / G.Time
		self.glide = if math.abs(self.glideTarget - self.glide) <= step then self.glideTarget else self.glide + (if self.glideTarget > self.glide then step else -step)
		f.model:SetAttribute("Glide", self.glide) -- the client dangles the legs and widens the aura
		changed = true
	end
	if self.glide > 0 then
		local bob = math.sin(f.clock * G.BobSpeed) * G.Bob * self.glide
		f.lift = f.baseLift + self.hover + self.glide * G.Height + bob
		f.tilt = -G.Lean * self.glide
		changed = true
		if self.glide > 0.5 and f.clock - self.glideSparkAt >= G.SparkEvery and ctx.fx.sparks then
			self.glideSparkAt = f.clock
			ctx.fx.sparks(ctx.parent, f.pos + Vector3.new(0, 0.3, 0), self.basic.color, 2, 0.7, 1.2)
		end
	elseif changed or f.tilt ~= 0 then
		f.lift = f.baseLift + self.hover
		f.tilt = 0
		changed = true
	end
	-- (the facing is refreshed every tick by turnStep, which also applies the new lift / lean)
	local ring = self.runeRing
	if ring then
		ring.update(f.pos + UP * (f.lift + 0.3), dt)
	end
	local reaction = self.reaction
	if reaction and reaction.name == "lastStand" and reaction.endsAt > f.clock and f.clock >= self.strobeNext then
		self.strobeNext = f.clock + 0.1
		ctx.fx.crystalFlash(f.model, if math.floor(f.clock * 10) % 2 == 0 then RED else WHITE, 0.1, 2.5)
	end
	if self.fury > 0 and f.clock - self.furyIdleSince > F.DecayDelay then
		self.fury = math.max(0, self.fury - F.Decay * dt)
	end
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
	local inRange = if dist <= maxRange then w.InRange else 0
	local score = inRange + proximity * w.Proximity + lowHp * w.LowHp + hate * w.Hate + typePriority * w.Type
	if enemy.ai and enemy.ai.state == "windup" then
		score += w.Casting or 0 -- právě sesílá: přerušit / potrestat
	end
	if enemy.champion then
		score += Config.ChampionBonus or 0.3
	end
	return score
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
	local _, nearestDist = nearest(f.pos, enemies)
	local dangerCount = 0
	for _, enemy in enemies do
		if (flat(enemy.pos) - flat(f.pos)).Magnitude <= Config.SurroundDistance then
			dangerCount += 1
		end
	end
	local hpFrac = f.hp / math.max(f.maxHp, 1)
	local hazardList = ctx.hazards()
	-- Nová hrozba na zemi poblíž: oranžové „!“ (útěk řeší skóre escape). Trvalé louže se nepočítají: stojí celou
	-- bitvu a nejsou žádná novinka.
	local alertCount = 0
	for _, hazard in hazardList do
		if hazard.kind ~= "puddle" then
			alertCount += 1
		end
	end
	if alertCount > self.knownHazards then
		for _, hazard in hazardList do
			if hazard.kind ~= "puddle" and (flat(hazard.pos) - flat(f.pos)).Magnitude <= hazard.radius + 4 then
				pop(self, "!", ORANGE, 24, true)
				break
			end
		end
	end
	self.knownHazards = alertCount
	local hazard = hazardAt(self, f.pos)
	local targetDist = if target then (flat(target.pos) - flat(f.pos)).Magnitude else math.huge
	local anyInRange = nearestDist <= range

	-- FINISH: poslední nepřítel pod hranicí v dosahu (jednou za bitvu).
	local last = self.lastEnemy
	if last and not self.finishUsed and last.hp > 0 and last.hp < Config.Reactions.Finish.Below * last.maxHp and (flat(last.pos) - flat(f.pos)).Magnitude <= range and not (self.casting and not self.casting.spell.basic) then
		self.target = last
		self.targetSince = clock
		finish(self, last)
		if self.casting then
			self.action = "attack"
			return
		end
	end

	-- Skóre akcí. Stojí a střílí, kdykoli má někoho v dosahu; jde dopředu jen, když nemá nikoho.
	local scores: { [string]: number } = {}
	scores.idle = U.IdleScore
	scores.attack = if target and targetDist <= range then U.AttackBase + 0.15 * clamp01(1 - targetDist / range) else 0
	scores.approach = if not anyInRange and #enemies > 0 then U.ApproachBase else 0
	scores.escape = if hazard then U.HazardEscape else 0
	local shieldSpell = spellOfKind(self, "shield")
	scores.shield = if shieldSpell and (hpFrac < U.ShieldBelowHp or (dangerCount >= 2 and hpFrac < 0.6)) then U.ShieldScore else 0
	local repelSpell = spellOfKind(self, "repel")
	scores.repel = if repelSpell and dangerCount >= Config.SurroundedCount then U.Repel else 0
	local blinkSpell = spellOfKind(self, "blink")
	scores.blink = if blinkSpell and not repelSpell and dangerCount >= Config.SurroundedCount then U.BlinkScore else 0
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
		if self.avengerBonus and score > 0 then
			score = math.min(1, score + 0.15) -- Mstitel: silné kouzlo je zdarma, tak s ním neotálí
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

	-- Čekající dovednostní reakce: žádné nové kouzlo nezačne (hop/protikouzlo/strážce/kombo přijde za okamžik).
	if self.pending then
		scores.strong, scores.shield, scores.blink, scores.support, scores.repel = 0, 0, 0, 0, 0
		if self.pending.name == "chargeAlert" and self.pending.payload.mode == "hop" then
			scores.escape = 0 -- hop JE útěk z dráhy; jinak by mág nejdřív odešel a pak ještě odskočil jinam
		end
	end

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
	if mistake and bestAction ~= "escape" then
		if bestAction == "strong" and strongPoint then
			local angle = math.random() * math.pi * 2
			local err = Config.AimError * (1 - clamp01((self.level - 1) / 29))
			strongPoint = (strongPoint :: Vector3) + Vector3.new(math.cos(angle) * err, 0, math.sin(angle) * err)
		else
			self.hesitateUntil = clock + Config.Hesitation[1] + math.random() * (Config.Hesitation[2] - Config.Hesitation[1])
		end
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
	elseif bestAction == "repel" and repelSpell then
		startCast(self, repelSpell, nil, nil)
		look(self, (nearest(f.pos, enemies) or { pos = f.pos + Vector3.new(0, 0, 10) }).pos)
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
			local reaction = if self.reaction and self.reaction.endsAt > clock then self.reaction.name else "-"
			label.Text = string.format("%s %.2f → %s  [%s]\nmana %d  fury %d  hp %d%%  L%d", bestAction, self.actionScore, targetName, reaction, math.floor(self.mana), math.floor(self.fury), math.floor(hpFrac * 100), self.level)
		end
	elseif self.debugLabel then
		local gui = self.debugLabel.Parent
		if gui then
			gui:Destroy()
		end
		self.debugLabel = nil
	end
end

-- ── Provedení akce (každý tick) ─────────────────────────────────────────────

-- Krok k cíli. Leží-li před mágem telegrafovaná plocha (louže, dráha nájezdu), neprojde skrz: uhne kolmo na tu stranu,
-- která vede dál od jejího středu, a obejde ji po okraji. Stojí-li už uvnitř, řeší to akce escape (žádné uhýbání).
local function moveTowards(self: Brain, goal: Vector3, dt: number, speedFactor: number)
	local f = self.f
	local rate = (if f.slowUntil > f.clock then f.slowFactor else 1) * (f.haste or 1)
	local delta = flat(goal) - flat(f.pos)
	local dist = delta.Magnitude
	if dist < 0.05 then
		setGlide(self, false)
		return
	end
	local stepLength = math.min(f.speed * dt * rate * speedFactor, dist)
	local dir = delta.Unit
	local step = dir * stepLength
	local ahead = hazardAt(self, f.pos + dir * math.max(stepLength, Config.HazardLookahead))
	if ahead and not hazardAt(self, f.pos) then
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local center = flat(ahead.pos)
		local here = flat(f.pos)
		local side = if (here + perp - center).Magnitude >= (here - perp - center).Magnitude then perp else -perp
		step = side * stepLength
		if hazardAt(self, f.pos + side * math.max(stepLength, Config.HazardLookahead)) then
			step = (side - dir).Unit * stepLength -- obě strany kryté: krok šikmo zpět, ne dovnitř
		end
	end
	local next = clampToArena(self, f.pos + step)
	f.pos = Vector3.new(next.X, f.pos.Y, next.Z)
	setGlide(self, true)
end

local function act(self: Brain, dt: number)
	local f = self.f
	local target = self.target
	local action = self.action
	local enemies = enemiesOf(self)
	local nearestEnemy = nearest(f.pos, enemies)
	local range = f.range

	if action == "escape" then
		-- Ven z telegrafované plochy nejkratší cestou (od jejího středu), kousek za okraj; u trvalé louže dál, a po
		-- vystoupení chvíli stojí, aby se útěk a přiblížení nestřídaly každé rozhodnutí.
		local hazard = hazardAt(self, f.pos)
		if hazard then
			local away = flat(f.pos) - flat(hazard.pos)
			if away.Magnitude < 0.1 then
				away = Vector3.new(0, 0, -1)
			end
			local exit = if hazard.kind == "puddle" then Config.HazardExitLong else Config.HazardExit
			local goal = hazard.pos + away.Unit * (hazard.radius + exit)
			moveTowards(self, clampToArena(self, goal), dt, 1)
		else
			setGlide(self, false)
			self.action = "idle"
			self.reactionBusyUntil = math.max(self.reactionBusyUntil, f.clock + Config.HazardHold)
		end
		if target then
			look(self, target.pos)
		end
		return
	end

	if action == "approach" then
		-- Nikdo v dosahu: jde k nejbližšímu nepříteli a zastaví v tom okamžiku, kdy ho má v dosahu (i mezi dvěma
		-- rozhodnutími, takže nikdy nedošlapuje k nepříteli, kterého už může střílet).
		local goal = nearestEnemy
		if goal then
			local dist = (flat(goal.pos) - flat(f.pos)).Magnitude
			if dist > range then
				moveTowards(self, goal.pos, dt, 1)
			else
				setGlide(self, false)
			end
			look(self, goal.pos)
		else
			setGlide(self, false)
		end
		return
	end

	if action == "attack" and target then
		-- Stojí na místě, dívá se na cíl a střílí v tempu útoku mága (při Overcharge rychleji).
		setGlide(self, false)
		look(self, target.pos)
		local dist = (flat(target.pos) - flat(f.pos)).Magnitude
		local rate = (if f.slowUntil > f.clock then f.slowFactor else 1) * (f.haste or 1)
		f.timer -= dt * rate
		if f.timer <= 0 and dist <= range + 1 then
			f.timer = f.cooldown * (if isOvercharged(self) then Config.Reactions.Overcharge.CooldownFactor else 1)
			-- Smrtící střela = poprava (velká bílá koule, zlaté číslo).
			local lethal = f.damage * self.basic.damage >= target.hp
			startCast(self, self.basic, target, nil, { execute = lethal })
		end
		return
	end

	-- idle a vše ostatní: stojí, dívá se na cíl nebo na nejbližšího nepřítele; z nudy gesto.
	setGlide(self, false)
	local lookAt = if target then target.pos elseif nearestEnemy then nearestEnemy.pos else nil
	if lookAt then
		look(self, lookAt)
	end
	if f.clock >= self.fidgetAt and reactionFree(self) then
		fidget(self, lookAt)
	end
end

-- Jeden tick bitvy pro mága: regenerace, události → reakce, vizuály, hop, dokončení castu, čekající dovednost,
-- zaváhání, rozhodnutí v intervalu, akce.
local function updateInner(self: Brain, dt: number)
	local f = self.f
	self.mana = math.min(Config.Mana.Max, self.mana + Config.Mana.Regen * dt)

	drainInbox(self)
	tickVisuals(self, dt)

	-- LAST STAND: pod hranicí HP, jednou za bitvu.
	if not self.lastStandUsed and f.hp < Config.Reactions.LastStand.Below * f.maxHp then
		lastStand(self)
	end
	local reaction = self.reaction
	if reaction and reaction.endsAt <= f.clock then
		self.reaction = nil
	end

	-- Dovednostní reakce po reakční době (může zrušit základní střelu a začít vlastní cast).
	tickPending(self)

	-- Hop: jen pohyb po úsečce (poslední tick dosedne na cíl), pak krátké stání.
	if self.hopUntil > 0 then
		hopTick(self)
		return
	end

	-- BLINK DODGE: a melee enemy is about to reach the mage.
	if tryDodge(self) then
		return
	end

	local cast = self.casting
	if cast then
		if f.clock >= cast.at then
			self.casting = nil
			resolve(self, cast)
		else
			setGlide(self, false)
			local target = cast.target
			local lookAt = cast.point or (target and target.hp > 0 and target.pos)
			if lookAt then
				look(self, lookAt)
			end
		end
		return
	end
	if f.clock < self.reactionBusyUntil or f.clock < self.hesitateUntil then
		setGlide(self, false)
		-- Busy (a reaction, recovering from a blink, hesitating): it keeps watching its target.
		local watch = self.target
		if watch and watch.hp > 0 then
			look(self, watch.pos)
		end
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

function MageBrain.update(self: Brain, dt: number)
	local f = self.f
	if f.hp <= 0 then
		return
	end
	updateInner(self, dt)
	-- TRACKING: with nothing else to look at, the mage watches its target, or the nearest enemy from afar.
	if not self.lookGoal or (self.target and self.target.hp > 0 and not self.casting and self.hopUntil <= 0 and self.action ~= "approach") then
		local watch = if self.target and self.target.hp > 0 then self.target else nearest(f.pos, enemiesOf(self))
		if watch then
			self.lookGoal = watch.pos
		end
	end
	turnStep(self, dt)
end

return MageBrain
