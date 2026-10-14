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
-- 7.1: the moves' sounds and the mountains' (sfx4.ogg): the furniture, the truck, the grip, the move's stings, the
-- horde's siren, the Wall's gate, a cuckoo clock, a cowbell, birdsong, the peaks' wind, a brook.
local USED4 = {
	"furniture_pickup", "furniture_putdown", "heavy_drop", "glass_break", "wood_scrape_loop", "cardboard_box",
	"truck_ramp", "truck_load", "strap_tighten", "house_door_creak", "grip_tick", "grip_warning", "grip_slip",
	"move_start", "move_success", "move_fail", "horde_siren", "checkpoint_gate", "cuckoo", "cowbell",
	"birds_alpine_loop", "wind_peaks_loop", "stream_loop",
	-- 8.1, at its end: the sandbox's (the stands, the till, the trip home, the Sprinter, the meadow, the hall, the room)
	"stand_display", "stand_takedown", "sale_register", "stored_fanfare", "van_slide_open", "van_slide_close",
	"sprinter_back_open", "sprinter_back_close", "van_step_up", "cowbell_far", "amb_alpine", "amb_warehouse", "amb_room",
}
local in4 = 0
for _ in SoundSheet.Sfx4 do
	in4 += 1
end
check(`sfx4 holds the {#USED4} sounds (7.1's 23 and 8.1's 13)`, in4 == #USED4, in4)
local LOOPS4 = { wood_scrape_loop = 2, birds_alpine_loop = 6, wind_peaks_loop = 6, stream_loop = 6, amb_alpine = 20, amb_warehouse = 8, amb_room = 8 }
for _, name in USED4 do
	local r = SoundSheet.Sfx4[name]
	check("sfx4 region " .. name, r ~= nil)
	if r then
		local loops = LOOPS4[name]
		if loops then
			check(name .. " loops, long enough not to be heard repeating", SoundSheet.Looped[name] == true and r[2] >= loops, r[2])
		else
			check(name .. " is short and does not loop", SoundSheet.Looped[name] == nil and r[2] <= 4, r[2])
		end
	end
end
check("the grip's tick is a tick", SoundSheet.Sfx4.grip_tick ~= nil and SoundSheet.Sfx4.grip_tick[2] <= 0.1)
check("the fourth sheet's id is a string", type(SoundSheet.Sfx4Id) == "string")
check("the fourth sheet is an asset id or empty", SoundSheet.Sfx4Id == "" or string.match(SoundSheet.Sfx4Id, "^rbxassetid://%d+$") ~= nil, SoundSheet.Sfx4Id)

-- Every name in one sheet only (client/Sounds.luau looks in them in turn: a name in two would play the first one's).
local SHEETS: { [string]: { [string]: { number } } } = {
	sfx = SoundSheet.Sfx, music = SoundSheet.Music, sfx2 = SoundSheet.Sfx2, sfx3 = SoundSheet.Sfx3, sfx4 = SoundSheet.Sfx4,
}
local seen: { [string]: string } = {}
for sheetName, sheet in SHEETS do
	for name in sheet do
		if sheetName ~= "music" then
			check(`{name} is in one sheet only`, seen[name] == nil, `{seen[name]} and {sheetName}`)
			seen[name] = sheetName
		end
	end
end
-- Every region inside its sheet (SoundSheet.Seconds: the .ogg's length).
for sheetName, sheet in SHEETS do
	local length = SoundSheet.Seconds[sheetName]
	check(`{sheetName}'s length is known`, type(length) == "number" and length > 0)
	for name, r in sheet do
		check(`{name} lies inside {sheetName}`, r[1] >= 0 and r[1] + r[2] <= (length or 0) + 1e-6, `{r[1] + r[2]} > {length}`)
	end
end

-- The stand-ins (SoundSheet.Fallback): each is for a sound of a later sheet, and plays (a stand-in's stand-in too, in
-- a few steps, no circle) from older sheets only, as it must while that sheet is not uploaded; a loop's is a loop.
local ORDER = { SoundSheet.Sfx, SoundSheet.Sfx2, SoundSheet.Sfx3, SoundSheet.Sfx4 }
local function sheetOf(name: string): number?
	for i, sheet in ORDER do
		if sheet[name] then
			return i
		end
	end
	return nil
end
local function resolve(name: string, upTo: number, steps: number): number?
	local i = sheetOf(name)
	if i and i <= upTo then
		return i
	end
	local standIn = SoundSheet.Fallback[name]
	if not standIn or steps >= 4 then
		return nil
	end
	return resolve(standIn, upTo, steps + 1)
end
local fallbacks = 0
for name, standIn in SoundSheet.Fallback do
	fallbacks += 1
	local own = sheetOf(name)
	check(`{name}'s stand-in is for a later sheet's sound`, own ~= nil and own > 1, own)
	if own then
		check(`{name} plays {standIn} until its sheet is up`, resolve(name, own - 1, 0) ~= nil, standIn)
	end
	if SoundSheet.Looped[name] then
		check(`{name} loops: its stand-in {standIn} loops too`, SoundSheet.Looped[standIn] == true)
	end
end
check("stand-ins listed", fallbacks >= 40, fallbacks)
check("the 5.7 stand-ins kept", SoundSheet.Fallback.coin == "cash" and SoundSheet.Fallback.knock == "putdown")
check("the 6.12 stand-ins kept", SoundSheet.Fallback.horn_van == "horn" and SoundSheet.Fallback.step_grass_b == "step_b" and SoundSheet.Fallback.task_done == "job_done")
-- 7.1: until sfx4.ogg is up every move's sound has a stand-in; the drag's scrape and the mountains' ambience wait.
-- 8.1: the sandbox's too, but for the chalet's room tone and the far cowbell.
local SILENT4 = { wood_scrape_loop = true, cuckoo = true, cowbell = true, birds_alpine_loop = true, amb_room = true, cowbell_far = true }
for _, name in USED4 do
	check(`{name}: {if SILENT4[name] then "silent" else "a stand-in"} until sfx4 is up`, (SoundSheet.Fallback[name] ~= nil) ~= (SILENT4[name] == true))
end
check("the house's door creaks like the 5.7 door", SoundSheet.Fallback.house_door_creak == "door_creak")
-- 8.1: the sandbox's. The 7.1 part of sfx4 stays where it was (its regions as before: the new ones come after it), the
-- feedback is short, the meadow's stand-in is a breeze (never the city's traffic, amb_day).
check("sfx4's 7.1 part where it was (furniture_pickup first, stream_loop last of it)", SoundSheet.Sfx4.furniture_pickup[1] == 0 and math.abs(SoundSheet.Sfx4.stream_loop[1] - 43.679932) < 1e-6)
for _, name in { "stand_display", "stand_takedown", "sale_register", "stored_fanfare", "van_slide_open", "van_slide_close", "sprinter_back_open", "sprinter_back_close", "van_step_up", "cowbell_far", "amb_alpine", "amb_warehouse", "amb_room" } do
	local r = SoundSheet.Sfx4[name]
	check(`8.1 {name} after sfx4's 7.1 part`, r ~= nil and r[1] >= SoundSheet.Sfx4.stream_loop[1] + SoundSheet.Sfx4.stream_loop[2])
end
for _, name in { "stand_display", "stand_takedown", "sale_register", "stored_fanfare", "van_slide_open", "van_slide_close", "sprinter_back_open", "sprinter_back_close", "van_step_up" } do
	check(`8.1 {name} is short feedback (at most 1.6 s)`, SoundSheet.Sfx4[name] ~= nil and SoundSheet.Sfx4[name][2] <= 1.6, SoundSheet.Sfx4[name] and SoundSheet.Sfx4[name][2])
end
check("8.1 the walk-in step is a step (at most 0.6 s)", SoundSheet.Sfx4.van_step_up[2] <= 0.6)
check("8.1 the meadow's stand-in is sfx2's breeze, a loop, not the city's traffic", SoundSheet.Fallback.amb_alpine == "wind" and SoundSheet.Looped.wind == true and SoundSheet.Fallback.amb_alpine ~= "amb_day")
check("8.1 the hall's stand-in is sfx2's hum, a loop", SoundSheet.Fallback.amb_warehouse == "ambience" and SoundSheet.Looped.ambience == true)
check("8.1 the till stands in with 6.12's purchase, the fanfare with task_done", SoundSheet.Fallback.sale_register == "purchase" and SoundSheet.Fallback.stored_fanfare == "task_done")
check("8.1 the Sprinter's back doors stand in with a van's", SoundSheet.Fallback.sprinter_back_open == "van_back_open" and SoundSheet.Fallback.sprinter_back_close == "van_back_close")
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
for _, sheet in { SoundSheet.Sfx, SoundSheet.Music, SoundSheet.Sfx2, SoundSheet.Sfx3, SoundSheet.Sfx4 } do
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
