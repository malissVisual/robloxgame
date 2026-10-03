--!strict
-- The fight's extra action (numbers in Config/BattleSpells.luau): the PLAYER'S SPELLS (meteor, blizzard, lightning,
-- heal: the round buttons / keys 1-4), REINFORCEMENTS (part of the wave comes again a few seconds in), the element
-- wizards' SIGNATURE spells (Inferno, Frost Nova, Thunderstorm, Wild Grove, Shadow Claw, Arcane Barrage), the enemy
-- AFFIXES (shielded, swift, explosive, splitter, giant) and the FEEL (crits, the kill combo, camera shakes, the
-- boss's slow-motion death). BattleService creates one State per battle with a context (the same helpers the brains
-- and the wave twists get), calls step(dt) every tick, onDeath(f) for every death and castPlayer() when the player
-- casts. Everything runs on the battle clock (schedule / movers), so the battle speed (2x) and the end of the battle
-- (events and movers are cleared) are handled by BattleService.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Wizards = require(Shared.Config.Wizards)
local Config = require(Shared.Config.BattleSpells)

local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.new(1, 1, 1)

local BattleSpells = {}

export type Ctx = {
	fighters: { any },
	playerSide: number,
	enemySide: number,
	parent: Instance,
	fx: any, -- BattleFx
	fxFolder: Instance,
	groundY: (pos: Vector3) -> number,
	damage: (target: any, amount: number, source: any?) -> number, -- applyDamage (plain: no tree passives)
	popNumber: (target: any, amount: number, color: Color3?) -> (),
	heal: (target: any, amount: number) -> (),
	schedule: (delay: number, fn: () -> ()) -> (),
	addMover: (fn: (dt: number) -> boolean) -> (),
	addHazard: (pos: Vector3, radius: number, duration: number, kind: string, source: any?) -> (),
	emit: (name: string, payload: any) -> (),
	notify: (text: string) -> (),
	spawnEnemy: (kind: string, tier: number, pos: Vector3) -> any,
	hold: (count: number) -> (), -- enemies on their way (the battle is not won while any are)
	archetype: (f: any) -> string?,
	clock: () -> number,
	center: Vector3, -- the arena's center
	arenaRadius: number,
	wave: number,
	boss: boolean, -- a boss wave
	twists: { string }, -- the ids of the wave's twists
	feel: (data: { [string]: any }) -> (), -- to the player's screen: { kind = "shake" | "combo" | "boss", … }
	slowmo: (speed: number, seconds: number) -> (), -- the fight runs slower for a few real seconds
	scaleModel: (f: any, scale: number) -> (), -- makes a fighter's model bigger / smaller (and its lift)
	random: Random?,
}

export type State = {
	ctx: Ctx,
	ready: { [string]: number }, -- player spell id → battle clock when it is ready
	nextSignature: { [any]: number }, -- mage fighter → battle clock of its next signature spell
	elements: { [any]: string }, -- mage fighter → its element (only the element wizards)
	reinforce: boolean, -- this wave gets reinforcements (not sent yet)
	starting: { any }, -- the starting combat enemies (their deaths trigger the reinforcements early)
	affixes: { [any]: string }, -- enemy fighter → its affix id
	shieldTags: { [any]: Instance }, -- shielded enemy → its tag (removed when the bubble pops)
	combo: number, -- kills in the running combo
	lastKill: number, -- battle clock of the last kill
	rng: Random,
}

local function alive(f: any): boolean
	return f.hp > 0
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function enemiesOf(self: State): { any }
	local list = {}
	for _, f in self.ctx.fighters do
		if f.side == self.ctx.enemySide and alive(f) then
			table.insert(list, f)
		end
	end
	return list
end

local function within(list: { any }, point: Vector3, radius: number): { any }
	local out = {}
	for _, f in list do
		if (flat(f.pos) - flat(point)).Magnitude <= radius then
			table.insert(out, f)
		end
	end
	return out
end

-- The enemy (of `list`) with the most other enemies within `radius`: where an area spell hurts the most.
local function densest(list: { any }, radius: number): any?
	local best, bestCount = nil, -1
	for _, f in list do
		local n = #within(list, f.pos, radius)
		if n > bestCount then
			best, bestCount = f, n
		end
	end
	return best
