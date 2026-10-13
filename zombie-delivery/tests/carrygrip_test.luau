-- 7.0 grip: the carry's grip bar (shared/CarryGrip.luau, pure; the owner: "like Fisch: the load keeps slipping away,
-- you hold to keep it under control"): which carries have a bar (a fragile one-hand thing, "both", "pair", a Mover's
-- pair thing alone, a pair thing dragged), the attribute's code, the profiles (the Mover's bigger box, a solo pair
-- harder, a heavy lift starting low), the grip box (up while held, gravity, the bounce), the load's wildness (weight,
-- fragile, speed, turns, slopes, a jump, a bite; calm standing still), the meter (fill, drain, the floor standing still,
-- steady, the warning, the slip once at 0), the reports and the server's wear, the same bar for the same seed, and
-- played: an attentive player keeps it, one who never holds drops it in seconds, one who stands still never does.
-- And where it sits (client/MoveLayout.luau grip): the HOLD button a finger's size and more, at the right over the touch
-- buttons, clear of them; the panel right of the middle, clear of them and of the button. Run with tests/run_tests.py.
local CarryGrip = require("./CarryGrip")
local Config = require("./Config")
local MoveLayout = require("./MoveLayout")
local TouchLayout = require("./TouchLayout")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local G = Config.CarryGrip
local WALK = Config.Movement.Walk
local DT = 1 / 60

-- ── The kinds and the attribute ─────────────────────────────────────────────

check("a one-hand thing: a bar only when fragile (gentler: \"hand\")", CarryGrip.kind("hand", false, false, nil) == nil and CarryGrip.kind("hand", true, false, nil) == "hand")
check("both hands: always", CarryGrip.kind("both", false, false, nil) == "both" and CarryGrip.kind("both", true, false, "mover") == "both")
check("a pair thing: two carry it (each their own bar)", CarryGrip.kind("pair", false, true, nil) == "pair" and CarryGrip.kind("pair", false, true, "mover") == "pair")
check("…a Mover alone: solo; anybody else alone: dragged", CarryGrip.kind("pair", false, false, "mover") == "solo" and CarryGrip.kind("pair", true, false, "guard") == "drag"
	and CarryGrip.kind("pair", false, false, nil) == "drag")
check("an unknown class: no bar", CarryGrip.kind("wheel", true, false, nil) == nil)
do
	local code = CarryGrip.encode("both", 4, true)
	local kind, weight, fragile = CarryGrip.decode(code)
	check("the attribute: \"both 4 fragile\" and back", code == "both 4 fragile" and kind == "both" and weight == 4 and fragile == true, code)
	local k2, w2, f2 = CarryGrip.decode(CarryGrip.encode("pair", 10, false))
	check("…\"pair 10\" (not fragile)", k2 == "pair" and w2 == 10 and f2 == false)
	check("…nonsense, an unknown kind, nil: no bar", CarryGrip.decode("sofa") == nil and CarryGrip.decode("wheel 3") == nil and CarryGrip.decode(nil) == nil and CarryGrip.decode(42) == nil)
end

-- ── The profiles ────────────────────────────────────────────────────────────

do
	local moverAll = true
	for kind in G.Kinds do
		local plain = CarryGrip.profile(kind, 5, false, false)
		local mover = CarryGrip.profile(kind, 5, false, true)
		moverAll = moverAll and math.abs(mover.zone - plain.zone * G.Mover) < 1e-9 and math.abs(G.Mover - 1.35) < 1e-9
	end
	check("the Mover: a 35% bigger grip box on every kind", moverAll)
	local pair = CarryGrip.profile("pair", 10, false, true)
	local solo = CarryGrip.profile("solo", 10, false, true)
	check("a Mover alone with a pair thing: a smaller box, a wilder load, a heavier fall than with a helper", solo.zone < pair.zone and solo.load > pair.load and solo.gravity > pair.gravity)
	local hand = CarryGrip.profile("hand", 2, true, false)
	local both = CarryGrip.profile("both", 2, true, false)
	check("a fragile one-hand thing is gentler than a both-hands one", hand.zone > both.zone and hand.load < both.load)
	check("the load: heavier and fragile, wilder", CarryGrip.profile("both", 9, false, false).load > CarryGrip.profile("both", 3, false, false).load
		and CarryGrip.profile("both", 4, true, false).load > CarryGrip.profile("both", 4, false, false).load)
	check("a heavy lift starts the meter at 60% (the first seconds matter), a light one higher", CarryGrip.profile("pair", G.Meter.HeavyAt, false, false).start == 0.6
		and CarryGrip.profile("both", G.Meter.HeavyAt - 1, false, false).start == G.Meter.Start and G.Meter.Start > 0.6)
	check("an unknown kind: a both-hands bar", CarryGrip.profile("wheel", 3, false, false).kind == "both")
