-- 6.12, what the world sounds like where you are (shared/SoundPlan.luau): the footsteps' surface by the material and
-- the place (the park's lawns, the pond, the river), the horns by vehicle, the back's sounds, the ambience by the
-- clock and the height; every name it gives has its region in SoundSheet.Sfx3. 8.0.1: in the sandbox
-- (Config.Sandbox.On) none of the city's places (no pond, river, sea or park lawn; client/SoundScape.luau's fountain
-- asks SoundPlan.cityPlaces too). 8.1, the sandbox's own: where you are (the meadow, a warehouse, the chalet), its
-- ambience (a calm alpine day, never the city's traffic; the hall's hum, the room's tone; their stand-ins), the far
-- cowbell, the collection's cues (on a stand, taken down, home), the income's clink (soft, not too often), the
-- Sprinter's sliding door, step and back doors, no ramp and no Wall's gate on a sandbox move. In the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local SoundSheet = require("./SoundSheet")
local SoundPlan = require("./SoundPlan")
local SandboxMap = require("./SandboxMap") -- (8.1: the sandbox's places)
local WarehouseLayout = require("./WarehouseLayout") -- (8.3: a warehouse at its level)

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
local sandboxOn = Config.Sandbox.On
Config.Sandbox.On = false -- (the city's places first; the sandbox's at the end)
check("the city: its places are there (SoundPlan.cityPlaces)", SoundPlan.cityPlaces())

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
for _, list in { Config.Cars, Config.AmbientCars } do -- (7.x: the ZDC Van and the bikes; the bodies nobody owns honk too)
	for _, def in list do
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

-- ── 8.0.1: the sandbox has none of the city's places ────────────────────────
-- Its Main Street runs over the park's (0, 0): no pond to wade or splash in there (nor a river or a sea), no park lawn
-- under its concrete pads, no fountain (SoundScape plays it only when SoundPlan.cityPlaces says so).
Config.Sandbox.On = true
check("the sandbox: no city places (no fountain at Map.Park)", not SoundPlan.cityPlaces())
check("… no pond's water at the park's middle (the sandbox's Main Street)", SoundPlan.waterTop(park.x + 10, park.z) == nil and not SoundPlan.inWater(park.x + 18.5, -0.1, park.z))
check("… steps where the pond was (the meadow by Main Street, its asphalt): grass and concrete, not water", SoundPlan.surface("Grass", park.x + 18.5, 0, park.z) == "grass" and SoundPlan.surface("Asphalt", park.x + 12, -3.5, park.z) == "concrete")
check("… no river, no sea", SoundPlan.waterTop(riverX, 0) == nil and SoundPlan.waterTop(Map.Sea.x0 + 50, 0) == nil)
check("… a plot's concrete where the park's lawn was: concrete", not SoundPlan.parkLawn(lawnX, lawnZ) and SoundPlan.surface("Concrete", -65, 0, -85) == "concrete")
check("… the materials still say their surface (terrain water, grass, planks)", SoundPlan.surface("Water", 0, 0, 0) == "water" and SoundPlan.surface("Grass", 0, 0, 0) == "grass" and SoundPlan.surface("WoodPlanks", 0, 0, 0) == "wood")

-- ── 8.1: the sandbox's own sounds ───────────────────────────────────────────
local SB = S.Sandbox
local function sfx4(name: string): boolean
	return SoundSheet.Sfx4[name] ~= nil
end
-- Where you are.
local plot = SandboxMap.Plots[1]
local w = plot.warehouse
local h = SandboxMap.House
check("the meadow is outdoors", SoundPlan.sandboxPlace(150, 2, 300, false) == "outdoors")
check("Main Street is outdoors", SoundPlan.sandboxPlace(0, 1, 200, false) == "outdoors")
check("in a warehouse's hall", SoundPlan.sandboxPlace(w.x + 10, 1, w.z, false) == "warehouse")
check("every plot's warehouse", (function(): boolean
	for _, p in SandboxMap.Plots do
		if SoundPlan.sandboxPlace(p.warehouse.x, 1, p.warehouse.z + 5, false) ~= "warehouse" then
			return false
		end
	end
	return true
end)())
check("the van's spot before the roller door is outdoors", SoundPlan.sandboxPlace(plot.vanSpot.x, 2, plot.vanSpot.z, false) == "outdoors")
-- 8.3: a plot's warehouse is the building of its level (levelOf: the client's workspace.Warehouses' Level<id>; nil, or
-- no levelOf: level 4, the building of before 8.3)
local garage = WarehouseLayout.site(plot, 1).warehouse
local centre = WarehouseLayout.site(plot, 5).warehouse
local function levelIs(n: number?): (number) -> number?
	return function(id: number): number?
		return if id == plot.id then n else nil
	end
end
local backZ = w.z - w.sz / 2 + 4 -- inside level 4's hall, near its back wall
local pastZ = w.z - w.sz / 2 - 6 -- behind level 4's back wall
check("8.3: the levels' halls: the garage inside level 4's, level 5's past its back wall", garage.sz < w.sz and centre.z - centre.sz / 2 < pastZ and backZ < garage.z - garage.sz / 2)
check("8.3: in a garage (level 1): the warehouse", SoundPlan.sandboxPlace(garage.x, 1, garage.z, false, levelIs(1)) == "warehouse")
check("… level 4's back of the hall, with a garage there: outdoors", SoundPlan.sandboxPlace(w.x, 1, backZ, false, levelIs(1)) == "outdoors")
check("… the same spot at level 4 (its level, nil, or no levelOf): the warehouse", SoundPlan.sandboxPlace(w.x, 1, backZ, false, levelIs(4)) == "warehouse"
	and SoundPlan.sandboxPlace(w.x, 1, backZ, false, levelIs(nil)) == "warehouse" and SoundPlan.sandboxPlace(w.x, 1, backZ, false) == "warehouse")
check("… behind level 4's back wall, in a Logistics Center (level 5): the warehouse; at level 4: outdoors", SoundPlan.sandboxPlace(w.x, 1, pastZ, false, levelIs(5)) == "warehouse"
	and SoundPlan.sandboxPlace(w.x, 1, pastZ, false) == "outdoors")
check("… over the garage's roof: outdoors (its top, not level 4's)", SoundPlan.sandboxPlace(garage.x, 1, garage.z, false, levelIs(1)) == "warehouse"
	and SoundPlan.sandboxPlace(garage.x, WarehouseLayout.outline(WarehouseLayout.site(plot, 1)).top + 3, garage.z, false, levelIs(1)) == "outdoors")
check("… another plot's level is its own (plot 1 a garage, plot 2 at level 4)", SoundPlan.sandboxPlace(SandboxMap.Plots[2].warehouse.x, 1, backZ, false, levelIs(1)) == "warehouse")
check("… a junk level (0, 9, NaN) is clamped or 4: never an error", SoundPlan.sandboxPlace(w.x, 1, backZ, false, levelIs(0)) == "outdoors"
	and SoundPlan.sandboxPlace(w.x, 1, pastZ, false, levelIs(9)) == "warehouse" and SoundPlan.sandboxPlace(w.x, 1, backZ, false, levelIs(0 / 0)) == "warehouse")
check("a plot's yard beside the hall is outdoors", SoundPlan.sandboxPlace(plot.spawn.x, 3, plot.spawn.z, false) == "outdoors")
check("in the move's house (its state's inside): the house", SoundPlan.sandboxPlace(150, 2, 300, true) == "house")
check("a move's interior far off the map: the house", SoundPlan.sandboxPlace(9000, 400, 9000, false) == "house")
check("in the chalet's own box: the house", SoundPlan.sandboxPlace(h.house.x, 3, h.house.z, false) == "house")
check("at the chalet's front door (where you come out): outdoors", SoundPlan.sandboxPlace(h.door.x, 1, h.door.z, false) == "outdoors")
-- The ambience: a calm alpine day outdoors, never the city's traffic.
local L = SoundPlan.SandboxLoops
check("the sandbox's outdoor loop is the meadow, not the city's traffic (amb_day) or night", L.alpine == "amb_alpine" and L.alpine ~= "amb_day" and L.alpine ~= "amb_night")
for part, name in L do
	check(`the sandbox's {part} loop {name} is in sfx4 and loops`, sfx4(name) and SoundSheet.Looped[name] == true)
end
-- (a stand-in's stand-in too: none on the way is the city's day or night)
local standIn: string? = L.alpine
local chain = {}
while standIn do
	table.insert(chain, standIn)
	check(`the meadow's stand-in chain: {standIn} is no city loop`, standIn ~= "amb_day" and standIn ~= "amb_night" and standIn ~= "ambience")
	standIn = SoundSheet.Fallback[standIn]
	if #chain > 4 then
		break
	end
end
check("the meadow stands in with a breeze until sfx4 is up", SoundSheet.Fallback[L.alpine] == "wind")
local out4, out3 = SoundPlan.sandboxAmbience("outdoors", true), SoundPlan.sandboxAmbience("outdoors", false)
check("outdoors: the meadow only", out4.alpine == SB.Alpine and out4.warehouse == 0 and out4.room == 0)
check("outdoors before sfx4: its breeze, quieter", out3.alpine == SB.AlpineStandIn and out3.alpine > 0 and out3.alpine < out4.alpine)
local hall = SoundPlan.sandboxAmbience("warehouse", true)
check("in a warehouse: its hall, the meadow faint through the door", hall.warehouse == SB.Warehouse and hall.alpine > 0 and hall.alpine < out4.alpine and hall.room == 0)
check("in a warehouse before sfx4: the hum's stand-in", SoundPlan.sandboxAmbience("warehouse", false).warehouse == SB.WarehouseStandIn)
local room = SoundPlan.sandboxAmbience("house", true)
check("in the house: the quiet room only", room.room == SB.Room and room.alpine == 0 and room.warehouse == 0)
check("in the house before sfx4: silence (no stand-in)", SoundPlan.sandboxAmbience("house", false).room == 0 and SoundSheet.Fallback[L.room] == nil)
for _, mix in { out4, out3, hall, room } do
	for key, value in mix :: any do
		check(`sandbox ambience {key} in 0 … 1`, value >= 0 and value <= 1, value)
	end
end
check("the warehouse's echo, none outdoors or in the house", SoundPlan.reverb("warehouse") == SB.Reverb.warehouse and SoundPlan.reverb("outdoors") == "NoReverb" and SoundPlan.reverb("house") == (SB.Reverb.house or "NoReverb"))
-- The far cowbell.
check("the cowbell's gaps", SoundPlan.cowbellGap(0) == SB.CowbellGap[1] and SoundPlan.cowbellGap(1) == SB.CowbellGap[2] and SoundPlan.cowbellGap(2) == SB.CowbellGap[2])
check("the cowbell rings now and then (20 s at least between two)", SB.CowbellGap[1] >= 20 and SB.CowbellGap[2] > SB.CowbellGap[1])
for _, r in { { 0, 0 }, { 0.3, 1 }, { 0.77, 0.5 } } do
	local x, z = SoundPlan.cowbellSpot(10, 20, r[1], r[2])
	local d = math.sqrt((x - 10) ^ 2 + (z - 20) ^ 2)
	check(`the cowbell far off ({math.floor(d)} studs)`, d >= SB.CowbellFar[1] - 1e-6 and d <= SB.CowbellFar[2] + 1e-6)
end
check("the far cowbell is in sfx4, short, not a loop", sfx4("cowbell_far") and SoundSheet.Looped.cowbell_far == nil and SoundSheet.Sfx4.cowbell_far[2] <= 4)
-- The collection's cues (the "Collection" remote's states, one after the other).
local function stock(list: { { any } }): { [string]: any }
	local out = {}
	for _, e in list do
		table.insert(out, { uid = e[1], item = "chair", stand = e[2] })
	end
	return { kind = "state", stock = out, income = 1, stands = 12 }
