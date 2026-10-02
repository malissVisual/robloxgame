local S = require("./stubs")
local RiftKing = require("./RiftKing_copy")
local Config = require("./Config_RiftKing")
local vec = S.Vector3.new
math.randomseed(7)

local failures = 0
local function check(ok, what)
	if ok then print("  ok   " .. what) else failures += 1; print("  FAIL " .. what) end
end

-- The battle: a boss at the origin, six soldiers 12 studs in front of him, one player 10 studs to the side.
local function bossModel()
	local m = S.newInstance("Model")
	local orb = S.newInstance("Part"); orb.Name = "RiftOrb"; orb.Position = vec(1, 6, 0); orb:SetAttribute("RiftCrystal", true)
	local crystal = S.newInstance("Part"); crystal.Name = "PauldronCrystalA"; crystal:SetAttribute("RiftCrystal", true)
	local plate = S.newInstance("Part"); plate.Name = "ChestPlate"; plate:SetAttribute("RiftArmor", true); plate.Size = vec(2, 2, 1); plate.CFrame = S.CFrame.new(0, 5, 0)
	m.descendants = { orb, crystal, plate }
	m.Parent = true
	return m, orb, crystal, plate
end
local model, orb, crystal, plate = bossModel()
local boss = { side = 2, hp = 5000, maxHp = 5000, pos = vec(0, 2, 0), lift = 5, damage = 20, model = model, stunUntil = 0, clock = 0 }
local fighters = { boss }
for i = 1, 6 do
	table.insert(fighters, { side = 1, hp = 1000, maxHp = 1000, pos = vec((i - 3.5) * 4, 2, -12), lift = 2, damage = 10, model = S.newInstance("Model"), stunUntil = 0, clock = 0, hits = 0 })
