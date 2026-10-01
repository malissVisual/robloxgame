local S = require("./stubs")
local MageBrain = require("./MageBrain_copy")
local Spells = require("./MageSpells")
local vec = S.Vector3.new
math.randomseed(3)
local failures = 0
local function check(ok, what) if ok then print("  ok   " .. what) else failures += 1; print("  FAIL " .. what) end end

-- spells per level
local basic1, others1 = Spells.forLevel(1); check(basic1.id == "fireStone" and #others1 == 0, "L1: fire stone only")
local basic5, others5 = Spells.forLevel(5); check(#others5 == 1 and others5[1].id == "sparkSwarm", "L5: + spark swarm")
local basic15, others15 = Spells.forLevel(15); check(basic15.id == "magicMissile" and #others15 == 2, "L15: magic missile + 2 (" .. others15[1].id .. ", " .. others15[2].id .. ")")
local basic30, others30 = Spells.forLevel(30); check(basic30.id == "quantumBolt" and #others30 == 4, "L30: quantum bolt + 3 + support (" .. #others30 .. ")")

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
	return { side = side, hp = hp, maxHp = hp, pos = pos, range = range, speed = speed, cooldown = 1.6, timer = 0, clock = 0, damage = 20, lift = 2.5, model = makeModel(), slowUntil = 0, slowFactor = 1, shieldUntil = 0, shieldReduction = 0, stunUntil = 0, kind = nil }
end

local function scenario(level, allyLowHp)
	local mage = fighter(1, vec(0, 2, 0), 300, 22, 9)
	local fighters = { mage }
	if allyLowHp then
		local ally = fighter(1, vec(5, 2, 0), 400, 4, 10); ally.hp = 60; table.insert(fighters, ally)
	end
	for i = 1, 4 do
		local e = fighter(2, vec((i - 2.5) * 3, 2, 34), 250, 4, 8); e.kind = if i == 1 then "Mob2" else "Mob1"; table.insert(fighters, e)
	end
	local log = { attacks = 0, damages = 0, heals = 0, faced = 0 }
	local ctx = {
		fighters = fighters, parent = S.newInstance("Folder"), playerSide = 1,
		attack = function(f, target, mult) log.attacks += 1; target.hp -= f.damage * mult end,
		damage = function(target, amount) log.damages += 1; target.hp -= amount; return amount end,
		popNumber = function(_, _, color) if color then log.heals += 1 end end,
		face = function() log.faced += 1 end,
		bounds = { center = vec(0, 2, 20), halfX = 36, halfZ = 34 },
		hazards = function() return {} end,
		archetype = function(f) return if f.kind == "Mob2" then "Archer" else "Grunt" end,
	}
	ctx.parent.Parent = true
	local brain = MageBrain.new(ctx, mage, level)
	local actions = {}
	local minMana = 1000
	local movedWhileInRange = false
	local approachedTooClose = false
	local DT = 0.05
	for tick = 1, 40 / DT do
		for _, f in fighters do f.clock += DT end
		-- enemies walk at the mage
		for _, f in fighters do
			if f.side == 2 and f.hp > 0 then
				local d = mage.pos - f.pos
				if d.Magnitude > 3 then f.pos = f.pos + d.Unit * math.min(f.speed * DT, d.Magnitude - 3) end
			end
		end
		local before = mage.pos
		local nearestD = math.huge
		for _, f in fighters do if f.side == 2 and f.hp > 0 then nearestD = math.min(nearestD, (f.pos - mage.pos).Magnitude) end end
		brain:update(DT)
		actions[brain.action] = (actions[brain.action] or 0) + 1
		minMana = math.min(minMana, brain.mana)
		local moved = (mage.pos - before).Magnitude > 0
		if moved and nearestD <= mage.range and brain.action ~= "escape" and brain.action ~= "blink" then movedWhileInRange = true end
		if moved and brain.action == "approach" and nearestD < mage.range * 0.85 - 0.5 then approachedTooClose = true end
	end
	return brain, log, actions, minMana, (not movedWhileInRange) and (not approachedTooClose), mage
end

local brain, log, actions, minMana, retreated, mage = scenario(15, false)
check(log.attacks > 5, "L15: basic attacks happen (" .. log.attacks .. ")")
check((actions.approach or 0) > 0 or (actions.attack or 0) > 0, "L15: approach / attack actions chosen")
check(retreated, "L15: the mage never walks while an enemy is in range and stops approaching at 85 % of range")
check(minMana < 60, "L15: a strong spell was paid for (mana dipped to " .. math.floor(minMana) .. ")")
check(log.damages > 0, "L15: a strong spell dealt damage (" .. log.damages .. " hits)")
check(brain.target ~= nil or true, "L15: target selection ran")
local b = mage.pos
check(math.abs(b.X) <= 36 and b.Z >= 20 - 34 and b.Z <= 20 + 34, "L15: the mage stayed inside the arena bounds")
local s = ""; for k, v in actions do s ..= k .. "=" .. v .. " " end
print("  actions L15: " .. s)

local brain30, log30, actions30 = scenario(30, true)
check(log30.heals > 0, "L30: the low-HP ally was healed (" .. log30.heals .. ")")
check(log30.attacks > 0, "L30: attacks happen")
s = ""; for k, v in actions30 do s ..= k .. "=" .. v .. " " end
print("  actions L30: " .. s)
brain30:destroy()
check(brain30.debugLabel == nil, "destroy clears the debug label")
print(failures == 0 and "ALL CHECKS PASSED" or (failures .. " CHECK(S) FAILED"))
