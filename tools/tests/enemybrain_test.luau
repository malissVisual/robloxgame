-- Logic test of the enemy brains (run by run_enemybrain_test.py): a tiny battle loop with the Roblox stubs, static
-- soldiers and the brains stepping every 0.05 s. The ctx mirrors the one BattleService builds; the default
-- "walk to the nearest and hit" branch is a simplified copy of BattleService.step.
local S = require("./stubs")
local EnemyBrain = require("./EnemyBrain_copy")
local Config = require("./EnemyAI")
local vec = S.Vector3.new
math.randomseed(7)
local failures = 0
local function check(ok, what) if ok then print("  ok   " .. what) else failures += 1; print("  FAIL " .. what) end end
local function flatDist(a, b) return (vec(a.X, 0, a.Z) - vec(b.X, 0, b.Z)).Magnitude end
local function round(x) return math.floor(x * 100 + 0.5) / 100 end

local function makeModel()
	local m = S.newInstance("Model")
	local head = S.newInstance("Part"); head.Name = "Head"
	local root = S.newInstance("Part"); root.Name = "HumanoidRootPart"
	m.descendants = { head, root }
	m.PrimaryPart = root
	m.Parent = true
	return m
end
local function fighter(side, pos, hp, range, speed, damage, cooldown)
	return {
		side = side, hp = hp, maxHp = hp, pos = pos, lift = 2.5, baseLift = 2.5, range = range, speed = speed, cooldown = cooldown or 1,
		timer = 0, damage = damage or 10, clock = 0, stunUntil = 0, slowUntil = 0, slowFactor = 1, haste = 1, buffDamage = 0, buffUntil = 0,
		hexFactor = 1, hexUntil = 0, taunt = nil, passive = nil, passiveValue = 0, kind = nil, boss = false, model = makeModel(), ai = nil,
		lastHitBy = nil, summoned = false, shieldUntil = 0, shieldReduction = 0, shieldHp = 0,
	}
end

