--!strict
-- The game's own sounds (art/audio/make_audio.py writes this file): two audio assets, sfx.ogg and music.ogg,
-- and where each sound / music loop sits in them (start, length in seconds; client/Sounds.luau plays the region).
-- Upload art/audio/sfx.ogg and art/audio/music.ogg (Asset Manager → Import) and paste the ids below.
-- 5.7: art/audio/sfx2.ogg holds the world's sounds (Sfx2); until its id is pasted, those play a stand-in from
-- Sfx or stay silent (client/Sounds.luau).
-- 6.12: art/audio/sfx3.ogg holds the doors, the horns, the footsteps by surface, the splash, the ambience loops and
-- the UI stings (Sfx3); until its id is pasted, those play a stand-in from Sfx / Sfx2 or stay silent
-- (client/Sounds.luau FALLBACK; art/audio/NAHRAT-SFX3.md says how to upload it).

local SoundSheet = {}

SoundSheet.SfxId = "rbxassetid://108821829330157" -- "rbxassetid://…" of art/audio/sfx.ogg
SoundSheet.MusicId = "rbxassetid://71392718953355" -- "rbxassetid://…" of art/audio/music.ogg
SoundSheet.Sfx2Id = "rbxassetid://86322785000784" -- "rbxassetid://…" of art/audio/sfx2.ogg
SoundSheet.Sfx3Id = "" -- "rbxassetid://…" of art/audio/sfx3.ogg (6.12)

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

SoundSheet.Sfx3 = {
	car_door_open = { 0.0, 0.5 },
	car_door_close = { 0.8, 0.55 },
	van_back_open = { 1.65, 0.8 },
	van_back_close = { 2.75, 0.9 },
	van_roll_up = { 3.95, 0.85 },
	van_roll_down = { 5.1, 0.9 },
	horn_car = { 6.3, 0.42 },
	horn_van = { 7.02, 0.55 },
	horn_truck = { 7.87, 0.95 },
	bike_bell = { 9.12, 0.95 },
	scooter_beep = { 10.37, 0.24 },
	step_concrete_a = { 10.91, 0.2 },
	step_concrete_b = { 11.41, 0.2 },
	step_grass_a = { 11.91, 0.2 },
	step_grass_b = { 12.41, 0.2 },
	step_wood_a = { 12.91, 0.22 },
	step_wood_b = { 13.43, 0.22 },
	step_metal_a = { 13.95, 0.25 },
	step_metal_b = { 14.5, 0.25 },
	step_water_a = { 15.05, 0.32 },
	step_water_b = { 15.67, 0.32 },
	splash = { 16.29, 1.1 },
	amb_day = { 17.69, 12.0 },
	amb_night = { 29.99, 12.0 },
	amb_roof = { 42.29, 8.0 },
	amb_fountain = { 50.59, 6.0 },
	task_done = { 56.89, 0.95 },
	purchase = { 58.14, 0.8 },
	event_start = { 59.24, 1.5 },
	event_end = { 61.04, 1.2 },
} :: { [string]: { number } }

-- Sounds that loop (their region repeats seamlessly).
SoundSheet.Looped = { amb_day = true, amb_fountain = true, amb_night = true, amb_roof = true, ambience = true, engine = true, freewheel = true, scooter = true, wind = true, zip = true } :: { [string]: boolean }

return SoundSheet
