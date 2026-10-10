--!strict
-- 6.16, zombies with a life of their own (the owner: "upgrade the visuals and the feel"), on this client: the zombies'
-- eyes and voices (Config.ZombieLife). Cosmetic only, the server knows nothing of it. The poses are
-- client/ZombieAnimator.luau's; its list of the zombies and its hooks (a hit, an attack, a death, a brute's step) feed
-- this.
--   * Eyes: the Neon eyes (the native body's EyeL / EyeR, the block fallback's Eye) take EyeDay's dull colour by day and
--     the kind's Glow at night, faded through dusk and dawn by the clock (the workspace's ClockHour, Map.nightFactor):
--     a faint glow, no lights. Within EyeRange of the camera, looked at every EyeEvery s; a body is painted again only
--     when the glow has moved on since (or when it comes near). Never the people (bandits, gunners).
--   * Voices: the existing zombie_a / zombie_b cues pitched (client/Sounds.luau Sounds.playAt: 3D, at the zombie):
--       groans  the nearest within Groan.Range of the camera, each zombie with a pause of its own (Min … Max s,
--               × Night at night, × Hunt while it moves fast), at most Groan.Voices at once and Gap s apart (this took
--               over Sounds' single 5.x groan);
--       scream a runner coming at you (within Scream.Range, faster than Speed, heading your way): a shriek, once every
--               Again s a runner;
--       grunt   a hit (ZombieAnimator.onHit; a hard one louder), a gurgle on a death, a snarl on a bite or a swipe
--               near you, a thud on a brute's step (a footstep cue pitched down).
--     Each kind its pitch (Config.ZombieLife.Pitch, ± Spread a zombie: shared/ZombieStyle.luau gait).
-- Looked at four times a second; the bodies' humanoids and roots come from client/Bodies.luau's cache; the zombies that
-- left are forgotten now and then.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Map = require(Shared:WaitForChild("Map"))
local SoundSheet = require(Shared:WaitForChild("SoundSheet"))
local ZombieStyle = require(Shared:WaitForChild("ZombieStyle"))
local Bodies = require(script.Parent.Bodies)
local Sounds = require(script.Parent.Sounds)
local ZombieAnimator = require(script.Parent.ZombieAnimator)

local ZombieLife = {}

local Tuning = Config.ZombieLife
local Groan, Scream, Grunt, Gurgle, Stomp, Snarl = Tuning.Groan, Tuning.Scream, Tuning.Grunt, Tuning.Gurgle, Tuning.Stomp, Tuning.Snarl
local TICK = 0.25
local SWEEP = 5
local player = Players.LocalPlayer

type Known = {
	kind: string,
	person: boolean,
	pitch: number,
	eyes: { BasePart }?, -- looked up when it first comes near
	glow: Color3,
	applied: number?, -- the night's glow its eyes were painted for
	nextGroan: number,
	screamed: number,
	grunted: number,
	snarled: number,
}

local known: { [Model]: Known } = {}
local started = false
local voices: { number } = {} -- when the zombie voices playing now end
local lastGroan = 0
local lastScream = 0
local lastGrunt = 0
local lastGurgle = 0
local sweptAt = 0

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local DAY = rgb(Tuning.EyeDay)

local function knownOf(model: Model, now: number): Known
	local k = known[model]
	if k then
		return k
	end
	local kind = model:GetAttribute("Zombie")
	local seed = model:GetAttribute("Seed")
	local name = if type(kind) == "string" then kind else "walker"
	local gait = ZombieStyle.gait(name, if type(seed) == "number" then seed else 0)
	local made: Known = {
		kind = name,
		person = gait.style == "person" or model:GetAttribute("Bandit") == true,
		pitch = gait.pitch,
		eyes = nil,
		glow = rgb(Tuning.Glow[name] or Tuning.GlowDefault),
		applied = nil,
		nextGroan = now + Groan.Min * math.random(),
		screamed = -math.huge,
		grunted = -math.huge,
		snarled = -math.huge,
	}
	known[model] = made
	return made
end

local function sweep(now: number)
	if now - sweptAt < SWEEP then
		return
	end
	sweptAt = now
	for model in known do
		if not model.Parent then
			known[model] = nil
		end
	end
end

-- ── Eyes ──────────────────────────────────────────────────────────────────

local function eyesOf(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, name in { "EyeL", "EyeR" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(list, part)
		end
	end
	if #list == 0 then
		for _, child in model:GetChildren() do
			if child.Name == "Eye" and child:IsA("BasePart") then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function nightNow(): number
	local hour = workspace:GetAttribute("ClockHour")
	return Map.nightFactor(if type(hour) == "number" then hour else Lighting.ClockTime)
end

local function paintEyes(eye: Vector3, now: number)
	local night = nightNow()
	local range = Tuning.EyeRange
	for _, model in ZombieAnimator.list() do
		local _, root = Bodies.of(model)
		if not root or (root.Position - eye).Magnitude > range then
			continue
		end
		local k = knownOf(model, now)
		if k.person then
			continue
		end
		if k.applied and math.abs(k.applied - night) < 0.02 then
			continue
		end
		local eyes: { BasePart } = k.eyes or eyesOf(model)
		if #eyes == 0 then
			eyes = eyesOf(model) -- (looked for again until found)
		end
		k.eyes = eyes
		local color = DAY:Lerp(k.glow, night)
		for _, part in eyes do
			part.Color = color
		end
		k.applied = night
	end
end

-- ── Voices ────────────────────────────────────────────────────────────────

local function length(name: string): number
	local r = SoundSheet.Sfx[name]
	return if r then r[2] else 1
end

-- How many zombie voices play now (the ended ones dropped).
local function playing(now: number): number
	for i = #voices, 1, -1 do
		if voices[i] <= now then
			table.remove(voices, i)
		end
	end
	return #voices
end

local function voice(name: string, at: Vector3, volume: number, pitch: number, reach: number, now: number)
	Sounds.playAt(name, at, volume, pitch, reach)
	table.insert(voices, now + length(name) / math.max(pitch, 0.3))
end

local function ear(): Vector3?
	local camera = workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

type Near = { model: Model, root: BasePart, distance: number, known: Known }
local candidates: { Near } = {}
local pool: { Near } = {}

local function talk(now: number)
	local listener = ear()
	if not listener then
		return
	end
	local character = player.Character
	local me: BasePart? = nil
	if character then
		local _, root = Bodies.of(character)
		me = root
	end
	local night = workspace:GetAttribute("Night") == true
	table.clear(candidates)
	for _, model in ZombieAnimator.list() do
		local humanoid, root = Bodies.of(model)
		if not humanoid or not root or humanoid.Health <= 0 then
			continue
		end
		local distance = (root.Position - listener).Magnitude
		if distance > Scream.Range then
			continue
		end
		local k = knownOf(model, now)
		if k.person then
			continue
		end
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z)
		-- A runner comes running at you: a shriek.
		if k.kind == "runner" and me and now - k.screamed > Scream.Again and now - lastScream > Scream.Gap and flat.Magnitude > Scream.Speed then
			local to = me.Position - root.Position
			to = Vector3.new(to.X, 0, to.Z)
			if to.Magnitude > 8 and to.Magnitude < Scream.Range and flat.Unit:Dot(to.Unit) > Scream.Toward then
				k.screamed = now
				lastScream = now
				voice("zombie_a", root.Position, Scream.Volume, Scream.Pitch * k.pitch, Scream.Range + 20, now)
			end
		end
		if distance <= Groan.Range and now >= k.nextGroan then
			local entry = pool[#candidates + 1]
			if not entry then
				entry = { model = model, root = root, distance = distance, known = k }
				pool[#candidates + 1] = entry
			end
			entry.model, entry.root, entry.distance, entry.known = model, root, distance, k
			table.insert(candidates, entry)
			-- (its next pause: shorter at night and while it hunts at a run)
			local pause = Groan.Min + (Groan.Max - Groan.Min) * math.random()
			k.nextGroan = now + pause * (if night then Groan.Night else 1) * (if flat.Magnitude > 8 then Groan.Hunt else 1)
		end
	end
	if #candidates == 0 then
		return
	end
	table.sort(candidates, function(a: Near, b: Near): boolean
		return a.distance < b.distance
	end)
	for _, c in candidates do
		if playing(now) >= Groan.Voices or now - lastGroan < Groan.Gap then
			c.known.nextGroan = now + 0.5 + math.random() -- (no room now: soon again)
			continue
		end
		lastGroan = now
		voice(if math.random() < 0.5 then "zombie_a" else "zombie_b", c.root.Position, Groan.Volume, c.known.pitch * (0.92 + math.random() * 0.16), Groan.Range + 20, now)
	end
end

-- A sound at a zombie within `reach` of the listener (its position), else nil.
local function within(model: Model, reach: number): Vector3?
	local listener = ear()
	local _, root = Bodies.of(model)
	if not listener or not root or (root.Position - listener).Magnitude > reach then
		return nil
	end
	return root.Position
end

local function onHit(model: Model, code: number)
	local now = os.clock()
	local at = within(model, Grunt.Range)
	if not at or now - lastGrunt < Grunt.Gap then
		return
	end
	local k = knownOf(model, now)
	if now - k.grunted < Grunt.Again then
		return
	end
	k.grunted = now
	lastGrunt = now
	local hard = code > 0
	Sounds.playAt("zombie_b", at, Grunt.Volume * (if hard then 1.3 else 1), Grunt.Pitch * k.pitch * (if hard then 0.9 else 1), Grunt.Range + 20)
end

local function onDeath(model: Model)
	local now = os.clock()
	local at = within(model, Gurgle.Range)
	if not at or now - lastGurgle < Gurgle.Gap then
		return
	end
	local k = knownOf(model, now)
	if k.person then
		return
	end
	lastGurgle = now
	Sounds.playAt("zombie_a", at, Gurgle.Volume, Gurgle.Pitch * k.pitch, Gurgle.Range + 20)
end

local function onAttack(model: Model)
	local now = os.clock()
	local at = within(model, Snarl.Range)
	if not at then
		return
	end
	local k = knownOf(model, now)
	if k.person or now - k.snarled < Snarl.Again then
		return
	end
	k.snarled = now
	Sounds.playAt("zombie_b", at, Snarl.Volume, Snarl.Pitch * k.pitch, Snarl.Range + 20)
end

local function onStomp(model: Model, at: Vector3)
	local listener = ear()
	if not listener or (at - listener).Magnitude > Stomp.Range then
		return
	end
	Sounds.playAt("step_concrete_a", at, Stomp.Volume, Stomp.Pitch, Stomp.Range + 20)
end

function ZombieLife.start()
	if started then
		return
	end
	started = true
	ZombieAnimator.onHit = onHit
	ZombieAnimator.onDeath = onDeath
	ZombieAnimator.onAttack = onAttack
	ZombieAnimator.onStomp = onStomp
	task.spawn(function()
		local nextEyes = 0
		while true do
			task.wait(TICK)
			local now = os.clock()
			sweep(now)
			if now >= nextEyes then
				nextEyes = now + Tuning.EyeEvery
				local camera = workspace.CurrentCamera
				if camera then
					paintEyes(camera.CFrame.Position, now)
				end
			end
			talk(now)
		end
	end)
end

return ZombieLife
