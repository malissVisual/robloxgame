--!strict
-- 6.16, a crash you see and feel (the owner: "sparks on a crash"): a car that loses at least Crash.From of its speed in
-- a blink (yours, or another player's within Crash.Range of the camera) throws a burst of sparks where it hit (a short
-- ray ahead of where it was going, else its bumper) and a metal thunk (Sounds.playAt "van_back_close", lower: a stand-in
-- until a crash sound is made); in your own car the camera gets a little more on top of its ram shake (CameraRig.shake,
-- Crash.Shake at the hardest). Scraping a wall at Scrape.Speed or more (your car: a short ray out of each side a few
-- times a second finds a wall against it) throws a stream of sparks there and trembles the camera a touch.
-- Numbers in Config.DriveFeel.Crash (shared/DriveFeel.luau crash). Cheap: one spark emitter for the bursts and one for
-- the scrape, each on an Attachment in the Terrain moved to the spot (nothing is made per crash); a phone throws half
-- the sparks, none on its lowest graphics. Reduced motion: no shake (CameraRig).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DriveFeel = require(Shared:WaitForChild("DriveFeel"))

local CameraRig = require(script.Parent.CameraRig)
local CarVisuals = require(script.Parent.CarVisuals)
local DeviceBudget = require(script.Parent.DeviceBudget)
local Drive = require(script.Parent.Drive)
local Sounds = require(script.Parent.Sounds)

local CrashFx = {}

local Crash = Config.DriveFeel.Crash
local Scrape = Crash.Scrape
local COOLDOWN = 0.4 -- seconds: one car's crashes at most this often (a crash shakes the speed for a few frames)
local SCRAPE_EVERY = 0.1 -- seconds between the side rays of your car
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

type Watch = { speed: number, velocity: Vector3, crashedAt: number }

local watches: { [Model]: Watch } = {}
local emitters: { burst: ParticleEmitter?, scrape: ParticleEmitter? } = { burst = nil, scrape = nil }
local scrapeClock = { at = 0, on = false, til = 0 }
local sweepClock = { at = 0 }
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function sparks(name: string): ParticleEmitter
	local at = Instance.new("Attachment")
	at.Name = name
	at.Parent = workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = SPARK
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 226, 140), Color3.fromRGB(255, 120, 36))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.4) })
	emitter.Lifetime = NumberRange.new(0.25, 0.6)
	emitter.Speed = NumberRange.new(16, 34)
	emitter.SpreadAngle = Vector2.new(60, 35)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Acceleration = Vector3.new(0, -70, 0)
	emitter.Drag = 2.5
	emitter.Rate = 0
	emitter.Parent = at
	return emitter
end

local function emitterOf(which: string): ParticleEmitter?
	local emitter = if which == "burst" then emitters.burst else emitters.scrape
	if emitter and emitter.Parent and emitter.Parent.Parent == workspace.Terrain then
		return emitter
	end
	local made = sparks(if which == "burst" then "CrashSparks" else "ScrapeSparks")
	if which == "burst" then
		emitters.burst = made
	else
		emitters.scrape = made
	end
	return made
end

-- A phone on its lowest graphics (the saved slider at 1 … 3) throws none.
local function off(): boolean
	if not DeviceBudget.lite then
		return false
	end
	local low = false
	pcall(function()
		local saved = UserSettings().GameSettings.SavedQualityLevel
		low = saved ~= Enum.SavedQualitySetting.Automatic and saved.Value <= 3
	end)
	return low
end

-- Where the car hit: a short ray ahead of where it was going, else its bumper that way.
local function impact(car: Model, chassis: BasePart, way: Vector3): Vector3
	local flat = Vector3.new(way.X, 0, way.Z)
	local frame = chassis.CFrame
	if flat.Magnitude < 0.01 then
		flat = frame.LookVector
	end
	local dir = flat.Unit
	local origin = frame.Position + frame.UpVector * 0.8
	rayParams.FilterDescendantsInstances = { car }
	local hit = workspace:Raycast(origin, dir * (chassis.Size.Z / 2 + 4), rayParams)
	if hit then
		return hit.Position
	end
	local nose = if dir:Dot(frame.LookVector) >= 0 then -1 else 1 -- (the front is at -Z)
	return (frame * CFrame.new(0, 0.6, nose * chassis.Size.Z / 2)).Position
end

