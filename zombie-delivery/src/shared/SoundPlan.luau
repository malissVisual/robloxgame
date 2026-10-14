--!strict
-- 6.12, what the world sounds like where you are (Config.Soundscape; the sounds: art/audio/sfx3.ogg, shared/SoundSheet
-- Sfx3). Plain numbers and names, no Roblox: client/SoundScape.luau and client/CarVisuals.luau ask, and
-- tests/soundplan_test.luau checks it.
--
--   SoundPlan.Surfaces                            "concrete", "grass", "wood", "metal", "water"
--   SoundPlan.cityPlaces()                        8.0.1: are the city's places there (the park with its pond, lawns
--                                                 and fountain, the river, the sea)? Not in the sandbox
--                                                 (Config.Sandbox.On), whose Main Street runs over the park's (0, 0):
--                                                 no water and no lawn found there, no fountain heard
--   SoundPlan.waterTop(x, z)                      the water's top over (x, z) (the park's pond: the ground's 0; the
--                                                 river and the sea: Map.WaterLevel), nil where there is none
--   SoundPlan.inWater(x, y, z)                    is a foot at (x, y, z) in the water
--   SoundPlan.parkLawn(x, z)                      is (x, z) on one of the park's lawns (not its paths, the walk round
--                                                 the block, the pond, the coping)
--   SoundPlan.surface(material, x, y, z)          the footstep's surface: the material's name under the foot (Enum
--                                                 Material's Name) where the foot is
--   SoundPlan.stepName(surface, left)             the step's sound ("step_grass_a" / "step_grass_b" in turn)
--   SoundPlan.horn(carId, bike, stand)            a vehicle's horn: its class's (Config.Soundscape.Horns), a pedal
--                                                 bike's bell, a stand-up scooter's beep
--   SoundPlan.backKind(axis, hingeUp)             the back that opens, from its hinge (server/Vehicles.luau): "swing"
--                                                 (two rear doors), "rollup" (a roll-up door) or "gate" (a tailgate,
--                                                 a trunk lid, a ramp)
--   SoundPlan.swingSound(what, moment)            the sound of a door ("door") or a back (its kind) at a moment
--                                                 ("opening" | "closing" | "shut"): name and pitch, nil: none then
--   SoundPlan.roofShare(height)                   0 on the street … 1 high up (the rooftop wind)
--   SoundPlan.ambience(night, height, sheet3)     the ambience loops' volumes: { day, night, roof, hum, wind }
--
-- 7.1, the move's sounds (art/audio/sfx4.ogg, Config.Soundscape.Move; client/MoveSounds.luau plays them). `view` is
-- server/Moving.luau's state of your move (the Moving remote's "state"), `result` its "result".
--   SoundPlan.moveCues(was, now, clock)           what changed between two states in a row (was: nil before a move's
--                                                 first; clock: the server's time now) → the cues to play, in order:
--                                                 move_start, horde_siren, truck_ramp, house_door_creak, truck_load,
--                                                 glass_break / heavy_drop
--   SoundPlan.moveItem(view, spot)                the state's piece at `spot` (a table) or nil
--   SoundPlan.isBox(item)                         is the piece a box (cardboard: its name says Box, or the 📦 icon)
--   SoundPlan.carryCue(item, up)                  the sound of your hands taking (up) or putting down a piece
--   SoundPlan.dragged(view, spot)                 is the piece in your hands dragged (two people's, alone, no Mover)
--   SoundPlan.resultCue(result)                   the end: the Wall's gate when the load got there, else nil
--
-- 8.1 SANDBOX, the sandbox's sounds (art/audio/sfx4.ogg's 8.1 part, Config.Soundscape.Sandbox; client/SoundScape.luau
-- plays the ambience, client/SandboxSounds.luau the rest). In the sandbox (Config.Sandbox.On) moveCues leaves out the
-- truck's ramp (the Sprinter has none: its back doors are heard swinging, swingSound's Sprinter doors) and resultCue
-- the Wall's gate (no Wall there: the trip home has its fanfare). 8.3: and the house's door creak (its leaves creak at
-- the door as they swing open, Config.Moving.Doors Swing: client/WalkDoors.luau).
--   SoundPlan.SandboxLoops                        the sandbox's loops by their part of the mix: alpine (amb_alpine, a
--                                                 calm alpine day: never the city's traffic, amb_day), warehouse
--                                                 (amb_warehouse), room (amb_room)
--   SoundPlan.sandboxPlace(x, y, z, inside, levelOf?)   where you are: "house" (inside: the move's state says you
--                                                 are in its house; or far off the sandbox's map, where the moves build
--                                                 their interiors; or in the chalet's own box), "warehouse" (in a plot's
--                                                 warehouse building) or "outdoors". 8.3: every plot's warehouse is the
--                                                 building of its level (WarehouseLayout.site: 1 the Garage … 5 the
--                                                 Logistics Center, up to its roof's top); levelOf(plot id) → its level
--                                                 (the caller reads workspace.Warehouses' Level<id>; nil, or no levelOf:
--                                                 4, the building of before 8.3)
--   SoundPlan.sandboxAmbience(place, sheet4)      the loops' volumes there { alpine, warehouse, room } (sheet4: is
--                                                 sfx4.ogg up; else the stand-ins' own volumes and no room tone)
--   SoundPlan.reverb(place)                       SoundService.AmbientReverb's name there ("NoReverb" outdoors)
--   SoundPlan.cowbellGap(r)                       seconds to the next far cowbell (r: a random 0 … 1)
--   SoundPlan.cowbellSpot(x, z, r1, r2)           where it rings: a random way round (x, z), CowbellFar studs off
--   SoundPlan.collectionCues(was, now, sinceResult, sinceFill)   two "Collection" states one after the other
--                                                 (server/Collection.luau) → the cues: pieces that came home
--                                                 (stored_fanfare; not when the move's result card played its own jingle
--                                                 sinceResult s ago), a piece put on a stand or moved to another
--                                                 (stand_display; 8.3: not FillQuiet s after ⭐ FILL BEST, sinceFill: its
--                                                 clicks said it), one taken down (stand_takedown); one of each at most,
--                                                 nothing on the first state
--   SoundPlan.incomeClink(gained, now, last, soldAt, open, earning)   does money that came in clink: the stands'
--                                                 income (pieces on show earn), not a sale's (SoldQuiet s after it), the
--                                                 warehouse's window shut, IncomeGap s since the last clink
--   SoundPlan.slideSound(open)                    the Sprinter's sliding door rolling open / slammed shut
--   SoundPlan.isStep(name)                        is a part of this name a Sprinter's step (its rear or side step)
--
-- 8.3 SANDBOX, the 8.2 features' feedback (the existing sheets only: sfx, sfx2, sfx3, sfx4 with its stand-ins;
-- Config.Soundscape.Sandbox's Discovery … FeedbackWait; client/SandboxSounds.luau plays them from the remotes' existing
-- messages). The kinds: "stored" (the trip home's fanfare, collectionCues'), "discovery" (a piece new in the collection
-- book: ding, a bright bell), "milestone" (a book milestone paid: level_up, the bells' fanfare), "taskDone" (task_done),
-- "claimed" (a task's reward: cash), "fill" (⭐ FILL BEST: a few soft stand clicks, stand_display), "bulkSold" (💰 SELL…:
-- the till once, sale_register louder, the old ka-ching, cash, on top).
--   SoundPlan.feedbackOf(remote, message) -> (kind?, count)   what a message of the "CollectionBook", "SandboxTasks" or
--                                                 "Collection" remote plays (count: the pieces it was about); nil: none
--                                                 (one piece sold is the till's own, as before)
--   SoundPlan.feedbackCues(kind, count?) -> { Timed }   its cues, each `at` s after it starts
--   SoundPlan.seconds(name) -> number             how long a sound plays: its region on the sheet that plays it (the
--                                                 sheet when its id is in, else its stand-in's, as client/Sounds.luau
--                                                 finds it)
--   SoundPlan.lane() -> Lane / SoundPlan.slot(lane, kind, now, count?) -> number?   when a kind starts (the clock's
--                                                 time): a sting (stored, discovery, milestone, taskDone) waits until the
--                                                 one before it ends, never over it; an answer to your own press
--                                                 (claimed, fill, bulkSold) at once, the stings after it wait; nil: left
--                                                 out (the same kind within its Gap, or a wait over FeedbackWait)
--   SoundPlan.hold(lane, now, seconds)            another module's sting plays now (the move's result card's jingle):
--                                                 the lane's stings wait for it too

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local SoundSheet = require(script.Parent.SoundSheet) -- (8.3: how long a sound plays)
local MoveRoles = require(script.Parent.MoveRoles)
local SandboxMap = require(script.Parent.SandboxMap)
local WarehouseLayout = require(script.Parent.WarehouseLayout) -- 8.3: a plot's warehouse at its level

local SoundPlan = {}

SoundPlan.Surfaces = { "concrete", "grass", "wood", "metal", "water" }

local S = Config.Soundscape

function SoundPlan.cityPlaces(): boolean
	return not Config.Sandbox.On
end

function SoundPlan.waterTop(x: number, z: number): number?
	if not SoundPlan.cityPlaces() then
		return nil -- (the sandbox: no pond, no river, no sea)
	end
	local park = Map.Park
	local dx, dz = math.abs(x - park.x), math.abs(z - park.z)
	if dx <= park.pond and dz <= park.pond and (dx + dz) <= park.pond * math.sqrt(2) then
		return 0 -- (the pond's Terrain water: from the ground's 0 down, server/World.luau)
	end
	if Map.inWater(x, z) then
		return Map.WaterLevel
	end
	return nil
end

function SoundPlan.inWater(x: number, y: number, z: number): boolean
	local top = SoundPlan.waterTop(x, z)
	return top ~= nil and y < top -- (the island, the bridge and the coping stand over the pond's top: dry)
end

-- The octagon's "radius" (flat sides to the four streets and the four corners, as the pond and the ring path).
local function octagon(dx: number, dz: number): number
	return math.max(math.abs(dx), math.abs(dz), (math.abs(dx) + math.abs(dz)) / math.sqrt(2))
end

-- server/CentralPark.luau's layout: the lawn inside the walk round the block, round the pond's coping and the ring
-- path, less the paths to the middles of the sides (5 wide) and to the corners (4 wide); the island's lawn round the
-- fountain's basin.
function SoundPlan.parkLawn(x: number, z: number): boolean
	if not SoundPlan.cityPlaces() then
		return false -- (the sandbox: no park; its own meadow is Grass, found by its material)
	end
	local park = Map.Park
	local dx, dz = x - park.x, z - park.z
	local lawnEdge = Map.BlockSize / 2 - park.walk
	if math.abs(dx) > lawnEdge or math.abs(dz) > lawnEdge then
		return false -- the walk round the block (or off the park)
	end
	local r = octagon(dx, dz)
	local ringIn = park.pond + 1.5
	local ringOut = ringIn + park.ring
	if r < ringIn then
		local round = math.sqrt(dx * dx + dz * dz)
		return round < park.island - 0.8 and round > 3.6 -- the island's lawn (not the fountain's basin), else the pond
	end
	if r <= ringOut then
		return false -- the ring path
	end
	local ax, az = math.abs(dx), math.abs(dz)
	if math.min(ax, az) <= 2.5 then
		return false -- a path to the middle of a side
	end
	if math.abs(ax - az) / math.sqrt(2) <= 2 then
		return false -- a path to a corner
	end
	return true
end

function SoundPlan.surface(material: string, x: number, y: number, z: number): string
	if SoundPlan.inWater(x, y - 0.1, z) then
		return "water"
	end
	local surface = S.Materials[material]
	if surface then
		return surface
	end
	-- The park's lawns are decoration (no collision, no ray hits) over its concrete slab and its island's slate.
	if (material == "Concrete" or material == "Slate") and SoundPlan.parkLawn(x, z) then
		return "grass"
	end
	return "concrete"
end

function SoundPlan.stepName(surface: string, left: boolean): string
	return `step_{surface}_{if left then "a" else "b"}`
end

function SoundPlan.horn(carId: string?, bike: boolean, stand: boolean): string
	if stand then
		return "scooter_beep"
	elseif bike then
		return "bike_bell"
	end
	return (carId and S.Horns[carId]) or "horn_car"
end

-- hingeUp: how far the hinge line sits above the leaf's middle (the BackHinge's C1.Y, studs).
function SoundPlan.backKind(axis: string, hingeUp: number): string
	if axis ~= "X" then
		return "swing"
	elseif hingeUp > 1 then
		return "rollup"
	end
	return "gate"
end

-- (the back's sounds are made to fit its swing, 0.45 s in client/CarVisuals.luau: the stop, the slam or the bang at its
-- end; a tailgate's thud comes when it is shut)
type Swing = { name: string, pitch: number }
local SWINGS: { [string]: { [string]: Swing } } = {
	door = { opening = { name = "car_door_open", pitch = 1 }, shut = { name = "car_door_close", pitch = 1 } },
	swing = { opening = { name = "van_back_open", pitch = 1 }, closing = { name = "van_back_close", pitch = 1 } },
	rollup = { opening = { name = "van_roll_up", pitch = 1 }, closing = { name = "van_roll_down", pitch = 1 } },
	gate = { opening = { name = "car_door_open", pitch = 0.8 }, shut = { name = "car_door_close", pitch = 0.78 } },
}

-- 8.1: a car's own doors, by its CarId (the rest as its kind's above): the ZDC Sprinter's two back doors swing round to
-- its sides (magnets catch them there) and its step folds out behind them (sprinter_back_open / _close, made to the same
-- 0.45 s swing).
local OWN_SWINGS: { [string]: { [string]: { [string]: Swing } } } = {
	sprinter = {
		swing = { opening = { name = "sprinter_back_open", pitch = 1 }, closing = { name = "sprinter_back_close", pitch = 1 } },
	},
}

-- carId: the car's CarId attribute (nil: its kind's sounds).
function SoundPlan.swingSound(what: string, moment: string, carId: string?): (string?, number)
	local own = if carId then OWN_SWINGS[carId] else nil
	local list = (own and own[what]) or SWINGS[what]
	local entry = list and list[moment]
	if not entry then
		return nil, 1
	end
	return entry.name, entry.pitch
