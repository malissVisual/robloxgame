-- 6.16: driving that feels alive (shared/DriveFeel.luau, Config.DriveFeel) in the standalone Luau CLI: what is under
-- the wheels, how hard the tyres work, what they throw (dust off dirt, snow in the winter, smoke and skid marks on
-- asphalt only when they work hard), a crash's strength, the engine's little gearbox and the speed lines.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local DriveFeel = require("./DriveFeel")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Feel = Config.DriveFeel

-- The ground.
check("asphalt is road", DriveFeel.surface("Asphalt", false, false) == "road")
check("concrete and plastic are road", DriveFeel.surface("Concrete", false, false) == "road" and DriveFeel.surface("SmoothPlastic", false, false) == "road")
check("grass, earth, sand, mud are dirt", DriveFeel.surface("Grass", false, false) == "dirt" and DriveFeel.surface("Ground", false, false) == "dirt"
	and DriveFeel.surface("Sand", false, false) == "dirt" and DriveFeel.surface("Mud", false, false) == "dirt")
check("snow and ice are snow", DriveFeel.surface("Snow", false, false) == "snow" and DriveFeel.surface("Ice", false, false) == "snow")
check("anything in the winter is snow", DriveFeel.surface("Asphalt", true, false) == "snow")
check("the lake's ice is snow", DriveFeel.surface("Asphalt", false, true) == "snow")

-- The strain.
check("cruising straight: no strain", DriveFeel.strain(50, 0, 0, 0, 0) == 0)
check("coasting down (a van: about 18): no strain", DriveFeel.strain(50, 18, 0, 0, 0) == 0)
check("a full brake (65) at speed: full strain", DriveFeel.strain(50, 65, 0, 0, 0) == 1)
check("a full brake at walking pace: none", DriveFeel.strain(6, 65, 0, 0, 0) == 0)
check("a fast sharp turn strains", DriveFeel.strain(55, 0, 105, 0, 0) > 0.8)
check("a gentle turn does not", DriveFeel.strain(55, 0, 40, 0, 0) == 0)
check("a slide on the ice strains", DriveFeel.strain(30, 0, 0, 12, 0) > 0.7)
check("a hard launch strains", DriveFeel.strain(4, 0, 0, 0, 50) == 1)
check("pulling away at speed does not count as a launch", DriveFeel.strain(30, 0, 0, 0, 50) == 0)
check("the strain is the hardest of them", DriveFeel.strain(50, 50, 105, 0, 0) == DriveFeel.strain(50, 0, 105, 0, 0))

-- What the tyres throw.
local kind, rate, skid = DriveFeel.tyres("road", 50, 0)
check("asphalt, cruising: nothing", kind == "smoke" and rate == 0 and skid == 0)
kind, rate, skid = DriveFeel.tyres("road", 50, 1)
check("asphalt, a hard brake: smoke and a mark", kind == "smoke" and rate == Feel.Tyres.Smoke.Rate and skid == 1)
_, _, skid = DriveFeel.tyres("road", 50, Feel.Skids.From - 0.05)
check("a little strain: no mark yet", skid == 0)
kind, rate, skid = DriveFeel.tyres("dirt", 50, 0)
check("grass at speed: dust, no mark", kind == "dust" and rate > Feel.Tyres.Dust.Rate * 0.5 and skid == 0)
local _, slowDust = DriveFeel.tyres("dirt", 3, 0)
check("grass at walking pace: no dust", slowDust == 0)
local _, hardDust = DriveFeel.tyres("dirt", 20, 1)
local _, easyDust = DriveFeel.tyres("dirt", 20, 0)
check("braking on grass throws more", hardDust > easyDust and hardDust <= Feel.Tyres.Dust.Rate)
kind, rate, skid = DriveFeel.tyres("snow", 30, 0)
check("the winter: snow spray, no mark", kind == "snow" and rate > 0 and skid == 0)

-- A crash.
check("a small knock is no crash", DriveFeel.crash(Feel.Crash.From - 1) == 0)
check("a crash from From", DriveFeel.crash(Feel.Crash.From) > 0)
check("the hardest is 1", DriveFeel.crash(Feel.Crash.Full + 50) == 1)
check("harder hits are stronger", DriveFeel.crash(40) > DriveFeel.crash(30))
check("the crash's From is at least the camera's ram shake's", Feel.Crash.From >= Config.LivingCity.Camera.RamFrom)

