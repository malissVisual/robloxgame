--!strict
-- 8.1 carrying in two (the owner: "the way Danny helps me is weird: when I turn around he teleports. When we carry
-- something heavy and I need help, we must walk, like, backwards and slowly"): the leader's steering, pure (no Roblox at
-- its top level: tests/paircarry_test.luau). While two carry a piece (a player and Danny, or two players) it sits welded
-- in front of its leader (the one who lifted it: server/Moving.luau) and the other end's carrier is held at its far end
-- by the server (server/PairHold.luau; Danny's own: server/MoveHelper.luau). The leader no longer spins to face the way
-- (client/PairSteer.luau turns Humanoid.AutoRotate off): the carry's heading (their facing: the line to the piece and
-- the partner) turns toward the way at Config.MoveHelper.PairTurn degrees a second at most, the shorter way round. A way
-- behind the facing is walked backwards (facing the piece and the partner, the leader at the front of the movement)
-- and needs no turn at all; a way ahead is walked forwards (the partner backwards). The walk is slower while the
-- heading turns (× PairTurnWalk at PairTurnFull degrees off or more, less slow in between).
-- 9.0 (the owner, 8.9.3: "When I want to walk forwards, Danny can't walk backwards"; tests/movehelper_backwards_runtime_
-- test.luau): the partner is shown on the leader's screen a moment late (the server holds him; Danny's lead makes that
-- up once the walk is under way), so a walk at once from standing ran the piece into him before he could step back on
-- that screen (2.4 studs into his body at a ping of 0.15 s). The walk eases in over PairStart s from standing, and again
-- when the way turns round (forwards to backwards at once): PairCarry.started; that start waits while the leader's own
-- screen shows the partner nearer than their place (PairCarry.waits: the server's lead has not caught up yet), and the
-- piece is never pushed into them as that screen shows them (PairCarry.keep), nor them into a wall of the house
-- (PairCarry.wall: the server's PairWall).
-- 9.2 (the owner, 8.9.5: "the carrying is better, but it feels like it's harder to control … fix it so it's playable";
-- that start took 0.85 s in Studio, 2 s online): Danny at the far end of a piece a player leads is driven by that
-- player's own client (client/PairLead.luau: his body's physics theirs), so nothing is late on their screen and none of
-- 9.0's start, waits or keep holds their walk back (they stay a crew mate's: the server holds a crew mate's body). The
-- leader's heading turns at PairLead.Turn, slower walking only to PairLead.TurnWalk; his catch-up glides in once
-- (PairCarry.catchUp), and the house's walls at his end take away the part of the leader's walk or turn that would push
-- his end further into them (PairCarry.wallShare, PairCarry.wall, PairCarry.wallTurn: the leader's own rays, no lag).
-- Angles in radians, Roblox's yaw: CFrame.Angles(0, yaw, 0) looks along (−sin yaw, 0, −cos yaw).
--   PairCarry.wrap(a)                          a in −π … π
--   PairCarry.yawOf(x, z)                      the yaw looking along (x, z) (flat)
--   PairCarry.turn(from, to, rate, dt)         `from` turned toward `to` by rate × dt at most, the shorter way
--   PairCarry.backwards(heading, want, wasBack)   is the way `want` walked backwards by a body facing `heading`: more
--                                              than 90° + PairBand off its facing; once backwards, until under 90° −
--                                              PairBand (between the two it stays as it was: no flicker sideways)
--   PairCarry.goal(want, back)                 where the heading goes: the way, or against it walking backwards
--   PairCarry.walkFactor(off, least?)          × the pair's walk with the heading `off` radians from its goal (least: ×
--                                              at PairTurnFull or more, else PairTurnWalk)
--   PairCarry.newSteer(heading)                a leader's steering state (heading, back, off)
--   PairCarry.steer(state, x, z, dt, rate?, wait?, least?)   one frame: the wanted way (x, z: Humanoid.MoveDirection;
--                                              shorter than Still: none, the heading stays) turns state.heading (rate:
--                                              radians a second, else PairTurn's), sets state.back and state.off;
--                                              returns × the pair's walk now (the turn's, walkFactor's `least`; 9.0 it
--                                              keeps state.start too)
--   PairCarry.started(state)                   9.0 × the pair's walk for the start: s walked since standing (or since
--                                              the way turned round) / PairStart, 1 from then on
--   PairCarry.keep(x, z, ox, oz, gap)          9.0 the walk (x, z) with the partner shown `gap` studs past their place
--                                              (along (ox, oz), the way from the leader to it; < 0: nearer, the piece
--                                              into them): the part toward them taken away from PairKeep.From studs
--                                              nearer, all of it at PairKeep.Stop; returns the walk (x, z)
--   PairCarry.waits(x, z, ox, oz, gap)         9.0 does the start wait (PairCarry.steer's `wait`): walking toward the
--                                              partner shown more than PairKeep.Wait studs nearer than their place
--   PairCarry.wall(x, z, wx, wz)               9.0 the walk (x, z) with the far end against a wall (wx, wz: the way into
--                                              it × the share to take away, the server's PairWall): returns the walk
--   PairCarry.catchUp(gap, speed, settled)     9.2 the far end's holder the leader's client drives: his top speed now
--                                              (AlignPosition.MaxVelocity) `gap` studs off his place, his place moving
--                                              `speed` studs a second; returns (the top speed, settled): settled within
--                                              PairLead.Settle (loose again past Loose) he is held there rigid (Rigid),
--                                              else he glides in at his place's speed + Glide (the first catch-up: never
--                                              a snap)
--   PairCarry.wallShare(room)                  9.2 how much (0 … 1) of the walk or turn pushing the far end into a wall
--                                              goes, `room` studs between his place and the wall (square off it): none
--                                              from HoldWall.Clear + PairLead.Soft on, all of it at Clear or nearer (NaN:
--                                              none)
--   PairCarry.wallTurn(from, to, ax, az, wx, wz)   9.2 the heading turned from `from` toward `to` with the far end's arm (ax,
--                                              az: from the leader's root to his place, flat) at a wall (wx, wz: the way
--                                              into it × the share to take away, as PairCarry.wall's): the part of the
--                                              turn that swings his place into the wall goes, a turn away from it stays;
--                                              returns the heading
--   PairCarry.boost(admin, kit)                × a carrier's walk from their AdminSpeed (1 … 4) and KitSpeed (1 … 2)
--                                              attributes (anything else: 1)

local Config = require(script.Parent.Config)

local PairCarry = {}

local PI = math.pi
local TAU = 2 * PI
local STILL = 0.1 -- a wanted way shorter than this is none (Humanoid.MoveDirection's length is 0 … 1)

export type Steer = {
	heading: number, -- the carry's heading now (the leader's facing)
	back: boolean, -- walking backwards
	off: number, -- radians the heading is still off its goal (0: on it)
	start: number, -- 9.0 s walked since standing or since the way turned round (PairStart at most)
	wayX: number, -- 9.0 the way wanted at the last walking step (a unit; 0, 0: standing)
	wayZ: number,
}

local function cfg(): any
	return (Config :: any).MoveHelper
end

function PairCarry.wrap(a: number): number
	return (a + PI) % TAU - PI
end

function PairCarry.yawOf(x: number, z: number): number
	return math.atan2(-x, -z)
end

function PairCarry.turn(from: number, to: number, rate: number, dt: number): number
	local diff = PairCarry.wrap(to - from)
	local step = math.max(rate, 0) * math.max(dt, 0)
	if math.abs(diff) <= step then
		return PairCarry.wrap(to)
	end
	return PairCarry.wrap(from + (if diff > 0 then step else -step))
end

function PairCarry.backwards(heading: number, want: number, wasBack: boolean): boolean
	local off = math.abs(PairCarry.wrap(want - heading))
	local band = math.rad(cfg().PairBand)
	if wasBack then
		return off > PI / 2 - band
	end
	return off > PI / 2 + band
end

function PairCarry.goal(want: number, back: boolean): number
	return if back then PairCarry.wrap(want + PI) else PairCarry.wrap(want)
end

function PairCarry.walkFactor(off: number, least: number?): number
	local c = cfg()
	local full = math.rad(c.PairTurnFull)
	local share = if full > 0 then math.clamp(math.abs(off) / full, 0, 1) else 1
	return 1 - (1 - (least or c.PairTurnWalk)) * share
end

function PairCarry.newSteer(heading: number): Steer
	return { heading = PairCarry.wrap(heading), back = false, off = 0, start = 0, wayX = 0, wayZ = 0 }
end

function PairCarry.steer(state: Steer, x: number, z: number, dt: number, rate: number?, wait: boolean?, least: number?): number
	local length = math.sqrt(x * x + z * z)
	if length < STILL then
		state.off = 0
		state.start, state.wayX, state.wayZ = 0, 0, 0 -- (9.0 standing: the next walk eases in)
		return 1
	end
	-- 9.0 the start: from standing, or the way turned round at once (more than a right angle in one step); `wait`: it
	-- waits this step (the partner not clear of the piece yet on this screen: PairCarry.waits), once begun (never held
	-- at a standstill: the first step always goes)
	local ux, uz = x / length, z / length
	if ux * state.wayX + uz * state.wayZ < 0 then
		state.start = 0
	end
	state.wayX, state.wayZ = ux, uz
	if not wait or state.start <= 0 then
		state.start = math.min(state.start + math.max(dt, 0), math.max(cfg().PairStart or 0, 0))
	end
	local want = PairCarry.yawOf(x, z)
	state.back = PairCarry.backwards(state.heading, want, state.back)
	local goal = PairCarry.goal(want, state.back)
	state.heading = PairCarry.turn(state.heading, goal, rate or math.rad(cfg().PairTurn), dt)
	state.off = math.abs(PairCarry.wrap(goal - state.heading))
	return PairCarry.walkFactor(state.off, least)
end

function PairCarry.started(state: Steer): number
	local full = cfg().PairStart or 0
	if full <= 0 then
		return 1
	end
	return math.clamp(state.start / full, 0, 1)
end

function PairCarry.keep(x: number, z: number, ox: number, oz: number, gap: number): (number, number)
	local push = x * ox + z * oz
	local k = cfg().PairKeep
	local into = -gap - k.From
	if gap ~= gap or into <= 0 or push <= 0 then
		return x, z
	end
	local span = k.Stop - k.From
	local share = if span > 0 then math.clamp(into / span, 0, 1) else 1
	return x - ox * push * share, z - oz * push * share
end

function PairCarry.waits(x: number, z: number, ox: number, oz: number, gap: number): boolean
	return gap == gap and gap < -cfg().PairKeep.Wait and x * ox + z * oz > 0
end

function PairCarry.wall(x: number, z: number, wx: number, wz: number): (number, number)
	local size = math.sqrt(wx * wx + wz * wz)
	if size ~= size or size < 1e-3 then
		return x, z
	end
	local ux, uz = wx / size, wz / size
	local push = x * ux + z * uz
	if push <= 0 then
		return x, z
	end
	local share = math.min(size, 1)
	return x - ux * push * share, z - uz * push * share
end

function PairCarry.catchUp(gap: number, speed: number, settled: boolean): (number, boolean)
	local lead = cfg().PairLead
	local there = gap == gap and gap <= (if settled then lead.Loose else lead.Settle)
	if there then
		return lead.Rigid, true
	end
	local moving = if speed == speed then math.clamp(speed, 0, cfg().HoldCap) else 0 -- (a door's trip: HoldCap at most)
	return moving + lead.Glide, false
end

function PairCarry.wallShare(room: number): number
	if room ~= room then
		return 0
	end
	local c = cfg()
	local clear = c.HoldWall.Clear
	local soft = math.max(c.PairLead.Soft, 0)
	if room <= clear then
		return 1
	elseif room >= clear + soft then
		return 0
	end
	return (clear + soft - room) / soft
end

function PairCarry.wallTurn(from: number, to: number, ax: number, az: number, wx: number, wz: number): number
	local size = math.sqrt(wx * wx + wz * wz)
	local turn = PairCarry.wrap(to - from)
	if size ~= size or size < 1e-3 or math.abs(turn) < 1e-9 or ax ~= ax or az ~= az then
		return to
	end
	-- the arm turned by `turn` about the leader's root (CFrame.Angles(0, turn, 0): x' = x cos + z sin, z' = −x sin + z cos)
	local c, s = math.cos(turn), math.sin(turn)
	local dx, dz = ax * c + az * s - ax, -ax * s + az * c - az
	if dx * wx + dz * wz <= 0 then
		return to -- (away from the wall, or along it)
	end
	return PairCarry.wrap(from + turn * (1 - math.min(size, 1)))
end

function PairCarry.boost(admin: any, kit: any): number
	local a = if type(admin) == "number" and admin == admin then math.clamp(admin, 1, 4) else 1
	local k = if type(kit) == "number" and kit == kit then math.clamp(kit, 1, 2) else 1
	return a * k
end

return PairCarry
