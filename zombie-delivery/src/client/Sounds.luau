--!strict
-- The game's sound and music on this client. Everything comes from two audio assets made for the game
-- (art/audio/make_audio.py): sfx.ogg with every effect one after another and music.ogg with four seamless loops;
-- shared/SoundSheet.luau says where each one sits, a Sound plays just that region (PlaybackRegion / LoopRegion).
--
-- Music: "menu" on the start screen, then "day" or "night" (workspace attribute Night), and "tension" on a job
-- while a zombie wave has just arrived or zombies crowd you; the loops crossfade (Config.Audio).
-- Effects: listened for on the remotes the HUD uses too (shots: Tracer, hit markers: Hit, results, notices, the car
-- call), on the world (explosions, your cargo, your car's engine, zombies' groans near you, elevator rides) and on
-- every Ui.button (a soft click). Other players' shots and explosions are 3D sounds at their place.
-- The SOUND button (Hud.onSound) and the N key cycle: everything on → music off → all off.
-- Until the two asset ids are filled in SoundSheet, it stays silent (one note in the Output).
--
-- 5.7, the world's sounds (art/audio/sfx2.ogg, SoundSheet.Sfx2, Config.Juice): your footsteps by speed (on foot, on
-- the ground; Roblox's own running sound is muted then), a bike's freewheel and a scooter's (or an E-Bike's) electric
-- hum in place of the van's engine, the zip line's whirr while you ride (your ZipLine attribute), the bus's brake as it
-- stands at a stop and its doors' hiss as it leaves (a bus's BusAt attribute), the knock at a door and the door's creak
-- (a character's Gesture "knock", server/Npcs.luau Npcs.act), the phone's buzz with a banner (client/PhoneMotion.luau),
-- coins on a payout and on money popped by a kill, and the city's hum and wind (louder at night). Until Sfx2Id is
-- filled in, a few play a stand-in from the first sheet (coin: cash, the buzz: notify, the knock: putdown) and the
-- rest stay silent (no van engine on a bike). Also starts client/Juice.luau.
--
-- 6.12, the world sounds alive (art/audio/sfx3.ogg, SoundSheet.Sfx3, Config.Soundscape): client/SoundScape.luau plays
-- the footsteps by surface (yours and the nearest players'; it took over the 5.7 steps and the hum and wind), the
-- splashes, the car doors and the backs, the horn (H in the driver's seat) and the ambience (the day, the night, a
-- rooftop's wind, the park's fountain); it gets how to play from here (SoundScape.start). Money that went down outside
-- a job plays "purchase". The UI stings for other modules: Sounds.play("task_done" | "purchase" | "event_start" |
-- "event_end", volume?, pitch?). Until Sfx3Id is filled in, a few play a stand-in (FALLBACK: the steps the 5.7 steps, a
-- door (or a tailgate) shut the putdown, the horns the chauffeur's horn, the bell the coin, the beep the notice,
-- task_done job_done, purchase cash, event_start the wave alarm, event_end the notice) and the rest stay silent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local SoundSheet = require(Shared.SoundSheet)
local Drive = require(script.Parent.Drive)
local Ui = require(script.Parent.Ui)
local PhoneMotion = require(script.Parent.PhoneMotion)
local Juice = require(script.Parent.Juice)
local SoundScape = require(script.Parent.SoundScape)

local Sounds = {}

local AUDIO = Config.Audio
local JUICE = Config.Juice
local player = Players.LocalPlayer

-- Set by client/Main.client.luau: shows a short message (the sound setting after N / SOUND).
Sounds.notify = nil :: ((text: string) -> ())?

local enabled = SoundSheet.SfxId ~= "" and SoundSheet.MusicId ~= ""
local sheet2 = SoundSheet.Sfx2Id ~= "" -- 5.7: the world's sounds
local sheet3 = SoundSheet.Sfx3Id ~= "" -- 6.12: doors, horns, steps by surface, ambience, UI stings
-- 5.7: stand-ins from the first sheet while sfx2.ogg is not uploaded yet. 6.12: and from the first two while sfx3.ogg
-- is not (a stand-in of a stand-in works too: a step plays the 5.7 step once sfx2 is up).
local FALLBACK: { [string]: string } = {
	coin = "cash", phone_buzz = "notify", knock = "putdown",
	car_door_close = "putdown",
	horn_car = "horn", horn_van = "horn", horn_truck = "horn", bike_bell = "coin", scooter_beep = "notify",
	task_done = "job_done", purchase = "cash", event_start = "wave", event_end = "notify",
}
for _, surface in { "concrete", "grass", "wood", "metal", "water" } do
	FALLBACK[`step_{surface}_a`] = "step_a"
	FALLBACK[`step_{surface}_b`] = "step_b"
end
local musicGroup: SoundGroup
local effectsGroup: SoundGroup
local started = false -- 6.12: Sounds.start made the groups (a module may play before)
local mode = 1 -- 1 everything, 2 music off, 3 all off
local MODES = { "Sound: music and effects on", "Sound: music off", "Sound: all off" }

-- ── Playing a region ──────────────────────────────────────────────────────

local function region(sheet: { [string]: { number } }, name: string): NumberRange?
	local r = sheet[name]
	if not r then
		return nil
	end
	return NumberRange.new(r[1], r[1] + r[2])
end

-- 5.7: the asset and the region of a sound: the first sheet, then the second (once uploaded), then its stand-in.
local function find(name: string): (string?, NumberRange?)
	local range = region(SoundSheet.Sfx, name)
	if range then
		return SoundSheet.SfxId, range
	end
	if sheet2 then
		range = region(SoundSheet.Sfx2, name)
		if range then
			return SoundSheet.Sfx2Id, range
		end
	end
	if sheet3 then
		range = region(SoundSheet.Sfx3, name)
		if range then
			return SoundSheet.Sfx3Id, range
		end
	end
	local standIn = FALLBACK[name]
	if standIn then
		return find(standIn)
	end
	return nil, nil
end

local function makeSound(asset: string, range: NumberRange, looped: boolean, group: SoundGroup, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = asset
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = range
	if looped then
		sound.LoopRegion = range
	end
	sound.Looped = looped
	sound.SoundGroup = group
	sound.Parent = parent
	return sound
end

-- 2D effects: one ready Sound per name (a small round of them for the fast ones), replayed from the start.
local ROUND = { gun_light = 3, gun_crack = 2, gun_heavy = 2, gun_rapid = 4, hit = 3, kill = 2, ui_click = 2, step_a = 2, step_b = 2, coin = 2 }
local flat: { [string]: { sounds: { Sound }, next: number } } = {}

local function play(name: string, volume: number?, pitch: number?)
	if not enabled or mode == 3 or not started then
		return
	end
	local entry = flat[name]
	if not entry then
		local asset, range = find(name)
		if not asset or not range then
			return
		end
		local made: { Sound } = {}
		for _ = 1, ROUND[name] or (if string.sub(name, 1, 5) == "step_" then 2 else 1) do -- (6.12: the steps by surface)
			table.insert(made, makeSound(asset, range, false, effectsGroup, effectsGroup))
		end
		entry = { sounds = made, next = 1 }
		flat[name] = entry
	end
	assert(entry)
	local sound = entry.sounds[entry.next]
	entry.next = entry.next % #entry.sounds + 1
	sound.Volume = volume or 1
	sound.PlaybackSpeed = pitch or 1
	sound.TimePosition = sound.PlaybackRegion.Min
	sound:Play()
end
Sounds.play = play

-- 3D effects: a Sound in an attachment at the spot, gone when it ends (at most MaxVoices at once).
local voices = 0
local function playAt(name: string, position: Vector3, volume: number?, pitch: number?, maxDistance: number?)
	if not enabled or mode == 3 or voices >= AUDIO.MaxVoices or not started then
		return
	end
	local camera = workspace.CurrentCamera
	local asset, range = find(name)
	if not asset or not range or not camera then
		return
	end
	local reach = maxDistance or AUDIO.HearRange
	if (camera.CFrame.Position - position).Magnitude > reach then
		return
	end
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local sound = makeSound(asset, range, false, effectsGroup, holder)
	sound.Volume = volume or 1
	sound.PlaybackSpeed = (pitch or 1) * (0.95 + math.random() * 0.1)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = reach
	voices += 1
	local done = false
	local function finish()
		if not done then
			done = true
			voices -= 1
			holder:Destroy()
		end
	end
	sound.Ended:Once(finish)
	task.delay(range.Max - range.Min + 0.5, finish) -- in case Ended never comes (the asset did not load)
	sound:Play()
end
Sounds.playAt = playAt

-- ── Music ─────────────────────────────────────────────────────────────────

local tracks: { [string]: Sound } = {}
local current: string? = nil
local inGame = false
local tenseUntil = 0
local tenseSince = 0

local function fade(sound: Sound, volume: number)
	local tween = TweenService:Create(sound, TweenInfo.new(AUDIO.MusicFade, Enum.EasingStyle.Sine), { Volume = volume })
	tween:Play()
	if volume <= 0 then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and sound.Volume <= 0.001 then
				sound:Stop()
			end
		end)
	end
end

local function setMusic(name: string)
	if name == current or not enabled then
		return
	end
	local old = current and tracks[current]
	if old then
		fade(old, 0)
	end
	current = name
	local track = tracks[name]
	if not track then
		local range = region(SoundSheet.Music, name)
		if not range then
			return
		end
		track = makeSound(SoundSheet.MusicId, range, true, musicGroup, musicGroup)
		tracks[name] = track
	end
	if not track.IsPlaying then
		track.Volume = 0
		track.TimePosition = track.PlaybackRegion.Min
		track:Play()
	end
	fade(track, 1)
end

-- What should play now (every second).
local hasJob = false
local function zombiesNear(range: number): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local folder = workspace:FindFirstChild("Zombies")
	if not root or not folder then
		return 0
	end
	local count = 0
	for _, model in folder:GetChildren() do
		local body = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if body and (body.Position - root.Position).Magnitude < range then
			count += 1
		end
	end
	return count
end

local function pickMusic()
	if not inGame then
		setMusic("menu")
		return
	end
	local now = os.clock()
	if hasJob and zombiesNear(AUDIO.TensionRange) >= AUDIO.TensionZombies then
		tenseUntil = math.max(tenseUntil, now + 6)
	end
	if hasJob and now < tenseUntil then
		if current ~= "tension" then
			tenseSince = now
		end
		setMusic("tension")
	elseif current == "tension" and now - tenseSince < AUDIO.TensionHold then
		return -- let it play a little longer: no flip-flopping
	else
		setMusic(if workspace:GetAttribute("Night") == true then "night" else "day")
	end
end

-- The start screen is over (Main's play()).
function Sounds.setInGame(on: boolean)
	inGame = on
	pickMusic()
end

-- ── The setting ───────────────────────────────────────────────────────────

local function applyMode()
	musicGroup.Volume = if mode == 1 then AUDIO.MusicVolume else 0
	effectsGroup.Volume = if mode == 3 then 0 else AUDIO.EffectsVolume
end

function Sounds.cycle()
	mode = mode % 3 + 1
	applyMode()
	local notify = Sounds.notify
	if notify then
		notify(MODES[mode])
	end
	play("ui_click")
end

-- ── Listening ─────────────────────────────────────────────────────────────

-- Tracer colour → the gun that fired it (every hand gun and car gun has its own colour; the same colours share a sound).
local byColor: { [string]: string } = {}
local function colorKey(c: Color3): string
	return `{math.floor(c.R * 255 + 0.5)},{math.floor(c.G * 255 + 0.5)},{math.floor(c.B * 255 + 0.5)}`
end
for _, list in { Config.Weapons :: { any }, Config.CarGuns :: { any } } do
	for _, def in list do
		local key = `{def.color[1]},{def.color[2]},{def.color[3]}`
		if not byColor[key] then
			byColor[key] = AUDIO.WeaponSounds[def.id] or "gun_light"
		end
	end
end

local function listenShots()
	local lastShot: { [number]: number } = {}
	Net.get("Tracer").OnClientEvent:Connect(function(from: Vector3, _to: Vector3, color: Color3, shooter: number)
		if typeof(from) ~= "Vector3" then
			return
		end
		local now = os.clock()
		local id = if type(shooter) == "number" then shooter else 0
		-- A shotgun's pellets are one shot; a bandit's burst too (shooter 0: everyone who is not a player).
		if id ~= 0 and lastShot[id] and now - lastShot[id] < 0.05 then
			return
		end
		lastShot[id] = now
		local name = if typeof(color) == "Color3" then byColor[colorKey(color)] or "gun_light" else "gun_light"
		if id == player.UserId then
			play(name, if name == "gun_rapid" then 0.55 else 0.8, 0.97 + math.random() * 0.06)
		else
			playAt(name, from, if id == 0 then 0.65 else 0.8)
		end
	end)
	Net.get("Hit").OnClientEvent:Connect(function(_position: Vector3, _damage: number, crit: boolean, killed: boolean)
		if crit then
			play("headshot", 0.7)
		elseif killed then
			play("kill", 0.8)
		else
			play("hit", 0.6, 0.95 + math.random() * 0.1)
		end
	end)
	workspace.ChildAdded:Connect(function(child)
		if child:IsA("Explosion") then
			local position = child.Position
			playAt("explosion", position, 1, 1, AUDIO.HearRange * 1.5)
		end
	end)
end

local function listenGame()
	local level: number? = nil
	local money: number? = nil
	local lastPayout = 0
	Net.get("State").OnClientEvent:Connect(function(state: any)
		if type(state) ~= "table" then
			return
		end
		if type(state.xp) == "number" then
			local now = Levels.levelFor(state.xp)
			if level and now > level then
				task.delay(0.6, play, "level_up", 0.8)
			end
			level = now
		end
		if type(state.money) == "number" then
			-- Money that moved without a job or a kill: a purchase, a collected safe. 6.12: a purchase (down) its own.
			if money and state.money ~= money and os.clock() - lastPayout > 1.5 then
				if state.money < money then
					play("purchase", Config.Soundscape.PurchaseVolume)
				else
					play("cash", 0.6)
				end
			end
			money = state.money
		end
	end)
	local lastCoin = 0
	Net.get("Reward").OnClientEvent:Connect(function()
		lastPayout = os.clock()
		if os.clock() - lastCoin > 0.2 then -- 5.7: the money popped by a kill clinks (quieter)
			lastCoin = os.clock()
			play("coin", JUICE.CoinVolume * 0.6, 1.08)
		end
	end)
	Net.get("DeliveryResult").OnClientEvent:Connect(function(r: any)
		lastPayout = os.clock()
		if type(r) == "table" and r.success then
			play("job_done", 0.8)
			if (tonumber(r.total) or 0) > 0 then
				task.delay(0.5, function() -- 5.7: and the pay comes in
					play("coin", JUICE.CoinVolume)
				end)
			end
		else
			play("job_fail", 0.7)
		end
	end)
	local wave = 0
	Net.get("Job").OnClientEvent:Connect(function(job: any)
		hasJob = type(job) == "table"
		local now = if hasJob and type(job.wave) == "number" then job.wave else 0
		if now > wave then
			play("wave", 0.7)
			tenseUntil = os.clock() + AUDIO.TensionAfterWave
			task.defer(pickMusic)
		end
		wave = now
		if not hasJob then
			lastPayout = os.clock()
		end
	end)
	local lastNotice = 0
	Net.get("Notice").OnClientEvent:Connect(function()
		if os.clock() - lastNotice > 1.2 then
			lastNotice = os.clock()
			play("notify", 0.5)
		end
	end)
	local lastOpen = 0
	local function opened()
		if os.clock() - lastOpen > 0.4 then
			lastOpen = os.clock()
			play("ui_open", 0.6)
		end
	end
	Net.get("OpenShop").OnClientEvent:Connect(opened)
	Net.get("Estate").OnClientEvent:Connect(opened)
	-- The chauffeur brought the car: it honks where it stopped.
	local calledCar: Model? = nil
	Net.get("CarCall").OnClientEvent:Connect(function(seconds: number?, car: any, _reason: any?)
		if seconds ~= nil then
			calledCar = if typeof(car) == "Instance" and car:IsA("Model") then car else nil
			return
		end
		local model = calledCar
		calledCar = nil
		if car == nil and model and model.Parent then
			playAt("horn", model:GetPivot().Position, 0.8, 1, 200)
		end
	end)
	Ui.onClick = function()
		play("ui_click", 0.5)
	end
end

-- Your cargo: picked up, put down, loaded into your car.
local function listenCargo()
	local lastLoad = 0
	local function watchCar(car: Instance)
		if not car:IsA("Model") or car:GetAttribute("OwnerId") ~= player.UserId then
			return
		end
		local count = car:GetAttribute("CargoCount") or 0
		car:GetAttributeChangedSignal("CargoCount"):Connect(function()
			local now = car:GetAttribute("CargoCount") or 0
			if type(now) == "number" and type(count) == "number" and now > count then
				lastLoad = os.clock()
				play("load", 0.75)
			end
			count = now
		end)
	end
	task.spawn(function()
		local cars = workspace:WaitForChild("Cars", 60)
		if not cars then
			return
		end
		for _, car in cars:GetChildren() do
			watchCar(car)
		end
		cars.ChildAdded:Connect(function(car)
			task.wait() -- its attributes are set before it is parented, but give them a frame
			watchCar(car)
		end)
	end)
	local function watchCharacter(character: Model)
		local carrying = character:GetAttribute("Carrying")
		character:GetAttributeChangedSignal("Carrying"):Connect(function()
			local now = character:GetAttribute("Carrying")
			if now ~= nil and carrying == nil then
				play("pickup", 0.7)
			elseif now == nil and carrying ~= nil then
				task.delay(0.25, function()
					if os.clock() - lastLoad > 0.5 then
						play("putdown", 0.7)
					end
				end)
			end
			carrying = now
		end)
	end
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

-- ── The steady loops: your engine, zombies, elevator rides, the music ─────

local engine: Sound? = nil
local engineCar: Model? = nil
local engineKind = "engine"

-- 5.7: what your ride sounds like: a pedal bike's freewheel, an electric scooter's (or the E-Bike's) hum, else the
-- engine. (No stand-in: a bike never plays the van's engine.)
local function loopFor(car: Model): string
	if car:GetAttribute("Bike") == true then
		return if car:GetAttribute("BikeStand") == true or car:GetAttribute("CarId") == "ebike" then "scooter" else "freewheel"
	end
	return "engine"
end

local function updateEngine()
	local car, driving = Drive.seatedCar()
	if not driving or not car then
		car = nil
	end
	if car ~= engineCar then
		if engine then
			engine:Destroy()
			engine = nil
		end
		engineCar = car
		local seat = car and car:FindFirstChild("DriverSeat")
		local kind = if car then loopFor(car) else "engine"
		local asset, range = find(kind)
		if seat and asset and range and enabled then
			local sound = makeSound(asset, range, true, effectsGroup, seat)
			sound.RollOffMinDistance = 15
			sound.RollOffMaxDistance = 120
			sound.Volume = if kind == "engine" then 0.35 else 0
			sound:Play()
			engine = sound
			engineKind = kind
		end
	end
	local sound = engine
	if sound and car then
		local top = car:GetAttribute("MaxSpeed")
		local share = math.clamp(math.abs(Drive.speed()) / (if type(top) == "number" and top > 0 then top else 80), 0, 1.3)
		local boost = if Drive.boosting() then 0.12 else 0
		if engineKind == "freewheel" then
			-- The ratchet ticks faster with the wheel; silent standing still.
			sound.PlaybackSpeed += (0.6 + share * 0.9 - sound.PlaybackSpeed) * 0.35
			sound.Volume = JUICE.BikeVolume * math.clamp(share * 2.5, 0, 1)
		elseif engineKind == "scooter" then
			sound.PlaybackSpeed += (0.75 + share * 0.55 + boost - sound.PlaybackSpeed) * 0.35
			sound.Volume = JUICE.ScooterVolume * (0.35 + 0.65 * math.min(share, 1))
		else
			local pitch = 0.75 + share * 0.8 + boost
			sound.PlaybackSpeed += (pitch - sound.PlaybackSpeed) * 0.35
			sound.Volume = 0.3 + share * 0.25
		end
	end
end

-- 5.7: the zip line's whirr while you ride one (your character's ZipLine attribute, client/ZipRide.luau), its pitch
-- with your speed.
local zipSound: Sound? = nil
local function updateZip()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local riding = character ~= nil and root ~= nil and character:GetAttribute("ZipLine") ~= nil and mode ~= 3
	local sound = zipSound
	if sound and (not riding or sound.Parent ~= root) then
		sound:Destroy()
		zipSound = nil
		sound = nil
	end
	if not riding or not root then
		return
	end
	if not sound then
		local asset, range = find("zip")
		if not asset or not range then
			return
		end
		local made = makeSound(asset, range, true, effectsGroup, root)
		made.RollOffMinDistance = 10
		made.RollOffMaxDistance = 90
		made.Volume = 0
		made:Play()
		zipSound = made
		sound = made
	end
	assert(sound)
	local share = math.clamp(root.AssemblyLinearVelocity.Magnitude / math.max(1, Config.ZipLines.Speed), 0, 1.2)
	sound.PlaybackSpeed += (0.7 + 0.5 * share - sound.PlaybackSpeed) * 0.4
	sound.Volume = JUICE.ZipVolume * (0.3 + 0.7 * math.min(share, 1))
end

-- 6.12: the footsteps (5.7: yours by speed) and the ambience (5.7: the hum and the wind) moved to
-- client/SoundScape.luau, with the doors, the horn, the splashes and the fountain. How it plays: this module's.
local function make(name: string, parent: Instance?, looped: boolean): Sound?
	if not enabled or not started then
		return nil
	end
	local asset, range = find(name)
	if not asset or not range then
		return nil
	end
	return makeSound(asset, range, looped, effectsGroup, parent or effectsGroup)
end

-- 5.7: the buses: the brake as one stands at a stop, the doors' hiss as it leaves (its BusAt attribute,
-- server/Buses.luau), where it is.
local function listenBuses()
	task.spawn(function()
		local buses = workspace:WaitForChild("Buses", 120)
		if not buses then
			return
		end
		local function watch(bus: Instance)
			if not bus:IsA("Model") then
				return
			end
			local at = bus:GetAttribute("BusAt")
			bus:GetAttributeChangedSignal("BusAt"):Connect(function()
				local now = bus:GetAttribute("BusAt")
				local arrived = now ~= nil and at == nil
				local left = now == nil and at ~= nil
				at = now
				if arrived or left then
					playAt(if arrived then "bus_brake" else "bus_door", bus:GetPivot().Position, JUICE.BusVolume, 1, JUICE.BusRange)
				end
			end)
		end
		for _, bus in buses:GetChildren() do
			watch(bus)
		end
		buses.ChildAdded:Connect(watch)
	end)
end

-- 5.7: a knock at a door (anybody's character, its Gesture "knock" from server/Npcs.luau Npcs.act) and, when the door
-- opens (GestureDoor), its creak a moment later.
local function listenKnocks()
	local function watchCharacter(character: Model)
		character:GetAttributeChangedSignal("GestureAt"):Connect(function()
			if character:GetAttribute("Gesture") ~= "knock" then
				return
			end
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return
			end
			local at = root.Position + root.CFrame.LookVector * 1.5
			playAt("knock", at, JUICE.KnockVolume, 1, 80)
			if character:GetAttribute("GestureDoor") == true then
				task.delay(JUICE.DoorDelay, function()
					playAt("door_creak", at, JUICE.DoorVolume, 1, 80)
				end)
			end
		end)
	end
	local function watchPlayer(other: Player)
		if other.Character then
			watchCharacter(other.Character)
		end
		other.CharacterAdded:Connect(watchCharacter)
	end
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
end

local lastGroan = 0
local function groan()
	local now = os.clock()
	if now - lastGroan < AUDIO.GroanEvery * (0.7 + math.random() * 0.6) then
		return
	end
	lastGroan = now
	local camera = workspace.CurrentCamera
	local folder = workspace:FindFirstChild("Zombies")
	if not camera or not folder then
		return
	end
	local near: { BasePart } = {}
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("Bandit") ~= true then
			local body = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if body and (body.Position - camera.Focus.Position).Magnitude < AUDIO.GroanRange then
				table.insert(near, body)
			end
		end
	end
	if #near > 0 then
		local body = near[math.random(1, #near)]
		playAt(if math.random() < 0.5 then "zombie_a" else "zombie_b", body.Position, 0.55, 0.85 + math.random() * 0.3, AUDIO.GroanRange + 20)
	end
end

local lastPosition: Vector3? = nil
local spawnedAt = 0
local function elevator()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		lastPosition = nil
		return
	end
	local position = root.Position
	local was = lastPosition
	lastPosition = position
	-- A jump of many studs in a tenth of a second, on foot: an elevator pad (or a ride home) took you there.
	if was and (position - was).Magnitude > 40 and os.clock() - spawnedAt > 3 and not Drive.seatedCar() then
		play("ding", 0.6)
	end
end

function Sounds.start()
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Parent = SoundService
	effectsGroup = Instance.new("SoundGroup")
	effectsGroup.Name = "Effects"
	effectsGroup.Parent = SoundService
	started = true
	applyMode()
	if not enabled then
		warn("[Sounds] no sound yet: upload art/audio/sfx.ogg and art/audio/music.ogg and put their ids in shared/SoundSheet.luau")
	elseif not sheet3 then
		print("[Sounds] 6.12: art/audio/sfx3.ogg is not uploaded yet (SoundSheet.Sfx3Id): stand-ins play (art/audio/NAHRAT-SFX3.md)")
	end
	player.CharacterAdded:Connect(function()
		spawnedAt = os.clock()
		lastPosition = nil
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() or input.KeyCode ~= Enum.KeyCode.N then
			return
		end
		Sounds.cycle()
	end)
	listenShots()
	listenGame()
	listenCargo()
	listenBuses()
	listenKnocks()
	PhoneMotion.onBanner = function()
		play("phone_buzz", JUICE.BuzzVolume)
	end
	pickMusic()
	-- 6.12: the footsteps, the splashes, the doors, the horn and the ambience (client/SoundScape.luau)
	SoundScape.start({
		play = play,
		playAt = playAt,
		make = make,
		has = function(name: string): boolean
			return enabled and find(name) ~= nil
		end,
		on = function(): boolean
			return enabled and mode ~= 3
		end,
		inGame = function(): boolean
			return inGame
		end,
		sheet3 = enabled and sheet3,
	})
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.1)
			tick += 1
			if enabled then
				updateEngine()
				updateZip()
				elevator()
				if tick % 5 == 0 and mode ~= 3 then
					groan()
				end
			end
			if tick % 10 == 0 then
				pickMusic()
			end
		end
	end)
	Juice.start() -- 5.7: the money counting up, the confetti
end

return Sounds
