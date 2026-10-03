--!strict
-- The fight's extra action (numbers in Config/BattleSpells.luau): REINFORCEMENTS (part of the wave comes again a few
-- seconds in), the player's METEOR (the round button / F during a fight) and the element wizards' SIGNATURE spells
-- (Inferno, Frost Nova, Thunderstorm, Wild Grove, Shadow Claw, Arcane Barrage). BattleService creates one State per
-- battle with a context (the same helpers the brains and the wave twists get), calls step(dt) every tick and
-- castMeteor() when the player presses the button. Everything runs on the battle clock (schedule / movers), so the
-- battle speed (2x) and the end of the battle (events and movers are cleared) are handled by BattleService.

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
	wave: number,
	boss: boolean, -- a boss wave
	twists: { string }, -- the ids of the wave's twists
	random: Random?,
}

export type State = {
	ctx: Ctx,
	meteorReady: number, -- battle clock
	nextSignature: { [any]: number }, -- mage fighter → battle clock of its next signature spell
	elements: { [any]: string }, -- mage fighter → its element (only the element wizards)
	reinforce: boolean, -- this wave gets reinforcements (not sent yet)
	starting: { any }, -- the starting combat enemies (their deaths trigger the reinforcements early)
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

function BattleSpells.new(ctx: Ctx): State
	local self: State = {
		ctx = ctx,
		meteorReady = Config.Meteor.FirstDelay,
		nextSignature = {},
		elements = {},
		reinforce = false,
		starting = {},
		rng = ctx.random or Random.new(),
	}
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

-- ── The player's meteor ─────────────────────────────────────────────────────

-- Returns (cast, battle seconds until the next one).
function BattleSpells.castMeteor(self: State): (boolean, number)
	local ctx, M = self.ctx, Config.Meteor
	local now = ctx.clock()
	if now < self.meteorReady then
		return false, self.meteorReady - now
	end
	local enemies = enemiesOf(self)
	local target = densest(enemies, M.Radius)
	if not target then
		return false, 0
	end
	local power = 0
	for _, f in ctx.fighters do
		if f.side == ctx.playerSide and alive(f) then
			power += f.damage
		end
	end
	if power <= 0 then
		return false, 0
	end
	self.meteorReady = now + M.Cooldown
	local point = Vector3.new(target.pos.X, ctx.groundY(target.pos), target.pos.Z)
	local fx = ctx.fx
	local reticle = fx.reticle(ctx.fxFolder, point, M.Radius, M.Color, point.Y + 0.05)
	ctx.emit("playerSpell", { id = "meteor", point = point }) -- the mages combo their area spells into it
	local rock = fx.newPart(ctx.fxFolder, Vector3.one * 5, CFrame.new(point + Vector3.new(14, 60, 10)), M.Color, 0, Enum.PartType.Ball)
	local core = fx.newPart(ctx.fxFolder, Vector3.one * 3, rock.CFrame, M.Color2, 0, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = M.Color
	light.Range = 30
	light.Brightness = 4
	light.Parent = rock
	local from = rock.Position
	local elapsed = 0
	ctx.addMover(function(dt: number): boolean
		elapsed += dt
		local f = math.clamp(elapsed / M.Fall, 0, 1)
		local pos = from:Lerp(point + UP * 2, f * f)
		if rock.Parent then
			rock.CFrame = CFrame.new(pos)
			core.CFrame = CFrame.new(pos)
			if math.random() < 0.7 then
				fx.sparks(ctx.fxFolder, pos - UP, M.Color, 1, 1.5, 3) -- a burning trail
			end
		end
		if f < 1 then
			return true
		end
		rock:Destroy()
		core:Destroy()
		reticle:Destroy()
		-- IMPACT
		fx.groundRing(ctx.parent, point, M.Color, M.Radius * 1.3, 0.6)
		fx.groundRing(ctx.parent, point, M.Color2, M.Radius * 0.8, 0.4)
		fx.sparks(ctx.parent, point, M.Color, 24, M.Radius, 9)
		fx.sparks(ctx.parent, point, M.Color2, 12, M.Radius * 0.6, 12)
		local flash = fx.newPart(ctx.parent, Vector3.one * 4, CFrame.new(point + UP * 2), M.Color2, 0.1, Enum.PartType.Ball)
		fx.fade(flash, 0.5, { Size = Vector3.one * (M.Radius * 2.4), Transparency = 1 })
		fx.pop(ctx.parent, point + UP * 6, "METEOR!", M.Color2, 30)
		for _, enemy in within(enemiesOf(self), point, M.Radius) do
			local amount = power * M.Damage * (if enemy.boss then M.BossDamage else 1)
			ctx.popNumber(enemy, ctx.damage(enemy, amount, nil), M.Color)
			if alive(enemy) then
				enemy.stunUntil = math.max(enemy.stunUntil, enemy.clock + M.Stun)
				fx.tint(enemy.model, M.Color, M.Stun)
			end
		end
		return false
	end)
	return true, M.Cooldown
end

function BattleSpells.meteorIn(self: State): number
	return math.max(0, self.meteorReady - self.ctx.clock())
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

local function hit(self: State, f: any, target: any, amount: number, color: Color3): number
	local taken = self.ctx.damage(target, amount, f)
	self.ctx.popNumber(target, taken, color)
	return taken
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

function BattleSpells.step(self: State, _dt: number)
	stepReinforcements(self)
	stepSignatures(self)
end

return BattleSpells
