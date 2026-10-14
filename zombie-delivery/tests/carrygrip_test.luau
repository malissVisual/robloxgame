-- 8.1 grip: the carry's timing checks (shared/CarryGrip.luau, pure; the owner: "when I fail, something must always
-- happen, but make it easier; when we pick it up the first time I should have to hit a target"): which carries have
-- checks (a fragile one-hand thing, "both", "pair", a Mover's pair thing alone, a pair thing dragged), the attribute's
-- code, the profiles (easy at Difficulty 1: zones of about a third of the sweep, slow needles; heavier and fragile a
-- little harder; the Mover's and Danny's bigger zone; Difficulty scales them all), the needle's maths (a triangle
-- wave from the left end, a hit only in the zone, never at once), the checks' windows and places, the server's
-- judging (only "ok", only a press time that can be true, only in the zone), the wire, the outcomes (a lift's miss
-- knocks it; a wobble's first miss staggers a sturdy piece, the second drops it, a fragile one drops at once; every
-- miss does something), the knocks, the walk, and the wobble clock (7 – 12 s of walking, seldom standing still, sooner
-- turning, rushing, jumping or bitten, the gap between two, sooner after a stagger), played over a minute.
-- And where it sits (client/MoveLayout.luau gripCheck): the GRIP button a finger's size and more, at the right over the
-- touch buttons, clear of them; the widget in the middle under the character, clear of them and of the button.
-- Run with tests/run_tests.py.
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
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-9)
end

local G = Config.CarryGrip
local WALK = Config.Movement.Walk

-- ── The kinds and the attribute ─────────────────────────────────────────────

check("a one-hand thing: checks only when fragile (gentle: \"hand\")", CarryGrip.kind("hand", false, false, nil) == nil and CarryGrip.kind("hand", true, false, nil) == "hand")
check("both hands: always", CarryGrip.kind("both", false, false, nil) == "both" and CarryGrip.kind("both", true, false, "mover") == "both")
check("a pair thing: two carry it (each their own checks)", CarryGrip.kind("pair", false, true, nil) == "pair" and CarryGrip.kind("pair", false, true, "mover") == "pair")
check("…a Mover alone: solo; anybody else alone: dragged", CarryGrip.kind("pair", false, false, "mover") == "solo" and CarryGrip.kind("pair", true, false, "guard") == "drag"
	and CarryGrip.kind("pair", false, false, nil) == "drag")
check("an unknown class: no checks", CarryGrip.kind("wheel", true, false, nil) == nil)
do
	local code = CarryGrip.encode("both", 4, true)
	local kind, weight, fragile = CarryGrip.decode(code)
	check("the attribute: \"both 4 fragile\" and back", code == "both 4 fragile" and kind == "both" and weight == 4 and fragile == true, code)
	local k2, w2, f2 = CarryGrip.decode(CarryGrip.encode("pair", 10, false))
	check("…\"pair 10\" (not fragile)", k2 == "pair" and w2 == 10 and f2 == false)
	check("…nonsense, an unknown kind, nil: none", CarryGrip.decode("sofa") == nil and CarryGrip.decode("wheel 3") == nil and CarryGrip.decode(nil) == nil and CarryGrip.decode(42) == nil)
end

-- ── The profiles: easy by default, harder by Config only ────────────────────