end

-- ── The grip box ────────────────────────────────────────────────────────────

do
	local sim = CarryGrip.new(CarryGrip.profile("both", 4, false, false), 7)
	local input = CarryGrip.newInput()
	local start = sim.zone
	input.hold = true
	for _ = 1, 15 do
		CarryGrip.step(sim, input, DT)
	end
	check("holding raises the box (with momentum)", sim.zone > start and sim.zoneVel > 0, sim.zone)
	local risen, speed = sim.zone, sim.zoneVel
	input.hold = false
	CarryGrip.step(sim, input, DT)
	check("let go: it keeps rising a moment, slower (gravity)", sim.zone > risen and sim.zoneVel < speed)
	for _ = 1, 40 do
		CarryGrip.step(sim, input, DT)
	end
	check("…then falls", sim.zone < risen and sim.zoneVel < 0, `{sim.zone} {sim.zoneVel}`)
	local bounced = false
	for _ = 1, 120 do
		local before = sim.zoneVel
		CarryGrip.step(sim, input, DT)
		if before < -G.Grip.BounceMin and sim.zoneVel > 0 then
			bounced = true
		end
	end
	check("a little bounce off the bottom, then it rests there", bounced and sim.zone == 0 and sim.zoneVel == 0)
	input.hold = true
	for _ = 1, 60 * 4 do
		CarryGrip.step(sim, input, DT)
	end
	check("held long: it stops at the top", math.abs(sim.zone - (1 - sim.profile.zone)) < 1e-9 and sim.zoneVel == 0)
	local fastest = 0
	sim = CarryGrip.new(CarryGrip.profile("both", 4, false, false), 7)
	for _ = 1, 20 do
		CarryGrip.step(sim, input, DT)
		fastest = math.max(fastest, sim.zoneVel)
	end
	check("…never faster than Rise", fastest <= G.Grip.Rise + 1e-9)
end

-- ── The load's wildness ─────────────────────────────────────────────────────

