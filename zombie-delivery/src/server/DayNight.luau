--!strict
-- Day and night (Config.DayNight). [STUB: stream "world-night" fills this in: the clock running Lighting.ClockTime,
-- the night look, workspace attribute "Night" (boolean) for everybody, the street lamps and headlights.]

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local Lighting = game:GetService("Lighting")

local DayNight = {}

-- Is it night now (Config.DayNight NightFrom … NightTo)?
function DayNight.isNight(): boolean
	local hour = Lighting.ClockTime
	return hour >= Config.DayNight.NightFrom or hour < Config.DayNight.NightTo
end

-- 0 in full day … 1 in deep night (smooth around dusk and dawn), for scaling the waves, roamers and pay.
function DayNight.nightFactor(): number
	return if DayNight.isNight() then 1 else 0
end

-- Set the clock (the admin panel's time buttons).
function DayNight.setClock(hour: number)
	Lighting.ClockTime = hour % 24
end

function DayNight.start() end

return DayNight
