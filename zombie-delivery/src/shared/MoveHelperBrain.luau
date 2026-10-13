--!strict
-- 7.0, the depot's helper ("Danny from the depot", server/MoveHelper.luau; the owner: solo play is allowed with an AI
-- helper, design/rework/NAVRH.md): his decisions, pure (no Roblox at its top level: tests/movehelper_test.luau runs it
-- in the standalone Luau). Positions are plain numbers (X and Z along the ground); "inside" is a move's interior, its
-- own world far from the street with the front door between the two. The numbers are Config.MoveHelper's, the carry's
-- MovingRules'.
-- 7.x Danny, a partner (the owner: "he helps weirdly, only some things, and mainly we don't carry anything together"):
-- a clear priority list each step (decide): his end of your piece; zombies (never while he holds your piece's other
-- end); your two-person lift (he sprints over, or fades over from far); the piece in his arms to the van; the van's back
-- for whoever comes with a piece; the order; the other side of a heavy two-hands piece you carry alone; the next piece
-- (★ first, then the most value a second of the trip, one-hand and two-hands ones; never one you are about to lift).
--
--   MoveHelperBrain.wanted(players)            does a crew of this many players get him (Solo, Duo)?
--   MoveHelperBrain.validMode(mode)            "help" (Help me) | "carry" (Carry small stuff, the default) | "wait"
--                                              (Wait at the van)
--   MoveHelperBrain.routeCost(...)             studs on foot from one point to another, through the front door when
--                                              they are in different worlds
--   MoveHelperBrain.routeVia(..., list, allowed?)   7.x farm move: the same through the best of several doors (a farm's
--                                              front door, its barn doors; only the `allowed` indexes): (studs, index)
--   MoveHelperBrain.reserved(playerCost, myCost)   a piece a crew player with free hands is about to lift: within
--                                              Reserve studs of it and nearer than he is (the player's lift wins)
--   MoveHelperBrain.worth(c)                   a piece's rank for a trip: its value a second of the trip (TripBase
--                                              studs added, the way back to the van at the carry's walk)
--   MoveHelperBrain.pickItem(list, backOpen)   the next piece he carries out alone (★ first, then the best worth; a
--                                              one-hand or a two-hands piece, never a pair one, a broken one, a
--                                              reserved one, one that no longer fits the van or one lying by the van
--                                              while its back is shut) and whether the van is full for the ones left
--   MoveHelperBrain.pickLift(list)             the crew's two-person lift he comes to: a pair piece a crew player
--                                              drags alone, the nearest within HelpFar, not one he gave up on
--   MoveHelperBrain.pickAssist(list)           a heavy two-hands piece (AssistWeight or more) a crew player carries
--                                              alone within AssistFar, not by the van's back already: he takes its
--                                              other side (the pair's walk for both)
--   MoveHelperBrain.shouldFlee(threat, fleeing, holding)   a zombie near: run (never while holding the other end of
--                                              your piece: the player leads); on until none is within SafeRange
--   MoveHelperBrain.fleeTo(x, z, zx, zz)       where he runs: FleeStep studs straight away from the zombie
--   MoveHelperBrain.decide(input)              what he does now and the piece's spot: "down" | "hold" | "flee" |
--                                              "help" | "deliver" | "open" | "wait" | "assist" | "follow" | "fetch"
--   MoveHelperBrain.atTruck(open, still, waited, mayOpen)   a piece in his arms at the van's back: "load" | "open" |
--                                              "wait" | "drop"
--   MoveHelperBrain.speed(walk, action, carry, weight)   his walk now: × Speed (× the carry's alone: "hand" | "both"),
--                                              Sprint × to a lift, Flee × running away
--   MoveHelperBrain.stuck(stuckFor, moved, dt, speed)    seconds without progress (under a fifth of his walk)
--   MoveHelperBrain.unstuck(stuckFor)          what a stuck walk does: "walk" | "repath" (StuckRepath s) | "nudge"
--                                              (StuckSnap s: he appears at his way's next point)
--   MoveHelperBrain.endRise(floorRise, carrierRise)   his root's height at your piece's far end over its middle: the
--                                              floor's there (stairs, steps), within HoldStep of the carrier's
--   MoveHelperBrain.farEnd(depth)              how far in front of the piece's middle his root stands (its far face
--                                              and Standoff)
--   MoveHelperBrain.aside(x, z, door)          a place in a doorway (Aside's zone): the place beside it, along the wall
--                                              (he never stands where you walk through); else the place itself
--   MoveHelperBrain.followSpot(x, z, lookX, lookZ)       his place behind you ("Help me")
--   MoveHelperBrain.doing(action, name, full)  what he does, in words (client/MoveHelperHud.luau's line)
--   MoveHelperBrain.Lines                      what he says (a speech bubble over his head; plain text)
--   MoveHelperBrain.line(key, sandbox)         his line for `key` (8.0 SANDBOX: SandboxLines' where the test world has
--                                              no Wall and no depot)

local Config = require(script.Parent.Config)
local Rules = require(script.Parent.MovingRules)

local MoveHelperBrain = {}

export type Mode = "help" | "carry" | "wait"

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

function MoveHelperBrain.validMode(mode: any): boolean
	return mode == "help" or mode == "carry" or mode == "wait"
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

-- His root's height over the piece's middle: the floor's under the far end (`floorRise`, his stand height on it), within
-- HoldStep of the carrier's root (`carrierRise`): up and down stairs and steps, never off his hands' reach.
function MoveHelperBrain.endRise(floorRise: number, carrierRise: number): number
	local step = cfg().HoldStep
	if floorRise ~= floorRise then
		return carrierRise
	end
	return math.clamp(floorRise, carrierRise - step, carrierRise + step)
end

-- ── What next ──────────────────────────────────────────────────────────────

function MoveHelperBrain.reserved(playerCost: number?, myCost: number): boolean
	return playerCost ~= nil and playerCost <= cfg().Reserve and playerCost < myCost
end

-- Its value a second of the trip there and back to the van (the carry's walk on the way back; TripBase studs on top so
-- a near cheap piece does not always win).
function MoveHelperBrain.worth(c: Candidate): number
	local mode = if c.class == "both" then "both" else "hand"
	local factor = math.max(Rules.speedFactor(mode, c.weight), 0.1)
	return c.value / (cfg().TripBase + c.cost + c.haul / factor)
end

function MoveHelperBrain.pickItem(list: { Candidate }, backOpen: boolean): (number?, boolean)
	local best: Candidate? = nil
	local bestWorth = -math.huge
	local left = false
	for _, c in list do
		if (c.class ~= "hand" and c.class ~= "both") or c.broken or (c.state ~= "home" and c.state ~= "ground") or c.reserved then
			continue
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

-- The priorities, in order: down; the other end of your piece (zombies or not: you lead); running from a zombie; your
-- two-person lift (his own piece set down or loaded first); the piece in his arms to the van; the van's back for whoever
-- comes with a piece; Wait at the van; the other side of your heavy two-hands piece; Help me (behind you); the next
-- piece while the van stands by the house; waiting at the van.
function MoveHelperBrain.decide(i: Input): (string, number?)
	if i.dead then
		return "down", nil
	elseif i.holding == "pair" then
		return "hold", nil
	elseif MoveHelperBrain.shouldFlee(i.threat, i.fleeing, i.holding) then
		return "flee", nil
	elseif i.lift ~= nil and i.mode ~= "wait" then
		return "help", i.lift
	elseif i.holding == "hand" then
		return "deliver", nil
	elseif i.open then
		return "open", nil
	elseif i.mode == "wait" then
		return "wait", nil
	elseif i.assist ~= nil then
		return "assist", i.assist
	elseif i.mode == "help" then
		return "follow", nil
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
	elseif action == "help" or action == "assist" then
		return walk * c.Sprint
	elseif action == "hold" then
		return Rules.carrySpeed(walk, "pair", weight) * c.KeepUp
	end
	local factor = if carry then Rules.speedFactor(carry, weight) else 1
	return walk * c.Speed * factor
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
	helpMode = "Right behind you.",
	carryMode = "On the small stuff.",
	waitMode = "Waiting at the van.",
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