-- The engine's classes.
check("a van's style is a van", DriveFeel.engineClass("van") == "van")
check("a bus is a truck", DriveFeel.engineClass("bus") == "truck")
check("the muscle car is a car", DriveFeel.engineClass("muscle") == "car")
check("unknown: a van", DriveFeel.engineClass(nil) == "van" and DriveFeel.engineClass("zzz") == "van")
for _, def in Config.Cars do
	check(`{def.id} has a style for its engine`, DriveFeel.styleOf(def.id) == def.style)
end
check("no car id: no style", DriveFeel.styleOf(nil) == nil)
for name, spec in Feel.Engine.Classes do
	check(`{name}: idle under top, gears 2 … 6`, spec.Idle < spec.Top and spec.Gears >= 2 and spec.Gears <= 6 and spec.Volume > 0 and spec.Volume <= 1)
end
for style, class in Feel.Engine.Styles do
	check(`{style} names a class`, Feel.Engine.Classes[class] ~= nil)
end

-- The gearbox.
check("a stand is first gear", DriveFeel.shift(1, 0, 5) == 1)
check("top speed is the last gear", DriveFeel.shift(1, 1, 5) == 5)
check("up only past the edge", DriveFeel.shift(1, 0.2, 5) == 1 and DriveFeel.shift(1, 0.2 + Feel.Engine.Shift + 0.01, 5) == 2)
check("down only under the edge", DriveFeel.shift(2, 0.2 - 0.01, 5) == 2 and DriveFeel.shift(2, 0.2 - Feel.Engine.Shift - 0.01, 5) == 1)
check("back to a stand: first gear", DriveFeel.shift(5, 0, 5) == 1)
local function note(class: string, share: number, throttle: number): (number, number, number)
	local gears = Feel.Engine.Classes[class].Gears
	local gear = DriveFeel.shift(1, share, gears)
	local p, v = DriveFeel.engine(class, share, gear, throttle, false)
	return p, v, gear
end
local idle = note("van", 0, 0)
check("a van idles at its Idle", math.abs(idle - Feel.Engine.Classes.van.Idle) < 1e-6, idle)
local low = note("van", 0.05, 1)
local high = note("van", 0.22, 1)
check("the revs climb in a gear", high > low, `{low} {high}`)
local before, _, g1 = note("van", 0.25 - 0.001, 1)
local after, _, g2 = note("van", 0.25 + Feel.Engine.Shift + 0.01, 1)
check("they drop at the shift", g2 == g1 + 1 and after < before, `{before} {after}`)
local top = note("van", 1, 0)
check("at the top a van is near its Top", math.abs(top - Feel.Engine.Classes.van.Top) < 0.12, top)
check("a truck sounds lower than a car", note("truck", 0.5, 1) < note("car", 0.5, 1))
local _, loud = note("van", 0.5, 1)
local _, quiet = note("van", 0.5, 0)
check("the throttle is louder than a coast", loud > quiet)
local onPitch = note("van", 0.5, 1)
local offPitch = note("van", 0.5, 0)
check("the throttle is a touch higher than a coast", onPitch > offPitch)
local stuck = note("van", 0, 1)
check("a held throttle at a stand revs", stuck > idle + 0.1)
local boosted = DriveFeel.engine("van", 1.2, 4, 1, true)
check("a boost past the top stays sane", boosted < Feel.Engine.Classes.van.Top + 0.4)

-- The speed lines.
check("no lines in town", DriveFeel.streaks(0.5, false) == 0)
check("lines at the top speed", DriveFeel.streaks(1, false) > 0.5)
check("full on a boost", DriveFeel.streaks(1.3, false) == 1)
check("a scooter's from a lower share", DriveFeel.streaks(0.75, true) > 0 and DriveFeel.streaks(0.75, false) == 0)
check("subtle", Feel.SpeedLines.Opacity <= 0.7 and Feel.SpeedLines.Count <= 24)

-- The caps.
check("the skid marks are capped", Feel.Skids.Count <= 250 and Feel.Skids.Life <= 10 and Feel.Skids.FadeFrom < Feel.Skids.Life)
check("a phone gets fewer", Feel.Skids.Lite < 1 and Feel.Tyres.Lite < 1 and Feel.SpeedLines.Lite < 1)
check("the tyres reach a few cars", Feel.Tyres.Cars >= 1 and Feel.Tyres.Cars <= 8)

if failures > 0 then
	print(`{failures} FAILED`)
else
	print("ALL CHECKS PASSED")
end
