-- 8.1 carrying in two (the owner: "the way Danny helps me is weird: when I turn around he teleports. When we carry
-- something heavy and I need help, we must walk, like, backwards and slowly"): the leader's steering, shared/
-- PairCarry.luau (pure; client/PairSteer.luau runs it every frame). Roblox's yaw; the heading turns toward the way at
-- PairTurn degrees a second at most, the shorter way round; a way behind the facing is walked backwards (no turn at
-- all), with a band against flickering sideways; the walk slower while the heading turns; a 180° turn of the input,
-- an input sweeping round, a still stick; the boosts (AdminSpeed, KitSpeed). tests/movehelper_runtime_test.luau and
-- tests/movehelper_art_runtime_test.luau walk the leader with it.
local PairCarry = require("./PairCarry")
local Brain = require("./MoveHelperBrain")
local Config = require("./Config")

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
	return math.abs(a - b) < (eps or 1e-9)
end

local H = Config.MoveHelper
local PI = math.pi
local RATE = math.rad(H.PairTurn)
local DT = 1 / 60

-- The numbers ---------------------------------------------------------------------------------------------------------------

check("PairTurn between 50 and 70 degrees a second (two movers turn slowly)", H.PairTurn >= 50 and H.PairTurn <= 70, H.PairTurn)
check("the pair walks a touch slower than before (Moving.Speed.Pair under 0.8), slower still while it turns", Config.Moving.Speed.Pair < 0.8
	and Config.Moving.Speed.Pair >= 0.6 and H.PairTurnWalk > 0.2 and H.PairTurnWalk < 1 and H.PairTurnFull > 0)
check("the band against the flicker: under 45 degrees", H.PairBand > 0 and H.PairBand < 45)

-- Angles ----------------------------------------------------------------------------------------------------------------------

check("wrap: into −π … π", near(PairCarry.wrap(3 * PI / 2), -PI / 2) and near(PairCarry.wrap(-3 * PI / 2), PI / 2) and near(PairCarry.wrap(0.3), 0.3)
	and near(PairCarry.wrap(2 * PI + 0.3), 0.3))
check("yawOf: Roblox's (CFrame.Angles(0, yaw, 0) looks along (−sin yaw, 0, −cos yaw))", near(PairCarry.yawOf(0, -1), 0) and near(PairCarry.yawOf(-1, 0), PI / 2)
	and near(PairCarry.yawOf(1, 0), -PI / 2) and near(math.abs(PairCarry.yawOf(0, 1)), PI))
do
	local ok = true
	for k = 0, 35 do
		local yaw = PairCarry.wrap(k * 0.17 - 3)
		local lx, lz = -math.sin(yaw), -math.cos(yaw)
		ok = ok and near(PairCarry.yawOf(lx, lz), yaw, 1e-9)
	end
	check("yawOf of a yaw's look is that yaw (all round)", ok)
end

-- The turn --------------------------------------------------------------------------------------------------------------------

check("turn: at most rate × dt a step", near(PairCarry.turn(0, 1, RATE, 0.1), RATE * 0.1) and near(PairCarry.turn(0, -1, RATE, 0.1), -RATE * 0.1))
check("turn: onto the goal when it is within the step", near(PairCarry.turn(0, 0.05, RATE, 0.1), 0.05))
check("turn: the shorter way round (from 170° to −170° is 20° on, through 180°)", PairCarry.turn(math.rad(170), math.rad(-170), RATE, 0.1) > math.rad(170)
	or PairCarry.turn(math.rad(170), math.rad(-170), RATE, 0.1) < -math.rad(170))
check("turn: nothing with no time or no rate", near(PairCarry.turn(0.4, 2, RATE, 0), 0.4) and near(PairCarry.turn(0.4, 2, 0, 1), 0.4))

-- Backwards ------------------------------------------------------------------------------------------------------------------

check("the way ahead: forwards", not PairCarry.backwards(0, 0, false) and not PairCarry.backwards(0, math.rad(60), false))
check("the way right behind: backwards (facing the piece and the partner)", PairCarry.backwards(0, PI, false))
check("sideways (90°): as it was (no flicker)", not PairCarry.backwards(0, PI / 2, false) and PairCarry.backwards(0, PI / 2, true))
check("forwards until 90° + PairBand off, then backwards", not PairCarry.backwards(0, math.rad(90 + H.PairBand - 1), false)
	and PairCarry.backwards(0, math.rad(90 + H.PairBand + 1), false))
check("backwards until under 90° − PairBand, then forwards", PairCarry.backwards(0, math.rad(90 - H.PairBand + 1), true)
	and not PairCarry.backwards(0, math.rad(90 - H.PairBand - 1), true))
check("the heading's goal: the way forwards, against it backwards", near(PairCarry.goal(0.5, false), 0.5) and near(PairCarry.goal(0.5, true), PairCarry.wrap(0.5 + PI)))

-- The walk while it turns ----------------------------------------------------------------------------------------------------

check("the pair's walk in full on its heading", near(PairCarry.walkFactor(0), 1))
check("× PairTurnWalk at PairTurnFull degrees off or more", near(PairCarry.walkFactor(math.rad(H.PairTurnFull)), H.PairTurnWalk)
	and near(PairCarry.walkFactor(math.rad(170)), H.PairTurnWalk))
check("…less slow in between, never faster", PairCarry.walkFactor(math.rad(H.PairTurnFull / 2)) < 1 and PairCarry.walkFactor(math.rad(H.PairTurnFull / 2)) > H.PairTurnWalk)

-- Steering a leader ----------------------------------------------------------------------------------------------------------

-- The way (x, z) at `yaw` (a stick pushed that way).
local function way(yaw: number): (number, number)
	return -math.sin(yaw), -math.cos(yaw)
end
do
	local s = PairCarry.newSteer(0)
	local factor = PairCarry.steer(s, 0, 0, DT)
	check("a still stick: the heading stays, the walk the pair's", near(s.heading, 0) and near(factor, 1) and not s.back)
	local x, z = way(PI)
	local moved = 0
	for _ = 1, 120 do
		local before = s.heading
		factor = PairCarry.steer(s, x, z, DT)
		moved += math.abs(PairCarry.wrap(s.heading - before))
	end
	check("the stick right back (180°): walked backwards, the heading never moves (no swing), at the pair's full walk", s.back and moved == 0 and near(factor, 1))
	x, z = way(0)
	for _ = 1, 30 do
		factor = PairCarry.steer(s, x, z, DT)
	end
	check("…and forwards again (toward the partner): no turn either", not s.back and near(s.heading, 0) and near(factor, 1))
end
do
	-- the way swept round 180° in half a second (the camera spun round, the stick held): the heading follows at PairTurn
	-- at most; the way soon behind the facing, the leader walks it backwards (no need to turn all the way round)
	local s = PairCarry.newSteer(0)
	local most, slowest, t = 0, 1, 0
	for _ = 1, 600 do
		t += DT
		local x, z = way(math.min(t / 0.5, 1) * math.rad(179))
		local before = s.heading
		local factor = PairCarry.steer(s, x, z, DT)
		most = math.max(most, math.abs(PairCarry.wrap(s.heading - before)))
		slowest = math.min(slowest, factor)
	end
	check("an input swept 180° round in 0.5 s: the heading turns PairTurn degrees a second at most", most <= RATE * DT + 1e-12, math.deg(most) / DT)
	check("…the new way soon behind: walked backwards, facing back the old way (on it again, the pair's full walk)", s.back
		and near(s.heading, PairCarry.goal(math.rad(179), true), 1e-6) and near(PairCarry.walkFactor(s.off), 1), math.deg(s.heading))
	check("…the walk slower while it turned (PairTurnWalk at the worst)", near(slowest, H.PairTurnWalk))
	-- the way swept round 180° slowly (45° a second: a gentle curve): the heading follows it forwards all the way round
	s = PairCarry.newSteer(0)
	most, t = 0, 0
	local backward = false
	for _ = 1, 360 do
		t += DT
		local x, z = way(math.min(t / 4, 1) * math.rad(179))
		local before = s.heading
		PairCarry.steer(s, x, z, DT)
		most = math.max(most, math.abs(PairCarry.wrap(s.heading - before)))
		backward = backward or s.back
	end
	check("an input swept 180° round in 4 s: the heading follows it forwards all the way round, PairTurn degrees a second at most",
		not backward and most <= RATE * DT + 1e-12 and near(s.heading, math.rad(179), 1e-6), math.deg(s.heading))
end
do
	-- the way to the right (90°): forwards still (the band), the heading turns there at PairTurn
	local s = PairCarry.newSteer(0)
	local x, z = way(-PI / 2)
	local steps = 0
	while math.abs(PairCarry.wrap(s.heading + PI / 2)) > 1e-9 and steps < 1000 do
		PairCarry.steer(s, x, z, DT)
		steps += 1
	end
	check("the way to the right: a forward turn of 90° in 90 / PairTurn s", not s.back and near(steps * DT, (PI / 2) / RATE, DT + 1e-9), steps * DT)
	-- the stick flicking either side of 90° behind the new facing: backwards then stays (the band)
	local flips = 0
	local was = s.back
	for k = 1, 40 do
		local off = if k % 2 == 0 then math.rad(85) else math.rad(95)
		x, z = way(s.heading + off)
		PairCarry.steer(s, x, z, DT)
		if s.back ~= was then
			flips += 1
			was = s.back
		end
	end
	check("a way flicking round 90° off: no flicker between forwards and backwards", flips == 0, flips)
end
do
	-- a 180° turn of the body over the steps' own rate: the client's frame time does not matter
	local a, b = PairCarry.newSteer(0), PairCarry.newSteer(0)
	local x, z = way(-PI / 2)
	for _ = 1, 60 do
		PairCarry.steer(a, x, z, 1 / 60)
	end
	for _ = 1, 20 do
		PairCarry.steer(b, x, z, 1 / 20)
	end
	check("the same second at 60 or 20 frames: the same turn", near(a.heading, b.heading, 1e-9) and near(a.heading, -RATE, 1e-9), `{a.heading} {b.heading}`)
end

-- 9.0 the start, the partner as the leader's screen shows them, the wall (the owner, 8.9.3: "When I want to walk forwards,
-- Danny can't walk backwards"; tests/movehelper_backwards_runtime_test.luau plays them with the real server) -----------------

do
	local K = H.PairKeep
	local s = PairCarry.newSteer(0)
	local x, z = way(0) -- (forwards: toward the partner)
	PairCarry.steer(s, 0, 0, DT)
	check("9.0 standing: no start yet", PairCarry.started(s) == 0)
	local t, last, rising = 0, 0, true
	while PairCarry.started(s) < 1 and t < 5 do
		PairCarry.steer(s, x, z, DT)
		t += DT
		rising = rising and PairCarry.started(s) >= last
		last = PairCarry.started(s)
	end
	check("9.0 the walk eases in from standing over PairStart s (never at once)", H.PairStart > 0 and near(t, H.PairStart, DT + 1e-9) and rising, t)
	local rx, rz = way(PI)
	PairCarry.steer(s, rx, rz, DT)
	check("…the way turned round at once (forwards to backwards): it eases in again", PairCarry.started(s) < 0.1, PairCarry.started(s))
	for _ = 1, 30 do
		PairCarry.steer(s, rx, rz, DT)
	end
	local was = PairCarry.started(s)
	for _ = 1, 30 do
		PairCarry.steer(s, rx, rz, DT, nil, true)
	end
	check("…`wait` (the partner not clear of the piece yet on the leader's screen): the start waits, the walk never slows for it",
		near(PairCarry.started(s), was) and was > 0)
	PairCarry.steer(s, 0, 0, DT)
	check("…standing again: from the start", PairCarry.started(s) == 0)
	-- the partner shown `gap` studs past their place along (0, -1) (ahead of the leader: the way to them)
	local ox, oz = 0, -1
	check("9.0 waits: walking toward the partner shown more than PairKeep.Wait studs nearer than their place",
		PairCarry.waits(0, -1, ox, oz, -(K.Wait + 0.01)) and not PairCarry.waits(0, -1, ox, oz, -(K.Wait - 0.01))
		and not PairCarry.waits(0, 1, ox, oz, -1) and not PairCarry.waits(1, 0, ox, oz, -1) and not PairCarry.waits(0, -1, ox, oz, 0 / 0))
	local kx, kz = PairCarry.keep(0, -1, ox, oz, -(K.From - 0.01))
	check("9.0 keep: shown nearer than From studs, the walk as it was", kx == 0 and kz == -1)
	kx, kz = PairCarry.keep(0, -1, ox, oz, -(K.From + K.Stop) / 2)
	check("…between From and Stop: part of the walk toward them goes", kz > -1 and kz < 0 and kx == 0, kz)
	kx, kz = PairCarry.keep(0.6, -0.8, ox, oz, -K.Stop - 1)
	check("…Stop studs in or more: all of the walk toward them goes, the rest stays (sideways)", near(kz, 0) and near(kx, 0.6), `{kx} {kz}`)
	kx, kz = PairCarry.keep(0, 1, ox, oz, -K.Stop - 1)
	check("…a walk away from them: never touched", kx == 0 and kz == 1)
	-- the wall: its way in (+X) × the share to take away
	local wx, wz = PairCarry.wall(1, 0, 0.5, 0)
	check("9.0 wall: half the walk into it goes at half a share", near(wx, 0.5) and near(wz, 0), wx)
	wx, wz = PairCarry.wall(0.6, 0.8, 1, 0)
	check("…all of it at a full share, along it as ever", near(wx, 0) and near(wz, 0.8), `{wx} {wz}`)
	wx, wz = PairCarry.wall(-1, 0, 1, 0)
	check("…away from it, or no wall: as it was", wx == -1 and wz == 0 and select(1, PairCarry.wall(1, 0, 0, 0)) == 1)
end

-- 9.2 you drive Danny's end (the owner, 8.9.5: "it feels like it's harder to control … fix it so it's playable"; client/
-- PairLead.luau): no start, no wait, a quicker turn, his first catch-up a glide, the walls at his end your own rays -----------

