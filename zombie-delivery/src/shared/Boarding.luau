--!strict
-- 3.10: getting in and out of a car, the pure part (no Roblox at its top level, so tests/boarding_test.luau runs it in
-- the standalone Luau): the timing of the move (Config.Cargo BoardSeconds, BoardStepSeconds, AlightSeconds), the
-- curve the body follows (plain numbers: the client builds its CFrames from them, client/CarBoarding.luau), the hand
-- on the handle (client/ArmPose.luau), a door's swing from its DoorOpenAt / DoorCloseAt (client/CarVisuals.luau,
-- server/Vehicles.luau) and the character attribute that names the seat ("ownerId:door:seat", seat 0 = the driver's).
--
-- Getting in, t seconds after the server's BoardAt:
--   0 .. BoardStepSeconds          a step to the handle (turning to the door), the hand goes to the handle
--   BoardStepSeconds .. BoardSeconds  the slide in through the door to the seat, ducking a little on the way
--   BoardSeconds                    the server seats you (Seat:Sit); the door shuts in DoorShutSeconds
-- Getting out: the door opens at once, the slide out to the door side takes AlightSeconds, then the door shuts.

local Config = require(script.Parent.Config)

local Boarding = {}

-- Smooth start, smooth end (0..1 → 0..1).
function Boarding.ease(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end

-- Where the move to get in is at t seconds: "step" (to the handle) or "slide" (into the seat), with the eased
-- progress of that part (0..1); after the end ("done", 1).
function Boarding.boardPhase(t: number): (string, number)
	local cfg = Config.Cargo
	local total, step = cfg.BoardSeconds, math.min(cfg.BoardStepSeconds, cfg.BoardSeconds)
	if t >= total then
		return "done", 1
	elseif t < step then
		return "step", Boarding.ease(if step > 0 then math.max(0, t) / step else 1)
	end
	return "slide", Boarding.ease((t - step) / math.max(1e-3, total - step))
end

-- The client sees the server's BoardAt `late` seconds after it (the attribute travels): it plays the whole move in
-- what is left until the server seats it, never quicker than `minSpan`. Returns how long its move takes.
function Boarding.span(late: number, total: number, minSpan: number): number
	return math.max(minSpan, total - math.max(0, late))
end

-- The move's time (0 .. total) `since` seconds after the client started it, played over `span` seconds.
function Boarding.moveTime(since: number, span: number, total: number): number
	if span <= 0 then
		return total
	end
	return total * math.clamp(since / span, 0, 1)
end

-- A quadratic Bezier between a and c, pulled toward b (one coordinate).
function Boarding.bezier(a: number, b: number, c: number, u: number): number
	local v = 1 - u
	return v * v * a + 2 * v * u * b + u * u * c
end

-- How far the body ducks forward (radians) at the slide's progress u: none at the ends, the most halfway.
function Boarding.duck(u: number): number
	return math.rad(Config.Cargo.BoardDuck) * math.sin(math.pi * math.clamp(u, 0, 1))
end

-- The slide's middle point (the door opening, chassis space): on the body's outer face at the door, the higher end
-- of the move (plus the climb's arc over a doorless seat). side: -1 left, 1 right; outside: the body's half width
-- there; (fromY, fromZ) the start, toY the end.
function Boarding.through(side: number, outside: number, fromY: number, fromZ: number, toY: number, climb: boolean): (number, number, number)
	local y = math.max(fromY, toY) + (if climb then Config.Cargo.ClimbArc else 0.3)
	return side * outside, y, fromZ
end

-- The hand on the handle (getting in) or pushing the door (getting out), `elapsed` seconds after BoardAt / AlightAt:
-- how far the reach pose is laid over the arm (0..1).
function Boarding.reach(elapsed: number, out: boolean): number
	if elapsed < 0 then
		return 0
	end
	if out then
		-- A quick push: up in 0.08 s, gone by 0.25 s.
		if elapsed < 0.08 then
			return 0.7 * Boarding.ease(elapsed / 0.08)
		end
		return 0.7 * (1 - Boarding.ease((elapsed - 0.08) / 0.17))
	end
	local step = Config.Cargo.BoardStepSeconds
	if elapsed < step then
		return Boarding.ease(elapsed / step)
	elseif elapsed < step + 0.12 then
		return 1
	end
	return 1 - Boarding.ease((elapsed - step - 0.12) / 0.18)
end

-- A door's goal at server time `now`: open (1) from openAt until closeAt, else shut (0).
function Boarding.doorGoal(now: number, openAt: number?, closeAt: number?): number
	if openAt and now >= openAt and (closeAt == nil or now < closeAt) then
		return 1
	end
	return 0
end

-- A door swung toward its goal over dt (open in DoorSwingSeconds, shut in DoorShutSeconds); open 0..1.
function Boarding.doorStep(open: number, goal: number, dt: number): number
	local cfg = Config.Cargo
	if goal > open then
		return math.min(goal, open + dt / math.max(1e-3, cfg.DoorSwingSeconds))
	elseif goal < open then
		return math.max(goal, open - dt / math.max(1e-3, cfg.DoorShutSeconds))
	end
	return open
end

-- Two people at one door: the new opening (newOpen .. newClose) joined with the one the door has (oldOpen ..
-- oldClose) while that one still runs at `now`: it opens at the earlier time and shuts at the later one.
function Boarding.mergeDoor(oldOpen: number?, oldClose: number?, newOpen: number, newClose: number, now: number): (number, number)
	if oldOpen and oldClose and oldClose > now then
		return math.min(oldOpen, newOpen), math.max(oldClose, newClose)
	end
	return newOpen, newClose
end

-- The character attribute Boarding names the car (its owner's UserId), the door and the seat (0 = the driver's).
function Boarding.encode(ownerId: number, door: number, seat: number): string
	return `{ownerId}:{door}:{seat}`
end

function Boarding.decode(value: any): (number?, number?, number?)
	if type(value) ~= "string" then
		return nil, nil, nil
	end
	local a, b, c = string.match(value, "^(%-?%d+):(%d+):(%d+)$")
	if not a or not b or not c then
		return nil, nil, nil
	end
	return tonumber(a), tonumber(b), tonumber(c)
end

-- Is a point (chassis space, X across, Z along) still over the car's footprint (half sizes)? The server puts somebody
-- who got out but is still there out at their door.
function Boarding.inside(x: number, z: number, halfX: number, halfZ: number): boolean
	return math.abs(x) < halfX + 0.3 and math.abs(z) < halfZ + 0.3
end

return Boarding
