-- 5.7, the rare rain and fog (shared/WeatherPlan.luau): rare, likelier rain at night, a few minutes long, and the
-- clients' blend reaches the look in Fade seconds; in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local WeatherPlan = require("./WeatherPlan")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local t = Config.LivingCity.Weather
local wrongWait = 0

-- Many rolls with the same dice the server uses (Map.lcg): how often it rains or fogs.
local function share(night: boolean): (number, number, number, number)
	local rand = Map.lcg(4242)
	local rains, fogs, shortest, longest = 0, 0, math.huge, 0
	local n = 20000
	for _ = 1, n do
		local state, seconds = WeatherPlan.roll(night, rand(), rand())
		if state == "rain" then
			rains += 1
		elseif state == "fog" then
			fogs += 1
		end
		if state ~= "clear" then
			shortest = math.min(shortest, seconds)
			longest = math.max(longest, seconds)
		elseif seconds ~= t.CheckEvery then
			wrongWait += 1
		end
	end
	return rains / n, fogs / n, shortest, longest
end
local dayRain, dayFog, shortest, longest = share(false)
local nightRain, nightFog = share(true)
print(string.format("  a roll by day: rain %.3f, fog %.3f; at night: rain %.3f, fog %.3f", dayRain, dayFog, nightRain, nightFog))
check("clear weather waits for the next roll", wrongWait == 0, wrongWait)
check("rain and fog are rare (under 1 roll in 6)", dayRain + dayFog < 1 / 6 and nightRain + nightFog < 1 / 6)
check("but they come (a roll in 30 at least)", dayRain + dayFog > 1 / 30)
check("rain is likelier at night", nightRain > dayRain * 1.3)
check("the fog does not care", math.abs(nightFog - dayFog) < 0.01)
check(`a spell lasts {t.Minutes[1]} – {t.Minutes[2]} minutes`, shortest >= t.Minutes[1] * 60 - 1e-6 and longest <= t.Minutes[2] * 60 + 1e-6, `{shortest} {longest}`)
check("the calm after a spell is longer than a roll", t.Calm * 60 > t.CheckEvery)

-- The looks.
local clear, rain, fog = WeatherPlan.look("clear"), WeatherPlan.look("rain"), WeatherPlan.look("fog")
check("clear weather is the plain look with the dawn's rays", clear.density == 0 and clear.reflect == 0 and clear.rain == 0 and clear.rays == 1)
check("rain: rain, wet roads, thicker air, no sun rays", rain.rain == 1 and rain.reflect > 0 and rain.density > 0 and rain.rays == 0)
check("fog: the thickest air, no rain", fog.density > rain.density and fog.rain == 0 and fog.rays == 0)
check("an unknown state looks clear", WeatherPlan.look("snowstorm").density == 0)
check("the roads shine a little, not like mirrors", t.WetReflectance > 0 and t.WetReflectance <= 0.3)

-- The blend: never past the goal, there within Fade seconds, back again.
local now = clear
local steps = 0
while (now.rain < 1 or now.reflect < rain.reflect or now.density < rain.density) and steps < 10000 do
	now = WeatherPlan.toward(now, rain, 0.1)
	steps += 1
	if now.rain > 1 or now.density > rain.density + 1e-9 then
		check("the blend never overshoots", false)
		break
	end
end
check(`into the rain in about {t.Fade} s`, steps * 0.1 <= t.Fade + 0.11, steps * 0.1)
local back = 0
while (now.rain > 0 or now.density > 0 or now.rays < 1) and back < 10000 do
	now = WeatherPlan.toward(now, clear, 0.1)
	back += 1
end
check("and out of it again", now.rain == 0 and now.density == 0 and now.reflect == 0 and now.rays == 1 and back * 0.1 <= t.Fade + 0.11)
local frozen = WeatherPlan.toward(rain, rain, 1)
check("standing still at the goal", frozen.density == rain.density and frozen.rain == 1)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
