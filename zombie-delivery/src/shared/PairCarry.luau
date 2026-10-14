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
-- Angles in radians, Roblox's yaw: CFrame.Angles(0, yaw, 0) looks along (−sin yaw, 0, −cos yaw).
--   PairCarry.wrap(a)                          a in −π … π
--   PairCarry.yawOf(x, z)                      the yaw looking along (x, z) (flat)
--   PairCarry.turn(from, to, rate, dt)         `from` turned toward `to` by rate × dt at most, the shorter way
--   PairCarry.backwards(heading, want, wasBack)   is the way `want` walked backwards by a body facing `heading`: more
--                                              than 90° + PairBand off its facing; once backwards, until under 90° −
--                                              PairBand (between the two it stays as it was: no flicker sideways)
--   PairCarry.goal(want, back)                 where the heading goes: the way, or against it walking backwards
--   PairCarry.walkFactor(off)                  × the pair's walk with the heading `off` radians from its goal
--   PairCarry.newSteer(heading)                a leader's steering state (heading, back, off)
--   PairCarry.steer(state, x, z, dt, rate?)    one frame: the wanted way (x, z: Humanoid.MoveDirection; shorter than
--                                              Still: none, the heading stays) turns state.heading (rate: radians a
--                                              second, else PairTurn's), sets state.back and state.off; returns × the
--                                              pair's walk now
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

function PairCarry.walkFactor(off: number): number
	local c = cfg()
	local full = math.rad(c.PairTurnFull)
	local share = if full > 0 then math.clamp(math.abs(off) / full, 0, 1) else 1
	return 1 - (1 - c.PairTurnWalk) * share
end

function PairCarry.newSteer(heading: number): Steer
	return { heading = PairCarry.wrap(heading), back = false, off = 0 }
end

function PairCarry.steer(state: Steer, x: number, z: number, dt: number, rate: number?): number
	if math.sqrt(x * x + z * z) < STILL then
		state.off = 0
		return 1
	end
	local want = PairCarry.yawOf(x, z)
	state.back = PairCarry.backwards(state.heading, want, state.back)
	local goal = PairCarry.goal(want, state.back)
	state.heading = PairCarry.turn(state.heading, goal, rate or math.rad(cfg().PairTurn), dt)
	state.off = math.abs(PairCarry.wrap(goal - state.heading))
	return PairCarry.walkFactor(state.off)
end

function PairCarry.boost(admin: any, kit: any): number
	local a = if type(admin) == "number" and admin == admin then math.clamp(admin, 1, 4) else 1
	local k = if type(kit) == "number" and kit == kit then math.clamp(kit, 1, 2) else 1
	return a * k
end

return PairCarry