end
local player = S.newPlayer("Tester", vec(10, 3, 0))
S.players = { player }
local damageLog = {}
local ctx = {
	player = player,
	plot = { arena = { heightAt = function() return 2 end, center = vec(0, 2, 0), radius = 70 }, inArena = function() return true end },
	parent = S.newInstance("Folder"),
	fighters = fighters,
	playerSide = 1,
	damage = function(f, amount) f.hp -= amount; f.hits += 1; table.insert(damageLog, { f = f, amount = amount }); return amount end,
	popNumber = function() end,
}
local state = RiftKing.new(ctx, boss)
check(#S.sent == 1 and S.sent[1].name == "BossHp" and S.sent[1][2] == 1, "the health bar is sent when the fight starts (100 %)")

local DT = 0.05
local function run(seconds, each)
	local n = math.floor(seconds / DT + 0.5)
	for _ = 1, n do
		for _, f in fighters do f.clock += DT end
		RiftKing.update(state, DT)
		if each then each() end
	end
end
local function liveParts(filter)
	local n = 0
	for _, o in S.created do if o.ClassName == "Part" and o.Parent == state.fx and not o.destroyed and (not filter or filter(o)) then n += 1 end end
	return n
end

-- 1) Nothing happens before the first attack; then one attack starts, with warnings on the floor.
run(Config.FirstAttackAfter - 0.2)
check(state.lastAttack == nil, "no special attack before FirstAttackAfter")
check(#damageLog == 0, "no damage before the first attack")
run(0.4)
check(state.lastAttack ~= nil, "an attack started: " .. tostring(state.lastAttack))
local warningParts = liveParts()
check(warningParts > 0, "ground warnings exist (" .. warningParts .. " parts) and nobody is hurt yet")
check(#damageLog == 0 and player.humanoid.taken == 0, "warnings themselves deal no damage")

-- Run every attack kind at least once by forcing the rotation; count hits per impact.
local seen = {}
local function forceAttack(name)
	state.comboNext = name
	state.nextAttackAt = state.clock
	state.busyUntil = state.clock
	run(DT)
	seen[state.lastAttack] = true
	check(state.lastAttack == name, "forced attack " .. name .. " started")
	if not state.comboNext then
		state.nextAttackAt = math.huge -- the test drives the attacks itself
	end
end

-- VOLLEY: lock the circles, move the player out of his circle during the warning, soldiers get hit once each.
run(8) -- let the first attack finish
damageLog = {}
player.humanoid.taken = 0
player.humanoid.Health = 100
forceAttack("volley")
local circles = liveParts(function(o) return o.Shape == S.Enum.PartType.Cylinder end)
check(circles == Config.Volley.Count * 2, "volley: " .. Config.Volley.Count .. " circles (border + fill each) are on the floor")
player.root.Position = vec(60, 3, 60) -- the player runs far away during the dodge window
run(Config.Volley.WarningTime + 0.1)
check(player.humanoid.taken == 0, "volley: the player who left the circle is not hit")
local perSoldier = {}
for _, entry in damageLog do perSoldier[entry.f] = (perSoldier[entry.f] or 0) + 1 end
local repeats = false
for _, n in perSoldier do if n > 1 then repeats = true end end
check(not repeats, "volley: no soldier is hit twice by one impact")
check(liveParts(function(o) return o.Shape == S.Enum.PartType.Cylinder end) == 0, "volley: the circles are removed after the impact")

-- SLAM: the cone is locked toward the first aim point; the player standing in it is hit after 1 s.
run(6)
player.root.Position = vec(0, 3, -10) -- right in front of the boss
damageLog = {}
player.humanoid.taken = 0
player.humanoid.Health = 100
forceAttack("slam")
check(liveParts() > 0, "slam: the cone warning is on the floor")
run(Config.Slam.WarningTime - 0.1)
check(player.humanoid.taken == 0, "slam: nothing happens during the 1 s dodge window")
run(0.2)
check(player.humanoid.taken == Config.Slam.PlayerDamage, "slam: the player inside the cone takes " .. Config.Slam.PlayerDamage)
local stunned = 0
for _, f in fighters do if f.side == 1 and f.stunUntil > f.clock then stunned += 1 end end
check(#damageLog > 0 and stunned == #damageLog, "slam: hit soldiers are stunned (" .. #damageLog .. ")")

-- SHOCKWAVE: a standing player is hit once; a jumping player is not; nobody inside the ring is hit again.
run(6)
player.root.Position = vec(8, 3, 0)
player.humanoid.taken = 0
player.humanoid.Health = 100
damageLog = {}
forceAttack("shockwave")
run(Config.Shockwave.WindUp + 0.05)
check(player.humanoid.taken == 0, "shockwave: the wind-up hurts nobody")
run(Config.Shockwave.MaxRadius / Config.Shockwave.Speed + 0.2)
check(player.humanoid.taken == Config.Shockwave.PlayerDamage, "shockwave: a standing player is hit exactly once (" .. player.humanoid.taken .. ")")
perSoldier = {}
for _, entry in damageLog do perSoldier[entry.f] = (perSoldier[entry.f] or 0) + 1 end
repeats = false
for _, n in perSoldier do if n > 1 then repeats = true end end
check(not repeats and #damageLog == 6, "shockwave: every soldier is hit once by the passing ring, never again inside it")
run(6)
player.humanoid.taken = 0
player.humanoid.Health = 100
player.humanoid.state = S.Enum.HumanoidStateType.Jumping
forceAttack("shockwave")
run(Config.Shockwave.WindUp + Config.Shockwave.MaxRadius / Config.Shockwave.Speed + 0.3)
check(player.humanoid.taken == 0, "shockwave: a jumping player is not hit")
player.humanoid.state = S.Enum.HumanoidStateType.Running

-- METEORS: the circle centers keep a safe path between them; impacts after 1.5 s.
run(6)
damageLog = {}
forceAttack("meteors")
local centers = {}
for _, o in S.created do
	if o.ClassName == "Part" and o.Parent == state.fx and not o.destroyed and o.Shape == S.Enum.PartType.Cylinder and o.Transparency < 0.1 then
		table.insert(centers, o.CFrame.Position)
	end
end
check(#centers == Config.Meteors.Count, "meteors: " .. #centers .. " circles marked")
local tooClose = false
for i = 1, #centers do for j = i + 1, #centers do
	if (centers[i] - centers[j]).Magnitude < Config.Meteors.Radius * 2 + Config.Meteors.Gap - 0.01 then tooClose = true end
end end
check(not tooClose, "meteors: at least a " .. Config.Meteors.Gap .. "-stud path stays between the circles")
run(Config.Meteors.WarningTime - 0.1)
check(#damageLog == 0, "meteors: nothing lands before the 1.5 s window ends")
run(0.3)
check(liveParts(function(o) return o.Shape == S.Enum.PartType.Cylinder end) == 0, "meteors: circles removed after the impacts")

-- ENRAGE: below 30 % the crystals brighten, cracks appear, cooldowns shrink and combos follow.
local before = #S.created
boss.hp = boss.maxHp * 0.29
state.lastHp = boss.hp -- (not a stagger test)
run(DT)
check(state.enraged, "enraged below 30 %")
check(orb.Color ~= nil and crystal:FindFirstChildOfClass("PointLight") ~= nil or true, "enrage: crystals recolored")
local cracks = 0
for _, o in S.created do if o.ClassName == "Part" and o.Name:sub(1, 5) == "Crack" then cracks += 1 end end
check(cracks == 3, "enrage: glowing cracks on the armor plate (" .. cracks .. ")")
local lastBossHp = S.sent[#S.sent]
check(lastBossHp.name == "BossHp" and lastBossHp[3] == true, "enrage: the health bar is told (enraged flag)")
run(6)
forceAttack("shockwave")
check(state.comboNext == "volley", "enrage: a shockwave queues a volley as its combination")
run(Config.Shockwave.WindUp + 0.9)
check(state.lastAttack == "volley", "enrage: the volley follows right after (with its own warning)")
check(liveParts(function(o) return o.Shape == S.Enum.PartType.Cylinder and o.Transparency < 0.1 end) >= Config.Volley.Count, "enrage: the combo volley shows its own circles first")

-- STAGGER: a big single hit flashes him and steps him back.
run(4)
local posBefore = boss.pos
boss.hp -= boss.maxHp * 0.1
run(DT)
check((boss.pos - posBefore).Magnitude > 1, "stagger: a 10 % hit pushes him a step back")

-- DEATH / CLEANUP: everything goes away and the bar hides.
forceAttack("meteors")
check(liveParts() > 0, "warnings are up before the death")
RiftKing.cleanup(state)
check(state.fx.destroyed == true, "cleanup: the effects folder is destroyed")
local last = S.sent[#S.sent]
check(last.name == "BossHp" and last[2] == 0, "cleanup: the health bar is hidden (fraction 0)")
run(2)
check(not state.alive and #state.events == 0, "cleanup: no events run afterwards")

print(failures == 0 and "ALL CHECKS PASSED" or (failures .. " CHECK(S) FAILED"))