do
	local p = CarryGrip.profile("both", 5, false, false)
	local still = CarryGrip.newInput()
	local walk = CarryGrip.newInput()
	walk.speed = WALK * 0.75
	local a0, a1 = CarryGrip.agitation(p, still, 0), CarryGrip.agitation(p, walk, 0)
	check("calmer standing still than walking", a0 < a1 and a0 > 0, `{a0} {a1}`)
	local fast = CarryGrip.newInput()
	fast.speed = WALK * 1.6
	check("…wilder the faster you go (a sprint)", CarryGrip.agitation(p, fast, 0) > a1)
	local turning = CarryGrip.newInput()
	turning.speed, turning.turn = walk.speed, 3
	local sloped = CarryGrip.newInput()
	sloped.speed, sloped.climb = walk.speed, -5
	local jumping = CarryGrip.newInput()
	jumping.speed, jumping.air = walk.speed, true
	check("…turning sharply, up or down a slope, in a jump", CarryGrip.agitation(p, turning, 0) > a1 and CarryGrip.agitation(p, sloped, 0) > a1
		and CarryGrip.agitation(p, jumping, 0) > a1)
	check("…bitten (the jolt)", CarryGrip.agitation(p, walk, 0.8) > a1)
	check("…heavier, fragile", CarryGrip.agitation(CarryGrip.profile("both", 10, false, false), walk, 0) > a1
		and CarryGrip.agitation(CarryGrip.profile("both", 5, true, false), walk, 0) > a1)
	check("nonsense from the body counts as nothing", CarryGrip.agitation(p, { hold = false, speed = 0 / 0, turn = math.huge, climb = -math.huge, air = false, bite = 0 }, 0 / 0) == a0)
	-- the load's travel over 20 s: walking more than standing, a heavy fragile thing more than a light one
	local function travel(profile: CarryGrip.Profile, input: CarryGrip.Input, seed: number): number
		local sim = CarryGrip.new(profile, seed)
		local sum, last = 0, sim.marker
		for _ = 1, 60 * 20 do
			CarryGrip.step(sim, input, DT)
			sum += math.abs(sim.marker - last)
			last = sim.marker
			sim.meter = 1 -- (kept alive: only the load's travel is measured)
		end
		return sum
	end
	local stand, go = 0, 0
	local light, heavy = 0, 0
	for seed = 1, 5 do
		stand += travel(p, still, seed * 31)
		go += travel(p, walk, seed * 31)
		light += travel(CarryGrip.profile("both", 2, false, false), walk, seed * 31)
		heavy += travel(CarryGrip.profile("both", 10, true, false), walk, seed * 31)
	end
	check("the load darts about more while you walk", go > stand * 1.3, `{stand} {go}`)
	check("…and more with a heavy fragile thing than a light one", heavy > light, `{light} {heavy}`)
	-- a bite adds a jolt that fades
	local sim = CarryGrip.new(p, 3)
	local bitten = CarryGrip.newInput()
	bitten.bite = G.Motion.BiteFull
	CarryGrip.step(sim, bitten, DT)
	local jolt = sim.shock
	bitten.bite = 0
	for _ = 1, 60 do
		CarryGrip.step(sim, bitten, DT)
	end
	check("a bite's jolt, fading", jolt > 1 and sim.shock < jolt, `{jolt} {sim.shock}`)
end

-- ── The meter ───────────────────────────────────────────────────────────────

do
	local sim = CarryGrip.new(CarryGrip.profile("both", 4, false, false), 1)
	sim.meter = 0.5
	CarryGrip.meterStep(sim, true, false, 1)
	check("inside the box it fills (Fill a second)", math.abs(sim.meter - (0.5 + G.Meter.Fill)) < 1e-9)
	CarryGrip.meterStep(sim, false, false, 1)
	check("outside it drains (Drain a second)", math.abs(sim.meter - (0.5 + G.Meter.Fill - G.Meter.Drain)) < 1e-9)
	sim.meter = G.Meter.Floor + 0.05
	CarryGrip.meterStep(sim, false, true, 5)
	check("standing still it stops draining at the floor (you can recover)", math.abs(sim.meter - G.Meter.Floor) < 1e-9)
	sim.meter = 0.1
	CarryGrip.meterStep(sim, false, true, 5)
	check("…already under it: no lower", math.abs(sim.meter - 0.1) < 1e-9)
	check("…and SLIPPING! shows there", sim.warn)
	sim.meter = 0.95
	CarryGrip.meterStep(sim, true, false, 1)
	check("full: steady", sim.meter == 1 and sim.steady and not sim.warn)
	CarryGrip.meterStep(sim, false, false, (1 - G.Meter.SteadyOff) / G.Meter.Drain * 0.5)
	check("…a little out: still steady (no flicker)", sim.steady)
	CarryGrip.meterStep(sim, false, false, 1)
	check("…under SteadyOff: not", not sim.steady)
	check("steady: the carry's walk × 1.1", CarryGrip.speedFactor(true) == 1.1 and CarryGrip.speedFactor(false) == 1)
	-- at 0 it slips, once
	local slip = CarryGrip.new(CarryGrip.profile("both", 4, false, false), 9)
	local walk = CarryGrip.newInput()
	walk.speed = WALK * 0.75
	slip.meter, slip.zone, slip.marker, slip.aim, slip.dart = 0.02, 0, 0.95, 0.95, 60
	local first = CarryGrip.step(slip, walk, 0.2)
	local second = CarryGrip.step(slip, walk, 0.2)
	check("at 0 it slips: \"slip\" once", first == "slip" and slip.slipped and second == nil and slip.meter == 0)
end

-- ── Reports and the server's wear ───────────────────────────────────────────

do
	local sim = CarryGrip.new(CarryGrip.profile("both", 4, false, false), 4)
	sim.window, sim.outside = 1, 0.25
	local quality, steady = CarryGrip.report(sim)
	check("a report: the share of the time outside, then it starts over", quality == 0.25 and steady == sim.steady and sim.window == 0 and sim.outside == 0)
	check("…nothing measured yet: 0", (CarryGrip.report(sim)) == 0)
	check("the wear: none fully inside", CarryGrip.wear(0, true, 1) == 0)
	local plain, fragile = CarryGrip.wear(0.5, false, 1), CarryGrip.wear(0.5, true, 1)
	check("…a little outside, more when fragile", plain > 0 and fragile > plain and plain < 0.01)
	check("…capped a second", CarryGrip.wear(1, true, 1) <= G.Server.WearCap + 1e-12 and CarryGrip.wear(5, true, 1) <= G.Server.WearCap + 1e-12)
	check("…one report counts Gap s at most", CarryGrip.wear(1, false, 60) <= G.Server.WearCap * G.Server.Gap + 1e-12)
	check("…a client's nonsense wears nothing", CarryGrip.wear(0 / 0, true, 1) == 0 and CarryGrip.wear("lots", true, 1) == 0 and CarryGrip.wear(1, true, -5) == 0
		and CarryGrip.wear(-1, true, 1) == 0)
	check("a slip's damage: more when fragile (× Moving.Damage.Fragile)", math.abs(CarryGrip.slipDamage(true) - CarryGrip.slipDamage(false) * Config.Moving.Damage.Fragile) < 1e-12
		and CarryGrip.slipDamage(false) > 0)
end

-- ── Steps: robust, deterministic ────────────────────────────────────────────

do
	local p = CarryGrip.profile("pair", 8, true, false)
	local input = CarryGrip.newInput()
	input.speed = WALK * 0.8
	local function trace(seed: number): { number }
		local sim = CarryGrip.new(p, seed)
		local out = {}
		for i = 1, 600 do
			input.hold = i % 50 < 20
			CarryGrip.step(sim, input, DT)
			if i % 30 == 0 then
				table.insert(out, sim.marker)
				table.insert(out, sim.zone)
				table.insert(out, sim.meter)
			end
		end
		return out
	end
	local a, b, c = trace(1234), trace(1234), trace(4321)
	local same, differ = true, false
	for i = 1, #a do
		same = same and a[i] == b[i]
		differ = differ or a[i] ~= c[i]
	end
	check("the same seed and steps: the same bar", same and #a == 60)
	check("another seed: another bar", differ)
	local sim = CarryGrip.new(p, 5)
	local t0 = sim.time
	CarryGrip.step(sim, input, 5)
	check("a long frame counts MaxDt at most", math.abs(sim.time - t0 - G.MaxDt) < 1e-9)
	local before = sim.time
	CarryGrip.step(sim, input, 0 / 0)
	CarryGrip.step(sim, input, -1)
	check("…a NaN or negative one: nothing", sim.time == before)
	local zeroSeed = CarryGrip.new(p, 0)
	CarryGrip.step(zeroSeed, input, 0.5)
	check("a zero seed still darts", zeroSeed.seed ~= 0 and zeroSeed.marker ~= 0.5)
end

-- ── Played (a reaction delay, walking with turns) ───────────────────────────

-- A player who sees the bar `delay` s late; strategy "attentive" (holds when the box's middle, where it is heading,
-- is under the load), "never", "always". Returns the share of the time inside and when it slipped (nil: never).
local function play(kind: string, weight: number, fragile: boolean, mover: boolean, share: number, strategy: string, delay: number, seed: number, seconds: number): (number, number?)
	local p = CarryGrip.profile(kind, weight, fragile, mover)
	local sim = CarryGrip.new(p, seed)
	local input = CarryGrip.newInput()
	local seen: { { number } } = {}
	local lag = math.max(1, math.floor(delay / DT))
	local inside, steps = 0, 0
	for i = 1, math.floor(seconds / DT) do
		input.speed = WALK * share
		input.turn = if i % 120 < 30 then 2 else 0
		table.insert(seen, { sim.zone, sim.zoneVel, sim.marker })
		local look = seen[math.max(1, #seen - lag)]
		input.hold = if strategy == "attentive" then look[1] + p.zone / 2 + look[2] * 0.25 < look[3] else strategy == "always"
		local event = CarryGrip.step(sim, input, DT)
		steps += 1
		if sim.inside then
			inside += 1
		end
		if event == "slip" then
			return inside / steps, i * DT
		end
	end
	return inside / steps, nil
end

do
	local kept, droppedFast, alwaysDropped = true, true, true
	local times: { number } = {}
	for seed = 1, 8 do
		local _, slipped = play("both", 6, true, false, 0.75, "attentive", 0.18, seed * 101, 60)
		kept = kept and slipped == nil
		local _, gone = play("both", 6, true, false, 0.75, "never", 0, seed * 101, 60)
		droppedFast = droppedFast and gone ~= nil and gone < 15
		table.insert(times, gone or math.huge)
		local _, held = play("pair", 9, false, false, 0.8, "always", 0, seed * 101, 60)
		alwaysDropped = alwaysDropped and held ~= nil
	end
	table.sort(times)
	check("an attentive player keeps a fragile both-hands thing a whole minute", kept)
	check("never holding while walking: it slips within seconds (mostly in 3 to 5)", droppedFast and times[4] < 6, table.concat(times, " "))
	check("always holding: the box sticks at the top, it slips too", alwaysDropped)
	local p = CarryGrip.profile("solo", 10, true, true)
	local sim = CarryGrip.new(p, 77)
	local stand = CarryGrip.newInput()
	local slipped = false
	for _ = 1, 60 * 120 do
		if CarryGrip.step(sim, stand, DT) then
			slipped = true
		end
	end
	check("standing still, never holding: it never slips (two minutes)", not slipped and sim.meter >= G.Meter.Floor - 1e-9, sim.meter)
	-- the Mover's bigger box: more of the time inside; a pair thing alone harder than carried by two
	local moverIn, plainIn, soloIn, pairIn = 0, 0, 0, 0
	for seed = 1, 8 do
		moverIn += (play("both", 6, true, true, 0.75, "attentive", 0.25, seed * 17, 30))
		plainIn += (play("both", 6, true, false, 0.75, "attentive", 0.25, seed * 17, 30))
		soloIn += (play("solo", 10, false, true, 0.8, "attentive", 0.25, seed * 17, 30))
		pairIn += (play("pair", 10, false, true, 0.8, "attentive", 0.25, seed * 17, 30))
	end
	check("the Mover keeps the load inside more of the time", moverIn > plainIn, `{moverIn / 8} {plainIn / 8}`)
	check("a pair thing alone (solo) is harder than with a helper", soloIn < pairIn, `{soloIn / 8} {pairIn / 8}`)
end

-- ── Where it sits (client/MoveLayout.luau grip) ─────────────────────────────

local function scaleFor(W: number, H: number): number -- (client/Ui.luau scaleFor)
	return math.clamp(math.min(W / 1150, H / 680), 0.55, 1.1)
end
local function show(b: TouchLayout.Box?): string
	return if b then string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1) else "nil"
end
local sizes = { hold = G.Ui.Hold, holdMin = G.Ui.HoldMin, scale = G.Ui.Scale, min = G.Ui.Min }
check("the HOLD button is at least 72 px", G.Ui.HoldMin >= 72)
for _, screen in { { 844, 354 }, { 844, 390 }, { 667, 339 }, { 932, 394 }, { 1024, 718 }, { 1180, 780 } } do
	local W, H = screen[1], screen[2]
	local S = scaleFor(W, H)
	local cluster = TouchLayout.cluster(W, H, S)
	local panel = MoveLayout.panel(W, S)
	local touchBlocks = TouchLayout.buttons(cluster)
	table.insert(touchBlocks, cluster.thumb)
	table.insert(touchBlocks, cluster.jump)
	local bar, scale, hold = MoveLayout.grip(W, H, S, true, { panel }, sizes)
	local clear = hold ~= nil
	for _, b in touchBlocks do
		clear = clear and not TouchLayout.overlap(bar, b) and not TouchLayout.overlap(hold :: TouchLayout.Box, b)
	end
	local h = hold :: TouchLayout.Box
	check(`{W} × {H}: HOLD ≥ 72 px at the right over the touch buttons, the panel right of the middle, clear of them, the move's panel and each other`,
		clear and h.x1 - h.x0 >= 72 and h.y1 <= cluster.top + 0.01 and h.x0 > W / 2 and (bar.x0 + bar.x1) / 2 > W / 2 and MoveLayout.inside(bar, W, H)
			and MoveLayout.inside(h, W, H) and not TouchLayout.overlap(bar, h) and not TouchLayout.overlap(bar, panel) and scale >= G.Ui.Min - 1e-9,
		`{show(bar)} {show(hold)}`)
end
do
	-- the actions' row (and ADMIN) over the button's first place: it goes elsewhere, still clear
	local W, H = 844, 354
	local S = scaleFor(W, H)
	local row = TouchLayout.box(W - 16 - 136, 56, W - 16, 131)
	local cluster = TouchLayout.cluster(W, H, S)
	local bar, _, hold = MoveLayout.grip(W, H, S, true, { MoveLayout.panel(W, S), row }, sizes)
	local h = hold :: TouchLayout.Box
	local clear = not TouchLayout.overlap(h, row) and not TouchLayout.overlap(bar, row) and not TouchLayout.overlap(bar, h)
	for _, b in TouchLayout.buttons(cluster) do
		clear = clear and not TouchLayout.overlap(h, b)
	end
	check("with ADMIN's row over FIRE: the HOLD button moves, still clear of everything", clear and h.x1 - h.x0 >= 72, `{show(bar)} {show(hold)}`)
	local pc, pcScale, none = MoveLayout.grip(1280, 684, scaleFor(1280, 684), false, { MoveLayout.panel(1280, scaleFor(1280, 684)) }, sizes)
	check("a computer: no HOLD button, the panel right of the middle at its scale", none == nil and (pc.x0 + pc.x1) / 2 > 640 and pcScale == scaleFor(1280, 684)
		and math.abs((pc.y0 + pc.y1) / 2 - 342) < 1, show(pc))
end
do
	-- 7.1 review: no place clear for HOLD: the one that covers the least (the touch controls CONTROL_WEIGHT × worse),
	-- not simply the first (over FIRE)
	local W, H = 844, 354
	local S = scaleFor(W, H)
	local size = math.max(sizes.holdMin, sizes.hold * S)
	local spots = MoveLayout.holdSpots(W, H, S, size)
	check("HOLD's places: five, each size × size", #spots == 5 and math.abs(spots[1].x1 - spots[1].x0 - size) < 1e-6 and math.abs(spots[3].y1 - spots[3].y0 - size) < 1e-6)
	local blocks = { MoveLayout.panel(W, S) }
	for index, spot in spots do -- (a block on each place, the first one whole, the others a corner each, smaller and smaller)
		local side = if index == 1 then size else size * (0.6 - index * 0.08)
		table.insert(blocks, TouchLayout.box(spot.x0, spot.y0, spot.x0 + side, spot.y0 + side))
	end
	local cluster = TouchLayout.cluster(W, H, S)
	local controls = table.clone(TouchLayout.buttons(cluster))
	table.insert(controls, cluster.thumb)
	table.insert(controls, cluster.jump)
	local avoid = table.clone(blocks)
	for _, b in controls do
		table.insert(avoid, b)
	end
	local function cost(b: TouchLayout.Box): number
		return MoveLayout.clash(b, W, H, avoid) + (MoveLayout.CONTROL_WEIGHT - 1) * MoveLayout.clash(b, W, H, controls) - (MoveLayout.CONTROL_WEIGHT - 1) * MoveLayout.clash(b, W, H, {})
	end
	local _, _, hold = MoveLayout.grip(W, H, S, true, blocks, sizes)
	local h = hold :: TouchLayout.Box
	local least = true
	for _, spot in spots do
		least = least and cost(h) <= cost(spot) + 1e-6
	end
	check("no HOLD place clear: the one that covers the least, not the first (over FIRE, covered whole)", least and cost(h) > 0
		and not (math.abs(h.x0 - spots[1].x0) < 1e-6 and math.abs(h.y0 - spots[1].y0) < 1e-6), show(h))
	check("MoveLayout.clash: 0 when clear, the shared area, off the screen twice", MoveLayout.clash(TouchLayout.box(10, 10, 20, 20), W, H, {}) == 0
		and MoveLayout.clash(TouchLayout.box(10, 10, 20, 20), W, H, { TouchLayout.box(15, 15, 40, 40) }) == 25
		and MoveLayout.clash(TouchLayout.box(-10, 0, 10, 10), W, H, {}) == 200)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