end

local function has(list: { string }, id: string): boolean
	return table.find(list, id) ~= nil
end

-- A mage's hit with the CRIT roll: × Crit.Mult, a gold number and "CRIT!".
local function hit(self: State, f: any, target: any, amount: number, color: Color3): number
	local ctx = self.ctx
	local crit = f.side == ctx.playerSide and self.rng:NextNumber() < Config.Crit.Chance
	if crit then
		amount *= Config.Crit.Mult
		ctx.fx.pop(ctx.parent, target.pos + UP * (target.lift * 2 + 2), "CRIT!", Config.Crit.Color, 22)
	end
	local taken = ctx.damage(target, amount, f)
	ctx.popNumber(target, taken, if crit then Config.Crit.Color else color)
	return taken
end

-- ── Enemy affixes ───────────────────────────────────────────────────────────

local function giveAffix(self: State, f: any, id: string)
	local ctx, A = self.ctx, Config.Affixes.Defs[id]
	self.affixes[f] = id
	f.bonusCoins += Config.Affixes.Coins
	local tag = ctx.fx.mark(f.model, A.label, A.color, 600)
	if id == "shielded" then
		f.shieldHp += f.maxHp * (A.shield :: number)
		self.shieldTags[f] = tag
		ctx.fx.tint(f.model, A.color, 1.5)
	elseif id == "swift" then
		f.haste *= A.haste :: number
	elseif id == "giant" then
		f.maxHp *= A.hp :: number
		f.hp = f.maxHp
		f.damage *= A.damage :: number
		ctx.scaleModel(f, A.scale :: number)
	end
end

