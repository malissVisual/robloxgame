--!strict
-- Sounds. The ids here are Roblox's BUILT-IN sounds (rbxasset://sounds/...; swoosh.wav is not allowed for games,
-- so it is not used), so everything works without
-- uploading anything; replace any id with your own "rbxassetid://..." to change a sound. `Music` is empty
-- by default (no built-in music exists): put a music asset id there and it plays in a loop.
-- Every entry: the sound id, its volume and its playback speed (pitch).

export type Def = { id: string, volume: number, speed: number }

local Sounds = {}

Sounds.Defs = {
	click = { id = "rbxasset://sounds/button.wav", volume = 0.4, speed = 1 },
	summonStart = { id = "rbxasset://sounds/snap.mp3", volume = 0.3, speed = 0.9 }, -- the altar fires
	summonCard = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.28, speed = 0.75 }, -- one per card, climbing a little (soft and low)
	summonRare = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.4, speed = 1.0 }, -- a level 4+ card
	merge = { id = "rbxasset://sounds/snap.mp3", volume = 0.7, speed = 1 },
	mergeBig = { id = "rbxasset://sounds/snap.mp3", volume = 0.9, speed = 0.7 }, -- level 5 and up
	levelUp = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, speed = 1.4 },
	coins = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, speed = 1.2 },
	fight = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, speed = 0.6 },
	spell = { id = "rbxasset://sounds/snap.mp3", volume = 0.7, speed = 1.4 },
	impact = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, speed = 0.8 },
	hit = { id = "rbxasset://sounds/collide.wav", volume = 0.15, speed = 1.3 },
	boss = { id = "rbxasset://sounds/bass.wav", volume = 1, speed = 0.7 },
	elite = { id = "rbxasset://sounds/bass.wav", volume = 0.8, speed = 1.1 },
	won = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.9, speed = 1.1 },
	lost = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.8, speed = 1 },
	teleport = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, speed = 1.8 },
	error = { id = "rbxasset://sounds/button.wav", volume = 0.5, speed = 0.6 },
} :: { [string]: Def }

Sounds.Music = "" -- e.g. "rbxassetid://1234567890"; empty = no music
Sounds.MusicVolume = 0.25

return Sounds