local function crash(car: Model, chassis: BasePart, way: Vector3, strength: number, seated: boolean)
	local point = impact(car, chassis, way)
	local flat = Vector3.new(way.X, 0, way.Z)
	local dir = if flat.Magnitude > 0.01 then flat.Unit else chassis.CFrame.LookVector
	if not off() then
		local burst = emitterOf("burst")
		local at = burst and burst.Parent
		if burst and at and at:IsA("Attachment") then
			-- the sparks fly back off what it hit, toward the car and to the sides
			at.WorldCFrame = CFrame.lookAt(point, point - dir)
			burst:Emit(math.max(4, math.floor(Crash.Sparks * strength * (if DeviceBudget.lite then 0.5 else 1) + 0.5)))
		end
	end
	Sounds.playAt("van_back_close", point, 0.45 + 0.55 * strength, 0.72)
	if seated then
		CameraRig.shake(Crash.Shake * strength) -- (on top of CameraRig's own ram shake)
	end
end

-- Your car against a wall: the point it scrapes along, or nil.
local function scraping(car: Model, chassis: BasePart): Vector3?
	local frame = chassis.CFrame
	local origin = frame.Position + frame.UpVector * 1
	local reach = chassis.Size.X / 2 + Scrape.Reach
	rayParams.FilterDescendantsInstances = { car }
	for _, side in { 1, -1 } do
		local hit = workspace:Raycast(origin, frame.RightVector * side * reach, rayParams)
		if hit and math.abs(hit.Normal.Y) < 0.6 then
			local model = hit.Instance:FindFirstAncestorOfClass("Model")
			if not (model and model:FindFirstChildOfClass("Humanoid")) then -- (not a zombie or a person)
				return hit.Position
			end
		end
	end
	return nil
end

local function stepScrape(car: Model, chassis: BasePart, speed: number)
	local now = os.clock()
	if now - scrapeClock.at < SCRAPE_EVERY then
		return
	end
	scrapeClock.at = now
	local point = if speed >= Scrape.Speed and not off() then scraping(car, chassis) else nil
	local emitter = if point or scrapeClock.on then emitterOf("scrape") else nil
	local at = emitter and emitter.Parent
	if not emitter or not at or not at:IsA("Attachment") then
		return
	end
	scrapeClock.on = point ~= nil
	if point then
		local back = -chassis.AssemblyLinearVelocity
		local flat = Vector3.new(back.X, 0, back.Z)
		at.WorldCFrame = CFrame.lookAt(point, point + (if flat.Magnitude > 0.1 then flat.Unit else chassis.CFrame.LookVector))
		emitter.Rate = Scrape.Rate * (if DeviceBudget.lite then 0.5 else 1)
		CameraRig.shake(Scrape.Shake * SCRAPE_EVERY)
		-- off on its own when nothing renews it (the car gone, out of reach)
		scrapeClock.til = now + SCRAPE_EVERY * 3
		task.delay(SCRAPE_EVERY * 4, function()
			if scrapeClock.on and os.clock() > scrapeClock.til then
				scrapeClock.on = false
				emitter.Rate = 0
			end
		end)
	else
		emitter.Rate = 0
	end
end

local function step(car: Model, chassis: BasePart, _dt: number, distance: number, mine: boolean)
	local now = os.clock()
	if now - sweepClock.at > 5 then
		sweepClock.at = now
		for known in watches do
			if known.Parent == nil then
				watches[known] = nil
			end
		end
	end
	if distance > Crash.Range and not mine then
		watches[car] = nil
		return
	end
	local velocity = chassis.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local watch = watches[car]
	if not watch then
		watches[car] = { speed = speed, velocity = velocity, crashedAt = 0 }
		return
	end
	local strength = DriveFeel.crash(watch.speed - speed)
	local seated = mine and Drive.seatedCar() == car -- (your own car with you in it: the camera feels it)
	if strength > 0 and now - watch.crashedAt > COOLDOWN and (car:GetAttribute("Health") or 1) :: number > 0 then
		watch.crashedAt = now
		crash(car, chassis, watch.velocity, strength, seated)
	end
	watch.speed, watch.velocity = speed, velocity
	if seated or scrapeClock.on and mine then
		stepScrape(car, chassis, if seated then speed else 0)
	end
end

function CrashFx.start()
	table.insert(CarVisuals.perCar, step)
end

return CrashFx
