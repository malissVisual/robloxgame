--!strict
-- 7.0, the depot's helper ("Danny from the depot", server/MoveHelper.luau; the owner: solo play is allowed with an AI
-- helper, design/rework/NAVRH.md): his decisions, pure (no Roblox at its top level: tests/movehelper_test.luau runs it
-- in the standalone Luau). Positions are plain numbers (X and Z along the ground); "inside" is a move's interior, its
-- own world far from the street with the front door between the two. The numbers are Config.MoveHelper's, the carry's
-- MovingRules'.
--
--   MoveHelperBrain.wanted(players)            does a crew of this many players get him (Solo, Duo)?
--   MoveHelperBrain.validMode(mode)            "help" (Help me) | "carry" (Carry small stuff, the default) | "wait"
--                                              (Wait at the truck)
--   MoveHelperBrain.routeCost(...)             studs on foot from one point to another, through the front door when
--                                              they are in different worlds
--   MoveHelperBrain.routeVia(..., list, allowed?)   7.x farm move: the same through the best of several doors (a farm's
--                                              front door, its barn doors; only the `allowed` indexes): (studs, index)
--   MoveHelperBrain.pickItem(list, backOpen)   the next one-hand thing he carries out (★ first, then the nearest; never a
--                                              "both" or a "pair" thing, a broken one, one that no longer fits the truck
--                                              or one lying by the truck while its back is shut) and whether the truck
--                                              is full for the ones left
--   MoveHelperBrain.pickLift(list)             the crew's lift he comes to help with: a pair thing a crew player drags
--                                              alone, the nearest within HelpFar, not one he gave up on
--   MoveHelperBrain.shouldFlee(threat, fleeing, holding)   a zombie near: run (never while holding his end of a pair
--                                              thing: the player leads); on until none is within SafeRange
--   MoveHelperBrain.fleeTo(x, z, zx, zz)       where he runs: FleeStep studs straight away from the zombie
--   MoveHelperBrain.decide(input)              what he does now and the thing's spot: "down" | "hold" | "flee" | "help" |
--                                              "deliver" | "follow" | "fetch" | "wait"
--   MoveHelperBrain.atTruck(open, still, waited)   a thing in his arms at the truck's back: "load" | "wait" | "drop"
--   MoveHelperBrain.speed(walk, action, carry, weight)   his walk now: × Speed (× the carry's alone), KeepUp × the
--                                              pair's holding his end, Flee × the walk running
--   MoveHelperBrain.stuck(stuckFor, moved, dt, speed)    seconds without progress (under a fifth of his walk)
--   MoveHelperBrain.apart(apartFor, gap, reach, dt)      his end out of his reach: seconds, and whether he lets go
--   MoveHelperBrain.followSpot(x, z, lookX, lookZ)       his place behind you ("Help me")
--   MoveHelperBrain.doing(action, name, full)  what he does, in words (client/MoveHelperHud.luau's line)
--   MoveHelperBrain.Lines                      what he says (a speech bubble over his head)

local Config = require(script.Parent.Config)
local Rules = require(script.Parent.MovingRules)

local MoveHelperBrain = {}

export type Mode = "help" | "carry" | "wait"

-- A one-hand thing he might carry out.
export type Candidate = {
	spot: number,
	class: string, -- hand | both | pair
	state: string, -- home | carried | ground | truck
	star: boolean,
	broken: boolean,
	cost: number, -- studs to it (routeCost)
	fits: boolean, -- room for it in the truck now
	byTruck: boolean, -- it lies by the truck already (set down there)
}

-- A pair thing somebody lifted.
export type Lift = {
	spot: number,
	class: string,
	state: string,
	helped: boolean, -- somebody holds its other end already
	crew: boolean, -- its carrier is a player of the move
	cost: number, -- studs to it (routeCost)
	gaveUp: boolean, -- he gave up on this lift (stuck on the way, or left behind)
}

export type Doors = { outX: number, outZ: number, inX: number, inZ: number } -- the front door outside, the exit inside

export type Input = {
	mode: Mode,
	dead: boolean,
	holding: string?, -- nil, "hand" (a thing in his arms) or "pair" (his end of a pair thing)
	threat: number?, -- studs to the nearest zombie (nil: none near)
	fleeing: boolean, -- he ran at the last step
	lift: number?, -- pickLift's
	pick: number?, -- pickItem's
	atHouse: boolean, -- the truck stands by the house (he carries things out only then)
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

-- ── What next ──────────────────────────────────────────────────────────────

function MoveHelperBrain.pickItem(list: { Candidate }, backOpen: boolean): (number?, boolean)
	local best: Candidate? = nil
	local left = false
	for _, c in list do
		if c.class ~= "hand" or c.broken or (c.state ~= "home" and c.state ~= "ground") then
			continue
		end
		if c.byTruck and not backOpen then
			continue -- (it waits by the truck for the back to open)
		end
		left = true
		if not c.fits then
			continue
		end
		local b = best
		if b == nil or (c.star and not b.star) or (c.star == b.star and c.cost < b.cost) then
			best = c
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

-- His end of a pair thing in his reach (top priority), then running from a zombie, then the player's lift (his own thing
-- set down first), then the thing in his arms to the truck, then the order: wait at the truck, follow you (Help me), or
-- the next one-hand thing while the truck stands by the house (Carry small stuff; nothing left: he waits at the truck).
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
	elseif i.mode == "wait" then
		return "wait", nil
	elseif i.mode == "help" then
		return "follow", nil
	elseif i.pick ~= nil and i.atHouse then
		return "fetch", i.pick
	end
	return "wait", nil
end

function MoveHelperBrain.atTruck(open: boolean, still: boolean, waited: number): string
	if open and still then
		return "load"
	elseif waited < cfg().WaitShut then
		return "wait"
	end
	return "drop"
end

-- `carry`: the carry's mode with a thing alone ("hand"), nil empty-handed.
function MoveHelperBrain.speed(walk: number, action: string, carry: string?, weight: number): number
	local c = cfg()
	if action == "flee" then
		return walk * c.Flee
	elseif action == "hold" then
		return Rules.carrySpeed(walk, "pair", weight) * c.KeepUp
	end
	local factor = if carry then Rules.speedFactor(carry, weight) else 1
	return walk * c.Speed * factor
end

-- His end too far from him (`gap` over `reach`): the seconds so far, and whether that is over HelpWait (he lets go).
function MoveHelperBrain.apart(apartFor: number, gap: number, reach: number, dt: number): (number, boolean)
	if gap <= reach then
		return 0, false
	end
	local t = apartFor + dt
	return t, t > cfg().HelpWait
end

-- ── Words ──────────────────────────────────────────────────────────────────

local DOING: { [string]: string } = {
	down = "Down: back at the truck soon",
	hold = "Lifting the %s with you",
	flee = "Running from the zombies",
	help = "Coming to lift the %s",
	deliver = "Carrying the %s to the truck",
	follow = "Right behind you",
	fetch = "Going for the %s",
	wait = "Waiting at the truck",
}

function MoveHelperBrain.doing(action: string, name: string?, full: boolean?): string
	if action == "wait" and full then
		return "Waiting: the truck is full"
	end
	local text = DOING[action] or "Waiting at the truck"
	if string.find(text, "%s", 1, true) then
		return string.format(text, name or "thing")
	end
	return text
end

MoveHelperBrain.Lines = {
	hello = "Danny from the depot. Got your back!",
	help = "Got your back!",
	lift = "Lift on three!",
	full = "Truck's full, boss.",
	shut = "Open the back, boss!",
	flee = "Zombies! I'm staying out of this one!",
	down = "Ugh... I'll be back!",
	back = "Back on my feet!",
	apart = "Too quick for me, boss: you drag it.",
	stuck = "Can't get to you, boss: drag it.",
	loaded = "In it goes.",
	helpMode = "Right behind you.",
	carryMode = "On the small stuff.",
	waitMode = "Waiting at the truck.",
} :: { [string]: string }

return MoveHelperBrain
