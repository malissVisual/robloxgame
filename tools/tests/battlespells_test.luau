-- Logic test of server/Services/BattleSpells.luau (run by run_battlespells_test.py with the Roblox stubs): the
-- reinforcements (when, how many, which waves), the player's meteor (cooldown, damage from the squad, bosses) and the
-- six element signature spells (each one casts, hits and does its own thing).
local Stubs = require("./stubs")
local Vector3 = Stubs.Vector3
local BattleSpells = require("./BattleSpells")
local Config = require("./Config")

local fails = 0
local function check(ok: boolean, msg: string)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

local PLAYER, ENEMY = 1, 2

local function newFighter(side, x, z, extra)
	local f = {
		side = side, hp = 100, maxHp = 100, pos = Vector3.new(x, 0, z), lift = 2, damage = 10, range = 22, clock = 0,
		stunUntil = 0, slowUntil = 0, slowFactor = 1, burnUntil = 0, burnDps = 0, burnBy = nil, boss = false,
		model = Stubs.newInstance("Model"), kind = "Mob1", tier = 1,
	}
	for k, v in extra or {} do
		f[k] = v
	end
	return f
end

local function noop() end
local function fakePart()
	return Stubs.newInstance("Part")
end

local function newBattle(opts)
	local battle = { clock = 0, events = {}, movers = {}, pending = 0, pops = {}, spawned = {}, notices = {}, emitted = {}, healed = 0 }
	battle.fighters = opts.fighters
	local fx = setmetatable({
		newPart = function(_, _, cf, _, _, _)
			local p = fakePart()
			p.CFrame = cf
			p.Position = cf.Position
			return p
		end,
		reticle = function() return fakePart() end,
		warningCircle = function() return { fakePart() } end,
		pop = function(_, _, text) table.insert(battle.pops, text) end,
	}, { __index = function() return noop end })
	local ctx = {
		fighters = battle.fighters, playerSide = PLAYER, enemySide = ENEMY, parent = Stubs.newInstance("Folder"), fx = fx,
		fxFolder = Stubs.newInstance("Folder"),
		groundY = function() return 0 end,
		damage = function(target, amount)
			local taken = math.min(target.hp, amount)
			target.hp -= taken
			return taken
		end,
		popNumber = noop,
		heal = function(target, amount)
			target.hp = math.min(target.maxHp, target.hp + amount)
			battle.healed += amount
		end,
		schedule = function(delay, fn) table.insert(battle.events, { at = battle.clock + delay, fn = fn }) end,
		addMover = function(fn) table.insert(battle.movers, fn) end,
		addHazard = noop,
		emit = function(name, payload) table.insert(battle.emitted, { name = name, payload = payload }) end,
		notify = function(text) table.insert(battle.notices, text) end,
		spawnEnemy = function(kind, tier, pos)
			local f = newFighter(ENEMY, pos.X, pos.Z, { kind = kind, tier = tier })
			table.insert(battle.fighters, f)
			table.insert(battle.spawned, f)
			return f
		end,
		hold = function(n) battle.pending += n end,
		archetype = function(f) return f.archetype or "Grunt" end,
		clock = function() return battle.clock end,
		center = Vector3.new(0, 0, 0),
		wave = opts.wave or 3,
		boss = opts.boss == true,
		twists = opts.twists or {},
		random = Stubs.Random.new(7),
	}
	battle.state = BattleSpells.new(ctx)
	function battle.advance(seconds)
		local dt = 0.05
		local t = 0
		while t < seconds - 1e-9 do
			t += dt
			battle.clock += dt
			for _, f in battle.fighters do
				f.clock += dt
			end
			table.sort(battle.events, function(a, b) return a.at < b.at end)
			while battle.events[1] and battle.events[1].at <= battle.clock do
				table.remove(battle.events, 1).fn()
			end
			for i = #battle.movers, 1, -1 do
				if not battle.movers[i](dt) then
					table.remove(battle.movers, i)
				end
			end
			BattleSpells.step(battle.state, dt)
		end
	end
	return battle
end

local function enemies(n, z)
	local list = {}
	for i = 1, n do
		table.insert(list, newFighter(ENEMY, (i - 1) * 2, z or 15))
	end
	return list
end