check("the default: Difficulty 1, the checks on", G.Difficulty == 1 and G.On == true)
do
	-- every carry a player can have (Movers' solo is theirs only), every weight, fragile or not
	local smallest, largest, fastest, slowest = math.huge, 0, 0, math.huge
	for kind in G.Kinds do
		for weight = 1, 10 do
			for _, fragile in { false, true } do
				if kind == "hand" and not fragile then
					continue
				end
				local p = CarryGrip.profile(kind, weight, fragile, kind == "solo")
				smallest, largest = math.min(smallest, p.zone), math.max(largest, p.zone)
				fastest, slowest = math.max(fastest, p.speed), math.min(slowest, p.speed)
			end
		end
	end
	check("easy: every lift's green zone 27 – 40% of the sweep", smallest >= 0.27 and largest <= 0.4 + 1e-9, `{smallest} … {largest}`)
	check("…a slow needle: at most 0.76 sweeps a second (1.3 s and more edge to edge)", fastest <= 0.76 and slowest >= 0.4, `{slowest} … {fastest}`)
	local tv = CarryGrip.profile("both", 4, true, false)
	local sofa = CarryGrip.profile("pair", 8, false, false)
	check("the TV (both 4 fragile) about 30%, the sofa by two (pair 8) about 36%", tv.zone > 0.29 and tv.zone < 0.33 and sofa.zone > 0.34 and sofa.zone < 0.38,
		`{tv.zone} {sofa.zone}`)
	check("heavier: a smaller zone and a faster needle", CarryGrip.profile("both", 9, false, false).zone < CarryGrip.profile("both", 2, false, false).zone
		and CarryGrip.profile("both", 9, false, false).speed > CarryGrip.profile("both", 2, false, false).speed)
	check("fragile: a smaller zone and a faster needle", CarryGrip.profile("both", 4, true, false).zone < CarryGrip.profile("both", 4, false, false).zone
		and CarryGrip.profile("both", 4, true, false).speed > CarryGrip.profile("both", 4, false, false).speed)
	local moverAll = true
	for kind in G.Kinds do
		local plain = CarryGrip.profile(kind, 5, false, false)
		local mover = CarryGrip.profile(kind, 5, false, true)
		moverAll = moverAll and near(mover.zone, math.min(G.Zone.Max, plain.zone * G.Mover))
	end
	check("the Mover: a 35% bigger zone on every kind", moverAll and near(G.Mover, 1.35))
	local alone = CarryGrip.profile("both", 6, true, false, false)
	local danny = CarryGrip.profile("both", 6, true, false, true)
	check("Danny steadies it (GripSteady): the zone × 1.3, the same needle", near(danny.zone, alone.zone * 1.3) and danny.speed == alone.speed and danny.steadied and not alone.steadied)
	check("two people steady it: a pair's zone bigger than one person's both-hands", CarryGrip.profile("pair", 6, false, false).zone > CarryGrip.profile("both", 6, false, false).zone)
	check("an unknown kind: a both-hands profile", CarryGrip.profile("wheel", 3, false, false).kind == "both")
	-- harder later: Config only
	G.Difficulty = 1.5
	local hard = CarryGrip.profile("both", 4, true, false)
	G.Difficulty = 1
	check("Difficulty 1.5: the zone ÷ 1.5, the needle × 1.5 (Config only)", near(hard.zone, tv.zone / 1.5) and near(hard.speed, tv.speed * 1.5), `{hard.zone} {hard.speed}`)
	G.Difficulty = 100
	local absurd = CarryGrip.profile("both", 10, true, false)
	G.Difficulty = 1
	check("…never past Zone.Min / Speed.Max", absurd.zone == G.Zone.Min and absurd.speed == G.Speed.Max)
end

-- ── The needle ──────────────────────────────────────────────────────────────

do
	local p = CarryGrip.profile("both", 4, true, false)
	local c = CarryGrip.check(p, "lift", 0.5)
	local sweep = 1 / c.speed
	check("the needle starts at the left end and sweeps right at a steady speed", CarryGrip.needle(c, 0) == 0 and near(CarryGrip.needle(c, sweep / 2), 0.5, 1e-6)
		and near(CarryGrip.needle(c, sweep / 4) * 2, CarryGrip.needle(c, sweep / 2), 1e-6))
	check("…at the right end after one sweep, back at the left after two (a triangle wave)", near(CarryGrip.needle(c, sweep), 1, 1e-6) and near(CarryGrip.needle(c, 2 * sweep), 0, 1e-6)
		and near(CarryGrip.needle(c, 1.25 * sweep), 0.75, 1e-6))
	check("…nonsense time: the start", CarryGrip.needle(c, 0 / 0) == 0 and CarryGrip.needle(c, -3) == 0)
	check("the zone never at the start (Zone.Start) nor past the right end less Edge", c.zone0 >= G.Zone.Start - 1e-9 and c.zone0 + c.zone <= 1 - G.Zone.Edge + 1e-9)
	check("an instant press never hits", not CarryGrip.hits(c, 0) and not CarryGrip.hits(c, 0.05))
	local first = CarryGrip.firstHit(c)
	check("a press with the needle in the zone's middle hits", CarryGrip.hits(c, first) and near(CarryGrip.needle(c, first), c.zone0 + c.zone / 2, 1e-6))
	local enter = c.zone0 / c.speed
	check("…its edges hit, just outside them misses", CarryGrip.hits(c, enter + 1e-6) and not CarryGrip.hits(c, enter - 0.02) and CarryGrip.hits(c, (c.zone0 + c.zone) / c.speed - 1e-6)
		and not CarryGrip.hits(c, (c.zone0 + c.zone) / c.speed + 0.02))
	check("…and on the way back", CarryGrip.hits(c, 2 * sweep - first))
	check("a press after the window misses", not CarryGrip.hits(c, c.window + 0.01))
	local lo = CarryGrip.check(p, "lift", 0)
	local hi = CarryGrip.check(p, "lift", 1)
	check("the zone's place: roll 0 at Zone.Start, roll 1 at the right end less Edge", near(lo.zone0, G.Zone.Start) and near(hi.zone0 + hi.zone, 1 - G.Zone.Edge))
	-- every check: the window at least Speed.Sweeps sweeps, a full pass through the zone in it, time to react in the zone
	local passAll, windowAll, slowest = true, true, math.huge
	for kind in G.Kinds do
		for weight = 1, 10 do
			for _, fragile in { false, true } do
				for _, what in { "lift", "wobble" } do
					for _, roll in { 0, 0.5, 1 } do
						local profile = CarryGrip.profile(kind, weight, fragile, kind == "solo")
						local k = CarryGrip.check(profile, what, roll)
						passAll = passAll and (k.zone0 + k.zone) / k.speed <= k.window
						windowAll = windowAll and k.window >= (if what == "lift" then G.Lift.Window else G.Wobble.Window) - 1e-9 and k.window * k.speed >= G.Speed.Sweeps - 1e-9
						slowest = math.min(slowest, k.zone / k.speed)
					end
				end
			end
		end
	end
	check("every check: its window (3 s a lift, 2.4 s a wobble) holds a full pass through the zone", passAll and windowAll and G.Lift.Window == 3)
	check("…and the needle stays in the zone 0.3 s and more a pass (time to react)", slowest >= 0.3, slowest)
	local w = CarryGrip.check(p, "wobble", 0.5)
	check("a wobble: a slightly smaller zone, a faster needle, a shorter window than the lift", near(w.zone, c.zone * G.Wobble.Zone) and near(w.speed, c.speed * G.Wobble.Speed)
		and w.window < c.window and w.what == "wobble" and c.what == "lift")
end

-- ── The server's judging ────────────────────────────────────────────────────

do
	local c = CarryGrip.check(CarryGrip.profile("both", 4, true, false), "lift", 0.4)
	local at = CarryGrip.firstHit(c)
	local S = G.Server
	check("\"ok\" with its press in the zone, a moment before the server got it: a hit", CarryGrip.judge(c, "ok", at, at + 0.2))
	check("…up to Lag s of lag", CarryGrip.judge(c, "ok", at, at + S.Lag - 0.01) and not CarryGrip.judge(c, "ok", at, at + S.Lag + 0.05))
	check("a press the server's clock has not reached yet (made up): a miss", not CarryGrip.judge(c, "ok", at, at - 0.5))
	check("\"ok\" with its press outside the zone (the client's lie): a miss", not CarryGrip.judge(c, "ok", 0.05, 0.2))
	check("\"miss\", or no press time, NaN, a string: a miss", not CarryGrip.judge(c, "miss", at, at) and not CarryGrip.judge(c, "ok", nil, at)
		and not CarryGrip.judge(c, "ok", 0 / 0, at) and not CarryGrip.judge(c, "ok", "now", at) and not CarryGrip.judge(c, true, at, at))
	check("…a press past the window: a miss", not CarryGrip.judge(c, "ok", c.window + 1, c.window + 1.2))
	local edge = c.zone0 / c.speed - 0.5 * S.Slack / c.speed
	check("Server.Slack: a press a hair before the zone still counts (float, a frame)", CarryGrip.judge(c, "ok", edge, edge + 0.1) and not CarryGrip.hits(c, edge))
	-- the wire
	local wire = CarryGrip.wire(c, { id = 7, spot = 2, name = "Old TV", drop = false })
	local back = CarryGrip.fromWire(wire)
	check("the wire: the check's numbers and the server's own fields, back as the same check", back ~= nil and wire.id == 7 and wire.name == "Old TV" and back.zone0 == c.zone0
		and back.zone == c.zone and back.speed == c.speed and back.window == c.window and back.what == "lift")
	check("…nonsense is no check (a zone past the end, NaN, no window, not a table)", CarryGrip.fromWire({ zone0 = 0.8, zone = 0.4, speed = 0.5, window = 3 }) == nil
		and CarryGrip.fromWire({ zone0 = 0 / 0, zone = 0.3, speed = 0.5, window = 3 }) == nil and CarryGrip.fromWire({ zone0 = 0.3, zone = 0.3, speed = 0.5 }) == nil
		and CarryGrip.fromWire("check") == nil)
end

-- ── The outcomes: every miss does something ─────────────────────────────────

do
	local sturdy = CarryGrip.profile("both", 4, false, false)
	local fragile = CarryGrip.profile("both", 4, true, false)
	local heavy = CarryGrip.profile("pair", 9, false, false)
	check("a lift: a hit lifts it balanced, a miss knocks it", CarryGrip.outcome("lift", true, sturdy, 0) == "balanced" and CarryGrip.outcome("lift", false, sturdy, 1) == "knock")
	check("a wobble hit: steady", CarryGrip.outcome("wobble", true, fragile, 0) == "steady")
	check("a sturdy piece: the first miss staggers, the second in a row drops it", CarryGrip.outcome("wobble", false, sturdy, 1) == "stagger"
		and CarryGrip.outcome("wobble", false, sturdy, 2) == "drop" and CarryGrip.dropAt(sturdy) == G.Miss.Drop.Sturdy)
	check("a fragile piece drops at its first miss", CarryGrip.outcome("wobble", false, fragile, 1) == "drop" and CarryGrip.dropAt(fragile) == 1)
	check("a heavy piece (from HeavyAt): Miss.Drop.Heavy (2 today: a stagger first)", CarryGrip.dropAt(heavy) == G.Miss.Drop.Heavy and CarryGrip.outcome("wobble", false, heavy, 1) == "stagger")
	G.Miss.Drop.Heavy = 1
	check("…harder later (Config only): Drop.Heavy 1 drops a heavy piece at once", CarryGrip.outcome("wobble", false, heavy, 1) == "drop")
	G.Miss.Drop.Heavy = 2
	check("a lift's knock 4% (fragile 5%), a stagger's 3%, two players' each half", near(CarryGrip.knock("lift", false), 0.04) and near(CarryGrip.knock("lift", true), 0.05)
		and near(CarryGrip.knock("wobble", false), 0.03) and near(CarryGrip.knock("wobble", false, true), 0.015) and near(CarryGrip.knock("lift", true, true), 0.025))
	check("a drop: the slip's damage, fragile more", CarryGrip.slipDamage(false) == G.Slip and CarryGrip.slipDamage(true) > CarryGrip.slipDamage(false))
	check("the walk: steady × 1.1, a stagger × 0.6 a moment, both × 0.66", CarryGrip.speedFactor(true) == 1.1 and CarryGrip.speedFactor(false) == 1
		and CarryGrip.speedFactor(false, true) == 0.6 and near(CarryGrip.speedFactor(true, true), 0.66))
end

-- ── The wobble clock ────────────────────────────────────────────────────────

do
	local p = CarryGrip.profile("both", 4, false, false)
	check("the time between two wobbles: 7 – 12 s of walking (× the kind's Every)", CarryGrip.interval(p, 0, false) == 7 and CarryGrip.interval(p, 1, false) == 12
		and near(CarryGrip.interval(CarryGrip.profile("drag", 4, false, false), 0, false), 7 * G.Kinds.drag.Every))
	check("…after a stagger, sooner (× Sooner: 3.5 – 6 s)", CarryGrip.interval(p, 0, true) == 3.5 and CarryGrip.interval(p, 1, true) == 6)
	local walk = WALK * 0.75
	check("its pace: Still standing, 1 at the carry's walk", near(CarryGrip.rate(0, walk, 0, false), G.Wobble.Still) and near(CarryGrip.rate(walk, walk, 0, false), 1)
		and near(CarryGrip.rate(walk / 2, walk, 0, false), G.Wobble.Still + (1 - G.Wobble.Still) / 2))
	check("…faster than the carry's walk (rushing), turning hard, in the air: sooner", near(CarryGrip.rate(walk * 1.5, walk, 0, false), 1 + G.Wobble.Rush)
		and near(CarryGrip.rate(walk, walk, G.Wobble.TurnFull * 2, false), 1 + G.Wobble.Turn) and near(CarryGrip.rate(walk, walk, 0, true), 1 + G.Wobble.Air))
	check("…a body that jitters under StillAt studs/s stands still", near(CarryGrip.rate(G.Wobble.StillAt - 0.1, walk, 0, false), G.Wobble.Still))
	local w = CarryGrip.wobbles(p, 0) -- (7 s)
	local due, t = false, 0
	while not due and t < 100 do
		t += 0.2
		due = CarryGrip.advance(w, 0.2, 1)
	end
	check("walking at the carry's walk: the wobble 7 s after the lift (roll 0)", due and near(t, 7, 0.21), t)
	CarryGrip.rearm(w, p, 0, false)
	check("rearm: the clock back to 0", w.due == 0 and w.gap == 0 and w.next == 7)
	t, due = 0, false
	while not due and t < 100 do
		t += 0.2
		due = CarryGrip.advance(w, 0.2, CarryGrip.rate(0, walk, 0, false))
	end
	check("standing still: five times later", due and near(t, 7 / G.Wobble.Still, 0.21), t)
	CarryGrip.rearm(w, p, 1, false) -- (12 s)
	CarryGrip.advance(w, 1, 1)
	for _ = 1, 4 do
		CarryGrip.bump(w)
	end
	local bumped = w.due
	local early = CarryGrip.advance(w, 0.2, 1)
	local still = CarryGrip.advance(w, 1.6, 1)
	local gapOver = CarryGrip.advance(w, 0.4, 1)
	check("bites move it on (Bump s each), but never sooner than Gap s after the last check", near(bumped, 1 + 4 * G.Wobble.Bump) and not early and not still and gapOver
		and w.gap >= G.Wobble.Gap, `{w.due} {w.gap}`)
	check("nonsense time or pace moves nothing", not CarryGrip.advance(CarryGrip.wobbles(p, 0), 0 / 0, 1) and not CarryGrip.advance(CarryGrip.wobbles(p, 0), 5, -3))
end

-- ── Played: a minute of carrying ────────────────────────────────────────────

do
	-- a carrier walking (or standing, or turning about), the wobbles the clock opens over 60 s, a check's 2.4 s on top
	local function wobbles(rate: number, seed: number): number
		local p = CarryGrip.profile("both", 4, false, false)
		local state = seed * 7919 + 17
		local function roll(): number -- (a small LCG: the same rolls every run)
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
		local w = CarryGrip.wobbles(p, roll())
		local count, t = 0, 0
		while t < 60 do
			t += 0.2
			if CarryGrip.advance(w, 0.2, rate) then
				count += 1
				t += G.Wobble.Window -- (the check; the clock waits)
				CarryGrip.rearm(w, p, roll(), false)
			end
		end
		return count
	end
	local walking, still, busy = 0, 0, 0
	for seed = 1, 20 do
		walking += wobbles(1, seed)
		still += wobbles(G.Wobble.Still, seed)
		busy += wobbles(1 + G.Wobble.Turn, seed)
	end
	check("a minute of walking: 4 – 7 wobbles (one every 7 – 12 s)", walking >= 20 * 4 and walking <= 20 * 7, walking / 20)
	check("…standing: one at most", still <= 20, still / 20)
	check("…turning about all the time: more", busy > walking, busy / 20)
	-- the presses: one at the zone's middle always hits, one at once never, one 0.15 s after the needle enters the zone
	-- hits every check of every carry (time to react)
	local attentive, instant, reacting, total = 0, 0, 0, 0
	for kind in G.Kinds do
		for weight = 1, 10 do
			for _, what in { "lift", "wobble" } do
				for roll = 0, 1, 0.25 do
					local c = CarryGrip.check(CarryGrip.profile(kind, weight, true, kind == "solo"), what, roll)
					total += 1
					attentive += if CarryGrip.hits(c, CarryGrip.firstHit(c)) then 1 else 0
					instant += if CarryGrip.hits(c, 0) then 1 else 0
					reacting += if CarryGrip.hits(c, c.zone0 / c.speed + 0.15) then 1 else 0
				end
			end
		end
	end
	check("played: a press at the zone's middle hits every check", attentive == total, `{attentive}/{total}`)
	check("…a press at once never does", instant == 0)
	check("…a press 0.15 s after the needle enters the zone still hits (even fragile, even a wobble)", reacting == total, `{reacting}/{total}`)
end

-- ── Where it sits (client/MoveLayout.luau gripCheck) ─────────────────────────

local function scaleFor(W: number, H: number): number -- (client/Ui.luau scaleFor)
	return math.clamp(math.min(W / 1150, H / 680), 0.55, 1.1)
end
local function show(b: TouchLayout.Box?): string
	return if b then string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1) else "nil"
