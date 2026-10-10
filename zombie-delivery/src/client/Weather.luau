--!strict
-- The weather and the light, only on this client:
--   * Day and night: the server runs the clock (Lighting.ClockTime, server/DayNight.luau); this blends the look of
--     the night over the day look from the same clock (Map.nightFactor): darker blue ambient and moonlight, a blue
--     night grade, a dark haze, a warm glow through dusk and dawn, a little bloom on the lights. Never pitch black:
--     a bright moon, the towns glow back at night (a warm haze, more light, blended in near the districts), and your
--     own soft light around you, so a zombie is always visible; the lamps and headlights (switched by the server)
--     still clearly matter.
--   * Winter north of the mountain: snow falls around the camera and the air turns cold and white (blended into
--     the same look, day or night).
--   * The ambulance's light bar flashes red / blue while its car's attribute Siren is true (server/Vehicles.luau
--     tags the lenses "SirenLight").
--   * The big landmark icons hide up close.
--   * 5.7, the weather (the workspace attribute "Weather" the server picks: shared/WeatherPlan.luau): a rain falls
--     around the camera (more snow in the winter), the roads shine wet (the parts tagged "WetRoad"), the air thickens
--     and greys, or a fog closes in; it all blends in and out over Config.LivingCity.Weather Fade seconds. A mist rises
--     over the river at night, at dawn and in the fog; sun rays at dawn under a clear sky. And it starts
--     client/WorldFx.luau (the night lights, the clock, the lighthouse and the beacon, the broken lamps).
--   * 5.9.2, cheaper: the rain (and the snow) follow your graphics quality (Roblox's quality slider, read now and
--     then): the rain at most RAIN_ALIVE drops alive at the top quality, fewer below; the river's mist and the sun
--     rays only from MEDIUM_QUALITY up. The wet roads have two looks (dry / wet) and only the ones within WET_RANGE of
--     the camera are wetted, looked at every WET_EVERY seconds (and as the weather turns).
--   * 6.15, the BLOOD MOON (server/LiveEvents.luau: the workspace attribute "LiveEvent" is "bloodmoon"): a red sky and
--     a red fog over the night look, the moonlight on the tops red (Lighting.ColorShift_Top), eased in and out over
--     Config.LiveEvents.BloodMoon.Fade s (smoothstep). A colour fade only (nothing moves: the same with reduced motion);
--     the night stays as readable (the red ambient is as bright as the night's, your own light stays).
--   * 6.16, light and atmosphere: the base look is the hour's (shared/SkyGrade.luau, Config.Atmosphere): a cool blue
--     dawn, a golden sunrise and sunset, a clean noon, a violet dusk, a readable blue night, blended smoothly by the
--     clock. It sets Lighting (Brightness, Ambient, OutdoorAmbient, ColorShift_Top / _Bottom, ExposureCompensation,
--     EnvironmentDiffuseScale / SpecularScale, ShadowSoftness: those three only when they moved a little), the
--     atmosphere (the fog: Color, Decay, Density, Offset, Glare, Haze), the grade (tint, saturation, contrast,
--     brightness), the bloom (the lamps, windows and headlights glow at night; nothing washes out by day) and the sun
--     rays (most at the golden hours); the town's glow, the snow, the rain and the fog (greyer, softer shadows, no
--     glare) and the Blood Moon blend over it as before. client/SkyFx.luau (stepped here) adds the clouds, the soft far
--     blur and the dust in the air.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Map = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Map"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local WeatherPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeatherPlan"))
local SkyGrade = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SkyGrade"))
local WorldFx = require(script.Parent.WorldFx)
local SkyFx = require(script.Parent.SkyFx)
local DeviceBudget = require(script.Parent.DeviceBudget)
local PhoneMotion = require(script.Parent.PhoneMotion)

local Weather = {}

local LOOK_EVERY = 0.1 -- seconds between look updates (the clock moves slowly; 10 Hz is smooth)
local HOUR_STEP = 0.004 -- 6.16: hours the clock moves before the look is drawn again (the client writes it every 0.01)
local FLASH_EVERY = 0.22 -- the light bar's beat
local SIREN_TAG = "SirenLight"

