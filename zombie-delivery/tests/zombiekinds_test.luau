-- 6.24, the special zombies (the owner: "new zombies, so the fighting isn't always the same"): shared/ZombieKinds.luau,
-- Config.Zombies' runner / brute / bloater and Config.ZombieTypes in the standalone Luau CLI: the spawn weights (the
-- night, the danger, the level, the Blood Moon, the caps), the brute's armour maths, the bloater's blast falloff and
-- fuse, the moves, and the parts budget of every look of every kind. (10.6: the city's fixed missions and their
-- plans went with shared/MissionPlan.luau.)
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local DangerRules = require("./DangerRules") -- (its pickKind: server/Zombies.luau's pick of a kind by the weights)
local ZombieKinds = require("./ZombieKinds")
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

local Z = Config.Zombies
local T = Config.ZombieTypes
local runner, brute, bloater, walker = Z.runner, Z.brute, Z.bloater, Z.walker

-- ── The kinds' numbers ────────────────────────────────────────────────────
do
	check("three special kinds next to the walker", runner ~= nil and brute ~= nil and bloater ~= nil and walker ~= nil)
	check("none of them is one of the people (they roam, bite, never shoot)", not runner.jobOnly and not brute.jobOnly and not bloater.jobOnly and not runner.ranged and not brute.ranged and not bloater.ranged)
	check("the runner: faster than a walker, less health, about a sprint's pace", runner.speed > walker.speed * 1.8 and runner.health < walker.health and runner.speed <= 28)
	check("the brute: big, slow, lots of health", brute.scale > 1.5 and brute.speed < walker.speed and brute.health >= walker.health * 5)
	check("the bloater: slow, never bites", bloater.speed < walker.speed and bloater.damage == 0)
	check("the new kinds pay a bit more than a walker", runner.reward > walker.reward and brute.reward > runner.reward and bloater.reward > runner.reward and (bloater.xp or 0) > 0 and (brute.xp or 0) > (bloater.xp or 0))
	local lunge = runner.lunge
	check("the runner leaps (a range, a rest, a strike)", lunge ~= nil and lunge.range[1] > Config.Horde.BiteReach and lunge.range[1] < lunge.range[2] and lunge.range[2] <= 20 and lunge.every >= 2 and lunge.damage > 0 and lunge.damage <= 15 and lunge.time > 0.2 and lunge.time < 1.5)
	check("… a short push, faster than its run, a low hop", lunge ~= nil and lunge.push > 0 and lunge.push < lunge.time and lunge.speed > runner.speed and lunge.up > 0 and lunge.up * lunge.push < 4)
	check("… far enough to cover the gap in its time", lunge ~= nil and lunge.speed * lunge.push + runner.speed * (lunge.time - lunge.push) >= lunge.range[2])
	local armour = brute.armour
	check("the brute's plates: shares in (0, 1], a floor", armour ~= nil and armour.front > 0 and armour.front < 1 and armour.small > 0 and armour.small < 1 and armour.least > 0 and armour.least <= armour.front and armour.angle > 30 and armour.angle < 90)
	check("the brute never hangs on a car, hits it hard and throws you back", brute.noLatch == true and (brute.carDamage or 0) > brute.damage and (brute.carBump or 1) < 1 and brute.shove ~= nil and brute.shove.speed > 20)
	local blast = bloater.blast
	check("the bloater's blast: a radius, a full core, an edge", blast ~= nil and blast.radius > blast.inner and blast.inner > 0 and blast.edge > 0 and blast.edge < 1 and blast.radius <= 24)
	check("… a short warning: the death fuse quicker than the walk-up", blast ~= nil and blast.deathFuse > 0.2 and blast.deathFuse < blast.fuse and blast.fuse <= 2.5)
	check("… it starts its fuse close (shoot it from range: out of its radius)", blast ~= nil and blast.trigger < blast.radius and blast.trigger >= Config.Horde.BiteReach)
	check("… never kills a healthy courier on its own (100 health)", blast ~= nil and blast.player < 100 and blast.player >= 20)
	check("… sets another bloater off at its core (a chain)", blast ~= nil and blast.zombie >= bloater.health)
	check("… a walker at its edge may live", blast ~= nil and blast.zombie * blast.edge < walker.health)
	check("the bloater never hangs on a car", bloater.noLatch == true)
	check("every kind's glow and voice", Config.ZombieLife.Glow.bloater ~= nil and Config.ZombieLife.Pitch.bloater ~= nil and Config.ZombieLife.Pitch.bloater < Config.ZombieLife.Pitch.walker)
end

-- ── The spawn weights ─────────────────────────────────────────────────────
do
	local base = Config.Horde.Roam.kinds
	local day = { night = 0, danger = 0, level = 10, bloodMoon = false }
	local night = { night = 1, danger = 0, level = 10, bloodMoon = false }
	local share = function(context: ZombieKinds.Context, kind: string, table_: { [string]: number }?): number
		return ZombieKinds.shares(ZombieKinds.weights(table_ or base, context))[kind] or 0
	end
	local before = table.clone(base)
	local w = ZombieKinds.weights(base, night)
	local same = true
	for kind, weight in before do
		same = same and base[kind] == weight
	end
	check("weights: the base table is never changed", same)
	local known = true
	for kind, weight in w do
		known = known and before[kind] ~= nil and weight >= 0
	end
	check("weights: only the table's kinds, never negative", known)
	check("weights: by day the table as it is", math.abs(share(day, "walker") - ZombieKinds.shares(base).walker) < 1e-9)
	check("weights: more runners at night", share(night, "runner") > share(day, "runner") * 1.4, `{share(day, "runner")} → {share(night, "runner")}`)
	check("weights: more bloaters at night", share(night, "bloater") > share(day, "bloater"))
	check("weights: fewer walkers at night", share(night, "walker") < share(day, "walker"))
	local far = { night = 0, danger = 1, level = 10, bloodMoon = false }
	check("weights: more brutes and bloaters in danger", share(far, "brute") > share(day, "brute") * 1.5 and share(far, "bloater") > share(day, "bloater") * 1.5)
	local young = { night = 1, danger = 1, level = 1, bloodMoon = true }
	check("weights: a level 1 courier never meets a bloater", share(young, "bloater") == 0)
	check("weights: … and fewer brutes", share({ night = 0, danger = 0, level = 1, bloodMoon = false }, "brute") < share(day, "brute"))
	check("weights: from FromLevel on, the bloater comes", share({ night = 0, danger = 0, level = T.FromLevel.bloater, bloodMoon = false }, "bloater") > 0)
	check("weights: no player (nil level): no level rule", share({ night = 0, danger = 0, level = nil, bloodMoon = false }, "bloater") > 0)
	local moon = { night = 1, danger = 0, level = 10, bloodMoon = true }
	check("weights: a Blood Moon has more runners and bloaters than a night", share(moon, "runner") > share(night, "runner") and share(moon, "bloater") > share(night, "bloater"))
	check("weights: the people are never weighed (a stop's bandits stay)", ZombieKinds.factor("bandit", moon) == 1 and ZombieKinds.factor("gunner", far) == 1)
	-- the danger: a tier, or the distance from the depot
	check("danger: none at the depot, by day, without a job", ZombieKinds.danger(nil, 0) == 0 and ZombieKinds.danger(nil, nil) == 0)
	check("danger: a ★ job none, ★★★★ full", ZombieKinds.danger(1, nil) == 0 and ZombieKinds.danger(4, nil) == 1)
	check("danger: grows with the distance, full far out", ZombieKinds.danger(nil, T.DangerNear) == 0 and ZombieKinds.danger(nil, (T.DangerNear + T.DangerFar) / 2) > 0.4 and ZombieKinds.danger(nil, T.DangerFar * 2) == 1)
	check("danger: the bigger of the two", ZombieKinds.danger(2, T.DangerFar) == 1 and ZombieKinds.danger(4, 0) == 1)
	-- every table the game picks from: the specials stay a minority; a tier's waves get more of them as it gets harder
	local tables: { [string]: { [string]: number } } = {
		roam = Config.Horde.Roam.kinds,
		residents = Config.Horde.Residents.kinds,
		supply = Config.LiveEvents.Supply.Kinds,
		horde = Config.LiveEvents.Horde.Kinds,
	}
	for n, tier in Config.Jobs.Tiers do
		tables[`waves{n}`] = tier.waveKinds
		tables[`stops{n}`] = tier.kinds
	end
	local worst = { night = 1, danger = 1, level = 15, bloodMoon = true }
	local minority, kindsOk = {}, {}
	for name, kinds in tables do
		local shares = ZombieKinds.shares(ZombieKinds.weights(kinds, worst))
		if (shares.bloater or 0) > 0.25 or (shares.brute or 0) > 0.35 then
			table.insert(minority, `{name} bloater {shares.bloater} brute {shares.brute}`)
		end
		for kind in kinds do
			if not Z[kind] then
				table.insert(kindsOk, `{name} {kind}`)
			end
		end
	end
	check("weights: even a Blood Moon night far out keeps the bloaters and brutes a minority", #minority == 0, table.concat(minority, "; "))
	check("weights: every table names known kinds", #kindsOk == 0, table.concat(kindsOk, ", "))
	local function bloaterShare(n: number): number
		return ZombieKinds.shares(Config.Jobs.Tiers[n].waveKinds).bloater or 0
	end
	check("tiers: no bloater in a ★ job's waves, more from ★★ to ★★★★", bloaterShare(1) == 0 and bloaterShare(2) > 0 and bloaterShare(3) > bloaterShare(2) and bloaterShare(4) > bloaterShare(3))
	-- the pick: the same roll, the same kind (DangerRules.pickKind sorts the names); the shares come out over many rolls
	local weights = ZombieKinds.weights(base, moon)
	local counts: { [string]: number } = {}
	local rolls = 20000
	for i = 0, rolls - 1 do
		local kind = DangerRules.pickKind(weights, (i + 0.5) / rolls)
		counts[kind] = (counts[kind] or 0) + 1
	end
	local shares = ZombieKinds.shares(weights)
	local off = {}
	for kind, s in shares do
		if math.abs((counts[kind] or 0) / rolls - s) > 0.002 then
			table.insert(off, `{kind} {(counts[kind] or 0) / rolls} / {s}`)
		end
	end
	check("pick: an even spread of rolls comes out in the weights' shares", #off == 0, table.concat(off, ", "))
	check("pick: the same roll, the same kind", DangerRules.pickKind(weights, 0.37) == DangerRules.pickKind(table.clone(weights), 0.37))
	-- the caps
	check("caps: the brute and the bloater have one, the walker none", T.MaxAlive.brute ~= nil and T.MaxAlive.bloater ~= nil and T.MaxAlive.walker == nil)
	check("caps: at its cap a kind is capped, below it not", ZombieKinds.capped("bloater", T.MaxAlive.bloater) and not ZombieKinds.capped("bloater", T.MaxAlive.bloater - 1) and not ZombieKinds.capped("walker", 1000))
	check("caps: well within the server's zombies", T.MaxAlive.brute + T.MaxAlive.bloater <= Config.Horde.MaxTotal / 4)
end

-- ── The brute's armour ────────────────────────────────────────────────────
do
	local armour = brute.armour :: Config.ArmourDef
	local function hit(damage: number, front: boolean, extra: { [string]: any }?): number
		local h: ZombieKinds.Hit = { crit = false, cause = nil, pellets = 1, damage = damage, front = front }
		for key, value in extra or {} do
			(h :: any)[key] = value
		end
		return ZombieKinds.armourShare(armour, h)
	end
	local pistol, rifle = 20, 60
	check("armour: a pistol at its chest barely scratches it", math.abs(hit(pistol, true) - math.max(armour.least, armour.front * armour.small)) < 1e-9, hit(pistol, true))
	check("armour: a rifle at its chest: the plate's share", math.abs(hit(rifle, true) - armour.front) < 1e-9)
	check("armour: a rifle in its back: all of it", hit(rifle, false) == 1)
	check("armour: a pistol in its back: the small gun's share", math.abs(hit(pistol, false) - armour.small) < 1e-9)
	check("armour: a headshot goes through", hit(pistol, true, { crit = true }) == 1)
	check("armour: a blast, a car, a fire go through", hit(90, true, { cause = "splash" }) == 1 and hit(90, true, { cause = "car" }) == 1)
	check("armour: a shotgun's pellets go through", hit(15, true, { pellets = 7 }) == 1 and hit(15, true, { pellets = armour.pellets }) == 1 and hit(15, true, { pellets = armour.pellets - 1 }) < 1)
	check("armour: a punch or a bat on its plates: the plate's share (not a gun's)", math.abs(hit(30, true, { cause = "melee" }) - armour.front) < 1e-9 and hit(30, false, { cause = "melee" }) == 1)
	check("armour: never below its floor", hit(1, true) >= armour.least)
	-- the front: within `angle` of where it faces
	check("front: a round flying at its face", ZombieKinds.isFront(0, 1, 0, -1, armour.angle))
	check("front: a round in its back", not ZombieKinds.isFront(0, 1, 0, 1, armour.angle))
	check("front: from the side is not the front", not ZombieKinds.isFront(0, 1, 1, 0, armour.angle))
	local a = math.rad(armour.angle - 5)
	local b = math.rad(armour.angle + 5)
	check("front: just inside its angle, just outside", ZombieKinds.isFront(0, 1, math.sin(a), -math.cos(a), armour.angle) and not ZombieKinds.isFront(0, 1, math.sin(b), -math.cos(b), armour.angle))
	check("front: no way, no front", not ZombieKinds.isFront(0, 0, 0, -1, armour.angle) and not ZombieKinds.isFront(0, 1, 0, 0, armour.angle))
	-- what it takes: a pistol from the front is hopeless, its head or a shotgun is the way
	local health = brute.health
	local pistolFront = math.ceil(health / (pistol * hit(pistol, true)))
	local headshots = math.ceil(health / (pistol * Config.Horde.HeadshotMultiplier * 2))
	local shotgun = math.ceil(health / (15 * 7))
	check("armour: a pistol from the front takes many times more shots than headshots", pistolFront >= headshots * 8, `{pistolFront} / {headshots}`)
	check("armour: a shotgun from the front still drops it in a few", shotgun <= 6, shotgun)
	check("armour: a rifle in its back drops it in under 10", math.ceil(health / rifle) < 10)
end

-- ── The bloater's blast ───────────────────────────────────────────────────
do
	local blast = bloater.blast :: Config.BlastDef
	check("blast: full at its middle and its core", ZombieKinds.blastShare(blast, 0) == 1 and ZombieKinds.blastShare(blast, blast.inner) == 1)
	check("blast: its edge's share at its radius", math.abs(ZombieKinds.blastShare(blast, blast.radius) - blast.edge) < 1e-9)
	check("blast: nothing beyond it", ZombieKinds.blastShare(blast, blast.radius + 0.01) == 0 and ZombieKinds.blastShare(blast, 1e6) == 0)
	check("blast: nothing for a broken distance", ZombieKinds.blastShare(blast, 0 / 0) == 0)
	local falling, last = true, 2
	for d = 0, blast.radius, 0.25 do
		local s = ZombieKinds.blastShare(blast, d)
		falling = falling and s <= last + 1e-12 and s >= blast.edge - 1e-9
		last = s
	end
	check("blast: falls off with the distance, never under its edge inside", falling)
	local mid = (blast.inner + blast.radius) / 2
	check("blast: halfway out, halfway down (linear)", math.abs(ZombieKinds.blastShare(blast, mid) - (1 + blast.edge) / 2) < 1e-9)
	-- the fuse: a re-lit fuse never burns longer
	check("fuse: a new one goes off its seconds from now", ZombieKinds.fuseLeft(nil, 10, blast.fuse) == 10 + blast.fuse)
	check("fuse: killed while it burns: the sooner one", ZombieKinds.fuseLeft(10 + blast.fuse, 10.2, blast.deathFuse) == 10.2 + blast.deathFuse)
	check("fuse: never later than one burning", ZombieKinds.fuseLeft(10.5, 10.2, blast.fuse) == 10.5)
	check("fuse: never in the past", ZombieKinds.fuseLeft(nil, 5, -3) == 5)
	-- shot from range is safe: the farthest a gun reaches is far outside the blast
	check("blast: shooting it from range is safe (a pistol's range is several radii)", Config.Weapons[1].range >= blast.radius * 3, Config.Weapons[1].range)
end

-- ── The moves ─────────────────────────────────────────────────────────────
do
	check("gaits: the runner lurches, the brute stomps, the bloater waddles", ZombieStyle.gait("runner", 3).style == "lurch" and ZombieStyle.gait("brute", 3).style == "stomp" and ZombieStyle.gait("bloater", 3).style == "waddle" and ZombieStyle.gait("walker", 3).style == "shamble" and ZombieStyle.gait("bandit", 3).style == "person")
	local L = Config.ZombieLife
	local function motion(speed: number, legs: number): ZombieStyle.Motion
		return { speed = speed, legs = legs, t = 1.3, attack = -1, attackSide = 1, hit = -1, hitCode = 0, hitSide = 1, latched = false, lunge = -1, fuse = -1 }
	end
	local function finite(p: ZombieStyle.Pose): boolean
		for _, v in p :: any do
			if v ~= v or math.abs(v) > 10 then
				return false
			end
		end
		return true
	end
	-- the runner's sprint: the arms pump with the legs, opposite each other
	local gait = ZombieStyle.gait("runner", 7)
	local sprint = ZombieStyle.pose(ZombieStyle.newPose(), gait, motion(27, 1))
	local jog = ZombieStyle.pose(ZombieStyle.newPose(), gait, motion(8, 1))
	check("runner: at a sprint the arms pump opposite each other", sprint.leftArm < -math.rad(L.Pump) * 0.5 and sprint.rightArm > math.rad(L.Pump) * 0.5, `{sprint.leftArm} {sprint.rightArm}`)
	check("runner: at a sprint it leans further than at a jog", sprint.waistPitch < jog.waistPitch)
	-- its leap: a dive at you
	local m = motion(27, 0)
	m.lunge = L.Dive.Time * 0.4
	local dive = ZombieStyle.pose(ZombieStyle.newPose(), gait, m)
	check("runner: its leap is a dive (the body down, the arms out in front)", dive.waistPitch < -math.rad(L.Dive.Lean) * 0.9 and dive.leftArm > math.rad(L.Dive.Arms) * 0.9 and dive.rightArm > math.rad(L.Dive.Arms) * 0.9 and finite(dive))
	m.lunge = L.Dive.Time + 0.01
	local after = ZombieStyle.pose(ZombieStyle.newPose(), gait, m)
	m.lunge = -1
	local plainRun = ZombieStyle.pose(ZombieStyle.newPose(), gait, m)
	check("runner: after the leap, its run again", math.abs(after.waistPitch - plainRun.waistPitch) < 1e-9)
	-- the brute: down and forward as a foot lands
	local stomp = ZombieStyle.gait("brute", 7)
	local landing = ZombieStyle.pose(ZombieStyle.newPose(), stomp, motion(10, 1))
	local passing = ZombieStyle.pose(ZombieStyle.newPose(), stomp, motion(10, 0))
	check("brute: dips and pitches forward as a foot lands", landing.rootY < passing.rootY and landing.waistPitch < passing.waistPitch)
	-- the bloater: rolled onto the leg, leaning back, the arms out; the fuse arches it back and flings the arms out
	local waddle = ZombieStyle.gait("bloater", 7)
	local left = ZombieStyle.pose(ZombieStyle.newPose(), waddle, motion(8, 1))
	local right = ZombieStyle.pose(ZombieStyle.newPose(), waddle, motion(8, -1))
	check("bloater: rolled from foot to foot", left.waistRoll > 0 and right.waistRoll < 0)
	check("bloater: its arms held out from its belly", left.leftArmRoll < 0 and left.rightArmRoll > 0)
	local fm = motion(0, 0)
	fm.fuse = 0.9
	local fusing = ZombieStyle.pose(ZombieStyle.newPose(), waddle, fm)
	check("bloater: its fuse arches it back, the arms flung out", fusing.waistPitch > math.rad(L.Swell.Arch) * 0.5 and fusing.leftArmRoll < -math.rad(L.Swell.Arms) * 0.8 and fusing.rightArmRoll > math.rad(L.Swell.Arms) * 0.8 and finite(fusing))
	local still = ZombieStyle.pose(ZombieStyle.newPose(), waddle, motion(0, 0))
	check("bloater: without a fuse no arch", still.waistPitch < fusing.waistPitch)
	-- the people keep their own (no dive, no fuse)
	local person = ZombieStyle.gait("bandit", 7)
	local pm = motion(0, 0)
	pm.lunge, pm.fuse = 0.2, 0.5
	local p = ZombieStyle.pose(ZombieStyle.newPose(), person, pm)
	check("the people never dive nor swell", p.waistPitch == 0 and p.leftArm == 0)
	-- an old Motion without the 6.24 fields still works
	local old = { speed = 5, legs = 0.3, t = 2, attack = -1, attackSide = 1, hit = -1, hitCode = 0, hitSide = 1, latched = false } :: any
	check("an old motion (no lunge, no fuse) still poses", finite(ZombieStyle.pose(ZombieStyle.newPose(), waddle, old)))
end

-- ── The looks and the parts budget ────────────────────────────────────────
do
	local over, unknown, names = {}, {}, {}
	local most: { [string]: number } = {}
	for kind, budget in T.Parts do
		local def = Z[kind]
		if not def or not table.find(Geometry.ids, kind) then
			table.insert(unknown, kind)
			continue
		end
		check(`parts: {kind}'s budget within Roblox-friendly 64`, budget <= 64 and budget >= 30, budget)
		for variant = 1, ZombieStyle.count(kind) do
			local look = ZombieStyle.variant(kind, variant)
			local spec = Geometry.spec(kind, def.scale, look.skin, look.shirt, look.pants, look.outfit)
			local parts = #spec.bones + #spec.pieces
			most[kind] = math.max(most[kind] or 0, parts)
			if parts > budget or parts > spec.budget then
				table.insert(over, `{kind} look {variant}: {parts}/{budget}`)
			end
			local seen = {}
			for _, list in { spec.bones, spec.pieces } do
				for _, piece in list do
					if seen[piece.name] then
						table.insert(names, `{kind} {variant} {piece.name}`)
					end
					seen[piece.name] = true
				end
			end
		end
	end
	check("parts: every infected kind has a budget", #unknown == 0 and T.Parts.walker ~= nil and T.Parts.runner ~= nil and T.Parts.brute ~= nil and T.Parts.bloater ~= nil and T.Parts.soldier ~= nil, table.concat(unknown, ", "))
	check("parts: every look of every kind within its budget", #over == 0, table.concat(over, ", "))
	check("parts: unique part names in every look", #names == 0, table.concat(names, ", "))
	-- the whole server at the worst mix: the capped kinds at their caps, the rest at the biggest other budget
	local capped, biggest = 0, 0
	local worst = 0
	for kind, budget in T.Parts do
		local cap = T.MaxAlive[kind]
		if cap then
			capped += cap
			worst += cap * budget
		else
			biggest = math.max(biggest, budget)
		end
	end
	worst += (Config.Horde.MaxTotal - capped) * biggest
	check("parts: a full server's zombies within Config.ZombieTypes.Server", worst <= T.Server, `{worst} / {T.Server}`)
	print(`      (the biggest looks: walker {most.walker}, runner {most.runner}, brute {most.brute}, bloater {most.bloater}, soldier {most.soldier}; a full server at worst {worst})`)
	-- each kind looks its own
	local function spec(kind: string): Geometry.Spec
		local def = Z[kind]
		return Geometry.spec(kind, def.scale, def.skin, def.shirt, def.pants)
	end
	local function bone(s: Geometry.Spec, name: string): Geometry.Bone
		for _, b in s.bones do
			if b.name == name then
				return b
			end
		end
		error(name)
	end
	local function piece(s: Geometry.Spec, name: string): Geometry.Piece?
		for _, p in s.pieces do
			if p.name == name then
				return p
			end
		end
		return nil
	end
	local w, r, br, bl = spec("walker"), spec("runner"), spec("brute"), spec("bloater")
	local function slim(s: Geometry.Spec): number
		local torso = bone(s, "UpperTorso")
		return torso.size[1] / torso.size[2]
	end
	check("looks: the runner is thinner than a walker", slim(r) < slim(w) * 0.85, `{slim(r)} / {slim(w)}`)
	check("looks: the bloater is wider than a walker", slim(bl) > slim(w) * 1.25)
	check("looks: the runner shows its ribs", piece(r, "Rib1") ~= nil and piece(r, "RibTear") ~= nil)
	local plates, back = 0, true
	for _, p in br.pieces do
		if p.material == "Metal" then
			plates += 1
			if p.attach == "UpperTorso" and p.at[3] > 0 then
				back = false
			end
		end
	end
	check("looks: the brute wears steel plates (its chest, its shoulders, arms and shins)", plates >= 8 and piece(br, "ChestPlate") ~= nil and piece(br, "BellyPlate") ~= nil and piece(br, "ShoulderPlateR") ~= nil and piece(br, "BracerL") ~= nil and piece(br, "GreaveR") ~= nil, plates)
	check("looks: … none on its back (straps only: its open side)", back and piece(br, "StrapL") ~= nil and (piece(br, "StrapL") :: Geometry.Piece).at[3] > 0)
	local belly = piece(bl, "Belly")
	local boils = 0
	for _, p in bl.pieces do
		if string.sub(p.name, 1, 4) == "Boil" or p.name == "NeckBoil" then
			boils += if p.material == "Neon" then 1 else 0
		end
	end
	check("looks: the bloater's swollen belly and hump", belly ~= nil and belly.shape == "Ellipsoid" and belly.at[3] < 0 and piece(bl, "Hump") ~= nil)
	check("looks: … with glowing boils (client/ZombieFx.luau pulses them)", boils >= 5, boils)
	for variant = 1, ZombieStyle.count("bloater") do
		local look = ZombieStyle.variant("bloater", variant)
		local s = Geometry.spec("bloater", bloater.scale, look.skin, look.shirt, look.pants, look.outfit)
		check(`looks: bloater look {variant} keeps its belly and boils`, piece(s, "Belly") ~= nil and piece(s, "Boil1") ~= nil and piece(s, "Hump") ~= nil)
	end
	check("looks: the bloater has several looks", ZombieStyle.count("bloater") >= 4)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