end

function SoundPlan.roofShare(height: number): number
	return math.clamp((height - S.RoofFrom) / (S.RoofFull - S.RoofFrom), 0, 1)
end

export type Mix = { day: number, night: number, roof: number, hum: number, wind: number }

-- night: 0 by day … 1 at night (Map.nightFactor); height: studs over the ground; sheet3: is sfx3.ogg uploaded.
function SoundPlan.ambience(night: number, height: number, sheet3: boolean): Mix
	local n = math.clamp(night, 0, 1)
	local roof = SoundPlan.roofShare(height)
	if sheet3 then
		local street = 1 - S.RoofDuck * roof
		return { day = S.Day * (1 - n) * street, night = S.Night * n * street, roof = S.Roof * roof, hum = 0, wind = 0 }
	end
	local J = Config.Juice
	return {
		day = 0,
		night = 0,
		roof = 0,
		hum = J.AmbienceDay + (J.AmbienceNight - J.AmbienceDay) * n,
		wind = J.WindDay + (J.WindNight - J.WindDay) * n + S.RoofStandIn * roof,
	}
end

-- ── 7.1: the move's sounds ──────────────────────────────────────────────────

export type Cue = { name: string, volume: number, pitch: number }

local function cueOf(name: string, volume: number, pitch: number?): Cue
	return { name = name, volume = volume, pitch = pitch or 1 }