-- 6.16: the hour's look is shared/SkyGrade.luau's (Config.Atmosphere); the night's haze tints the rain at night.
local NIGHT_AIR = (SkyGrade.look("night") :: SkyGrade.Look).air
-- In town at night the streets glow back: a warm sodium haze and more light from everywhere (blended in with the
-- distance to the nearest district, CITY_FADE studs outside its edge roads).
local CITY_OUTDOOR = Color3.fromRGB(128, 120, 122)
local CITY_AMBIENT = Color3.fromRGB(88, 84, 92)
local CITY_HAZE = Color3.fromRGB(110, 92, 84)
local CITY_FADE = 220
-- Your own soft light at night (only on your screen): the zombie right next to you is never in the black.
local AURA_RANGE = 26
local AURA_BRIGHTNESS = 0.9
local WINTER_HAZE_DAY = Color3.fromRGB(220, 230, 240)
local WINTER_HAZE_NIGHT = Color3.fromRGB(110, 122, 150)
local WINTER_DENSITY = 0.12 -- added to the density in the snow
local WET_HAZE = Color3.fromRGB(128, 134, 140) -- the air in the rain and the fog
local WET_RANGE = 400 -- 5.9.2: the roads within this of the camera shine wet …
local WET_EVERY = 3 -- … looked at every this many seconds
local QUALITY_EVERY = 2 -- 5.9.2: seconds between looks at the graphics quality
local RAIN_ALIVE = 300 -- raindrops alive at most at the top quality (fewer below)
local MEDIUM_QUALITY = 4 -- the river's mist and the sun rays from this quality (1 … 10) up
local AUTO_QUALITY = 6 -- the quality assumed when Roblox picks it itself (no number to read)
-- 6.15, the Blood Moon's look (blended over the rest by how far it has come in): one table, few locals.
local BLOOD = {
	ambient = Color3.fromRGB(104, 46, 46),
	outdoor = Color3.fromRGB(150, 62, 56),
	haze = Color3.fromRGB(150, 30, 26), -- the atmosphere: the red fog and the sky's glow
	decay = Color3.fromRGB(96, 14, 12),
	tint = Color3.fromRGB(255, 178, 168), -- the colour grade
	shift = Color3.fromRGB(150, 26, 20), -- the moonlight on the tops
	density = 0.08, -- added to the atmosphere's density (the fog closes in a little)
	hazeAmount = 0.9, -- added to its haze
}

-- 6.16: a look's { r, g, b } as a Color3.
local function rgb(c: SkyGrade.Rgb): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- 5.9.2: the graphics quality, 1 … 10: your saved slider, else the rendering's level, else AUTO_QUALITY.
local function qualityNow(): number
	local level = AUTO_QUALITY
	pcall(function()
		local saved = UserSettings().GameSettings.SavedQualityLevel
		if saved ~= Enum.SavedQualitySetting.Automatic then
			level = saved.Value
			return
		end
		local rendering = settings().Rendering.QualityLevel
		if rendering ~= Enum.QualityLevel.Automatic then
			level = math.ceil(rendering.Value / 2.1) -- (Level01 … Level21)
		end
	end)
	return math.clamp(level, 1, 10)
end

