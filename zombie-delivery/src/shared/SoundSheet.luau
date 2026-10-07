--!strict
-- The game's own sounds (art/audio/make_audio.py writes this file): two audio assets, sfx.ogg and music.ogg,
-- and where each sound / music loop sits in them (start, length in seconds; client/Sounds.luau plays the region).
-- Upload art/audio/sfx.ogg and art/audio/music.ogg (Asset Manager → Import) and paste the ids below.
-- 5.7: art/audio/sfx2.ogg holds the world's sounds (Sfx2); until its id is pasted, those play a stand-in from
-- Sfx or stay silent (client/Sounds.luau).

local SoundSheet = {}

SoundSheet.SfxId = "rbxassetid://108821829330157" -- "rbxassetid://…" of art/audio/sfx.ogg
SoundSheet.MusicId = "rbxassetid://71392718953355" -- "rbxassetid://…" of art/audio/music.ogg
SoundSheet.Sfx2Id = "" -- "rbxassetid://…" of art/audio/sfx2.ogg

SoundSheet.Sfx = {
	gun_light = { 0.0, 0.349977 },
	gun_crack = { 0.649977, 0.55 },
	gun_heavy = { 1.499977, 0.6 },
	gun_rapid = { 2.399977, 0.14 },
	gun_launch = { 2.839977, 0.5 },
	explosion = { 3.639977, 1.6 },
	hit = { 5.539977, 0.05 },
	headshot = { 5.889977, 0.45 },
	kill = { 6.639977, 0.25 },
	pickup = { 7.189977, 0.16 },
	putdown = { 7.649977, 0.2 },
	load = { 8.149977, 0.23 },
	cash = { 8.679977, 0.62 },
	job_done = { 9.599977, 1.399977 },
	job_fail = { 11.299955, 1.2 },
	level_up = { 12.799955, 1.9 },
	wave = { 14.999955, 1.2 },
	ui_click = { 16.499955, 0.03 },
	ui_open = { 16.829955, 0.09 },
	notify = { 17.219955, 0.4 },
	horn = { 17.919955, 0.6 },
	ding = { 18.819955, 1.0 },
	zombie_a = { 20.119955, 1.3 },
	zombie_b = { 21.719955, 1.1 },
	engine = { 23.119955, 1.0 },
} :: { [string]: { number } }

SoundSheet.Music = {
	menu = { 0.0, 24.0 },
	day = { 24.5, 20.869546 },
	night = { 45.869546, 27.428571 },
	tension = { 73.798118, 17.142857 },
} :: { [string]: { number } }

SoundSheet.Sfx2 = {
	knock = { 0.0, 0.62 },
	door_creak = { 0.92, 0.9 },
	zip = { 2.12, 1.0 },
	scooter = { 3.42, 1.0 },
	freewheel = { 4.72, 1.0 },
	bus_brake = { 6.02, 1.7 },
	bus_door = { 8.02, 0.75 },
	phone_buzz = { 9.07, 0.52 },
	step_a = { 9.89, 0.13 },
	step_b = { 10.32, 0.13 },
	coin = { 10.75, 0.6 },
	ambience = { 11.65, 8.0 },
	wind = { 19.95, 8.0 },
} :: { [string]: { number } }

-- Sounds that loop (their region repeats seamlessly).
SoundSheet.Looped = { ambience = true, engine = true, freewheel = true, scooter = true, wind = true, zip = true } :: { [string]: boolean }

return SoundSheet
