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
--   The truck bed (a grid of cells `cell` studs square under the box, any size: cols across, rows from the cab to the
--   door). A thing rests on the highest top under its footprint (the floor, or the things it covers, overhanging the
--   lower ones) when at least Pack.Support of it lies level there round its middle; never through the roof. Of every
--   place it can stand, both ways round, the best score wins, like Tetris: snug against the walls and its neighbours,
--   its top level with theirs, little air under it, low, to one side, near the cab, a fragile thing high up
--   (Config.Moving.Pack)
--   MovingRules.newPacking(width, length, height, cell)   an empty bed
--   MovingRules.footprint(size, cell, turned)  the cells it covers (cols, rows)
--   MovingRules.fit(packing, size, fragile?, lie?) -> Placement?   where it would go (nil: no room); place(packing,
--                                              spot, size, fragile?, lie?) puts it; room(packing, size, lie?): does it
--                                              still go in (the HUD); lie: it may lie on its side when it has no place
--                                              standing (a both / pair piece, Pack.Lie: Placement.lying, laid(size,
--                                              lying) its size so)
--   MovingRules.free(packing, spot)            nothing rests on it (it may come out); remove(packing, spot)
--   MovingRules.fill(packing)                  the share of the bed's room used (0 … 1): up to every top, and to the
--                                              roof where nothing goes any more (a crack, a sliver under the roof)
--   MovingRules.where(packing, placement)      its middle in studs from the bed's middle (x across, z toward the door)
--   A move
--   MovingRules.newMove(spots, defs, bed, now, seconds)   from the plan's spots and the furniture defs
--   MovingRules.holding(move, who) -> (spot?, "carrier" | "helper" | nil)
--   MovingRules.pick(move, spot, who) / help(move, spot, who) / release(move, who) / load(move, who) /
--   unload(move, who, spot?) -> (ok / spot / placement, why?)   the carry's steps (why: a short code, whyText)
--   MovingRules.lastOut(move)                  the thing Unload takes: the last loaded one nothing rests on
--   MovingRules.counts(move)                   { total, out, stars, starsOut, broken, carried, home }
--   MovingRules.advance(phase, event)          the phase machine: running → horde → done | late | cancelled | failed
--   MovingRules.due(move, now)                 the event the clock brings now ("horde", "timeout") or nil
--   MovingRules.result(move, how, now)         the pay: Σ value × condition, ★ × Pay.Star, a time bonus, − the broken
--                                              ones' fine; late: × LateShare; the stars 1 … 5 and the XP (Xp + the
--                                              value delivered / XpPerValue + XpPerStar × the stars, at most XpMax)
--   MovingRules.estimate(spots, defs)          the contract card's pay: everything out whole, in time
--   MovingRules.whyText(why)                   what the player is told

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
	lying: string?, -- on its side (Pack.Lie): "x" its height along its width, "z" along its depth (MovingRules.laid)
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
	state: string, -- home | carried | ground | truck
	carrier: number?,
	helper: number?,
	place: Placement?,
}
export type Move = {
	things: { [number]: Thing },
	order: { number }, -- the spots in the plan's order
	packing: Packing,
	phase: string, -- running | horde | done | late | cancelled | failed
	startedAt: number,
	endsAt: number,
	seconds: number,
}
export type Counts = { total: number, out: number, stars: number, starsOut: number, broken: number, carried: number, home: number }
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

-- Under a footprint: the highest top (where it would stand) and the sum of the tops; nil when a top there is over
-- `limit` (the roof would not let it in).
local function survey(p: Packing, col: number, row: number, cols: number, rows: number, limit: number): (number?, number)
	local high, sum = 0, 0
	for r = row, row + rows - 1 do
		local at = (r - 1) * p.cols
		for c = col, col + cols - 1 do
			local h = p.heights[at + c]
			if h > limit then
				return nil, 0
			end
			if h > high then
				high = h
			end
			sum += h
		end
	end
	return high, sum
end