end

-- The state's pieces by their spot (the view comes over the network: anything not a table is skipped).
local function piecesOf(view: any): { [number]: any }
	local out: { [number]: any } = {}
	if type(view) == "table" and type(view.items) == "table" then
		for _, item in view.items do
			if type(item) == "table" and type(item.spot) == "number" then
				out[item.spot] = item
			end
		end
	end
	return out
end

function SoundPlan.moveItem(view: any, spot: any): any
	if type(spot) ~= "number" then
		return nil
	end
	return piecesOf(view)[spot]
end

function SoundPlan.isBox(item: any): boolean
	if type(item) ~= "table" then
		return false
	end
	local name = if type(item.name) == "string" then item.name else ""
	return item.icon == "📦" or string.find(name, "%f[%a]Box%f[%A]") ~= nil
end

function SoundPlan.carryCue(item: any, up: boolean): Cue
	local M = S.Move
	if SoundPlan.isBox(item) then
		return cueOf("cardboard_box", M.Box, if up then 1 else 0.92)
	end
	return if up then cueOf("furniture_pickup", M.Pickup) else cueOf("furniture_putdown", M.PutDown)
end

function SoundPlan.dragged(view: any, spot: any): boolean
	local item = SoundPlan.moveItem(view, spot)
	if not item or item.class ~= "pair" or item.state ~= "carried" then
		return false
	end
	-- (the state names the holders "Carrier + Helper": somebody at the other end lifts it)
	if type(item.by) == "string" and string.find(item.by, " + ", 1, true) then
		return false
	end
	local team = if type(view.team) == "table" then view.team else nil
	local role = if team and type(team.role) == "string" then team.role else nil
	return MoveRoles.holdMode(role, "drag") == "drag" -- (a Mover holds it up alone)
