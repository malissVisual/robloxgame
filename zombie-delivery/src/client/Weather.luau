--!strict
-- The weather and the light, only on this client:
--   * Day and night: the server runs the clock (Lighting.ClockTime, server/DayNight.luau); this blends the look of
--     the night over the day look from the same clock (Map.nightFactor): darker blue ambient and moonlight, a blue
--     night grade, a denser dark haze, a warm glow through dusk and dawn, a little bloom on the lights. Not pitch
--     black: the roads stay readable, the lamps and headlights (switched by the server) do the rest.
--   * Winter north of the mountain: snow falls around the camera and the air turns cold and white (blended into
--     the same look, day or night).
--   * The ambulance's light bar flashes red / blue while its car's attribute Siren is true (server/Vehicles.luau
--     tags the lenses "SirenLight").
--   * The big landmark icons hide up close.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Map = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Map"))

local Weather = {}

local LOOK_EVERY = 0.1 -- seconds between look updates (the clock moves slowly; 10 Hz is smooth)
local FLASH_EVERY = 0.22 -- the light bar's beat
local SIREN_TAG = "SirenLight"

-- The look at noon, at midnight, in the middle of dusk / dawn, and in the snow.
type Look = {
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	exposure: number,
	haze: Color3, -- the atmosphere's colour
	decay: Color3,
	density: number,
	hazeAmount: number,
	tint: Color3, -- the colour grade
	saturation: number,
	contrast: number,
	bloom: number,
}

local DAY: Look = {
	brightness = 1.6,
	ambient = Color3.fromRGB(70, 70, 80),
	outdoor = Color3.fromRGB(100, 100, 110),
	exposure = 0,
	haze = Color3.fromRGB(150, 160, 140),
	decay = Color3.fromRGB(90, 100, 80),
	density = 0.3,
	hazeAmount = 1.8,
	tint = Color3.fromRGB(235, 245, 225),
	saturation = -0.2,
	contrast = 0.1,
	bloom = 0.35,
}
local NIGHT: Look = {
	brightness = 1.1, -- the moon
	ambient = Color3.fromRGB(42, 46, 62),
	outdoor = Color3.fromRGB(64, 72, 104),
	exposure = -0.15,
	haze = Color3.fromRGB(56, 66, 94),
	decay = Color3.fromRGB(26, 32, 50),
	density = 0.36,
	hazeAmount = 1.1,
	tint = Color3.fromRGB(184, 200, 255),
	saturation = -0.35,
	contrast = 0.18,
	bloom = 0.9,
}
local DUSK_HAZE = Color3.fromRGB(196, 128, 92)
local DUSK_TINT = Color3.fromRGB(255, 216, 190)
local WINTER_HAZE_DAY = Color3.fromRGB(220, 230, 240)
local WINTER_HAZE_NIGHT = Color3.fromRGB(110, 122, 150)
local WINTER_DENSITY = 0.12 -- added to the density in the snow

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
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

	-- A soft bloom of our own (the lamps, the headlights and the neon signs glow more at night).
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "NightBloom"
	bloom.Size = 24
	bloom.Threshold = 1.4
	bloom.Intensity = DAY.bloom
	bloom.Parent = Lighting

	watchSirens()

	local wasWinter = false
	local winter = 0 -- 0 … 1: how far the winter look is blended in (fades over ~2 s)
	local lastNight, lastWinter = -1, -1
	local lookClock, tagClock, flashClock, beat = 0, 0, 0, 0

	-- The look for this night factor and winter blend: written only when it changed (the clock crawls).
	local function applyLook(f: number)
		if math.abs(f - lastNight) < 0.002 and math.abs(winter - lastWinter) < 0.002 then
			return
		end
		local dusk = 4 * f * (1 - f) -- 1 halfway through dusk or dawn
		Lighting.Brightness = lerp(DAY.brightness, NIGHT.brightness, f)
		Lighting.Ambient = DAY.ambient:Lerp(NIGHT.ambient, f)
		Lighting.OutdoorAmbient = DAY.outdoor:Lerp(NIGHT.outdoor, f)
		Lighting.ExposureCompensation = lerp(DAY.exposure, NIGHT.exposure, f)
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			local haze = DAY.haze:Lerp(NIGHT.haze, f):Lerp(DUSK_HAZE, dusk * 0.55)
			atmosphere.Color = haze:Lerp(WINTER_HAZE_DAY:Lerp(WINTER_HAZE_NIGHT, f), winter)
			atmosphere.Decay = DAY.decay:Lerp(NIGHT.decay, f)
			atmosphere.Density = lerp(DAY.density, NIGHT.density, f) + WINTER_DENSITY * winter
			atmosphere.Haze = lerp(DAY.hazeAmount, NIGHT.hazeAmount, f)
		end
		local grade = Lighting:FindFirstChild("ZombieGrade")
		if grade and grade:IsA("ColorCorrectionEffect") then
			grade.TintColor = DAY.tint:Lerp(NIGHT.tint, f):Lerp(DUSK_TINT, dusk * 0.5)
			grade.Saturation = lerp(DAY.saturation, NIGHT.saturation, f)
			grade.Contrast = lerp(DAY.contrast, NIGHT.contrast, f)
		end
		bloom.Intensity = lerp(DAY.bloom, NIGHT.bloom, f)
		bloom.Threshold = lerp(1.4, 1.05, f)
		-- Until the server has made the atmosphere and the grade (the world is still building), try again next time.
		if atmosphere and grade then
			lastNight, lastWinter = f, winter
		end
	end

	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local position = camera.CFrame.Position
		cloud.CFrame = CFrame.new(position + Vector3.new(0, 40, 0))
		-- The big icons over the landmarks: only from afar (up close the buildings' own signs say it).
		tagClock += dt
		if tagClock > 0.25 then
			tagClock = 0
			local world = workspace:FindFirstChild("World")
			local tags = world and world:FindFirstChild("LandmarkTags")
			if tags then
				for _, tag in tags:GetChildren() do
					local gui = tag:FindFirstChildOfClass("BillboardGui")
					if gui and tag:IsA("BasePart") then
						gui.Enabled = Vector3.new(tag.Position.X - position.X, 0, tag.Position.Z - position.Z).Magnitude > 110
					end
				end
			end
		end
		-- The light bars.
		flashClock += dt
		if flashClock > FLASH_EVERY then
			flashClock = 0
			beat += 1
			flash(beat)
		end
		-- Snow on, off.
		local inWinter = Map.isWinter(position.X, position.Z)
		if inWinter ~= wasWinter then
			wasWinter = inWinter
			snow.Rate = if inWinter then 400 else 0
		end
		-- Day, night, winter.
		lookClock += dt
		if lookClock >= LOOK_EVERY then
			winter = math.clamp(winter + (if inWinter then 1 else -1) * lookClock / 2, 0, 1)
			lookClock = 0
			applyLook(Map.nightFactor(Lighting.ClockTime))
		end
	end)
end

return Weather
