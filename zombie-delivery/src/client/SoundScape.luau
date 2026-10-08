--!strict
-- 6.12, the world sounds alive (the owner: "more sounds so the game feels alive"; Config.Soundscape, the sounds in
-- art/audio/sfx3.ogg, what plays where: shared/SoundPlan.luau). Started by client/Sounds.luau (Sounds.start), which
-- hands over how to play (SoundScape.start(api): its regions, its stand-ins, the SOUND setting):
--   footsteps  yours and the nearest other players' (Others within OthersRange of the camera, looked for every
--              OthersEvery s): one every Config.Juice.StepStride studs walked on the ground (ClimbStride climbed on a
--              ladder, WadeStride longer in the water), the a / b step in turn of the surface under the feet (a ray
--              down, Terrain too: SoundPlan.surface, the park's lawns, the water); yours 2D, theirs 3D at their feet
--              (one Sound per step in their root: no one-shot voices). Roblox's own running and climbing sounds
--              (RbxCharacterSounds, in the root) are muted on a body that steps here; with sfx3 its splash and swim too.
--   splashes   a body going into the water (its feet under SoundPlan.waterTop: the park's pond, the river, the sea),
--              louder falling fast; a car driving in (every Tick)
--   doors      a cabin door opening and shut, the back opening and closing (two rear doors, a roll-up door, a
--              tailgate), on every car near the camera (client/CarVisuals.luau onSwing → SoundPlan.swingSound)
--   the horn   H in the driver's seat (client/KeyHints.luau shows it; client/EstateUi.luau leaves H to it there): your
--              horn at once and the Horn remote; server/Horn.luau checks it and sends the car to the players near it,
--              who hear its class's horn from it (SoundPlan.horn: a car, a van, a truck, a bike's bell, a scooter's beep)
--   ambience   the day's and the night's loops blended by the clock (the workspace's ClockHour from server/DayNight,
--              Map.nightFactor), a rooftop's wind by your height (SoundPlan.ambience), only in the game; without
--              sfx3.ogg the 5.7 hum and wind as before (moved here from client/Sounds.luau); the park's fountain, a 3D
--              loop at it (Map.Park) while the camera is near
-- Every look is throttled (Tick, OthersEvery); the steps run on Heartbeat for a handful of bodies.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local SoundPlan = require(Shared.SoundPlan)
local CarVisuals = require(script.Parent.CarVisuals)
local Drive = require(script.Parent.Drive)

local SoundScape = {}

-- How to play (client/Sounds.luau).
export type Api = {
	play: (name: string, volume: number?, pitch: number?) -> (), -- 2D, from the start of its region
	playAt: (name: string, position: Vector3, volume: number?, pitch: number?, maxDistance: number?) -> (), -- 3D, once
	make: (name: string, parent: Instance?, looped: boolean) -> Sound?, -- a Sound of its region (nil parent: 2D)
	has: (name: string) -> boolean, -- it (or its stand-in) can play
	on: () -> boolean, -- effects can be heard (the sheets uploaded, SOUND not "all off")
	inGame: () -> boolean, -- past the start screen
	sheet3: boolean, -- art/audio/sfx3.ogg is uploaded (SoundSheet.Sfx3Id)
}

local S = Config.Soundscape
local J = Config.Juice
local player = Players.LocalPlayer
local api: Api = nil :: any
local started = false

-- ── Footsteps and splashes ────────────────────────────────────────────────

type Walker = {
	distance: number, -- studs walked (or climbed) since the last step
	left: boolean,
	wet: boolean, -- the feet in the water at the last look
	splashAt: number,
	sounds: { [string]: Sound }, -- (another player's: a Sound per step name in their root)
	muted: { [string]: boolean }, -- Roblox's own sounds muted in this root
	params: RaycastParams,
}

local walkers: { [Model]: Walker } = {}
local others: { Model } = {} -- the other players' bodies stepping now (the nearest)
local stepsOn = false -- the steps can play (sfx3, or the 5.7 steps standing in)
local MUTE = { "Running", "Climbing" } -- RbxCharacterSounds' (6.12: with sfx3 also Splash, Swimming: start)

local function walkerOf(character: Model): Walker
	local walker = walkers[character]
	if walker then
		return walker
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = false
	local made: Walker = { distance = J.StepStride * 0.6, left = false, wet = false, splashAt = 0, sounds = {}, muted = {}, params = params }
	walkers[character] = made
	return made
end

-- Roblox's own sounds of this body would step over ours (5.7 muted your Running; 6.12 everybody's that steps here).
local function mute(walker: Walker, root: BasePart)
	for _, name in MUTE do
		if not walker.muted[name] then
			local sound = root:FindFirstChild(name)
			if sound and sound:IsA("Sound") then
				sound.Volume = 0
				walker.muted[name] = true
			end
		end
	end
end

local function splashAt(position: Vector3, volume: number, pitch: number)
	api.playAt("splash", position, volume, pitch, S.SplashRange)
end

-- One body's step this frame (mine: your own, 2D; else 3D in its root).
local function stepFor(character: Model, dt: number, mine: boolean, now: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local walker = walkerOf(character)
	local state = humanoid:GetState()
	if humanoid.Health <= 0 or humanoid.SeatPart ~= nil or humanoid.Sit or humanoid.PlatformStand
		or state == Enum.HumanoidStateType.Seated or character:GetAttribute("ZipLine") ~= nil then
		walker.distance = J.StepStride * 0.6 -- the first step after it comes soon
		walker.wet = false
		return
	end
	local position = root.Position
	local foot = position.Y - humanoid.HipHeight - root.Size.Y / 2
	-- Into the water: a splash where it was broken.
	local top = SoundPlan.waterTop(position.X, position.Z)
	local wet = (top ~= nil and foot < top) or state == Enum.HumanoidStateType.Swimming
	local v = root.AssemblyLinearVelocity
	if wet and not walker.wet and now - walker.splashAt > S.SplashGap then
		walker.splashAt = now
		local fall = math.max(0, -v.Y)
		splashAt(Vector3.new(position.X, top or foot, position.Z), S.SplashVolume * math.clamp(0.45 + fall / 40, 0.45, 1), 0.9 + math.random() * 0.2)
	end
	walker.wet = wet
	local climbing = state == Enum.HumanoidStateType.Climbing
	local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
		or (mine and not climbing and not wet and humanoid.FloorMaterial == Enum.Material.Air)
	local speed = if climbing then math.abs(v.Y) else Vector3.new(v.X, 0, v.Z).Magnitude
	if airborne or speed < J.StepMinSpeed then
		walker.distance = J.StepStride * 0.6
		return
	end
	local stride = if climbing then S.ClimbStride elseif wet then J.StepStride * S.WadeStride else J.StepStride
	walker.distance += speed * dt
	if walker.distance < stride then
		return
	end
	walker.distance = math.min(walker.distance - stride, stride * 0.5)
	local surface: string
	if climbing then
		surface = "metal" -- (the zip lines' ladders are metal trusses)
	elseif wet then
		surface = "water"
	else
		local reach = math.max(position.Y - foot, 3) + 1.5 -- (to just under the feet)
		local hit = workspace:Raycast(position, Vector3.new(0, -reach, 0), walker.params)
		if not hit then
			return -- (over nothing: a ledge, a step down)
		end
		surface = SoundPlan.surface(hit.Material.Name, hit.Position.X, hit.Position.Y, hit.Position.Z)
	end
	walker.left = not walker.left
	local name = SoundPlan.stepName(surface, walker.left)
	local volume = J.StepVolume * (S.StepVolume[surface] or 1) * math.clamp(speed / 16, 0.6, 1.3)
	local pitch = 0.92 + math.random() * 0.16
	if mine then
		api.play(name, volume, pitch)
	else
		local sound = walker.sounds[name]
		if not sound or sound.Parent ~= root then
			local made = api.make(name, root, false)
			if not made then
				return
			end
			made.RollOffMode = Enum.RollOffMode.InverseTapered
			made.RollOffMinDistance = 8
			made.RollOffMaxDistance = S.OthersRange + 20
			walker.sounds[name] = made
			sound = made
		end
		assert(sound)
		sound.Volume = volume * S.OthersVolume
		sound.PlaybackSpeed = pitch
		sound.TimePosition = sound.PlaybackRegion.Min
		sound:Play()
	end
	mute(walker, root)
end

-- Who else steps now: the nearest other players' bodies near the camera; the walkers of bodies gone are forgotten.
local function lookForOthers()
	local camera = workspace.CurrentCamera
	table.clear(others)
	for character in walkers do
		if character.Parent == nil then
			walkers[character] = nil
		end
	end
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local near: { { character: Model, distance: number } } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if other ~= player and character and root and root:IsA("BasePart") then
			local distance = (root.Position - eye).Magnitude
			if distance < S.OthersRange then
				table.insert(near, { character = character, distance = distance })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	for i = 1, math.min(#near, S.Others) do
		table.insert(others, near[i].character)
	end
end

-- A car driving into the water (yours or anybody's near the camera): a big, low splash.
local carWet: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function carSplashes()
	local camera = workspace.CurrentCamera
	local cars = workspace:FindFirstChild("Cars")
	if not camera or not cars then
		return
	end
	local eye = camera.CFrame.Position
	for _, car in cars:GetChildren() do
		local chassis = car:IsA("Model") and car.PrimaryPart
		if chassis and car:IsA("Model") then
			local p = chassis.Position
			if (p - eye).Magnitude < S.SplashRange then
				local top = SoundPlan.waterTop(p.X, p.Z)
				local wet = top ~= nil and p.Y < top + 0.5
				if wet and carWet[car] == false then
					splashAt(Vector3.new(p.X, top or p.Y, p.Z), S.SplashVolume, 0.7)
				end
				carWet[car] = wet
			else
				carWet[car] = nil
			end
		end
	end
end

-- ── The horn ──────────────────────────────────────────────────────────────

local hornSounds: { [Model]: Sound } = setmetatable({}, { __mode = "k" }) :: any

local function hornOf(car: Model): string
	local id = car:GetAttribute("CarId")
	return SoundPlan.horn(if type(id) == "string" then id else nil, car:GetAttribute("Bike") == true, car:GetAttribute("BikeStand") == true)
end

-- The car's own horn from the car (it moves with it).
local function honk(car: Model)
	local chassis = car.PrimaryPart
	if not chassis or not api.on() then
		return
	end
	local name = hornOf(car)
	local sound = hornSounds[car]
	if not sound or sound.Parent ~= chassis or sound.Name ~= "Horn_" .. name then
		if sound then
			sound:Destroy()
		end
		local made = api.make(name, chassis, false)
		if not made then
			return
		end
		made.Name = "Horn_" .. name
		made.RollOffMode = Enum.RollOffMode.InverseTapered
		made.RollOffMinDistance = 18
		made.RollOffMaxDistance = S.HornRange
		hornSounds[car] = made
		sound = made
	end
	assert(sound)
	sound.Volume = S.HornVolume
	sound.TimePosition = sound.PlaybackRegion.Min
	sound:Play()
end

local function listenHorn()
	local remote = Net.get("Horn")
	local last = 0
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.H or UserInputService:GetFocusedTextBox() then
			return
		end
		local car, driving = Drive.seatedCar()
		local now = os.clock()
		if not car or not driving or now - last < S.HornGap then
			return
		end
		last = now
		honk(car)
		remote:FireServer()
	end)
	remote.OnClientEvent:Connect(function(car: any)
		local camera = workspace.CurrentCamera
		if typeof(car) ~= "Instance" or not car:IsA("Model") or not car.Parent or not camera then
			return
		end
		if (car:GetPivot().Position - camera.CFrame.Position).Magnitude < S.HornRange then
			honk(car)
		end
	end)
end

-- ── The doors ─────────────────────────────────────────────────────────────

local function listenDoors()
	CarVisuals.onSwing = function(what: string, moment: string, part: BasePart)
		local name, pitch = SoundPlan.swingSound(what, moment)
		local camera = workspace.CurrentCamera
		if not name or not camera or not api.on() or (part.Position - camera.CFrame.Position).Magnitude > S.DoorRange then
			return
		end
		api.playAt(name, part.Position, if what == "door" then S.DoorVolume else S.BackVolume, pitch, S.DoorRange)
	end
end

-- ── The ambience ──────────────────────────────────────────────────────────

local loops: { [string]: Sound } = {}

-- One 2D loop toward its volume (made the first time it is wanted; paused at silence).
local function toward(name: string, goal: number, offset: number?)
	local sound = loops[name]
	if not sound then
		if goal <= 0.001 then
			return
		end
		local made = api.make(name, nil, true)
		if not made then
			return
		end
		made.Volume = 0
		made.TimePosition = made.PlaybackRegion.Min + (offset or 0)
		made:Play()
		loops[name] = made
		sound = made
	end
	assert(sound)
	local volume = sound.Volume + (goal - sound.Volume) * S.Blend
	if goal <= 0.001 and volume < 0.003 then
		sound.Volume = 0
		if sound.IsPlaying then
			sound:Pause()
		end
		return
	end
	sound.Volume = volume
	if not sound.IsPlaying then
		sound:Resume()
	end
end

local function height(): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position.Y
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.Focus.Position.Y else 0
end

local function updateAmbience()
	local playing = api.inGame()
	local hour = workspace:GetAttribute("ClockHour")
	local clock = if type(hour) == "number" then hour else Lighting.ClockTime
	local mix = SoundPlan.ambience(Map.nightFactor(clock), height(), api.sheet3)
	local on = if playing then 1 else 0
	toward("amb_day", mix.day * on)
	toward("amb_night", mix.night * on, 5) -- (the loops out of step with each other)
	toward("amb_roof", mix.roof * on, 2)
	toward("ambience", mix.hum * on)
	toward("wind", mix.wind * on, 3)
end

-- The park's fountain: a 3D loop at it while the camera is near (made and gone with the distance).
local fountain: Attachment? = nil
local function updateFountain()
	local camera = workspace.CurrentCamera
	if not camera or not api.sheet3 then
		return
	end
	local park = Map.Park
	local spot = Vector3.new(park.x, Map.WalkTop + S.FountainHeight, park.z)
	local near = api.inGame() and (camera.CFrame.Position - spot).Magnitude < S.FountainRange + 30
	local holder = fountain
	if near and not holder then
		local made = Instance.new("Attachment")
		made.Name = "FountainSound"
		made.WorldPosition = spot
		local sound = api.make("amb_fountain", made, true)
		if not sound then
			made:Destroy()
			return
		end
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 10
		sound.RollOffMaxDistance = S.FountainRange
		sound.Volume = S.Fountain
		made.Parent = workspace.Terrain
		sound:Play()
		fountain = made
	elseif not near and holder then
		holder:Destroy()
		fountain = nil
	end
end

function SoundScape.start(given: Api)
	if started then
		return
	end
	started = true
	api = given
	stepsOn = api.has("step_concrete_a")
	if api.sheet3 then
		table.insert(MUTE, "Splash")
		table.insert(MUTE, "Swimming")
	end
	listenDoors()
	listenHorn()
	RunService.Heartbeat:Connect(function(dt: number)
		if not stepsOn or not api.on() then
			return
		end
		local now = os.clock()
		local character = player.Character
		if character then
			stepFor(character, dt, true, now)
		end
		for _, other in others do
			if other.Parent then
				stepFor(other, dt, false, now)
			end
		end
	end)
	task.spawn(function()
		local since = 0
		local warned = false
		while true do
			task.wait(S.Tick)
			since += S.Tick
			local ok, problem = pcall(function()
				if since >= S.OthersEvery then
					since = 0
					lookForOthers()
				end
				if api.on() then
					carSplashes()
				end
				updateAmbience()
				updateFountain()
			end)
			if not ok and not warned then
				warned = true
				warn(`[SoundScape] {problem}`)
			end
		end
	end)
end

return SoundScape
