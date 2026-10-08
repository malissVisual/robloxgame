--!strict
-- 6.12, what the world sounds like where you are (Config.Soundscape; the sounds: art/audio/sfx3.ogg, shared/SoundSheet
-- Sfx3). Plain numbers and names, no Roblox: client/SoundScape.luau and client/CarVisuals.luau ask, and
-- tests/soundplan_test.luau checks it.
--
--   SoundPlan.Surfaces                            "concrete", "grass", "wood", "metal", "water"
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

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)

local SoundPlan = {}

SoundPlan.Surfaces = { "concrete", "grass", "wood", "metal", "water" }

local S = Config.Soundscape

function SoundPlan.waterTop(x: number, z: number): number?
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

function SoundPlan.swingSound(what: string, moment: string): (string?, number)
	local list = SWINGS[what]
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

return SoundPlan