end
local sizes = { tap = G.Ui.Tap, tapMin = G.Ui.TapMin, scale = G.Ui.Scale, min = G.Ui.Min }
check("the GRIP button is at least 80 px", G.Ui.TapMin >= 80)
for _, screen in { { 844, 354 }, { 844, 390 }, { 667, 339 }, { 932, 394 }, { 1024, 718 }, { 1180, 780 } } do
	local W, H = screen[1], screen[2]
	local S = scaleFor(W, H)
	local cluster = TouchLayout.cluster(W, H, S)
	local panel = MoveLayout.panel(W, S)
	local touchBlocks = TouchLayout.buttons(cluster)
	table.insert(touchBlocks, cluster.thumb)
	table.insert(touchBlocks, cluster.jump)
	local widget, scale, tap = MoveLayout.gripCheck(W, H, S, true, { panel }, sizes)
	local clear = tap ~= nil
	for _, b in touchBlocks do
		clear = clear and not TouchLayout.overlap(widget, b) and not TouchLayout.overlap(tap :: TouchLayout.Box, b)
	end
	local t = tap :: TouchLayout.Box
	check(`{W} × {H}: GRIP ≥ 80 px at the right over the touch buttons, the widget on the screen, clear of them, the move's panel and each other`,
		clear and t.x1 - t.x0 >= 80 and t.y1 <= cluster.top + 0.01 and t.x0 > W / 2 and MoveLayout.inside(widget, W, H)
			and MoveLayout.inside(t, W, H) and not TouchLayout.overlap(widget, t) and not TouchLayout.overlap(widget, panel) and scale >= G.Ui.Min - 1e-9,
		`{show(widget)} {show(tap)}`)
