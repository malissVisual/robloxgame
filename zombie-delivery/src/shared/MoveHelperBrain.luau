--!strict
-- 7.0, the depot's helper ("Danny from the depot", server/MoveHelper.luau; the owner: solo play is allowed with an AI
-- helper, design/rework/NAVRH.md): his decisions, pure (no Roblox at its top level: tests/movehelper_test.luau runs it
-- in the standalone Luau). Positions are plain numbers (X and Z along the ground); "inside" is a move's interior, its
-- own world far from the street with the front door between the two. The numbers are Config.MoveHelper's, the carry's
-- MovingRules'.
-- 7.x Danny, a partner (the owner: "he helps weirdly, only some things, and mainly we don't carry anything together"):
-- a clear priority list each step (decide): his end of your piece; zombies (never while he holds your piece's other
-- end); your two-person lift (8.3: your call, he walks over); the piece in his arms to the van; the van's back for
-- whoever comes with a piece; the next piece of his list.
--
-- 8.3 Danny for hire (the owner: "make it so I click on the helper, but I have to PAY for him when I want help. It
-- doesn't work well when he does 4 things. Instead: you go into the house, click on something, and that assigns it to
-- him, and the rest you carry yourself"; and "he must sit in my car with me"): at a move's start he waits by the van,
-- not working; a crew player hires him for that move (hireCheck, hirePrice: Config.MoveHelper.Hire, the money's
-- PlayerData.spend on the server); then the crew clicks pieces into his list (assignCheck: a click again takes one
-- back; Config.MoveHelper.Queue at most) and he carries them in order (nextQueued): a light one to the van alone, a
-- two-person one he waits at for you ("needs"); everything else is yours. A two-person Lift calls him while he is hired
-- (decide's "come"; inPlace; approach: a fade-over only as the last resort). When you sit at the van's wheel he walks
-- to its passenger door and rides with you (pickSeat, "ride", "seat"), out again when you get out (getOut). 8.5 his
-- way to that door goes round the van, never through it (roundVan), and he fades into the seat only when the van is
-- far off or out of his reach a long while (rideBlink). 8.5.1 (the owner: "Danny STILL goes through it"): every way of
-- his outside keeps off the van's outline (crossesVan: round it with roundVan), and he is never left inside it
-- (outOfVan).
--
--   MoveHelperBrain.wanted(players, hired)     does a crew of this many players have him (Solo, Duo; a hired Danny stays
--                                              with any crew of one or more)
--   MoveHelperBrain.hirePrice(pieces)          8.3 the hire for a move of a house with this many pieces: Hire.Base +
--                                              Hire.PerPiece each, to Hire.Round dollars, Hire.Min … Hire.Max
--   MoveHelperBrain.hireCheck(crew, hired, money, price)   8.3 a HIRE checked: (true, nil) or (false, why: "crew" not
--                                              the move's crew, "hired" he works for this move already, "money" not enough)
--   MoveHelperBrain.assignCheck(a)             8.3 a click on a piece checked (an Assign: crew, hired, mine, state, held,
--                                              his, queued, count, near): "add" | "remove" | why: "crew" | "hire" |
--                                              "piece" (not this move's) | "far" | "van" (in the van) | "gone" (home
--                                              already, lost) | "held" (somebody holds it) | "his" (in his arms) | "full";
--                                              8.5 "clipboard": hired, but the player's clipboard is not out (orders
--                                              mode: shared/ClipboardRules.luau; a click on his list's piece too)
--   MoveHelperBrain.keepQueued(state, held)    8.3 is a piece of his list still his to carry (home or on the ground,
--                                              nobody holding it)?
--   MoveHelperBrain.nextQueued(list)           8.3 the piece of his list he goes for now (Queued: in his list's order, the
--                                              first that still fits the van; a two-person one too: he waits at it for
--                                              you): (spot?, pair, full: some left, none fits)
--   MoveHelperBrain.queueText(count)           8.3 "Nothing to carry" | "1 piece to carry" | "3 pieces to carry"
--   MoveHelperBrain.status(hired, price, count, doing)   8.3 his status in a line: "For hire · $170 this move", or "2
--                                              pieces to carry · Carrying the Lamp to the van"
--   MoveHelperBrain.money(n)                   8.3 "$1,234" (shared/UpgradeRules.luau's: the hire's words)
--   MoveHelperBrain.markText(index, needs)     8.3 the marker over a piece of his list: "🧑‍🔧 Danny · 2", "🙋 Danny needs you"
--   MoveHelperBrain.pickSeat(taken)            8.3 the van's passenger seat he takes: the first one nobody sits in (nil:
--                                              all taken, he follows the van on foot)
--   MoveHelperBrain.getOut(driving, still, carOk)   8.3 seated in the van: out when nobody drives it and it stands, or at
--                                              once when it is wrecked or gone
--   MoveHelperBrain.roundVan(x, z, gx, gz, halfX, halfZ, reach, margin?)   8.5 his way to the van's door in the van's own frame
--                                              (its footprint |x| <= halfX, |z| <= halfZ): the next point (x, z) and the
--                                              way's length: straight when it keeps RideMargin studs off the footprint,
--                                              else round its corners (RideMargin out, the shorter way round; a corner
--                                              within `reach` passed); from within the margin straight out first
--                                              (8.5.1 `margin`: that many studs off instead of RideMargin)
--   MoveHelperBrain.crossesVan(x, z, gx, gz, halfX, halfZ, pad)   8.5.1 does the way from (x, z) to (gx, gz) cross the
--                                              van's footprint grown by `pad` (in its own frame)? (his outline guard:
--                                              any way of his outside, RideHug)
--   MoveHelperBrain.outOfVan(x, z, halfX, halfZ, pad, sideways)   8.5.1 (x, z) just out of the footprint grown by
--                                              `pad`, through its nearer side (`sideways`: its left or right only, out
--                                              of the way of a van driving along its length); a point outside as it is
--   MoveHelperBrain.rideBlink(a, gap, dt)      8.5 his walk to the van to ride: true for the last resort (a fade into
--                                              the seat): RideFar studs or more to go, or no closer by CallGain studs
--                                              for RideBlink s
--   MoveHelperBrain.inPlace(gap, stuckFor)     8.3 at the other end of your call: within CallReady studs of his place,
--                                              or within CallClose and blocked CallStuck s (the hold walks him the rest)
--   MoveHelperBrain.newApproach() / approach(a, gap, dt)   8.3 his walk to your call (or to your piece dragged alone):
--                                              true once he has come no closer than CallGain studs for CallBlink s (the
--                                              last resort: a fade-over; 8.5 his walk to the van to ride: rideBlink)
--   MoveHelperBrain.callKept(fromPiece, reach, ready, readyFor)   8.3 does your call go on: "on", "away" (you walked
--                                              CallLeave studs past the Lift's reach), "idle" (he was in place CallIdle s
--                                              and you never lifted)
--   MoveHelperBrain.routeCost(...)             studs on foot from one point to another, through the front door when
--                                              they are in different worlds
--   MoveHelperBrain.routeVia(..., list, allowed?)   7.x farm move: the same through the best of several doors (a farm's
--                                              front door, its barn doors; only the `allowed` indexes): (studs, index)
--   MoveHelperBrain.pickLift(list)             the crew's two-person lift he comes to (hired): a pair piece a crew
--                                              player drags alone, the nearest within HelpFar, not one he gave up on
--   MoveHelperBrain.shouldFlee(threat, fleeing, holding)   a zombie near: run (never while holding the other end of
--                                              your piece: the player leads); on until none is within SafeRange
--   MoveHelperBrain.fleeTo(x, z, zx, zz)       where he runs: FleeStep studs straight away from the zombie
--   MoveHelperBrain.decide(input)              what he does now and the piece's spot: "down" | "hold" | "seat" (8.3
--                                              in the van) | "flee" | "come" (your call) | "help" | "deliver" | "ride"
--                                              (8.3 to the van's passenger door) | "open" | "needs" (8.3 at a two-person
--                                              piece of his list) | "fetch" | "wait"
--   MoveHelperBrain.atTruck(open, still, waited, mayOpen)   a piece in his arms at the van's back: "load" | "open" |
--                                              "wait" | "drop"
--   MoveHelperBrain.speed(walk, action, carry, weight)   his walk now: × Speed (× the carry's alone: "hand" | "both"),
--                                              Sprint × to a lift, to your call and to the van to ride, Flee × running away
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
--   MoveHelperBrain.doing(action, name, full)  what he does, in words (client/MoveHelperHud.luau's line)
--   MoveHelperBrain.Lines                      what he says (a speech bubble over his head; plain text)
--   MoveHelperBrain.line(key, sandbox)         his line for `key` (8.0 SANDBOX: SandboxLines' where the test world has
--                                              no Wall and no depot)

local Config = require(script.Parent.Config)
local Rules = require(script.Parent.MovingRules)
local UpgradeRules = require(script.Parent.UpgradeRules) -- 8.1: Danny's training; 8.3: the money's words

local MoveHelperBrain = {}

MoveHelperBrain.money = UpgradeRules.money

-- A piece somebody carries alone that he might take the other end of.
export type Lift = {
	spot: number,
	class: string, -- pair (a two-person lift)
	state: string,
	helped: boolean, -- somebody holds its other end already
	crew: boolean, -- its carrier is a player of the move
	cost: number, -- studs to it (routeCost)
	gaveUp: boolean, -- he gave up on it a while (a take that failed)
}

-- 8.3 a piece of his list, in its order: its class, and whether it still fits the van (MovingRules.canLoad).
export type Queued = { spot: number, class: string, fits: boolean }

-- 8.3 a click on a piece, as the server sees it (assignCheck).
export type Assign = {
	crew: boolean, -- the player is of the move's crew
	hired: boolean, -- Danny works for this move
	mine: boolean, -- the piece is this move's (its model is the move's own)
	state: string, -- the piece's: home | carried | ground | truck | delivered | lost
	held: boolean, -- somebody holds it (a player, or Danny)
	his: boolean, -- Danny holds it
	queued: boolean, -- it is on his list already
	count: number, -- the pieces on his list
	near: boolean, -- the player is near enough to it to see it (ClickReach)
	clipboard: boolean, -- 8.5 the player's clipboard is out (orders mode: the character attribute ClipboardHeld)
}

export type Doors = { outX: number, outZ: number, inX: number, inZ: number } -- the front door outside, the exit inside

-- A doorway he keeps out of: its middle, half its width, the way through it (a unit vector) and how deep the zone
-- reaches on each side.
export type Doorway = { x: number, z: number, half: number, dirX: number, dirZ: number, depth: number }

export type Input = {
	hired: boolean, -- 8.3 somebody of the crew hired him for this move
	dead: boolean,
	holding: string?, -- nil, "hand" (a piece in his arms alone: one-hand or two-hands) or "pair" (the other end of yours)
	seated: boolean, -- 8.3 he sits in the van (a passenger)
	ride: boolean, -- 8.3 somebody of the crew sits at the van's wheel: he gets in
	threat: number?, -- studs to the nearest zombie (nil: none near)
	fleeing: boolean, -- he ran at the last step
	lift: number?, -- pickLift's
	queued: number?, -- 8.3 nextQueued's: the piece of his list he goes for
	pair: boolean, -- 8.3 … a two-person one (he waits at it for you)
	open: boolean, -- the van's back is shut, somebody comes with a piece and he may open it (Config OpenBack)
	atHouse: boolean, -- the van stands by the house (he carries pieces out only then)
	call: number?, -- 8.3 a crew player's call: the two-person piece they wait at (Moving's Lift, MoveHelper.call)
}