end
local function cueNames(cues: { SoundPlan.Cue }): string
	local list = {}
	for _, c in cues do
		check(`collection cue {c.name} has its region`, sfx4(c.name))
		check(`collection cue {c.name}: volume and pitch`, c.volume > 0 and c.volume <= 1 and c.pitch == 1)
		table.insert(list, c.name)
	end
	return table.concat(list, ",")
end
local s0 = stock({ { "1-1" }, { "1-2" } })
check("the first state: nothing", cueNames(SoundPlan.collectionCues(nil, s0)) == "")
check("nothing changed: nothing", cueNames(SoundPlan.collectionCues(s0, stock({ { "1-1" }, { "1-2" } }))) == "")
local shown = stock({ { "1-1", 3 }, { "1-2" } })
check("a piece put on a stand: the thunk and the sparkle", cueNames(SoundPlan.collectionCues(s0, shown)) == "stand_display")
check("moved to another stand: the same", cueNames(SoundPlan.collectionCues(shown, stock({ { "1-1", 7 }, { "1-2" } }))) == "stand_display")
check("taken down", cueNames(SoundPlan.collectionCues(shown, s0)) == "stand_takedown")
local home = stock({ { "1-1" }, { "1-2" }, { "1-3" }, { "1-4" } })
check("pieces came home: the fanfare (once)", cueNames(SoundPlan.collectionCues(s0, home)) == "stored_fanfare")
check("… not right after the move's result card (its own jingle)", cueNames(SoundPlan.collectionCues(s0, home, SB.StoredQuiet / 2)) == "")
check("… but a while after it", cueNames(SoundPlan.collectionCues(s0, home, SB.StoredQuiet + 1)) == "stored_fanfare")
check("sold (gone from the stock): nothing here (the till plays from \"sold\")", cueNames(SoundPlan.collectionCues(shown, stock({ { "1-2" } }))) == "")
check("a uid as a number", cueNames(SoundPlan.collectionCues(stock({ { 5 } }), stock({ { 5, 1 } }))) == "stand_display")
check("junk is skipped", cueNames(SoundPlan.collectionCues({ stock = { 1, "x", { uid = {} } } }, { stock = "nope" })) == "" and cueNames(SoundPlan.collectionCues(5, s0)) == "")
-- The income's clink: the stands' money coming in, softly, not too often.
local G = SB.IncomeGap
check("the income clinks", SoundPlan.incomeClink(12, 100, 100 - G, -math.huge, false, true))
check("… at most once every IncomeGap s", not SoundPlan.incomeClink(12, 100, 100 - G + 0.5, -math.huge, false, true) and G >= 10)
check("… not with the warehouse's window open", not SoundPlan.incomeClink(12, 100, -math.huge, -math.huge, true, true))
check("… not right after a sale (its money)", not SoundPlan.incomeClink(300, 100, -math.huge, 100 - SB.SoldQuiet / 2, false, true))
check("… nor with nothing on show", not SoundPlan.incomeClink(12, 100, -math.huge, -math.huge, false, false))
check("… nor money going down", not SoundPlan.incomeClink(-40, 100, -math.huge, -math.huge, false, true) and not SoundPlan.incomeClink(0, 100, -math.huge, -math.huge, false, true))
check("the income's clink is soft (sfx2's coin, quiet)", SoundSheet.Sfx2.coin ~= nil and SB.Income > 0 and SB.Income <= 0.25)
check("the sale's till and the income's coin", sfx4("sale_register") and SoundSheet.Fallback.sale_register ~= nil)
-- The Sprinter: its sliding door, its step, its back doors.
check("the sliding door rolls open", SoundPlan.slideSound(true) == "van_slide_open" and sfx4("van_slide_open"))
check("… and slams shut", SoundPlan.slideSound(false) == "van_slide_close" and sfx4("van_slide_close"))
check("the rear and side steps are steps", SoundPlan.isStep("RearStep") and SoundPlan.isStep("SideStep"))
check("the bay's floor and the bumper are not", not SoundPlan.isStep("BayFloor") and not SoundPlan.isStep("RearBumper") and not SoundPlan.isStep("StepFolded"))
check("the step's clonk", sfx4("van_step_up") and SoundSheet.Fallback.van_step_up == "step_metal_a")
local open, openPitch = SoundPlan.swingSound("swing", "opening", "sprinter")
local close = SoundPlan.swingSound("swing", "closing", "sprinter")
check("the Sprinter's back doors swing round with their own sound", open == "sprinter_back_open" and openPitch == 1 and sfx4(open :: string))
check("… and shut with their own", close == "sprinter_back_close" and sfx4(close :: string))
check("… its cabin doors as any car's", SoundPlan.swingSound("door", "opening", "sprinter") == "car_door_open" and SoundPlan.swingSound("door", "shut", "sprinter") == "car_door_close")
check("another van's back as before", SoundPlan.swingSound("swing", "opening", "van") == "van_back_open" and SoundPlan.swingSound("swing", "opening") == "van_back_open")
-- The moves in the sandbox: no ramp (the Sprinter's doors are heard), no Wall's gate (the trip home's fanfare).
check("the sandbox: the Sprinter's back plays no truck ramp", names(SoundPlan.moveCues(base, state({ backOpen = true }), 1000 + 30)) == "" and names(SoundPlan.moveCues(state({ backOpen = true }), base, 1000 + 30)) == "")
check("… the house's door still creaks", names(SoundPlan.moveCues(base, state({ inside = true }), 1000 + 30)) == "house_door_creak")
check("… and no Wall's gate at the end", SoundPlan.resultCue({ how = "done" }) == nil and SoundPlan.resultCue({ how = "late" }) == nil)
for key, value in SB do
	if type(value) == "number" then
		local most = if string.find(key, "Range", 1, true) then 200 else 60 -- (a range in studs)
		check(`Config.Soundscape.Sandbox.{key} is a sane number`, value >= 0 and value <= most, value)
	elseif key ~= "Reverb" then
		local list = value :: { number }
		check(`Config.Soundscape.Sandbox.{key} is a range`, #list == 2 and list[1] > 0 and list[2] >= list[1], key)
	end
end
for key, value in { "Alpine", "AlpineStandIn", "Warehouse", "WarehouseStandIn", "Room", "Display", "TakeDown", "Sold", "Stored", "Slide", "Step" } do
	check(`Config.Soundscape.Sandbox.{value} is a volume (0 … 1)`, SB[value] > 0 and SB[value] <= 1, key)
end
Config.Sandbox.On = sandboxOn

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
