-- The game's sounds (shared/SoundSheet.luau, made by art/audio/make_audio.py) and Config.Audio. Run with
-- tests/run_tests.py.
local Config = require("./Config")
local SoundSheet = require("./SoundSheet")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- Every sound the client plays by name.
local USED = {
	"gun_light", "gun_crack", "gun_heavy", "gun_rapid", "gun_launch", "explosion", "hit", "headshot", "kill",
	"pickup", "putdown", "load", "cash", "job_done", "job_fail", "level_up", "wave", "ui_click", "ui_open", "notify",
	"horn", "ding", "zombie_a", "zombie_b", "engine",
}
for _, name in USED do
	check("sfx region " .. name, SoundSheet.Sfx[name] ~= nil)
end
-- 5.7: the world's sounds (sfx2.ogg), their own sheet.
local USED2 = {
	"knock", "door_creak", "zip", "scooter", "freewheel", "bus_brake", "bus_door", "phone_buzz", "step_a", "step_b",
	"coin", "ambience", "wind",
}
for _, name in USED2 do
	check("sfx2 region " .. name, SoundSheet.Sfx2[name] ~= nil)
	check("sfx2 " .. name .. " is not also in sfx", SoundSheet.Sfx[name] == nil)
end
for _, name in { "zip", "scooter", "freewheel", "ambience", "wind" } do
	check(name .. " loops", SoundSheet.Looped[name] == true)
end
check("the second sheet's id is a string", type(SoundSheet.Sfx2Id) == "string")
-- 6.12: the doors, the horns, the footsteps by surface, the splash, the ambience and the UI stings (sfx3.ogg).
local USED3 = {
	"car_door_open", "car_door_close", "van_back_open", "van_back_close", "van_roll_up", "van_roll_down",
	"horn_car", "horn_van", "horn_truck", "bike_bell", "scooter_beep",
	"step_concrete_a", "step_concrete_b", "step_grass_a", "step_grass_b", "step_wood_a", "step_wood_b",
	"step_metal_a", "step_metal_b", "step_water_a", "step_water_b", "splash",
	"amb_day", "amb_night", "amb_roof", "amb_fountain",
	"task_done", "purchase", "event_start", "event_end",
}
for _, name in USED3 do
	check("sfx3 region " .. name, SoundSheet.Sfx3[name] ~= nil)
	check("sfx3 " .. name .. " is in no other sheet", SoundSheet.Sfx[name] == nil and SoundSheet.Sfx2[name] == nil)
end
for _, name in { "amb_day", "amb_night", "amb_roof", "amb_fountain" } do
	check(name .. " loops", SoundSheet.Looped[name] == true and SoundSheet.Sfx3[name][2] >= 4)
end
for _, name in { "car_door_open", "car_door_close", "horn_car", "step_concrete_a", "splash", "task_done", "event_start" } do
	check(name .. " does not loop", SoundSheet.Looped[name] == nil)
end
check("the third sheet's id is a string", type(SoundSheet.Sfx3Id) == "string")
check("the third sheet is an asset id or empty", SoundSheet.Sfx3Id == "" or string.match(SoundSheet.Sfx3Id, "^rbxassetid://%d+$") ~= nil, SoundSheet.Sfx3Id)
for _, name in { "menu", "day", "night", "tension" } do
	check("music loop " .. name, SoundSheet.Music[name] ~= nil and SoundSheet.Music[name][2] > 10)
end
for id, sound in Config.Audio.WeaponSounds do
	check(`weapon sound {id} exists`, SoundSheet.Sfx[sound] ~= nil, sound)
end
local weapons = 0
for _, def in Config.Weapons do
	weapons += 1
	check(`weapon {def.id} has a sound`, Config.Audio.WeaponSounds[def.id] ~= nil)
end
for _, def in Config.CarGuns do
	check(`car gun {def.id} has a sound`, Config.Audio.WeaponSounds[def.id] ~= nil)
end
check("weapons listed", weapons > 0)
-- The regions never overlap (each plays only its own sound).
for _, sheet in { SoundSheet.Sfx, SoundSheet.Music, SoundSheet.Sfx2, SoundSheet.Sfx3 } do
	local list = {}
	for name, r in sheet do
		check(`region {name} is valid`, r[1] >= 0 and r[2] > 0)
		table.insert(list, r)
	end
	table.sort(list, function(a, b)
		return a[1] < b[1]
	end)
	for i = 2, #list do
		check("regions do not overlap", list[i - 1][1] + list[i - 1][2] <= list[i][1] + 1e-6)
	end
end
check("engine loops", SoundSheet.Looped.engine == true)
check("volumes in range", Config.Audio.MusicVolume > 0 and Config.Audio.MusicVolume <= 1 and Config.Audio.EffectsVolume <= 1)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
