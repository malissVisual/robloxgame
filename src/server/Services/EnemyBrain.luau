--!strict
-- The enemies' battle AI: one small brain per goblin (`fighter.ai`), created by BattleService.start for every enemy
-- whose archetype is not the Rift King (bosses included) and by battle.spawnEnemy. BattleService calls
-- brain:update(dt) every tick; `true` means the brain handled the tick itself (a wind-up, a charge, a scurry, its own
-- attack), `false` lets the default "walk to the nearest and hit" loop do the boring part.
--
-- Personalities (numbers in shared/Config/EnemyAI.luau):
--   GRUNT   pack hunter. WAR CRY: the first grunt to see a soldier stops 0.6 s and roars; the pack runs 20 % faster
--           for 3 s (one cry per 8 s per wave). FLANK: when grunts share a target every second one aims 3 studs
--           beside it, so they wrap around instead of stacking. GANG UP: +10 % damage per other grunt nearby (≤ +30 %).
--   ARCHER  cowardly skirmisher. Shoots the soldier with the LOWEST HP fraction (teaches healing / shields). SCURRY:
--           a melee soldier within 8 studs → "EEK!", runs 8 studs straight away over 0.9 s, then stands and shoots
--           even if the threat is still there; HARD LIMIT one scurry per 6 s (a cornered archer dies, it never
--           dances). FOCUS FIRE: with 2+ archers, every 7 s all archers shoot the same soldier for 3 s after 0.3 s of
--           red beams (the volley lands together). Never the player's own character (only fighters are targets).
--   BRUTE   charger / the wall. CHARGE: a target 7-14 studs away → 0.8 s wind-up with an ORANGE LANE locked on the
--           floor (data hazards for the Mage, "enemyCharging" event), then runs the lane at 40 studs/s (slowed by the
--           Mage's trip), stops at a soldier on the path or at the lane's end: soldiers within 3 studs take 1.6×,
--           are pushed and stunned; players standing in the end circle lose 20 HP. Nobody hit → DIZZY 0.8 s with a
--           spinning star (the dodge is rewarded on screen). GUARD: near an allied Archer / Shaman it is the wall
--           (taunt 8). ENRAGE under 30 % HP: faster for the rest of the fight.
--   SHAMAN  support caster that stays behind: advances only while the nearest soldier is farther than 18 studs and
--           NEVER retreats (after 40 s it comes to 10 studs so a lone shaman cannot run the clock). Every 6 s a 0.6 s
--           wind-up with orbiting runes ("shamanCast" event): MEND an ally under 60 %, else FRENZY a fighting Grunt /
--           Brute (+35 % damage, 15 % faster, "FRENZY" tag), else HEX the soldier with the highest damage (−30 %,
--           "HEX" tag). A hit of 15 % max HP or the Mage's counter-spell during the wind-up fizzles it.
--   BOSSES  Brute: SLAM — 0.9 s orange circle (radius 9), 2× damage + 1 s stun inside, players lose 25 HP.
--           Archer: VOLLEY — 0.7 s red beams to every soldier in range, then the arrows (0.6×). Shaman: HEAL — 0.6 s
--           green ring, every enemy heals 8 % (a counter-spell halves it: "WEAKENED"). Chief: SUMMON at 50 % HP (0.8 s
--           purple circles where the mobs appear), RALLY HORN every 10 s (+25 % damage and speed around it for 4 s),
--           DESPERATE CALL at 25 % (two more mobs). PHASE 2 at 50 % (every boss, once): a roar, 25 % faster
--           abilities, 5 % bigger.
--   TREASURE flees from the nearest soldier every tick (slides along the arena edge when cornered), never attacks.
--   TOTEM   stands (the healing aura belongs to the wave twists).
--   Bodyguards (`ai.guard = boss`) stay within 8 studs of their boss until it is under half HP or a soldier comes
--   within 12 studs.
--
-- Rules: every area attack = a floor telegraph (ctx.fx.warningCircle / warningLane, destroyed at impact) + a data
-- hazard (ctx.addHazard, what the Mage reads) + an event, at least 0.6 s ahead. Every voluntary move is short,
-- committed and followed by standing; Grunt / Brute / Shaman never retreat. Everything that changes state runs on the
-- battle clock (ctx.schedule, fighter clocks), never task.delay. Decisions every Config.Decide (0.25 s, staggered),
-- movement every tick, O(fighters) per decision.
--
-- Interface (duck-typed, used by BattleService and the Mage brain): EnemyBrain.new(ctx, fighter, archetype, boss);
-- brain:update(dt): boolean; brain:onDamaged(attacker?, amount); brain:onEvent(name, payload); brain:interrupt():
-- boolean (true when a wind-up was fizzled / a boss heal halved); brain:destroy(); brain:buff(damage?, haste?, time).
-- Readable: brain.state ("advance" | "attack" | "windup" | "charge" | "dizzy" | "scurry" | "hold" | "cry" | "guard" |
-- "flee" | "stand" | "roar" | "fight"), brain.castKind while winding up, brain.cooldownFactor (1; a champion 0.5),
-- brain.guard. The header above `local UP` is replaced by the test harness (tools/tests/run_enemybrain_test.py):
-- no other requires here; the visuals come through ctx.fx (BattleFx).

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.EnemyAI)
local Rig = require(Shared.Rig)

local UP = Vector3.new(0, 1, 0)

local WHITE = Color3.new(1, 1, 1)

-- What a brain gets from BattleService (built once per battle). Fighters are the plain records of BattleService
-- (side, hp, maxHp, pos, lift, range, speed, cooldown, timer, damage, clock, stunUntil, slowUntil, slowFactor, haste,
-- buffDamage, buffUntil, hexFactor, hexUntil, taunt, passive, passiveValue, kind, boss, model, ai).
export type Context = {
	fighters: { any },
	playerSide: number,
	parent: Instance, -- plot.folder (rings, sparks, beams)
	fx: any, -- BattleFx; a table of no-op functions in the tests
	fxFolder: Instance, -- battle.fx: telegraph parts, pops (destroyed with the battle)
	groundY: (pos: Vector3) -> number,
	attack: (f: any, target: any, mult: number) -> (), -- a standard attack (performAttack: passives, effect, splash)
	hurt: (target: any, amount: number, source: any?) -> number,
	heal: (target: any, amount: number) -> (),
	face: (f: any, pos: Vector3) -> (),
	bounds: { center: Vector3, halfX: number, halfZ: number },
	emit: (name: string, payload: any) -> (),
	addHazard: (pos: Vector3, radius: number, duration: number, kind: string, source: any?) -> (),
	schedule: (delay: number, fn: () -> ()) -> (),
	addMover: (fn: (dt: number) -> boolean) -> (),
	notify: (text: string) -> (),
	spawnEnemy: (kind: string, tier: number, pos: Vector3) -> any,
	hitPlayers: (center: Vector3, radius: number, hp: number) -> (),
	clock: () -> number, -- the battle clock
	speed: () -> number, -- the battle speed (animations)
	wave: number,
	archetype: (f: any) -> string?,
	summonKind: string?,
	summonTier: number,
	flags: { [string]: any }, -- shared per battle: lastWarcry, focusNext, focusTarget, focusUntil
}

type HasteBuff = { factor: number, endsAt: number }

