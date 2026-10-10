-- 6.16: the shots' show (shared/ShotFeel.luau, Config.Shots) in the standalone Luau CLI: every gun has a kick (a
-- shotgun or a rifle kicks harder than a pistol, a pistol harder than an SMG), the camera's spring peaks where it should
-- and settles back without overshooting at any frame rate, a casing falls, bounces lower and comes to rest, the
-- surfaces, the hit marker's looks, the token bucket and the round-robin pool.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local ShotFeel = require("./ShotFeel")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local S = Config.Shots

-- Every gun and car gun has its own kick, in sane numbers.
for _, list in { Config.Weapons :: { any }, Config.CarGuns :: { any } } do
	for _, def in list do
		local k = S.Guns[def.id]
		check(`{def.id} has a kick`, k ~= nil)
		if k then
			check(`{def.id}: the kick is sane`, k.pitch > 0 and k.pitch <= S.KickMax and k.yaw >= 0 and k.yaw < k.pitch + 1 and k.arm >= 0 and k.arm <= S.ArmMax, k.pitch)
			check(`{def.id}: its casing is known`, k.casing == nil or k.casing == "brass" or k.casing == "shell", k.casing)
		end
	end
end
check("an unknown gun kicks like Default", ShotFeel.kick("nothing") == S.Default and ShotFeel.kick(nil) == S.Default)
check("a shotgun and a rifle kick harder than a pistol", S.Guns.shotgun.pitch > S.Guns.pistol.pitch and S.Guns.rifle.pitch > S.Guns.pistol.pitch)
check("a pistol kicks harder than an SMG, an SMG than a minigun", S.Guns.pistol.pitch > S.Guns.smg.pitch and S.Guns.smg.pitch > S.Guns.minigun.pitch)
check("a shotgun throws shells, late (the pump)", S.Guns.shotgun.casing == "shell" and (S.Guns.shotgun.casingDelay or 0) > 0)
check("a revolver and a launcher throw no casing", S.Guns.revolver.casing == nil and S.Guns.launcher.casing == nil)
check("the roof guns do not kick the arms", S.Guns.roofmg.arm == 0 and S.Guns.roofminigun.arm == 0)
check("reduced motion keeps only a small share", S.ReducedMotion > 0 and S.ReducedMotion <= 0.35)

-- The spring: an impulse peaks at the asked height, 1 / rate seconds later, and settles back without going below 0.
local rate = S.KickRate
local function run(dt: number, seconds: number): (number, number, number, number)
	local x, v = 0, ShotFeel.impulse(2, rate)
	local peak, peakAt, lowest, t = 0, 0, 0, 0
	while t < seconds do
		x, v = ShotFeel.spring(x, v, rate, dt)
		t += dt
		if x > peak then
			peak, peakAt = x, t
		end
		lowest = math.min(lowest, x)
	end
	return peak, peakAt, lowest, x
end
local peak, peakAt, lowest, final = run(1 / 240, 1)
check("an impulse peaks at the asked height", math.abs(peak - 2) < 0.01, peak)
check("… 1 / rate seconds after the shot", math.abs(peakAt - 1 / rate) < 0.01, peakAt)
check("… never swings below rest", lowest > -1e-9, lowest)
check("… and is back at rest in half a second", math.abs(final) < 0.01 and select(4, run(1 / 60, 0.5)) < 0.01, final)
local _, _, lowSlow, finalSlow = run(0.25, 2) -- a hitch: 4 frames a second
check("a slow frame rate never overshoots either", lowSlow > -1e-9 and math.abs(finalSlow) < 0.01, lowSlow)
local fx, fv = ShotFeel.spring(1.5, -3, rate, 0.1)
local gx, gv = ShotFeel.spring(1.5, -3, rate, 0.05)
gx, gv = ShotFeel.spring(gx, gv, rate, 0.05)
check("the spring is exact (two half steps = one step)", math.abs(fx - gx) < 1e-9 and math.abs(fv - gv) < 1e-9)
check("no time, no change", select(1, ShotFeel.spring(0.7, 2, rate, 0)) == 0.7)

-- A casing: thrown up and out, falls, bounces lower each time, comes to rest on its floor.
local c: ShotFeel.Fall = { x = 0, y = 3, z = 0, vx = 6, vy = 5, vz = 0, floor = 0, resting = false }
local bounces, highest, lastBounceTop, below = 0, 3, math.huge, false
local top = 3
local steps = 0
while not c.resting and steps < 2000 do
	local bounced = ShotFeel.fall(c, 1 / 60)
	steps += 1
	top = math.max(top, c.y)
	highest = math.max(highest, c.y)
	below = below or c.y < c.floor - 1e-9
	if bounced then
		bounces += 1
		if bounces > 1 then
			check(`bounce {bounces} is lower than the one before`, top < lastBounceTop + 1e-9, top)
		end
		lastBounceTop = top
		top = c.y
	end
