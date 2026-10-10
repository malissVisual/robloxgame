--!strict
-- 6.16, zombies with a life of their own (the owner: "upgrade the visuals and the feel"): the pure rules, shared by the
-- server (the bodies, the deaths: server/Zombies.luau) and every client (the poses: client/ZombieAnimator.luau; the
-- eyes and the voices: client/ZombieLife.luau). Pure (no Roblox at its top level; tests/zombiestyle_test.luau runs it in
-- the plain Luau CLI). Everything is picked from a zombie's seed (its id, the model's Seed attribute), so the server
-- and every client pick the same, and nothing random is sent.
--   * ZombieStyle.look(kind, seed): its look, one of the kind's LOOKS. The first is the kind's classic 6.0 look
--     (Config.Zombies' colours, no outfit: the body built exactly as before); the others a skin from pale green to
--     grey-blue to bruised, torn and stained clothes, a missing sleeve, an outfit (a hospital gown, a torn suit, a
--     hi-vis vest, a tracksuit, a hoodie, a butcher's apron, a prison jumpsuit …) and a cap or a hard hat
--     (server/CharacterArt/Geometry.luau builds it; native parts and colours only). Each kind keeps its build: the
--     brute big, the runner lean (the scale is Config.Zombies', the looks only paint and dress).
--   * ZombieStyle.gait(kind, seed): how it moves: its style ("shamble" walkers and soldiers, "lurch" runners, "stomp"
--     brutes, "person" the people), a limp on one leg, the head's tilt, a hunch, an arm hanging lower, its own rhythm
--     and its voice's pitch (Config.ZombieLife.Pitch).
--   * ZombieStyle.pose(into, gait, motion): the offsets laid over the stock animation this frame (radians, studs) from
--     its speed, the stock walk's thigh, the clock, the time since its attack and its hit, whether it hangs on a car.
--   * ZombieStyle.swing(u), ZombieStyle.flinch(u): the attack's (wind-up, strike) and the hit's curves, 0 … 1 over
--     u = the time since / its length.
--   * ZombieStyle.hitMark(count, code) / hitCode(cause, crit) / hitOf(mark): the Hit attribute (a count × 4 + how:
--     0 a body shot, 1 a headshot, 2 a punch or a strike, 3 a ram or a blast).
--   * ZombieStyle.death(seed, cause, headshot, pushed): which fall: "back" (knocked back: a headshot, a punch), "flung"
--     (a car or a blast, or thrown off a car: the 6.0 flying parts), "crumple" (no cause, no push), else one of
--     "forward", "spin", "crumple", "back".

local Config = require(script.Parent.Config)

local ZombieStyle = {}

local Tuning = Config.ZombieLife

export type Triple = { number }
-- What a look wears over the block body (server/CharacterArt/Geometry.luau Outfit: the same fields).
export type Outfit = {
	wear: string, -- "jacket" (the 6.0 torn jacket), "tee", "tank", "gown", "suit", "hivis", "tracksuit", "hoodie", "apron", "jumpsuit", "bare"
	bare: string, -- the arms without a sleeve: "none", "left", "right", "both"
	legs: string?, -- "bare": the legs and the feet in the skin's colour (under a gown)
	hat: string?, -- "cap" or "hard" (a hard hat)
	hatColor: Triple?,
	trim: Triple?, -- the outfit's second colour: the vest, the tie, the stripes, the apron, the print, the soldier's helmet
	stains: number, -- 0 … 2 blood stains
}
export type Look = { variant: number, count: number, skin: Triple, shirt: Triple, pants: Triple, outfit: Outfit? }

ZombieStyle.Wears = { "jacket", "tee", "tank", "gown", "suit", "hivis", "tracksuit", "hoodie", "apron", "jumpsuit", "bare" }
ZombieStyle.Bare = { "none", "left", "right", "both" }

-- Skins: from pale green to grey-blue to bruised.
local PALE = { 158, 178, 128 }
local SICKLY = { 120, 150, 100 }
local GREY_BLUE = { 122, 138, 152 }
local ASHEN = { 158, 158, 146 }
local BRUISED = { 128, 104, 122 }
local JAUNDICE = { 172, 166, 108 }
local ROT = { 96, 110, 80 }
local ORANGE = { 236, 124, 30 }
local HARD_HAT = { 232, 196, 40 }
local WHITE = { 235, 235, 228 }

type LookDef = { skin: Triple, shirt: Triple, pants: Triple, outfit: Outfit }
local function dress(skin: Triple, shirt: Triple, pants: Triple, outfit: Outfit): LookDef
	return { skin = skin, shirt = shirt, pants = pants, outfit = outfit }
end

-- Each kind's looks after its classic one (look 1). The people (bandits, gunners) have only the classic.
local LOOKS: { [string]: { LookDef } } = {
	walker = {
		dress(GREY_BLUE, { 150, 188, 180 }, GREY_BLUE, { wear = "gown", bare = "both", legs = "bare", trim = WHITE, stains = 2 }),
		dress(ASHEN, { 46, 48, 56 }, { 46, 48, 56 }, { wear = "suit", bare = "none", trim = { 128, 26, 32 }, stains = 1 }),
		dress(SICKLY, { 88, 92, 98 }, { 52, 70, 110 }, { wear = "hivis", bare = "none", trim = ORANGE, hat = "hard", hatColor = HARD_HAT, stains = 1 }),
		dress(PALE, { 70, 102, 142 }, { 58, 72, 104 }, { wear = "tee", bare = "both", trim = { 210, 200, 170 }, hat = "cap", hatColor = { 150, 40, 36 }, stains = 1 }),
		dress(BRUISED, { 112, 86, 60 }, { 62, 62, 66 }, { wear = "jacket", bare = "left", stains = 2 }),
		dress(JAUNDICE, { 176, 166, 146 }, { 84, 74, 58 }, { wear = "tee", bare = "right", stains = 2 }),
		dress(BRUISED, { 176, 190, 206 }, BRUISED, { wear = "gown", bare = "both", legs = "bare", trim = WHITE, stains = 1 }),
		dress(GREY_BLUE, { 74, 60, 50 }, { 74, 60, 50 }, { wear = "suit", bare = "none", trim = { 32, 44, 84 }, stains = 2 }),
		dress(ASHEN, { 60, 60, 66 }, { 40, 40, 44 }, { wear = "hivis", bare = "none", trim = { 214, 214, 48 }, hat = "cap", hatColor = { 40, 40, 44 }, stains = 0 }),
	},
	runner = {
		dress(GREY_BLUE, { 40, 72, 150 }, { 40, 72, 150 }, { wear = "tracksuit", bare = "none", trim = WHITE, stains = 1 }),
		dress(JAUNDICE, { 196, 196, 186 }, { 42, 42, 44 }, { wear = "tank", bare = "both", stains = 2 }),
		dress(PALE, { 92, 92, 98 }, { 50, 54, 70 }, { wear = "hoodie", bare = "none", trim = WHITE, stains = 1 }),
		dress(BRUISED, { 150, 32, 40 }, { 150, 32, 40 }, { wear = "tracksuit", bare = "none", trim = { 30, 30, 30 }, stains = 2 }),
		dress(ASHEN, { 44, 120, 92 }, { 58, 72, 104 }, { wear = "tee", bare = "left", trim = { 230, 200, 60 }, hat = "cap", hatColor = { 30, 30, 34 }, stains = 1 }),
	},
	brute = {
		dress(ROT, { 176, 170, 160 }, { 60, 56, 52 }, { wear = "apron", bare = "both", trim = { 206, 200, 190 }, stains = 2 }),
		dress(GREY_BLUE, { 214, 112, 38 }, { 214, 112, 38 }, { wear = "jumpsuit", bare = "both", trim = WHITE, stains = 1 }),
		dress(BRUISED, { 72, 72, 74 }, { 52, 70, 110 }, { wear = "hivis", bare = "none", trim = ORANGE, hat = "hard", hatColor = HARD_HAT, stains = 1 }),
		dress(ASHEN, ASHEN, { 64, 58, 50 }, { wear = "bare", bare = "both", stains = 2 }),
	},
	soldier = {
		dress(GREY_BLUE, { 150, 132, 92 }, { 140, 122, 86 }, { wear = "jacket", bare = "none", trim = { 150, 132, 92 }, stains = 1 }),
		dress(BRUISED, { 50, 62, 40 }, { 48, 58, 40 }, { wear = "jacket", bare = "right", trim = { 50, 62, 40 }, stains = 2 }),
		dress(JAUNDICE, { 92, 98, 102 }, { 80, 84, 88 }, { wear = "jacket", bare = "none", trim = { 70, 74, 78 }, stains = 1 }),
	},
}
ZombieStyle.Looks = LOOKS

-- A small integer hash of the seed (the same on the server and every client): 0 … 2^31 - 2.
local function mix(seed: number, salt: number): number
	local h = ((math.floor(math.abs(seed)) % 1000003) * 48271 + salt * 69621 + 12345) % 2147483647
	h = (h * 48271) % 2147483647
	h = (h * 48271) % 2147483647
	return h
end
ZombieStyle.mix = mix

-- A number from lo to hi picked by the seed.
local function between(seed: number, salt: number, lo: number, hi: number): number
	return lo + (hi - lo) * (mix(seed, salt) % 1001) / 1000
end

-- How many looks a kind has (1: the classic only).
function ZombieStyle.count(kind: string): number
	local list = LOOKS[kind]
	return 1 + (if list then #list else 0)
end

-- Look number `variant` of a kind (1: the classic, Config.Zombies' colours, no outfit).
function ZombieStyle.variant(kind: string, variant: number): Look
	local count = ZombieStyle.count(kind)
	local classic = Config.Zombies[kind] or Config.Zombies.walker
	local list = LOOKS[kind]
	if variant <= 1 or not list or variant > count then
		return { variant = 1, count = count, skin = classic.skin, shirt = classic.shirt, pants = classic.pants, outfit = nil }
	end
	local d = list[variant - 1]
	return { variant = variant, count = count, skin = d.skin, shirt = d.shirt, pants = d.pants, outfit = d.outfit }
end

-- The look of a kind's zombie with this seed.
function ZombieStyle.look(kind: string, seed: number): Look
	return ZombieStyle.variant(kind, mix(seed, 1) % ZombieStyle.count(kind) + 1)
end

-- ── How it moves ───────────────────────────────────────────────────────────

export type Gait = {
	style: string, -- "shamble", "lurch", "stomp", "person"
	limp: number, -- -1 … 1: the bad leg (- left, + right) and how bad
	tilt: number, -- -1 … 1: the head on one side
	hunch: number, -- 0.6 … 1
	drop: number, -- -1 the left arm hangs lower, 1 the right, 0 neither
	rhythm: number, -- × its sways' and lolls' speed
	phase: number, -- radians: where its sways start
	pitch: number, -- × its voice's pitch
}

function ZombieStyle.gait(kind: string, seed: number): Gait
	local def = Config.Zombies[kind]
	local style = if def and def.ranged then "person" elseif kind == "runner" then "lurch" elseif kind == "brute" then "stomp" else "shamble"
	local side = if mix(seed, 11) % 2 == 0 then -1 else 1
	local drops = { -1, 0, 0, 1 }
	return {
		style = style,
		limp = side * between(seed, 12, 0.4, 1),
		tilt = between(seed, 13, -1, 1),
		hunch = between(seed, 14, 0.6, 1),
		drop = drops[mix(seed, 15) % 4 + 1],
		rhythm = between(seed, 16, 0.85, 1.15),
		phase = between(seed, 17, 0, 2 * math.pi),
		pitch = (Tuning.Pitch[kind] or 1) * (1 + Tuning.Spread * between(seed, 18, -1, 1)),
	}
end

local function smooth(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The attack, u = the time since it / Config.ZombieLife.AttackTime: (the wind-up, the strike), each 0 … 1. The
-- wind-up rises first and is gone as the strike peaks; both 0 before 0 and from 1 on.
function ZombieStyle.swing(u: number): (number, number)
	if u < 0 or u >= 1 then
		return 0, 0
	end
	local wind = if u < 0.25 then smooth(u / 0.25) else 1 - smooth((u - 0.25) / 0.2)
	local strike = if u < 0.3 then 0 elseif u < 0.5 then smooth((u - 0.3) / 0.2) else 1 - smooth((u - 0.5) / 0.5)
	return wind, strike
end

-- The flinch, u = the time since the hit / its length: a jerk up to 1 at once, then easing back to 0.
function ZombieStyle.flinch(u: number): number
	if u < 0 or u >= 1 then
		return 0
	end
	if u < 0.12 then
		return smooth(u / 0.12)
	end
	local k = 1 - (u - 0.12) / 0.88
	return k * k
end

-- The Hit attribute: how (0 a body shot, 1 a headshot, 2 a punch or a strike, 3 a ram or a blast) in a count that
-- always changes (so every hit is a change the clients hear).
function ZombieStyle.hitCode(cause: string?, crit: boolean?): number
	if cause == "car" or cause == "splash" then
		return 3
	elseif cause == "melee" then
		return 2
	elseif crit then
		return 1
	end
	return 0
end
function ZombieStyle.hitMark(count: number, code: number): number
	return count * 4 + code
end
function ZombieStyle.hitOf(mark: number): number
	return math.floor(mark) % 4
end

-- Which fall (see the top).
ZombieStyle.Deaths = { "forward", "spin", "crumple", "back" }
function ZombieStyle.death(seed: number, cause: string?, headshot: boolean?, pushed: boolean?): string
	if cause == "car" or cause == "splash" then
		return "flung"
	elseif cause == nil or cause == "other" then
		return if pushed then "flung" else "crumple" -- (thrown off a car in the depot: flung)
	elseif headshot or cause == "melee" then
		return "back"
	end
	return ZombieStyle.Deaths[mix(seed, 21) % #ZombieStyle.Deaths + 1]
end

-- ── The pose ───────────────────────────────────────────────────────────────

-- The offsets over the animation (radians; studs for root*). Waist / neck pitch: + back, - forward; roll: + to the
-- body's left; an arm's pitch: + raised forward; its roll: + toward the body's left (the left arm in, the right out).
export type Pose = {
	rootY: number,
	rootZ: number, -- + back, - forward (the lunge)
	waistPitch: number,
	waistRoll: number,
	neckPitch: number,
	neckRoll: number,
	neckYaw: number,
	leftArm: number,
	leftArmRoll: number,
	rightArm: number,
	rightArmRoll: number,
}
-- What it does this frame: speed (studs / s, flat), legs (the stock walk's left thigh, -1 back … 1 forward,
-- ÷ Config.ZombieLife.HipSwing), t (the clock, s), attack / hit (s since, or -1), attackSide (-1 the left arm swipes, 1 the right),
-- hitCode (ZombieStyle.hitOf), hitSide (-1 / 1: which way it twists), latched (hangs on a car).
export type Motion = {
	speed: number,
	legs: number,
	t: number,
	attack: number,
	attackSide: number,
	hit: number,
	hitCode: number,
	hitSide: number,
	latched: boolean,
}

function ZombieStyle.newPose(): Pose
	return { rootY = 0, rootZ = 0, waistPitch = 0, waistRoll = 0, neckPitch = 0, neckRoll = 0, neckYaw = 0, leftArm = 0, leftArmRoll = 0, rightArm = 0, rightArmRoll = 0 }
end

local rad = math.rad

function ZombieStyle.pose(into: Pose, gait: Gait, m: Motion): Pose
	local T = Tuning
	local p = m.t * gait.rhythm + gait.phase
	local walk = math.clamp(m.speed / T.WalkRef, 0, 1)
	local still = 1 - math.clamp(m.speed / T.IdleBelow, 0, 1)
	local w = math.clamp(m.legs, -1, 1)
	local rootY, rootZ = 0, 0
	local waistPitch, waistRoll = 0, 0
	local neckPitch, neckRoll, neckYaw = 0, 0, 0
	local leftArm, leftArmRoll, rightArm, rightArmRoll = 0, 0, 0, 0
	local style = gait.style
	if style ~= "person" then
		if m.latched then
			-- Clawing at the car, biting.
			leftArm = rad(T.Claw) * math.sin(p * 18)
			rightArm = rad(T.Claw) * math.sin(p * 18 + 2)
			neckPitch = rad(T.Bite) * 0.6 * math.sin(p * 9)
		elseif style == "lurch" then
			-- The runner: leaning into it, thrown from side to side with the steps, the arms flailing, the head jerking.
			waistPitch = -rad(T.RunLean) * walk - rad(T.Hunch) * 0.4 * gait.hunch
			waistRoll = rad(T.RunRoll) * w * walk
			neckPitch = rad(T.RunLean) * 0.5 * walk + rad(4) * math.sin(p * 7)
			neckRoll = rad(T.HeadTilt) * 0.5 * gait.tilt
			leftArm = rad(T.Flail) * math.sin(p * 9) * walk
			rightArm = rad(T.Flail) * math.sin(p * 9 + 2.2) * walk
		elseif style == "stomp" then
			-- The brute: the body drops on every step and sways onto the leg, hunched, the arms held out.
			local a = math.abs(w)
			rootY = -T.StompDip * a * a * walk
			waistRoll = rad(T.StompRoll) * w * walk
			waistPitch = -rad(T.Hunch) * 0.8 * gait.hunch
			neckPitch = -rad(6)
			neckRoll = rad(T.HeadTilt) * 0.3 * gait.tilt
			leftArmRoll = -rad(T.StompArms)
			rightArmRoll = rad(T.StompArms)
		else
			-- The shamble: the body drops and rolls onto the bad leg as it lands (the uneven gait), a hunch, the head on
			-- one side and lolling, one arm hanging lower.
			local bad = if gait.limp < 0 then w else -w -- (legs is the left thigh: the right one swings opposite)
			local down = math.max(0, bad) * math.abs(gait.limp) * walk
			rootY = -T.Limp * down
			waistRoll = (if gait.limp < 0 then 1 else -1) * rad(T.LimpRoll) * down
			waistPitch = -rad(T.Hunch) * gait.hunch + rad(2) * math.sin(p * 2) * walk
			neckPitch = -rad(6) + rad(3) * math.sin(p * 1.7)
			neckRoll = rad(T.HeadTilt) * gait.tilt + rad(T.Loll) * 0.3 * math.sin(p * 0.9)
			if gait.drop < 0 then
				leftArm = -rad(T.ArmDrop)
			elseif gait.drop > 0 then
				rightArm = -rad(T.ArmDrop)
			end
			leftArm += rad(5) * math.sin(p * 2.1)
			rightArm += rad(5) * math.sin(p * 2.4 + 1)
		end
		-- Waiting: a slow sway, the head lolling.
		if still > 0 and not m.latched then
			local sway = math.sin(p * T.SwayHz * 2 * math.pi)
			waistRoll += rad(T.Sway) * sway * still
			waistPitch += rad(T.Sway) * 0.4 * math.sin(p * T.SwayHz * math.pi) * still
			neckRoll += rad(T.Loll) * math.sin(p * T.SwayHz * 1.3 * math.pi + 1) * still
			neckYaw += rad(T.Loll) * 0.6 * math.sin(p * T.SwayHz * 0.7 * math.pi) * still
		end
		-- The attack: back on the wind-up, a lunge and a swipe (the brute both arms overhead; the runner both forward).
		if m.attack >= 0 then
			local wind, strike = ZombieStyle.swing(m.attack / T.AttackTime)
			if wind > 0 or strike > 0 then
				waistPitch += rad(T.Wind) * wind - rad(T.Lunge) * strike
				rootZ -= T.LungeStuds * strike
				neckPitch -= rad(T.Bite) * strike
				local raise = rad(T.ArmRaise) * wind - rad(T.ArmStrike) * strike
				if style == "stomp" then
					leftArm += raise * 1.2
					rightArm += raise * 1.2
				elseif style == "lurch" then
					leftArm += raise * 0.5
					rightArm += raise * 0.5
					rootZ -= T.LungeStuds * 0.5 * strike
				elseif m.attackSide < 0 then
					leftArm += raise
					leftArmRoll -= rad(25) * strike -- (across the body)
				else
					rightArm += raise
					rightArmRoll += rad(25) * strike
				end
			end
		end
	end
	-- The flinch (the people too): the chest jerked back, the head snapped, the arms flung up; a hard hit staggers.
	if m.hit >= 0 then
		local hard = m.hitCode > 0
		local f = ZombieStyle.flinch(m.hit / (if hard then T.HardTime else T.FlinchTime))
		if f > 0 then
			waistPitch += rad(if hard then T.FlinchHard else T.Flinch) * f
			waistRoll += m.hitSide * rad(8) * f
			neckPitch += rad(if m.hitCode == 1 then T.HeadShotSnap else T.HeadSnap) * f
			neckRoll += m.hitSide * rad(10) * f
			if style ~= "person" then
				leftArm += rad(20) * f
				rightArm += rad(20) * f
			end
			if hard then
				rootZ += T.Stagger * f
				rootY -= 0.2 * f
			end
		end
	end
	into.rootY, into.rootZ = rootY, rootZ
	into.waistPitch, into.waistRoll = waistPitch, waistRoll
	into.neckPitch, into.neckRoll, into.neckYaw = neckPitch, neckRoll, neckYaw
	into.leftArm, into.leftArmRoll, into.rightArm, into.rightArmRoll = leftArm, leftArmRoll, rightArm, rightArmRoll
	return into
end

return ZombieStyle
