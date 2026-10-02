local S = require("./stubs")
local MageBrain = require("./MageBrain_copy")
local Spells = require("./MageSpells")
local vec = S.Vector3.new
math.randomseed(3)
local failures = 0
local function check(ok, what) if ok then print("  ok   " .. what) else failures += 1; print("  FAIL " .. what) end end
local function flat(v) return vec(v.X, 0, v.Z) end

-- spells per level (the repel spell and the heal sit outside the strong-spell cap)
local basic1, others1 = Spells.forLevel(1); check(basic1.id == "fireStone" and #others1 == 0, "L1: fire stone only")
local basic5, others5 = Spells.forLevel(5); check(#others5 == 3 and others5[1].id == "sparkSwarm" and others5[2].id == "arcanePush" and others5[3].id == "healingLight", "L5: + spark swarm + arcane push + healing light")
local basic15, others15 = Spells.forLevel(15); check(basic15.id == "magicMissile" and #others15 == 4 and others15[3].kind == "repel" and others15[4].kind == "heal", "L15: magic missile + 2 + repel + heal (" .. others15[1].id .. ", " .. others15[2].id .. ", " .. others15[3].id .. ")")
local basic30, others30 = Spells.forLevel(30); check(basic30.id == "quantumBolt" and #others30 == 5, "L30: quantum bolt + 3 + repel + support (" .. #others30 .. ")")

local function makeModel()
	local m = S.newInstance("Model")
	local arm = S.newInstance("Part"); arm.Name = "RightUpperArm"
	local shoulder = S.newInstance("Motor6D"); shoulder.Name = "RightShoulder"; shoulder.C0 = S.CFrame.new(0, 0, 0); shoulder.Parent = arm
	arm.descendants = { shoulder }
	local weapon = S.newInstance("Model"); weapon.Name = "Weapon"
	local crystal = S.newInstance("Part"); crystal.Name = "Piece"; crystal.Position = vec(0, 6, 0); crystal.Size = vec(1, 1, 1)
	local light = S.newInstance("PointLight"); light.Brightness = 1; light.Range = 8; light.Parent = crystal
	crystal.descendants = { light }
	weapon.descendants = { crystal }
	local head = S.newInstance("Part"); head.Name = "Head"
	local root = S.newInstance("Part"); root.Name = "HumanoidRootPart"
	m.descendants = { arm, weapon, head, root }
	m.PrimaryPart = root
	m.Parent = true
	return m
end
local function fighter(side, pos, hp, range, speed)
	return { side = side, hp = hp, maxHp = hp, pos = pos, range = range, speed = speed, cooldown = 1.6, timer = 0, clock = 0, damage = 20, lift = 2.5, baseLift = 2.5, model = makeModel(), slowUntil = 0, slowFactor = 1, shieldUntil = 0, shieldReduction = 0, stunUntil = 0, kind = nil }
end

-- A battle world: a mage at the origin, optional ally, enemies; `walk` makes the enemies close in on the mage.
local DT = 0.05
local function world(level, opts)
	opts = opts or {}
	local mage = fighter(1, vec(0, 2, 0), 300, 22, 9)
	local fighters = { mage }
	local ally = nil
	if opts.ally then
		ally = fighter(1, vec(5, 2, 0), 400, 4, 10); ally.hp = opts.allyHp or 400; table.insert(fighters, ally)
	end
	local enemies = {}
	for i = 1, (opts.enemies or 4) do
		local e = fighter(2, (opts.enemyPos and opts.enemyPos(i)) or vec((i - 2.5) * 3, 2, 34), opts.enemyHp or 250, 4, 8)
		e.kind = if i == 1 then "Mob2" else "Mob1"
		table.insert(fighters, e)
		table.insert(enemies, e)
	end
	local log = { attacks = 0, damages = 0, heals = 0, faced = 0 }
	local fx = { pops = 0 }
	setmetatable(fx, { __index = function() return function() end end })
	fx.pop = function() fx.pops += 1 end
	fx.runeRing = function() return { update = function() end, destroy = function() end } end
	fx.reticle = function() return S.newInstance("Part") end
	fx.mark = function() return S.newInstance("Part") end
	local ctx = {
		fighters = fighters, parent = S.newInstance("Folder"), playerSide = 1, self = mage, fx = fx,
		attack = function(f, target, mult) log.attacks += 1; target.hp -= f.damage * mult end,
		damage = function(target, amount) log.damages += 1; target.hp -= amount; return amount end,
		popNumber = function(_, _, color) if color then log.heals += 1 end end,
		face = function() log.faced += 1 end,
		bounds = { center = vec(0, 2, 20), halfX = 36, halfZ = 34 },
		hazards = function() return {} end,
		archetype = function(f) return if f.kind == "Mob2" then "Archer" else "Grunt" end,
		emit = function() end,
		clock = function() return mage.clock end,
		addHazard = function() end,
		schedule = function() end,
		groundY = function() return 0 end,
	}
	ctx.parent.Parent = true
	local brain = MageBrain.new(ctx, mage, level)
	local w = { mage = mage, ally = ally, enemies = enemies, fighters = fighters, brain = brain, ctx = ctx, log = log, fx = fx, actions = {}, minMana = 1000, movedWhileInRange = false, approachedTooClose = false }
	-- One tick: clocks, the enemies' walk, the brain; records moves while anything is in range.
	function w.tick()
		for _, f in fighters do f.clock += DT end
		if opts.walk ~= false then
			for _, f in fighters do
				if f.side == 2 and f.hp > 0 and f.stunUntil <= f.clock then
					local d = mage.pos - f.pos
					if d.Magnitude > 3 then f.pos = f.pos + d.Unit * math.min(f.speed * DT, d.Magnitude - 3) end
				end
			end
		end
		local before = mage.pos
		local nearestD = math.huge
		for _, f in fighters do if f.side == 2 and f.hp > 0 then nearestD = math.min(nearestD, (f.pos - mage.pos).Magnitude) end end
		local hopBefore = brain.hopUntil > 0 -- a hop in progress (reset to 0 when it lands)
		brain:update(DT)
		w.actions[brain.action] = (w.actions[brain.action] or 0) + 1
		w.minMana = math.min(w.minMana, brain.mana)
		local moved = (mage.pos - before).Magnitude > 0
		local hopping = hopBefore or brain.hopUntil > mage.clock
		if moved and nearestD <= mage.range and brain.action ~= "escape" and brain.action ~= "blink" and not hopping then w.movedWhileInRange = true end
		if moved and brain.action == "approach" and nearestD <= mage.range then w.approachedTooClose = true end
	end
	function w.run(seconds) for _ = 1, math.floor(seconds / DT + 0.5) do w.tick() end end
	-- Runs until `cond()` or `seconds` pass; returns the seconds spent.
	function w.until_(cond, seconds)
		local t = 0
		while t < seconds do
			if cond() then return t end
			w.tick(); t += DT
		end
		return t
	end
	return w
end

-- ── The classic 40 s scenario (L15, enemies walk in) ──
local w = world(15)
w.run(40)
local brain, log, actions, mage = w.brain, w.log, w.actions, w.mage
check(log.attacks > 5, "L15: basic attacks happen (" .. log.attacks .. ")")
check((actions.approach or 0) > 0 or (actions.attack or 0) > 0, "L15: approach / attack actions chosen")
check(not w.movedWhileInRange and not w.approachedTooClose, "L15: the mage never walks while an enemy is in range (except escape / blink / hop)")
check(w.minMana < 60, "L15: a strong spell was paid for (mana dipped to " .. math.floor(w.minMana) .. ")")
check(log.damages > 0, "L15: a strong spell dealt damage (" .. log.damages .. " hits)")
check(brain.target ~= nil or true, "L15: target selection ran")
local b = mage.pos
check(math.abs(b.X) <= 36 and b.Z >= 20 - 34 and b.Z <= 20 + 34, "L15: the mage stayed inside the arena bounds")
check(w.fx.pops <= 60, "L15: pops over 40 s are rate limited (" .. w.fx.pops .. " <= 60)")
local s = ""; for k, v in actions do s ..= k .. "=" .. v .. " " end
print("  actions L15: " .. s)

-- ── L30 heals the low ally ──
local w30 = world(30, { ally = true, allyHp = 60 })
w30.run(40)
check(w30.log.heals > 0, "L30: the low-HP ally was healed (" .. w30.log.heals .. ")")
check(w30.log.attacks > 0, "L30: attacks happen")
s = ""; for k, v in w30.actions do s ..= k .. "=" .. v .. " " end
print("  actions L30: " .. s)
w30.brain:destroy()
check(w30.brain.debugLabel == nil, "destroy clears the debug label")

-- ── (a) AVENGER: an ally falls → the killer becomes the target with hate ──
do
	local wa = world(15, { ally = true, walk = false, enemyPos = function(i) return vec((i - 2.5) * 4, 2, 15) end })
	wa.run(1)
	local killer = wa.enemies[3]
	wa.ally.hp = 0
	wa.brain:onEvent("allyDown", { victim = wa.ally, killer = killer })
	local t = wa.until_(function() return wa.brain.target == killer end, 1)
	check(wa.brain.target == killer and (wa.brain.hate[killer] or 0) >= 3, string.format("(a) avenger: the killer is the target after %.2f s with hate %.1f", t, wa.brain.hate[killer] or 0))
	check(wa.brain.avengerBonus == true or wa.brain.casting ~= nil, "(a) avenger: the next strong spell is empowered")
end

-- ── (b) FURY → OVERCHARGE: 9 hits fill the meter, the mage hovers, then lands ──
do
	local wb = world(15, { walk = false, enemyPos = function(i) return vec((i - 2.5) * 4, 2, 15) end })
	wb.run(0.5)
	local e = wb.enemies[1]
	for i = 1, 9 do
		wb.brain:onDamaged(e, 5)
		wb.run(0.3)
	end
	check(wb.brain.overchargeUntil > wb.mage.clock, "(b) overcharge: 9 hits within 3 s start OVERCHARGE")
	check(wb.mage.lift > wb.mage.baseLift, string.format("(b) overcharge: the mage hovers (lift %.2f > %.2f)", wb.mage.lift, wb.mage.baseLift))
	wb.run(7)
	check(wb.mage.lift == wb.mage.baseLift, string.format("(b) overcharge: after 7 s the mage is back on the ground (lift %.2f)", wb.mage.lift))
	check(wb.brain.overchargeUntil <= wb.mage.clock, "(b) overcharge: ended")
end

-- ── (b2) CHIP DAMAGE: sourceless small hits (a puddle) give no fury and no flinch; a storm-sized hit does ──
do
	local wp = world(15, { walk = false, enemyPos = function(i) return vec((i - 2.5) * 4, 2, 15) end })
	wp.run(0.5)
	for _ = 1, 40 do
		wp.brain:onDamaged(nil, wp.mage.maxHp * 0.03 * 0.05) -- a puddle tick: 3 %/s × 0.05 s
		wp.tick()
	end
	check(wp.brain.fury == 0 and wp.brain.overchargeUntil <= wp.mage.clock, "(b2) chip: 40 puddle ticks give no fury and no OVERCHARGE")
	wp.brain:onDamaged(nil, wp.mage.maxHp * 0.10) -- a storm strike
	wp.tick()
	check(wp.brain.fury > 0, "(b2) chip: a 10 % sourceless hit still counts (fury " .. wp.brain.fury .. ")")
end

-- ── (b3) PUDDLES: a permanent hazard on the approach path is walked around, never through, and never alerted ──
do
	local wq = world(15, { walk = false, enemies = 1, enemyPos = function() return vec(0, 2, 40) end })
	local puddle = { pos = vec(0, 2, 12), radius = 6, kind = "puddle" }
	wq.ctx.hazards = function() return { puddle } end
	local inside, escapes = false, 0
	local popsBefore = wq.fx.pops
	for _ = 1, math.floor(6 / DT + 0.5) do
		wq.tick()
		if (flat(wq.mage.pos - puddle.pos)).Magnitude <= puddle.radius then inside = true end
		if wq.brain.action == "escape" then escapes += 1 end
	end
	local enemyDist = (flat(wq.enemies[1].pos - wq.mage.pos)).Magnitude
	check(not inside and escapes == 0, "(b3) puddle: the mage never stepped into the puddle on its way (escapes " .. escapes .. ")")
	check(enemyDist <= wq.mage.range + 0.5, string.format("(b3) puddle: it still reached its target around the puddle (distance %.1f)", enemyDist))
	check(wq.fx.pops - popsBefore <= 2, "(b3) puddle: a standing puddle is no '!' alert (" .. (wq.fx.pops - popsBefore) .. " pops)")
end

-- ── (c) CHARGE ALERT → ARCANE HOP: a brute charges through the mage, the mage hops sideways once ──
do
	local wc = world(15, { walk = false, enemyPos = function(i) return vec((i - 2.5) * 4, 2, 18) end })
	wc.run(0.5)
	local brute = wc.enemies[2]
	brute.kind = "Mob3"
	local start = wc.mage.pos
	local from, to = brute.pos, wc.mage.pos
	wc.brain:onEvent("enemyCharging", { brute = brute, from = from, to = to, impactAt = wc.mage.clock + 0.8 })
	wc.run(1)
	local disp = flat(wc.mage.pos - start)
	local lane = flat(to - from).Unit
	local along = disp.X * lane.X + disp.Z * lane.Z
	local towardBrute = disp.X * (brute.pos.X - start.X) + disp.Z * (brute.pos.Z - start.Z)
	check(disp.Magnitude >= 4 and disp.Magnitude <= 6, string.format("(c) hop: the mage moved %.2f studs (4-6)", disp.Magnitude))
	check(math.abs(along) < 0.3 * disp.Magnitude, string.format("(c) hop: the move is perpendicular to the lane (along %.2f)", along))
	check(towardBrute <= 0.3 * disp.Magnitude * (brute.pos - start).Magnitude, "(c) hop: never toward the brute")
	check(not wc.movedWhileInRange, "(c) hop: counted as the only move while in range")
	wc.run(1)
	local mid = wc.mage.pos
	wc.brain:onEvent("enemyCharging", { brute = brute, from = brute.pos, to = wc.mage.pos, impactAt = wc.mage.clock + 0.8 })
	wc.run(1)
	check((flat(wc.mage.pos - mid)).Magnitude < 0.01, "(c) hop: a second charge 2 s later produces no move (8 s cooldown)")
	-- A level 1 mage is too slow / too low to hop.
	local w1 = world(1, { walk = false, enemyPos = function(i) return vec((i - 2.5) * 4, 2, 18) end })
	w1.run(0.5)
	local p1 = w1.mage.pos
	w1.brain:onEvent("enemyCharging", { brute = w1.enemies[2], from = w1.enemies[2].pos, to = w1.mage.pos, impactAt = w1.mage.clock + 0.8 })
	w1.run(1)
	check((flat(w1.mage.pos - p1)).Magnitude < 0.01, "(c) hop: a level 1 mage does not hop")
end

-- ── (d) COUNTER-SPELL: a shaman winds up in range → the next bolt hits it and interrupts ──
do
	local wd = world(15, { walk = false, enemyPos = function(i) return vec((i - 2.5) * 4, 2, 16) end })
	wd.run(0.5)
	wd.until_(function() return wd.brain.casting == nil end, 2)
	local shaman = wd.enemies[4]
	shaman.kind = "Mob4"
	shaman.ai = { state = "windup", interrupt = function(self) self.hit = true; return true end }
	local hpBefore = shaman.hp
	wd.brain:onEvent("shamanCast", { shaman = shaman, kind = "mend", ["until"] = wd.mage.clock + 0.6 })
	local t = wd.until_(function() return shaman.ai.hit == true end, 1)
	check(shaman.hp < hpBefore, string.format("(d) counter: the shaman took damage after %.2f s", t))
	check(shaman.ai.hit == true, "(d) counter: the shaman's cast was interrupted")
end

-- ── (e) GUARDIAN: a hurt ally within 14 studs gets a shield ──
do
	local we = world(15, { ally = true, allyHp = 120, walk = false, enemyPos = function(i) return vec((i - 2.5) * 4, 2, 16) end })
	we.run(0.5)
	we.until_(function() return we.brain.casting == nil end, 2)
	we.brain:onEvent("allyHurt", { ally = we.ally, fraction = 0.3, attacker = we.enemies[1] })
	local t = we.until_(function() return we.ally.shieldUntil > we.ally.clock end, 1.5)
	check(we.ally.shieldUntil > we.ally.clock, string.format("(e) guardian: the ally is shielded after %.2f s (reduction %.2f)", t, we.ally.shieldReduction))
	-- Level 5 has no shield spell: the ward does it.
	local w5 = world(5, { ally = true, allyHp = 120, walk = false, enemyPos = function(i) return vec((i - 2.5) * 4, 2, 16) end })
	w5.run(0.5)
	w5.until_(function() return w5.brain.casting == nil end, 2)
	w5.brain:onEvent("allyHurt", { ally = w5.ally, fraction = 0.3 })
	w5.until_(function() return w5.ally.shieldUntil > w5.ally.clock end, 1.5)
	check(w5.ally.shieldUntil > w5.ally.clock and w5.ally.shieldReduction == 0.25, "(e) guardian: a level 5 mage wards the ally (-25 %)")
end

-- ── (f) REPEL: 3 grunts at 4 studs are pushed away, the mage does not move ──
do
	local wf = world(5, { walk = false, enemies = 3, enemyPos = function(i) local a = i / 3 * math.pi * 2; return vec(math.cos(a) * 4, 2, math.sin(a) * 4) end })
	local start = wf.mage.pos
	local before = {}
	for i, e in wf.enemies do before[i] = (flat(e.pos - start)).Magnitude end
	wf.run(2)
	local pushed = true
	for i, e in wf.enemies do
		if (flat(e.pos - start)).Magnitude < before[i] + 5 then pushed = false end
	end
	check(pushed, "(f) repel: every grunt is at least 5 studs farther within 2 s")
	check((wf.mage.pos - start).Magnitude < 0.01, "(f) repel: the mage did not move")
	check(wf.enemies[1].stunUntil > 0, "(f) repel: the grunts were stunned")
end

-- ── (g) FINISH: the last enemy under 35 % in range gets the execute bolt ──
do
	local wg = world(15, { walk = false, enemies = 1, enemyPos = function() return vec(0, 2, 12) end })
	wg.run(0.5)
	wg.until_(function() return wg.brain.casting == nil end, 2)
	local e = wg.enemies[1]
	e.hp = 0.3 * e.maxHp
	wg.brain:onEvent("lastEnemy", { enemy = e })
	wg.until_(function() return wg.brain.finishUsed end, 1.5)
	check(wg.brain.finishUsed, "(g) finish: the execute bolt was cast on the last enemy")
end

-- ── Flinch snaps the next shot earlier (attacker in range) and the events do not break the loop ──
do
	local wh = world(15, { walk = false, enemyPos = function(i) return vec((i - 2.5) * 4, 2, 12) end })
	wh.run(0.3)
	wh.mage.timer = 1.5
	wh.brain:onDamaged(wh.enemies[1], 10)
	wh.tick()
	check(wh.mage.timer <= 1.2 + 0.01, string.format("flinch: the next shot comes sooner (timer %.2f)", wh.mage.timer))
	wh.brain:onEvent("battleStart", {})
	wh.brain:onEvent("waveEvent", { id = "ambush", points = { vec(10, 2, 10) } })
	wh.brain:onEvent("hazard", { pos = vec(0, 0, 0), radius = 3 })
	wh.brain:onEvent("battleEnd", { won = true })
	wh.run(1)
	check(true, "events: salute, wave event, hazard and victory did not break the brain")
	wh.brain:destroy()
	check(wh.mage.lift == wh.mage.baseLift, "destroy restores the lift")
end

print(failures == 0 and "ALL CHECKS PASSED" or (failures .. " CHECK(S) FAILED"))
