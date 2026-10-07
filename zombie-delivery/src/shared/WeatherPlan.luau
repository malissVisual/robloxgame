--!strict
-- 5.7, the rare rain and fog (Config.LivingCity.Weather), as plain numbers: the server (server/DayNight.luau) rolls
-- for a change every CheckEvery seconds of clear weather (and only after Calm minutes of it), keeps a rain or a fog for
-- Minutes and puts the state in the workspace attribute "Weather" ("clear" | "rain" | "fog"); every client blends into
-- its look over Fade seconds (client/Weather.luau). Rain is likelier at night (NightBoost). Pure Luau:
-- tests/weather_test.luau checks it.
--
--   WeatherPlan.States                            "clear", "rain", "fog"
--   WeatherPlan.roll(night, chance, length)        the state a roll gives in clear weather (chance, length: 0 … 1 dice)
--                                                  and how many seconds it lasts (clear: until the next roll)
--   WeatherPlan.look(state)                        what a client blends toward: { density, reflect, rain, rays }
--   WeatherPlan.toward(current, goal, dt)          one step of the blend (Fade seconds from one end to the other)

local Config = require(script.Parent.Config)

local WeatherPlan = {}

WeatherPlan.States = { "clear", "rain", "fog" }

export type Look = {
	density: number, -- added to the atmosphere's density
	reflect: number, -- the roads' reflectance
	rain: number, -- 0 … 1 of the rain's rate
	rays: number, -- 0 … 1 of the dawn's sun rays (none under clouds)
}

function WeatherPlan.roll(night: boolean, chance: number, length: number): (string, number)
	local t = Config.LivingCity.Weather
	local rain = t.RainChance * (if night then t.NightBoost else 1)
	local fog = t.FogChance
	local seconds = (t.Minutes[1] + (t.Minutes[2] - t.Minutes[1]) * math.clamp(length, 0, 1)) * 60
	if chance < rain then
		return "rain", seconds
	elseif chance < rain + fog then
		return "fog", seconds
	end
	return "clear", t.CheckEvery
end

function WeatherPlan.look(state: string): Look
	local t = Config.LivingCity.Weather
	if state == "rain" then
		return { density = t.RainDensity, reflect = t.WetReflectance, rain = 1, rays = 0 }
	elseif state == "fog" then
		return { density = t.FogDensity, reflect = t.WetReflectance * 0.4, rain = 0, rays = 0 }
	end
	return { density = 0, reflect = 0, rain = 0, rays = 1 }
end

function WeatherPlan.toward(current: Look, goal: Look, dt: number): Look
	local t = Config.LivingCity.Weather
	local k = math.clamp(dt / math.max(t.Fade, 0.01), 0, 1)
	local function step(a: number, b: number, full: number): number
		local most = full * k
		return if b > a then math.min(b, a + most) else math.max(b, a - most)
	end
	return {
		density = step(current.density, goal.density, math.max(t.FogDensity, t.RainDensity)),
		reflect = step(current.reflect, goal.reflect, t.WetReflectance),
		rain = step(current.rain, goal.rain, 1),
		rays = step(current.rays, goal.rays, 1),
	}
end

return WeatherPlan
