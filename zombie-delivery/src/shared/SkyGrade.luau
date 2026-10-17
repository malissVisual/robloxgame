--!strict
-- 6.16, light and atmosphere: the look of every time of day as plain numbers (Config.Atmosphere). The named looks
-- (night, dawn, sunrise, morning, noon, afternoon, golden, dusk) are full at their hours on Config.Atmosphere.Clock and
-- blend smoothly in between (smoothstep, round midnight too). Every client draws it (client/Weather.luau: Lighting, the
-- atmosphere, the colour grade, the bloom, the sun rays; client/SkyFx.luau: the clouds, the soft far blur, the dust).
-- Pure Luau (no Roblox): tests/skygrade_test.luau checks it.
--
--   SkyGrade.at(hour)                  the look at this hour (0 … 24, any number wraps) and the name of the nearest look
--   SkyGrade.look(name)                a named look (nil: no such look)
--   SkyGrade.mix(a, b, t)              a blend of two looks (t 0 … 1)
--   SkyGrade.luma(rgb)                 how bright a colour reads (0 … 255; the 3.0.1 readability rule's measure)
--   SkyGrade.farBlur(look, scene)      the soft far blur's strength (DepthOfFieldEffect.FarIntensity) now
--   SkyGrade.dustRate(look, scene)     the dust motes a second now
--   SkyGrade.clouds(rain, fog)         the clouds' Cover and Density for this weather (0 … 1 of the rain, of a fog)

local Config = require(script.Parent.Config)

local SkyGrade = {}

export type Rgb = { number } -- r, g, b (0 … 255)

export type Look = {
	brightness: number,
	exposure: number,
	ambient: Rgb,
	outdoor: Rgb,
	top: Rgb,
	bottom: Rgb,
	diffuse: number,
	specular: number,
	soft: number,
	tint: Rgb,
	saturation: number,
	contrast: number,
	lift: number,
	bloom: number,
	bloomSize: number,
	threshold: number,
	rays: number,
	air: Rgb,
	decay: Rgb,
	density: number,
	offset: number,
	glare: number,
	haze: number,
	clouds: Rgb,
	blur: number,
	dust: number,
}

-- What the client knows now (client/Weather.luau): how clear the sky is (1 clear … 0 in the rain or a fog), the snow
-- (0 … 1), whether you aim, a phone or a tablet, the graphics quality (1 … 10), the player's Reduced Motion.
export type Scene = {
	clear: number,
	winter: number,
	aiming: boolean,
	lite: boolean,
	quality: number,
	reduced: boolean,
}

local A = Config.Atmosphere
local LOOKS = (A.Looks :: any) :: { [string]: Look }
local CLOCK = A.Clock

-- The fields a look blends (numbers, then colours).
SkyGrade.Numbers = { "brightness", "exposure", "diffuse", "specular", "soft", "saturation", "contrast", "lift", "bloom", "bloomSize", "threshold", "rays", "density", "offset", "glare", "haze", "blur", "dust" }
SkyGrade.Colours = { "ambient", "outdoor", "top", "bottom", "tint", "air", "decay", "clouds" }

function SkyGrade.look(name: string): Look?
	return LOOKS[name]
end

function SkyGrade.mix(a: Look, b: Look, t: number): Look
	local out: { [string]: any } = {}
	for _, key in SkyGrade.Numbers do
		local x, y = (a :: any)[key] :: number, (b :: any)[key] :: number
		out[key] = x + (y - x) * t
	end
	for _, key in SkyGrade.Colours do
		local x, y = (a :: any)[key] :: Rgb, (b :: any)[key] :: Rgb
		out[key] = { x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t, x[3] + (y[3] - x[3]) * t }
	end
	return (out :: any) :: Look
end

function SkyGrade.at(hour: number): (Look, string)
	local h = hour % 24
	local n = #CLOCK
	-- The last key at or before this hour (before the first one: the last, a day earlier) and the one after it.
	local i = n
	for k = 1, n do
		if CLOCK[k].hour <= h then
			i = k
		end
	end
	local from, to = CLOCK[i], CLOCK[i % n + 1]
	local span = (to.hour - from.hour) % 24
	if span <= 0 then
		span = 24
	end
	local t = math.clamp(((h - from.hour) % 24) / span, 0, 1)
	local s = t * t * (3 - 2 * t)
	return SkyGrade.mix(LOOKS[from.look], LOOKS[to.look], s), if s < 0.5 then from.look else to.look
end

function SkyGrade.luma(rgb: Rgb): number
	return 0.2126 * rgb[1] + 0.7152 * rgb[2] + 0.0722 * rgb[3]
end

-- The far blur: Blur.Far × the look's blur (half in the rain or a fog); none on a phone, at a low quality or aiming.
function SkyGrade.farBlur(look: Look, scene: Scene): number
	local blur = A.Blur
	if scene.lite or scene.aiming or scene.quality < blur.Quality then
		return 0
	end
	return blur.Far * look.blur * (0.5 + 0.5 * math.clamp(scene.clear, 0, 1))
end

-- The dust: Dust.Rate × the look's dust, only in clear weather and out of the snow; none with Reduced Motion; a phone
-- Dust.Lite of it; thinner at a low graphics quality (the rain's rule: quality / 8, at least 0.3).
function SkyGrade.dustRate(look: Look, scene: Scene): number
	local dust = A.Dust
	if scene.reduced then
		return 0
	end
	local scale = math.clamp(scene.quality / 8, 0.3, 1) * (if scene.lite then dust.Lite else 1)
	return dust.Rate * look.dust * math.clamp(scene.clear, 0, 1) * (1 - math.clamp(scene.winter, 0, 1)) * scale
end

-- The clouds: clear weather's cover and density, more of both in the rain or a fog (whichever is more).
function SkyGrade.clouds(rain: number, fog: number): (number, number)
	local c = A.Clouds
	local r, f = math.clamp(rain, 0, 1), math.clamp(fog, 0, 1)
	local cover = math.max(c.Cover + (c.RainCover - c.Cover) * r, c.Cover + (c.FogCover - c.Cover) * f)
	local density = math.max(c.Density + (c.RainDensity - c.Density) * r, c.Density + (c.FogDensity - c.Density) * f)
	return cover, density
end

return SkyGrade