end
do
	local W, H = 1280, 684
	local S = scaleFor(W, H)
	local widget, scale, none = MoveLayout.gripCheck(W, H, S, false, { MoveLayout.panel(W, S) }, sizes)
	check("a computer: no GRIP button, the widget in the middle under the character at the HUD's scale", none == nil and math.abs((widget.x0 + widget.x1) / 2 - W / 2) < 1
		and near(widget.y0, H * 0.6, 1) and near(scale, math.max(S, G.Ui.Scale)) and near(widget.x1 - widget.x0, MoveLayout.CHECK_W * scale, 1e-6), show(widget))
	-- the bottom bar where the widget would go first: it moves (lower, higher, over the head …), still clear
	local bar = TouchLayout.box(W / 2 - 300, H * 0.58, W / 2 + 300, H)
	local moved = MoveLayout.gripCheck(W, H, S, false, { MoveLayout.panel(W, S), bar }, sizes)
	check("…something under the middle: it goes over the character's head, clear", not TouchLayout.overlap(moved, bar) and moved.y1 <= H * 0.58 and MoveLayout.inside(moved, W, H),
		show(moved))
end
do
	-- the actions' row (and ADMIN) over the button's first place: it goes elsewhere, still clear
	local W, H = 844, 354
	local S = scaleFor(W, H)
	local row = TouchLayout.box(W - 16 - 136, 56, W - 16, 131)
	local cluster = TouchLayout.cluster(W, H, S)
	local widget, _, tap = MoveLayout.gripCheck(W, H, S, true, { MoveLayout.panel(W, S), row }, sizes)
	local t = tap :: TouchLayout.Box
	local clear = not TouchLayout.overlap(t, row) and not TouchLayout.overlap(widget, row) and not TouchLayout.overlap(widget, t)
	for _, b in TouchLayout.buttons(cluster) do
		clear = clear and not TouchLayout.overlap(t, b)
	end
	check("with ADMIN's row over FIRE: the GRIP button moves, still clear of everything", clear and t.x1 - t.x0 >= 80, `{show(widget)} {show(tap)}`)