-- 5.9.2: the flat distance from (x, z) to a road part's top (its box, turned with it).
local function roadDistance(road: BasePart, eye: Vector3): number
	local at = road.CFrame:PointToObjectSpace(eye)
	local half = road.Size / 2
	local dx = math.max(math.abs(at.X) - half.X, 0)
	local dz = math.max(math.abs(at.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- 0 … 1: how much "in town" the point is (1 inside a district's edge roads, fading to 0 CITY_FADE studs out).
local function cityFactor(x: number, z: number): number
	local best = 0
	for _, district in Map.Districts do
		local x0, x1, z0, z1 = Map.districtEdges(district)
		local dx = math.max(x0 - x, 0, x - x1)
		local dz = math.max(z0 - z, 0, z - z1)
		best = math.max(best, 1 - math.clamp(math.sqrt(dx * dx + dz * dz) / CITY_FADE, 0, 1))
	end
	return best
end

-- ── The light bars ─────────────────────────────────────────────────────────

local LENS_LIT: { [string]: Color3 } = { red = Color3.fromRGB(255, 40, 40), blue = Color3.fromRGB(60, 110, 255) }
local LENS_DIM: { [string]: Color3 } = { red = Color3.fromRGB(120, 34, 34), blue = Color3.fromRGB(34, 44, 120) }
local lenses: { [BasePart]: string } = {} -- lens part → the state shown ("off", "red", "blue")

local function watchSirens()
	local function add(item: Instance)
		if item:IsA("BasePart") then
			lenses[item] = ""
		end
	end
	for _, item in CollectionService:GetTagged(SIREN_TAG) do
		add(item)
	end
	CollectionService:GetInstanceAddedSignal(SIREN_TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(SIREN_TAG):Connect(function(item)
		if item:IsA("BasePart") then
			lenses[item] = nil
		end
	end)
end

-- One beat: on a flashing car the red lenses light on even beats, the blue on odd ones, the bar's light swaps colour.
local function flash(beat: number)
	local red = beat % 2 == 0
	for lens, shown in lenses do
		local car = lens.Parent
		local on = car ~= nil and car:GetAttribute("Siren") == true
		local kind = lens:GetAttribute("Lens")
		local state = if not on then "off" elseif red then "red" else "blue"
		if state == shown then
			continue
		end
		lenses[lens] = state
		if kind == "bar" then
			local glow = lens:FindFirstChild("SirenGlow")
			if glow and glow:IsA("PointLight") then
				glow.Enabled = on
				glow.Color = if red then LENS_LIT.red else LENS_LIT.blue
			end
		elseif type(kind) == "string" and LENS_LIT[kind] then
			local lit = on and kind == state
			lens.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			lens.Color = if lit then LENS_LIT[kind] else LENS_DIM[kind]
		end
	end
end

-- ── Start ──────────────────────────────────────────────────────────────────

function Weather.start()
	WorldFx.start() -- 5.7: the night lights, the clock, the lighthouse, the beacon, the broken lamps
	local cloud = Instance.new("Part")
	cloud.Name = "SnowCloud"
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.Transparency = 1
	cloud.Size = Vector3.new(160, 1, 160)
	cloud.Parent = workspace
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.LightEmission = 0.3
	snow.Size = NumberSequence.new(0.35)
	snow.Lifetime = NumberRange.new(5, 7)
	snow.Speed = NumberRange.new(8, 12)
	snow.SpreadAngle = Vector2.new(15, 15)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Acceleration = Vector3.new(2, 0, 1)
	snow.Rate = 0
	snow.Parent = cloud

	-- 5.7: the rain (long thin drops falling fast), the river's mist and the dawn's sun rays.
	local tuning = Config.LivingCity.Weather
	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.Texture = "rbxasset://textures/particles/smoke_main.dds"
	rain.Color = ColorSequence.new(Color3.fromRGB(196, 206, 216))
	rain.Transparency = NumberSequence.new(0.35)
	rain.LightEmission = 0.15
	rain.Size = NumberSequence.new(0.14)
	rain.Squash = NumberSequence.new(3)
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Lifetime = NumberRange.new(0.7, 0.9)
	rain.Speed = NumberRange.new(70, 85)
	rain.SpreadAngle = Vector2.new(4, 4)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Acceleration = Vector3.new(3, 0, 1)
	rain.Rate = 0
	rain.Parent = cloud
	local mistPart = Instance.new("Part")
	mistPart.Name = "RiverMist"
	mistPart.Anchored = true
	mistPart.CanCollide = false
	mistPart.CanQuery = false
	mistPart.CanTouch = false
	mistPart.Transparency = 1
	mistPart.Size = Vector3.new(Map.River.x1 - Map.River.x0 - 20, 1, 320)
	mistPart.Parent = workspace
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(214, 220, 226))
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.82), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new(22, 34)
	mist.Lifetime = NumberRange.new(9, 13)
	mist.Speed = NumberRange.new(0.5, 1.5)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.RotSpeed = NumberRange.new(-6, 6)
	mist.Rate = 0
	mist.Parent = mistPart
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "ZombieSunRays" -- (6.16: by the hour's look, most at the golden hours)
	rays.Intensity = 0
	rays.Spread = 0.5
	rays.Enabled = false
	rays.Parent = Lighting
	local wet: WeatherPlan.Look = WeatherPlan.look("clear")
	local wetShown = 0 -- the roads' reflectance now (0 dry, else the wet look's)
	local wetLevel = 0 -- 5.9.2: the wet look's reflectance (the last rain's or fog's)
	local wetClock = WET_EVERY -- (looked at on the first tick)
	local wetRoads: { [BasePart]: boolean } = {} -- the roads shown wet
	local quality = qualityNow()
	local qualityClock = 0
	local lastWet = -1
	local roads: { BasePart } = {}
	local function addRoad(item: Instance)
		if item:IsA("BasePart") then
			table.insert(roads, item) -- (wetted at the next look when it is near)
		end
	end
	for _, item in CollectionService:GetTagged("WetRoad") do
		addRoad(item)
	end
	CollectionService:GetInstanceAddedSignal("WetRoad"):Connect(addRoad)
	CollectionService:GetInstanceRemovedSignal("WetRoad"):Connect(function(item: Instance)
		for n, road in roads do
			if road == item then
				table.remove(roads, n)
				wetRoads[road] = nil
				break
			end
		end
	end)
	-- 5.9.2: the roads near the camera wet (shine > 0) or dry, the far ones dry.
	local function wetten(shine: number, eye: Vector3)
		for _, road in roads do
			local want = shine > 0 and roadDistance(road, eye) <= WET_RANGE
			if want then
				if road.Reflectance ~= shine then
					road.Reflectance = shine
				end
				wetRoads[road] = true
			elseif wetRoads[road] then
				wetRoads[road] = nil
				road.Reflectance = 0
			end
		end
	end
	local function weatherNow(): string
		local state = workspace:GetAttribute("Weather")
		return if type(state) == "string" then state else "clear"
	end

	-- A soft bloom of our own (the lamps, the headlights and the neon signs glow more at night; 6.16: the hour's look).
	local look: SkyGrade.Look = SkyGrade.at(Lighting.ClockTime)
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "NightBloom"
	bloom.Size = look.bloomSize
	bloom.Threshold = look.threshold
	bloom.Intensity = look.bloom
	bloom.Parent = Lighting
	SkyFx.start() -- 6.16: the clouds, the soft far blur, the dust
	local reduced = PhoneMotion.reducedMotion() -- (looked at with the graphics quality)

	watchSirens()

	local winter = 0 -- 0 … 1: how far the winter look is blended in (fades over ~2 s)
	local blood = 0 -- 6.15: 0 … 1: how far the Blood Moon has come in (Config.LiveEvents.BloodMoon.Fade s each way)
	local lastBlood = -1
	local lastHour, lastWinter, lastCity = -1, -1, -1
	local city = 0 -- 0 … 1: the town glow (follows the camera, eases over ~1 s)
	local lookClock, flashClock, beat = 0, 0, 0
	local function newAura(): PointLight
		local light = Instance.new("PointLight")
		light.Name = "NightAura"
		light.Range = AURA_RANGE
		light.Color = Color3.fromRGB(200, 214, 255)
		light.Shadows = false
		light.Brightness = 0
		return light
	end
	local aura = newAura()

	-- The look for this hour, night factor, winter, town glow, weather and Blood Moon: written only when one of them
	-- moved (the clock crawls). 6.16: the base is the hour's look (SkyGrade.at); kept in `look` for the tick.
	local function applyLook(f: number, hour: number)
		-- Your own light follows your character (re-parented after a respawn).
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and aura.Parent ~= root then
			-- A destroyed root takes the light with it (its Parent is locked then): setting it would throw every
			-- tick and freeze the day/night look, so a fresh light is made instead.
			local light = aura
			if not pcall(function()
				light.Parent = root
			end) then
				aura = newAura()
				aura.Parent = root
			end
		end
		aura.Brightness = AURA_BRIGHTNESS * f
		aura.Enabled = f > 0.02
		local moved = math.abs(hour - lastHour)
		if math.min(moved, 24 - moved) < HOUR_STEP and math.abs(winter - lastWinter) < 0.002 and math.abs(city - lastCity) < 0.01 and math.abs(wet.density - lastWet) < 0.002 and math.abs(blood - lastBlood) < 0.002 then
			return
		end
		look = SkyGrade.at(hour)
		local red = blood * blood * (3 - 2 * blood) -- 6.15: the Blood Moon, eased in and out
		local grey = math.clamp(wet.density / math.max(tuning.FogDensity, 0.01), 0, 1) -- 1 in a full fog
		local gloom = math.clamp(wet.rain * 0.6 + grey * 0.4, 0, 1)
		local glow = city * f -- the town glow is a night thing
		Lighting.Brightness = look.brightness * (1 - 0.25 * gloom) * (1 - 0.1 * red)
		Lighting.Ambient = rgb(look.ambient):Lerp(CITY_AMBIENT, glow):Lerp(BLOOD.ambient, red * 0.8)
		Lighting.OutdoorAmbient = rgb(look.outdoor):Lerp(CITY_OUTDOOR, glow):Lerp(BLOOD.outdoor, red * 0.8)
		Lighting.ColorShift_Top = rgb(look.top):Lerp(BLOOD.shift, red)
		Lighting.ColorShift_Bottom = rgb(look.bottom)
		Lighting.ExposureCompensation = look.exposure
		-- 6.16: these may re-light the world: written only when they moved a little. An overcast sky softens the shadows
		-- and wets the shine.
		local specular = math.min(1, look.specular + 0.2 * gloom)
		local soft = math.min(1, look.soft + 0.35 * gloom)
		if math.abs(Lighting.EnvironmentDiffuseScale - look.diffuse) > 0.01 then
			Lighting.EnvironmentDiffuseScale = look.diffuse
		end
		if math.abs(Lighting.EnvironmentSpecularScale - specular) > 0.01 then
			Lighting.EnvironmentSpecularScale = specular
		end
		if math.abs(Lighting.ShadowSoftness - soft) > 0.01 then
			Lighting.ShadowSoftness = soft
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			local wetHaze = WET_HAZE:Lerp(rgb(NIGHT_AIR), f * 0.7)
			atmosphere.Color = rgb(look.air):Lerp(CITY_HAZE, glow * 0.6):Lerp(WINTER_HAZE_DAY:Lerp(WINTER_HAZE_NIGHT, f), winter):Lerp(wetHaze, gloom * 0.7):Lerp(BLOOD.haze, red * 0.85)
			atmosphere.Decay = rgb(look.decay):Lerp(BLOOD.decay, red)
			atmosphere.Density = look.density + WINTER_DENSITY * winter + wet.density + BLOOD.density * red
			atmosphere.Offset = look.offset * (1 - grey) -- (a fog swallows the skyline)
			atmosphere.Glare = look.glare * wet.rays -- (no sun's glare under the clouds)
			atmosphere.Haze = look.haze + grey * 1.2 + BLOOD.hazeAmount * red
		end
		local grade = Lighting:FindFirstChild("ZombieGrade")
		if grade and grade:IsA("ColorCorrectionEffect") then
			grade.TintColor = rgb(look.tint):Lerp(BLOOD.tint, red * 0.9)
			grade.Saturation = look.saturation - 0.1 * gloom + 0.12 * red
			grade.Contrast = look.contrast + 0.06 * red
			grade.Brightness = look.lift
		end
		bloom.Intensity = look.bloom
		bloom.Size = look.bloomSize
		bloom.Threshold = look.threshold
		-- Until the server has made the atmosphere and the grade (the world is still building), try again next time.
		if atmosphere and grade then
			lastHour, lastWinter, lastCity, lastWet, lastBlood = hour, winter, city, wet.density, blood
		end
	end

	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local position = camera.CFrame.Position
		cloud.CFrame = CFrame.new(position + Vector3.new(0, 40, 0))
		-- The light bars.
		flashClock += dt
		if flashClock > FLASH_EVERY then
			flashClock = 0
			beat += 1
			flash(beat)
		end
		-- Snow on, off.
		local inWinter = Map.isWinter(position.X, position.Z)
		-- 5.7: in the winter a rain falls as more snow. 5.9.2: both thinner at a lower graphics quality, the rain never
		-- more than RAIN_ALIVE drops alive (scaled the same way; a drop lives rain.Lifetime).
		local scale = math.clamp(quality / 8, 0.3, 1)
		local snowRate = if inWinter then (400 + 500 * wet.rain) * scale else 0
		local rainRate = if inWinter then 0 else math.min(tuning.RainRate * wet.rain, RAIN_ALIVE / 0.8) * scale
		if snow.Rate ~= snowRate then
			snow.Rate = snowRate
		end
		if math.abs(rain.Rate - rainRate) > 1 then
			rain.Rate = rainRate
		end
		-- Day, night, winter.
		lookClock += dt
		if lookClock >= LOOK_EVERY then
			winter = math.clamp(winter + (if inWinter then 1 else -1) * lookClock / 2, 0, 1)
			city += (cityFactor(position.X, position.Z) - city) * math.min(1, lookClock)
			-- 5.7: the weather blends toward the server's (rain, fog or clear).
			wet = WeatherPlan.toward(wet, WeatherPlan.look(weatherNow()), lookClock)
			-- 6.15: the Blood Moon comes in (and goes) over its Fade seconds.
			local bloodGoal = if workspace:GetAttribute("LiveEvent") == "bloodmoon" then 1 else 0
			if blood ~= bloodGoal then
				local stepBy = lookClock / math.max(Config.LiveEvents.BloodMoon.Fade, 0.1)
				blood = if bloodGoal > blood then math.min(1, blood + stepBy) else math.max(0, blood - stepBy)
			end
			lookClock = 0
			local hour = Lighting.ClockTime
			local nightF = Map.nightFactor(hour)
			applyLook(nightF, hour)
			-- The roads shine in the rain (5.9.2: dry or wet, wet past half way to the wet look; near the camera only).
			local goal = WeatherPlan.look(weatherNow()).reflect
			if goal > 0 then
				wetLevel = goal
			end
			local shine = if wetLevel > 0 and wet.reflect >= wetLevel * 0.5 then wetLevel else 0
			wetClock += LOOK_EVERY
			if shine ~= wetShown or (shine > 0 and wetClock >= WET_EVERY) then
				wetShown = shine
				wetClock = 0
				wetten(shine, position)
			end
			-- 5.9.2: the graphics quality, now and then
			qualityClock += LOOK_EVERY
			if qualityClock >= QUALITY_EVERY then
				qualityClock = 0
				quality = qualityNow()
				reduced = PhoneMotion.reducedMotion()
			end
			local fancy = quality >= MEDIUM_QUALITY
			local grey = math.clamp(wet.density / math.max(tuning.FogDensity, 0.01), 0, 1)
			-- The river's mist: at night, at dawn and in the fog, near the river.
			local dawn = math.clamp(1 - math.abs(hour - 7) / 1.6, 0, 1)
			local riverX = (Map.River.x0 + Map.River.x1) / 2
			local nearRiver = math.abs(position.X - riverX) < tuning.MistRange
			local mistAmount = if nearRiver and fancy then math.max(nightF * 0.6, dawn, grey) else 0
			mist.Rate = 7 * mistAmount
			if mistAmount > 0 then
				local b = Map.Bounds
				mistPart.CFrame = CFrame.new(riverX, Map.WaterLevel + 1.5, math.clamp(position.Z, b.z0 + 160, b.z1 - 160))
			end
			-- Sun rays under a clear sky (6.16: the hour's look: most at sunrise and sunset).
			local intensity = if fancy then look.rays * wet.rays else 0
			rays.Enabled = intensity > 0.002
			if math.abs(rays.Intensity - intensity) > 0.001 then
				rays.Intensity = intensity
			end
			-- 6.16: the clouds, the soft far blur, the dust (client/SkyFx.luau).
			local scene: SkyGrade.Scene = { clear = wet.rays, winter = winter, aiming = false, lite = DeviceBudget.lite, quality = quality, reduced = reduced }
			SkyFx.step(look, scene, wet.rain, grey, blood * blood * (3 - 2 * blood), LOOK_EVERY)
		end
	end)
end

return Weather