end

function SoundPlan.moveCues(was: any, now: any, clock: number): { Cue }
	local M = S.Move
	local cues: { Cue } = {}
	if type(now) ~= "table" then
		return cues -- the move is over (its result card plays the rest)
	end
	if type(was) ~= "table" or was.id ~= now.id then
		-- a new move: the sting, unless it has been running a while (you joined or rejoined in the middle)
		local seconds, endsAt = tonumber(now.seconds), tonumber(now.endsAt)
		if seconds and endsAt and seconds - (endsAt - clock) <= M.StartWithin then
			table.insert(cues, cueOf("move_start", M.Start))
		end
		return cues
	end
	if now.horde == true and was.horde ~= true then
		table.insert(cues, cueOf("horde_siren", M.Siren))
	end
	-- (8.1: not in the sandbox: the Sprinter has no ramp, its back doors are heard swinging, swingSound)
	if (now.backOpen == true) ~= (was.backOpen == true) and not Config.Sandbox.On then
		table.insert(cues, cueOf("truck_ramp", M.Ramp, if now.backOpen == true then 1 else M.RampShut))
	end
	-- (8.3: not in the sandbox, whose doors' leaves creak at the door as they swing open: client/WalkDoors.luau)
	if (now.inside == true) ~= (was.inside == true) and not (Config.Sandbox.On and Config.Moving.Doors.Swing) then
		table.insert(cues, cueOf("house_door_creak", M.Door, if now.inside == true then 1 else M.DoorOut))
	end
	-- the pieces: one load and one crash at most a state (the loudest), yours louder than the crew's
	local before = piecesOf(was)
	local load = 0
	local crash: Cue? = nil
	for spot, item in piecesOf(now) do
		local old = before[spot]
		if old then
			local mine = old.mine == true or item.mine == true
			if item.state == "truck" and old.state ~= "truck" then
				load = math.max(load, if mine then M.Load else M.LoadCrew)
			end
			local volume = if mine then M.Break else M.BreakCrew
			if item.broken == true and old.broken ~= true then
				local name = if item.fragile == true then "glass_break" else "heavy_drop"
				if not crash or volume > crash.volume or (volume == crash.volume and name == "glass_break") then
					crash = cueOf(name, volume)
				end
			elseif mine and item.state ~= "truck" and (tonumber(old.condition) or 1) - (tonumber(item.condition) or 1) >= M.Jolt then
				if not crash then
					crash = cueOf("heavy_drop", M.JoltVolume)
				end
			end
		end
	end
	if load > 0 then
		table.insert(cues, cueOf("truck_load", load))
	end
	if crash then
		table.insert(cues, crash)
	end
	return cues
end

function SoundPlan.resultCue(result: any): Cue?
	if Config.Sandbox.On then
		return nil -- (8.1: the sandbox has no Wall: the trip home has its fanfare, collectionCues)
	end
	if type(result) == "table" and (result.how == "done" or result.how == "late") then
		return cueOf("checkpoint_gate", S.Move.Gate)
	end
	return nil
end

-- ── 8.1 SANDBOX: the meadow, the warehouse, the chalet, the collection, the Sprinter ───────────────────────────────

SoundPlan.SandboxLoops = { alpine = "amb_alpine", warehouse = "amb_warehouse", room = "amb_room" }

local OFF_MAP = 1000 -- studs past SandboxMap.Bounds: a move's interior (server/HouseInterior.luau builds them far off)
local INSET = 2 -- studs inside the chalet's box (its front door's step, where you come out, is outdoors)

