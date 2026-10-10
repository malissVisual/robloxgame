--!strict
-- 6.16, the air, only on this client (started and stepped by client/Weather.luau on its look tick, never per frame; the
-- numbers in Config.Atmosphere, the rules in shared/SkyGrade.luau):
--   * The clouds: Roblox's moving clouds (Terrain.Clouds: the place's own, else made here), more cover in the rain and
--     the fog, coloured by the hour's look (white by day, golden at sunrise and sunset, dark blue at night, greyer in the
--     rain, red under the Blood Moon). Clouds.Lite: on a phone or a tablet too.
--   * The soft blur far away: a DepthOfFieldEffect "ZombieFarBlur" in Lighting, sharp out to Blur.Focus + Radius studs,
--     a very soft blur beyond (SkyGrade.farBlur: never on a phone or a tablet, below a medium graphics quality, or while
--     you aim: the character's Aiming attribute; it fades in and out over Blur.Fade s, and is switched off at nothing).
--   * Dust in the air: a few tiny, slow motes in a box just ahead of the camera by day (one ParticleEmitter on an
--     invisible part that follows the camera), most in the golden light (SkyGrade.dustRate: none at night, in the rain,
--     the fog or the snow, or with Reduced Motion; fewer on a phone or at a low graphics quality).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SkyGrade = require(Shared:WaitForChild("SkyGrade"))
local DeviceBudget = require(script.Parent.DeviceBudget)

local SkyFx = {}

local A = Config.Atmosphere
local RAIN_CLOUDS = Color3.fromRGB(122, 126, 134) -- the clouds in the rain and the fog
local BLOOD_CLOUDS = Color3.fromRGB(120, 34, 30) -- under the Blood Moon

local state = {
	clouds = nil :: Clouds?,
	blur = nil :: DepthOfFieldEffect?,
	blurShown = 0,
	dustPart = nil :: BasePart?,
	dust = nil :: ParticleEmitter?,
}

local function rgb(c: SkyGrade.Rgb): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function SkyFx.start()
	if state.dust then
		return
	end
	-- The clouds (the place's own if it has them; a phone only with Clouds.Lite).
	if A.Clouds.Lite or not DeviceBudget.lite then
		local terrain = workspace.Terrain
		local clouds = terrain:FindFirstChildOfClass("Clouds")
		if not clouds then
			local made = Instance.new("Clouds")
			made.Cover = A.Clouds.Cover
			made.Density = A.Clouds.Density
			made.Parent = terrain
			clouds = made
		end
		state.clouds = clouds
	end
	-- The far blur (off until a step wants it).
	local blur = Instance.new("DepthOfFieldEffect")
	blur.Name = "ZombieFarBlur"
	blur.NearIntensity = 0
	blur.FarIntensity = 0
	blur.FocusDistance = A.Blur.Focus
	blur.InFocusRadius = A.Blur.Radius
	blur.Enabled = false
	blur.Parent = Lighting
	state.blur = blur
	-- The dust: soft tiny motes drifting every way, fading in and out, lit by the sun (and glowing a little).
	local box = Instance.new("Part")
	box.Name = "DustBox"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Transparency = 1
	box.Size = Vector3.new(A.Dust.Box, A.Dust.Box * 0.45, A.Dust.Box)
	box.Parent = workspace
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Dust"
	motes.Texture = "rbxasset://textures/particles/smoke_main.dds"
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 238, 212))
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.4), NumberSequenceKeypoint.new(0.75, 0.4), NumberSequenceKeypoint.new(1, 1) })
	motes.Size = NumberSequence.new(A.Dust.Size)
	motes.LightEmission = 0.5
	motes.LightInfluence = 0.7
	motes.Lifetime = NumberRange.new(A.Dust.Life[1], A.Dust.Life[2])
	motes.Speed = NumberRange.new(0.15, 0.45)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0.04, -0.02, 0.03)
	motes.Drag = 0.4
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Rate = 0
	motes.Parent = box
	state.dustPart = box
	state.dust = motes
end

-- One look tick: the hour's look, what this client knows (SkyGrade.Scene), the rain and the fog (0 … 1), the Blood Moon
-- (0 … 1, eased), the seconds since the last tick.
function SkyFx.step(look: SkyGrade.Look, scene: SkyGrade.Scene, rain: number, fog: number, red: number, dt: number)
	local clouds = state.clouds
	if clouds and clouds.Parent then
		local cover, density = SkyGrade.clouds(rain, fog)
		if math.abs(clouds.Cover - cover) > 0.004 or math.abs(clouds.Density - density) > 0.004 then
			clouds.Cover = cover
			clouds.Density = density
		end
		local colour = rgb(look.clouds):Lerp(RAIN_CLOUDS, math.max(rain, fog) * 0.6):Lerp(BLOOD_CLOUDS, red * 0.8)
		if clouds.Color ~= colour then
			clouds.Color = colour
		end
	end
	-- The far blur: toward its strength now, Blur.Far per Blur.Fade seconds.
	local blur = state.blur
	if blur then
		local character = Players.LocalPlayer.Character
		scene.aiming = scene.aiming or (character ~= nil and character:GetAttribute("Aiming") == true)
		local goal = SkyGrade.farBlur(look, scene)
		local most = A.Blur.Far / math.max(A.Blur.Fade, 0.05) * dt
		local shown = state.blurShown
		shown = if goal > shown then math.min(goal, shown + most) else math.max(goal, shown - most)
		state.blurShown = shown
		blur.Enabled = shown > 0.002
		if blur.Enabled and math.abs(blur.FarIntensity - shown) > 0.001 then
			blur.FarIntensity = shown
		end
	end
	-- The dust: its rate now, its box just ahead of the camera.
	local motes, box = state.dust, state.dustPart
	local camera = workspace.CurrentCamera
	if motes and box and camera then
		local rate = SkyGrade.dustRate(look, scene)
		if math.abs(motes.Rate - rate) > 0.05 then
			motes.Rate = rate
		end
		if rate > 0 then
			local view = camera.CFrame
			box.CFrame = CFrame.new(view.Position + view.LookVector * (A.Dust.Box * 0.3))
		end
	end
end

return SkyFx
