--!strict
-- 7.0, the depot's helper ("Danny from the depot", server/MoveHelper.luau; the owner: solo play is allowed with an AI
-- helper, design/rework/NAVRH.md): his decisions, pure (no Roblox at its top level: tests/movehelper_test.luau runs it
-- in the standalone Luau). Positions are plain numbers (X and Z along the ground); "inside" is a move's interior, its
-- own world far from the street with the front door between the two. The numbers are Config.MoveHelper's, the carry's
-- MovingRules'.
-- 7.x Danny, a partner (the owner: "he helps weirdly, only some things, and mainly we don't carry anything together"):
-- a clear priority list each step (decide): his end of your piece; zombies (never while he holds your piece's other
-- end); your two-person lift (he sprints over, or fades over from far; 8.3: your call, he walks over); the piece in his
-- arms to the van; the van's back for whoever comes with a piece; the order; the other side of a heavy two-hands piece
-- you carry alone; the next piece (★ first, then the most value a second of the trip, one-hand and two-hands ones; never
-- one you are about to lift).
--
-- 8.3 Danny's orders (the owner: "when you want to take a heavy thing you must wait until the helper comes; I'd like to
-- click on him any time and tell him what to do, or an auto mode where he carries only light things and calls for help
-- with a heavy one"): four orders (Modes), each given from his command card (client/MoveHelperCard.luau) by his move's
-- crew only (order); a two-person Lift calls him on every order and you wait at your end while he WALKS to its other
-- end (decide's "come"; inPlace; approach: a fade-over only as the last resort); on AUTO he carries the light pieces
-- alone (light) and asks for a hand with a heavy one (pickAsk, askKept), never nagging (Config AskAgain).
--
--   MoveHelperBrain.wanted(players)            does a crew of this many players get him (Solo, Duo)?
--   MoveHelperBrain.Modes                      8.3 the orders in the card's order: "auto" (AUTO, the default) | "help"
--                                              (HELP ME: behind you, lifts with you) | "stay" (WAIT HERE) | "van"
--                                              (WAIT AT VAN)
--   MoveHelperBrain.validMode(mode)            one of Modes?
--   MoveHelperBrain.order(mode, current, crew) 8.3 a command checked: (the new order, nil) or (nil, why: "crew" not his
--                                              move's crew, "mode" no such order, "same" in force already)
--   MoveHelperBrain.modeName(mode)             8.3 its name on the card and the status line ("AUTO", "HELP ME" ...)
--   MoveHelperBrain.status(mode, doing)        8.3 the status line: "AUTO · Carrying the Lamp to the van"
--   MoveHelperBrain.light(class, weight)       8.3 a piece he carries alone on AUTO: one-hand, or two-hands under
--                                              LightWeight (heavy: a pair one, or two-hands at LightWeight or more)
--   MoveHelperBrain.pickAsk(list)              8.3 AUTO: the heavy piece he asks a hand for (★ first, then the best
--                                              worth; home or on the ground, not broken, not one you are about to
--                                              lift, one that still fits the van, within AskFar), nil: none
--   MoveHelperBrain.askKept(asked, waited, fits, free)   8.3 does his ask go on: "on", "timeout" (nobody came within
--                                              AskWait s of his "give me a hand!"), "gone" (somebody holds it, no room)
--   MoveHelperBrain.inPlace(gap, stuckFor)     8.3 at the other end of your call: within CallReady studs of his place,
--                                              or within CallClose and blocked CallStuck s (the hold walks him the rest)
--   MoveHelperBrain.newApproach() / approach(a, gap, dt)   8.3 his walk to your call: true once he has come no closer
--                                              than CallGain studs for CallBlink s (the last resort: a fade-over)
--   MoveHelperBrain.callKept(fromPiece, reach, ready, readyFor)   8.3 does your call go on: "on", "away" (you walked
--                                              CallLeave studs past the Lift's reach), "idle" (he was in place CallIdle s
--                                              and you never lifted)
--   MoveHelperBrain.routeCost(...)             studs on foot from one point to another, through the front door when
--                                              they are in different worlds
--   MoveHelperBrain.routeVia(..., list, allowed?)   7.x farm move: the same through the best of several doors (a farm's
--                                              front door, its barn doors; only the `allowed` indexes): (studs, index)
--   MoveHelperBrain.reserved(playerCost, myCost)   a piece a crew player with free hands is about to lift: within
--                                              Reserve studs of it and nearer than he is (the player's lift wins)
--   MoveHelperBrain.worth(c)                   a piece's rank for a trip: its value a second of the trip (TripBase
--                                              studs added, the way back to the van at the carry's walk)
--   MoveHelperBrain.pickItem(list, backOpen)   the next piece he carries out alone (★ first, then the best worth; a
--                                              one-hand or (8.3) a light two-hands piece, never a pair one, a broken
--                                              one, a reserved one, one that no longer fits the van or one lying by the
--                                              van while its back is shut) and whether the van is full for the ones left
--   MoveHelperBrain.pickLift(list)             the crew's two-person lift he comes to: a pair piece a crew player
--                                              drags alone, the nearest within HelpFar, not one he gave up on
--   MoveHelperBrain.pickAssist(list)           a heavy two-hands piece (AssistWeight or more) a crew player carries
--                                              alone within AssistFar, not by the van's back already: he takes its
--                                              other side (the pair's walk for both)
--   MoveHelperBrain.shouldFlee(threat, fleeing, holding)   a zombie near: run (never while holding the other end of
--                                              your piece: the player leads); on until none is within SafeRange
--   MoveHelperBrain.fleeTo(x, z, zx, zz)       where he runs: FleeStep studs straight away from the zombie
--   MoveHelperBrain.decide(input)              what he does now and the piece's spot: "down" | "hold" | "flee" |
--                                              "come" (8.3 your call) | "help" | "deliver" | "open" | "stay" | "wait" |
--                                              "assist" | "follow" | "ask" (8.3) | "fetch"
--   MoveHelperBrain.atTruck(open, still, waited, mayOpen)   a piece in his arms at the van's back: "load" | "open" |
--                                              "wait" | "drop"
--   MoveHelperBrain.speed(walk, action, carry, weight)   his walk now: × Speed (× the carry's alone: "hand" | "both"),
--                                              Sprint × to a lift (8.3: and to your call), Flee × running away
--   MoveHelperBrain.trained(owner)             8.1 SANDBOX: his walk x this for the move's owner (Danny's training,
--                                              the level in their player attribute Config.SandboxUpgrades.Danny,
--                                              shared/UpgradeRules.luau dannySpeed; 1 without one)
--   MoveHelperBrain.stuck(stuckFor, moved, dt, speed)    seconds without progress (under a fifth of his walk)
--   MoveHelperBrain.unstuck(stuckFor)          what a stuck walk does: "walk" | "repath" (StuckRepath s) | "nudge"
--                                              (StuckSnap s: he appears at his way's next point)
--   MoveHelperBrain.endRise(floorRise, carrierRise)   his root's height at your piece's far end over its middle: the
--                                              floor's there (stairs, steps) when within HoldStep of the floor under
--                                              the carrier (8.3: else the carrier's floor: never a roof, never a pop)
--   MoveHelperBrain.farEnd(depth)              how far in front of the piece's middle his root stands (its far face
--                                              and Standoff)
--   8.1 carrying in two (the owner: "when I turn around he teleports"; the leader's steering: shared/PairCarry.luau):
--   the far end's holder (Danny, or a crew mate who helps lift: server/PairHold.luau) is never put there at once while
--   holding, he walks there at a top speed that fits the pair's walk and the swing of a turn:
--   MoveHelperBrain.holdSpeed(walk, pace?)     his top speed (AlignPosition.MaxVelocity) with the leader walking at
--                                              `walk` (the carry's CarrySpeed × PairCarry.boost): × HoldMargin + HoldExtra;
--                                              8.3 (the owner: "when I run, he just goes behind me"): of the leader's real
--                                              speed `pace` when that is more (holdPace), at most HoldCap (never under
--                                              the carry's own)
--   MoveHelperBrain.holdPace(trail, x, z, dt, reset)   8.3 one look at the leader's root (x, z along the ground): their
--                                              real speed (a rise taken at once, HoldCap at most; a fall over
--                                              HoldPace.Fall s) and their velocity smoothed over HoldLead.Smooth s;
--                                              `reset` (a new hold, a door's fade) or a jump past HoldPace.Jump: none
--   MoveHelperBrain.leadTime(ping)             8.3 the seconds Danny is aimed ahead: HoldLead.Base + ping × Ping, 0 … Most
--   MoveHelperBrain.holdLead(trail, seconds)   8.3 how far ahead (x, z studs): the leader's smoothed velocity × seconds,
--                                              HoldLead.Far at most
--   MoveHelperBrain.holdTurn()                 his body's top turn (radians a second: HoldTurn × PairTurn)
--   MoveHelperBrain.newTrail()                 a holder's record of how long he has been behind
--   MoveHelperBrain.holdTrack(trail, gap, crossed, speed, dt)   one look: `gap` studs off his place, the piece in the
--                                              other world (`crossed`: a door's fade) → (top speed now, snap): snap
--                                              only when crossed; more than HoldBehind studs off for HoldStuck s, an
--                                              ease of HoldEase s (the gap / HoldEase a second); else `speed`
--   8.3 (the owner: "he just jumps weirdly … make him walk like me, backwards too"):
--   MoveHelperBrain.holdClimb(trail, height, dt, snap)   his root's height now: toward `height` at HoldClimb studs a
--                                              second at most (a step stepped, never popped; at once on a new hold or a
--                                              door's fade)
--   MoveHelperBrain.holdLegs(trail, forward, side, dt)   the speed his legs step at (negative: backwards, 0: standing)
--                                              from his root's own velocity in his frame: his whole speed along the
--                                              ground, from HoldLegs.From, under HoldLegs.To standing, backwards past
--                                              Band behind him, forwards past Band ahead, sideways as they went
--   MoveHelperBrain.aside(x, z, door)          a place in a doorway (Aside's zone): the place beside it, along the wall
--                                              (he never stands where you walk through); else the place itself
--   MoveHelperBrain.followSpot(x, z, lookX, lookZ)       his place behind you ("Help me")
--   MoveHelperBrain.doing(action, name, full)  what he does, in words (client/MoveHelperHud.luau's line)
--   MoveHelperBrain.Lines                      what he says (a speech bubble over his head; plain text)
--   MoveHelperBrain.line(key, sandbox)         his line for `key` (8.0 SANDBOX: SandboxLines' where the test world has
--                                              no Wall and no depot)

local Config = require(script.Parent.Config)
local Rules = require(script.Parent.MovingRules)
local UpgradeRules = require(script.Parent.UpgradeRules) -- 8.1: Danny's training

local MoveHelperBrain = {}

export type Mode = "auto" | "help" | "stay" | "van"

-- A piece he might carry out alone.
export type Candidate = {
	spot: number,
	class: string, -- hand | both | pair
	state: string, -- home | carried | ground | truck
	star: boolean,
	broken: boolean,
	cost: number, -- studs to it (routeCost)
	haul: number, -- studs from it to the van's back (routeCost)
	value: number, -- what it pays (its value × its condition)
	weight: number,
	fits: boolean, -- room for it in the van now
	byTruck: boolean, -- it lies by the van already (set down there)
	reserved: boolean, -- a crew player is about to lift it (reserved)
}

-- A piece somebody carries alone that he might take the other end of.
export type Lift = {
	spot: number,
	class: string, -- pair (a two-person lift) | both (a heavy two-hands piece: assist)
	state: string,
	helped: boolean, -- somebody holds its other end already
	crew: boolean, -- its carrier is a player of the move
	cost: number, -- studs to it (routeCost)
	gaveUp: boolean, -- he gave up on it a while (a take that failed)
	weight: number,
	byBack: boolean, -- it is by the van's back already (about to be loaded)
}

export type Doors = { outX: number, outZ: number, inX: number, inZ: number } -- the front door outside, the exit inside

-- A doorway he keeps out of: its middle, half its width, the way through it (a unit vector) and how deep the zone
-- reaches on each side.
export type Doorway = { x: number, z: number, half: number, dirX: number, dirZ: number, depth: number }

export type Input = {
	mode: Mode,
	dead: boolean,
	holding: string?, -- nil, "hand" (a piece in his arms alone: one-hand or two-hands) or "pair" (the other end of yours)
	threat: number?, -- studs to the nearest zombie (nil: none near)
	fleeing: boolean, -- he ran at the last step
	lift: number?, -- pickLift's
	assist: number?, -- pickAssist's
	pick: number?, -- pickItem's
	open: boolean, -- the van's back is shut, somebody comes with a piece and he may open it (Config OpenBack)
	atHouse: boolean, -- the van stands by the house (he carries pieces out only then)
	call: number?, -- 8.3 a crew player's call: the two-person piece they wait at (Moving's Lift, MoveHelper.call)
	ask: number?, -- 8.3 AUTO: the heavy piece he asks a hand for (pickAsk, kept while askKept says "on")
}

local function cfg(): any
	return (Config :: any).MoveHelper
end

local function dist(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

-- ── Who gets him ───────────────────────────────────────────────────────────

function MoveHelperBrain.wanted(players: number): boolean
	local c = cfg()
	return (players == 1 and c.Solo == true) or (players == 2 and c.Duo == true)
end

MoveHelperBrain.Modes = { "auto", "help", "stay", "van" } :: { Mode }

local MODE_NAMES: { [string]: string } = { auto = "AUTO", help = "HELP ME", stay = "WAIT HERE", van = "WAIT AT VAN" }

function MoveHelperBrain.validMode(mode: any): boolean
	return type(mode) == "string" and MODE_NAMES[mode] ~= nil
end

-- 8.3 a command from a player (the Moving remote's ("helper", mode), after the server's rate limit): only his move's
-- crew may give one, only one of the orders, and not the one in force already.
function MoveHelperBrain.order(mode: any, current: Mode, crew: boolean): (Mode?, string?)
	if not crew then
		return nil, "crew"
	elseif not MoveHelperBrain.validMode(mode) then
		return nil, "mode"
	elseif mode == current then
		return nil, "same"
	end
	return mode :: Mode, nil
end

function MoveHelperBrain.modeName(mode: any): string
	return MODE_NAMES[mode] or "AUTO"
end

-- 8.3 the status line under the move's panel (client/MoveHelperHud.luau): the order and what he does.
function MoveHelperBrain.status(mode: any, doing: string?): string
	local name = MoveHelperBrain.modeName(mode)
	if type(doing) ~= "string" or doing == "" then
		return name
	end
	return `{name} · {doing}`
end

-- 8.3 a piece he carries alone on AUTO: one-hand, or two-hands under LightWeight.
function MoveHelperBrain.light(class: string, weight: number): boolean
	return class == "hand" or (class == "both" and weight < cfg().LightWeight)
end

-- ── The way ────────────────────────────────────────────────────────────────

function MoveHelperBrain.routeCost(fromInside: boolean, fx: number, fz: number, toInside: boolean, tx: number, tz: number, doors: Doors): number
	if fromInside == toInside then
		return dist(fx, fz, tx, tz)
	elseif fromInside then
		return dist(fx, fz, doors.inX, doors.inZ) + dist(doors.outX, doors.outZ, tx, tz)
	end
	return dist(fx, fz, doors.outX, doors.outZ) + dist(doors.inX, doors.inZ, tx, tz)
end

-- 7.x farm move: the way through the best of `list`'s doors (`allowed`: the indexes he may use; nil: all), and which.
function MoveHelperBrain.routeVia(fromInside: boolean, fx: number, fz: number, toInside: boolean, tx: number, tz: number, list: { Doors }, allowed: { number }?): (number, number)
	local best, which = math.huge, 1
	for index, doors in list do
		if allowed and not table.find(allowed, index) then
			continue
		end
		local cost = MoveHelperBrain.routeCost(fromInside, fx, fz, toInside, tx, tz, doors)
		if cost < best then
			best, which = cost, index
		end
	end
	return best, which
end

-- Seconds without progress: `moved` studs in the last dt s at `speed` (under a fifth of it is no progress).
function MoveHelperBrain.stuck(stuckFor: number, moved: number, dt: number, speed: number): number
	if moved < speed * dt * 0.2 then
		return stuckFor + dt
	end
	return 0
end

-- A stuck walk: a new path after StuckRepath s, a nudge to the way's next point after StuckSnap s.
function MoveHelperBrain.unstuck(stuckFor: number): string
	local c = cfg()
	if stuckFor >= c.StuckSnap then
		return "nudge"
	elseif stuckFor >= c.StuckRepath then
		return "repath"
	end
	return "walk"
end

-- His place `Follow` studs behind somebody at (x, z) looking along (lookX, lookZ).
function MoveHelperBrain.followSpot(x: number, z: number, lookX: number, lookZ: number): (number, number)
	local d = cfg().Follow
	local len = math.sqrt(lookX * lookX + lookZ * lookZ)
	local fx, fz = 0, 1
	if len > 0.01 then
		fx, fz = lookX / len, lookZ / len
	end
	return x - fx * d, z - fz * d
end

-- A place inside a doorway's zone (along the wall within its half width + Margin, through it within its depth) moved
-- beside it: along the wall to Step past its edge on the side it was on, a little off the wall on its own side.
function MoveHelperBrain.aside(x: number, z: number, door: Doorway): (number, number, boolean)
	local a = cfg().Aside
	local sideX, sideZ = -door.dirZ, door.dirX -- along the wall
	local dx, dz = x - door.x, z - door.z
	local along = dx * sideX + dz * sideZ
	local through = dx * door.dirX + dz * door.dirZ
	if math.abs(along) > door.half + a.Margin or math.abs(through) > door.depth then
		return x, z, false
	end
	local s = if along < 0 then -1 else 1
	local t = if through < 0 then -1 else 1
	local off = math.max(math.abs(through), a.Off) * t
	local out = door.half + a.Step
	return door.x + sideX * out * s + door.dirX * off, door.z + sideZ * out * s + door.dirZ * off, true
end

-- ── Your piece's other end ─────────────────────────────────────────────────

-- In front of the piece's middle (its -Z, away from the carrier) where his root stands: past its far face.
function MoveHelperBrain.farEnd(depth: number): number
	return depth / 2 + cfg().Standoff
end

-- His root's height over the piece's middle: the floor's under the far end (`floorRise`, his stand height on it) when it
-- is within HoldStep of the carrier's floor (`carrierRise`: his stand height on the floor under the carrier's feet):
-- up and down stairs and steps. 8.3 (the owner: "he just jumps weirdly"): a floor farther off is not his (a porch's
-- roof, a ceiling, a door's header the ray found; it was clamped HoldStep over you: a 2.5-stud hop), nor is none: level
-- with you.
function MoveHelperBrain.endRise(floorRise: number, carrierRise: number): number
	if floorRise ~= floorRise or math.abs(floorRise - carrierRise) > cfg().HoldStep then
		return carrierRise
	end
	return floorRise
end

-- 8.1 his top speed holding the far end: the leader's walk and a margin (the far end swings round a turn at PairTurn
-- on top of the walk: HoldExtra). 8.3 keeping up (the owner: "when I run, he just goes behind me with his arms
-- stretched out"): the leader's real speed along the ground (`pace`: holdPace) when it is more than the carry's walk (a
-- lag spike, a slope, anything that moves them faster), at most HoldCap; the carry's own walk is never cut (an admin's
-- boost).
function MoveHelperBrain.holdSpeed(walk: number, pace: number?): number
	local c = cfg()
	local own = math.max(walk, 0) * c.HoldMargin + c.HoldExtra
	local real = pace or 0
	if real ~= real or real <= walk then
		return own
	end
	return math.min(real * c.HoldMargin + c.HoldExtra, math.max(own, c.HoldCap))
end

function MoveHelperBrain.holdTurn(): number
	local c = cfg()
	return math.rad(c.PairTurn) * c.HoldTurn
end

-- (8.3: also the height his root follows (nil: none yet) and his legs: walking, backwards; the leader's root at the last
-- look (fromX, fromZ; nil: none yet), their real speed (pace) and their smoothed velocity (vx, vz))
export type Trail = {
	behind: number,
	ease: number,
	easeSpeed: number,
	height: number?,
	walking: boolean,
	back: boolean,
	fromX: number?,
	fromZ: number?,
	pace: number,
	vx: number,
	vz: number,
}

function MoveHelperBrain.newTrail(): Trail
	return { behind = 0, ease = 0, easeSpeed = 0, height = nil, walking = false, back = false, fromX = nil, fromZ = nil, pace = 0, vx = 0, vz = 0 }
end

-- 8.3 keeping up: one look at the leader's root (`x`, `z`), `dt` s after the last: their real speed along the ground
-- (a rise taken at once, at most HoldCap: a lag spike's jump is a burst, not a teleport; a fall over HoldPace.Fall s:
-- one slow look while they walk on never slows him) and their velocity smoothed over HoldLead.Smooth s (holdLead).
-- `reset` (a new hold, a door's fade: the other world), or a root more than HoldPace.Jump studs off (put there at
-- once): nothing measured, all at rest.
function MoveHelperBrain.holdPace(trail: Trail, x: number, z: number, dt: number, reset: boolean): number
	local c = cfg()
	local fromX, fromZ = trail.fromX, trail.fromZ
	local known = x == x and z == z -- (no root: NaN, never kept)
	trail.fromX = if known then x else nil
	trail.fromZ = if known then z else nil
	if reset or not known or fromX == nil or fromZ == nil or dt ~= dt or dt <= 1e-4 then
		trail.pace, trail.vx, trail.vz = 0, 0, 0
		return 0
	end
	local vx, vz = (x - fromX) / dt, (z - fromZ) / dt
	local speed = math.sqrt(vx * vx + vz * vz)
	if speed * dt > c.HoldPace.Jump then -- (put there at once: a door's fade, a respawn)
		trail.pace, trail.vx, trail.vz = 0, 0, 0
		return 0
	end
	if speed > c.HoldCap then -- (a burst: its way, at HoldCap)
		vx, vz, speed = vx / speed * c.HoldCap, vz / speed * c.HoldCap, c.HoldCap
	end
	if speed >= trail.pace then
		trail.pace = speed
	else
		trail.pace = speed + (trail.pace - speed) * math.exp(-dt / math.max(c.HoldPace.Fall, 0.01))
	end
	local keep = math.exp(-dt / math.max(c.HoldLead.Smooth, 0.01))
	trail.vx = vx + (trail.vx - vx) * keep
	trail.vz = vz + (trail.vz - vz) * keep
	return trail.pace
end

-- 8.3 the seconds Danny is aimed ahead of his place: HoldLead.Base + the leader's ping (round trip, s) × Ping, 0 … Most.
function MoveHelperBrain.leadTime(ping: number?): number
	local lead = cfg().HoldLead
	local p = if ping and ping == ping then math.max(ping, 0) else 0
	return math.clamp(lead.Base + p * lead.Ping, 0, math.max(lead.Most, 0))
end

-- 8.3 how far ahead of his place (x, z studs): the leader's smoothed velocity × `seconds`, HoldLead.Far at most.
function MoveHelperBrain.holdLead(trail: Trail, seconds: number): (number, number)
	local dx, dz = trail.vx * math.max(seconds, 0), trail.vz * math.max(seconds, 0)
	local far = math.sqrt(dx * dx + dz * dz)
	local most = cfg().HoldLead.Far
	if far ~= far then
		return 0, 0
	elseif far > most and far > 0 then
		dx, dz = dx / far * most, dz / far * most
	end
	return dx, dz
end

-- 8.3 his root's height now, toward `height` (where the floor under his end puts it) at HoldClimb studs a second at
-- most: a step or a kerb stepped up or down, never popped. At once on a new hold (none yet) and through a door's fade
-- (`snap`: the piece in the other world).
function MoveHelperBrain.holdClimb(trail: Trail, height: number, dt: number, snap: boolean): number
	local was = trail.height
	if snap or was == nil or height ~= height then
		trail.height = height
		return height
	end
	local most = cfg().HoldClimb * math.max(dt, 0)
	local now = was + math.clamp(height - was, -most, most)
	trail.height = now
	return now
end

-- 8.3 his legs holding the far end (the owner: "walk like me and backwards"): the speed they step at (studs a second:
-- negative backwards, 0 standing) from his root's own velocity in his frame (`forward` along his facing, `side` across
-- it): his whole speed along the ground (a step to the side steps too, never a slide on still legs); walking from
-- HoldLegs.From, standing under HoldLegs.To; backwards once the way is more than Band of it behind him (you walk toward
-- him: he backs away facing you), forwards once more than Band ahead, sideways the way they went (no flicker).
function MoveHelperBrain.holdLegs(trail: Trail, forward: number, side: number, _dt: number): number
	local legs = cfg().HoldLegs
	local speed = math.sqrt(forward * forward + side * side)
	if trail.walking then
		trail.walking = speed >= legs.To
	else
		trail.walking = speed >= legs.From
	end
	if not trail.walking then
		return 0
	end
	local along = forward / speed
	if trail.back and along > legs.Band then
		trail.back = false
	elseif not trail.back and along < -legs.Band then
		trail.back = true
	end
	return if trail.back then -speed else speed
end

function MoveHelperBrain.holdTrack(trail: Trail, gap: number, crossed: boolean, speed: number, dt: number): (number, boolean)
	local c = cfg()
	if crossed then
		trail.behind, trail.ease = 0, 0
		return speed, true
	end
	if trail.ease > 0 then
		trail.ease = math.max(0, trail.ease - dt)
		if trail.ease > 1e-6 then
			return math.max(speed, trail.easeSpeed), false
		end
	end
	if gap <= c.HoldBehind then
		trail.behind = 0
		return speed, false
	end
	trail.behind += dt
	if trail.behind < c.HoldStuck then
		return speed, false
	end
	trail.behind = 0
	trail.ease = c.HoldEase
	trail.easeSpeed = gap / math.max(c.HoldEase, 0.05)
	return math.max(speed, trail.easeSpeed), false
end

-- ── What next ──────────────────────────────────────────────────────────────

function MoveHelperBrain.reserved(playerCost: number?, myCost: number): boolean
	return playerCost ~= nil and playerCost <= cfg().Reserve and playerCost < myCost
end

-- Its value a second of the trip there and back to the van (the carry's walk on the way back; TripBase studs on top so
-- a near cheap piece does not always win).
function MoveHelperBrain.worth(c: Candidate): number
	local mode = if c.class == "both" then "both" elseif c.class == "pair" then "pair" else "hand" -- (8.3: two carry it)
	local factor = math.max(Rules.speedFactor(mode, c.weight), 0.1)
	return c.value / (cfg().TripBase + c.cost + c.haul / factor)
end

function MoveHelperBrain.pickItem(list: { Candidate }, backOpen: boolean): (number?, boolean)
	local best: Candidate? = nil
	local bestWorth = -math.huge
	local left = false
	for _, c in list do
		if not MoveHelperBrain.light(c.class, c.weight) or c.broken or (c.state ~= "home" and c.state ~= "ground") or c.reserved then
			continue -- (8.3: a heavy two-hands piece is one he asks a hand for)
		end
		if c.byTruck and not backOpen then
			continue -- (it waits by the van for the back to open)
		end
		left = true
		if not c.fits then
			continue
		end
		local w = MoveHelperBrain.worth(c)
		local b = best
		if b == nil or (c.star and not b.star) or (c.star == b.star and (w > bestWorth + 1e-9 or (math.abs(w - bestWorth) <= 1e-9 and c.cost < b.cost))) then
			best, bestWorth = c, w
		end
	end
	if best then
		return best.spot, false
	end
	return nil, left
end

-- 8.3 AUTO: the heavy piece nobody handles that he asks a hand for (★ first, then its worth for a trip of two).
function MoveHelperBrain.pickAsk(list: { Candidate }): number?
	local best: Candidate? = nil
	local bestWorth = -math.huge
	for _, c in list do
		if MoveHelperBrain.light(c.class, c.weight) or (c.class ~= "pair" and c.class ~= "both") or c.broken
			or (c.state ~= "home" and c.state ~= "ground") or c.reserved or not c.fits or c.cost > cfg().AskFar then
			continue
		end
		local w = MoveHelperBrain.worth(c)
		local b = best
		if b == nil or (c.star and not b.star) or (c.star == b.star and (w > bestWorth + 1e-9 or (math.abs(w - bestWorth) <= 1e-9 and c.cost < b.cost))) then
			best, bestWorth = c, w
		end
	end
	return if best then best.spot else nil
end

-- 8.3 his ask for a hand (`asked`: he is there and said so, `waited` s ago; `fits`: it still fits the van; `free`: home
-- or on the ground, nobody holds it).
function MoveHelperBrain.askKept(asked: boolean, waited: number, fits: boolean, free: boolean): string
	if not free or not fits then
		return "gone"
	elseif asked and waited >= cfg().AskWait then
		return "timeout"
	end
	return "on"
end

-- 8.3 your call: at the other end of your piece (within CallReady studs of his place there), or near it and blocked
-- (a wall, the piece itself: within CallClose studs, no progress for CallStuck s; the hold walks him the rest).
function MoveHelperBrain.inPlace(gap: number, stuckFor: number): boolean
	local c = cfg()
	return gap <= c.CallReady or (gap <= c.CallClose and stuckFor >= c.CallStuck)
end

export type Approach = { best: number, idle: number }

function MoveHelperBrain.newApproach(): Approach
	return { best = math.huge, idle = 0 }
end

-- 8.3 one look at his walk to your call (`gap`: studs to his place on foot): true when he came no closer than CallGain
-- studs for CallBlink s (his path fails, a wall: the last resort, a fade-over).
function MoveHelperBrain.approach(a: Approach, gap: number, dt: number): boolean
	local c = cfg()
	if gap < a.best - c.CallGain then
		a.best, a.idle = gap, 0
		return false
	end
	a.idle += dt
	return a.idle >= c.CallBlink
end

-- 8.3 does your call go on: you within the Lift's `reach` of the piece (and CallLeave more) and, once he is in place,
-- your lift within CallIdle s.
function MoveHelperBrain.callKept(fromPiece: number, reach: number, ready: boolean, readyFor: number): string
	local c = cfg()
	if fromPiece > reach + c.CallLeave then
		return "away"
	elseif ready and readyFor >= c.CallIdle then
		return "idle"
	end
	return "on"
end

function MoveHelperBrain.pickLift(list: { Lift }): number?
	local best: Lift? = nil
	for _, l in list do
		if l.class ~= "pair" or l.state ~= "carried" or l.helped or not l.crew or l.gaveUp or l.cost > cfg().HelpFar then
			continue
		end
		local b = best
		if b == nil or l.cost < b.cost then
			best = l
		end
	end
	return if best then best.spot else nil
end

function MoveHelperBrain.pickAssist(list: { Lift }): number?
	local c = cfg()
	local best: Lift? = nil
	for _, l in list do
		if l.class ~= "both" or l.state ~= "carried" or l.helped or not l.crew or l.gaveUp or l.byBack or l.weight < c.AssistWeight or l.cost > c.AssistFar then
			continue
		end
		local b = best
		if b == nil or l.cost < b.cost then
			best = l
		end
	end
	return if best then best.spot else nil
end

function MoveHelperBrain.shouldFlee(threat: number?, fleeing: boolean, holding: string?): boolean
	if holding == "pair" or threat == nil then
		return false
	end
	local c = cfg()
	return threat <= c.FleeRange or (fleeing and threat <= c.SafeRange)
end

function MoveHelperBrain.fleeTo(x: number, z: number, zx: number, zz: number): (number, number)
	local dx, dz = x - zx, z - zz
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.01 then
		dx, dz, len = 1, 0, 1
	end
	local step = cfg().FleeStep
	return x + dx / len * step, z + dz / len * step
end

-- The priorities, in order: down; the other end of your piece (zombies or not: you lead); running from a zombie; 8.3
-- your call (a two-person Lift: on every order; his own piece set down or loaded first); your two-person piece dragged
-- alone (every order); the piece in his arms to the van; the van's back for whoever comes with a piece (not on WAIT
-- HERE); WAIT HERE; WAIT AT VAN; the other side of your heavy two-hands piece; HELP ME (behind you); on AUTO his ask for
-- a hand with a heavy piece, then the next light piece, while the van stands by the house; waiting at the van.
function MoveHelperBrain.decide(i: Input): (string, number?)
	if i.dead then
		return "down", nil
	elseif i.holding == "pair" then
		return "hold", nil
	elseif MoveHelperBrain.shouldFlee(i.threat, i.fleeing, i.holding) then
		return "flee", nil
	elseif i.call ~= nil then
		return "come", i.call
	elseif i.lift ~= nil then
		return "help", i.lift
	elseif i.holding == "hand" then
		return "deliver", nil
	elseif i.open and i.mode ~= "stay" then
		return "open", nil
	elseif i.mode == "stay" then
		return "stay", nil
	elseif i.mode == "van" then
		return "wait", nil
	elseif i.assist ~= nil then
		return "assist", i.assist
	elseif i.mode == "help" then
		return "follow", nil
	elseif i.ask ~= nil and i.atHouse then
		return "ask", i.ask
	elseif i.pick ~= nil and i.atHouse then
		return "fetch", i.pick
	end
	return "wait", nil
end

-- At the van's back with a piece: in it goes (open, the van standing); shut: he opens it himself when he may, else he
-- waits WaitShut s for you to open it, then sets the piece down beside the van.
function MoveHelperBrain.atTruck(open: boolean, still: boolean, waited: number, mayOpen: boolean?): string
	if open and still then
		return "load"
	elseif not open and still and mayOpen then
		return "open"
	elseif waited < cfg().WaitShut then
		return "wait"
	end
	return "drop"
end

-- `carry`: the carry's mode with a piece alone ("hand" | "both"), nil empty-handed.
function MoveHelperBrain.speed(walk: number, action: string, carry: string?, weight: number): number
	local c = cfg()
	if action == "flee" then
		return walk * c.Flee
	elseif action == "help" or action == "assist" or action == "come" then
		return walk * c.Sprint
	elseif action == "hold" then
		return Rules.carrySpeed(walk, "pair", weight) * c.KeepUp
	end
	local factor = if carry then Rules.speedFactor(carry, weight) else 1
	return walk * c.Speed * factor
end

-- 8.1 SANDBOX: Danny's training (server/Upgrades.luau keeps the level in the owner's player attribute): his walk x this.
function MoveHelperBrain.trained(owner: any): number
	local ok, level = pcall(function(): any
		return owner:GetAttribute(Config.SandboxUpgrades.Danny)
	end)
	return UpgradeRules.dannySpeed(if ok then level else nil)
end

-- ── Words ──────────────────────────────────────────────────────────────────

local DOING: { [string]: string } = {
	down = "Down: back at the van soon",
	hold = "Carrying the %s with you",
	flee = "Running from the zombies",
	help = "Coming to lift the %s",
	assist = "Taking the other side of the %s",
	deliver = "Carrying the %s to the van",
	open = "Opening the van's back",
	follow = "Right behind you",
	fetch = "Going for the %s",
	wait = "Waiting at the van",
	come = "Coming to lift the %s with you", -- 8.3 your call
	ready = "At the %s: on three!",
	ask = "Needs a hand with the %s",
	stay = "Waiting here",
}

function MoveHelperBrain.doing(action: string, name: string?, full: boolean?): string
	if action == "wait" and full then
		return "Waiting: the van is full"
	end
	local text = DOING[action] or "Waiting at the van"
	if string.find(text, "%s", 1, true) then
		return string.format(text, name or "piece")
	end
	return text
end

MoveHelperBrain.Lines = {
	hello = "Danny from the depot. Got your back!",
	help = "Hold it, I'll get the other end!",
	assist = "Here, let me take the other side.",
	lift = "Got the other end!",
	three = "On three... lift!",
	door = "Watch the doorframe!",
	van = "That's going in the van.",
	loaded = "That's going in the van.",
	full = "Van's full, boss - drive it to the Wall?",
	shut = "Open the back, boss!",
	open = "I'll get the doors!",
	mine = "All yours, boss.",
	flee = "Zombies! I'm staying out of this one!",
	down = "Ugh... I'll be back!",
	back = "Back on my feet!",
	autoMode = "On it! Small stuff's mine, I'll shout for the big ones.", -- 8.3 the orders
	helpMode = "Right behind you.",
	stayMode = "I'll wait right here.",
	vanMode = "Waiting at the van.",
	ask = "This one's too heavy for me alone, give me a hand!", -- 8.3 AUTO's ask
	askOff = "No takers? I'll grab the small stuff.",
	callOff = "No problem, boss.", -- 8.3 a call you called off
} :: { [string]: string }

-- 8.0 SANDBOX (Config.Sandbox.On): the lines that would name the city's depot or the Wall.
MoveHelperBrain.SandboxLines = {
	hello = "Danny from ZDC. Got your back!",
	full = "Van's full, boss - drive it home?",
} :: { [string]: string }

function MoveHelperBrain.line(key: string, sandbox: boolean?): string?
	return (if sandbox then MoveHelperBrain.SandboxLines[key] else nil) or MoveHelperBrain.Lines[key]
end

return MoveHelperBrain
