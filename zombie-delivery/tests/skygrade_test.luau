-- 6.16, light and atmosphere (shared/SkyGrade.luau, Config.Atmosphere): every look is complete, the clock's looks blend
-- without a jump (round midnight too), the dawn is cool, the golden hours warm, the noon clean, the night blue and still
-- readable (3.0.1's rule, every minute of the day), the lamps bloom at night and nothing washes out by day, and the far
-- blur, the dust and the clouds follow the device and the weather; in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local SkyGrade = require("./SkyGrade")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local A = Config.Atmosphere
local luma = SkyGrade.luma

-- Every look has every field, the colours in range.
local broken = {}
local names = {}
for name, look in A.Looks do
	table.insert(names, name)
	for _, key in SkyGrade.Numbers do
		if type((look :: any)[key]) ~= "number" then
			table.insert(broken, `{name}.{key}`)
		end
	end
	for _, key in SkyGrade.Colours do
		local c = (look :: any)[key]
		if type(c) ~= "table" or #c ~= 3 or c[1] < 0 or c[1] > 255 or c[2] < 0 or c[2] > 255 or c[3] < 0 or c[3] > 255 then
			table.insert(broken, `{name}.{key}`)
		end
	end
end
check("every look has every number and colour (0 … 255)", #broken == 0, table.concat(broken, ", "))
check("the eight looks are there", #names == 8 and SkyGrade.look("dawn") ~= nil and SkyGrade.look("golden") ~= nil and SkyGrade.look("nope") == nil, #names)

-- The clock: sorted, every look it names exists, every look is used.
local sorted, known, used = true, true, {}
for n, key in A.Clock do
	if key.hour < 0 or key.hour >= 24 or (n > 1 and key.hour <= A.Clock[n - 1].hour) then
		sorted = false
	end
	if A.Looks[key.look] == nil then
		known = false
	end
	used[key.look] = true
end
local unused = {}
for _, name in names do
	if not used[name] then
		table.insert(unused, name)
	end
end
check("the clock's hours are sorted within 0 … 24", sorted)
check("every look on the clock exists", known)
check("every look is on the clock", #unused == 0, table.concat(unused, ", "))

-- A key's hour shows its own look.
local exact = true
for _, key in A.Clock do
	local look, name = SkyGrade.at(key.hour)
	local want = A.Looks[key.look]
	if name ~= key.look or math.abs(look.brightness - want.brightness) > 1e-9 or math.abs(look.tint[3] - want.tint[3]) > 1e-9 then
		exact = false
	end
end
check("at a key's hour its look is full", exact)
check("the hour wraps (25:00 is 01:00, -1:00 is 23:00)", SkyGrade.at(25).brightness == SkyGrade.at(1).brightness and SkyGrade.at(-1).tint[1] == SkyGrade.at(23).tint[1])
local _, atNoon = SkyGrade.at(12.4)
local _, atMidnight = SkyGrade.at(0)
check("the nearest look's name (12:24 noon, 00:00 night)", atNoon == "noon" and atMidnight == "night", `{atNoon} {atMidnight}`)

-- No jump anywhere (a minute at a time, round midnight too): a number moves at most 4 % of its range in a minute.
local ranges: { [string]: number } = {}
for _, key in SkyGrade.Numbers do
	local low, high = math.huge, -math.huge
	for _, look in A.Looks do
		local v = (look :: any)[key] :: number
		low, high = math.min(low, v), math.max(high, v)
	end
	ranges[key] = math.max(high - low, 1e-6)
end
local worst, worstAt = 0, ""
local last = SkyGrade.at(24 - 1 / 60)
for minute = 0, 24 * 60 - 1 do
	local now = SkyGrade.at(minute / 60)
	for _, key in SkyGrade.Numbers do
		local step = math.abs((now :: any)[key] - (last :: any)[key]) / ranges[key]
		if step > worst then
			worst, worstAt = step, `{key} at {minute} min`
		end
	end
	for _, key in SkyGrade.Colours do
		local a, b = (now :: any)[key], (last :: any)[key]
		local step = math.max(math.abs(a[1] - b[1]), math.abs(a[2] - b[2]), math.abs(a[3] - b[3])) / 255
		if step > worst then
			worst, worstAt = step, `{key} at {minute} min`
		end
	end
	last = now
end
check("the looks blend smoothly (no jump in a minute)", worst <= 0.04, `{worst} {worstAt}`)

-- 3.0.1's rule, every minute of the day: never so dark a zombie hides.
local floor = A.ReadableFloor
local dark = {}
for minute = 0, 24 * 60 - 1, 5 do
	local look = SkyGrade.at(minute / 60)
	if luma(look.outdoor) < floor.outdoor or luma(look.ambient) < floor.ambient or luma(look.tint) < floor.tint or look.brightness < floor.brightness or look.lift < 0 or look.saturation < -0.3 then
		table.insert(dark, string.format("%02d:%02d", minute // 60, minute % 60))
	end
end
check("the night is dark but readable (every hour above the floor)", #dark == 0, table.concat(dark, " "))
local night, noon = SkyGrade.look("night") :: SkyGrade.Look, SkyGrade.look("noon") :: SkyGrade.Look
check("… and the night stays darker than the day", night.brightness < noon.brightness and luma(night.tint) < luma(noon.tint))
check("the night does not darken the picture (exposure ≥ 0)", night.exposure >= 0 and (SkyGrade.look("dusk") :: SkyGrade.Look).exposure >= 0 and (SkyGrade.look("dawn") :: SkyGrade.Look).exposure >= 0)

-- The character of each time of day.
local function warm(c: SkyGrade.Rgb): boolean
	return c[1] > c[3] + 30
end
local function cool(c: SkyGrade.Rgb): boolean
	return c[3] > c[1] + 30
end
local dawn, sunrise, golden, dusk = SkyGrade.at(5.5), SkyGrade.at(6.5), SkyGrade.at(17.8), SkyGrade.at(18.9)
check("a cool blue dawn", cool(dawn.tint) and cool(dawn.air) and cool(dawn.outdoor))
check("a warm golden sunrise (the grade, the sun, the haze)", warm(sunrise.tint) and warm(sunrise.top) and warm(sunrise.air))
check("a warm golden sunset, the warmest haze", warm(golden.tint) and warm(golden.top) and golden.air[1] - golden.air[3] >= sunrise.air[1] - sunrise.air[3])
check("a violet-blue dusk", cool(dusk.tint) and dusk.air[3] > dusk.air[2])
check("a clean noon (a nearly neutral grade, the brightest sun, crisp shadows)", math.abs(noon.tint[1] - noon.tint[3]) <= 10 and noon.brightness >= SkyGrade.at(9).brightness and noon.soft <= 0.25 and noon.haze <= SkyGrade.at(17.7).haze)
check("a blue night", cool(night.tint) and cool(night.outdoor) and cool(night.air))
check("the sun glares at the golden hours, not at night", golden.glare > noon.glare and sunrise.glare > noon.glare and night.glare == 0)

-- The bloom: the lamps, the windows and the headlights glow at night, nothing washes out by day.
local bloomBad = {}
for minute = 0, 24 * 60 - 1, 5 do
	local hour = minute / 60
	local look = SkyGrade.at(hour)
	local f = Map.nightFactor(hour)
	if f >= 0.9 and (look.bloom < 0.8 or look.threshold > 1.15) then
		table.insert(bloomBad, `night {hour}`)
	elseif f <= 0.1 and (look.threshold < 1.2 or look.bloom > 0.7) then
		table.insert(bloomBad, `day {hour}`)
	end
end
check("the night lights bloom at night, the day does not wash out", #bloomBad == 0, table.concat(bloomBad, " "))
check("the bloom stays soft (size ≤ 40, intensity ≤ 1.2)", night.bloomSize <= 40 and night.bloom <= 1.2)

-- The sun rays and the dust: in the sun, most at the golden hours, none at night.
check("no sun rays at night, most at the golden hours", night.rays == 0 and golden.rays > noon.rays and sunrise.rays > noon.rays and golden.rays <= 0.25)
check("no dust at night, most in the golden light", night.dust == 0 and golden.dust >= noon.dust and sunrise.dust >= noon.dust)

local function scene(over: { [string]: any }?): SkyGrade.Scene
	local s: { [string]: any } = { clear = 1, winter = 0, aiming = false, lite = false, quality = 10, reduced = false }
	for key, value in over or {} do
		s[key] = value
	end
	return (s :: any) :: SkyGrade.Scene
end
local dustPc = SkyGrade.dustRate(golden, scene())
check("dust by day on a computer", dustPc > 0 and dustPc <= A.Dust.Rate)
check("fewer motes on a phone, none with Reduced Motion", SkyGrade.dustRate(golden, scene({ lite = true })) < dustPc and SkyGrade.dustRate(golden, scene({ reduced = true })) == 0)
check("no dust in the rain or the fog, nor in the snow", SkyGrade.dustRate(golden, scene({ clear = 0 })) == 0 and SkyGrade.dustRate(golden, scene({ winter = 1 })) == 0)
check("thinner dust at a low graphics quality", SkyGrade.dustRate(golden, scene({ quality = 2 })) < dustPc and SkyGrade.dustRate(golden, scene({ quality = 1 })) > 0)
check("dust is sparse (under 60 alive)", A.Dust.Rate * A.Dust.Life[2] <= 80 and A.Dust.Rate * A.Dust.Lite * A.Dust.Life[2] <= 40)

-- The soft far blur.
local blurPc = SkyGrade.farBlur(golden, scene())
check("a very soft far blur on a computer", blurPc > 0 and blurPc <= 0.2, blurPc)
check("no far blur on a phone, while aiming, or at a low quality", SkyGrade.farBlur(golden, scene({ lite = true })) == 0 and SkyGrade.farBlur(golden, scene({ aiming = true })) == 0 and SkyGrade.farBlur(golden, scene({ quality = A.Blur.Quality - 1 })) == 0)
check("half the blur in the rain or the fog", math.abs(SkyGrade.farBlur(golden, scene({ clear = 0 })) - blurPc / 2) < 1e-9)
check("the sharp distance reaches far (Focus + Radius ≥ 150 studs)", A.Blur.Focus + A.Blur.Radius >= 150 and A.Blur.Focus <= 200 and A.Blur.Radius <= 50)

-- The clouds.
local cover, density = SkyGrade.clouds(0, 0)
local rainCover, rainDensity = SkyGrade.clouds(1, 0)
local fogCover = SkyGrade.clouds(0, 1)
check("clear weather: some clouds", cover > 0.2 and cover < 0.7 and density > 0.2)
check("the rain covers the sky, a fog less", rainCover > fogCover and fogCover > cover and rainDensity > density and rainCover <= 1)

-- The sky and the halos: within Roblox's ranges, no pictures by default.
local sky = A.Sky
local pictures = sky.Sun ~= "" or sky.Moon ~= ""
for _, id in sky.Skybox do
	pictures = pictures or id ~= ""
end
check("the sky's numbers are in range", sky.Stars >= 0 and sky.Stars <= 5000 and sky.SunSize > 0 and sky.SunSize <= 60 and sky.MoonSize > 0 and sky.MoonSize <= 60)
check("no uploaded sky pictures by default", not pictures)
check("a few lamp halos on a computer, none or fewer on a phone", A.Halo.Count > 0 and A.Halo.Count <= 20 and A.Halo.Lite <= A.Halo.Count and A.Halo.Transparency >= 0.8)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
