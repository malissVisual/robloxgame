--!strict
-- 6.12, the world sounds alive (the owner: "more sounds so the game feels alive"; Config.Soundscape, the sounds in
-- art/audio/sfx3.ogg and sfx4.ogg, what plays where: shared/SoundPlan.luau). Started by client/Sounds.luau
-- (Sounds.start), which hands over how to play (SoundScape.start(api): its regions, its stand-ins, the SOUND setting):
--   footsteps  yours and the nearest other players' (Others within OthersRange of the camera, looked for every
--              OthersEvery s): one every Config.Juice.StepStride studs walked on the ground (ClimbStride climbed on a
--              ladder, WadeStride longer swimming), the a / b step in turn of the surface under the feet (a ray down,
--              Terrain too: SoundPlan.surface by its material); yours 2D, theirs 3D at their feet (one Sound per step in
--              their root: no one-shot voices). Roblox's own running and climbing sounds (RbxCharacterSounds, in the
--              root) are muted on a body that steps here; with sfx3 its splash and swim too.
--   splashes   a body going into the water (swimming), louder falling fast
--   doors      the van's back opening and closing (two rear doors, a roll-up door, a tailgate), on every van near the
--              camera (client/CarVisuals.luau onSwing → SoundPlan.swingSound); the ZDC Sprinter's back doors have
--              their own swing (by its CarId)
--   ambience   8.1, the game's own (Config.Soundscape.Sandbox, art/audio/sfx4.ogg's 8.1 part), only past the start
--              screen: where you are (SoundPlan.sandboxPlace: the move's state says when you are in the farmstead,
--              client/MoveSounds.luau inside) blends the fields (SoundPlan.SandboxLoops), a warehouse's hall (its
--              lights' hum; a little of the fields through its roller door) or the farmstead's quiet room
--              (SoundPlan.sandboxAmbience); in a warehouse the room's echo (SoundService.AmbientReverb,
--              SoundPlan.reverb; NoReverb elsewhere, on the start screen and with SOUND all off). 8.3: a warehouse's
--              hall is the building of its plot's level (workspace.Warehouses' Level<id>, 1 … 5: the Garage is small,
--              the Logistics Center big; SoundPlan.sandboxPlace's levelOf).
--   8.9, 9.4 the countryside: the fields outdoors (birds and larks over them, a breeze), the D5 motorway's far hum (a
--              3D loop on the motorway at its point nearest you: always from the east; faint in a warehouse, none in
--              the house), and outdoors now and then, each on its own clock (SoundPlan.farGap) and 3D (you hear
--              where): a woodpecker drumming in the forest (a few drums), a dog barking far off, a tractor driving past
--              on the fields (a 3D loop that moves across your view, fading in and out). Every one is a sound wanted on
--              the next sheet; until then its stand-in plays (SoundPlan.sandboxSound, picked once: the sheets do not
--              change while you play).
-- Every look is throttled (Tick, OthersEvery); the steps run on Heartbeat for a handful of bodies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SoundPlan = require(Shared.SoundPlan)
local CarVisuals = require(script.Parent.CarVisuals)
local MoveSounds = require(script.Parent.MoveSounds) -- (8.1: are you in the move's house)

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
	sheet4: boolean, -- 8.1: art/audio/sfx4.ogg is uploaded (SoundSheet.Sfx4Id)
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
		or state == Enum.HumanoidStateType.Seated then
		walker.distance = J.StepStride * 0.6 -- the first step after it comes soon
		walker.wet = false
		return
	end
	local position = root.Position
	local foot = position.Y - humanoid.HipHeight - root.Size.Y / 2
	-- Into the water: a splash where it was broken.
	local wet = state == Enum.HumanoidStateType.Swimming
	local v = root.AssemblyLinearVelocity
	if wet and not walker.wet and now - walker.splashAt > S.SplashGap then
		walker.splashAt = now
		local fall = math.max(0, -v.Y)
		splashAt(Vector3.new(position.X, foot, position.Z), S.SplashVolume * math.clamp(0.45 + fall / 40, 0.45, 1), 0.9 + math.random() * 0.2)
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
		surface = "metal" -- (a ladder's rungs)
	elseif wet then
		surface = "water"
	else
		local reach = math.max(position.Y - foot, 3) + 1.5 -- (to just under the feet)
		local hit = workspace:Raycast(position, Vector3.new(0, -reach, 0), walker.params)
		if not hit then
			return -- (over nothing: a ledge, a step down)
		end
		surface = SoundPlan.surface(hit.Material.Name)
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

-- ── The doors ─────────────────────────────────────────────────────────────

-- 8.1: the car's CarId (a leaf may hang in a model of its own under the car's: up to the first that says it).
local function carIdOf(part: Instance): string?
	local node = part.Parent
	while node and node ~= workspace do
		local id = node:GetAttribute("CarId")
		if type(id) == "string" then
			return id
		end
		node = node.Parent
	end
	return nil
end

local function listenDoors()
	CarVisuals.onSwing = function(what: string, moment: string, part: BasePart)
		local name, pitch = SoundPlan.swingSound(what, moment, carIdOf(part))
		local camera = workspace.CurrentCamera
		if not name or not camera or not api.on() or (part.Position - camera.CFrame.Position).Magnitude > S.DoorRange then
			return
		end
		api.playAt(name, part.Position, if what == "door" then S.DoorVolume else S.BackVolume, pitch, S.DoorRange)
	end
end

-- ── The ambience ──────────────────────────────────────────────────────────

local loops: { [string]: Sound } = {}

-- A loop a share of the way (Blend) toward its volume; paused at silence.
local function fadeLoop(sound: Sound, goal: number)
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

-- One 2D loop toward its volume (made the first time it is wanted, at its pitch: the sandbox's stand-ins).
local function toward(name: string, goal: number, offset: number?, pitch: number?)
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
		made.PlaybackSpeed = pitch or 1
		made.TimePosition = made.PlaybackRegion.Min + (offset or 0)
		made:Play()
		loops[name] = made
		sound = made
	end
	assert(sound)
	fadeLoop(sound, goal)
end

-- Where you are: your body, else the camera's focus.
local function where(): Vector3
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.Focus.Position else Vector3.zero
end

-- 8.1: the fields, a warehouse's hall or the farmstead's room; the room's echo. The D5's far hum, and now and then
-- outdoors a woodpecker in the forest, a dog and a tractor far off.
local SB = S.Sandbox
local reverbName = "" -- the AmbientReverb set here ("": none yet; nothing else in the game sets it)

-- What plays for a wanted sound (SoundPlan.sandboxSound: itself or its stand-in), picked once (chosen nil:
-- nothing can play it).
local picks: { [string]: { chosen: SoundPlan.Pick? } } = {}
local function pick(name: string): SoundPlan.Pick?
	local known = picks[name]
	if not known then
		known = { chosen = SoundPlan.sandboxSound(name, api.has) }
		picks[name] = known
	end
	assert(known)
	return known.chosen
end

-- A 3D sound at a spot (a far sound: Volume within `near` studs, nothing past `range`), at its pick's pitch, its
-- attachment gone when it has played. Only while the camera is within range.
local function farOnce(chosen: SoundPlan.Pick, spot: Vector3, volume: number, near: number, range: number)
	local camera = workspace.CurrentCamera
	if not camera or not api.on() or (camera.CFrame.Position - spot).Magnitude > range then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Name = "FarSound"
	holder.WorldPosition = spot
	local sound = api.make(chosen.name, holder, false)
	if not sound then
		holder:Destroy()
		return
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = near
	sound.RollOffMaxDistance = range
	sound.Volume = volume * chosen.gain
	sound.PlaybackSpeed = chosen.pitch * (0.97 + math.random() * 0.06)
	holder.Parent = workspace.Terrain
	sound:Play()
	local region = sound.PlaybackRegion
	task.delay((region.Max - region.Min) / sound.PlaybackSpeed + 0.5, function()
		holder:Destroy()
	end)
end

-- The D5's far hum: one 3D loop on the motorway at its point nearest you (SoundPlan.motorwaySpot), toward its volume.
type Hum = { holder: Attachment, sound: Sound, gain: number }
local hum: Hum? = nil
local function updateMotorway(at: Vector3, goal: number)
	local M = SB.Motorway
	local current = hum
	if not current then
		local chosen = if goal > 0.001 then pick(SoundPlan.SandboxFar.motorway) else nil
		if not chosen then
			return
		end
		local holder = Instance.new("Attachment")
		holder.Name = "MotorwayHum"
		local sound = api.make(chosen.name, holder, true)
		if not sound then
			holder:Destroy()
			return
		end
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = M.Near
		sound.RollOffMaxDistance = M.Range
		sound.PlaybackSpeed = chosen.pitch
		sound.Volume = 0
		holder.Parent = workspace.Terrain
		sound:Play()
		current = { holder = holder, sound = sound, gain = chosen.gain }
		hum = current
	end
	assert(current)
	local x, z = SoundPlan.motorwaySpot(at.Z)
	current.holder.WorldPosition = Vector3.new(x, M.Y, z)
	fadeLoop(current.sound, goal * current.gain)
end

-- A woodpecker drumming in the forest: Drums drums, Every s apart.
local function drumWoodpecker()
	local B = SB.Woodpecker
	local chosen = pick(SoundPlan.SandboxFar.woodpecker)
	if not chosen then
		return
	end
	local x, z = SoundPlan.farSpot("woodpecker", 0, 0, 0, 0)
	local spot = Vector3.new(x, B.Y, z)
	for i = 0, B.Drums - 1 do
		task.delay(i * B.Every, farOnce, chosen, spot, B.Volume, B.Near, B.Range)
	end
end

-- A dog barking far off, a random way round you.
local function barkFar(at: Vector3)
	local D = SB.Dog
	local chosen = pick(SoundPlan.SandboxFar.dog)
	if chosen then
		local x, z = SoundPlan.farSpot("dog", at.X, at.Z, math.random(), math.random())
		farOnce(chosen, Vector3.new(x, at.Y + 1, z), D.Volume, D.Near, D.Range)
	end
end

-- A tractor driving past on the fields: a 3D loop that moves across your view (SoundPlan.tractorPath), fading in and
-- out (passShare); fading away indoors, gone at its end.
type Pass = { holder: Attachment, sound: Sound, born: number, x: number, y: number, z: number, vx: number, vz: number, gain: number }
local tractor: Pass? = nil
local function startTractor(at: Vector3)
	local T = SB.Tractor
	local chosen = if tractor == nil then pick(SoundPlan.SandboxFar.tractor) else nil
	if not chosen then
		return
	end
	local x, z, vx, vz = SoundPlan.tractorPath(at.X, at.Z, math.random(), math.random())
	local holder = Instance.new("Attachment")
	holder.Name = "TractorSound"
	holder.WorldPosition = Vector3.new(x, at.Y + 2, z)
	local sound = api.make(chosen.name, holder, true)
	if not sound then
		holder:Destroy()
		return
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = T.Near
	sound.RollOffMaxDistance = T.Range
	sound.PlaybackSpeed = chosen.pitch
	sound.Volume = 0
	holder.Parent = workspace.Terrain
	sound:Play()
	tractor = { holder = holder, sound = sound, born = os.clock(), x = x, y = at.Y + 2, z = z, vx = vx, vz = vz, gain = chosen.gain }
end

local function updateTractor(now: number, outdoors: boolean)
	local pass = tractor
	if not pass then
		return
	end
	local T = SB.Tractor
	local t = now - pass.born
	if t >= T.Seconds then
		pass.holder:Destroy()
		tractor = nil
		return
	end
	pass.holder.WorldPosition = Vector3.new(pass.x + pass.vx * t, pass.y, pass.z + pass.vz * t)
	local goal = if outdoors then T.Volume * pass.gain * SoundPlan.passShare(t, T.Seconds, T.Fade) else 0
	pass.sound.Volume += (goal - pass.sound.Volume) * S.Blend
end

-- Each far sound's next time (os.clock; 0: not set yet, the first look only sets it).
local nextFar: { [string]: number } = { woodpecker = 0, dog = 0, tractor = 0 }

local function setReverb(name: string)
	if name == reverbName then
		return
	end
	reverbName = name
	local ok, value = pcall(function(): any
		return (Enum.ReverbType :: any)[name] -- (a name Roblox does not know: a warning, once)
	end)
	if ok and typeof(value) == "EnumItem" then
		SoundService.AmbientReverb = value
	else
		warn(`[SoundScape] Config.Soundscape.Sandbox.Reverb: no Enum.ReverbType "{name}"`)
	end
end

-- 8.3: a plot's warehouse level, 1 … 5 (server/Warehouse.luau's attribute Level<id> on workspace.Warehouses; nil: not
-- there yet, SoundPlan takes 4): its hall is that level's building.
local levelKeys: { [number]: string } = {}
local function warehouseLevel(id: number): number?
	local folder = workspace:FindFirstChild("Warehouses")
	if not folder then
		return nil
	end
	local key = levelKeys[id]
	if not key then
		key = `Level{id}`
		levelKeys[id] = key
	end
	local level = folder:GetAttribute(key)
	return if type(level) == "number" then level else nil
end

local function updateAmbience()
	local playing = api.inGame()
	local at = where()
	local place = SoundPlan.sandboxPlace(at.X, at.Y, at.Z, MoveSounds.inside(), warehouseLevel)
	local mix = SoundPlan.sandboxAmbience(place, api.sheet4)
	local on = if playing then 1 else 0
	local names = SoundPlan.SandboxLoops
	local fields = pick(names.fields)
	if fields then
		toward(fields.name, mix.fields * fields.gain * on, nil, fields.pitch)
	end
	toward(names.warehouse, mix.warehouse * on, 3) -- (out of step with the fields)
	toward(names.room, mix.room * on)
	setReverb(if playing and api.on() then SoundPlan.reverb(place) else "NoReverb")
	updateMotorway(at, mix.motorway * on)
	local now = os.clock()
	local outdoors = playing and place == "outdoors" and api.on()
	updateTractor(now, outdoors)
	for kind, due in nextFar do
		if now >= due then
			nextFar[kind] = now + SoundPlan.farGap(kind, math.random())
			if due > 0 and outdoors then
				if kind == "woodpecker" then
					drumWoodpecker()
				elseif kind == "dog" then
					barkFar(at)
				else
					startTractor(at)
				end
			end
		end
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
				updateAmbience()
			end)
			if not ok and not warned then
				warned = true
				warn(`[SoundScape] {problem}`)
			end
		end
	end)
end

return SoundScape