-- 8.3: a plot's warehouse at a level: its box and its roof's top (WarehouseLayout.site, outline), found once a plot and
-- level (the ambience asks every Tick: nothing made then).
type Hall = { x: number, y: number, z: number, sx: number, sz: number, top: number }
local halls: { [number]: { [number]: Hall } } = {}
local function hallOf(plot: SandboxMap.Plot, level: any): Hall
	local n = if type(level) == "number" and level == level then math.clamp(math.floor(level), 1, WarehouseLayout.Levels) else 4
	local byLevel = halls[plot.id]
	if not byLevel then
		byLevel = {}
		halls[plot.id] = byLevel
	end
	local known = byLevel[n]
	if not known then
		local site = WarehouseLayout.site(plot, n) or plot
		local w = site.warehouse
		known = { x = w.x, y = w.y, z = w.z, sx = w.sx, sz = w.sz, top = WarehouseLayout.outline(site).top }
		byLevel[n] = known
	end
	return known :: Hall
end

function SoundPlan.sandboxPlace(x: number, y: number, z: number, inside: boolean, levelOf: ((plot: number) -> number?)?): string
	if inside then
		return "house"
	end
	local b = SandboxMap.Bounds
	if x < b.x0 - OFF_MAP or x > b.x1 + OFF_MAP or z < b.z0 - OFF_MAP or z > b.z1 + OFF_MAP then
		return "house"
	end
	local house: any = SandboxMap.House
	local h = if type(house) == "table" then house.house else nil
	if type(h) == "table" and math.abs(x - h.x) <= h.sx / 2 - INSET and math.abs(z - h.z) <= h.sz / 2 - INSET and y >= h.y - 2 and y <= h.y + h.sy then
		return "house"
	end
	local plot = SandboxMap.plotAt(x, z)
	local w = if plot then hallOf(plot, if levelOf then levelOf(plot.id) else nil) else nil
	if w and math.abs(x - w.x) <= w.sx / 2 and math.abs(z - w.z) <= w.sz / 2 and y >= w.y - 2 and y <= w.y + w.top then
		return "warehouse"
	end
	return "outdoors"