-- Does it stand on `base`: at least Pack.Support of its cells within Pack.Level under it (the floor: all of them), and
-- those cells reach past its middle both across and along (not on one corner or one edge)?
local function supported(p: Packing, col: number, row: number, cols: number, rows: number, base: number): boolean
	if base <= EPS then
		return true
	end
	local k = tune().Pack
	local level = base - k.Level - 1e-3
	local count = 0
	local c0, c1, r0, r1 = math.huge, -math.huge, math.huge, -math.huge
	for r = row, row + rows - 1 do
		local at = (r - 1) * p.cols
		for c = col, col + cols - 1 do
			if p.heights[at + c] >= level then
				count += 1
				c0, c1 = math.min(c0, c), math.max(c1, c)
				r0, r1 = math.min(r0, r), math.max(r1, r)
			end
		end
	end
	if count < k.Support * cols * rows - 1e-6 then
		return false
	end
	local midCol, midRow = col - 1 + cols / 2, row - 1 + rows / 2 -- its middle (from the cells' edges)
	return c0 - 1 < midCol and c1 > midCol and r0 - 1 < midRow and r1 > midRow
end

-- Its sides, from `base` to `top`: the share against the bed's walls or the things beside it, and the share of its
-- edge where the top beside it is level with its own (a wall counts for both).
local function contact(p: Packing, col: number, row: number, cols: number, rows: number, base: number, top: number, level: number): (number, number)
	local heights, width = p.heights, p.cols
	local tall = top - base
	local touch, flush = 0, 0
	local function beside(index: number)
		local h = heights[index]
		touch += math.max(0, math.min(h, top) - base)
		if math.abs(h - top) <= level then
			flush += 1
		end
	end
	local last = row + rows - 1
	for r = row, last do
		local at = (r - 1) * width
		if col == 1 then
			touch += tall
			flush += 1
		else
			beside(at + col - 1)
		end
		if col + cols - 1 == p.cols then
			touch += tall
			flush += 1
		else
			beside(at + col + cols)
		end
	end
	for c = col, col + cols - 1 do
		if row == 1 then
			touch += tall
			flush += 1
		else
			beside((row - 2) * width + c)
		end
		if last == p.rows then
			touch += tall
			flush += 1
		else
			beside(last * width + c)
		end
	end
	local edge = 2 * (cols + rows)
	return touch / (edge * tall), flush / edge
end

local TURNS = { false, true }

-- Every place it can stand, both ways round: on the highest top under it, supported, under the roof. Calls
-- `each(col, row, cols, rows, turned, base, sum)` for each; stops when it returns true.
local function places(p: Packing, size: Size, each: (number, number, number, number, boolean, number, number) -> boolean?)
	local limit = p.height - size.Y + 1e-3 -- the highest base under the roof
	if limit < 0 then
		return
	end
	for _, turned in TURNS do
		local cols, rows = MovingRules.footprint(size, p.cell, turned)
		if cols > p.cols or rows > p.rows or (turned and cols == rows) then
			continue
		end
		for row = 1, p.rows - rows + 1 do
			for col = 1, p.cols - cols + 1 do
				local base, sum = survey(p, col, row, cols, rows, limit)
				if base ~= nil and supported(p, col, row, cols, rows, base) and each(col, row, cols, rows, turned, base, sum) then
					return
				end
			end
		end
	end
end

-- Its best place standing as `size` (nil: none) and that place's score. Of every place it can stand (places) the
-- lowest score wins (Config.Moving.Pack): snug against the walls and its neighbours, its top level with theirs, little
-- air under it, low, to one side, near the cab, no sliver of room left over it; a fragile thing high up (little room
-- over it: little goes on it).
local function choose(p: Packing, size: Size, fragile: boolean?): (Placement?, number)
	local k = tune().Pack
	local cell = p.cell
	local best: Placement? = nil
	local bestScore = math.huge
	places(p, size, function(col: number, row: number, cols: number, rows: number, turned: boolean, base: number, sum: number): boolean?
		local area = cols * rows
		local top = base + size.Y
		local air = (area * base - sum) / (area * size.Y) -- the air left under it, a share of its own room
		local snug, flush = contact(p, col, row, cols, rows, base, top, k.Level)
		local depth = (row - 1 + rows / 2) * cell -- its middle from the cab
		local side = math.min(col - 1, p.cols - col - cols + 1) * cell
		local over = p.height - top
		local dead = if over < k.Headroom then over else 0 -- a sliver nothing goes into
		local score = k.Base * base + k.Waste * air - k.Contact * snug - k.Flush * flush + k.Depth * depth + k.Side * side
			+ (k.Dead * dead + (if fragile then k.High * over else 0)) / size.Y
		if score < bestScore - 1e-9 then
			bestScore = score
			best = { spot = 0, col = col, row = row, cols = cols, rows = rows, base = base, top = top, turned = turned }
		end
		return nil
	end)
	return best, bestScore
end

-- Its size lying on its side (`lying` "x": its height along its width, "z": along its depth; else as it is).
function MovingRules.laid(size: Size, lying: string?): Size
	if lying == "x" then
		return { X = size.Y, Y = size.X, Z = size.Z }
	elseif lying == "z" then
		return { X = size.X, Y = size.Z, Z = size.Y }
	end
	return size
end

local SIDES = { "x", "z" }

-- Where it would go (nil: no room): standing up (choose); when it has no place standing and it may lie (`lie`: a
-- both / pair piece, and Pack.Lie), the better of its places lying on either side (Placement.lying).
function MovingRules.fit(p: Packing, size: Size, fragile: boolean?, lie: boolean?): Placement?
	local best, bestScore = choose(p, size, fragile)
	if best or not lie or not tune().Pack.Lie then
		return best
	end
	for _, lying in SIDES do
		local at, score = choose(p, MovingRules.laid(size, lying), fragile)
		if at and score < bestScore then
			at.lying = lying
			best, bestScore = at, score
		end
	end
	return best
end

-- Does it still go in (the HUD: the carried thing; `lie` as fit's)? The first place found is enough.
function MovingRules.room(p: Packing, size: Size, lie: boolean?): boolean
	local found = false
	local function any(): boolean?
		found = true
		return true
	end
	places(p, size, any)
	if not found and lie and tune().Pack.Lie then
		for _, lying in SIDES do
			places(p, MovingRules.laid(size, lying), any)
			if found then
				break
			end
		end
	end
	return found
end

local function stamp(p: Packing, at: Placement)
	for r = at.row, at.row + at.rows - 1 do
		for c = at.col, at.col + at.cols - 1 do
			local index = (r - 1) * p.cols + c
			p.heights[index] = math.max(p.heights[index], at.top)
		end
	end
end

function MovingRules.place(p: Packing, spot: number, size: Size, fragile: boolean?, lie: boolean?): Placement?
	local at = MovingRules.fit(p, size, fragile, lie)
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

-- Nothing rests on it: no other thing over its footprint at or above its top (one that only overhangs it counts too).
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

-- The share of the bed's room used (0 … 1): every cell up to its top (the things, and the air under them nothing reaches
-- any more), and up to the roof where nothing goes any more: no flat Pack.Probe-stud square with Pack.Headroom over it
-- covers the cell (a crack between two things, a sliver under the roof).
function MovingRules.fill(p: Packing): number
	local cells = p.cols * p.rows
	local room = cells * p.height
	if room <= 0 then
		return 0
	end
	local k = tune().Pack
	local heights, width = p.heights, p.cols
	local n = math.clamp(math.ceil(k.Probe / p.cell - 1e-3), 1, math.min(p.cols, p.rows))
	local roof = math.max(0, p.height - k.Headroom) + 1e-3
	local open: { boolean } = table.create(cells, false)
	for row = 1, p.rows - n + 1 do
		for col = 1, p.cols - n + 1 do
			local low, high = math.huge, -math.huge
			for r = row, row + n - 1 do
				for c = col, col + n - 1 do
					local h = heights[(r - 1) * width + c]
					low, high = math.min(low, h), math.max(high, h)
				end
			end
			if high <= roof and high - low <= k.Level + 1e-3 then
				for r = row, row + n - 1 do
					for c = col, col + n - 1 do
						open[(r - 1) * width + c] = true
					end
				end
			end
		end
	end
	local used = 0
	for i = 1, cells do
		used += if open[i] then heights[i] else p.height
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

function MovingRules.newMove(spots: { Spot }, defs: { [string]: ItemDef }, bed: Bed, now: number, seconds: number): Move
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
	local at = MovingRules.place(move.packing, spot, thing.size, thing.fragile, thing.class ~= "hand")
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
	return nil
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
	if not MovingRules.remove(move.packing, pick) then
		return nil, "under"
	end
	thing.state = "carried"
	thing.carrier = who
	thing.helper = nil
	thing.place = nil
	return pick, nil
end

function MovingRules.counts(move: Move): Counts
	local c: Counts = { total = 0, out = 0, stars = 0, starsOut = 0, broken = 0, carried = 0, home = 0 }
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
	elseif move.phase == "running" and left <= tune().HordeAt then
		return "horde"
	end
	return nil
end

-- ── The pay ────────────────────────────────────────────────────────────────

function MovingRules.result(move: Move, how: string, now: number): Result
	local pay = tune().Pay
	local r: Result = { how = how, delivered = 0, left = 0, broken = 0, starsOut = 0, stars = 0, base = 0, starBonus = 0, timeBonus = 0, fine = 0, total = 0, xp = 0 }
	local paid = how == "done" or how == "late"
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
		if paid and thing.state == "truck" then
			r.delivered += 1
			if broken then
				r.fine += thing.value * pay.Scale * pay.BrokenFine
			else
				got += thing.value * thing.condition
				local value = thing.value * thing.condition * pay.Scale
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
	local share = if how == "late" then pay.LateShare else 1
	r.total = math.max(0, math.floor((r.base + r.starBonus + r.timeBonus) * share - r.fine + 0.5))
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
function MovingRules.estimate(spots: { Spot }, defs: { [string]: ItemDef }): number
	local pay = tune().Pay
	local total = 0
	local seen: { [number]: boolean } = {}
	for _, spot in spots do
		local def = defs[spot.item]
		if def and not seen[spot.id] then
			seen[spot.id] = true
			total += def.value * pay.Scale * (if spot.star then pay.Star else 1)
		end
	end
	return math.floor(total + 0.5)
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
	noroom = "No room — unload something or bring a bigger truck.",
	nothing = "Nothing in the truck.",
	under = "Something rests on it: take that out first.",
}

function MovingRules.whyText(why: string?): string
	return WHY[why or ""] or "You can't do that now."
end

return MovingRules
