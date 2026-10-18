--!strict
-- 10.6 SNATCHING (Config.Rounds.Tug; the owner: "you can take it out of somebody's hands, but not so that you could just
-- take it … not somebody waiting at your car to take it straight out of your hands"): the rules of a tug of war over a
-- piece in a round, pure (no Roblox: tests/tugrules_test.luau). server/Runs.luau runs the tugs with them,
-- client/TugUi.luau shows them.
--
-- A tug: the rope's mark `p` from -1 (the carrier keeps it) to +1 (the snatcher takes it), from T.Start (on the
-- carrier's side: the carrier is favoured). Each one's pull (a press: E, a tap) moves it T.Pull, the carrier's T.Boost
-- times as far; a press counts at most T.Rate times a second (faster ones are not heard). It ends at either end or when
-- its T.Seconds are over: then the snatcher takes it only past the middle (a tie is the carrier's).
--   TugRules.new(now, T) -> Tug
--   TugRules.pull(tug, side, now, T) -> boolean      side "carrier" | "snatcher": heard?
--   TugRules.result(tug, now) -> side?               the winner once it is over, nil while it goes on
--   TugRules.open(c, T) -> (boolean, why?)           may the carrier in `c` be snatched from now? (why: "alone" a piece
--                                                    carried in two or none | "fresh" picked up under T.Protect s ago |
--                                                    "van" within T.SafeVan of their own van | "door" within T.SafeDoor
--                                                    of the house's door | "busy" in a tug, stunned or on a door's trip |
--                                                    "again" tugged at under T.Target s ago)
--   TugRules.grab(g, T) -> (boolean, why?)           may the snatcher in `g` start one? (why: "full" their hands are full |
--                                                    "busy" in a tug or stunned | "again" their last try under T.Again
--                                                    s ago | "far" out of T.Reach + 2)
local Config = require(script.Parent.Config)

local TugRules = {}

export type Tug = { p: number, startedAt: number, endsAt: number, last: { [string]: number }, pulls: { [string]: number } }
export type Tune = typeof(Config.Rounds.Tug)
export type Carrier = {
	carrying: boolean, -- holds a piece (its carrier)
	alone: boolean, -- nobody at its other end, not a two-person piece
	since: number, -- when they picked it up (server time)
	now: number,
	van: number?, -- studs to their own van's back (nil: not at the house: inside it)
	door: number?, -- studs to the house's front door outside (nil: inside)
	busy: boolean, -- in a tug, stunned, or on a door's trip
	targetAt: number?, -- when a tug at them last ended
}
export type Grabber = { full: boolean, busy: boolean, triedAt: number?, now: number, distance: number }

local SIDES = { carrier = true, snatcher = true }

function TugRules.new(now: number, T: Tune): Tug
	return { p = T.Start, startedAt = now, endsAt = now + T.Seconds, last = { carrier = -math.huge, snatcher = -math.huge }, pulls = { carrier = 0, snatcher = 0 } }
end

function TugRules.pull(tug: Tug, side: string, now: number, T: Tune): boolean
	if not SIDES[side] or now >= tug.endsAt or now < tug.startedAt or math.abs(tug.p) >= 1 then
		return false
	end
	if now - tug.last[side] < 1 / T.Rate - 1e-6 then
		return false
	end
	tug.last[side] = now
	tug.pulls[side] += 1
	local move = if side == "snatcher" then T.Pull else -T.Pull * T.Boost
	tug.p = math.clamp(tug.p + move, -1, 1)
	return true
end

function TugRules.result(tug: Tug, now: number): string?
	if tug.p >= 1 then
		return "snatcher"
	elseif tug.p <= -1 then
		return "carrier"
	elseif now >= tug.endsAt then
		return if tug.p > 0 then "snatcher" else "carrier"
	end
	return nil
end

function TugRules.open(c: Carrier, T: Tune): (boolean, string?)
	if not c.carrying or not c.alone then
		return false, "alone"
	elseif c.busy then
		return false, "busy"
	elseif c.now - c.since < T.Protect then
		return false, "fresh"
	elseif c.van ~= nil and c.van <= T.SafeVan then
		return false, "van"
	elseif c.door ~= nil and c.door <= T.SafeDoor then
		return false, "door"
	elseif c.targetAt ~= nil and c.now - c.targetAt < T.Target then
		return false, "again"
	end
	return true, nil
end

function TugRules.grab(g: Grabber, T: Tune): (boolean, string?)
	if g.full then
		return false, "full"
	elseif g.busy then
		return false, "busy"
	elseif g.triedAt ~= nil and g.now - g.triedAt < T.Again then
		return false, "again"
	elseif g.distance > T.Reach + 2 then
		return false, "far"
	end
	return true, nil
end

return TugRules