-- ── Reinforcements ──
do
	local fighters = enemies(6)
	table.insert(fighters, newFighter(PLAYER, 0, 0))
	local b = newBattle({ fighters = fighters, wave = 3 })
	b.advance(5.9)
	check(#b.spawned == 0 and b.pending == 0, "no reinforcements before At")
	b.advance(0.2)
	check(b.pending == 2, "6 enemies: 2 announced (" .. b.pending .. ")")
	check(table.find(b.notices, "REINFORCEMENTS!") ~= nil, "announced")
	b.advance(Config.Reinforcements.Warning + 0.1)
	check(#b.spawned == 2 and b.pending == 0, "2 arrive after the warning, nothing pending")
	b.advance(20)
	check(#b.spawned == 2, "only once")
end
do
	local fighters = enemies(10)
	local b = newBattle({ fighters = fighters, wave = 3 })
	for i = 1, 4 do
		fighters[i].hp = 0 -- 40 % dead
	end
	b.advance(0.1)
	check(b.pending == 4, "early when 40 % are dead; 10 → 4 (max) (" .. b.pending .. ")")
end
for _, case in { { wave = 1 }, { wave = 5, boss = true }, { wave = 20, twists = { "ambush" } }, { wave = 20, twists = { "swarm" } } } do
	local b = newBattle({ fighters = enemies(6), wave = case.wave, boss = case.boss, twists = case.twists })
	b.advance(10)
	check(#b.spawned == 0 and b.pending == 0, "no reinforcements on wave " .. case.wave)
end

-- ── The meteor ──
do
	local fighters = enemies(4, 30)
	local boss = newFighter(ENEMY, 2, 30, { boss = true, maxHp = 1000, hp = 1000 })
	table.insert(fighters, boss)
	table.insert(fighters, newFighter(ENEMY, 80, 80)) -- far away
	local mages = {}
	for i = 1, 3 do
		local m = newFighter(PLAYER, i * 3, 0, { damage = 20 })
		table.insert(mages, m)
		table.insert(fighters, m)
	end
	for _, f in fighters do
		f.maxHp, f.hp = math.max(f.maxHp, 1000), math.max(f.hp, 1000)
	end
	local b = newBattle({ fighters = fighters, wave = 1 }) -- (wave 1: no reinforcements to confuse the counts)
	local ok, wait = BattleSpells.castMeteor(b.state)
	check(not ok and math.abs(wait - Config.Meteor.FirstDelay) < 1e-6, "refused before FirstDelay")
	b.advance(Config.Meteor.FirstDelay + 0.01)
	ok, wait = BattleSpells.castMeteor(b.state)
	check(ok and wait == Config.Meteor.Cooldown, "cast once ready")
	local spell = false
	for _, e in b.emitted do
		if e.name == "playerSpell" and e.payload.id == "meteor" then
			spell = true
		end
	end
	check(spell, "playerSpell emitted (the mages' combo)")
	ok = BattleSpells.castMeteor(b.state)
	check(not ok, "refused while cooling down")
	b.advance(Config.Meteor.Fall + 0.1)
	local expected = 60 * Config.Meteor.Damage
	check(math.abs(fighters[1].hp - (1000 - expected)) < 1e-6, "a mob takes 1.2 × the squad's attack (" .. fighters[1].hp .. ")")
	check(math.abs(boss.hp - (1000 - expected * Config.Meteor.BossDamage)) < 1e-6, "the boss takes less")
	check(fighters[6].hp == 1000, "far enemies are not hit")
	check(fighters[1].stunUntil > fighters[1].clock, "stunned")
	b.advance(Config.Meteor.Cooldown)
	ok = BattleSpells.castMeteor(b.state)
	check(ok, "ready again after the cooldown")
end

-- ── The signature spells ──
local variants = { Fire = "Ember", Ice = "Frost", Storm = "Storm", Nature = "Verdant", Shadow = "Shadow", Arcane = "Arcane" }
for element, variant in variants do
	local fighters = enemies(5, 12)
	for _, e in fighters do
		e.maxHp, e.hp = 1000, 1000
	end
	fighters[5].hp = 60 -- 6 %: the Shadow Claw executes it
	local mage = newFighter(PLAYER, 0, 0, { variant = variant, mageLevel = 1, damage = 50 })
	local ally = newFighter(PLAYER, 4, 0, { hp = 40 })
	table.insert(fighters, mage)
	table.insert(fighters, ally)
	local b = newBattle({ fighters = fighters, wave = 1 })
	b.advance(Config.SignatureFirst + 2.5)
	local label = Config.Signatures[element].label
	check(table.find(b.pops, label) ~= nil, element .. ": " .. label .. " cast")
	local hurt = 0
	for i = 1, 4 do
		hurt += 1000 - fighters[i].hp
	end
	check(hurt > 0, element .. ": enemies hit")
	if element == "Ice" then
		local frozen = false
		for i = 1, 4 do
			frozen = frozen or fighters[i].stunUntil > 0 -- (the freeze may be over by now)
		end
		check(frozen, "Ice freezes")
	elseif element == "Fire" then
		local burning = false
		for i = 1, 4 do
			burning = burning or fighters[i].burnUntil > fighters[i].clock
		end
		check(burning, "Fire burns")
	elseif element == "Nature" then
		check(ally.hp > 40, "Nature heals the squad")
	elseif element == "Shadow" then
		check(fighters[5].hp <= 0, "Shadow executes the weak one")
	end
	local count = 0
	for _, text in b.pops do
		if text == label then
			count += 1
		end
	end
	b.advance(Config.signatureCooldown(1) + 0.1)
	local again = 0
	for _, text in b.pops do
		if text == label then
			again += 1
		end
	end
	check(again == count + 1, element .. ": casts again after its cooldown")
end
do -- a wizard without an element (Void) and an enemy-free fight cast nothing
	local mage = newFighter(PLAYER, 0, 0, { variant = "Void", mageLevel = 5 })
	local b = newBattle({ fighters = { mage, newFighter(ENEMY, 0, 10) }, wave = 1 })
	b.advance(20)
	check(#b.pops == 0, "Void has no signature")
end
check(Config.signatureCooldown(1) == Config.SignatureCooldownLow and Config.signatureCooldown(16) == Config.SignatureCooldownTop, "cooldown by level")

if fails == 0 then
	print("ALL CHECKS PASSED")
else
	print(fails .. " CHECKS FAILED")
end