export type Brain = {
	ctx: Context,
	f: any,
	archetype: string,
	boss: boolean,
	index: number,
	state: string,
	castKind: string?,
	cooldownFactor: number, -- ability cooldowns × this (phase 2: 0.75, a champion: 0.5)
	guard: any?, -- a bodyguard's boss
	destroyed: boolean,
	thinkIn: number,
	stateUntil: number, -- fighter clock when the current timed state ends
	token: number, -- scheduled callbacks check it (a fizzle / destroy invalidates them)
	parts: { Instance }, -- telegraph parts and the dizzy star (destroyed at impact / destroy)
	runeRing: any?,
	-- Buffs on this fighter (haste is multiplicative, the damage bonus additive; both restored on expiry).
	hasteBase: number,
	hasteBuffs: { HasteBuff },
	gang: number,
	extraDamage: number,
	extraUntil: number,
	-- Targeting and the archetype's timers (fighter clock).
	target: any?,
	retargetAt: number,
	cryReadyAt: number,
	flanking: boolean,
	flankSign: number,
	scurryReadyAt: number,
	moveFrom: Vector3?,
	moveTo: Vector3?,
	moveStart: number,
	moveTime: number,
	chargeReadyAt: number,
	chargeFrom: Vector3?,
	chargeTo: Vector3?,
	chargeDir: Vector3?,
	chargeLen: number,
	chargeTravel: number,
	chargeStart: number,
	enraged: boolean,
	castReadyAt: number,
	castTarget: any?,
	castPoints: { Vector3 }?,
	castCount: number,
	healWeakened: boolean,
	nextAbilityAt: number,
	phase2: boolean,
	summonedOnce: boolean,
	desperateOnce: boolean,
	update: (self: Brain, dt: number) -> boolean,
	onDamaged: (self: Brain, attacker: any?, amount: number?) -> (),
	onEvent: (self: Brain, name: string, payload: any) -> (),
	interrupt: (self: Brain) -> boolean,
	destroy: (self: Brain) -> (),
	buff: (self: Brain, damageBonus: number?, hasteFactor: number?, duration: number) -> (),
}

local EnemyBrain = {}
EnemyBrain.__index = EnemyBrain

local created = 0 -- stagger of the decisions and the flank parity

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	return (flat(a) - flat(b)).Magnitude
end

-- Distance from point p to the segment a → b (all flat).
local function distToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = flat(b - a)
	local len2 = ab.X * ab.X + ab.Z * ab.Z
	if len2 < 1e-6 then
		return flatDist(p, a)
	end
	local ap = flat(p - a)
	local t = math.clamp((ap.X * ab.X + ap.Z * ab.Z) / len2, 0, 1)
	return flatDist(p, a + ab * t)
end

-- Keeps a written position inside the arena with a margin of 3 studs (the Y is kept).
local MARGIN = 3
local function clampToArena(self: Brain, pos: Vector3): Vector3
	local b = self.ctx.bounds
	local x = math.clamp(pos.X, b.center.X - b.halfX + MARGIN, b.center.X + b.halfX - MARGIN)
	local z = math.clamp(pos.Z, b.center.Z - b.halfZ + MARGIN, b.center.Z + b.halfZ - MARGIN)
	return Vector3.new(x, pos.Y, z)
end

-- The movement / attack rate of a fighter right now (slows and hastes).
local function rateOf(f: any): number
	return (if f.slowUntil > f.clock then f.slowFactor else 1) * f.haste
end

local function isSoldier(self: Brain, o: any): boolean
	return o.side == self.ctx.playerSide and o.hp > 0
end

local function isAlly(self: Brain, o: any): boolean
	return o ~= self.f and o.side == self.f.side and o.hp > 0
end

local function archetypeOf(self: Brain, o: any): string?
	if o.ai and o.ai.archetype then
		return o.ai.archetype
	end
	return self.ctx.archetype(o)
end

-- The nearest soldier, with the same taunt rules as BattleService.nearestEnemy (a Tank's Bulwark, a brute's wall).
local function nearestFoe(self: Brain): any?
	local f = self.f
	local best, bestDist = nil, math.huge
	local taunter, taunterDist = nil, math.huge
	for _, o in self.ctx.fighters do
		if isSoldier(self, o) then
			local d = flatDist(o.pos, f.pos)
			if d < bestDist then
				best, bestDist = o, d
			end
			if ((o.passive == "taunt" and d <= o.passiveValue) or (o.taunt and d <= o.taunt)) and d < taunterDist then
				taunter, taunterDist = o, d
			end
		end
	end
	return taunter or best
end

-- The soldier with the lowest HP fraction within `maxDist` of the fighter (the archers' pick).
local function weakestFoe(self: Brain, maxDist: number): any?
	local f = self.f
	local best, bestFraction = nil, math.huge
	for _, o in self.ctx.fighters do
		if isSoldier(self, o) and flatDist(o.pos, f.pos) <= maxDist then
			local fraction = o.hp / math.max(o.maxHp, 1)
			if fraction < bestFraction then
				best, bestFraction = o, fraction
			end
		end
	end
	return best
end

local function anySoldierWithin(self: Brain, pos: Vector3, radius: number): boolean
	for _, o in self.ctx.fighters do
		if isSoldier(self, o) and flatDist(o.pos, pos) <= radius then
			return true
		end
	end
	return false
end

local function pop(self: Brain, text: string, color: Color3, size: number?)
	local f = self.f
	self.ctx.fx.pop(self.ctx.fxFolder, f.pos + UP * (f.lift + 3), text, color, size)
end

local function destroyParts(self: Brain)
	for _, part in self.parts do
		part:Destroy()
	end
	table.clear(self.parts)
end

local function addParts(self: Brain, list: any)
	if type(list) == "table" then
		for _, part in list do
			if part then
				table.insert(self.parts, part)
			end
		end
	elseif list then
		table.insert(self.parts, list)
	end
end

-- A scheduled callback that only runs while the brain is alive and nothing (a fizzle, a death) invalidated it.
local function later(self: Brain, delay: number, fn: () -> ())
	local token = self.token
	self.ctx.schedule(delay, function()
		if not self.destroyed and self.token == token and self.f.hp > 0 then
			fn()
		end
	end)
end

local function setMoving(self: Brain, moving: boolean)
	Rig.setMoving(self.f.model, moving)
end

-- A short orange flash on the brute's head (the wind-up of a charge).
local function headFlash(self: Brain, color: Color3, duration: number)
	local head = self.f.model:FindFirstChild("Head")
	if not head then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 9
	light.Brightness = 3
	light.Parent = head
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 0 }):Play()
	Debris:AddItem(light, duration + 0.05)
end