local DT = 0.05
local function world()
	local w = { clock = 0, fighters = {}, events = {}, movers = {}, emitted = {}, hazards = {}, hits = {}, heals = 0, healed = 0, attacks = 0, spawned = {}, playersHit = {}, pops = {}, notices = {} }
	local folder = S.newInstance("Folder"); folder.Parent = true
	local fx = setmetatable({}, { __index = function() return function() end end })
	fx.runeRing = function() return { update = function() end, destroy = function() end } end
	fx.warningCircle = function() return { S.newInstance("Part"), S.newInstance("Part") } end
	fx.warningLane = function() return { S.newInstance("Part"), S.newInstance("Part") } end
	fx.reticle = function() return S.newInstance("Part") end
	fx.mark = function() return S.newInstance("Part") end
	fx.newPart = function() return S.newInstance("Part") end
	fx.pop = function(_, _, text) table.insert(w.pops, text) end
	local function nearestSoldier(f)
		local best, bestD = nil, math.huge
		for _, o in w.fighters do
			if o.side == 1 and o.hp > 0 then
				local d = flatDist(o.pos, f.pos)
				if d < bestD then best, bestD = o, d end
			end
		end
		return best
	end
	local ctx = {
		fighters = w.fighters, playerSide = 1, parent = folder, fx = fx, fxFolder = folder,
		groundY = function() return 0 end,
		attack = function(f, target, mult) w.attacks += 1; target.hp -= f.damage * mult; target.lastHitBy = f end,
		hurt = function(target, amount, source) target.hp -= amount; target.lastHitBy = source; table.insert(w.hits, { target = target, amount = amount, source = source }); return amount end,
		heal = function(target, amount) target.hp = math.min(target.maxHp, target.hp + amount); w.heals += 1; w.healed += amount end,
		face = function() end,
		bounds = { center = vec(0, 2, 20), halfX = 36, halfZ = 34 },
		emit = function(name, payload) table.insert(w.emitted, { name = name, payload = payload }) end,
		addHazard = function(pos, radius, duration, kind, source) table.insert(w.hazards, { pos = pos, radius = radius, duration = duration, kind = kind, source = source }) end,
		schedule = function(delay, fn)
			local at = w.clock + delay
			local i = #w.events + 1
			while i > 1 and w.events[i - 1].at > at do i -= 1 end
			table.insert(w.events, i, { at = at, fn = fn })
		end,
		addMover = function(fn) table.insert(w.movers, fn) end,
		notify = function(text) table.insert(w.notices, text) end,
		spawnEnemy = function(kind, tier, pos) local f = fighter(2, pos, 50, 4, 12, 5, 1); f.kind = kind; table.insert(w.fighters, f); table.insert(w.spawned, f); return f end,
		hitPlayers = function(center, radius, hp) table.insert(w.playersHit, { center = center, radius = radius, hp = hp }) end,
		clock = function() return w.clock end,
		speed = function() return 1 end,
		wave = 10,
		archetype = function(f) return f.archetype end,
		summonKind = "Mob1", summonTier = 1,
		flags = {},
	}
	w.ctx = ctx
	function w.add(f, archetype, boss)
		table.insert(w.fighters, f)
		f.archetype = archetype
		if archetype then f.ai = EnemyBrain.new(ctx, f, archetype, boss == true) end
		return f
	end
	function w.count(name) local n = 0; for _, e in w.emitted do if e.name == name then n += 1 end end; return n end
	function w.last(name) for i = #w.emitted, 1, -1 do if w.emitted[i].name == name then return w.emitted[i].payload end end; return nil end
	function w.pop(text) local n = 0; for _, t in w.pops do if t == text then n += 1 end end; return n end
	-- The default branch of BattleService.step, simplified (enemies only; soldiers stand still unless a test moves them).
	local function default(f)
		local target = nearestSoldier(f)
		if not target then return end
		local d = target.pos - f.pos
		local dist = d.Magnitude
		local rate = (if f.slowUntil > f.clock then f.slowFactor else 1) * f.haste
		if dist <= f.range + 1 then
			f.timer -= DT * rate
			if f.timer <= 0 then f.timer = f.cooldown; ctx.attack(f, target, 1) end
		else
			f.pos = f.pos + d.Unit * math.min(f.speed * DT * rate, dist - f.range)
		end
	end
	function w.tick()
		w.clock += DT
		while w.events[1] and w.events[1].at <= w.clock do local e = table.remove(w.events, 1); e.fn() end
		for i = #w.movers, 1, -1 do if not w.movers[i](DT) then table.remove(w.movers, i) end end
		for _, f in w.fighters do
			if f.hp > 0 then
				f.clock += DT
				if f.stunUntil > f.clock then continue end
				if f.side == 2 then
					if not (f.ai and f.ai:update(DT)) then default(f) end
				end
			end
		end
		if w.each then w.each() end
	end
	function w.run(seconds) for _ = 1, math.floor(seconds / DT + 0.5) do w.tick() end end
	function w.until_(cond, seconds)
		local t = 0
		while t < seconds do
			if cond() then return true end
			w.tick(); t += DT
		end
		return cond()
	end
	return w
end

