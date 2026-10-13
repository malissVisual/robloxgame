--!strict
-- 7.0 grip (the owner, like the Roblox game Fisch's reeling: "while you carry something a bar shows, the load keeps
-- slipping away and you click / hold to keep it under control; hold it and you get it to the truck"): the grip bar of a
-- carried thing, pure (no Roblox at the top level: tests/carrygrip_test.luau). client/CarryGripUi.luau runs it every
-- frame and draws it; server/Moving.luau's grip block names the carry's kind (the character attribute CarryGrip,
-- CarryGrip.encode), drops a thing whose bar ran out (the Moving remote's "slip") and wears one that shook (its
-- "grip" reports: CarryGrip.wear). The numbers are Config.CarryGrip's.
--
-- The bar runs from 0 (its bottom) to 1 (its top). The LOAD (the thing's icon) darts up and down by itself, the wilder
-- the heavier and the more fragile it is, the faster you walk, the sharper you turn, up or down a slope, in a jump or
-- bitten; standing still it calms down. The GRIP (a box) rises while you hold (the left mouse button or F, a gamepad's
-- R2, the touch HOLD button) and falls back when you let go, with momentum and a little bounce at the bottom. The METER
-- fills while the load is inside the box and drains while it is out (standing still: never under Meter.Floor); full,
-- you are steady (the carry's walk × Meter.SteadySpeed); at Meter.Warn it is SLIPPING!; at 0 the thing slips out of
-- your hands.
--
--   CarryGrip.kind(class, fragile, helped, role)   the carry's kind ("hand" | "both" | "pair" | "solo" | "drag"), nil:
--                                         no bar (a one-hand thing that is not fragile). helped: a pair thing has its
--                                         second carrier; role: its carrier's (a Mover alone with it: "solo")
--   CarryGrip.encode(kind, weight, fragile) / decode(text)   the character attribute CarryGrip ("both 4 fragile")
--   CarryGrip.profile(kind, weight, fragile, mover)   the bar for one carry (its zone, load, gravity and start)
--                                         7.x steadied: Danny holds the other end (the zone × Steadied)
--   CarryGrip.new(profile, seed)          a bar at the lift: the load in the middle in the box, the meter at its start
--   CarryGrip.setProfile(sim, profile)    the same carry, another kind (a helper took the other end): the meter kept
--   CarryGrip.newInput()                  the body's state for a step (the client fills one table and reuses it)
--   CarryGrip.agitation(profile, input, shock)   the load's wildness now
--   CarryGrip.step(sim, input, dt) -> "slip"?   the bar after dt s (in steps of Step at most): "slip" once, when it ran out
--   CarryGrip.meterStep(sim, inside, still, dt)  the meter alone (step's)
--   CarryGrip.report(sim) -> (quality, steady)   the share of the time outside since the last report (and resets it)
--   CarryGrip.wear(quality, fragile, dt)  the condition a report takes on the server (WearCap a second at most)
--   CarryGrip.slipDamage(fragile)         the condition a slip takes
--   CarryGrip.speedFactor(steady)         × the carry's walk (SteadySpeed when steady)
-- Deterministic: the load's darts come from the bar's own seed (a xorshift), so a seed and the same steps give the same
-- bar. A step makes no tables, closures or strings (the client steps it every frame).

local Config = require(script.Parent.Config)

local CarryGrip = {}

export type Profile = {
	kind: string,
	weight: number,
	fragile: boolean,
	mover: boolean,
	zone: number, -- the grip box's share of the bar
	load: number, -- the load's own wildness
	gravity: number, -- × the box's fall
	start: number, -- the meter at the lift
}

export type Input = {
	hold: boolean, -- held now (a mouse button, F, R2, the touch HOLD)
	speed: number, -- studs/s along the ground
	turn: number, -- rad/s about the vertical
	climb: number, -- studs/s up or down on the ground (a slope, stairs)
	air: boolean, -- in the air (a jump, a fall)
	bite: number, -- hp lost since the last step (0: none)
}

export type Sim = {
	profile: Profile,
	zone: number, -- the box's bottom edge (0 … 1 - profile.zone)
	zoneVel: number,
	marker: number, -- the load's middle (0 … 1)
	markerVel: number,
	aim: number, -- where the load darts to
	dart: number, -- s to its next aim
	meter: number, -- 0 … 1
	agitation: number, -- the load's wildness at the last step
	shock: number, -- a bite's jolt, fading
	inside: boolean,
	still: boolean,
	steady: boolean,
	warn: boolean,
	slipped: boolean,
	outside: number, -- s outside the box since the last report
	window: number, -- s since the last report
	seed: number, -- the random state (xorshift32)
	time: number,
}

local function tune(): any
	return (Config :: any).CarryGrip
end

local function walk(): number
	return (Config :: any).Movement.Walk
end

-- A number, or 0 (nil, NaN, ±inf, a string a client sent).
local function finite(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return value
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

-- (kind, weight, fragile); kind nil: not a bar's attribute.
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

-- ── The bar ────────────────────────────────────────────────────────────────

function CarryGrip.profile(kind: string, weight: number, fragile: boolean, mover: boolean, steadied: boolean?): Profile
	local t = tune()
	local k = t.Kinds[kind] or t.Kinds.both
	local w = math.clamp(finite(weight), 0, 10)
	return {
		kind = if t.Kinds[kind] then kind else "both",
		weight = w,
		fragile = fragile,
		mover = mover,
		zone = math.clamp(k.Zone * (if mover then t.Mover else 1) * (if steadied then t.Steadied else 1), 0.05, 0.9),
		load = k.Load + w * t.Weight + (if fragile then t.Fragile else 0),
		gravity = k.Gravity,
		start = if w >= t.Meter.HeavyAt then t.Meter.HeavyStart else t.Meter.Start,
	}
end

-- xorshift32 (bit32: the same on every machine): 0 … 1.
local function random(sim: Sim): number
	local x = sim.seed
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	sim.seed = x
	return x / 4294967296
end

function CarryGrip.new(profile: Profile, seed: number?): Sim
	local s = bit32.band(math.floor(math.abs(finite(seed or 1))), 0xFFFFFFFF)
	local sim: Sim = {
		profile = profile,
		zone = math.clamp(0.5 - profile.zone / 2, 0, 1 - profile.zone),
		zoneVel = 0,
		marker = 0.5,
		markerVel = 0,
		aim = 0.5,
		dart = 0,
		meter = profile.start,
		agitation = 0,
		shock = 0,
		inside = true,
		still = true,
		steady = profile.start >= 1,
		warn = false,
		slipped = false,
		outside = 0,
		window = 0,
		seed = if s == 0 then 0x9E3779B9 else s,
		time = 0,
	}
	random(sim) -- (the first draw mixes a small seed)
	sim.dart = 0.4 + 0.4 * random(sim) -- (a calm moment at the lift before the first dart)
	return sim
end

function CarryGrip.setProfile(sim: Sim, profile: Profile)
	sim.profile = profile
	sim.zone = math.clamp(sim.zone, 0, 1 - profile.zone)
end

function CarryGrip.newInput(): Input
	return { hold = false, speed = 0, turn = 0, climb = 0, air = false, bite = 0 }
end

function CarryGrip.agitation(profile: Profile, input: Input, shock: number): number
	local m = tune().Motion
	local move = math.clamp(finite(input.speed) / walk(), 0, m.SpeedMax)
	local turn = math.clamp(math.abs(finite(input.turn)) / m.TurnFull, 0, 1)
	local climb = math.clamp(math.abs(finite(input.climb)) / m.SlopeFull, 0, 1)
	local motion = m.Still + move * m.Speed + turn * m.Turn + climb * m.Slope + (if input.air then m.Air else 0)
	return profile.load * (motion + math.max(0, finite(shock)))
end

function CarryGrip.meterStep(sim: Sim, inside: boolean, still: boolean, dt: number)
	local m = tune().Meter
	if inside then
		sim.meter = math.min(1, sim.meter + m.Fill * dt)
	else
		local drained = sim.meter - m.Drain * dt
		if still then
			drained = math.max(drained, math.min(sim.meter, m.Floor)) -- (standing still: you can recover)
		end
		sim.meter = math.max(0, drained)
	end
	if sim.meter >= 1 - 1e-9 then
		sim.steady = true
	elseif sim.meter < m.SteadyOff then
		sim.steady = false
	end
	sim.warn = sim.meter <= m.Warn
end

-- One step of at most Step s.
local function tick(sim: Sim, input: Input, dt: number)
	local t = tune()
	local p = sim.profile
	-- the load's wildness: the body's motion, a bite's jolt fading
	sim.shock = math.max(0, sim.shock - t.Motion.Fade * dt)
	local a = CarryGrip.agitation(p, input, sim.shock)
	sim.agitation = a
	sim.still = finite(input.speed) < t.Motion.StillAt and not input.air
	-- the load darts to a new aim now and then (wilder: sooner and farther), pulled there with a jitter
	local mk = t.Marker
	sim.dart -= dt
	if sim.dart <= 0 then
		local wild = math.clamp(a / mk.WildAt, 0, 1)
		sim.dart = (mk.Dart[2] + (mk.Dart[1] - mk.Dart[2]) * wild) * (0.7 + 0.6 * random(sim))
		local reach = mk.Reach * (mk.Base + a)
		sim.aim = math.clamp(sim.marker + (random(sim) * 2 - 1) * reach, mk.Edge, 1 - mk.Edge)
	end
	local pull = mk.Spring * (mk.Base + a)
	sim.markerVel += ((sim.aim - sim.marker) * pull + (random(sim) * 2 - 1) * mk.Jitter * a) * dt
	sim.markerVel *= math.exp(-mk.Damp * dt)
	sim.marker += sim.markerVel * dt
	if sim.marker < 0 then
		sim.marker, sim.markerVel = 0, 0
	elseif sim.marker > 1 then
		sim.marker, sim.markerVel = 1, 0
	end
	-- the grip box: up while held, down when let go (momentum), a little bounce off the bottom
	local g = t.Grip
	if input.hold then
		sim.zoneVel += g.Lift * dt
	else
		sim.zoneVel -= g.Gravity * p.gravity * dt
	end
	sim.zoneVel = math.clamp(sim.zoneVel, -g.Fall, g.Rise)
	sim.zone += sim.zoneVel * dt
	local top = 1 - p.zone
	if sim.zone <= 0 then
		sim.zone = 0
		sim.zoneVel = if sim.zoneVel < -g.BounceMin then -sim.zoneVel * g.Bounce else math.max(0, sim.zoneVel)
	elseif sim.zone >= top then
		sim.zone = top
		sim.zoneVel = math.min(0, sim.zoneVel)
	end
	-- the meter
	sim.inside = sim.marker >= sim.zone and sim.marker <= sim.zone + p.zone
	CarryGrip.meterStep(sim, sim.inside, sim.still, dt)
	sim.window += dt
	if not sim.inside then
		sim.outside += dt
	end
	sim.time += dt
end

function CarryGrip.step(sim: Sim, input: Input, dt: number): string?
	if sim.slipped then
		return nil
	end
	local t = tune()
	local left = math.clamp(finite(dt), 0, t.MaxDt)
	local bite = finite(input.bite)
	if bite > 0 then
		local m = t.Motion
		sim.shock = math.min(m.ShockMax, sim.shock + m.Bite * math.min(1, bite / m.BiteFull))
	end
	while left > 1e-9 do
		local d = math.min(left, t.Step)
		tick(sim, input, d)
		left -= d
		if sim.meter <= 0 then
			sim.slipped = true
			return "slip"
		end
	end
	return nil
end

function CarryGrip.report(sim: Sim): (number, boolean)
	local quality = if sim.window > 1e-6 then math.clamp(sim.outside / sim.window, 0, 1) else 0
	sim.outside, sim.window = 0, 0
	return quality, sim.steady
end

-- ── The server's side ──────────────────────────────────────────────────────

function CarryGrip.wear(quality: any, fragile: boolean, dt: any): number
	local s = tune().Server
	local q = math.clamp(finite(quality), 0, 1)
	local d = math.clamp(finite(dt), 0, s.Gap)
	return math.min(q * s.Wear * (if fragile then s.WearFragile else 1), s.WearCap) * d
end

function CarryGrip.slipDamage(fragile: boolean): number
	return tune().Server.Slip * (if fragile then (Config :: any).Moving.Damage.Fragile else 1)
end

function CarryGrip.speedFactor(steady: boolean): number
	return if steady then tune().Meter.SteadySpeed else 1
end

return CarryGrip