end
do
	-- no place clear for GRIP: the one that covers the least (the touch controls CONTROL_WEIGHT × worse), not the first
	local W, H = 844, 354
	local S = scaleFor(W, H)
	local size = math.max(sizes.tapMin, sizes.tap * S)
	local spots = MoveLayout.tapSpots(W, H, S, size)
	check("GRIP's places: five, each size × size", #spots == 5 and math.abs(spots[1].x1 - spots[1].x0 - size) < 1e-6 and math.abs(spots[3].y1 - spots[3].y0 - size) < 1e-6)
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
	local _, _, tap = MoveLayout.gripCheck(W, H, S, true, blocks, sizes)
	local t = tap :: TouchLayout.Box
	local least = true
	for _, spot in spots do
		least = least and cost(t) <= cost(spot) + 1e-6
	end
	check("no GRIP place clear: the one that covers the least, not the first (over FIRE, covered whole)", least and cost(t) > 0
		and not (math.abs(t.x0 - spots[1].x0) < 1e-6 and math.abs(t.y0 - spots[1].y0) < 1e-6), show(t))
	check("MoveLayout.clash: 0 when clear, the shared area, off the screen twice", MoveLayout.clash(TouchLayout.box(10, 10, 20, 20), W, H, {}) == 0
		and MoveLayout.clash(TouchLayout.box(10, 10, 20, 20), W, H, { TouchLayout.box(15, 15, 40, 40) }) == 25
		and MoveLayout.clash(TouchLayout.box(-10, 0, 10, 10), W, H, {}) == 200)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
