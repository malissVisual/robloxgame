--!strict
-- 6.16, driving that feels alive (the owner: "upgrade the visuals and the feel"): the pure rules behind the tyres' dust,
-- smoke and skid marks, a crash's sparks, the engine's note and the speed lines. Pure (no Roblox at its top level;
-- tests/drivefeel_test.luau runs it in the plain Luau CLI). Numbers in Config.DriveFeel; the body's sway is
-- shared/Suspension.luau.
--   * DriveFeel.surface(material, winter, ice): what is under the wheels: "road" (asphalt, concrete, a pavement …),
--     "dirt" (grass, earth, sand, mud, gravel) or "snow" (snow, ice; anywhere in the winter, Map.isWinter; the lake's
--     ice, Map.onIce). material: the Enum.Material's Name.
--   * DriveFeel.strain(speed, decel, lateral, slide, accel): how hard the tyres work now, 0 … 1: a hard brake, a fast
--     sharp turn, a slide sideways, a hard launch from a stand (the hardest of them).
--   * DriveFeel.tyres(surface, speed, strain): what a rear wheel throws: the kind ("dust", "snow", "smoke"), its rate
--     (particles a second) and the skid (0: no mark; else the mark's strength: on asphalt only).
--   * DriveFeel.crash(drop): how hard a hit was (0: none … 1) from the speed lost in a blink.
--   * DriveFeel.styleOf(carId), DriveFeel.engineClass(style): which engine a car has ("car", "van", "truck", "monster").
--   * DriveFeel.shift(gear, share, gears) and DriveFeel.engine(class, share, gear, throttle, boost): a little gearbox:
--     the gear for this share of the top speed (with some hysteresis) and the engine loop's pitch and volume.
--   * DriveFeel.streaks(share, twoWheels): how strong the speed lines are (0 … 1).

local Config = require(script.Parent.Config)

local DriveFeel = {}

local Feel = Config.DriveFeel
local Tyres = Feel.Tyres
local Engine = Feel.Engine

-- 0 at `from`, 1 at `full`, linear between.
local function ramp(value: number, from: number, full: number): number
	return math.clamp((value - from) / math.max(full - from, 1e-6), 0, 1)
end
DriveFeel.ramp = ramp

local DIRT: { [string]: boolean } = {
	Grass = true, LeafyGrass = true, Ground = true, Mud = true, Sand = true, Sandstone = true, Pebble = true, Salt = true,
	CrackedLava = true,
}
local SNOW: { [string]: boolean } = { Snow = true, Ice = true, Glacier = true }

function DriveFeel.surface(material: string, winter: boolean, ice: boolean): string
	if SNOW[material] or winter or ice then
		return "snow"
	elseif DIRT[material] then
		return "dirt"
	end
	return "road"
end

-- speed: along the nose (any sign); decel: how fast it slows (studs/s², ≥ 0 braking); lateral: the sideways
-- acceleration (any sign); slide: the sideways speed (any sign); accel: how fast it speeds up (studs/s²).
function DriveFeel.strain(speed: number, decel: number, lateral: number, slide: number, accel: number): number
	local moving = math.abs(speed) >= Tyres.MinSpeed
	local brake = if moving then ramp(decel, Tyres.Brake.From, Tyres.Brake.Full) else 0
	local corner = if moving then ramp(math.abs(lateral), Tyres.Corner.From, Tyres.Corner.Full) else 0
	local skid = ramp(math.abs(slide), Tyres.Slide.From, Tyres.Slide.Full)
	local launch = if math.abs(speed) < Tyres.Launch.Below then ramp(accel, Tyres.Launch.From, Tyres.Launch.Full) else 0
	return math.max(brake, corner, skid, launch)
end

function DriveFeel.tyres(surface: string, speed: number, strain: number): (string, number, number)
	local pace = math.abs(speed)
	if surface == "dirt" then
		local dust = Tyres.Dust
		return "dust", dust.Rate * math.min(1, ramp(pace, dust.From, dust.Full) * 0.7 + strain * 0.6), 0
	elseif surface == "snow" then
		local snow = Tyres.Snow
		return "snow", snow.Rate * math.min(1, ramp(pace, snow.From, snow.Full) * 0.7 + strain * 0.6), 0
	end
	local smoke = Tyres.Smoke
	local rate = if strain >= smoke.From then smoke.Rate * strain else 0
	return "smoke", rate, if strain >= Feel.Skids.From then strain else 0
end

function DriveFeel.crash(drop: number): number
	local crash = Feel.Crash
	if drop < crash.From then
		return 0
	end
	return math.max(0.05, ramp(drop, crash.From, crash.Full))
end

-- The Config.Cars style of a car id (nil: not found).
local styles: { [string]: string } = {}
for _, def in Config.Cars do
	styles[def.id] = def.style
end
function DriveFeel.styleOf(carId: string?): string?
	return if carId then styles[carId] else nil
end

function DriveFeel.engineClass(style: string?): string
	return (if style then Engine.Styles[style] else nil) or "van"
end

-- The gear for `share` of the top speed (1 … gears), from the one in now: up a little past its top edge, down a
-- little under its bottom edge (no hunting when the speed sits at an edge). Several gears at once after a jump.
function DriveFeel.shift(gear: number, share: number, gears: number): number
	local g = math.clamp(math.floor(gear), 1, gears)
	for _ = 1, gears do
		if g < gears and share > g / gears + Engine.Shift then
			g += 1
		elseif g > 1 and share < (g - 1) / gears - Engine.Shift then
			g -= 1
		else
			break
		end
	end
	return g
end

-- The engine loop's pitch (PlaybackSpeed) and volume: share of the top speed (0 … above 1 on a boost), the gear
-- (DriveFeel.shift), the throttle (-1 … 1; the driver's), boost (the nitro: a touch higher).
function DriveFeel.engine(class: string, share: number, gear: number, throttle: number, boost: boolean): (number, number)
	local spec = Engine.Classes[class] or Engine.Classes.van
	local gears = spec.Gears
	local g = math.clamp(gear, 1, gears)
	local s = math.max(0, share)
	-- where the revs are in this gear: from nothing in the first gear, from a third up after a shift
	local within = math.clamp(s * gears - (g - 1), 0, 1.15)
	local rev = if g == 1 then within else 0.35 + 0.65 * within
	local climb = if gears > 1 then (g - 1) / (gears - 1) else 1
	rev *= 0.7 + 0.3 * climb
	local on = math.max(0, throttle)
	if s < 0.04 and on > 0 then
		rev = math.max(rev, Engine.Rev * on) -- revving at a stand (stuck, held by the open back)
	end
	local span = spec.Top - spec.Idle
	local pitch = spec.Idle + span * rev + (if on > 0 then Engine.Load * on else -Engine.Coast * math.min(1, s * 4))
		+ (if boost then 0.08 else 0)
	local volume = spec.Volume * (0.72 + 0.28 * math.min(s, 1)) * (if on > 0 then 1 else 0.8)
	return math.max(spec.Idle * 0.9, pitch), volume
end

function DriveFeel.streaks(share: number, twoWheels: boolean): number
	local lines = Feel.SpeedLines
	if twoWheels then
		return ramp(share, lines.TwoFrom, lines.TwoFull)
	end
	return ramp(share, lines.From, lines.Full)
end

return DriveFeel