local function cfg(): any
	return (Config :: any).MoveHelper
end

local function dist(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- ── Who has him ────────────────────────────────────────────────────────────

function MoveHelperBrain.wanted(players: number, hired: boolean?): boolean
	local c = cfg()
	if hired then
		return players >= 1 -- (8.3 paid for the move: he stays whoever joins)
	end
	return (players == 1 and c.Solo == true) or (players == 2 and c.Duo == true)
end

-- ── 8.3 the hire ───────────────────────────────────────────────────────────

function MoveHelperBrain.hirePrice(pieces: any): number
	local h = cfg().Hire
	local n = if finite(pieces) then math.max(0, math.floor(pieces)) else 0
	local raw = h.Base + h.PerPiece * n
	local step = math.max(1, h.Round)
	return math.clamp(math.floor(raw / step + 0.5) * step, h.Min, h.Max)
end

function MoveHelperBrain.hireCheck(crew: boolean, hired: boolean, money: any, price: number): (boolean, string?)
	if not crew then
		return false, "crew"
	elseif hired then
		return false, "hired"
	elseif not finite(money) or money < price then
		return false, "money"
	end
	return true, nil
end

-- ── 8.3 his list ───────────────────────────────────────────────────────────

function MoveHelperBrain.keepQueued(state: string, held: boolean): boolean
	return not held and (state == "home" or state == "ground")
end

function MoveHelperBrain.assignCheck(a: Assign): string
	if not a.crew then
		return "crew"
	elseif not a.mine then
		return "piece"
	elseif not a.hired then
		return "hire"
	elseif not a.clipboard then
		return "clipboard" -- (8.5: orders only with the clipboard out: never a piece given by a stray click)
	elseif a.queued then
		return "remove" -- (a click on a piece of his list takes it back, wherever it is now)
	elseif not a.near then
		return "far"
	elseif a.his then
		return "his"
	elseif a.state == "truck" then
		return "van"
	elseif a.state ~= "home" and a.state ~= "ground" and a.state ~= "carried" then
		return "gone"
	elseif a.held or a.state == "carried" then
		return "held"
	elseif a.count >= cfg().Queue then
		return "full"
	end
	return "add"
end

function MoveHelperBrain.nextQueued(list: { Queued }): (number?, boolean, boolean)
	for _, q in list do
		if q.fits then
			return q.spot, q.class == "pair", false
		end
	end
	return nil, false, #list > 0
end

function MoveHelperBrain.queueText(count: any): string
	local n = if finite(count) then math.max(0, math.floor(count)) else 0
	if n == 0 then
		return "Nothing to carry"
	end
	return if n == 1 then "1 piece to carry" else `{n} pieces to carry`
end

function MoveHelperBrain.status(hired: boolean, price: any, count: any, doing: string?): string
	if not hired then
		return `For hire · {UpgradeRules.money(price)} this move`
	end
	local list = MoveHelperBrain.queueText(count)
	if type(doing) ~= "string" or doing == "" then
		return list
	end
	return `{list} · {doing}`
end

function MoveHelperBrain.markText(index: number, needs: boolean?): string
	local name = cfg().Name
	if needs then
		return `🙋 {name} needs you`
	end
	return `🧑‍🔧 {name} · {index}`
end

-- ── 8.3 riding with you ────────────────────────────────────────────────────

function MoveHelperBrain.pickSeat(taken: { boolean }): number?
	for index, busy in taken do
		if not busy then
			return index
		end
	end
	return nil
end

function MoveHelperBrain.getOut(driving: boolean, still: boolean, carOk: boolean): boolean
	return not carOk or (not driving and still)
end

-- 8.5 (the owner: "when I got into the car, Danny got a bit stuck under the car and then appeared in the car
-- already"): does the way from (ax, az) to (bx, bz) cross the inside of the box |x| < hx, |z| < hz (its edges are
-- outside)? The segment clipped to the box (Liang-Barsky): crossing when a piece of it is left.
local function clip(p: number, q: number, t0: number, t1: number): (number, number)
	if math.abs(p) < 1e-9 then
		return if q > 0 then t0 else 1, if q > 0 then t1 else 0 -- (parallel: all in that side's slab, or none)
	end
	local t = q / p
	if p < 0 then
		return math.max(t0, t), t1
	end
	return t0, math.min(t1, t)
end

local function crosses(ax: number, az: number, bx: number, bz: number, hx: number, hz: number): boolean
	local dx, dz = bx - ax, bz - az
	local t0, t1 = clip(-dx, ax + hx, 0, 1)
	t0, t1 = clip(dx, hx - ax, t0, t1)
	t0, t1 = clip(-dz, az + hz, t0, t1)
	t0, t1 = clip(dz, hz - az, t0, t1)
	return (t1 - t0) * math.sqrt(dx * dx + dz * dz) > 1e-4
end

-- 8.5 his way to the van's door (`gx`, `gz`), never through the van: in the van's own frame its footprint is |x| <=
-- halfX, |z| <= halfZ; he keeps RideMargin studs off it. The shortest way among the four corners of the footprint
-- grown by the margin (a hair farther out: the way along a side stays outside): (x, z) of the next point and the way's
-- length. A first corner within `reach` studs: the point after it (he walks on round it, no stop there). Within the
-- margin already (a nudge, the van parked next to him): straight out of its nearer side first. 8.5.1 `margin`: that many
-- studs off the footprint instead (the outline guard's way to a goal nearer the van than RideMargin).
function MoveHelperBrain.roundVan(x: number, z: number, gx: number, gz: number, halfX: number, halfZ: number, reach: number, margin: number?): (number, number, number)
	local m = margin or cfg().RideMargin
	local hx, hz = halfX + m, halfZ + m
	local edge = 0.05
	local before = 0
	local inX, inZ = hx - math.abs(x), hz - math.abs(z)
	if inX > 0 and inZ > 0 then
		local ox, oz = x, z
		if inX <= inZ then
			ox = (if x < 0 then -1 else 1) * (hx + edge)
		else
			oz = (if z < 0 then -1 else 1) * (hz + edge)
		end
		before = dist(x, z, ox, oz)
		if before > reach then
			local _, _, rest = MoveHelperBrain.roundVan(ox, oz, gx, gz, halfX, halfZ, reach, margin)
			return ox, oz, before + rest
		end
		x, z = ox, oz -- (a step from its edge: on from there)
	end
	local ex, ez = hx + edge, hz + edge
	local xs = { x, ex, ex, -ex, -ex, gx }
	local zs = { z, ez, -ez, -ez, ez, gz }
	local best = { 0, math.huge, math.huge, math.huge, math.huge, math.huge }
	local from = { 0, 0, 0, 0, 0, 0 }
	local done = { false, false, false, false, false, false }
	for _ = 1, 6 do
		local u, bu = 0, math.huge
		for i = 1, 6 do
			if not done[i] and best[i] < bu then
				u, bu = i, best[i]
			end
		end
		if u == 0 or u == 6 then
			break
		end
		done[u] = true
		for v = 2, 6 do
			if not done[v] and not crosses(xs[u], zs[u], xs[v], zs[v], hx, hz) then
				local d = bu + dist(xs[u], zs[u], xs[v], zs[v])
				if d < best[v] then
					best[v], from[v] = d, u
				end
			end
		end
	end
	if best[6] == math.huge then
		return gx, gz, before + dist(x, z, gx, gz) -- (the door's spot itself within the margin: straight to it)
	end
	local first, second = 6, 6
	while from[first] ~= 1 do
		second = first
		first = from[first]
	end
	if first ~= 6 and dist(x, z, xs[first], zs[first]) <= reach then
		first = second
	end
	return xs[first], zs[first], before + best[6]
end

-- 8.5.1 (the owner: "Danny STILL goes through it"): his outline guard, for any way of his outside (server/
-- MoveHelper.luau's go): does the way cross the footprint grown by `pad`?
function MoveHelperBrain.crossesVan(x: number, z: number, gx: number, gz: number, halfX: number, halfZ: number, pad: number): boolean
	return crosses(x, z, gx, gz, halfX + pad, halfZ + pad)
end

-- 8.5.1: (x, z) moved just out of the footprint grown by `pad` (a hair past it), through its nearer side, or its left
-- or right side (`sideways`: a van driving along its length goes on past him); a point outside it as it is.
function MoveHelperBrain.outOfVan(x: number, z: number, halfX: number, halfZ: number, pad: number, sideways: boolean?): (number, number)
	local hx, hz = halfX + pad, halfZ + pad
	local inX, inZ = hx - math.abs(x), hz - math.abs(z)
	if inX <= 0 or inZ <= 0 then
		return x, z
	end
	if sideways or inX <= inZ then
		return (if x < 0 then -1 else 1) * (hx + 0.05), z
	end
	return x, (if z < 0 then -1 else 1) * (hz + 0.05)
end

-- 8.5 one look at his walk to the van to ride (`gap`: studs on foot to his spot at its door): true for the last
-- resort, a fade into the seat: the van RideFar studs or more away (driven off without him), or no closer by CallGain
-- studs for RideBlink s (his way blocked, the van keeps going).
function MoveHelperBrain.rideBlink(a: Approach, gap: number, dt: number): boolean
	local c = cfg()
	if gap >= c.RideFar then
		return true
	elseif gap < a.best - c.CallGain then
		a.best, a.idle = gap, 0
		return false
	end
	a.idle += dt
	return a.idle >= c.RideBlink
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

-- ── 8.3 your call ──────────────────────────────────────────────────────────

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

-- ── What next ──────────────────────────────────────────────────────────────

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

-- The priorities, in order: down; the other end of your piece (zombies or not: you lead); 8.3 in the van's seat (he
-- rides; out when you get out); running from a zombie; hired: your call (a two-person Lift; his own piece set down or
-- loaded first), your two-person piece dragged alone; the piece in his arms to the van; hired: into the van when you
-- sit at its wheel; not hired: waiting by the van (for hire); the van's back for whoever comes with a piece; the next
-- piece of his list (a two-person one: he waits at it for you) while the van stands by the house; waiting at the van.
function MoveHelperBrain.decide(i: Input): (string, number?)
	if i.dead then
		return "down", nil
	elseif i.holding == "pair" then
		return "hold", nil
	elseif i.seated then
		return "seat", nil
	elseif MoveHelperBrain.shouldFlee(i.threat, i.fleeing, i.holding) then
		return "flee", nil
	elseif i.hired and i.call ~= nil then
		return "come", i.call
	elseif i.hired and i.lift ~= nil then
		return "help", i.lift
	elseif i.holding == "hand" then
		return "deliver", nil
	elseif i.hired and i.ride then
		return "ride", nil
	elseif not i.hired then
		return "wait", nil
	elseif i.open then
		return "open", nil
	elseif i.queued ~= nil and i.atHouse then
		return if i.pair then "needs" else "fetch", i.queued
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
	elseif action == "help" or action == "come" or action == "ride" then
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
	deliver = "Carrying the %s to the van",
	open = "Opening the van's back",
	fetch = "Going for the %s",
	wait = "Waiting at the van",
	come = "Coming to lift the %s with you", -- 8.3 your call
	ready = "At the %s: on three!",
	needs = "Waiting for you at the %s", -- 8.3 a two-person piece of his list
	offer = "Waiting by the van for hire",
	ride = "Getting in the van",
	seat = "Riding in the van",
	alight = "Getting out of the van", -- 8.5 (his way out at its door)
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
	hello = "Danny from the depot. Need a hand? Hire me!",
	hired = "You got it, boss! Show me what to carry.", -- 8.3 the hire
	queued = "Got it, I'll take that one.",
	cleared = "Okay, my list is empty.",
	empty = "All done. Anything else, boss?",
	help = "Hold it, I'll get the other end!",
	lift = "Got the other end!",
	three = "On three... lift!",
	door = "Watch the doorframe!",
	van = "That's going in the van.",
	loaded = "That's going in the van.",
	full = "Van's full, boss - drive it to the Wall?",
	shut = "Open the back, boss!",
	open = "I'll get the doors!",
	mine = "All yours, boss.", -- 8.3 a piece of his list you picked up yourself
	flee = "Zombies! I'm staying out of this one!",
	down = "Ugh... I'll be back!",
	back = "Back on my feet!",
	ask = "This one's too heavy for me alone, give me a hand!", -- 8.3 a two-person piece of his list
	callOff = "No problem, boss.", -- 8.3 a call you called off
	ride = "Wait up, I'm riding with you!", -- 8.3 riding with you
	out = "Back to work!",
} :: { [string]: string }

-- 8.0 SANDBOX (Config.Sandbox.On): the lines that would name the city's depot or the Wall.
MoveHelperBrain.SandboxLines = {
	hello = "Danny from ZDC. Need a hand? Hire me!",
	full = "Van's full, boss - drive it home?",
} :: { [string]: string }

function MoveHelperBrain.line(key: string, sandbox: boolean?): string?
	return (if sandbox then MoveHelperBrain.SandboxLines[key] else nil) or MoveHelperBrain.Lines[key]
end

return MoveHelperBrain