local function rollAffixes(self: State)
	local chance = Config.affixChance(self.ctx.wave)
	if chance <= 0 then
		return
	end
	local pool: { string } = {}
	for _, id in Config.Affixes.Order do
		if self.ctx.wave >= Config.Affixes.Defs[id].minWave then
			table.insert(pool, id)
		end
	end
	for _, f in self.starting do
		if self.rng:NextNumber() < chance then
			giveAffix(self, f, pool[self.rng:NextInteger(1, #pool)])
		end
	end
end

local function explode(self: State, f: any)
	local ctx, A = self.ctx, Config.Affixes.Defs.explosive
	local pos = Vector3.new(f.pos.X, ctx.groundY(f.pos), f.pos.Z)
	local radius, damage = A.radius :: number, f.damage * (A.damage :: number)
	local parts = ctx.fx.warningCircle(ctx.fxFolder, pos, radius, A.color, pos.Y + 0.05)
	ctx.addHazard(pos, radius, A.delay :: number, "volatile", nil) -- the mages step out of it
	ctx.schedule(A.delay :: number, function()
		for _, part in parts do
			part:Destroy()
		end
		ctx.fx.groundRing(ctx.parent, pos, A.color, radius * 1.2, 0.5)
		ctx.fx.sparks(ctx.parent, pos, A.color, 16, radius, 7)
		local flash = ctx.fx.newPart(ctx.parent, Vector3.one * 2, CFrame.new(pos + UP * 1.5), A.color, 0.1, Enum.PartType.Ball)
		ctx.fx.fade(flash, 0.4, { Size = Vector3.one * radius * 2, Transparency = 1 })
		ctx.feel({ kind = "shake", power = Config.ExplosionShake })
		for _, mage in ctx.fighters do
			if mage.side == ctx.playerSide and alive(mage) and (flat(mage.pos) - flat(pos)).Magnitude <= radius then
				ctx.popNumber(mage, ctx.damage(mage, damage, nil), A.color)
			end
		end
	end)
end

local function split(self: State, f: any)
	local ctx, A = self.ctx, Config.Affixes.Defs.splitter
	local count = A.parts :: number
	local pos, kind, tier, hp, damage = f.pos, f.kind, f.tier, f.maxHp * (A.hp :: number), f.damage
	if not kind then
		return
	end
	ctx.hold(count) -- the wave is not beaten while they are coming
	ctx.fx.pop(ctx.parent, pos + UP * (f.lift * 2 + 1), "SPLIT!", A.color, 22)
	ctx.schedule(0.05, function()
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			local child = ctx.spawnEnemy(kind, tier, pos + Vector3.new(math.cos(angle) * 2.5, 0, math.sin(angle) * 2.5))
			child.maxHp = hp
			child.hp = hp
			child.damage = damage * 0.6
			child.haste *= 1.3
			ctx.scaleModel(child, 0.7)
			ctx.fx.tint(child.model, A.color, 1)
		end
		ctx.hold(-count)
	end)
end

function BattleSpells.new(ctx: Ctx): State
	local self: State = {
		ctx = ctx,
		ready = {},
		nextSignature = {},
		elements = {},
		reinforce = false,
		starting = {},
		affixes = {},
		shieldTags = {},
		combo = 0,
		lastKill = -math.huge,
		rng = ctx.random or Random.new(),
	}
	for id, spell in Config.PlayerSpells do
		self.ready[id] = spell.first
	end
	for _, f in ctx.fighters do
		if f.side == ctx.playerSide and f.variant then
			local def = Wizards.Types[f.variant]
			local element = def and def.evolution
			if element and Config.Signatures[element] then
				self.elements[f] = element
				self.nextSignature[f] = Config.SignatureFirst + self.rng:NextNumber() * 2
			end
		elseif f.side == ctx.enemySide then
			local archetype = ctx.archetype(f)
			if archetype ~= "Totem" and archetype ~= "Treasure" and not f.boss then
				table.insert(self.starting, f)
			end
		end
	end
	local R = Config.Reinforcements
	local skip = false
	for _, id in R.SkipTwists do
		if has(ctx.twists, id) then
			skip = true
		end
	end
	self.reinforce = ctx.wave >= R.MinWave and not ctx.boss and not skip and #self.starting > 0
	rollAffixes(self)
	return self
end

-- ── Reinforcements ──────────────────────────────────────────────────────────

local function sendReinforcements(self: State)
	local ctx, R = self.ctx, Config.Reinforcements
	self.reinforce = false
	local count = math.clamp(math.floor(#self.starting * R.Fraction + 0.5), R.Min, R.Max)
	local points: { Vector3 } = {}
	local parts: { Instance } = {}
	for i = 1, math.min(count, #R.Points) do
		local point = ctx.center + R.Points[i]
		point = Vector3.new(point.X, ctx.groundY(point), point.Z)
		table.insert(points, point)
		for _, part in ctx.fx.warningCircle(ctx.fxFolder, point, R.Radius, R.Color, ctx.groundY(point)) do
			table.insert(parts, part)
		end
		ctx.addHazard(point, R.Radius, R.Warning, "ambush", nil)
	end
	local picks: { any } = {}
	for i = 1, count do
		table.insert(picks, self.starting[self.rng:NextInteger(1, #self.starting)])
	end
	ctx.hold(count)
	ctx.notify("REINFORCEMENTS!")
	ctx.emit("waveEvent", { id = "reinforcements", points = points, at = ctx.clock() + R.Warning })
	ctx.schedule(R.Warning, function()
		for _, part in parts do
			part:Destroy()
		end
		for i, pick in picks do
			local point = points[(i - 1) % #points + 1]
			local offset = Vector3.new((self.rng:NextNumber() - 0.5) * 3, 0, ((i - 1) // #points) * 3)
			ctx.spawnEnemy(pick.kind, pick.tier, point + offset)
		end
		ctx.hold(-count)
	end)
end

local function stepReinforcements(self: State)
	if not self.reinforce then
		return
	end
	local R = Config.Reinforcements
	local dead = 0
	for _, f in self.starting do
		if not alive(f) then
			dead += 1
		end
	end
	if self.ctx.clock() >= R.At or dead >= #self.starting * R.HalfDead then
		if dead < #self.starting then
			sendReinforcements(self)
		else
			self.reinforce = false -- the wave fell before they came: the fight is over
		end
	end
end

-- ── The player's spells ─────────────────────────────────────────────────────

local function power(self: State): number
	local sum = 0
	for _, f in self.ctx.fighters do
		if f.side == self.ctx.playerSide and alive(f) then
			sum += f.damage
		end
	end
	return sum
end

local function impactPoint(self: State, spell: Config.PlayerSpell, aim: Vector3?): Vector3?
	local ctx = self.ctx
	if aim and (flat(aim) - flat(ctx.center)).Magnitude <= ctx.arenaRadius + Config.AimSlack then
		return Vector3.new(aim.X, ctx.groundY(aim), aim.Z)
	end
	local target = densest(enemiesOf(self), spell.radius)
	if not target then
		return nil
	end
	return Vector3.new(target.pos.X, ctx.groundY(target.pos), target.pos.Z)
end

local function meteor(self: State, M: Config.PlayerSpell, point: Vector3, strength: number)
	local ctx, fx = self.ctx, self.ctx.fx
	local reticle = fx.reticle(ctx.fxFolder, point, M.radius, M.color, point.Y + 0.05)
	local rock = fx.newPart(ctx.fxFolder, Vector3.one * 5, CFrame.new(point + Vector3.new(14, 60, 10)), M.color, 0, Enum.PartType.Ball)
	local core = fx.newPart(ctx.fxFolder, Vector3.one * 3, rock.CFrame, M.color2, 0, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = M.color
	light.Range = 30
	light.Brightness = 4
	light.Parent = rock
	local from = rock.Position
	local elapsed = 0
	local fall = M.fall :: number
	ctx.addMover(function(dt: number): boolean
		elapsed += dt
		local f = math.clamp(elapsed / fall, 0, 1)
		local pos = from:Lerp(point + UP * 2, f * f)
		if rock.Parent then
			rock.CFrame = CFrame.new(pos)
			core.CFrame = CFrame.new(pos)
			if math.random() < 0.7 then
				fx.sparks(ctx.fxFolder, pos - UP, M.color, 1, 1.5, 3) -- a burning trail
			end
		end
		if f < 1 then
			return true
		end
		rock:Destroy()
		core:Destroy()
		reticle:Destroy()
		-- IMPACT
		fx.groundRing(ctx.parent, point, M.color, M.radius * 1.3, 0.6)
		fx.groundRing(ctx.parent, point, M.color2, M.radius * 0.8, 0.4)
		fx.sparks(ctx.parent, point, M.color, 24, M.radius, 9)
		fx.sparks(ctx.parent, point, M.color2, 12, M.radius * 0.6, 12)
		local flash = fx.newPart(ctx.parent, Vector3.one * 4, CFrame.new(point + UP * 2), M.color2, 0.1, Enum.PartType.Ball)
		fx.fade(flash, 0.5, { Size = Vector3.one * (M.radius * 2.4), Transparency = 1 })
		fx.pop(ctx.parent, point + UP * 6, "METEOR!", M.color2, 30)
		ctx.feel({ kind = "shake", power = M.shake })
		for _, enemy in within(enemiesOf(self), point, M.radius) do
			local amount = strength * (M.damage :: number) * (if enemy.boss then M.bossDamage :: number else 1)
			ctx.popNumber(enemy, ctx.damage(enemy, amount, nil), M.color)
			if alive(enemy) then
				enemy.stunUntil = math.max(enemy.stunUntil, enemy.clock + (M.stun :: number))
				fx.tint(enemy.model, M.color, M.stun :: number)
			end
		end
		return false
	end)
end

local function blizzard(self: State, S: Config.PlayerSpell, point: Vector3, strength: number)
	local ctx, fx = self.ctx, self.ctx.fx
	fx.groundRing(ctx.parent, point, S.color, S.radius, 0.8)
	fx.groundRing(ctx.parent, point, S.color2, S.radius * 0.6, 0.6)
	for i = 1, 16 do -- ice falling from the sky, shards growing from the ground
		local a = self.rng:NextNumber() * math.pi * 2
		local r = S.radius * math.sqrt(self.rng:NextNumber())
		local at = point + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local h = 2 + self.rng:NextNumber() * 3
		local shard = fx.newPart(ctx.parent, Vector3.new(0.8, h, 0.8), CFrame.new(at + UP * (h / 2)) * CFrame.Angles(self.rng:NextNumber() * 0.6, a, self.rng:NextNumber() * 0.6), S.color, 0.1)
		shard.Material = Enum.Material.Ice
		fx.fade(shard, 2.2, { Transparency = 1, Size = Vector3.new(0.2, h, 0.2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if i <= 8 then
			fx.beam(ctx.parent, at + Vector3.new(4, 30, 2), at, S.color2, 0.4, 0.35)
		end
	end
	fx.pop(ctx.parent, point + UP * 6, "BLIZZARD!", S.color2, 30)
	ctx.feel({ kind = "shake", power = S.shake })
	for _, enemy in within(enemiesOf(self), point, S.radius) do
		ctx.popNumber(enemy, ctx.damage(enemy, strength * (S.damage :: number) * (if enemy.boss then S.bossDamage :: number else 1), nil), S.color)
		if alive(enemy) then
			local time = if enemy.boss then S.bossFreeze :: number else S.freeze :: number
			enemy.stunUntil = math.max(enemy.stunUntil, enemy.clock + time)
			fx.tint(enemy.model, S.color2, time)
			fx.mark(enemy.model, "FROZEN", S.color2, time)
		end
	end
end

local function lightning(self: State, S: Config.PlayerSpell, point: Vector3, strength: number)
	local ctx, fx = self.ctx, self.ctx.fx
	local enemies = enemiesOf(self)
	local first, bestDist = nil, math.huge
	for _, e in enemies do
		local d = (flat(e.pos) - flat(point)).Magnitude
		if d < bestDist then
			first, bestDist = e, d
		end
	end
	if not first then
		return
	end
	ctx.feel({ kind = "shake", power = S.shake })
	local hitSet: { [any]: boolean } = {}
	local current = first
	local from = current.pos + UP * 45
	for i = 0, S.jumps :: number do
		local target, origin = current, from
		hitSet[target] = true
		ctx.schedule(i * 0.08, function()
			if not alive(target) then
				return
			end
			if i == 0 then
				fx.lightning(ctx.parent, origin, target.pos, S.color, 1)
				fx.groundRing(ctx.parent, target.pos, S.color2, 4, 0.35)
				fx.pop(ctx.parent, target.pos + UP * 6, "LIGHTNING!", S.color, 28)
			else
				fx.beam(ctx.parent, origin, target.pos + UP * target.lift, S.color, 0.5, 0.3)
				fx.beam(ctx.parent, origin, target.pos + UP * target.lift, S.color2, 0.2, 0.3)
			end
			fx.sparks(ctx.parent, target.pos, S.color, 6, 2, 4)
			ctx.popNumber(target, ctx.damage(target, strength * (S.damage :: number) * (if target.boss then S.bossDamage :: number else 1), nil), S.color)
			if alive(target) then
				target.stunUntil = math.max(target.stunUntil, target.clock + (S.stun :: number))
			end
		end)
		-- the next jump: the nearest enemy not hit yet
		local nextTarget, nextDist = nil, S.jumpRadius :: number
		for _, e in enemies do
			if not hitSet[e] then
				local d = (flat(e.pos) - flat(current.pos)).Magnitude
				if d <= nextDist then
					nextTarget, nextDist = e, d
				end
			end
		end
		if not nextTarget then
			break
		end
		from = current.pos + UP * current.lift
		current = nextTarget
	end
end

local function healSquad(self: State, S: Config.PlayerSpell)
	local ctx, fx = self.ctx, self.ctx.fx
	for _, mage in ctx.fighters do
		if mage.side == ctx.playerSide and alive(mage) then
			ctx.heal(mage, mage.maxHp * (S.heal :: number))
			mage.shieldUntil = math.max(mage.shieldUntil, mage.clock + (S.shieldTime :: number))
			mage.shieldReduction = math.max(mage.shieldReduction, S.shield :: number)
			fx.groundRing(ctx.parent, mage.pos, S.color, 5, 0.6)
			fx.sparks(ctx.parent, mage.pos, S.color2, 8, 2, 6)
			fx.beam(ctx.parent, mage.pos + UP * 30, mage.pos, S.color2, 0.8, 0.4)
			fx.tint(mage.model, S.color, S.shieldTime :: number)
		end
	end
	fx.pop(ctx.parent, ctx.center + UP * 8, "HEAL!", S.color2, 32)
end

-- The player casts `id` (aimed at `aim`, or nil: it aims itself). Returns (cast, battle seconds until it is ready).
function BattleSpells.castPlayer(self: State, id: string, aim: Vector3?): (boolean, number)
	local ctx = self.ctx
	local spell = Config.PlayerSpells[id]
	if not spell then
		return false, 0
	end
	local now = ctx.clock()
	local ready = self.ready[id] or spell.first
	if now < ready then
		return false, ready - now
	end
	local strength = power(self)
	if strength <= 0 then
		return false, 0
	end
	local point: Vector3? = nil
	if spell.aim then
		point = impactPoint(self, spell, aim)
		if not point then
			return false, 0
		end
	end
	self.ready[id] = now + spell.cooldown
	if id == "meteor" then
		meteor(self, spell, point :: Vector3, strength)
	elseif id == "frost" then
		blizzard(self, spell, point :: Vector3, strength)
	elseif id == "lightning" then
		lightning(self, spell, point :: Vector3, strength)
	elseif id == "heal" then
		healSquad(self, spell)
	end
	if point then
		ctx.emit("playerSpell", { id = id, point = point }) -- the mages combo their area spells into it
	end
	return true, spell.cooldown
end

-- Kept for older callers: the meteor aimed by itself.
function BattleSpells.castMeteor(self: State): (boolean, number)
	return BattleSpells.castPlayer(self, "meteor", nil)
end

-- Battle seconds until the player's spell `id` is ready.
function BattleSpells.readyIn(self: State, id: string): number
	local spell = Config.PlayerSpells[id]
	return math.max(0, (self.ready[id] or (if spell then spell.first else 0)) - self.ctx.clock())
end

-- ── The element wizards' signature spells ───────────────────────────────────

local function staffTop(f: any): Vector3
	return f.pos + UP * (f.lift + 3)
end

local function nearestWithin(self: State, f: any, reach: number): any?
	local best, bestDist = nil, reach
	for _, e in enemiesOf(self) do
		local d = (flat(e.pos) - flat(f.pos)).Magnitude
		if d <= bestDist then
			best, bestDist = e, d
		end
	end
	return best
end

local CAST: { [string]: (self: State, f: any, sig: any, target: any) -> () } = {}

CAST.Fire = function(self, f, sig, target)
	local ctx, fx = self.ctx, self.ctx.fx
	local near = within(enemiesOf(self), target.pos, f.range + Config.SignatureReach)
	local center = (densest(near, sig.radius) or target).pos
	fx.groundRing(ctx.parent, center, sig.color, sig.radius, 0.55)
	fx.sparks(ctx.parent, center, sig.color, 18, sig.radius, 8)
	fx.sparks(ctx.parent, center, sig.color2, 8, sig.radius * 0.5, 11)
	local column = fx.newPart(ctx.parent, Vector3.new(12, 3, 3), CFrame.new(center + UP * 6) * CFrame.Angles(0, 0, math.rad(90)), sig.color, 0.2, Enum.PartType.Cylinder)
	fx.fade(column, 0.6, { Size = Vector3.new(16, sig.radius * 1.6, sig.radius * 1.6), Transparency = 1 })
	fx.beam(ctx.parent, staffTop(f), center + UP, sig.color2, 0.5, 0.25)
	for _, e in within(enemiesOf(self), center, sig.radius) do
		hit(self, f, e, f.damage * sig.damage, sig.color)
		if alive(e) then
			e.burnUntil = math.max(e.burnUntil, e.clock + sig.burn.time)
			e.burnDps = math.max(e.burnDps, e.maxHp * sig.burn.dps) -- (BattleService burns a boss less: Balance.BossPercentDamage)
			e.burnBy = f
			fx.tint(e.model, sig.color, sig.burn.time)
		end
	end
end

CAST.Ice = function(self, f, sig, target)
	local ctx, fx = self.ctx, self.ctx.fx
	local center = target.pos
	fx.groundRing(ctx.parent, center, sig.color, sig.radius, 0.6)
	fx.groundRing(ctx.parent, center, sig.color2, sig.radius * 0.6, 0.45)
	fx.beam(ctx.parent, staffTop(f), center + UP, sig.color2, 0.4, 0.25)
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local r = sig.radius * (0.35 + self.rng:NextNumber() * 0.6)
		local at = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local h = 1.5 + self.rng:NextNumber() * 2.5
		local shard = fx.newPart(ctx.parent, Vector3.new(0.6, h, 0.6), CFrame.new(at + UP * (h / 2)) * CFrame.Angles(self.rng:NextNumber() * 0.5, a, self.rng:NextNumber() * 0.5), sig.color, 0.15)
		shard.Material = Enum.Material.Ice
		fx.fade(shard, 1.4, { Transparency = 1, Size = Vector3.new(0.2, h, 0.2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	for _, e in within(enemiesOf(self), center, sig.radius) do
		hit(self, f, e, f.damage * sig.damage, sig.color)
		if alive(e) then
			local time = sig.freeze * (if e.boss then 1 / 3 else 1)
			e.stunUntil = math.max(e.stunUntil, e.clock + time)
			fx.tint(e.model, sig.color2, time)
		end
	end
end

CAST.Storm = function(self, f, sig, _target)
	local ctx, fx = self.ctx, self.ctx.fx
	local reach = f.range + Config.SignatureReach + 8
	for i = 1, sig.hits do
		ctx.schedule((i - 1) * 0.15, function()
			if not alive(f) then
				return
			end
			local options = within(enemiesOf(self), f.pos, reach)
			if #options == 0 then
				return
			end
			local e = options[self.rng:NextInteger(1, #options)]
			fx.lightning(ctx.parent, e.pos + UP * 40, e.pos, sig.color, 0.7)
			fx.groundRing(ctx.parent, e.pos, sig.color2, sig.radius, 0.3)
			fx.sparks(ctx.parent, e.pos, sig.color, 6, 2, 4)
			for _, other in within(enemiesOf(self), e.pos, sig.radius) do
				hit(self, f, other, f.damage * sig.damage, sig.color)
			end
		end)
	end
end

CAST.Nature = function(self, f, sig, target)
	local ctx, fx = self.ctx, self.ctx.fx
	local center = target.pos
	fx.groundRing(ctx.parent, center, sig.color, sig.radius, 0.7)
	fx.sparks(ctx.parent, center, sig.color2, 14, sig.radius, 3)
	for i = 1, 8 do -- vines bursting from the ground
		local a = i / 8 * math.pi * 2
		local at = center + Vector3.new(math.cos(a) * sig.radius * 0.6, 0, math.sin(a) * sig.radius * 0.6)
		local vine = fx.newPart(ctx.parent, Vector3.new(0.5, 3.5, 0.5), CFrame.new(at + UP * 1.5) * CFrame.Angles(0, a, 0.4), sig.color, 0.1)
		vine.Material = Enum.Material.Grass
		fx.fade(vine, 1.6, { Transparency = 1, Size = Vector3.new(0.2, 4.5, 0.2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	for _, e in within(enemiesOf(self), center, sig.radius) do
		hit(self, f, e, f.damage * sig.damage, sig.color)
		if alive(e) then
			local slowed = e.slowUntil > e.clock
			e.slowUntil = math.max(e.slowUntil, e.clock + sig.root.time)
			e.slowFactor = math.min(if slowed then e.slowFactor else 1, sig.root.factor)
			fx.tint(e.model, sig.color, sig.root.time)
		end
	end
	for _, ally in ctx.fighters do
		if ally.side == f.side and alive(ally) and (ally.pos - f.pos).Magnitude <= Config.HealRadius then
			if ally ~= f then
				fx.beam(ctx.parent, staffTop(f), ally.pos + UP * ally.lift, sig.color2, 0.25, 0.35)
			end
			ctx.heal(ally, ally.maxHp * sig.heal)
		end
	end
end

CAST.Shadow = function(self, f, sig, _target)
	local ctx, fx = self.ctx, self.ctx.fx
	local options = within(enemiesOf(self), f.pos, f.range + Config.SignatureReach + 6)
	table.sort(options, function(a, b)
		return a.hp / a.maxHp < b.hp / b.maxHp
	end)
	for i = 1, math.min(sig.hits, #options) do
		local e = options[i]
		ctx.schedule((i - 1) * 0.12, function()
			if not alive(e) then
				return
			end
			fx.beam(ctx.parent, staffTop(f), e.pos + UP * e.lift, sig.color, 0.6, 0.3)
			fx.afterimage(ctx.parent, e.pos, e.lift, sig.color)
			hit(self, f, e, f.damage * sig.damage, sig.color)
			if alive(e) and not e.boss and e.hp < e.maxHp * sig.execute then
				ctx.popNumber(e, ctx.damage(e, e.hp + 1, f), WHITE)
				fx.pop(ctx.parent, e.pos + UP * (e.lift * 2 + 1.5), "EXECUTE", sig.color2, 20)
			end
		end)
	end
end

CAST.Arcane = function(self, f, sig, _target)
	local ctx, fx = self.ctx, self.ctx.fx
	local reach = f.range + Config.SignatureReach + 4
	for i = 1, sig.hits do
		ctx.schedule((i - 1) * 0.1, function()
			if not alive(f) then
				return
			end
			local options = within(enemiesOf(self), f.pos, reach)
			if #options == 0 then
				return
			end
			local e = options[self.rng:NextInteger(1, #options)]
			fx.beam(ctx.parent, staffTop(f), e.pos + UP * e.lift, if i % 2 == 0 then sig.color2 else sig.color, 0.35, 0.25)
			fx.groundRing(ctx.parent, e.pos, sig.color, 2.5, 0.3)
			hit(self, f, e, f.damage * sig.damage, sig.color)
		end)
	end
end

local function stepSignatures(self: State)
	local ctx = self.ctx
	local now = ctx.clock()
	for f, element in self.elements do
		if not alive(f) or now < (self.nextSignature[f] or math.huge) or f.stunUntil > f.clock then
			continue
		end
		local target = nearestWithin(self, f, f.range + Config.SignatureReach)
		if not target then
			continue
		end
		local sig = Config.Signatures[element]
		self.nextSignature[f] = now + BattleSpells.signatureCooldown(f.mageLevel or 1)
		ctx.fx.pop(ctx.parent, f.pos + UP * (f.lift * 2 + 3), sig.label, sig.color2, 22)
		ctx.fx.crystalFlash(f.model, sig.color, 0.5, 3)
		ctx.fx.groundRing(ctx.parent, f.pos, sig.color, 4, 0.4)
		CAST[element](self, f, sig, target)
	end
end

BattleSpells.signatureCooldown = Config.signatureCooldown

-- ── Deaths: the combo, the boss's fall, explosive and splitter enemies ──────────

-- Called by BattleService for every fighter that just died (before its kill is paid, so the combo's coins count).
function BattleSpells.onDeath(self: State, f: any)
	local ctx = self.ctx
	if f.side ~= ctx.enemySide then
		return
	end
	local now = ctx.clock()
	local K = Config.Combo
	if now - self.lastKill <= K.Window then
		self.combo += 1
	else
		self.combo = 1
	end
	self.lastKill = now
	local bonus = math.min(K.CoinMax, K.CoinStep * (self.combo - 1))
	f.bonusCoins += bonus
	if self.combo >= K.Show then
		ctx.feel({ kind = "combo", n = self.combo, bonus = math.floor(bonus * 100 + 0.5) })
	end
	if f.boss then
		ctx.feel({ kind = "boss", shake = Config.BossShake })
		local others = 0
		for _, e in ctx.fighters do
			if e.side == ctx.enemySide and alive(e) then
				others += 1
			end
		end
		if others > 0 then
			ctx.slowmo(Config.BossSlowmo.Speed, Config.BossSlowmo.Time)
		end
	end
	local affix = self.affixes[f]
	if affix == "explosive" then
		explode(self, f)
	elseif affix == "splitter" then
		split(self, f)
	end
	self.affixes[f] = nil
end

function BattleSpells.step(self: State, _dt: number)
	stepReinforcements(self)
	stepSignatures(self)
	for f, tag in self.shieldTags do
		if not alive(f) or f.shieldHp <= 0 then
			tag:Destroy() -- the bubble popped (BattleFx.shieldBreak shows it)
			self.shieldTags[f] = nil
		end
	end
end

return BattleSpells