-- ── Buffs (haste multiplicative with a base, the damage bonus additive; both expire on the fighter's clock) ──

local function recomputeHaste(self: Brain)
	local product = 1
	for _, buff in self.hasteBuffs do
		product *= buff.factor
	end
	self.f.haste = self.hasteBase * product
end

local function refreshDamageBuff(self: Brain)
	local f = self.f
	local extra = if self.extraUntil > f.clock then self.extraDamage else 0
	f.buffDamage = self.gang + extra
	if f.buffDamage > 0 then
		local gangUntil = if self.gang > 0 then f.clock + Config.Decide + 0.15 else 0
		f.buffUntil = math.max(gangUntil, if extra > 0 then self.extraUntil else 0)
	else
		f.buffUntil = 0
	end
end

local function tickBuffs(self: Brain)
	local f = self.f
	local changed = false
	for i = #self.hasteBuffs, 1, -1 do
		if self.hasteBuffs[i].endsAt <= f.clock then
			table.remove(self.hasteBuffs, i)
			changed = true
		end
	end
	if changed then
		recomputeHaste(self)
	end
	if self.extraUntil > 0 and self.extraUntil <= f.clock then
		self.extraUntil = 0
		self.extraDamage = 0
		refreshDamageBuff(self)
	end
end

-- Gives `target` (an enemy) a damage bonus and / or a haste for `duration` seconds through its brain when it has one.
local function buffTarget(ctx: Context, target: any, damageBonus: number?, hasteFactor: number?, duration: number)
	local ai: any = target.ai
	if ai and ai.buff then
		(ai.buff :: any)(ai, damageBonus, hasteFactor, duration)
		return
	end
	if damageBonus and damageBonus > 0 then
		target.buffDamage = math.max(damageBonus, if target.buffUntil > target.clock then target.buffDamage else 0)
		target.buffUntil = target.clock + duration
	end
	if hasteFactor and hasteFactor ~= 1 then
		target.haste = hasteFactor
		ctx.schedule(duration, function()
			target.haste = 1
		end)
	end
end

-- ── Grunt: pack hunter ──────────────────────────────────────────────────────

local function warCry(self: Brain)
	local f, ctx, G = self.f, self.ctx, Config.Grunt
	local color = Config.Colors.cry
	self.state = "cry"
	self.stateUntil = f.clock + G.CryTime
	self.cryReadyAt = f.clock + G.CryCooldown
	ctx.flags.lastWarcry = ctx.clock()
	Rig.cast(f.model, "cast")
	setMoving(self, false)
	ctx.fx.groundRing(ctx.parent, f.pos, color, G.CryRadius, 0.6)
	pop(self, "RAAH!", color, 26)
	ctx.emit("warcry", { grunt = f })
	for _, o in ctx.fighters do
		if o.side == f.side and o.hp > 0 and archetypeOf(self, o) == "Grunt" and not o.boss and flatDist(o.pos, f.pos) <= G.CryRadius then
			buffTarget(ctx, o, nil, G.CryHaste, G.CryBuffTime)
			ctx.fx.tint(o.model, color, G.CryBuffTime)
		end
	end
end

local function gruntDecide(self: Brain, battleClock: number)
	local f, ctx, G = self.f, self.ctx, Config.Grunt
	if self.state == "cry" then
		return
	end
	-- GANG UP: +damage per other grunt close by (shown as extra sparks on its hits). Not in the first waves and not
	-- in the first seconds: the opening of a fight stays as gentle as before.
	local others = 0
	if ctx.wave >= G.GangFromWave and battleClock >= Config.AbilityGrace then
		for _, o in ctx.fighters do
			if isAlly(self, o) and not o.boss and archetypeOf(self, o) == "Grunt" and flatDist(o.pos, f.pos) <= G.GangRadius then
				others += 1
			end
		end
	end
	self.gang = math.min(G.GangMax, G.GangPer * others)
	refreshDamageBuff(self)
	-- Target and FLANK: grunts that share a target spread out around it (every second one aims beside it).
	local target = nearestFoe(self)
	self.target = target
	self.flanking = false
	if target then
		local shared = 0
		for _, o in ctx.fighters do
			if isAlly(self, o) and o.ai and o.ai.target == target and archetypeOf(self, o) == "Grunt" then
				shared += 1
			end
		end
		if shared >= 1 and self.index % 2 == 1 then
			self.flanking = true
			self.flankSign = if self.index % 4 == 1 then 1 else -1
		end
		-- WAR CRY: the first grunt that sees a soldier (one per pack per PackGap, per grunt per CryCooldown).
		local lastCry = ctx.flags.lastWarcry
		if battleClock >= Config.AbilityGrace and f.clock >= self.cryReadyAt and (lastCry == nil or battleClock - lastCry >= G.PackGap) and flatDist(target.pos, f.pos) <= G.CrySight then
			warCry(self)
		end
	end
end

local function gruntAct(self: Brain, dt: number): boolean
	local f, ctx = self.f, self.ctx
	if self.state == "cry" then
		if f.clock >= self.stateUntil then
			self.state = "advance"
		else
			if self.target and self.target.hp > 0 then
				ctx.face(f, self.target.pos)
			end
			return true
		end
	end
	local t = self.target
	if self.flanking and t and t.hp > 0 then
		local d = flat(t.pos - f.pos)
		local dist = d.Magnitude
		if dist > f.range + 1 and dist > 0.1 then
			local perp = Vector3.new(-d.Z, 0, d.X).Unit * (Config.Grunt.FlankOffset * self.flankSign)
			local goal = clampToArena(self, t.pos + perp)
			local toGoal = goal - f.pos
			local remaining = toGoal.Magnitude
			if remaining > 0.3 then
				f.pos += toGoal.Unit * math.min(f.speed * dt * rateOf(f), remaining)
				setMoving(self, true)
				ctx.face(f, goal)
				return true
			end
		end
	end
	return false -- in range (or no flank): the default loop hits the target
end

-- ── Archer: cowardly skirmisher ─────────────────────────────────────────────

local function startScurry(self: Brain, threat: any)
	local f, A = self.f, Config.Archer
	local away = flat(f.pos - threat.pos)
	if away.Magnitude < 0.1 then
		away = Vector3.new(0, 0, 1) -- straight back toward the enemy side
	end
	self.moveFrom = f.pos
	self.moveTo = clampToArena(self, f.pos + away.Unit * A.ScurryDistance)
	self.moveStart = f.clock
	self.moveTime = A.ScurryTime
	self.state = "scurry"
	self.scurryReadyAt = f.clock + A.ScurryCooldown -- HARD LIMIT: one scurry per cooldown, cornered or not
	pop(self, "EEK!", WHITE, 22)
	setMoving(self, true)
end

-- FOCUS FIRE: every archer picks the same soldier (the lowest HP fraction among those most archers can reach), red
-- beams for FocusTelegraph seconds, every timer set so the volley lands together. Only fighters can be targets, so the
-- player's own character is never shot at.
local function focusFire(self: Brain, battleClock: number): boolean
	local ctx, A = self.ctx, Config.Archer
	local archers: { any } = {}
	for _, o in ctx.fighters do
		if o.side == self.f.side and o.hp > 0 and not o.boss and o.ai and o.ai.archetype == "Archer" and o.ai.state ~= "scurry" then
			table.insert(archers, o)
		end
	end
	if #archers < A.FocusMinArchers then
		return false
	end
	local best: any, bestCount, bestFraction = nil, 0, math.huge
	for _, s in ctx.fighters do
		if isSoldier(self, s) then
			local count = 0
			for _, a in archers do
				if flatDist(a.pos, s.pos) <= a.range + 1 then
					count += 1
				end
			end
			local fraction = s.hp / math.max(s.maxHp, 1)
			if count > 0 and (count > bestCount or (count == bestCount and fraction < bestFraction)) then
				best, bestCount, bestFraction = s, count, fraction
			end
		end
	end
	if not best then
		return false
	end
	local flags = ctx.flags
	flags.focusTarget = best
	flags.focusUntil = battleClock + A.FocusTime
	for _, a in archers do
		a.ai.target = best
		a.ai.retargetAt = a.clock + A.FocusTime
		if flatDist(a.pos, best.pos) <= a.range + 1 then
			a.timer = A.FocusTelegraph
		end
		ctx.fx.beam(ctx.parent, a.pos + UP * a.lift, best.pos + UP * best.lift, Config.Colors.warning, 0.15, A.FocusTelegraph)
	end
	ctx.emit("focusFire", { archers = archers, target = best, at = battleClock + A.FocusTelegraph })
	return true
end

local function archerDecide(self: Brain, battleClock: number)
	local f, ctx, A = self.f, self.ctx, Config.Archer
	if self.state == "scurry" then
		return
	end
	local flags = ctx.flags
	if flags.focusNext == nil then
		flags.focusNext = A.FocusFirst
	end
	local focus = flags.focusTarget
	if focus and focus.hp > 0 and (flags.focusUntil or 0) > battleClock then
		self.target = focus
	else
		if battleClock >= flags.focusNext then
			flags.focusNext = battleClock + (if focusFire(self, battleClock) then A.FocusEvery else 1)
		end
		local t = self.target
		if not (t and t.hp > 0 and flatDist(t.pos, f.pos) <= f.range + 1) or f.clock >= self.retargetAt then
			self.target = weakestFoe(self, f.range + 1) or t
			self.retargetAt = f.clock + A.Retarget
		end
	end
	-- SCURRY from a melee soldier that comes close (once per ScurryCooldown).
	if f.clock >= self.scurryReadyAt then
		local threat, threatDist = nil, A.ScurryAt
		for _, o in ctx.fighters do
			if isSoldier(self, o) and o.range <= 6 then
				local d = flatDist(o.pos, f.pos)
				if d <= threatDist then
					threat, threatDist = o, d
				end
			end
		end
		if threat then
			startScurry(self, threat)
		end
	end
end

local function archerAct(self: Brain, dt: number): boolean
	local f, ctx = self.f, self.ctx
	if self.state == "scurry" then
		local from, to = self.moveFrom :: Vector3, self.moveTo :: Vector3
		local alpha = math.clamp((f.clock - self.moveStart) / self.moveTime, 0, 1)
		f.pos = from:Lerp(to, alpha)
		ctx.face(f, to + flat(to - from))
		if alpha >= 1 then
			self.state = "attack" -- stands and shoots now, whatever is near
			setMoving(self, false)
		end
		return true
	end
	local t = self.target
	if t and t.hp > 0 then
		local d = flat(t.pos - f.pos)
		local dist = d.Magnitude
		if dist <= f.range + 1 then
			f.timer -= dt * rateOf(f)
			if f.timer <= 0 then
				f.timer = f.cooldown
				ctx.attack(f, t, 1)
			end
			setMoving(self, false)
			ctx.face(f, t.pos)
		else
			f.pos += d.Unit * math.min(f.speed * dt * rateOf(f), dist - f.range)
			setMoving(self, true)
			ctx.face(f, t.pos)
		end
		self.state = "attack"
		return true
	end
	return false
end

-- ── Brute: charger / the wall ───────────────────────────────────────────────

local function startCharge(self: Brain, target: any)
	local f, ctx, B = self.f, self.ctx, Config.Brute
	local from = f.pos
	local d = flat(target.pos - from)
	local dir = d.Unit
	local len = math.min(d.Magnitude, B.ChargeRange)
	local to = from + dir * len -- LOCKED: the lane does not follow the target
	self.chargeFrom, self.chargeTo, self.chargeDir, self.chargeLen, self.chargeTravel = from, to, dir, len, 0
	self.state = "windup"
	self.castKind = "charge"
	self.stateUntil = f.clock + B.WindUp
	self.chargeReadyAt = f.clock + B.Cooldown * self.cooldownFactor
	addParts(self, ctx.fx.warningLane(ctx.fxFolder, from, to, B.Width, Config.Colors.charge, ctx.groundY(from)))
	local s = 0
	while true do
		ctx.addHazard(from + dir * s, B.HitRadius, B.WindUp, "charge", f)
		if s >= len then
			break
		end
		s = math.min(s + B.LaneStep, len)
	end
	ctx.emit("enemyCharging", { brute = f, from = from, to = to, impactAt = ctx.clock() + B.WindUp })
	Rig.cast(f.model, "jump")
	setMoving(self, false)
	headFlash(self, Config.Colors.charge, B.WindUp)
end

-- A charge that hit nobody: the brute stands stunned with a spinning star over its head.
local function dizzy(self: Brain)
	local f, ctx, B = self.f, self.ctx, Config.Brute
	self.state = "dizzy"
	self.stateUntil = f.clock + B.Dizzy
	f.stunUntil = f.clock + B.Dizzy
	local star: { any } = {}
	for _ = 1, 2 do
		local slab = ctx.fx.newPart(ctx.fxFolder, Vector3.new(2.4, 0.25, 0.45), CFrame.new(f.pos + UP * (f.lift + 2.6)), Config.Colors.dizzy, 0)
		if slab then
			table.insert(star, slab)
			table.insert(self.parts, slab)
		end
	end
	local angle = 0
	local token = self.token
	ctx.addMover(function(dt: number): boolean
		if self.destroyed or self.token ~= token or f.hp <= 0 or f.clock >= self.stateUntil then
			for _, slab in star do
				slab:Destroy()
			end
			return false
		end
		angle += dt * 6
		local center = f.pos + UP * (f.lift + 2.6)
		for i, slab in star do
			slab.CFrame = CFrame.new(center) * CFrame.Angles(0, angle + (i - 1) * math.pi / 2, 0)
		end
		return true
	end)
end

local function chargeImpact(self: Brain)
	local f, ctx, B = self.f, self.ctx, Config.Brute
	destroyParts(self)
	local stop = f.pos
	local dir = self.chargeDir :: Vector3
	local hit = false
	local amount = f.damage * (if f.buffUntil > f.clock then 1 + f.buffDamage else 1) * B.Damage
	for _, s in ctx.fighters do
		if isSoldier(self, s) and flatDist(s.pos, stop) <= B.HitRadius then
			ctx.hurt(s, amount, f)
			local away = flat(s.pos - stop)
			if away.Magnitude < 0.1 then
				away = dir
			end
			s.pos = clampToArena(self, s.pos + away.Unit * B.Knockback)
			s.stunUntil = s.clock + B.Stun
			hit = true
		end
	end
	ctx.fx.groundRing(ctx.parent, stop, Config.Colors.charge, B.HitRadius + 1, 0.4)
	ctx.fx.sparks(ctx.parent, stop, Config.Colors.charge, 10, B.HitRadius, 4)
	Rig.cast(f.model, "slash")
	ctx.hitPlayers(stop, B.HitRadius, B.PlayerDamage) -- only inside the telegraphed lane end
	setMoving(self, false)
	self.castKind = nil
	if hit then
		self.state = "fight"
	else
		dizzy(self)
	end
end

-- The charge is lost (the brute was pushed off its lane or stunned past the wind-up): the lane goes, a grey puff
-- and "...", the cooldown stays spent, the brute fights on from where it stands (never snaps back to the lane).
local function cancelCharge(self: Brain)
	local f, ctx = self.f, self.ctx
	destroyParts(self)
	setMoving(self, false)
	self.state = "fight"
	self.castKind = nil
	ctx.fx.sparks(ctx.parent, f.pos + UP * f.lift, Config.Colors.fizzle, 6, 1.5, 2)
	pop(self, "...", Config.Colors.fizzle, 22)
end

local function enrage(self: Brain)
	local f, ctx, B = self.f, self.ctx, Config.Brute
	self.enraged = true
	if #self.hasteBuffs == 0 then
		self.hasteBase = f.haste
	end
	self.hasteBase *= B.EnrageHaste -- for the rest of the fight
	recomputeHaste(self)
	ctx.fx.tint(f.model, Config.Colors.enrage, 3)
	pop(self, "GRRR", Config.Colors.enrage, 26)
end

local function bruteDecide(self: Brain, battleClock: number)
	local f, ctx, B = self.f, self.ctx, Config.Brute
	if self.state == "windup" or self.state == "charge" then
		return
	end
	if self.state == "dizzy" then
		if f.clock >= self.stateUntil then
			self.state = "fight"
		else
			return
		end
	end
	if not self.enraged and f.hp < B.EnrageAt * f.maxHp then
		enrage(self)
	end
	-- GUARD: the wall in front of its casters.
	local guarding = false
	for _, o in ctx.fighters do
		if isAlly(self, o) and flatDist(o.pos, f.pos) <= B.GuardRadius then
			local kind = archetypeOf(self, o)
			if kind == "Archer" or kind == "Shaman" then
				guarding = true
				break
			end
		end
	end
	f.taunt = if guarding then B.GuardTaunt else nil
	-- CHARGE at a target in the window.
	local target = nearestFoe(self)
	self.target = target
	if target and battleClock >= Config.AbilityGrace and f.clock >= self.chargeReadyAt then
		local dist = flatDist(target.pos, f.pos)
		if dist >= B.ChargeMin and dist <= B.ChargeRange then
			startCharge(self, target)
		end
	end
end

local function bruteAct(self: Brain, dt: number): boolean
	local f, ctx, B = self.f, self.ctx, Config.Brute
	if self.state == "windup" then
		ctx.face(f, self.chargeTo :: Vector3)
		if f.clock >= self.stateUntil then
			if flatDist(f.pos, self.chargeFrom :: Vector3) > B.CancelDrift or f.clock > self.stateUntil + B.CancelLate then
				cancelCharge(self) -- pushed off the lane / stunned through the wind-up: no teleport back to its start
				return true
			end
			destroyParts(self)
			self.state = "charge"
			self.castKind = nil
			self.chargeStart = f.clock
			setMoving(self, true)
		end
		return true
	elseif self.state == "charge" then
		local from, dir = self.chargeFrom :: Vector3, self.chargeDir :: Vector3
		if flatDist(f.pos, from + dir * self.chargeTravel) > B.CancelDrift then
			cancelCharge(self) -- knocked off the lane mid-run (a repel): it stops where it landed
			return true
		end
		local slow = if f.slowUntil > f.clock then f.slowFactor else 1 -- the Mage's trip bolt
		local prev = f.pos
		self.chargeTravel = math.min(self.chargeTravel + B.Speed * slow * dt, self.chargeLen)
		f.pos = from + dir * self.chargeTravel
		ctx.face(f, f.pos + dir)
		local blocked = false
		for _, s in ctx.fighters do
			if isSoldier(self, s) and distToSegment(s.pos, prev, f.pos) <= 2 then
				blocked = true
				break
			end
		end
		if blocked or self.chargeTravel >= self.chargeLen - 1e-3 or f.clock - self.chargeStart > 1.0 then
			chargeImpact(self)
		end
		return true
	elseif self.state == "dizzy" then
		if f.clock >= self.stateUntil then
			self.state = "fight"
			return false
		end
		return true
	end
	return false -- advance / fight: the default loop
end

-- ── Shaman: support caster, stays behind ────────────────────────────────────

local function chooseCast(self: Brain): (string?, any?)
	local f, ctx, S = self.f, self.ctx, Config.Shaman
	-- MEND: the most wounded ally under MendBelow within MendRange.
	local best, bestFraction = nil, S.MendBelow
	for _, o in ctx.fighters do
		if isAlly(self, o) and flatDist(o.pos, f.pos) <= S.MendRange then
			local fraction = o.hp / math.max(o.maxHp, 1)
			if fraction < bestFraction then
				best, bestFraction = o, fraction
			end
		end
	end
	if best then
		return "mend", best
	end
	-- FRENZY: a Grunt / Brute that is fighting (a soldier within 6 of it), not frenzied yet.
	for _, o in ctx.fighters do
		if isAlly(self, o) and flatDist(o.pos, f.pos) <= S.Frenzy.Range then
			local kind = archetypeOf(self, o)
			if (kind == "Grunt" or kind == "Brute") and not (o.ai and o.ai.extraUntil > o.clock) and anySoldierWithin(self, o.pos, 6) then
				return "frenzy", o
			end
		end
	end
	-- HEX: the soldier with the highest damage within Hex.Range, not hexed yet.
	local victim, victimDamage = nil, -1
	for _, s in ctx.fighters do
		if isSoldier(self, s) and s.hexUntil <= s.clock and flatDist(s.pos, f.pos) <= S.Hex.Range and s.damage > victimDamage then
			victim, victimDamage = s, s.damage
		end
	end
	if victim then
		return "hex", victim
	end
	return nil, nil
end

local function resolveShamanCast(self: Brain)
	local f, ctx, S = self.f, self.ctx, Config.Shaman
	if self.runeRing then
		self.runeRing.destroy()
		self.runeRing = nil
	end
	local kind = self.castKind
	local target = self.castTarget
	self.state = "hold"
	self.castKind = nil
	self.castTarget = nil
	self.castReadyAt = f.clock + S.CastEvery * self.cooldownFactor
	if not kind then
		return
	end
	-- The target may have died during the wind-up: pick again for the same kind.
	if not (target and target.hp > 0) then
		local newKind, newTarget = chooseCast(self)
		if newKind ~= kind or not newTarget then
			return
		end
		target = newTarget
	end
	local from, to = f.pos + UP * f.lift, target.pos + UP * target.lift
	if kind == "mend" then
		ctx.heal(target, target.maxHp * S.Mend)
		ctx.fx.beam(ctx.parent, from, to, Config.Colors.mend, 0.3, 0.4)
		ctx.fx.groundRing(ctx.parent, target.pos, Config.Colors.mend, 3, 0.5)
		ctx.fx.sparks(ctx.parent, target.pos, Config.Colors.mend, 6, 1.5, 5)
	elseif kind == "frenzy" then
		buffTarget(ctx, target, S.Frenzy.Damage, S.Frenzy.Haste, S.Frenzy.Time)
		ctx.fx.beam(ctx.parent, from, to, Config.Colors.frenzy, 0.3, 0.4)
		ctx.fx.mark(target.model, "FRENZY", Config.Colors.frenzy, S.Frenzy.Time)
		ctx.fx.tint(target.model, Config.Colors.frenzy, S.Frenzy.Time)
	elseif kind == "hex" then
		target.hexFactor = S.Hex.Factor
		target.hexUntil = target.clock + S.Hex.Time
		ctx.fx.beam(ctx.parent, from, to, Config.Colors.hex, 0.3, 0.4)
		ctx.fx.mark(target.model, "HEX", Config.Colors.hex, S.Hex.Time)
		ctx.fx.tint(target.model, Config.Colors.hex, S.Hex.Time)
		ctx.fx.sparks(ctx.parent, target.pos, Config.Colors.hex, 6, 1.5, 4)
	end
end

local function startShamanCast(self: Brain, kind: string, target: any)
	local f, ctx, S = self.f, self.ctx, Config.Shaman
	local color = (Config.Colors :: any)[kind] or WHITE
	self.state = "windup"
	self.castKind = kind
	self.castTarget = target
	self.stateUntil = f.clock + S.WindUp
	self.token += 1
	self.runeRing = ctx.fx.runeRing(ctx.fxFolder, color, 3, 1.4)
	Rig.cast(f.model, "cast")
	setMoving(self, false)
	pop(self, string.upper(kind), color, 20)
	ctx.emit("shamanCast", { shaman = f, kind = kind, ["until"] = ctx.clock() + S.WindUp })
	later(self, S.WindUp, function()
		if self.state == "windup" and self.castKind == kind then
			if f.stunUntil > f.clock then
				self:interrupt() -- stunned (the Mage's repel) during the wind-up: the cast is lost
			else
				resolveShamanCast(self)
			end
		end
	end)
end

-- The wind-up is lost: a grey puff, "...", the next cast comes sooner.
local function fizzle(self: Brain)
	local f, ctx, S = self.f, self.ctx, Config.Shaman
	self.token += 1
	if self.runeRing then
		self.runeRing.destroy()
		self.runeRing = nil
	end
	destroyParts(self)
	self.state = "hold"
	self.castKind = nil
	self.castTarget = nil
	self.castReadyAt = f.clock + S.FizzleCooldown
	ctx.fx.sparks(ctx.parent, f.pos + UP * f.lift, Config.Colors.fizzle, 6, 1.5, 2)
	pop(self, "...", Config.Colors.fizzle, 22)
end

local function shamanDecide(self: Brain, battleClock: number)
	local f = self.f
	if self.state == "windup" then
		return
	end
	if battleClock >= Config.AbilityGrace and f.clock >= self.castReadyAt then
		local kind, target = chooseCast(self)
		if kind then
			startShamanCast(self, kind, target)
		else
			self.castReadyAt = f.clock + 1 -- nothing worth casting: look again soon
		end
	end
end

local function shamanAct(self: Brain, dt: number, battleClock: number): boolean
	local f, ctx, S = self.f, self.ctx, Config.Shaman
	if self.state == "windup" then
		local look = self.castTarget or nearestFoe(self)
		if look then
			ctx.face(f, look.pos)
		end
		return true
	end
	local target = nearestFoe(self)
	if not target then
		return false
	end
	local d = flat(target.pos - f.pos)
	local dist = d.Magnitude
	local hold = if battleClock >= S.LateAdvanceAt then S.LateHold else S.Hold
	if dist > hold then
		-- Forward only, and only up to the hold distance (never a step back).
		f.pos += d.Unit * math.min(f.speed * dt * rateOf(f), dist - hold)
		setMoving(self, true)
		ctx.face(f, target.pos)
		self.state = "advance"
		return true
	end
	if dist <= f.range + 1 then
		f.timer -= dt * rateOf(f)
		if f.timer <= 0 then
			f.timer = f.cooldown
			ctx.attack(f, target, 1) -- the splash orb
		end
	end
	setMoving(self, false)
	ctx.face(f, target.pos)
	self.state = "hold"
	return true
end

-- ── Bosses ──────────────────────────────────────────────────────────────────

local function startWindup(self: Brain, kind: string, duration: number)
	self.state = "windup"
	self.castKind = kind
	self.stateUntil = self.f.clock + duration
	self.token += 1
	Rig.cast(self.f.model, "cast")
	setMoving(self, false)
end

local function endWindup(self: Brain)
	destroyParts(self)
	self.state = "fight"
	self.castKind = nil
end

local function startSlam(self: Brain)
	local f, ctx, Bo = self.f, self.ctx, Config.Boss
	local pos, radius = f.pos, Bo.SlamRadius
	startWindup(self, "slam", Bo.SlamWindUp)
	self.nextAbilityAt = f.clock + Bo.SlamEvery * self.cooldownFactor
	addParts(self, ctx.fx.warningCircle(ctx.fxFolder, pos, radius, Config.Colors.charge, ctx.groundY(pos)))
	ctx.addHazard(pos, radius, Bo.SlamWindUp, "slam", f)
	ctx.emit("bossTelegraph", { boss = f, ability = "slam", pos = pos, radius = radius, impactAt = ctx.clock() + Bo.SlamWindUp })
	later(self, Bo.SlamWindUp, function()
		if self.castKind ~= "slam" then
			return
		end
		endWindup(self)
		if flatDist(f.pos, pos) > Bo.SlamDrift then
			pop(self, "...", Config.Colors.fizzle, 22) -- pushed off its own telegraph: the slam is lost
			return
		end
		Rig.cast(f.model, "jump")
		ctx.fx.groundRing(ctx.parent, pos, Config.Colors.charge, radius, 0.5)
		ctx.fx.sparks(ctx.parent, pos, Config.Colors.charge, 16, radius, 5)
		for _, s in ctx.fighters do
			if isSoldier(self, s) and flatDist(s.pos, pos) <= radius then
				ctx.hurt(s, f.damage * Bo.SlamDamage, f)
				s.stunUntil = s.clock + Bo.SlamStun
				ctx.fx.tint(s.model, Config.Colors.rally, Bo.SlamStun)
			end
		end
		ctx.hitPlayers(pos, radius, Bo.SlamPlayerDamage)
	end)
end

local function startVolley(self: Brain)
	local f, ctx, Bo = self.f, self.ctx, Config.Boss
	local reach = f.range + 4
	startWindup(self, "volley", Bo.VolleyWindUp)
	self.nextAbilityAt = f.clock + Bo.VolleyEvery * self.cooldownFactor
	for _, s in ctx.fighters do
		if isSoldier(self, s) and flatDist(s.pos, f.pos) <= reach then
			ctx.fx.beam(ctx.parent, f.pos + UP * f.lift, s.pos + UP * s.lift, Config.Colors.warning, 0.15, Bo.VolleyWindUp)
		end
	end
	ctx.emit("bossTelegraph", { boss = f, ability = "volley", pos = f.pos, radius = reach, impactAt = ctx.clock() + Bo.VolleyWindUp })
	later(self, Bo.VolleyWindUp, function()
		if self.castKind ~= "volley" then
			return
		end
		endWindup(self)
		Rig.cast(f.model, "lunge")
		for _, s in ctx.fighters do
			if isSoldier(self, s) and flatDist(s.pos, f.pos) <= reach then
				ctx.attack(f, s, Bo.VolleyDamage)
			end
		end
	end)
end

local function startHeal(self: Brain)
	local f, ctx, Bo = self.f, self.ctx, Config.Boss
	local pos, radius = f.pos, Bo.HealRadius
	startWindup(self, "heal", Bo.HealWindUp)
	self.nextAbilityAt = f.clock + Bo.HealEvery * self.cooldownFactor
	self.healWeakened = false
	addParts(self, ctx.fx.reticle(ctx.fxFolder, pos, radius, Config.Colors.mend, ctx.groundY(pos)))
	ctx.emit("bossTelegraph", { boss = f, ability = "heal", pos = pos, radius = radius, impactAt = ctx.clock() + Bo.HealWindUp })
	later(self, Bo.HealWindUp, function()
		if self.castKind ~= "heal" then
			return
		end
		endWindup(self)
		local fraction = Bo.HealFraction * (if self.healWeakened then Bo.HealInterruptFactor else 1)
		ctx.fx.groundRing(ctx.parent, pos, Config.Colors.mend, radius, 0.6)
		for _, o in ctx.fighters do
			if o.side == f.side and o.hp > 0 and flatDist(o.pos, pos) <= radius then
				ctx.heal(o, o.maxHp * fraction) -- only inside the ring that was shown
			end
		end
		if self.healWeakened then
			pop(self, "WEAKENED", WHITE, 24)
		end
	end)
end

local function startSummon(self: Brain, count: number)
	local f, ctx, Bo = self.f, self.ctx, Config.Boss
	local kind = ctx.summonKind
	if not kind then
		return
	end
	startWindup(self, "summon", Bo.SummonWarn)
	local points: { Vector3 } = {}
	for i = 1, count do
		local angle = math.rad(45 + (i - 1) * (90 / math.max(count - 1, 1)))
		local pos = clampToArena(self, f.pos + Vector3.new(math.cos(angle) * 5, 0, math.sin(angle) * 5))
		table.insert(points, pos)
		addParts(self, ctx.fx.warningCircle(ctx.fxFolder, pos, 3, Config.Colors.summon, ctx.groundY(pos)))
		ctx.addHazard(pos, 3, Bo.SummonWarn, "summon", f)
	end
	ctx.emit("bossTelegraph", { boss = f, ability = "summon", pos = f.pos, radius = 3, impactAt = ctx.clock() + Bo.SummonWarn, points = points })
	later(self, Bo.SummonWarn, function()
		if self.castKind ~= "summon" then
			return
		end
		endWindup(self)
		ctx.fx.groundRing(ctx.parent, f.pos, Config.Colors.summon, 8, 0.6)
		for _, pos in points do
			ctx.spawnEnemy(kind, ctx.summonTier, pos)
		end
	end)
end

local function startRally(self: Brain)
	local f, ctx, Bo = self.f, self.ctx, Config.Boss
	startWindup(self, "rally", Bo.RallyWindUp)
	self.nextAbilityAt = f.clock + Bo.RallyEvery * self.cooldownFactor
	ctx.fx.groundRing(ctx.parent, f.pos, Config.Colors.rally, 6, Bo.RallyWindUp)
	ctx.emit("bossTelegraph", { boss = f, ability = "rally", pos = f.pos, radius = Bo.RallyRadius, impactAt = ctx.clock() + Bo.RallyWindUp })
	later(self, Bo.RallyWindUp, function()
		if self.castKind ~= "rally" then
			return
		end
		endWindup(self)
		ctx.fx.groundRing(ctx.parent, f.pos, Config.Colors.rally, Bo.RallyRadius, 0.7)
		pop(self, "RALLY!", Config.Colors.rally, 26)
		for _, o in ctx.fighters do
			if o.side == f.side and o.hp > 0 and flatDist(o.pos, f.pos) <= Bo.RallyRadius then
				buffTarget(ctx, o, Bo.RallyBonus, 1 + Bo.RallyBonus, Bo.RallyTime)
				ctx.fx.tint(o.model, Config.Colors.rally, Bo.RallyTime)
			end
		end
	end)
end

-- PHASE 2: a roar, faster abilities, a bit bigger.
local function roar(self: Brain)
	local f, ctx, Bo = self.f, self.ctx, Config.Boss
	self.phase2 = true
	self.state = "roar"
	self.stateUntil = f.clock + Bo.RoarTime
	self.cooldownFactor *= Bo.EnrageCooldownFactor
	Rig.cast(f.model, "cast")
	setMoving(self, false)
	pop(self, "ROAR!", Config.Colors.enrage, 30)
	ctx.notify("The boss is enraged!")
	ctx.fx.tint(f.model, Config.Colors.enrage, 1.5)
	ctx.fx.groundRing(ctx.parent, f.pos, Config.Colors.enrage, 10, 0.6)
	pcall(function()
		local model = f.model :: any
		model:ScaleTo(model:GetScale() * Bo.EnrageScale)
	end)
	f.lift *= Bo.EnrageScale
end

local function bossDecide(self: Brain, battleClock: number)
	local f, ctx, Bo = self.f, self.ctx, Config.Boss
	if self.state == "windup" or self.state == "roar" then
		return
	end
	if not self.phase2 and f.hp <= Bo.EnrageAt * f.maxHp then
		roar(self)
		return
	end
	local kind = self.archetype
	if kind == "Chief" and ctx.summonKind then
		if not self.summonedOnce and f.hp <= Bo.SummonAt * f.maxHp then
			self.summonedOnce = true
			f.summoned = true
			startSummon(self, Bo.SummonCount)
			return
		end
		if self.summonedOnce and not self.desperateOnce and f.hp <= Bo.DesperateAt * f.maxHp then
			self.desperateOnce = true
			startSummon(self, Bo.DesperateCount)
			return
		end
	end
	if battleClock < Bo.FirstAbilityAt or f.clock < self.nextAbilityAt then
		return
	end
	if kind == "Brute" then
		if anySoldierWithin(self, f.pos, Bo.SlamRadius) then
			startSlam(self)
		else
			self.nextAbilityAt = f.clock + 1 -- nobody to hit: look again soon
		end
	elseif kind == "Archer" then
		if anySoldierWithin(self, f.pos, f.range + 4) then
			startVolley(self)
		else
			self.nextAbilityAt = f.clock + 1
		end
	elseif kind == "Shaman" then
		local wounded = false
		for _, o in ctx.fighters do
			if o.side == f.side and o.hp > 0 and o.hp < o.maxHp * 0.95 then
				wounded = true
				break
			end
		end
		if wounded then
			startHeal(self)
		else
			self.nextAbilityAt = f.clock + 1
		end
	elseif kind == "Chief" then
		startRally(self)
	end
end

local function bossAct(self: Brain, _dt: number): boolean
	local f, ctx = self.f, self.ctx
	if self.state == "roar" then
		if f.clock >= self.stateUntil then
			self.state = "fight"
			return false
		end
		return true
	elseif self.state == "windup" then
		local look = nearestFoe(self)
		if look then
			ctx.face(f, look.pos)
		end
		return true
	end
	return false -- the default loop walks and hits
end

-- ── Treasure goblin and totem ───────────────────────────────────────────────

local function treasureAct(self: Brain, dt: number): boolean
	local f, ctx = self.f, self.ctx
	self.state = "flee"
	local nearest: any, nearestDist = nil, math.huge
	for _, o in ctx.fighters do
		if isSoldier(self, o) then
			local d = flatDist(o.pos, f.pos)
			if d < nearestDist then
				nearest, nearestDist = o, d
			end
		end
	end
	if not nearest then
		setMoving(self, false)
		return true
	end
	local away = flat(f.pos - nearest.pos)
	if away.Magnitude < 0.1 then
		away = Vector3.new(0, 0, 1)
	end
	away = away.Unit
	local stepLength = f.speed * dt * rateOf(f)
	local goal = clampToArena(self, f.pos + away * stepLength)
	if (goal - f.pos).Magnitude < stepLength * 0.5 then
		-- Cornered: slide along the edge toward the side farther from the chaser.
		local perp = Vector3.new(-away.Z, 0, away.X)
		local a = clampToArena(self, f.pos + perp * stepLength)
		local b = clampToArena(self, f.pos - perp * stepLength)
		goal = if flatDist(a, nearest.pos) >= flatDist(b, nearest.pos) then a else b
	end
	f.pos = goal
	ctx.face(f, f.pos + away)
	setMoving(self, true)
	return true
end

local function totemAct(self: Brain, _dt: number): boolean
	self.state = "stand"
	return true
end

-- ── Bodyguards ──────────────────────────────────────────────────────────────

-- A mob with `guard` set stays near its boss until the boss is under half HP or a soldier comes close.
local function guardAct(self: Brain, dt: number): boolean
	local f, ctx, Bo = self.f, self.ctx, Config.Boss
	local boss = self.guard
	if not (boss and boss.hp > 0 and boss.hp > 0.5 * boss.maxHp) then
		return false
	end
	if self.state == "windup" or self.state == "charge" or self.state == "dizzy" or self.state == "scurry" or self.state == "cry" then
		return false
	end
	if anySoldierWithin(self, f.pos, Bo.GuardBreak) then
		return false
	end
	local d = flat(boss.pos - f.pos)
	local dist = d.Magnitude
	if dist > Bo.GuardStay then
		f.pos += d.Unit * math.min(f.speed * dt * rateOf(f), dist - Bo.GuardStay)
		setMoving(self, true)
		ctx.face(f, boss.pos)
	else
		setMoving(self, false)
		local look = nearestFoe(self)
		if look then
			ctx.face(f, look.pos)
		end
	end
	self.state = "guard"
	return true
end

-- ── The brain ───────────────────────────────────────────────────────────────

local DECIDE: { [string]: (Brain, number) -> () } = {
	Grunt = gruntDecide,
	Archer = archerDecide,
	Brute = bruteDecide,
	Shaman = shamanDecide,
	Boss = bossDecide,
}
local ACT: { [string]: (Brain, number, number) -> boolean } = {
	Grunt = gruntAct,
	Archer = archerAct,
	Brute = bruteAct,
	Shaman = shamanAct,
	Boss = bossAct,
	Treasure = treasureAct,
	Totem = totemAct,
}

-- `archetype` is the kind's archetype (Grunt | Archer | Brute | Shaman | Chief | Treasure | Totem); `boss` picks
-- the boss behaviors for Brute / Chief / Archer / Shaman.
function EnemyBrain.new(ctx: Context, fighter: any, archetype: string, boss: boolean): Brain
	created += 1
	local self = {
		ctx = ctx,
		f = fighter,
		archetype = archetype,
		boss = boss,
		index = created,
		state = "advance",
		castKind = nil,
		cooldownFactor = 1,
		guard = nil,
		destroyed = false,
		thinkIn = (created % 5) * 0.05,
		stateUntil = 0,
		token = 0,
		parts = {},
		runeRing = nil,
		hasteBase = fighter.haste or 1,
		hasteBuffs = {},
		gang = 0,
		extraDamage = 0,
		extraUntil = 0,
		target = nil,
		retargetAt = 0,
		cryReadyAt = 0,
		flanking = false,
		flankSign = 1,
		scurryReadyAt = 0,
		moveFrom = nil,
		moveTo = nil,
		moveStart = 0,
		moveTime = 1,
		chargeReadyAt = Config.Brute.FirstCharge,
		chargeFrom = nil,
		chargeTo = nil,
		chargeDir = nil,
		chargeLen = 0,
		chargeTravel = 0,
		chargeStart = 0,
		enraged = false,
		castReadyAt = Config.Shaman.FirstCast,
		castTarget = nil,
		castPoints = nil,
		castCount = 0,
		healWeakened = false,
		nextAbilityAt = Config.Boss.FirstAbilityAt,
		phase2 = false,
		summonedOnce = false,
		desperateOnce = false,
	}
	if archetype == "Treasure" then
		self.state = "flee"
	elseif archetype == "Totem" then
		self.state = "stand"
	end
	return (setmetatable(self, EnemyBrain) :: any) :: Brain
end

local function handlerKey(self: Brain): string
	if self.boss then
		return "Boss"
	end
	return self.archetype
end

-- One tick. Returns true when the brain moved / attacked for the fighter itself.
function EnemyBrain.update(self: Brain, dt: number): boolean
	if self.destroyed or self.f.hp <= 0 then
		return false
	end
	local f, ctx = self.f, self.ctx
	tickBuffs(self)
	if self.runeRing then
		self.runeRing.update(f.pos + UP * (f.lift + 1.4), dt)
	end
	local battleClock = ctx.clock()
	local key = handlerKey(self)
	self.thinkIn -= dt
	if self.thinkIn <= 0 then
		self.thinkIn = Config.Decide
		local decide = DECIDE[key]
		if decide then
			decide(self, battleClock)
		end
	end
	if self.guard and not self.boss and guardAct(self, dt) then
		return true
	end
	local act = ACT[key]
	if act then
		return act(self, dt, battleClock)
	end
	return false
end

-- A hit: a shaman's wind-up is lost when the hit is big enough.
function EnemyBrain.onDamaged(self: Brain, _attacker: any?, amount: number?)
	if self.destroyed then
		return
	end
	local f = self.f
	if self.archetype == "Shaman" and not self.boss and self.state == "windup" and (amount or 0) >= Config.Shaman.InterruptFraction * f.maxHp then
		fizzle(self)
	end
end

function EnemyBrain.onEvent(_self: Brain, _name: string, _payload: any)
	-- Nothing yet: the brains read the battle directly. (Kept for the wave twists and future reactions.)
end

-- The Mage's counter-spell: fizzles a shaman's (or a rally's) wind-up, halves a boss heal. Returns true when
-- something was interrupted, false when nothing was winding up.
function EnemyBrain.interrupt(self: Brain): boolean
	if self.destroyed or self.state ~= "windup" then
		return false
	end
	local kind = self.castKind
	if kind == "heal" then
		if self.healWeakened then
			return false
		end
		self.healWeakened = true
		return true
	end
	if kind == "mend" or kind == "frenzy" or kind == "hex" or kind == "rally" then
		fizzle(self)
		return true
	end
	return false
end

-- Routes a damage bonus / haste onto this fighter so overlapping buffs expire correctly (war cry, frenzy, rally).
function EnemyBrain.buff(self: Brain, damageBonus: number?, hasteFactor: number?, duration: number)
	local f = self.f
	if damageBonus and damageBonus > 0 then
		self.extraDamage = math.max(damageBonus, if self.extraUntil > f.clock then self.extraDamage else 0)
		self.extraUntil = f.clock + duration
		refreshDamageBuff(self)
	end
	if hasteFactor and hasteFactor ~= 1 then
		if #self.hasteBuffs == 0 then
			self.hasteBase = f.haste
		end
		table.insert(self.hasteBuffs, { factor = hasteFactor, endsAt = f.clock + duration })
		recomputeHaste(self)
	end
end

-- The enemy died or the battle ended: every telegraph, rune and star goes away; scheduled callbacks are void.
function EnemyBrain.destroy(self: Brain)
	self.destroyed = true
	self.token += 1
	destroyParts(self)
	if self.runeRing then
		self.runeRing.destroy()
		self.runeRing = nil
	end
	self.f.taunt = nil
	self.castKind = nil
end

return EnemyBrain
