-- 6.12, what the world sounds like where you are (shared/SoundPlan.luau): the footsteps' surface by the material and
-- the place (the park's lawns, the pond, the river), the horns by vehicle, the back's sounds, the ambience by the
-- clock and the height; every name it gives has its region in SoundSheet.Sfx3. In the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local SoundSheet = require("./SoundSheet")
local SoundPlan = require("./SoundPlan")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local S = Config.Soundscape
local park = Map.Park

-- ── Surfaces ────────────────────────────────────────────────────────────────
check("asphalt is concrete", SoundPlan.surface("Asphalt", 300, 0.4, 300) == "concrete")
check("a sidewalk is concrete", SoundPlan.surface("Concrete", 300, 0.9, 300) == "concrete")
check("an unknown material is concrete", SoundPlan.surface("Neon", 300, 1, 300) == "concrete")
check("grass is grass", SoundPlan.surface("Grass", 300, 1, 300) == "grass")
check("snow crunches like grass", SoundPlan.surface("Snow", 300, 1, 300) == "grass")
check("planks are wood", SoundPlan.surface("WoodPlanks", 300, 1, 300) == "wood")
check("a diamond plate is metal", SoundPlan.surface("DiamondPlate", 300, 40, 300) == "metal")
check("a metal ladder is metal", SoundPlan.surface("Metal", 300, 40, 300) == "metal")
check("terrain water is water", SoundPlan.surface("Water", 300, 0, 300) == "water")
for _, surface in SoundPlan.Surfaces do
	check(`{surface} has a volume`, type(S.StepVolume[surface]) == "number" and S.StepVolume[surface] > 0 and S.StepVolume[surface] <= 1.5)
end
for material, surface in S.Materials do
	check(`material {material} → a known surface`, table.find(SoundPlan.Surfaces, surface) ~= nil, surface)
end

-- The park: a lawn between two paths is grass (its slab is concrete), the paths, the ring and the walk round the
-- block are not, the island's lawn is (its stone is slate), the fountain's basin is not.
local lawnX, lawnZ = park.x + 30, park.z + 12 -- between the east path and the south-east corner path
check("the park's lawn is grass", SoundPlan.surface("Concrete", lawnX, Map.WalkTop, lawnZ) == "grass")
check("the park's lawn: parkLawn", SoundPlan.parkLawn(lawnX, lawnZ))
check("the east path is not lawn", not SoundPlan.parkLawn(park.x + 30, park.z + 1))
check("a corner path is not lawn", not SoundPlan.parkLawn(park.x + 30, park.z + 30))
local ring = park.pond + 1.5 + park.ring / 2
check("the ring path is not lawn", not SoundPlan.parkLawn(park.x + ring, park.z + 6))
check("the walk round the block is not lawn", not SoundPlan.parkLawn(park.x + Map.BlockSize / 2 - 3, park.z + 20))
check("off the park is not lawn", not SoundPlan.parkLawn(park.x + Map.BlockSize, park.z + 12))
check("the island's lawn is grass", SoundPlan.surface("Slate", park.x + 4.5, Map.WalkTop + 0.3, park.z) == "grass")
check("the fountain's basin is not lawn", not SoundPlan.parkLawn(park.x + 1, park.z + 1))
check("the coping is stone", SoundPlan.surface("Slate", park.x + park.pond + 0.6, 1.6, park.z) == "concrete")
check("a street's concrete elsewhere stays concrete", SoundPlan.surface("Concrete", lawnX + Map.Cell, Map.WalkTop, lawnZ) == "concrete")
check("the bridge's planks are wood", SoundPlan.surface("WoodPlanks", park.x, Map.WalkTop + 1.3, park.z + 14) == "wood")

-- Water: the pond (its top the ground's 0), the river and the sea (Map.WaterLevel); dry over them.
check("the pond's water top", SoundPlan.waterTop(park.x + 10, park.z) == 0)
check("no water on the lawn", SoundPlan.waterTop(lawnX, lawnZ) == nil)
check("wading in the pond", SoundPlan.inWater(park.x + 12, -3, park.z))
check("the pond floor's mud is water", SoundPlan.surface("Mud", park.x + 12, -3.5, park.z) == "water")
check("on the island: dry", not SoundPlan.inWater(park.x + 3, Map.WalkTop + 0.3, park.z))
check("on the footbridge: dry", not SoundPlan.inWater(park.x, Map.WalkTop + 1.3, park.z + 14))
local riverX = (Map.River.x0 + Map.River.x1) / 2
check("the river's top", SoundPlan.waterTop(riverX, 0) == Map.WaterLevel)
check("swimming in the river", SoundPlan.inWater(riverX, Map.WaterLevel - 2, 0))
check("on a bridge over the river: dry", not SoundPlan.inWater(riverX, 1, 0.5 * Map.Cell))
check("the sea", SoundPlan.inWater(Map.Sea.x0 + 50, Map.WaterLevel - 1, 0))

-- The steps' names: a and b in turn, every one in the sheet.
for _, surface in SoundPlan.Surfaces do
	for _, left in { true, false } do
		local name = SoundPlan.stepName(surface, left)
		check(`{name} has its region`, SoundSheet.Sfx3[name] ~= nil)
	end
	check(`{surface}: the feet differ`, SoundPlan.stepName(surface, true) ~= SoundPlan.stepName(surface, false))
end

-- ── Horns ───────────────────────────────────────────────────────────────────
local carsSeen = 0
for _, def in Config.Cars do
	carsSeen += 1
	local name = SoundPlan.horn(def.id, def.bike == true, def.stand == true)
	check(`{def.id}'s horn {name} has its region`, SoundSheet.Sfx3[name] ~= nil, name)
	if def.stand then
		check(`{def.id} beeps`, name == "scooter_beep")
	elseif def.bike then
		check(`{def.id} rings`, name == "bike_bell")
	else
		check(`{def.id} has a class horn`, S.Horns[def.id] ~= nil and name == S.Horns[def.id])
	end
end
check("cars seen", carsSeen > 10)
check("an unknown vehicle honks like a car", SoundPlan.horn("nope", false, false) == "horn_car")
check("no car id honks like a car", SoundPlan.horn(nil, false, false) == "horn_car")
check("the van and the truck differ", SoundPlan.horn("van", false, false) ~= SoundPlan.horn("boxtruck", false, false))
for id, name in S.Horns do
	check(`horn of {id} exists`, SoundSheet.Sfx3[name] ~= nil, name)
end

-- ── Doors and backs ─────────────────────────────────────────────────────────
check("two rear doors swing", SoundPlan.backKind("Y", 0) == "swing")
check("a roll-up door rolls (hinged at its top)", SoundPlan.backKind("X", 4.1) == "rollup")
check("a tailgate drops (hinged at its bottom)", SoundPlan.backKind("X", -0.8) == "gate")
check("a trunk lid (hinged at its front edge, flat)", SoundPlan.backKind("X", 0.06) == "gate")
for _, what in { "door", "swing", "rollup", "gate" } do
	local any = false
	for _, moment in { "opening", "closing", "shut" } do
		local name, pitch = SoundPlan.swingSound(what, moment)
		if name then
			any = true
			check(`{what} {moment}: {name} has its region`, SoundSheet.Sfx3[name] ~= nil)
			check(`{what} {moment}: pitch`, pitch > 0.5 and pitch <= 1.2, pitch)
		end
	end
	check(`{what} makes a sound`, any)
	local opened = SoundPlan.swingSound(what, "opening")
	check(`{what} sounds as it opens`, opened ~= nil)
	local closed = SoundPlan.swingSound(what, "closing") or SoundPlan.swingSound(what, "shut")
	check(`{what} sounds as it shuts`, closed ~= nil)
end
check("nothing for an unknown swing", SoundPlan.swingSound("nope", "opening") == nil)

-- ── Ambience ────────────────────────────────────────────────────────────────
check("street level: no roof wind", SoundPlan.roofShare(1) == 0)
check("high up: full roof wind", SoundPlan.roofShare(S.RoofFull + 10) == 1)
check("half way up", math.abs(SoundPlan.roofShare((S.RoofFrom + S.RoofFull) / 2) - 0.5) < 1e-6)
local noon = SoundPlan.ambience(Map.nightFactor(12), 1, true)
local midnight = SoundPlan.ambience(Map.nightFactor(0), 1, true)
local dusk = SoundPlan.ambience(Map.nightFactor(Config.DayNight.NightFrom), 1, true)
check("noon: the day's loop", math.abs(noon.day - S.Day) < 1e-6 and noon.night == 0)
check("midnight: the night's loop", math.abs(midnight.night - S.Night) < 1e-6 and midnight.day == 0)
check("dusk: both, half way", dusk.day > 0 and dusk.night > 0)
check("with sfx3 the 5.7 hum and wind rest", noon.hum == 0 and noon.wind == 0 and midnight.hum == 0)
local roofNoon = SoundPlan.ambience(0, S.RoofFull + 5, true)
check("on a roof the wind rises", math.abs(roofNoon.roof - S.Roof) < 1e-6 and noon.roof == 0)
check("on a roof the street quiets", roofNoon.day < noon.day and roofNoon.day > 0)
local old = SoundPlan.ambience(0, 1, false)
local oldNight = SoundPlan.ambience(1, 1, false)
check("without sfx3: the 5.7 levels by day", old.hum == Config.Juice.AmbienceDay and old.wind == Config.Juice.WindDay and old.day == 0)
check("without sfx3: the 5.7 levels by night", oldNight.hum == Config.Juice.AmbienceNight and oldNight.wind == Config.Juice.WindNight)
check("without sfx3: more wind on a roof", SoundPlan.ambience(0, S.RoofFull, false).wind > old.wind)
for _, mix in { noon, midnight, dusk, roofNoon, old, oldNight } do
	for key, value in mix :: any do
		check(`ambience {key} in 0 … 1`, value >= 0 and value <= 1, value)
	end
end
for _, name in { "amb_day", "amb_night", "amb_roof", "amb_fountain" } do
	check(name .. " loops", SoundSheet.Looped[name] == true and SoundSheet.Sfx3[name] ~= nil)
end

-- ── 7.1: the move's sounds ───────────────────────────────────────────────────
-- (states shaped as server/Moving.luau's viewFor: what SoundPlan reads of them)
local MV = S.Move
local function piece(spot: number, props: { [string]: any }): { [string]: any }
	local item: { [string]: any } = { spot = spot, name = "Armchair", icon = "🪑", class = "both", state = "home", condition = 1, broken = false, fragile = false, mine = false }
	for key, value in props do
		item[key] = value
	end
	return item
end
local function state(props: { [string]: any }, items: { any }?): { [string]: any }
	local view: { [string]: any } = { id = 7, seconds = 600, endsAt = 1000 + 600, horde = false, backOpen = false, inside = false, items = items or {}, team = { role = "driver" } }
	for key, value in props do
		view[key] = value
	end
	return view
end
local function names(cues: { SoundPlan.Cue }): string
	local list = {}
	for _, c in cues do
		check(`cue {c.name} has its region`, SoundSheet.Sfx4[c.name] ~= nil)
		check(`cue {c.name}: volume and pitch`, c.volume > 0 and c.volume <= 1 and c.pitch > 0.5 and c.pitch < 1.5, `{c.volume} {c.pitch}`)
		table.insert(list, c.name)
	end
	return table.concat(list, ",")
end
local base = state({})
check("a new move starts with its sting", names(SoundPlan.moveCues(nil, base, 1000 + 2)) == "move_start")
check("joining a move half way: no sting", names(SoundPlan.moveCues(nil, base, 1000 + 300)) == "")
check("another move's state is a new move", names(SoundPlan.moveCues(state({ id = 6 }), base, 1000 + 1)) == "move_start")
check("nothing changed: nothing plays", names(SoundPlan.moveCues(base, state({}), 1000 + 30)) == "")
check("the move over: nothing (its result plays)", names(SoundPlan.moveCues(base, nil, 1000 + 30)) == "")
check("the horde comes: the siren", names(SoundPlan.moveCues(base, state({ horde = true }), 1000 + 420)) == "horde_siren")
check("the horde stays: once", names(SoundPlan.moveCues(state({ horde = true }), state({ horde = true }), 1000 + 421)) == "")
local opened = SoundPlan.moveCues(base, state({ backOpen = true }), 1000 + 30)
check("the truck's back opens", names(opened) == "truck_ramp" and opened[1].pitch == 1)
local shut = SoundPlan.moveCues(state({ backOpen = true }), base, 1000 + 30)
check("… and shuts lower", names(shut) == "truck_ramp" and shut[1].pitch == MV.RampShut)
check("in through the house's door", names(SoundPlan.moveCues(base, state({ inside = true }), 1000 + 30)) == "house_door_creak")
local out = SoundPlan.moveCues(state({ inside = true }), base, 1000 + 30)
check("… and out", names(out) == "house_door_creak" and out[1].pitch == MV.DoorOut)
-- the pieces
local carried = state({}, { piece(1, { state = "carried", mine = true }), piece(2, { state = "carried" }) })
local loaded = SoundPlan.moveCues(carried, state({}, { piece(1, { state = "truck" }), piece(2, { state = "carried" }) }), 1000 + 30)
check("your piece into the truck", names(loaded) == "truck_load" and loaded[1].volume == MV.Load)
local crewLoad = SoundPlan.moveCues(carried, state({}, { piece(1, { state = "carried", mine = true }), piece(2, { state = "truck" }) }), 1000 + 30)
check("a crew mate's: quieter", names(crewLoad) == "truck_load" and crewLoad[1].volume == MV.LoadCrew)
local both = SoundPlan.moveCues(carried, state({}, { piece(1, { state = "truck" }), piece(2, { state = "truck" }) }), 1000 + 30)
check("two at once: one load, the louder", names(both) == "truck_load" and both[1].volume == MV.Load)
local glass = SoundPlan.moveCues(carried, state({}, { piece(1, { state = "carried", mine = true, fragile = true, broken = true, condition = 0.1 }), piece(2, { state = "carried" }) }), 1000 + 30)
check("a fragile piece breaks: glass", names(glass) == "glass_break" and glass[1].volume == MV.Break)
local smashed = SoundPlan.moveCues(carried, state({}, { piece(1, { state = "carried", mine = true }), piece(2, { state = "ground", broken = true, condition = 0.1 }) }), 1000 + 30)
check("a crew mate's chair breaks: a crash, quieter", names(smashed) == "heavy_drop" and smashed[1].volume == MV.BreakCrew)
local jolt = SoundPlan.moveCues(carried, state({}, { piece(1, { state = "carried", mine = true, condition = 1 - MV.Jolt - 0.01 }), piece(2, { state = "carried" }) }), 1000 + 30)
check("a hard knock in your hands: a thud", names(jolt) == "heavy_drop" and jolt[1].volume == MV.JoltVolume)
check("a small knock: nothing", names(SoundPlan.moveCues(carried, state({}, { piece(1, { state = "carried", mine = true, condition = 1 - MV.Jolt / 2 }), piece(2, { state = "carried" }) }), 1000 + 30)) == "")
check("a crew mate's knock: nothing", names(SoundPlan.moveCues(carried, state({}, { piece(1, { state = "carried", mine = true }), piece(2, { state = "carried", condition = 0.5 }) }), 1000 + 30)) == "")
check("broken already: once", names(SoundPlan.moveCues(state({}, { piece(1, { broken = true }) }), state({}, { piece(1, { broken = true, condition = 0 }) }), 1000 + 30)) == "")
check("junk in a state is skipped", names(SoundPlan.moveCues(state({ items = { 1, "x" } }), state({ items = { false, { spot = "a" } } }), 1000 + 30)) == "")
-- your hands
check("a moving box rustles", SoundPlan.isBox({ name = "Moving Box", icon = "📦" }))
check("a box of dishes rustles", SoundPlan.isBox({ name = "Box of Dishes", icon = "🥣" }))
check("a toolbox is not cardboard", not SoundPlan.isBox({ name = "Toolbox", icon = "🧰" }))
check("an armchair is not a box", not SoundPlan.isBox(piece(1, {})))
check("nothing is not a box", not SoundPlan.isBox(nil))
check("a lift", SoundPlan.carryCue(piece(1, {}), true).name == "furniture_pickup")
check("a put-down", SoundPlan.carryCue(piece(1, {}), false).name == "furniture_putdown")
check("a box either way", SoundPlan.carryCue({ name = "Moving Box" }, true).name == "cardboard_box" and SoundPlan.carryCue({ name = "Moving Box" }, false).name == "cardboard_box")
check("an unknown piece lifts as furniture", SoundPlan.carryCue(nil, true).name == "furniture_pickup")
for _, up in { true, false } do
	check("the hands' cues have regions", SoundSheet.Sfx4[SoundPlan.carryCue(piece(1, {}), up).name] ~= nil)
end
check("moveItem finds the spot", SoundPlan.moveItem(carried, 2) ~= nil and SoundPlan.moveItem(carried, 2).spot == 2)
check("moveItem: no spot, no piece", SoundPlan.moveItem(carried, nil) == nil and SoundPlan.moveItem(nil, 1) == nil and SoundPlan.moveItem(carried, 9) == nil)
-- the drag
local alone = state({}, { piece(3, { class = "pair", state = "carried", by = "Pavel", mine = true }) })
check("a two-person piece alone is dragged", SoundPlan.dragged(alone, 3))
check("… not with a helper", not SoundPlan.dragged(state({}, { piece(3, { class = "pair", state = "carried", by = "Pavel + Danny", mine = true }) }), 3))
check("… not by a Mover (held up)", not SoundPlan.dragged(state({ team = { role = "mover" } }, alone.items), 3))
check("a one-person piece is carried", not SoundPlan.dragged(state({}, { piece(3, { class = "both", state = "carried", by = "Pavel", mine = true }) }), 3))
check("nothing in your hands: no drag", not SoundPlan.dragged(alone, nil) and not SoundPlan.dragged(nil, 3))
check("the drag's loop is a loop", SoundSheet.Looped.wood_scrape_loop == true)
-- the end
local gate = SoundPlan.resultCue({ how = "done" })
check("delivered: the Wall's gate", gate ~= nil and gate.name == "checkpoint_gate" and SoundSheet.Sfx4[gate.name] ~= nil)
check("late: the gate too", SoundPlan.resultCue({ how = "late" }) ~= nil)
check("lost or called off: no gate", SoundPlan.resultCue({ how = "failed" }) == nil and SoundPlan.resultCue({ how = "cancelled" }) == nil and SoundPlan.resultCue(nil) == nil)
for key, value in MV do
	check(`Config.Soundscape.Move.{key} is a sane number`, type(value) == "number" and value >= 0 and value <= 60, value)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
