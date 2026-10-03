-- Logic test of server/Services/BattleSpells.luau (run by run_battlespells_test.py with the Roblox stubs): the
-- reinforcements (when, how many, which waves), the player's four spells (cooldowns, damage from the squad, bosses,
-- aiming), the six element signature spells, the enemy affixes, the kill combo and the boss's fall.
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
		model = Stubs.newInstance("Model"), kind = "Mob1", tier = 1, bonusCoins = 0, haste = 1, shieldHp = 0,
		shieldUntil = 0, shieldReduction = 0,
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
	local battle = { clock = 0, events = {}, movers = {}, pending = 0, pops = {}, spawned = {}, notices = {}, emitted = {}, healed = 0, feel = {}, slowmo = 0, marks = {} }
	battle.fighters = opts.fighters
	local fx = setmetatable({
		newPart = function(_, _, cf, _, _, _)
			local p = fakePart()
			p.CFrame = cf
			p.Position = cf.Position
			return p
		end,
		reticle = function() return fakePart() end,
		mark = function(_, text) table.insert(battle.marks, text); return fakePart() end,
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
		arenaRadius = 70,
		feel = function(data) table.insert(battle.feel, data) end,
		slowmo = function(_, seconds) battle.slowmo = seconds end,
		scaleModel = function(f, scale) f.lift *= scale end,
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
	check(not ok and math.abs(wait - Config.PlayerSpells.meteor.first) < 1e-6, "refused before FirstDelay")
	b.advance(Config.PlayerSpells.meteor.first + 0.01)
	ok, wait = BattleSpells.castMeteor(b.state)
	check(ok and wait == Config.PlayerSpells.meteor.cooldown, "cast once ready")
	local spell = false
	for _, e in b.emitted do
		if e.name == "playerSpell" and e.payload.id == "meteor" then
			spell = true
		end
	end
	check(spell, "playerSpell emitted (the mages' combo)")
	ok = BattleSpells.castMeteor(b.state)
	check(not ok, "refused while cooling down")
	b.advance(Config.PlayerSpells.meteor.fall + 0.1)
	local expected = 60 * Config.PlayerSpells.meteor.damage
	check(math.abs(fighters[1].hp - (1000 - expected)) < 1e-6, "a mob takes 1.2 × the squad's attack (" .. fighters[1].hp .. ")")
	check(math.abs(boss.hp - (1000 - expected * Config.PlayerSpells.meteor.bossDamage)) < 1e-6, "the boss takes less")
	check(fighters[6].hp == 1000, "far enemies are not hit")
	check(fighters[1].stunUntil > fighters[1].clock, "stunned")
	b.advance(Config.PlayerSpells.meteor.cooldown)
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

-- ── The other player spells ──
local function squadAndWave(wave)
	local fighters = enemies(5, 30)
	for _, e in fighters do
		e.maxHp, e.hp = 1000, 1000
	end
	local mages = {}
	for i = 1, 3 do
		local m = newFighter(PLAYER, i * 3, 0, { damage = 20, hp = 30 })
		table.insert(mages, m)
		table.insert(fighters, m)
	end
	return fighters, mages
end
do
	local fighters, _ = squadAndWave()
	local b = newBattle({ fighters = fighters, wave = 1 })
	b.advance(Config.PlayerSpells.frost.first + 0.01)
	local ok = BattleSpells.castPlayer(b.state, "frost", Vector3.new(4, 0, 30))
	check(ok, "blizzard cast at an aimed point")
	local frozen = 0
	for i = 1, 5 do
		if fighters[i].stunUntil > fighters[i].clock + 1 then
			frozen += 1
		end
	end
	check(frozen >= 3, "blizzard freezes the group (" .. frozen .. ")")
	check(table.find(b.marks, "FROZEN") ~= nil, "FROZEN tags")
end
do
	local fighters, _ = squadAndWave()
	local b = newBattle({ fighters = fighters, wave = 1 })
	b.advance(Config.PlayerSpells.lightning.first + 0.01)
	local ok = BattleSpells.castPlayer(b.state, "lightning", Vector3.new(999, 0, 999)) -- outside the arena: aims itself
	check(ok, "lightning cast (bad aim → auto)")
	b.advance(1)
	local struck = 0
	for i = 1, 5 do
		if fighters[i].hp < 1000 then
			struck += 1
		end
	end
	check(struck == 5, "lightning jumps through the whole group (" .. struck .. ")")
end
do
	local fighters, mages = squadAndWave()
	local b = newBattle({ fighters = fighters, wave = 1 })
	local ok, wait = BattleSpells.castPlayer(b.state, "heal", nil)
	check(not ok and wait > 0, "heal not ready at once")
	b.advance(Config.PlayerSpells.heal.first + 0.01)
	ok = BattleSpells.castPlayer(b.state, "heal", nil)
	check(ok and mages[1].hp > 30 and mages[1].shieldUntil > mages[1].clock, "heal heals and shields the squad")
	check(not BattleSpells.castPlayer(b.state, "nonsense", nil), "unknown spell refused")
end

-- ── Affixes ──
do
	check(Config.affixChance(1) == 0 and Config.affixChance(4) > 0 and Config.affixChance(500) == Config.Affixes.ChanceMax, "affix chance by wave")
	local fighters = enemies(60, 20)
	local b = newBattle({ fighters = fighters, wave = 30 })
	local count, kinds = 0, {}
	for f, id in b.state.affixes do
		count += 1
		kinds[id] = true
		check(f.bonusCoins >= Config.Affixes.Coins, "an affixed enemy pays more")
	end
	check(count > 5 and count < 50, "some enemies have affixes (" .. count .. ")")
	check(kinds.giant and kinds.splitter and kinds.explosive and kinds.shielded and kinds.swift, "every affix appears at wave 30")
	for f, id in b.state.affixes do
		if id == "shielded" then
			check(f.shieldHp > 0, "shielded has a bubble")
		elseif id == "giant" then
			check(f.maxHp > 100 and f.lift > 2, "giant is bigger")
		elseif id == "swift" then
			check(f.haste > 1, "swift is faster")
		end
	end
end
do -- a splitter's death: two smaller copies, the wave held while they come
	local f = newFighter(ENEMY, 0, 10)
	local mage = newFighter(PLAYER, 0, 0)
	local b = newBattle({ fighters = { f, mage }, wave = 1 })
	b.state.affixes[f] = "splitter"
	f.hp = 0
	BattleSpells.onDeath(b.state, f)
	check(b.pending == 2, "split: 2 on their way")
	b.advance(0.1)
	check(#b.spawned == 2 and b.pending == 0 and b.spawned[1].maxHp < f.maxHp, "split: 2 small copies")
end
do -- an explosive's death: the mages inside are hurt after the warning
	local f = newFighter(ENEMY, 0, 2, { damage = 10 })
	local mage = newFighter(PLAYER, 0, 0)
	local far = newFighter(PLAYER, 30, 0)
	local b = newBattle({ fighters = { f, mage, far }, wave = 1 })
	b.state.affixes[f] = "explosive"
	f.hp = 0
	BattleSpells.onDeath(b.state, f)
	check(mage.hp == 100, "explosion waits for its warning")
	b.advance(Config.Affixes.Defs.explosive.delay + 0.1)
	check(mage.hp < 100 and far.hp == 100, "explosion hurts the mage inside only")
end

-- ── Combo and the boss's fall ──
do
	local list = enemies(4)
	local boss = newFighter(ENEMY, 0, 40, { boss = true })
	table.insert(list, boss)
	local b = newBattle({ fighters = list, wave = 1 })
	for i = 1, 3 do
		list[i].hp = 0
		BattleSpells.onDeath(b.state, list[i])
		b.advance(0.5)
	end
	check(b.state.combo == 3, "3 quick kills = combo 3")
	check(math.abs(list[3].bonusCoins - 2 * Config.Combo.CoinStep) < 1e-9, "the 3rd kill pays 20 % more")
	local shown = false
	for _, d in b.feel do
		if d.kind == "combo" and d.n == 3 then
			shown = true
		end
	end
	check(shown, "the combo is sent to the screen")
	b.advance(Config.Combo.Window + 0.5)
	list[4].hp = 0
	BattleSpells.onDeath(b.state, list[4])
	check(b.state.combo == 1, "a slow kill starts a new combo")
	boss.hp = 0
	-- (no other enemy left: no slow motion, but the banner)
	BattleSpells.onDeath(b.state, boss)
	local banner = false
	for _, d in b.feel do
		banner = banner or d.kind == "boss"
	end
	check(banner and b.slowmo == 0, "boss: banner, no slow motion when the fight is over")
end
do
	local boss = newFighter(ENEMY, 0, 40, { boss = true })
	local other = newFighter(ENEMY, 5, 40)
	local b = newBattle({ fighters = { boss, other }, wave = 1 })
	boss.hp = 0
	BattleSpells.onDeath(b.state, boss)
	check(b.slowmo > 0, "boss: slow motion while the fight goes on")
end

if fails == 0 then
	print("ALL CHECKS PASSED")
else
	print(fails .. " CHECKS FAILED")
end
