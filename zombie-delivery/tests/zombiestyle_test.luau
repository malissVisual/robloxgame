-- 6.16: zombies with a life of their own (shared/ZombieStyle.luau, Config.ZombieLife) in the standalone Luau CLI: the
-- looks (several per kind, picked from the id the same everywhere, the classic first, every one built by the real
-- character geometry within the part budget, each kind keeping its build), the gait (a limp on one leg only, the
-- runner's lean, the brute's stomp), the attack's and the flinch's curves, the Hit attribute, the falls.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local ZombieStyle = require("./ZombieStyle")
local Geometry = require("./CharacterGeometry")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local L = Config.ZombieLife
local function isColor(c: any): boolean
	return type(c) == "table" and #c == 3 and c[1] >= 0 and c[1] <= 255 and c[2] >= 0 and c[2] <= 255 and c[3] >= 0 and c[3] <= 255
end

-- The numbers.
check("posed within a street's range, the near ones every frame", L.Range >= 80 and L.Range <= 250 and L.Near > 0 and L.Near < L.Range and L.FarEvery >= 2 and L.FarEvery <= 6)
check("a few dozen posed at most, picked a few times a second", L.MaxPosed >= 8 and L.MaxPosed <= 40 and L.Retarget >= 0.1 and L.Retarget <= 0.5)
check("a phone still poses a few", math.floor(L.MaxPosed * Config.Performance.Lite.Count + 0.5) >= 6)
check("the attack and the flinch are quick", L.AttackTime > 0.2 and L.AttackTime < 1 and L.FlinchTime > 0.1 and L.FlinchTime < L.HardTime and L.HardTime < 1.2)
check("a hit is shown a few times a second at most", L.HitEvery >= 0.05 and L.HitEvery <= 0.3)
check("the eyes: a day colour and a glow per zombie kind", isColor(L.EyeDay) and isColor(L.GlowDefault) and isColor(L.Glow.walker) and isColor(L.Glow.runner) and isColor(L.Glow.brute) and isColor(L.Glow.soldier))
check("the glow is brighter than the day's eyes", L.Glow.walker[1] + L.Glow.walker[2] + L.Glow.walker[3] > L.EyeDay[1] + L.EyeDay[2] + L.EyeDay[3])
check("a few voices at once, each with a pause", L.Groan.Voices >= 1 and L.Groan.Voices <= 5 and L.Groan.Min >= 2 and L.Groan.Max > L.Groan.Min and L.Groan.Gap > 0)
check("the voices are heard near only", L.Groan.Range <= 80 and L.Scream.Range <= 120 and L.Grunt.Range <= 100 and L.Gurgle.Range <= 100 and L.Stomp.Range <= 80)
check("a brute's voice is lower than a walker's, a runner's higher", L.Pitch.brute < L.Pitch.walker and L.Pitch.walker < L.Pitch.runner)
check("the falls' speeds", L.Death.Fall > 0 and L.Death.Fall < 6 and L.Death.Spin > 0 and L.Death.Back > 0 and L.Death.Slump > 0)

-- The looks.
local ZOMBIES = { "walker", "runner", "brute", "soldier" }
for _, kind in ZOMBIES do
	check(kind .. ": several looks", ZombieStyle.count(kind) >= 4, ZombieStyle.count(kind))
end
check("the people (bandits, gunners) keep their one look", ZombieStyle.count("bandit") == 1 and ZombieStyle.count("gunner") == 1)
check("an unknown kind has the classic only", ZombieStyle.count("nobody") == 1)

for kind, def in Config.Zombies do
	local classic = ZombieStyle.variant(kind, 1)
	check(kind .. ": look 1 is the classic (Config.Zombies' colours, no outfit)", classic.outfit == nil and classic.skin == def.skin and classic.shirt == def.shirt and classic.pants == def.pants)
end

local wears: { [string]: boolean } = {}
for _, w in ZombieStyle.Wears do
	wears[w] = true
end
local bares: { [string]: boolean } = {}
for _, b in ZombieStyle.Bare do
	bares[b] = true