end

export type SandboxMix = { alpine: number, warehouse: number, room: number }

function SoundPlan.sandboxAmbience(place: string, sheet4: boolean): SandboxMix
	local B = S.Sandbox
	local alpine = if sheet4 then B.Alpine else B.AlpineStandIn
	if place == "warehouse" then
		return { alpine = alpine * B.AlpineIndoors, warehouse = if sheet4 then B.Warehouse else B.WarehouseStandIn, room = 0 }
	elseif place == "house" then
		return { alpine = 0, warehouse = 0, room = if sheet4 then B.Room else 0 }
	end
	return { alpine = alpine, warehouse = 0, room = 0 }
end

function SoundPlan.reverb(place: string): string
	return S.Sandbox.Reverb[place] or "NoReverb"
end

function SoundPlan.cowbellGap(r: number): number
	local gap = S.Sandbox.CowbellGap
	return gap[1] + (gap[2] - gap[1]) * math.clamp(r, 0, 1)
end

function SoundPlan.cowbellSpot(x: number, z: number, r1: number, r2: number): (number, number)
	local far = S.Sandbox.CowbellFar
	local angle = math.clamp(r1, 0, 1) * 2 * math.pi
	local distance = far[1] + (far[2] - far[1]) * math.clamp(r2, 0, 1)
	return x + math.cos(angle) * distance, z + math.sin(angle) * distance