do
	local L = H.PairLead
	check("9.2 the drive's numbers: on, the heading's turn quicker than a crew mate's (100 – 180 degrees a second), the walk less slow while it turns",
		L.On == true and L.Turn >= 100 and L.Turn <= 180 and L.Turn > H.PairTurn and L.TurnWalk > H.PairTurnWalk and L.TurnWalk <= 1, L.Turn)
	check("…rigid once there, the first catch-up a glide (Glide studs a second over his place's own), a door's jump far past any walk",
		L.Rigid >= 100 and L.Glide > 0 and L.Glide < 12 and L.Settle < L.Loose and L.Jump >= 20 and L.Spin > Brain.holdTurn())
	check("…the server's look: off more than Sane studs for Grace s (a few studs, a second or two: never a stumble's)", L.Sane >= 4 and L.Sane <= 12
		and L.Grace >= 0.5 and L.Grace <= 3)
	-- the walk from standing: the pair's at once (9.0 eased in over PairStart)
	local s = PairCarry.newSteer(0)
	PairCarry.steer(s, 0, 0, DT)
	local x, z = way(0)
	local first = PairCarry.steer(s, x, z, DT, math.rad(L.Turn), false, L.TurnWalk)
	check("9.2 from standing straight ahead or behind: the pair's walk at once (nothing multiplies it but the turn's)", near(first, 1)
		and near(PairCarry.steer(PairCarry.newSteer(0), -x, -z, DT, math.rad(L.Turn), false, L.TurnWalk), 1))
	check("…while the heading turns, the walk at TurnWalk at the worst (least)", near(PairCarry.walkFactor(math.rad(170), L.TurnWalk), L.TurnWalk)
		and near(PairCarry.walkFactor(math.rad(170)), H.PairTurnWalk))
	-- the turn at PairLead.Turn: a quarter round in 90 / Turn s
	s = PairCarry.newSteer(0)
	x, z = way(-PI / 2)
	local steps = 0
	while math.abs(PairCarry.wrap(s.heading + PI / 2)) > 1e-9 and steps < 1000 do
		PairCarry.steer(s, x, z, DT, math.rad(L.Turn), false, L.TurnWalk)
		steps += 1
	end
	check(`9.2 a quarter turn in 90 / {L.Turn} s (PairTurn's {H.PairTurn}: twice as long)`, near(steps * DT, (PI / 2) / math.rad(L.Turn), DT + 1e-9), steps * DT)
	-- the catch-up
	local limit, settled = PairCarry.catchUp(2, 0, false)
	check("9.2 catchUp: 2 studs off his place, standing: a glide at Glide (never a snap)", near(limit, L.Glide) and not settled, limit)
	limit, settled = PairCarry.catchUp(2, 9.8, false)
	check("…his place walking at 9.8: a glide at 9.8 + Glide", near(limit, 9.8 + L.Glide) and not settled, limit)
	limit, settled = PairCarry.catchUp(L.Settle - 0.01, 9.8, false)
	check("…within Settle: there, rigid (Rigid)", limit == L.Rigid and settled)
	limit, settled = PairCarry.catchUp((L.Settle + L.Loose) / 2, 9.8, true)
	local stays = settled and limit == L.Rigid
	limit, settled = PairCarry.catchUp(L.Loose + 0.01, 9.8, true)
	check("…settled, it stays rigid until Loose studs off (no flicker), then glides again", stays and not settled and near(limit, 9.8 + L.Glide))
	limit = PairCarry.catchUp(0 / 0, 0 / 0, false)
	check("…no numbers (NaN): a glide at Glide", near(limit, L.Glide), limit)
	-- the walls: how much of the walk or turn into one goes
	local clear, soft = H.HoldWall.Clear, L.Soft
	check("9.2 wallShare: none from his clearance + Soft studs off the wall, all of it at his clearance or nearer (or past it), between in step",
		PairCarry.wallShare(clear + soft + 0.01) == 0 and PairCarry.wallShare(clear) == 1 and PairCarry.wallShare(-2) == 1
		and near(PairCarry.wallShare(clear + soft / 2), 0.5) and PairCarry.wallShare(0 / 0) == 0)
	-- a turn at a wall: the far end 9 studs ahead of the leader (+X), a wall ahead of it at an angle (its way in: (1, 1)/√2)
	local s2 = math.sqrt(0.5)
	local heading = PairCarry.yawOf(1, 0) -- (facing +X)
	local towardWall = PairCarry.wallTurn(heading, heading + 0.1, 9, 0, s2, s2) -- (+0.1 swings the end toward −Z: away)
	local intoWall = PairCarry.wallTurn(heading, heading - 0.1, 9, 0, s2, s2) -- (−0.1 swings it toward +Z: into the wall)
	local half = PairCarry.wallTurn(heading, heading - 0.1, 9, 0, s2 / 2, s2 / 2)
	check("9.2 wallTurn: a turn swinging his end into the wall (its push along the way in) goes, all of it at a full share, half at half",
		near(intoWall, heading) and near(PairCarry.wrap(half - heading), -0.05, 1e-9), `{intoWall - heading} {half - heading}`)
	check("…a turn swinging it away from the wall stays as it was, and no wall (share 0) leaves any turn", near(towardWall, PairCarry.wrap(heading + 0.1))
		and near(PairCarry.wallTurn(heading, heading - 0.1, 9, 0, 0, 0), PairCarry.wrap(heading - 0.1)))