end
check("a casing rises first, then falls", highest > 3)
check("it bounces at least once", bounces >= 1, bounces)
check("it comes to rest on its floor", c.resting and c.y == c.floor and c.vx == 0 and c.vy == 0, c.y)
check("it never sinks under the floor", not below)
check("it rests well within its life", steps / 60 < S.Casings.Life, steps / 60)
check("a resting casing stays", not ShotFeel.fall(c, 0.1) and c.y == c.floor)
check("the friction slows it sideways on a bounce", S.Casings.Friction > 0 and S.Casings.Friction < 1 and S.Casings.Bounce > 0 and S.Casings.Bounce < 1)

-- The surfaces.
check("metal sparks", ShotFeel.surface("Metal") == "metal" and ShotFeel.surface("DiamondPlate") == "metal" and ShotFeel.surface("CorrodedMetal") == "metal")
check("concrete, brick, asphalt are stone", ShotFeel.surface("Concrete") == "stone" and ShotFeel.surface("Brick") == "stone" and ShotFeel.surface("Asphalt") == "stone")
check("a plain wall (SmoothPlastic) is stone", ShotFeel.surface("SmoothPlastic") == "stone" and ShotFeel.surface("Plastic") == "stone")
check("grass, sand, ground are soft", ShotFeel.surface("Grass") == "soft" and ShotFeel.surface("Sand") == "soft" and ShotFeel.surface("Ground") == "soft")
check("wood is wood", ShotFeel.surface("WoodPlanks") == "wood" and ShotFeel.surface("Wood") == "wood")
check("water and glass", ShotFeel.surface("Water") == "water" and ShotFeel.surface("Glass") == "glass")
check("water takes no mark, a wall does", not ShotFeel.marks("water") and ShotFeel.marks("stone") and ShotFeel.marks("metal"))

-- The Hit remote's news and the marker.
check("a headshot", ShotFeel.hitKind(true, true) == "head" and select(2, ShotFeel.hitKind(true, true)))
check("a kill (a blast's count too)", ShotFeel.hitKind(false, true) == "kill" and ShotFeel.hitKind(false, 2) == "kill")
check("a plain hit", ShotFeel.hitKind(false, false) == "hit" and ShotFeel.hitKind(false, 0) == "hit" and ShotFeel.hitKind(nil, nil) == "hit")
local hit, hitSkull = ShotFeel.marker("hit")
local kill, killSkull = ShotFeel.marker("kill")
local head, headSkull = ShotFeel.marker("head", true)
local _, braced = ShotFeel.marker("head", false) -- a brute takes a headshot and stands
check("a hit is white and shows no skull", hit.color[1] == 255 and hit.color[2] == 255 and hit.color[3] == 255 and not hitSkull)
check("a kill shows the skull (when on)", killSkull == (S.Marker.Skull == true) and headSkull == killSkull and not braced)
check("a kill's mark is bigger and lasts longer than a hit's", kill.size > hit.size and kill.seconds > hit.seconds and kill.thick >= hit.thick)
check("a headshot's is the biggest and longest", head.size > kill.size and head.seconds >= kill.seconds)
check("a headshot is not white", not (head.color[1] == 255 and head.color[2] == 255 and head.color[3] == 255))
for _, name in { "hit", "kill", "head" } do
	local tick = S.Marker.Ticks[name]
	check(`the {name} tick names a sound, a volume and a pitch`, tick ~= nil and type(tick[1]) == "string" and type(tick[2]) == "number" and tick[2] <= 1 and type(tick[3]) == "number")
end

-- The bucket: a burst at once, then perSecond.
local bucket = ShotFeel.bucket(3)
local first = 0
for _ = 1, 10 do
	if ShotFeel.allow(bucket, 0, 10, 3) then
		first += 1
	end
end
check("a burst lets `burst` through at once", first == 3, first)
local later = 0
for i = 1, 100 do
	if ShotFeel.allow(bucket, i / 100, 10, 3) then -- one second, a try every 1/100 s
		later += 1
	end
end
check("… then perSecond a second", later >= 9 and later <= 11, later)

-- The ring: in turn, the oldest first.
local ring = ShotFeel.ring(3)
local order = {}
for _ = 1, 7 do
	table.insert(order, ShotFeel.take(ring))
end
check("a ring goes round", table.concat(order, ",") == "1,2,3,1,2,3,1", table.concat(order, ","))
check("a ring of 0 is a ring of 1", ShotFeel.take(ShotFeel.ring(0)) == 1)

-- The budgets are budgets.
check("a phone gets fewer marks and lights", S.Impacts.LiteMarks < S.Impacts.Marks and S.Flash.LiteLights <= S.Flash.Lights)
check("the flash's lights fit in its pool", S.Flash.Lights <= S.Flash.Pool and S.Flash.Seconds < 0.2)
check("casings are capped and short-lived", S.Casings.Max > 0 and S.Casings.Max <= 40 and S.Casings.Life <= 3 and S.Casings.Fade < S.Casings.Life)

if failures > 0 then
	print(`{failures} FAILED`)
else
	print("ALL CHECKS PASSED")
end
