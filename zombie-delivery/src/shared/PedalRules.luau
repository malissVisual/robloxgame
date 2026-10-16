--!strict
-- 8.9.4 (the owner: "on the screen as if driving with pedals, an automatic"): what the driving dashboard shows
-- (client/DrivePedals.luau), from the driver's throttle (client/Drive.luau Drive.throttle: -1 … 1, S and the arrows' down
-- below 0) and the car's speed along its nose (Drive.speed: studs a second, backing up below 0). Pure (no Roblox at its
-- top level): tests/pedalrules_test.luau runs it in the plain Luau CLI. Drive.luau drives as before; this only says
-- which pedal that is and in which gear, as an automatic would:
--   * standing (slower than Config.DrivePedals.Stop) with nothing pressed: P;
--   * W / up: D and the gas (as far down as the throttle); while backing up it is the brake (it stops you first);
--   * S / down while rolling forward: the brake (D stays in); standing or backing up: R and the gas (an automatic backs
--     up on the gas in R);
--   * rolling with nothing pressed: D, or R while backing up (no pedal).
--   PedalRules.state(throttle, speed)   { gear ("P" | "R" | "N" | "D"), gas (0 … 1), brake (0 … 1) }
--   PedalRules.ease(shown, want, dt)    a pedal's travel one step toward where the foot puts it (Config.DrivePedals.Ease)
--   PedalRules.Gears                    the selector's letters, top to bottom
local Config = require(script.Parent.Config)

local PedalRules = {}

export type State = { gear: string, gas: number, brake: number }

PedalRules.Gears = { "P", "R", "N", "D" }

local function tune(): any
	local t = (Config :: any).DrivePedals
	return if type(t) == "table" then t else { Stop = 0.5, Ease = 9 }
end

local function finite(n: any): number
	return if type(n) == "number" and n == n and n > -math.huge and n < math.huge then n else 0
end

function PedalRules.state(throttle: number, speed: number): State
	local t, v = math.clamp(finite(throttle), -1, 1), finite(speed)
	local stop = tune().Stop or 0.5
	if t > 0 then
		if v < -stop then
			return { gear = "R", gas = 0, brake = t } -- (forward while backing up: it brakes first)
		end
		return { gear = "D", gas = t, brake = 0 }
	elseif t < 0 then
		if v > stop then
			return { gear = "D", gas = 0, brake = -t }
		end
		return { gear = "R", gas = -t, brake = 0 }
	end
	if v > stop then
		return { gear = "D", gas = 0, brake = 0 }
	elseif v < -stop then
		return { gear = "R", gas = 0, brake = 0 }
	end
	return { gear = "P", gas = 0, brake = 0 }
end

function PedalRules.ease(shown: number, want: number, dt: number): number
	local rate = finite(tune().Ease)
	local step = math.max(0, finite(dt)) * (if rate > 0 then rate else 9)
	local from, to = finite(shown), math.clamp(finite(want), 0, 1)
	if math.abs(to - from) <= step then
		return to
	end
	return from + (if to > from then step else -step)
end

return PedalRules
