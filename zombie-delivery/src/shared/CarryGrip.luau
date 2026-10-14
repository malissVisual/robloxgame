--!strict
-- 8.1 grip (the owner: "when I fail, something must always happen, but make it easier, it can get harder later; it is
-- hard to keep pressing and walk at the same time. When we pick it up the first time I should have to hit a target:
-- I'm feeling for the grip, and when I succeed I can carry it away, I keep my balance"), pure (no Roblox at the top
-- level: tests/carrygrip_test.luau). The 7.0 bar you held all the way is gone: a carry with a grip has TIMING CHECKS.
-- A needle sweeps a bar back and forth at a steady speed (it starts at the left end, going right); a green zone lies
-- on it; one press (the left mouse button or F, a gamepad's R2, the touch TAP button) while the needle is in the zone
-- is a hit. No press within the check's window is a miss.
--   * The lift check ("feeling for the grip"): Pick up / Lift / Help lift on a piece with a grip opens one; a hit lifts
--     it balanced (the steady walk), a miss knocks it (it slips back down where it stood) and you try again.
--   * Wobbles: while you carry it, a WOBBLE! check now and then (Wobble.Every s of walking; sooner when you go faster
--     than the carry's walk, turn hard, jump or get bitten; seldom standing still). A hit: steady again. A miss always
--     does something: a stagger (a knock, a short slowdown, the next wobble sooner) or, the Drop-th miss in a row (a
--     fragile piece: the first), a drop.
-- client/CarryGripUi.luau draws a check and reads the press; server/Moving.luau's grip block opens the checks, judges
-- the answers (CarryGrip.judge: a hit only in an open check, at a press time the needle was in the zone) and applies
-- the outcome. Every number is Config.CarryGrip's (Difficulty: × the needles, ÷ the zones).
--
--   CarryGrip.kind(class, fragile, helped, role)   the carry's kind ("hand" | "both" | "pair" | "solo" | "drag"), nil:
--                                         no checks (a one-hand thing that is not fragile). helped: a pair thing has
--                                         its second carrier; role: its carrier's (a Mover alone with it: "solo")
--   CarryGrip.encode(kind, weight, fragile) / decode(text)   the character attribute CarryGrip ("both 4 fragile")
--   CarryGrip.profile(kind, weight, fragile, mover, steadied?)   a carry's checks: the zone, the needle, × the wobbles'
--                                         interval (steadied: Danny holds the other end, the zone × Steadied)
--   CarryGrip.check(profile, what, roll)  a check ("lift" | "wobble"): its zone's place from roll (0 … 1), its window
--   CarryGrip.needle(check, elapsed)      the needle's place (0 … 1) elapsed s into the check
--   CarryGrip.inZone(check, at, slack?)   is a place in the zone (widened by slack each side)?
--   CarryGrip.hits(check, elapsed)        a press elapsed s in: a hit?
--   CarryGrip.firstHit(check)             the first time the needle is at the zone's middle (s)
--   CarryGrip.judge(check, verdict, pressed, elapsed)   the server's verdict on an answer: a hit only for "ok", a
--                                         press time that can be true (not newer than the server's elapsed + Ahead,
--                                         not older than it − Lag, within the window) with the needle in the zone
--   CarryGrip.wire(check, extra?) / fromWire(raw)   a check as the Moving remote sends it, and back (checked numbers)
--   CarryGrip.dropAt(profile)             the wobble misses in a row that drop it
--   CarryGrip.outcome(what, hit, profile, misses)   "balanced" | "knock" (a lift), "steady" | "stagger" | "drop" (a
--                                         wobble; misses: in a row, this one counted)
--   CarryGrip.knock(what, fragile, shared)   the condition a lift miss or a stagger takes (shared: two players hold it)
--   CarryGrip.slipDamage(fragile)         the condition a drop takes
--   CarryGrip.speedFactor(steady, staggered?)   × the carry's walk
--   CarryGrip.interval(profile, roll, shaky)   s of the wobble clock to the next wobble (shaky: after a stagger)
--   CarryGrip.rate(speed, walk, turn, air)   the wobble clock's pace (1 at the carry's own walk)
--   CarryGrip.wobbles(profile, roll) / advance(w, dt, rate) / bump(w) / rearm(w, profile, roll, shaky)   the wobble
--                                         clock: advance says true when a wobble is due
-- No tables, closures or strings in needle / inZone / hits (the client asks every frame).

local Config = require(script.Parent.Config)

local CarryGrip = {}

export type Profile = {
	kind: string,
	weight: number,
	fragile: boolean,
	mover: boolean,
	steadied: boolean,
	zone: number, -- the lift check's green zone (a share of the sweep)
	speed: number, -- the lift check's needle (sweeps a second)
	every: number, -- × the time between two wobbles
}

export type Check = {
	what: string, -- "lift" | "wobble"
	zone0: number, -- the zone's left end (0 … 1)
	zone: number, -- its width
	speed: number, -- sweeps a second
	window: number, -- s to press
}

export type Wobbles = {
	due: number, -- the wobble clock (s) since the last check
	next: number, -- the clock's s when the next wobble comes
	gap: number, -- real s since the last check (Wobble.Gap)
}

local function tune(): any
	return (Config :: any).CarryGrip
end

-- A number, or 0 (nil, NaN, ±inf, a string a client sent).
local function finite(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return value
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function difficulty(): number
	local d = finite(tune().Difficulty)
	return if d > 0 then d else 1
end

-- ── The kind ───────────────────────────────────────────────────────────────

function CarryGrip.kind(class: string, fragile: boolean, helped: boolean, role: string?): string?
	if class == "hand" then
		return if fragile then "hand" else nil
	elseif class == "both" then
		return "both"
	elseif class == "pair" then
		if helped then
			return "pair"
		end
		return if role == "mover" then "solo" else "drag"
	end
	return nil
end

function CarryGrip.encode(kind: string, weight: number, fragile: boolean): string
	local w = math.clamp(math.floor(finite(weight) + 0.5), 0, 99)
	return `{kind} {w}{if fragile then " fragile" else ""}`
end

-- (kind, weight, fragile); kind nil: not a grip's attribute.
function CarryGrip.decode(text: any): (string?, number, boolean)
	if type(text) ~= "string" then
		return nil, 0, false
	end
	local kind, weight, rest = string.match(text, "^(%a+) (%d+)(.*)$")
	if not kind or not weight or not tune().Kinds[kind] then
		return nil, 0, false
	end
	return kind, tonumber(weight) or 0, rest == " fragile"
end

-- ── The checks ─────────────────────────────────────────────────────────────

function CarryGrip.profile(kind: string, weight: number, fragile: boolean, mover: boolean, steadied: boolean?): Profile
	local t = tune()
	local k = t.Kinds[kind] or t.Kinds.both
	local w = math.clamp(finite(weight), 0, 10)
	local d = difficulty()
	local zone = (k.Zone - w * t.Weight.Zone) * (if fragile then t.Fragile.Zone else 1)
	zone *= (if mover then t.Mover else 1) * (if steadied then t.Steadied else 1) / d
	local speed = (k.Speed + w * t.Weight.Speed) * (if fragile then t.Fragile.Speed else 1) * d
	return {
		kind = if t.Kinds[kind] then kind else "both",
		weight = w,
		fragile = fragile,
		mover = mover,
		steadied = steadied == true,
		zone = math.clamp(zone, t.Zone.Min, t.Zone.Max),
		speed = math.clamp(speed, t.Speed.Min, t.Speed.Max),
		every = k.Every,
	}
end

-- A check of `profile`: a lift's as the profile has it, a wobble's zone × Wobble.Zone and needle × Wobble.Speed (kept
-- within Zone / Speed's bounds); the zone at roll (0 … 1) of the room between Zone.Start and the right end less Edge;
-- the window the kind's, at least Speed.Sweeps sweeps.
function CarryGrip.check(profile: Profile, what: string, roll: number): Check
	local t = tune()
	local wobble = what == "wobble"
	local zone = math.clamp(profile.zone * (if wobble then t.Wobble.Zone else 1), t.Zone.Min, t.Zone.Max)
	local speed = math.clamp(profile.speed * (if wobble then t.Wobble.Speed else 1), t.Speed.Min, t.Speed.Max)
	local lo = t.Zone.Start
	local hi = math.max(lo, 1 - t.Zone.Edge - zone)
	local zone0 = math.min(lo + (hi - lo) * math.clamp(finite(roll), 0, 1), 1 - zone)
	local window = math.max(if wobble then t.Wobble.Window else t.Lift.Window, t.Speed.Sweeps / speed)
	return { what = if wobble then "wobble" else "lift", zone0 = zone0, zone = zone, speed = speed, window = window }
end

-- The needle elapsed s in: a triangle wave from 0 (the left end) right to 1, back to 0, at check.speed sweeps a second.
function CarryGrip.needle(check: Check, elapsed: number): number
	local u = (math.max(0, finite(elapsed)) * check.speed) % 2
	return if u <= 1 then u else 2 - u
end

function CarryGrip.inZone(check: Check, at: number, slack: number?): boolean
	local s = slack or 0
	return at >= check.zone0 - s and at <= check.zone0 + check.zone + s
end

function CarryGrip.hits(check: Check, elapsed: number): boolean
	local e = finite(elapsed)
	if e < 0 or e > check.window then
		return false
	end
	return CarryGrip.inZone(check, CarryGrip.needle(check, e))
end

function CarryGrip.firstHit(check: Check): number
	return (check.zone0 + check.zone / 2) / check.speed
end

-- The server's verdict on an answer (verdict "ok" | "miss", the press `pressed` s into the check by the client's
-- clock, `elapsed` s since the server opened it): a hit only for an "ok" whose press can be true and whose needle was
-- in the zone (Server.Slack wider each side); anything else a miss. `lag`: the most this player's press may be older
-- than the server's clock (CarryGrip.lagFor: their ping; nil: Server.Lag), never more than Server.Lag.
function CarryGrip.judge(check: Check, verdict: any, pressed: any, elapsed: number, lag: number?): boolean
	if verdict ~= "ok" or not isFinite(pressed) then
		return false
	end
	local s = tune().Server
	local p = pressed :: number
	local most = if lag and isFinite(lag) and lag >= 0 then math.min(lag, s.Lag) else s.Lag
	if p < 0 or p > check.window + s.Ahead or p > elapsed + s.Ahead or p < elapsed - most then
		return false
	end
	return CarryGrip.inZone(check, CarryGrip.needle(check, p), s.Slack)
end

-- 8.1 review: how much older than the server's clock a press of a player with this round trip (`ping` s, the
-- server's Player:GetNetworkPing; nil: unknown) may be: Server.LagPing × it + Server.LagMin, never more than Server.Lag
-- (a press claimed long ago no longer passes for one in time).
function CarryGrip.lagFor(ping: number?): number
	local s = tune().Server
	if not ping or not isFinite(ping) or ping < 0 then
		return s.Lag
	end
	return math.min(s.Lag, ping * s.LagPing + s.LagMin)
end

-- A check as the Moving remote sends it ("grip", "open", wire): its numbers, plus the server's own fields (`extra`: the
-- id, the spot, the piece's name and icon, whether a miss drops it).
function CarryGrip.wire(check: Check, extra: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = if extra then table.clone(extra) else {}
	out.what, out.zone0, out.zone, out.speed, out.window = check.what, check.zone0, check.zone, check.speed, check.window
	return out
end

-- The check in a wire table (nil: not one: a number missing or out of bounds).
function CarryGrip.fromWire(raw: any): Check?
	if type(raw) ~= "table" then
		return nil
	end
	local zone0, zone, speed, window = raw.zone0, raw.zone, raw.speed, raw.window
	if not isFinite(zone0) or not isFinite(zone) or not isFinite(speed) or not isFinite(window) then
		return nil
	end
	if zone <= 0 or zone >= 1 or zone0 < 0 or zone0 + zone > 1 + 1e-6 or speed <= 0 or speed > 10 or window <= 0 or window > 30 then
		return nil
	end
	return { what = if raw.what == "wobble" then "wobble" else "lift", zone0 = zone0, zone = zone, speed = speed, window = window }
end

-- ── The outcomes ───────────────────────────────────────────────────────────

function CarryGrip.dropAt(profile: Profile): number
	local drop = tune().Miss.Drop
	local at = if profile.fragile then drop.Fragile elseif profile.weight >= drop.HeavyAt then drop.Heavy else drop.Sturdy
	return math.max(1, math.floor(finite(at) + 0.5))
end

function CarryGrip.outcome(what: string, hit: boolean, profile: Profile, misses: number): string
	if what ~= "wobble" then
		return if hit then "balanced" else "knock"
	end
	if hit then
		return "steady"
	end
	return if finite(misses) >= CarryGrip.dropAt(profile) then "drop" else "stagger"
end

function CarryGrip.knock(what: string, fragile: boolean, shared: boolean?): number
	local t = tune()
	local base = if what == "wobble" then t.Miss.Knock else t.Lift.Knock
	return base * (if fragile then t.FragileKnock else 1) * (if shared then t.Shared else 1)
end

function CarryGrip.slipDamage(fragile: boolean): number
	return tune().Slip * (if fragile then (Config :: any).Moving.Damage.Fragile else 1)
end

function CarryGrip.speedFactor(steady: boolean, staggered: boolean?): number
	local t = tune()
	return (if steady then t.SteadySpeed else 1) * (if staggered then t.Miss.Slow else 1)
end

-- ── The wobble clock ───────────────────────────────────────────────────────

function CarryGrip.interval(profile: Profile, roll: number, shaky: boolean): number
	local t = tune()
	local every = t.Wobble.Every
	local s = every[1] + (every[2] - every[1]) * math.clamp(finite(roll), 0, 1)
	return s * profile.every * (if shaky then t.Miss.Sooner else 1)
end

-- The clock's pace: Still standing still (under StillAt studs/s), up to 1 at `walk` (the carry's walk), + Rush × how far
-- over it (all of it half again over), + Turn turning at TurnFull rad/s, + Air in the air.
function CarryGrip.rate(speed: number, walk: number, turn: number, air: boolean): number
	local w = tune().Wobble
	local v = math.max(0, finite(speed))
	local share = if v < w.StillAt then 0 else v / math.max(finite(walk), 1)
	local pace = w.Still + (1 - w.Still) * math.min(share, 1)
	pace += w.Rush * math.clamp((share - 1) / 0.5, 0, 1)
	pace += w.Turn * math.clamp(math.abs(finite(turn)) / w.TurnFull, 0, 1)
	return pace + (if air then w.Air else 0)
end

function CarryGrip.wobbles(profile: Profile, roll: number): Wobbles
	return { due = 0, next = CarryGrip.interval(profile, roll, false), gap = 0 }
end

function CarryGrip.advance(w: Wobbles, dt: number, rate: number): boolean
	local d = math.max(0, finite(dt))
	w.due += d * math.max(0, finite(rate))
	w.gap += d
	return w.due >= w.next and w.gap >= tune().Wobble.Gap
end

function CarryGrip.bump(w: Wobbles)
	w.due += tune().Wobble.Bump
end

function CarryGrip.rearm(w: Wobbles, profile: Profile, roll: number, shaky: boolean)
	w.due, w.gap = 0, 0
	w.next = CarryGrip.interval(profile, roll, shaky)
end

return CarryGrip