end

-- The far end's holder keeps up -----------------------------------------------------------------------------------------------

do
	local walk = Config.Movement.Walk * Config.Moving.Speed.Pair
	local top = Brain.holdSpeed(walk)
	-- the far end of a long piece (the marble slab: 9.8 deep) swings round the leader's root as the heading turns
	local reach = Config.Cargo.CarryFront + 9.8 + H.Standoff
	check("his top speed keeps up with the pair's walk", top >= walk * 1.2)
	check("…and with the far end of a long piece swinging round a turn at PairTurn, the walk slowed meanwhile", top >= walk * H.PairTurnWalk + RATE * reach, `{top} vs {walk * H.PairTurnWalk + RATE * reach}`)
	check("…yet no faster than a sprint (no flying across the room)", top <= Config.Movement.Walk * H.Sprint * 1.2, top)
	check("his body turns faster than the heading does (always facing the leader)", Brain.holdTurn() > RATE)
end

-- The boosts -----------------------------------------------------------------------------------------------------------------

check("boost: AdminSpeed × KitSpeed, clamped", near(PairCarry.boost(2, 1.5), 3) and near(PairCarry.boost(9, 9), 8) and near(PairCarry.boost(0.2, 0.2), 1))
check("boost: anything else is 1", near(PairCarry.boost(nil, nil), 1) and near(PairCarry.boost("x", 0 / 0), 1))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