end
local outfitsSeen: { [string]: boolean } = {}
local hats: { [string]: boolean } = {}
for _, kind in ZOMBIES do
	local def = Config.Zombies[kind]
	local skins: { [string]: boolean } = {}
	local classicSpec = Geometry.spec(kind, def.scale, def.skin, def.shirt, def.pants)
	for variant = 1, ZombieStyle.count(kind) do
		local look = ZombieStyle.variant(kind, variant)
		local name = kind .. " look " .. variant
		check(name .. ": its number", look.variant == variant and look.count == ZombieStyle.count(kind))
		check(name .. ": colours", isColor(look.skin) and isColor(look.shirt) and isColor(look.pants))
		skins[table.concat(look.skin, ",")] = true
		local outfit = look.outfit
		if outfit then
			outfitsSeen[outfit.wear] = true
			check(name .. ": a known outfit", wears[outfit.wear] == true and bares[outfit.bare] == true, outfit.wear .. " / " .. outfit.bare)
			check(name .. ": 0 … 2 stains", outfit.stains >= 0 and outfit.stains <= 2)
			check(name .. ": legs bare or not", outfit.legs == nil or outfit.legs == "bare")
			check(name .. ": a cap, a hard hat or nothing", outfit.hat == nil or ((outfit.hat == "cap" or outfit.hat == "hard") and isColor(outfit.hatColor)))
			check(name .. ": its second colour", outfit.trim == nil or isColor(outfit.trim))
			if outfit.hat then
				hats[outfit.hat] = true
			end
		end
		-- Built by the real geometry: within the budget, unique names, the kind's build (sizes) unchanged.
		local ok, spec = pcall(Geometry.spec, kind, def.scale, look.skin, look.shirt, look.pants, outfit)
		check(name .. ": the geometry builds it", ok, spec)
		if ok then
			check(name .. ": within the part budget", #spec.bones + #spec.pieces <= spec.budget, #spec.bones + #spec.pieces)
			local names: { [string]: boolean } = {}
			local unique = true
			for _, list in { spec.bones, spec.pieces } :: { { any } } do
				for _, p in list do
					if names[p.name] then
						unique = false
					end
					names[p.name] = true
				end
			end
			check(name .. ": every part its own name", unique)
			local same = true
			for i, b in spec.bones do
				local c = classicSpec.bones[i]
				if b.name ~= c.name or b.size[1] ~= c.size[1] or b.size[2] ~= c.size[2] or b.size[3] ~= c.size[3] then
					same = false
				end
			end
			check(name .. ": the kind's body (the same bones and sizes)", same and spec.hipHeight == classicSpec.hipHeight)
			check(name .. ": the glowing eyes are there (EyeL, EyeR in Neon)", names.EyeL == true and names.EyeR == true)
		end
	end
	local n = 0
	for _ in skins do
		n += 1
	end
	check(kind .. ": several skin tones", n >= 3, n)
end
for _, want in { "gown", "suit", "hivis", "tee", "tracksuit", "hoodie", "apron", "jumpsuit" } do
	check("someone wears a " .. want, outfitsSeen[want] == true)
end
check("caps and hard hats", hats.cap == true and hats.hard == true)
check("the 6.0 look is unchanged without an outfit", #Geometry.spec("walker", 1).pieces == #Geometry.spec("walker", 1, nil, nil, nil, nil).pieces)
do
	local walker = Geometry.spec("walker", Config.Zombies.walker.scale)
	local brute = Geometry.spec("brute", Config.Zombies.brute.scale)
	local runner = Geometry.spec("runner", Config.Zombies.runner.scale)
	check("the brute stays big", brute.bones[3].size[1] > walker.bones[3].size[1] * 1.5 and brute.hipHeight > walker.hipHeight * 1.5)
	check("the runner stays lean (no wider than a walker)", runner.bones[3].size[1] <= walker.bones[3].size[1])
end

-- Picked from the seed: the same every time, every look in use, none much rarer than the rest.
for _, kind in ZOMBIES do
	local count = ZombieStyle.count(kind)
	local hits: { number } = table.create(count, 0)
	local stable = true
	for seed = 1, 600 do
		local look = ZombieStyle.look(kind, seed)
		hits[look.variant] += 1
		if ZombieStyle.look(kind, seed).variant ~= look.variant then
			stable = false
		end
	end
	local least = math.huge
	for _, n in hits do
		least = math.min(least, n)
	end
	check(kind .. ": the same seed, the same look", stable)
	check(kind .. ": every look in use, none rare", least >= 600 / count / 3, least)
end
check("a huge id still picks a look", ZombieStyle.look("walker", 987654321).variant >= 1)
check("neighbouring ids look different", ZombieStyle.look("walker", 1).variant ~= ZombieStyle.look("walker", 2).variant or ZombieStyle.look("walker", 2).variant ~= ZombieStyle.look("walker", 3).variant)

-- The gait.
check("walkers and soldiers shamble, runners lurch, brutes stomp, the people do not", ZombieStyle.gait("walker", 1).style == "shamble" and ZombieStyle.gait("soldier", 1).style == "shamble" and ZombieStyle.gait("runner", 1).style == "lurch" and ZombieStyle.gait("brute", 1).style == "stomp" and ZombieStyle.gait("bandit", 1).style == "person" and ZombieStyle.gait("gunner", 1).style == "person")
local lefts, rights = 0, 0
local inRange = true
for seed = 1, 200 do
	local g = ZombieStyle.gait("walker", seed)
	if g.limp < 0 then
		lefts += 1
	else
		rights += 1
	end
	if math.abs(g.limp) < 0.4 or math.abs(g.limp) > 1 or math.abs(g.tilt) > 1 or g.hunch < 0.6 or g.hunch > 1 or g.rhythm < 0.85 or g.rhythm > 1.15 then
		inRange = false
	end
end
check("a limp on either leg", lefts > 50 and rights > 50, lefts .. " / " .. rights)
check("the gait's numbers in their ranges", inRange)
check("the same seed, the same gait", ZombieStyle.gait("runner", 77).limp == ZombieStyle.gait("runner", 77).limp)
check("a brute's voice low, a runner's high", ZombieStyle.gait("brute", 5).pitch < 0.8 and ZombieStyle.gait("runner", 5).pitch > 1)

-- The attack's and the flinch's curves.
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end
local w0, s0 = ZombieStyle.swing(0)
local w1, s1 = ZombieStyle.swing(0.25)
local w2, s2 = ZombieStyle.swing(0.5)
local w3, s3 = ZombieStyle.swing(1)
local wb, sb = ZombieStyle.swing(-0.1)
check("the attack starts at rest", near(w0, 0) and near(s0, 0) and near(wb, 0) and near(sb, 0))
check("the wind-up first", near(w1, 1) and near(s1, 0))
check("then the strike, the wind-up gone", near(s2, 1) and near(w2, 0))
check("and back at rest", near(w3, 0) and near(s3, 0))
local smoothSwing = true
for i = 0, 99 do
	local a1, b1 = ZombieStyle.swing(i / 100)
	local a2, b2 = ZombieStyle.swing((i + 1) / 100)
	if math.abs(a2 - a1) > 0.2 or math.abs(b2 - b1) > 0.2 then
		smoothSwing = false
	end
end
check("the attack has no jumps", smoothSwing)
check("the flinch: at once, then back", near(ZombieStyle.flinch(0), 0) and near(ZombieStyle.flinch(0.12), 1) and ZombieStyle.flinch(0.5) < ZombieStyle.flinch(0.2) and near(ZombieStyle.flinch(1), 0) and near(ZombieStyle.flinch(-1), 0))

-- The Hit attribute.
check("how a hit was: a body shot, a headshot, a punch, a ram or a blast", ZombieStyle.hitCode(nil, false) == 0 and ZombieStyle.hitCode("gun", true) == 1 and ZombieStyle.hitCode("melee", false) == 2 and ZombieStyle.hitCode("car", false) == 3 and ZombieStyle.hitCode("splash", false) == 3)
local round = true
for count = 1, 50 do
	for code = 0, 3 do
		if ZombieStyle.hitOf(ZombieStyle.hitMark(count, code)) ~= code then
			round = false
		end
	end
end
check("the mark gives back how", round)
check("every new hit is a new mark", ZombieStyle.hitMark(5, 0) ~= ZombieStyle.hitMark(6, 0))

-- The falls.
check("a car or a blast flings it (as before)", ZombieStyle.death(1, "car", false, true) == "flung" and ZombieStyle.death(1, "splash", false, true) == "flung")
check("thrown off a car in the depot: flung", ZombieStyle.death(1, nil, false, true) == "flung")
check("no cause, no push: it crumples", ZombieStyle.death(1, nil, false, false) == "crumple" and ZombieStyle.death(1, "other", false, false) == "crumple")
check("a headshot or a punch knocks it back", ZombieStyle.death(3, "gun", true, true) == "back" and ZombieStyle.death(3, "melee", false, true) == "back")
local deaths: { [string]: number } = {}
for seed = 1, 200 do
	local d = ZombieStyle.death(seed, "gun", false, true)
	deaths[d] = (deaths[d] or 0) + 1
end
check("a body shot: every fall in use", (deaths.forward or 0) > 20 and (deaths.spin or 0) > 20 and (deaths.crumple or 0) > 20 and (deaths.back or 0) > 20)

-- The pose.
local pose = ZombieStyle.newPose()
local function motion(speed: number, legs: number, attack: number?, hit: number?, code: number?): ZombieStyle.Motion
	return { speed = speed, legs = legs, t = 1.3, attack = attack or -1, attackSide = 1, hit = hit or -1, hitCode = code or 0, hitSide = 1, latched = false }
end
local walkerLeft = ZombieStyle.gait("walker", 1)
walkerLeft.limp = -0.8
local a = ZombieStyle.pose(ZombieStyle.newPose(), walkerLeft, motion(12, 1)).rootY
local b = ZombieStyle.pose(ZombieStyle.newPose(), walkerLeft, motion(12, -1)).rootY
check("the shamble dips onto the bad leg only (uneven)", a < -0.05 and near(b, 0), a .. " / " .. b)
local standing = ZombieStyle.pose(pose, walkerLeft, motion(0, 0))
check("standing: no dip", near(standing.rootY, 0))
check("standing: it sways and lolls a little", math.abs(standing.waistRoll) < math.rad(L.Sway + L.LimpRoll + 1) and math.abs(standing.neckRoll) < math.rad(L.HeadTilt + L.Loll * 1.4))
local runner = ZombieStyle.gait("runner", 4)
check("the runner leans into the run", ZombieStyle.pose(pose, runner, motion(27, 0)).waistPitch < -math.rad(L.RunLean * 0.9))
local brute = ZombieStyle.gait("brute", 4)
local stepDown = ZombieStyle.pose(ZombieStyle.newPose(), brute, motion(10, 1)).rootY
local stepOther = ZombieStyle.pose(ZombieStyle.newPose(), brute, motion(10, -1)).rootY
local mid = ZombieStyle.pose(ZombieStyle.newPose(), brute, motion(10, 0)).rootY
check("the brute stomps on every step", stepDown < -0.2 and near(stepDown, stepOther) and near(mid, 0))
local rest = ZombieStyle.pose(ZombieStyle.newPose(), walkerLeft, motion(0, 0))
local strike = ZombieStyle.pose(ZombieStyle.newPose(), walkerLeft, motion(0, 0, L.AttackTime * 0.5))
check("the attack lunges forward", strike.rootZ < -0.3 and strike.waistPitch < rest.waistPitch - math.rad(10) and strike.rightArm < rest.rightArm)
local hit = ZombieStyle.pose(ZombieStyle.newPose(), walkerLeft, motion(0, 0, nil, L.FlinchTime * 0.12, 0))
local hard = ZombieStyle.pose(ZombieStyle.newPose(), walkerLeft, motion(0, 0, nil, L.HardTime * 0.12, 1))
check("a hit jerks it back", hit.waistPitch > rest.waistPitch + math.rad(10) and hit.neckPitch > rest.neckPitch)
check("a headshot further, with a stagger", hard.waistPitch > hit.waistPitch and hard.neckPitch > hit.neckPitch and hard.rootZ > 0.3)
local person = ZombieStyle.gait("bandit", 2)
local still = ZombieStyle.pose(ZombieStyle.newPose(), person, motion(12, 1, 0.2))
check("the people: no shamble, no swipe", near(still.rootY, 0) and near(still.waistPitch, 0) and near(still.leftArm, 0) and near(still.rightArm, 0))
local flinched = ZombieStyle.pose(ZombieStyle.newPose(), person, motion(0, 0, nil, L.FlinchTime * 0.12, 0))
check("… but they flinch", flinched.waistPitch > math.rad(10) and near(flinched.leftArm, 0))
local latched = motion(0, 0)
latched.latched = true
local claw = ZombieStyle.pose(ZombieStyle.newPose(), walkerLeft, latched)
check("hanging on a car: clawing, no sway", math.abs(claw.leftArm) > 0 and near(claw.rootY, 0))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