-- ── (1) + (2) Brute: telegraphed charge down a locked lane, impact on the soldier ──
do
	local w = world()
	local soldier = w.add(fighter(1, vec(0, 2, 20), 500, 4, 0, 10))
	local brute = w.add(fighter(2, vec(0, 2, 32), 300, 4, 0, 10, 1.4), "Brute")
	local ai = brute.ai
	local reached = w.until_(function() return ai.state == "windup" end, 5)
	check(reached and w.clock >= Config.AbilityGrace and w.clock >= Config.Brute.FirstCharge, "brute: wind-up after the grace and the first-charge delay (" .. round(w.clock) .. " s)")
	local charges = 0
	for _, h in w.hazards do if h.kind == "charge" and h.source == brute then charges += 1 end end
	check(charges >= 3, "brute: the lane put " .. charges .. " charge hazards on the floor")
	local ev = w.last("enemyCharging")
	check(ev ~= nil and ev.brute == brute and flatDist(ev.to, soldier.pos) < 0.01 and flatDist(ev.from, vec(0, 2, 32)) < 0.01, "brute: enemyCharging carries the locked lane from the brute to the soldier")
	check(ev ~= nil and ev.impactAt > w.clock and ev.impactAt <= w.clock + Config.Brute.WindUp + 0.01, "brute: impactAt is WindUp ahead")
	local hitsBefore = #w.hits
	w.run(Config.Brute.WindUp - 0.05)
	check(ai.state == "windup" and #w.hits == hitsBefore and flatDist(brute.pos, vec(0, 2, 32)) < 0.01, "brute: stands still for the whole wind-up, nobody hurt yet")
	w.until_(function() return ai.state ~= "windup" and ai.state ~= "charge" end, 1.5)
	check(math.abs(brute.pos.X) < 0.01 and flatDist(brute.pos, ev.to) <= 3, "brute: ran along the locked line and stopped within 3 studs of its end (" .. round(flatDist(brute.pos, ev.to)) .. ")")
	local hit = nil
	for _, h in w.hits do if h.target == soldier and h.source == brute then hit = h end end
	check(hit ~= nil and hit.amount >= brute.damage * Config.Brute.Damage - 0.01, "brute: the soldier took the charge damage (" .. (hit and round(hit.amount) or 0) .. " = 1.6x)")
	check(soldier.stunUntil > soldier.clock and flatDist(soldier.pos, vec(0, 2, 20)) >= 2.9, "brute: the soldier is stunned and pushed back")
	check(ai.state == "fight" and #w.playersHit == 1 and w.playersHit[1].hp == Config.Brute.PlayerDamage and w.playersHit[1].radius == Config.Brute.HitRadius, "brute: back to fighting; players in the lane end would take 20 HP")
end

-- ── (3) Brute: the soldier steps aside → dizzy, nobody hurt ──
do
	local w = world()
	local soldier = w.add(fighter(1, vec(0, 2, 20), 500, 4, 0, 10))
	local brute = w.add(fighter(2, vec(0, 2, 32), 300, 4, 0, 10, 1.4), "Brute")
	local ai = brute.ai
	w.until_(function() return ai.state == "windup" end, 5)
	soldier.pos = vec(6, 2, 20) -- the Mage hopped
	w.until_(function() return ai.state ~= "windup" and ai.state ~= "charge" end, 1.5)
	check(ai.state == "dizzy" and brute.stunUntil > brute.clock, "brute: a charge that hit nobody ends dizzy (stunned " .. round(brute.stunUntil - brute.clock) .. " s)")
	check(#w.hits == 0 and soldier.hp == 500, "brute: nobody was hurt by the empty charge")
	check(flatDist(brute.pos, vec(0, 2, 20)) < 0.05, "brute: it ran the whole locked lane (" .. round(brute.pos.Z) .. ")")
	w.run(Config.Brute.Dizzy + 0.3)
	check(ai.state ~= "dizzy" and brute.stunUntil <= brute.clock, "brute: shakes the dizziness off and fights again")
end

-- ── (4) Brute: the Mage's trip halves the charge speed ──
do
	local w = world()
	w.add(fighter(1, vec(0, 2, 20), 500, 4, 0, 10))
	local brute = w.add(fighter(2, vec(0, 2, 34), 300, 4, 0, 10, 1.4), "Brute")
	local ai = brute.ai
	w.until_(function() return ai.state == "windup" end, 5)
	brute.slowUntil = brute.clock + 1.2
	brute.slowFactor = 0.5
	w.until_(function() return ai.state == "charge" end, 1.5)
	local start = brute.pos
	w.run(0.2)
	local covered = flatDist(brute.pos, start)
	check(covered > 3 and covered < 5, "brute: tripped, it covers " .. round(covered) .. " studs in 0.2 s (half of 8)")
end

-- ── (4b) Brute: pushed off its lane during the wind-up (the Mage's repel) → the charge is cancelled, no snap back ──
do
	local w = world()
	w.add(fighter(1, vec(0, 2, 20), 500, 4, 0, 10))
	local brute = w.add(fighter(2, vec(0, 2, 34), 300, 4, 0, 10, 1.4), "Brute")
	local ai = brute.ai
	w.until_(function() return ai.state == "windup" end, 5)
	local pushed = brute.pos + vec(8, 0, 0)
	brute.pos = pushed
	brute.stunUntil = brute.clock + 0.6
	local charged = false
	w.each = function() if ai.state == "charge" then charged = true end end
	w.run(1.5)
	w.each = nil
	check(not charged and ai.state ~= "windup", "brute: a wind-up it was pushed out of never turns into a charge (state " .. ai.state .. ")")
	check(flatDist(brute.pos, pushed) < 3 and brute.pos.X > 6, "brute: it fights on from where it landed (x " .. round(brute.pos.X) .. "), no teleport to the lane start")
	check(w.pop("...") >= 1 and #w.hits == 0, "brute: the lost charge shows '...' and hurt nobody")
end

-- ── (5) Archer: one scurry, then shooting even with the threat near ──
do
	local w = world()
	local soldier = w.add(fighter(1, vec(0, 2, 24), 500, 4, 12, 10))
	local archer = w.add(fighter(2, vec(0, 2, 30), 100, 26, 10, 6, 1.3), "Archer")
	local ai = archer.ai
	w.each = function() -- the melee soldier follows the archer
		local d = archer.pos - soldier.pos
		if d.Magnitude > 3 then soldier.pos = soldier.pos + d.Unit * math.min(soldier.speed * DT, d.Magnitude - 3) end
	end
	local start = archer.pos
	check(w.until_(function() return ai.state == "scurry" end, 1), "archer: scurries when a melee soldier is within 8")
	w.run(1)
	local moved = flatDist(archer.pos, start)
	check(moved >= 7 and moved <= 9, "archer: ran " .. round(moved) .. " studs straight away (7-9)")
	check(ai.state ~= "scurry", "archer: stands again after 0.9 s")
	local attacksBefore = w.attacks
	w.run(2)
	check(w.attacks > attacksBefore, "archer: shooting resumed within 2 s (" .. (w.attacks - attacksBefore) .. " shots)")
	w.run(3)
	check(w.pop("EEK!") == 1, "archer: no second scurry within 6 s although the soldier follows (scurries: " .. w.pop("EEK!") .. ")")
	check(flatDist(archer.pos, soldier.pos) <= 3.1, "archer: the cornered archer lets the soldier reach it (" .. round(flatDist(archer.pos, soldier.pos)) .. ")")
end

-- ── Archers: lowest-HP target and focus fire ──
do
	local w = world()
	local healthy = w.add(fighter(1, vec(-4, 2, 20), 500, 4, 0, 10))
	local wounded = w.add(fighter(1, vec(4, 2, 20), 500, 4, 0, 10)); wounded.hp = 150
	local a1 = w.add(fighter(2, vec(-6, 2, 40), 100, 26, 10, 6, 1.3), "Archer")
	local a2 = w.add(fighter(2, vec(6, 2, 40), 100, 26, 10, 6, 1.3), "Archer")
	w.run(1)
	check(a1.ai.target == wounded and a2.ai.target == wounded, "archers: both shoot the soldier with the lowest HP fraction")
	local focused = w.until_(function() return w.count("focusFire") >= 1 end, 6)
	local ev = w.last("focusFire")
	check(focused and ev.target == wounded and #ev.archers == 2 and math.abs(ev.at - w.clock - Config.Archer.FocusTelegraph) < 0.01, "archers: focus fire announced at " .. round(w.clock) .. " s on the wounded soldier")
	check(a1.timer <= Config.Archer.FocusTelegraph + 0.001 and a2.timer <= Config.Archer.FocusTelegraph + 0.001 and math.abs(a1.timer - a2.timer) < DT + 0.001, "archers: both timers set so the volley lands together (" .. round(a1.timer) .. ", " .. round(a2.timer) .. ")")
	check(healthy.hp == 500 or wounded.hp < 150, "archers: the healthy soldier is not the one being chipped")
end

-- ── (6) Shaman: MEND heals after the wind-up; a big hit or interrupt() fizzles it ──
do
	local w = world()
	w.add(fighter(1, vec(0, 2, 10), 500, 4, 0, 10))
	local shaman = w.add(fighter(2, vec(0, 2, 40), 100, 20, 0, 10, 2), "Shaman")
	local ally = w.add(fighter(2, vec(4, 2, 42), 100, 4, 0, 5, 1), "Grunt"); ally.hp = 20
	local ai = shaman.ai
	check(w.until_(function() return ai.state == "windup" end, 3), "shaman: starts a cast after the grace (" .. round(w.clock) .. " s)")
	local ev = w.last("shamanCast")
	check(ev ~= nil and ev.shaman == shaman and ev.kind == "mend" and ai.castKind == "mend", "shaman: shamanCast { kind = mend } emitted, state windup")
	w.run(Config.Shaman.WindUp - 0.05)
	check(ally.hp == 20, "shaman: nothing healed before the wind-up ends")
	w.run(0.15)
	check(math.abs(ally.hp - 35) < 0.01 and ai.state ~= "windup", "shaman: MEND healed 15 % of max HP (" .. round(ally.hp) .. ")")
	check(ai:interrupt() == false, "shaman: interrupt() returns false when nothing is winding up")

	-- A hit of 15 % max HP during the next wind-up fizzles it.
	ally.hp = 20
	w.until_(function() return ai.state == "windup" end, 8)
	local at = w.clock
	ai:onDamaged(w.fighters[1], Config.Shaman.InterruptFraction * shaman.maxHp)
	check(ai.state ~= "windup" and w.pop("...") == 1, "shaman: a 15 % hit during the wind-up fizzles the cast")
	w.run(1)
	check(ally.hp == 20, "shaman: the fizzled MEND healed nothing")
	-- The fizzle cooldown is short; the Mage's counter-spell (interrupt) also fizzles.
	check(w.until_(function() return ai.state == "windup" end, Config.Shaman.FizzleCooldown + 0.5), "shaman: casts again " .. round(w.clock - at) .. " s after the fizzle")
	check(ai:interrupt() == true and ai.state ~= "windup" and ai.castKind == nil, "shaman: interrupt() fizzles a running wind-up and returns true")
	w.run(1)
	check(ally.hp == 20, "shaman: the silenced MEND healed nothing")
end

-- ── Shaman: hold distance (never retreats), FRENZY and HEX ──
do
	local w = world()
	local soldier = w.add(fighter(1, vec(0, 2, 20), 500, 4, 0, 30))
	local shaman = w.add(fighter(2, vec(0, 2, 50), 100, 20, 9, 10, 2), "Shaman")
	local grunt = w.add(fighter(2, vec(0, 2, 24), 100, 4, 0, 5, 1), "Grunt")
	w.run(1.5)
	local hold = flatDist(shaman.pos, soldier.pos)
	check(hold >= Config.Shaman.Hold - 0.1 and hold < 30, "shaman: advances to the hold distance and stops (" .. round(hold) .. ")")
	local held = shaman.pos
	soldier.pos = vec(0, 2, 26) -- the soldier walks in: the shaman must not step back (nor advance)
	w.run(1)
	check(flatDist(shaman.pos, held) < 0.01, "shaman: never retreats when the soldier closes in (z " .. round(shaman.pos.Z) .. ")")
	soldier.pos = vec(0, 2, 20)
	w.until_(function() return w.count("shamanCast") >= 1 end, 3)
	local ev = w.last("shamanCast")
	check(ev.kind == "frenzy", "shaman: FRENZY for the grunt that is fighting (no wounded ally)")
	w.run(Config.Shaman.WindUp + 0.1)
	-- (the grunt's own war cry may still be on it: hastes multiply)
	check(math.abs(grunt.buffDamage - Config.Shaman.Frenzy.Damage) < 0.01 and grunt.buffUntil > grunt.clock and grunt.haste >= Config.Shaman.Frenzy.Haste - 0.01, "shaman: the grunt is frenzied (+35 % damage, haste " .. round(grunt.haste) .. ")")
	w.run(Config.Shaman.Frenzy.Time + 0.2)
	check(grunt.haste == 1 and grunt.buffUntil <= grunt.clock, "shaman: the frenzy wears off (haste back to 1)")
	grunt.hp = 0 -- nobody to mend or frenzy: the next cast is a HEX
	w.until_(function() return w.count("shamanCast") >= 2 end, 8)
	ev = w.last("shamanCast")
	check(ev.kind == "hex", "shaman: HEX when nobody needs mending and no melee ally is fighting")
	w.run(Config.Shaman.WindUp + 0.1)
	check(math.abs(soldier.hexFactor - Config.Shaman.Hex.Factor) < 0.01 and soldier.hexUntil > soldier.clock, "shaman: the soldier with the highest damage is hexed")
end

-- ── (7) Grunt: WAR CRY hastes the pack ──
do
	local w = world()
	w.add(fighter(1, vec(0, 2, 20), 500, 4, 0, 10))
	local g1 = w.add(fighter(2, vec(0, 2, 36), 60, 4, 0, 5, 1), "Grunt")
	local g2 = w.add(fighter(2, vec(4, 2, 36), 60, 4, 0, 5, 1), "Grunt")
	local far = w.add(fighter(2, vec(30, 2, 50), 60, 4, 0, 5, 1), "Grunt")
	check(w.until_(function() return w.count("warcry") >= 1 end, 3), "grunt: a war cry after the grace (" .. round(w.clock) .. " s)")
	w.run(0.1)
	check(math.abs(g1.haste - Config.Grunt.CryHaste) < 0.01 and math.abs(g2.haste - Config.Grunt.CryHaste) < 0.01 and far.haste == 1, "grunt: grunts within 10 studs run at 1.2, the far one does not")
	local crier = w.last("warcry").grunt
	check((crier == g1 or crier == g2) and crier.ai.state == "cry", "grunt: the crier stands and roars")
	w.run(Config.Grunt.CryBuffTime + 0.2)
	check(g1.haste == 1 and g2.haste == 1, "grunt: the haste wears off after 3 s")
	check(w.count("warcry") == 1, "grunt: one cry per pack (gap 8 s)")
	w.run(1)
	check(math.abs(g1.buffDamage - Config.Grunt.GangPer) < 0.01 and g1.buffUntil > g1.clock, "grunt: gang up +10 % with one other grunt within 6")
end

-- ── (8) Brute: the wall (taunt) while a caster is near ──
do
	local w = world()
	w.add(fighter(1, vec(0, 2, -10), 500, 4, 0, 10))
	local brute = w.add(fighter(2, vec(0, 2, 36), 300, 4, 0, 10, 1.4), "Brute")
	local archer = w.add(fighter(2, vec(3, 2, 36), 60, 26, 0, 6, 1.3))
	archer.archetype = "Archer"
	w.run(0.6)
	check(brute.taunt == Config.Brute.GuardTaunt, "brute: taunt 8 while an archer stands within 6")
	archer.hp = 0
	w.run(0.6)
	check(brute.taunt == nil, "brute: taunt gone when the archer is gone")
	brute.hp = brute.maxHp * 0.2
	w.run(0.6)
	check(brute.ai.enraged and math.abs(brute.haste - Config.Brute.EnrageHaste) < 0.01 and w.pop("GRRR") == 1, "brute: enrages under 30 % HP (haste 1.25)")
end

-- ── (9) Boss slam: telegraphed 0.9 s, hits only inside radius 9 ──
do
	local w = world()
	local near = w.add(fighter(1, vec(0, 2, 25), 500, 4, 0, 10))
	local farAway = w.add(fighter(1, vec(0, 2, 15), 500, 4, 0, 10))
	local boss = w.add(fighter(2, vec(0, 2, 30), 1000, 4, 0, 10, 1.4), "Brute", true)
	boss.boss = true
	local ai = boss.ai
	check(w.until_(function() return ai.state == "windup" end, 6) and w.clock >= Config.Boss.FirstAbilityAt, "boss: the slam winds up after FirstAbilityAt (" .. round(w.clock) .. " s)")
	local slam = nil
	for _, h in w.hazards do if h.kind == "slam" then slam = h end end
	check(slam ~= nil and slam.radius == Config.Boss.SlamRadius and math.abs(slam.duration - Config.Boss.SlamWindUp) < 0.01, "boss: slam hazard radius 9 for 0.9 s")
	local ev = w.last("bossTelegraph")
	check(ev ~= nil and ev.ability == "slam" and ev.boss == boss and ev.radius == 9, "boss: bossTelegraph { slam } emitted")
	w.run(Config.Boss.SlamWindUp - 0.1)
	check(#w.hits == 0, "boss: nobody hurt before the telegraph ends")
	w.run(0.2)
	local hitNear, hitFar = false, false
	for _, h in w.hits do if h.target == near then hitNear = h.amount end; if h.target == farAway then hitFar = true end end
	check(hitNear and math.abs(hitNear - boss.damage * Config.Boss.SlamDamage) < 0.01 and not hitFar, "boss: only the soldier inside the circle took 2x damage")
	check(near.stunUntil > near.clock and #w.playersHit == 1 and w.playersHit[1].hp == Config.Boss.SlamPlayerDamage, "boss: the soldier is stunned; players inside would lose 25 HP")
	check(ai.state ~= "windup", "boss: fights again after the slam")
	-- Phase 2 at half HP.
	boss.hp = boss.maxHp * 0.45
	w.run(0.6)
	check(ai.phase2 and math.abs(ai.cooldownFactor - Config.Boss.EnrageCooldownFactor) < 0.01 and w.pop("ROAR!") == 1 and #w.notices == 1, "boss: phase 2 roar at 50 % (cooldowns x0.75, the player is told)")
end

-- ── Chief: summon at half HP with warning circles, rally horn ──
do
	local w = world()
	w.add(fighter(1, vec(0, 2, 10), 500, 4, 0, 10))
	local chief = w.add(fighter(2, vec(0, 2, 40), 1000, 5, 0, 16, 1.2), "Chief", true)
	chief.boss = true
	local grunt = w.add(fighter(2, vec(5, 2, 40), 60, 4, 0, 5, 1), "Grunt")
	check(w.until_(function() return w.count("bossTelegraph") >= 1 end, 6), "chief: the first telegraph comes (" .. round(w.clock) .. " s)")
	check(w.last("bossTelegraph").ability == "rally", "chief: RALLY HORN")
	w.run(Config.Boss.RallyWindUp + 0.1)
	check(math.abs(grunt.buffDamage - Config.Boss.RallyBonus) < 0.01 and math.abs(grunt.haste - (1 + Config.Boss.RallyBonus)) < 0.01, "chief: the grunt nearby is rallied")
	chief.hp = chief.maxHp * 0.45
	w.until_(function() return w.last("bossTelegraph") and w.last("bossTelegraph").ability == "summon" end, 2)
	local summons = 0
	for _, h in w.hazards do if h.kind == "summon" then summons += 1 end end
	check(summons == Config.Boss.SummonCount and #w.spawned == 0, "chief: 2 summon circles warned, nothing spawned yet")
	w.run(Config.Boss.SummonWarn + 0.1)
	check(#w.spawned == Config.Boss.SummonCount and chief.summoned, "chief: the mobs appear after the warning")
	chief.hp = chief.maxHp * 0.2
	w.run(Config.Boss.SummonWarn + 0.6)
	check(#w.spawned == Config.Boss.SummonCount + Config.Boss.DesperateCount, "chief: desperate call at 25 % brings 2 more (once)")
end

-- ── Treasure goblin flees, totem stands, destroy cleans up ──
do
	local w = world()
	local soldier = w.add(fighter(1, vec(0, 2, 20), 500, 4, 0, 10))
	local treasure = w.add(fighter(2, vec(0, 2, 30), 40, 0, 14, 0, 1), "Treasure")
	local totem = w.add(fighter(2, vec(10, 2, 38), 100, 0, 0, 0, 1), "Totem")
	w.run(2)
	check(treasure.pos.Z > 40 and w.attacks == 0, "treasure: runs away from the soldier and never attacks (z " .. round(treasure.pos.Z) .. ")")
	w.run(3)
	check(treasure.pos.Z <= 20 + 34 - 3 + 0.01 and math.abs(treasure.pos.X) <= 33.01, "treasure: stays inside the arena with a 3 stud margin")
	soldier.pos = vec(treasure.pos.X, 2, treasure.pos.Z - 4)
	local before = treasure.pos
	w.run(0.5)
	check(flatDist(treasure.pos, before) > 2, "treasure: cornered, it slides along the edge (" .. round(flatDist(treasure.pos, before)) .. ")")
	check(totem.pos.X == 10 and totem.pos.Z == 38 and totem.ai.state == "stand", "totem: stands still")
	local shaman = w.add(fighter(2, vec(0, 2, 44), 100, 20, 0, 10, 2), "Shaman")
	local ally = w.add(fighter(2, vec(4, 2, 44), 100, 4, 0, 5, 1), "Grunt"); ally.hp = 10
	w.until_(function() return shaman.ai.state == "windup" end, 3)
	shaman.ai:destroy()
	w.run(1)
	check(ally.hp == 10 and shaman.ai.runeRing == nil, "destroy: a scheduled cast never resolves and the runes are gone")
end

if failures == 0 then print("ALL CHECKS PASSED") else print(failures .. " CHECK(S) FAILED") end