end

-- A state's pieces by their uid: the stand each is on (0: in the stock). (Over the network: junk is skipped.)
local function standsOf(state: any): { [string]: number }?
	if type(state) ~= "table" or type(state.stock) ~= "table" then
		return nil
	end
	local out: { [string]: number } = {}
	for _, entry in state.stock do
		if type(entry) == "table" and (type(entry.uid) == "string" or type(entry.uid) == "number") then
			out[tostring(entry.uid)] = if type(entry.stand) == "number" then entry.stand else 0
		end
	end
	return out
end

function SoundPlan.collectionCues(was: any, now: any, sinceResult: number?, sinceFill: number?): { Cue }
	local B = S.Sandbox
	local cues: { Cue } = {}
	local before, after = standsOf(was), standsOf(now)
	if not before or not after then
		return cues -- (the first state: nothing changed yet)
	end
	local came, shown, taken = 0, false, false
	for uid, stand in after do
		local old = before[uid]
		if old == nil then
			came += 1
		elseif stand ~= old then
			if stand > 0 then
				shown = true -- (put up, or moved to another stand)
			else
				taken = true
			end
		end
	end
	-- (a piece gone: sold, its till plays from the "sold" message; or cleared: nothing)
	if came > 0 and not (sinceResult and sinceResult < B.StoredQuiet) then
		table.insert(cues, cueOf("stored_fanfare", B.Stored))
	end
	if shown and not (sinceFill and sinceFill < B.FillQuiet) then -- (8.3: FILL BEST's clicks said it)
		table.insert(cues, cueOf("stand_display", B.Display))
	end
	if taken then
		table.insert(cues, cueOf("stand_takedown", B.TakeDown))
	end
	return cues
end

function SoundPlan.incomeClink(gained: number, now: number, last: number, soldAt: number, open: boolean, earning: boolean): boolean
	local B = S.Sandbox
	return gained > 0 and earning and not open and now - soldAt >= B.SoldQuiet and now - last >= B.IncomeGap
end

function SoundPlan.slideSound(open: boolean): string
	return if open then "van_slide_open" else "van_slide_close"
end

local STEPS = { RearStep = true, SideStep = true } -- (shared/SprinterLooks.luau Switched: the steps out while a door is open)

function SoundPlan.isStep(name: string): boolean
	return STEPS[name] == true
end

-- ── 8.3 SANDBOX: the book's, the tasks' and the bulk actions' feedback ──────────────────────────────────────────────

export type Timed = { name: string, volume: number, pitch: number, at: number }
export type Lane = { free: number, last: { [string]: number } }

SoundPlan.FeedbackKinds = { "stored", "discovery", "milestone", "taskDone", "claimed", "fill", "bulkSold" }
local ANSWERS = { claimed = true, fill = true, bulkSold = true } -- (your own press: at once)

local function count(value: any): number
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then math.floor(value) else 0
end

function SoundPlan.feedbackOf(remote: string, message: any): (string?, number)
	if type(message) ~= "table" then
		return nil, 0
	end
	local kind = message.kind
	if remote == "CollectionBook" then
		if kind == "state" and type(message.new) == "table" then
			local n = 0
			for _, item in message.new do
				if type(item) == "string" then
					n += 1
				end
			end
			if n > 0 then
				return "discovery", n
			end
		elseif kind == "milestone" and type(message.id) == "string" then
			return "milestone", 1
		end
	elseif remote == "SandboxTasks" then
		if kind == "done" then
			return "taskDone", 1
		elseif kind == "claimed" then
			return "claimed", 1
		end
	elseif remote == "Collection" then
		if kind == "bulk" and message.action == "fillbest" and count(message.count) > 0 then
			return "fill", count(message.count)
		elseif kind == "sold" and count(message.count) >= 2 then
			return "bulkSold", count(message.count)
		end
	end
	return nil, 0
end

local function timed(name: string, volume: number, pitch: number, at: number): Timed
	return { name = name, volume = volume, pitch = pitch, at = at }
end

function SoundPlan.feedbackCues(kind: string, n: number?): { Timed }
	local B = S.Sandbox
	if kind == "stored" then
		return { timed("stored_fanfare", B.Stored, 1, 0) }
	elseif kind == "discovery" then
		return { timed("ding", B.Discovery, 1.12, 0) }
	elseif kind == "milestone" then
		return { timed("level_up", B.Milestone, 1, 0) }
	elseif kind == "taskDone" then
		return { timed("task_done", B.TaskDone, 1, 0) }
	elseif kind == "claimed" then
		return { timed("cash", B.Claimed, 1.04, 0) }
	elseif kind == "fill" then
		local clicks: { Timed } = {}
		for i = 1, math.clamp(math.floor(n or 1), 1, B.FillClicks) do
			table.insert(clicks, timed("stand_display", B.Fill, 1 + 0.07 * (i - 1), (i - 1) * B.FillEvery))
		end
		return clicks
	elseif kind == "bulkSold" then
		return { timed("sale_register", B.BulkSold, 0.94, 0), timed("cash", B.BulkKa, 1, B.BulkKaAt) }
	end
	return {}
end

function SoundPlan.seconds(name: string): number
	local sheets = {
		{ sheet = SoundSheet.Sfx, up = true },
		{ sheet = SoundSheet.Sfx2, up = SoundSheet.Sfx2Id ~= "" },
		{ sheet = SoundSheet.Sfx3, up = SoundSheet.Sfx3Id ~= "" },
		{ sheet = SoundSheet.Sfx4, up = SoundSheet.Sfx4Id ~= "" },
	}
	local now: string? = name
	for _ = 1, 6 do -- (a stand-in's stand-in)
		local look = now
		if not look then
			break
		end
		for _, entry in sheets do
			local region = entry.sheet[look]
			if entry.up and region then
				return region[2]
			end
		end
		now = SoundSheet.Fallback[look]
	end
	return 0
end

function SoundPlan.lane(): Lane
	return { free = -math.huge, last = {} }
end

function SoundPlan.hold(lane: Lane, now: number, seconds: number)
	lane.free = math.max(lane.free, now + math.max(0, seconds))
end

local function gapOf(kind: string): number
	local B = S.Sandbox
	local gaps: { [string]: number } = {
		discovery = B.DiscoveryGap,
		milestone = B.MilestoneGap,
		taskDone = B.TaskDoneGap,
		claimed = B.ClaimedGap,
		fill = B.FillGap,
		bulkSold = B.BulkGap,
	}
	return gaps[kind] or 0
end

function SoundPlan.slot(lane: Lane, kind: string, now: number, n: number?): number?
	local cues = SoundPlan.feedbackCues(kind, n)
	if #cues == 0 then
		return nil
	end
	local last = lane.last[kind]
	if last and now - last < gapOf(kind) then
		return nil -- (the same again too soon: a burst is one)
	end
	local at = if ANSWERS[kind] then now else math.max(now, lane.free)
	if at - now > S.Sandbox.FeedbackWait then
		return nil -- (too far behind the stings before it)
	end
	lane.last[kind] = now
	local length = 0
	for _, cue in cues do
		length = math.max(length, cue.at + SoundPlan.seconds(cue.name) / cue.pitch)
	end
	lane.free = math.max(lane.free, at + length)
	return at
end

return SoundPlan
