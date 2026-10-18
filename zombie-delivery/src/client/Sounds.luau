--!strict
-- The game's sound and music on this client. Everything comes from the audio sheets made for the game
-- (art/audio/make_audio.py): sfx.ogg … sfx6.ogg with the effects one after another and music.ogg with its seamless
-- loops; shared/SoundSheet.luau says where each one sits, a Sound plays just that region (PlaybackRegion / LoopRegion).
-- A sheet not uploaded yet plays the stand-ins of SoundSheet.Fallback (written by make_audio.py) from the sheets that
-- are. Every module plays by name: Sounds.play(name, volume?, pitch?) (2D) and Sounds.playAt(name, position, …) (3D, at
-- most Config.Audio.MaxVoices at once); Sounds.has(name) says whether a sound plays now.
--
-- Music: "menu" on the start screen, then "day" (10.6: the game's light is a fixed afternoon, so never the city's
-- "night"); the loops crossfade (Config.Audio).
-- Effects heard here: money that went down (a purchase), a server's notice (8.9: unless a sound of its own answers it:
-- Sounds.answered, Config.Soundscape.NoticeWait), the ding of a jump far away (a run's fade), every Ui.button's soft
-- click (Ui.onClick); while the danger has zombies in a run (none since 10.5: Config.Runs.Danger) the hits of the run's
-- bat (the Hit remote, server/CloseCombat.luau: a hit, a kill, a headshot, each with its soft tick), explosions (a
-- bloater) and the money a kill pays (the Reward remote's soft coin). The world's sounds (the footsteps by surface, the
-- van's back, the countryside's ambience) are client/SoundScape.luau's; the moves' (a piece picked up, put down,
-- loaded) client/MoveSounds.luau's; the sandbox's stands, till and trades client/SandboxSounds.luau's; the zombies'
-- voices client/ZombieLife.luau's; the start screen's, the character creator's and the ride's their own modules' (by
-- name). 10.6: the city's cargo, its car's load and the couriers' knocks at doors are gone.
-- The N key cycles: everything on → music off → all off (Sounds.cycle; Sounds.notify says it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SoundSheet = require(Shared.SoundSheet)
local Ui = require(script.Parent.Ui)
local SoundScape = require(script.Parent.SoundScape)
local MoveSounds = require(script.Parent.MoveSounds) -- 7.1

local Sounds = {}

local AUDIO = Config.Audio
local JUICE = Config.Juice
local player = Players.LocalPlayer

-- Set by client/Main.client.luau: shows a short message (the sound setting after N / SOUND).
Sounds.notify = nil :: ((text: string) -> ())?
-- 8.9 set by client/SandboxSounds.luau: is the Notice that came at `at` (os.clock()) answered by a sound of its own?
-- (asked NoticeWait s after it: true leaves its notify out)
Sounds.answered = nil :: ((at: number) -> boolean)?

local enabled = SoundSheet.SfxId ~= "" and SoundSheet.MusicId ~= ""
local sheet2 = SoundSheet.Sfx2Id ~= "" -- 5.7: the world's sounds
local sheet3 = SoundSheet.Sfx3Id ~= "" -- 6.12: doors, horns, steps by surface, ambience, UI stings
local sheet4 = SoundSheet.Sfx4Id ~= "" -- 7.1: the moves' sounds and the mountains'
local sheet5 = SoundSheet.Sfx5Id ~= "" -- 8.9: the newest features' (the clipboard, Danny's orders, trades, the auction)
local sheet6 = SoundSheet.Sfx6Id ~= "" -- 10.1: the start's (the start screen, the character creator; the intro's)
-- 5.7: stand-ins from the first sheet while sfx2.ogg is not uploaded yet. 6.12: and from the first two while sfx3.ogg
-- is not (a stand-in of a stand-in works too: a step plays the 5.7 step once sfx2 is up). 7.1: the list is
-- SoundSheet.Fallback (make_audio.py), sfx4's too.
local FALLBACK: { [string]: string } = SoundSheet.Fallback
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
	if sheet4 then
		range = region(SoundSheet.Sfx4, name)
		if range then
			return SoundSheet.Sfx4Id, range
		end
	end
	if sheet5 then
		range = region(SoundSheet.Sfx5, name)
		if range then
			return SoundSheet.Sfx5Id, range
		end
	end
	if sheet6 then
		range = region(SoundSheet.Sfx6, name)
		if range then
			return SoundSheet.Sfx6Id, range
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
local ROUND = { hit = 3, kill = 2, ui_click = 2, step_a = 2, step_b = 2, coin = 2, stand_display = 3 } -- (8.3: FILL BEST's clicks ring out)
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

-- 8.9: does `name` play now (its sheet uploaded, or a stand-in's; the sounds on, Sounds.start done)?
function Sounds.has(name: string): boolean
	return enabled and started and mode ~= 3 and find(name) ~= nil
end

-- ── Music ─────────────────────────────────────────────────────────────────

local tracks: { [string]: Sound } = {}
local current: string? = nil
local inGame = false

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
local function pickMusic()
	if not inGame then
		setMusic("menu")
		return
	end
	setMusic("day")
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

-- The soft tick under a hit's own sound: a sound of the sheet, its volume, its pitch (a headshot's brighter); one tick
-- in TICK_GAP s unless a better hit comes (the city's guns' numbers, Config.Shots.Marker's, kept for the bat).
local TICKS: { [string]: { any } } = {
	hit = { "ui_click", 0.3, 1.8 },
	kill = { "ui_click", 0.45, 1.35 },
	head = { "ding", 0.22, 2.2 },
}
local TICK_GAP = 0.05

-- The run's bat: a hit, a kill, a headshot (the Hit remote, server/CloseCombat.luau), each with its soft tick under it.
-- Explosions where they are.
local function listenHits()
	local RANK: { [string]: number } = { hit = 1, kill = 2, head = 3 }
	local tickAt, tickRank = -math.huge, 0
	Net.get("Hit").OnClientEvent:Connect(function(_position: Vector3, _damage: number, crit: boolean, killed: any)
		local dead = killed == true or (type(killed) == "number" and killed > 0)
		if crit then
			play("headshot", 0.7)
		elseif dead then
			play("kill", 0.8)
		else
			play("hit", 0.6, 0.95 + math.random() * 0.1)
		end
		local kind = if crit then "head" elseif dead then "kill" else "hit"
		local now = os.clock()
		local tick = TICKS[kind]
		if tick and (now - tickAt >= TICK_GAP or RANK[kind] > tickRank) then
			tickAt, tickRank = now, RANK[kind]
			play(tick[1], tick[2], tick[3])
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
	local money: number? = nil
	Net.get("State").OnClientEvent:Connect(function(state: any)
		if type(state) ~= "table" or type(state.money) ~= "number" then
			return
		end
		-- 6.12: money that went down: a purchase (up is a sale or the stands' income: client/SandboxSounds.luau's)
		if money and state.money < money then
			play("purchase", Config.Soundscape.PurchaseVolume)
		end
		money = state.money
	end)
	local lastCoin = 0
	Net.get("Reward").OnClientEvent:Connect(function()
		if os.clock() - lastCoin > 0.2 then -- 5.7: the money a kill pays (server/Zombies.luau's KillReward) clinks, quieter
			lastCoin = os.clock()
			play("coin", JUICE.CoinVolume * 0.6, 1.08)
		end
	end)
	local lastNotice = 0
	Net.get("Notice").OnClientEvent:Connect(function()
		-- 8.9: a sound of its own may answer it (Sounds.answered: a piece given to Danny, an order, a trade's): its
		-- notify waits NoticeWait s for that and is left out then
		local at = os.clock()
		task.delay(Config.Soundscape.NoticeWait, function()
			local answered = Sounds.answered
			if answered then
				local ok, yes = pcall(answered, at)
				if ok and yes == true then
					return
				end
			end
			if os.clock() - lastNotice > 1.2 then
				lastNotice = os.clock()
				play("notify", 0.5)
			end
		end)
	end)
	Ui.onClick = function()
		play("ui_click", 0.5)
	end
end

-- ── The world's loops, the knocks, the ding ─────────────────────────────────

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

-- (6.16: the zombies' groans are client/ZombieLife.luau's: the nearest few, each its own voice)

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
	-- A jump of many studs in a tenth of a second: a run's fade (there and back) took you there.
	if was and (position - was).Magnitude > 40 and os.clock() - spawnedAt > 3 then
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
	elseif not sheet4 then
		print("[Sounds] 7.1: art/audio/sfx4.ogg is not uploaded yet (SoundSheet.Sfx4Id): stand-ins play (art/audio/NAHRAT-SFX4.md)")
	elseif not sheet5 then
		print("[Sounds] 8.9: art/audio/sfx5.ogg is not uploaded yet (SoundSheet.Sfx5Id): stand-ins play (art/audio/NAHRAT-SFX5.md)")
	elseif not sheet6 then
		print("[Sounds] 10.1: art/audio/sfx6.ogg is not uploaded yet (SoundSheet.Sfx6Id): stand-ins play (art/audio/NAHRAT-SFX6.md)")
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
	listenHits()
	listenGame()
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
		sheet4 = enabled and sheet4, -- 8.1: the sandbox's loops or their stand-ins
	})
	-- 7.1: the move's sounds from what the move already sends (client/MoveSounds.luau)
	MoveSounds.start({
		play = play,
		make = make,
		on = function(): boolean
			return enabled and mode ~= 3
		end,
	})
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.1)
			tick += 1
			if enabled then
				elevator()
			end
			if tick % 10 == 0 then
				pickMusic()
			end
		end
	end)
end

return Sounds
