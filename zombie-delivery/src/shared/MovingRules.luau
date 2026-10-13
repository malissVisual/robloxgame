--!strict
-- 7.0 prototype, MOVES (the owner's rework, design/rework/NAVRH.md): the pure rules of one house move (no Roblox at the
-- top level: tests/moving_test.luau). server/Moving.luau runs a move with these and does the world's side (the
-- interior, the prompts, the welds, the truck); client/MovingHud.luau shows the state it sends. The numbers are
-- Config.Moving's.
--
-- A move is plain data (Move): its things (one per furniture spot of the house's plan: shared/HouseLayout.luau spots,
-- shared/FurnitureLooks.luau Items), the truck bed's packing and the phase. Who holds what is kept by user id, so the
-- tests run it with plain numbers.
--
--   The carry
--   MovingRules.mode(thing)                    "hand" | "both" | "pair" (two lift it) | "drag" (a pair thing alone)
--   MovingRules.speedFactor(mode, weight)      × the walk: hand 1 − weight × HandPerWeight (not under MinHand), both
--                                              Both, pair Pair, drag Drag
--   MovingRules.carrySpeed(walk, mode, weight) the walk speed with it (the character's CarrySpeed attribute)
--   MovingRules.hands(mode)                    1 (a hand free: you open the truck's back yourself) or 2
--   The damage (a share of the condition 0 … 1; fragile things Damage.Fragile × as much)
--   MovingRules.fallDamage(height, fragile)    a landing (or a thing set down) from `height` studs: nothing up to
--                                              SafeDrop, then PerStud a stud
--   MovingRules.hitDamage(hp, fragile)         its carrier lost `hp` health (a zombie's bite)
--   MovingRules.deathDamage(fragile)           its carrier died: it fell
--   MovingRules.truckDamage(hp, fragile)       the truck it rides in took `hp` damage
--   MovingRules.hurt(thing, share) -> broke    takes it off (true when this broke it); MovingRules.broken(thing)
--   The truck bed (a grid of Bed.Cell studs under the box: cols across, rows from the cab to the door; a thing stands
--   on the floor or flat on others, its footprint turned 90° when that fits better; the lowest place first, the cab's
--   end first: first-fit)
--   MovingRules.newPacking(width, length, height, cell)   an empty bed
--   MovingRules.footprint(size, cell, turned)  the cells it covers (cols, rows)
--   MovingRules.fit(packing, size) -> Placement?   where it would go (nil: no room); place(packing, spot, size) puts it
--   MovingRules.free(packing, spot)            nothing rests on it (it may come out); remove(packing, spot)
--   MovingRules.fill(packing)                  the share of the bed's room taken (0 … 1)
--   MovingRules.where(packing, placement)      its middle in studs from the bed's middle (x across, z toward the door)
--   A move
--   MovingRules.newMove(spots, defs, bed, now, seconds, hordeAt?, pay?)   from the plan's spots and the furniture defs
--                                              (7.x farm move: a contract's own horde time, s left, and × on its pay)
--   MovingRules.holding(move, who) -> (spot?, "carrier" | "helper" | nil)
--   MovingRules.pick(move, spot, who) / help(move, spot, who) / release(move, who) / load(move, who) /
--   unload(move, who, spot?) -> (ok / spot / placement, why?)   the carry's steps (why: a short code, whyText)
--   MovingRules.lastOut(move)                  the thing Unload takes: the last loaded one nothing rests on
--   MovingRules.counts(move)                   { total, out, stars, starsOut, broken, carried, home }
--   MovingRules.advance(phase, event)          the phase machine: running → horde → done | late | cancelled | failed
--   MovingRules.due(move, now)                 the event the clock brings now ("horde", "timeout") or nil (the horde at
--                                              the move's own hordeAt, else HordeAt)
--   MovingRules.result(move, how, now)         the pay: Σ value × condition, ★ × Pay.Star, a time bonus, − the broken
--                                              ones' fine; late: × LateShare; the stars 1 … 5 and the XP (Xp + the
--                                              value delivered / XpPerValue + XpPerStar × the stars, at most XpMax)
--   MovingRules.estimate(spots, defs, pay?)    the contract card's pay: everything out whole, in time (× pay)
--   MovingRules.whyText(why)                   what the player is told
--   7.x van moves (the owner: the move is driven with the owner's own van; several trips to the Wall):
--   MovingRules.deliver(move, now) -> spots    at the Wall: everything in the van (and on its hitch) is delivered
--                                              (state "delivered", late when the clock had run out), the bed empty again
--   MovingRules.lose(move) -> spots            the van was lost: what was in it is lost (state "lost", condition 0)
--   MovingRules.setBed(move, bed)              another car's bed (an empty one: after the van was lost)
--   The hitch: a piece too big for the bed that may be towed (ItemDef.tow: FurnitureLooks bigDoor, the hay wagon) is
--   hitched behind the car instead (Placement.hitch; one at a time), Unload takes it off once the bed is empty.
--   The pay counts the delivered things only (each trip's); one delivered late pays LateShare of it.

local Config = require(script.Parent.Config)

local MovingRules = {}

local EPS = 1e-6

export type Size = { X: number, Y: number, Z: number }
export type ItemDef = {
	id: string,
	name: string,
	icon: string,
	size: Size,
	class: string, -- hand | both | pair
	weight: number, -- 1 … 10
	value: number,
	fragile: boolean,
	room: string,
	tow: boolean?, -- 7.x van moves: too big for a bed, it may ride hitched behind the car (FurnitureLooks bigDoor)
}
export type Spot = { id: number, item: string, room: string, star: boolean }
export type Placement = {
	spot: number,
	col: number, -- the first column it covers (1: the bed's left)
	row: number, -- the first row (1: at the cab)
	cols: number,
	rows: number,
	base: number, -- studs over the floor where it stands
	top: number,
	turned: boolean, -- its footprint turned 90°
	hitch: boolean?, -- 7.x van moves: hitched behind the car, not on the bed
}
export type Packing = {
	cols: number,
	rows: number,
	cell: number,
	height: number,
	heights: { number }, -- (row - 1) × cols + col → the top there
	placed: { Placement }, -- in the order they went in
}
export type Thing = {
	spot: number,
	item: string,
	name: string,
	icon: string,
	class: string,
	weight: number,
	value: number,
	fragile: boolean,
	star: boolean,
	room: string,
	size: Size,
	condition: number,
	state: string, -- home | carried | ground | truck (in the van) | delivered (at the Wall) | lost (with a lost van)
	carrier: number?,
	helper: number?,
	place: Placement?,
	tow: boolean?, -- 7.x van moves: it may ride hitched (ItemDef.tow)
	late: boolean?, -- 7.x van moves: delivered after the clock ran out (pays LateShare)
}
export type Move = {
	things: { [number]: Thing },
	order: { number }, -- the spots in the plan's order
	packing: Packing,
	phase: string, -- running | horde | done | late | cancelled | failed
	startedAt: number,
	endsAt: number,
	seconds: number,
	hordeAt: number?, -- 7.x farm move: s left when the horde comes (nil: Config.Moving.HordeAt)
	pay: number?, -- 7.x farm move: × the pay (nil: 1)
	bed: Bed?, -- 7.x van moves: the bed's numbers (an empty bed again after a trip)
	hitch: number?, -- 7.x van moves: the spot hitched behind the car (nil: none)
	trips: number?, -- 7.x van moves: the trips delivered at the Wall
}
export type Counts = { total: number, out: number, stars: number, starsOut: number, broken: number, carried: number, home: number, delivered: number, starsDelivered: number, lost: number }
export type Result = {
	how: string,
	delivered: number,
	left: number,
	broken: number,
	starsOut: number,
	stars: number, -- the rating, 1 … 5 (0: called off)
	base: number,
	starBonus: number,
	timeBonus: number,
	fine: number,
	total: number,
	xp: number,
}

local function tune(): any
	return (Config :: any).Moving
end

-- ── The carry ──────────────────────────────────────────────────────────────

function MovingRules.mode(thing: Thing): string
	if thing.class == "hand" then
		return "hand"
	elseif thing.class == "both" then
		return "both"
	end
	return if thing.helper ~= nil then "pair" else "drag"
end

function MovingRules.speedFactor(mode: string, weight: number): number
	local s = tune().Speed
	if mode == "hand" then
		local w = math.clamp(if weight == weight then weight else 1, 0, 10)
		return math.max(s.MinHand, 1 - w * s.HandPerWeight)
	elseif mode == "both" then
		return s.Both
	elseif mode == "pair" then
		return s.Pair
	end
	return s.Drag
end

function MovingRules.carrySpeed(walk: number, mode: string, weight: number): number
	return walk * MovingRules.speedFactor(mode, weight)
end

function MovingRules.hands(mode: string): number
	return if mode == "hand" then 1 else 2
end

-- ── Damage ─────────────────────────────────────────────────────────────────

local function fragility(fragile: boolean): number
	return if fragile then tune().Damage.Fragile else 1
end

function MovingRules.fallDamage(height: number, fragile: boolean): number
	local d = tune().Damage
	local over = height - d.SafeDrop
	if over ~= over or over <= 0 then
		return 0
	end
	return math.min(1, over * d.PerStud * fragility(fragile))
end

function MovingRules.hitDamage(hp: number, fragile: boolean): number
	if hp ~= hp or hp <= 0 then
		return 0
	end
	return math.min(1, hp * tune().Damage.PerHp * fragility(fragile))
end

function MovingRules.deathDamage(fragile: boolean): number
	return math.min(1, tune().Damage.Death * fragility(fragile))
end

function MovingRules.truckDamage(hp: number, fragile: boolean): number
	if hp ~= hp or hp <= 0 then
		return 0
	end
	return math.min(1, hp * tune().Damage.PerTruckHp * fragility(fragile))
end

function MovingRules.broken(thing: Thing): boolean
	return thing.condition <= tune().Damage.BrokenAt + EPS
end

-- Takes `share` off its condition; true when this broke it.
function MovingRules.hurt(thing: Thing, share: number): boolean
	if share ~= share or share <= 0 then
		return false
	end
	local was = MovingRules.broken(thing)
	thing.condition = math.clamp(thing.condition - share, 0, 1)
	return not was and MovingRules.broken(thing)
end

-- ── The truck bed ──────────────────────────────────────────────────────────

function MovingRules.newPacking(width: number, length: number, height: number, cell: number): Packing
	local cols = math.max(1, math.floor(width / cell + EPS))
	local rows = math.max(1, math.floor(length / cell + EPS))
	local heights = table.create(cols * rows, 0)
	return { cols = cols, rows = rows, cell = cell, height = height, heights = heights, placed = {} }
end

function MovingRules.footprint(size: Size, cell: number, turned: boolean): (number, number)
	local across = if turned then size.Z else size.X
	local along = if turned then size.X else size.Z
	return math.max(1, math.ceil(across / cell - 1e-3)), math.max(1, math.ceil(along / cell - 1e-3))
end

-- The lowest and the highest top under a footprint.
local function span(p: Packing, col: number, row: number, cols: number, rows: number): (number, number)
	local low, high = math.huge, -math.huge
	for r = row, row + rows - 1 do
		local at = (r - 1) * p.cols
		for c = col, col + cols - 1 do
			local h = p.heights[at + c]
			if h < low then
				low = h
			end
			if h > high then
				high = h
			end
		end
	end
	return low, high
end

function MovingRules.fit(p: Packing, size: Size): Placement?
	local best: Placement? = nil
	for row = 1, p.rows do
		for col = 1, p.cols do
			for _, turned in { false, true } do
				local cols, rows = MovingRules.footprint(size, p.cell, turned)
				if col + cols - 1 > p.cols or row + rows - 1 > p.rows then
					continue
				end
				local low, high = span(p, col, row, cols, rows)
				-- flat under it (the floor, or the tops of what it rests on all level), and under the roof
				if high - low > 0.05 or high + size.Y > p.height + 1e-3 then
					continue
				end
				if best == nil or high < best.base - 1e-3 then
					best = { spot = 0, col = col, row = row, cols = cols, rows = rows, base = high, top = high + size.Y, turned = turned }
				end
			end
		end
	end
	return best
end

local function stamp(p: Packing, at: Placement)
	for r = at.row, at.row + at.rows - 1 do
		for c = at.col, at.col + at.cols - 1 do
			local index = (r - 1) * p.cols + c
			p.heights[index] = math.max(p.heights[index], at.top)
		end
	end
end

function MovingRules.place(p: Packing, spot: number, size: Size): Placement?
	local at = MovingRules.fit(p, size)
	if not at then
		return nil
	end
	at.spot = spot
	stamp(p, at)
	table.insert(p.placed, at)
	return at
end

local function overlaps(a: Placement, b: Placement): boolean
	return a.col < b.col + b.cols and b.col < a.col + a.cols and a.row < b.row + b.rows and b.row < a.row + a.rows
end

local function placementOf(p: Packing, spot: number): (Placement?, number?)
	for index, at in p.placed do
		if at.spot == spot then
			return at, index
		end
	end
	return nil, nil
end

function MovingRules.free(p: Packing, spot: number): boolean
	local at = placementOf(p, spot)
	if not at then
		return false
	end
	for _, other in p.placed do
		if other ~= at and other.base >= at.top - 1e-3 and overlaps(at, other) then
			return false
		end
	end
	return true
end

function MovingRules.remove(p: Packing, spot: number): boolean
	local at, index = placementOf(p, spot)
	if not at or not index or not MovingRules.free(p, spot) then
		return false
	end
	table.remove(p.placed, index)
	for i = 1, p.cols * p.rows do
		p.heights[i] = 0
	end
	for _, other in p.placed do
		stamp(p, other)
	end
	return true
end

function MovingRules.fill(p: Packing): number
	local room = p.cols * p.rows * p.height
	if room <= 0 then
		return 0
	end
	local used = 0
	for _, at in p.placed do
		used += at.cols * at.rows * (at.top - at.base)
	end
	return math.clamp(used / room, 0, 1)
end

-- Its middle in studs from the bed's middle: x across (+ right), y up from the floor, z toward the door (+ back).
function MovingRules.where(p: Packing, at: Placement): (number, number, number)
	local cell = p.cell
	local x = (at.col - 1 + at.cols / 2) * cell - p.cols * cell / 2
	local z = (at.row - 1 + at.rows / 2) * cell - p.rows * cell / 2
	return x, (at.base + at.top) / 2, z
end

-- ── A move ─────────────────────────────────────────────────────────────────

export type Bed = { width: number, length: number, height: number, cell: number }

function MovingRules.newMove(spots: { Spot }, defs: { [string]: ItemDef }, bed: Bed, now: number, seconds: number, hordeAt: number?, pay: number?): Move
	local things: { [number]: Thing } = {}
	local order: { number } = {}
	for _, spot in spots do
		local def = defs[spot.item]
		if not def or things[spot.id] then
			continue
		end
		things[spot.id] = {
			spot = spot.id,
			item = def.id,
			name = def.name,
			icon = def.icon,
			class = if def.class == "hand" or def.class == "both" or def.class == "pair" then def.class else "both",
			weight = def.weight,
			value = math.max(0, def.value),
			fragile = def.fragile == true,
			tow = def.tow == true,
			star = spot.star == true,
			room = spot.room,
			size = { X = def.size.X, Y = def.size.Y, Z = def.size.Z },
			condition = 1,
			state = "home",
			carrier = nil,
			helper = nil,
			place = nil,
		}
		table.insert(order, spot.id)
	end
	return {
		things = things,
		order = order,
		packing = MovingRules.newPacking(bed.width, bed.length, bed.height, bed.cell),
		phase = "running",
		startedAt = now,
		endsAt = now + seconds,
		seconds = seconds,
		hordeAt = hordeAt,
		pay = pay,
		bed = bed,
		hitch = nil,
		trips = 0,
	}
end

function MovingRules.holding(move: Move, who: number): (number?, string?)
	for _, spot in move.order do
		local thing = move.things[spot]
		if thing.carrier == who then
			return spot, "carrier"
		elseif thing.helper == who then
			return spot, "helper"
		end
	end
	return nil, nil
end

local function active(move: Move): boolean
	return move.phase == "running" or move.phase == "horde"
end

-- `who` takes it in their hands (a pair thing alone: dragged until somebody helps).
function MovingRules.pick(move: Move, spot: number, who: number): (boolean, string?)
	local thing = move.things[spot]
	if not active(move) then
		return false, "over"
	elseif not thing then
		return false, "gone"
	elseif MovingRules.holding(move, who) then
		return false, "full"
	elseif thing.state == "carried" then
		return false, "taken"
	elseif thing.state ~= "home" and thing.state ~= "ground" then
		return false, "gone"
	end
	thing.state = "carried"
	thing.carrier = who
	thing.helper = nil
	return true, nil
end

-- `who` takes the other end of a pair thing somebody lifted.
function MovingRules.help(move: Move, spot: number, who: number): (boolean, string?)
	local thing = move.things[spot]
	if not active(move) then
		return false, "over"
	elseif not thing or thing.state ~= "carried" then
		return false, "gone"
	elseif thing.class ~= "pair" then
		return false, "single"
	elseif thing.carrier == who then
		return false, "yours"
	elseif thing.helper ~= nil then
		return false, "helped"
	elseif MovingRules.holding(move, who) then
		return false, "full"
	end
	thing.helper = who
	return true, nil
end

-- `who` lets go: the carrier sets it down (it is on the ground, the helper's hands free too), a helper only lets go
-- of their end (the carrier drags it on). Returns the spot and whether it went down.
function MovingRules.release(move: Move, who: number): (number?, boolean)
	local spot, role = MovingRules.holding(move, who)
	if not spot then
		return nil, false
	end
	local thing = move.things[spot]
	if role == "helper" then
		thing.helper = nil
		return spot, false
	end
	thing.state = "ground"
	thing.carrier = nil
	thing.helper = nil
	return spot, true
end

-- The carrier puts it into the truck: its place on the bed, or nil and why ("noroom").
function MovingRules.load(move: Move, who: number): (Placement?, string?)
	if not active(move) then
		return nil, "over"
	end
	local spot, role = MovingRules.holding(move, who)
	if not spot then
		return nil, "empty"
	elseif role ~= "carrier" then
		return nil, "helper"
	end
	local thing = move.things[spot]
	local at = MovingRules.place(move.packing, spot, thing.size)
	if not at and thing.tow then
		-- 7.x van moves: too big for the bed: hitched behind the car (one at a time)
		if move.hitch ~= nil then
			return nil, "hitched"
		end
		move.hitch = spot
		at = { spot = spot, col = 0, row = 0, cols = 0, rows = 0, base = 0, top = thing.size.Y, turned = false, hitch = true }
	end
	if not at then
		return nil, "noroom"
	end
	thing.state = "truck"
	thing.carrier = nil
	thing.helper = nil
	thing.place = at
	return at, nil
end

-- The last loaded thing nothing rests on (Unload takes it), nil when the bed is empty.
function MovingRules.lastOut(move: Move): number?
	local placed = move.packing.placed
	for index = #placed, 1, -1 do
		local spot = placed[index].spot
		if MovingRules.free(move.packing, spot) then
			return spot
		end
	end
	return move.hitch -- (7.x van moves: the hitched piece once the bed is empty)
end

-- `who` (empty hands) takes a thing back out of the truck (`spot`, else lastOut) into their hands.
function MovingRules.unload(move: Move, who: number, spot: number?): (number?, string?)
	if not active(move) then
		return nil, "over"
	elseif MovingRules.holding(move, who) then
		return nil, "full"
	end
	local pick = spot or MovingRules.lastOut(move)
	local thing = if pick then move.things[pick] else nil
	if not pick or not thing or thing.state ~= "truck" then
		return nil, "nothing"
	end
	if pick == move.hitch then
		move.hitch = nil -- (7.x van moves: off the hitch)
	elseif not MovingRules.remove(move.packing, pick) then
		return nil, "under"
	end
	thing.state = "carried"
	thing.carrier = who
	thing.helper = nil
	thing.place = nil
	return pick, nil
end

function MovingRules.counts(move: Move): Counts
	local c: Counts = { total = 0, out = 0, stars = 0, starsOut = 0, broken = 0, carried = 0, home = 0, delivered = 0, starsDelivered = 0, lost = 0 }
	for _, spot in move.order do
		local thing = move.things[spot]
		c.total += 1
		if thing.star then
			c.stars += 1
		end
		if thing.state == "truck" then
			c.out += 1
			if thing.star then
				c.starsOut += 1
			end
		elseif thing.state == "carried" then
			c.carried += 1
		elseif thing.state == "home" then
			c.home += 1
		elseif thing.state == "delivered" then -- 7.x van moves
			c.delivered += 1
			if thing.star then
				c.starsDelivered += 1
			end
		elseif thing.state == "lost" then
			c.lost += 1
		end
		if MovingRules.broken(thing) then
			c.broken += 1
		end
	end
	return c
end

-- ── The phases ─────────────────────────────────────────────────────────────

local NEXT: { [string]: { [string]: string } } = {
	running = { horde = "horde", deliver = "done", timeout = "late", cancel = "cancelled", lose = "failed" },
	horde = { deliver = "done", timeout = "late", cancel = "cancelled", lose = "failed" },
}

-- The phase after `event` (nil: not from this phase).
function MovingRules.advance(phase: string, event: string): string?
	local from = NEXT[phase]
	return if from then from[event] else nil
end

function MovingRules.over(phase: string): boolean
	return NEXT[phase] == nil
end

function MovingRules.left(move: Move, now: number): number
	return math.max(0, move.endsAt - now)
end

-- The clock's event now: "timeout" at 0, "horde" at HordeAt left (once: the phase is still running), else nil.
function MovingRules.due(move: Move, now: number): string?
	if not active(move) then
		return nil
	end
	local left = MovingRules.left(move, now)
	if left <= 0 then
		return "timeout"
	elseif move.phase == "running" and left <= (move.hordeAt or tune().HordeAt) then
		return "horde"
	end
	return nil
end

-- ── The pay ────────────────────────────────────────────────────────────────

function MovingRules.result(move: Move, how: string, now: number): Result
	local pay = tune().Pay
	local r: Result = { how = how, delivered = 0, left = 0, broken = 0, starsOut = 0, stars = 0, base = 0, starBonus = 0, timeBonus = 0, fine = 0, total = 0, xp = 0 }
	local paid = how == "done" or how == "late"
	local scale = move.pay or 1 -- (7.x farm move: the contract's own pay)
	local worth, got, stars = 0, 0, 0
	for _, spot in move.order do
		local thing = move.things[spot]
		worth += thing.value
		if thing.star then
			stars += 1
		end
		local broken = MovingRules.broken(thing)
		if broken then
			r.broken += 1
		end
		if paid and thing.state == "delivered" then -- (7.x van moves: what reached the Wall, over every trip)
			r.delivered += 1
			if broken then
				r.fine += thing.value * pay.Scale * scale * pay.BrokenFine
			else
				got += thing.value * thing.condition
				local value = thing.value * thing.condition * pay.Scale * scale * (if thing.late then pay.LateShare else 1)
				r.base += value
				if thing.star then
					r.starsOut += 1
					r.starBonus += value * (pay.Star - 1)
				end
			end
		else
			r.left += 1
		end
	end
	if not paid then
		return r
	end
	if how == "done" and move.seconds > 0 then
		r.timeBonus = (r.base + r.starBonus) * pay.TimeBonus * math.clamp(MovingRules.left(move, now) / move.seconds, 0, 1)
	end
	-- (7.x van moves: a thing delivered late counts LateShare of itself above, the on-time trips in full)
	r.total = math.max(0, math.floor(r.base + r.starBonus + r.timeBonus - r.fine + 0.5))
	-- The rating: the ★ things, the value brought whole, few broken; late: 3 at most, a ★ left behind: 3 at most.
	local count = #move.order
	local starShare = if stars > 0 then r.starsOut / stars else 1
	local valueShare = if worth > 0 then got / worth else 0
	local brokenShare = if count > 0 then r.broken / count else 0
	local score = 0.45 * starShare + 0.45 * valueShare + 0.1 * (1 - brokenShare)
	local rating = math.clamp(math.floor(1 + score * 4 + 0.5), 1, 5)
	if how == "late" or r.starsOut < stars then
		rating = math.min(rating, 3)
	end
	r.stars = rating
	-- (7.0 review: the XP grows with the value brought whole: a one-lamp move is no full move)
	r.xp = math.min(pay.XpMax, math.floor(pay.Xp + got / pay.XpPerValue + pay.XpPerStar * rating + 0.5))
	return r
end

-- The contract card's pay: every thing out whole, ★ ones with their bonus (no time bonus).
function MovingRules.estimate(spots: { Spot }, defs: { [string]: ItemDef }, scale: number?): number
	local pay = tune().Pay
	local factor = scale or 1
	local total = 0
	local seen: { [number]: boolean } = {}
	for _, spot in spots do
		local def = defs[spot.item]
		if def and not seen[spot.id] then
			seen[spot.id] = true
			total += def.value * pay.Scale * factor * (if spot.star then pay.Star else 1)
		end
	end
	return math.floor(total + 0.5)
end

-- ── 7.x van moves: the trips ────────────────────────────────────────────────

local function emptyBed(move: Move)
	local bed = move.bed
	local p = move.packing
	move.packing = if bed then MovingRules.newPacking(bed.width, bed.length, bed.height, bed.cell) else MovingRules.newPacking(p.cols * p.cell, p.rows * p.cell, p.height, p.cell)
	move.hitch = nil
end

-- At the Wall: everything in the van and on its hitch is delivered (late after the clock ran out); the spots, in the
-- order they went in (the hitch last). An empty van delivers nothing (no trip).
function MovingRules.deliver(move: Move, now: number): { number }
	local spots: { number } = {}
	for _, at in move.packing.placed do
		table.insert(spots, at.spot)
	end
	if move.hitch then
		table.insert(spots, move.hitch)
	end
	local late = now >= move.endsAt
	local delivered: { number } = {}
	for _, spot in spots do
		local thing = move.things[spot]
		if thing and thing.state == "truck" then
			thing.state, thing.place, thing.carrier, thing.helper = "delivered", nil, nil, nil
			thing.late = late
			table.insert(delivered, spot)
		end
	end
	if #spots > 0 then
		emptyBed(move)
	end
	if #delivered > 0 then
		move.trips = (move.trips or 0) + 1
	end
	return delivered
end

-- The van was lost (wrecked, gone): what was in it is lost with it (condition 0); the spots.
function MovingRules.lose(move: Move): { number }
	local spots: { number } = {}
	for _, spot in move.order do
		local thing = move.things[spot]
		if thing.state == "truck" then
			thing.state, thing.place, thing.condition = "lost", nil, 0
			table.insert(spots, spot)
		end
	end
	emptyBed(move)
	return spots
end

-- Another car's bed (the owner's new van after the old one was lost): an empty one.
function MovingRules.setBed(move: Move, bed: Bed)
	move.bed = bed
	emptyBed(move)
end

local WHY: { [string]: string } = {
	over = "The move is over.",
	gone = "That is not here any more.",
	full = "Your hands are full: put it down (G) first.",
	taken = "Somebody has it already.",
	single = "One person carries that.",
	yours = "You hold it already: a crew mate takes the other end.",
	helped = "Two are on it already.",
	empty = "Carry something to the truck first.",
	helper = "The one at the front loads it.",
	noroom = "No room — unload something, or drive this load to the Wall first.",
	hitched = "The hitch is taken: drive that one to the Wall first.",
	nothing = "Nothing in the van.",
	under = "Something rests on it: take that out first.",
}

function MovingRules.whyText(why: string?): string
	return WHY[why or ""] or "You can't do that now."
end

return MovingRules
