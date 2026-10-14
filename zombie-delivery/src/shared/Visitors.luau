--!strict
-- 8.3 SANDBOX, the showroom's visitors (the owner: the warehouse should feel alive). Pure (no Roblox at its top level:
-- tests/visitors_test.luau); Config.Visitors holds the numbers. server/Visitors.luau walks the visitors (server/Npcs.luau's
-- bodies) with these plans, server/VisitorOffers.luau prices and checks their offers, client/OfferCard.luau shows one.
--   * Who: Config.Visitors.Kinds (tourists, hikers, a collector in a tweed jacket, an antique dealer): a kind by its
--     weight, a name from its list, its look (shared/NpcLooks.luau's townsperson in the kind's clothes), how keen it is
--     to offer (chance) and how much more it pays (pay).
--   * When: a group of 1 – 3 (Group's chances) every NearEvery s while the owner is at their warehouse, else every
--     AwayEvery s; only to a warehouse with pieces on show (server/Visitors.luau).
--   * Where: the hall as a walking grid of Cell studs (Visitors.hall: its floor, its podiums and the UPGRADES desk as
--     numbers, from shared/WarehouseLayout.luau for any warehouse level); a spot to look at a stand's piece (Visitors.spot:
--     in front of the podium, else beside or behind it; never in the door's way, at the desk or on a podium); the way
--     there round the podiums (Visitors.route: A* on the grid, cut to a few straight legs); in and out through the
--     roller door beside the van (Visitors.doorway).
--   * The offer: the piece's market price now × Min … Max, + Rare a rarity rank over common, + Hot for a hot kind, +
--     the kind's pay, Top at most, rounded up to a round price, always over the market price (Visitors.offerPrice).
--   * The words: what a visitor says (Visitors.say), the owner's toast (Visitors.toast), the card's lines
--     (Visitors.cardLines), the remote's offer checked on the client (Visitors.readOffer).
--
--   Visitors.kinds() / Visitors.kind(id)          Config's kinds / one by its id (nil: none)
--   Visitors.pickKind(roll)                       a kind by the weights (roll in [0, 1))
--   Visitors.pickName(kind, roll)                 one of its names
--   Visitors.look(kind, name)                     the NpcLooks.Look it wears (its walk at Config.Visitors.Walk)
--   Visitors.who(kind)                            "The collector" (the toast's and the card's)
--   Visitors.groupSize(roll)                      1 … #Group
--   Visitors.between(range, roll)                 range[1] … range[2]
--   Visitors.gap(near, roll)                      s until a warehouse's next group (NearEvery or AwayEvery)
--   Visitors.offerChance(kind)                    Offer.Chance × the kind's chance (at most 1)
--   Visitors.offerFactor(rank, hot, pay, roll)    the offer's × over the market price (Top at most)
--   Visitors.offerPrice(market, rank, hot, pay, roll)   $ offered (whole, round, more than `market`)
--   Visitors.hall(input) -> Hall                  the walking grid of a hall: input = { inside (Rect), door = { x, z
--                                                 (the wall's outer face), width }, doorPath (Rect)?, desk (Podium)?,
--                                                 stands = { Podium } (the podiums that stand there) }; a Podium
--                                                 { index, x, z, sx (across), sz (deep), yaw (the way its piece looks) }
--   Visitors.free(hall, x, z)                     is the grid's cell under the point walkable?
--   Visitors.spot(hall, stand, roll?)             where to stand to look at stand `stand`'s piece: { x, z, faceX,
--                                                 faceZ } (nil: no free spot); roll moves it a little to the side
--   Visitors.route(hall, from, to)                { Point } the legs from `from` to `to` (the last `to`, or the nearest
--                                                 free point to it), nil: no way
--   Visitors.doorway(hall, side)                  { outside, threshold, inside } the way in and out on that side (−1 west,
--                                                 1 east) of the door: outside beside the van, the threshold, inside
--   Visitors.say(event, roll, name?, price?)      a visitor's line ("greet", "look", "offer", "sold", "declined",
--                                                 "expired", "gone"; nil: it says nothing)
--   Visitors.toast(who, price, name)             "🤝 The collector offers $340 for your Gramophone"
--   Visitors.cardLines(offer)                     the card's lines: who, price, item, market ("Market price $260 · +31%")
--   Visitors.readOffer(raw)                       the remote's offer checked (nil for anything else)

local Config = require(script.Parent.Config)
local NpcLooks = require(script.Parent.NpcLooks)
local Market = require(script.Parent.Market)

local Visitors = {}

export type Kind = Config.VisitorKind
export type Point = { x: number, z: number }
export type Rect = { x0: number, x1: number, z0: number, z1: number }
export type Podium = { index: number, x: number, z: number, sx: number, sz: number, yaw: number }
export type HallInput = {
	inside: Rect,
	door: { x: number, z: number, width: number },
	doorPath: Rect?,
	desk: Podium?,
	stands: { Podium },
}
export type Hall = {
	input: HallInput,
	cell: number,
	x0: number, -- the grid's west edge
	z0: number, -- its north edge
	nx: number,
	nz: number,
	blocked: { boolean }, -- by cell number: i + (j - 1) × nx
	podiums: { [number]: Podium }, -- by stand index
}
export type Spot = { x: number, z: number, faceX: number, faceZ: number }
export type Doorway = { outside: Point, threshold: Point, inside: Point }
export type Offer = {
	id: string,
	name: string,
	item: string,
	price: number,
	base: number, -- the piece's market price when the offer was made
	who: string, -- "Collector"
	seconds: number, -- s it stays open (from when it reached the client)
	rarity: string?,
	market: string?, -- "hot", "cold" or nil
}

local SQRT2 = math.sqrt(2)
local MAX_ID = 40
local MAX_NAME = 60
local MAX_PRICE = 2 ^ 40

local function tune()
	return Config.Visitors
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function unit(roll: number?): number
	return if finite(roll) then math.clamp(roll :: number, 0, 0.999999) else 0.5
end

-- ── Who and when ────────────────────────────────────────────────────────────

function Visitors.kinds(): { Kind }
	return tune().Kinds
end

function Visitors.kind(id: string): Kind?
	for _, kind in tune().Kinds do
		if kind.id == id then
			return kind
		end
	end
	return nil
end

function Visitors.pickKind(roll: number): Kind
	local kinds = tune().Kinds
	local total = 0
	for _, kind in kinds do
		total += math.max(0, kind.weight)
	end
	local at = unit(roll) * total
	for _, kind in kinds do
		at -= math.max(0, kind.weight)
		if at < 0 then
			return kind
		end
	end
	return kinds[#kinds]
end

function Visitors.pickName(kind: Kind, roll: number): string
	local names = kind.names
	if #names == 0 then
		return kind.title
	end
	return names[math.floor(unit(roll) * #names) + 1]
end

function Visitors.look(kind: Kind, name: string): NpcLooks.Look
	local look = NpcLooks.look("townsperson", name, kind.title)
	for key, value in kind.look do
		(look :: any)[key] = value
	end
	look.walkSpeed = tune().Walk
	return look
end

function Visitors.who(kind: Kind): string
	return "The " .. string.lower(kind.title)
end

function Visitors.groupSize(roll: number): number
	local chances = tune().Group
	local total = 0
	for _, chance in chances do
		total += math.max(0, chance)
	end
	local at = unit(roll) * total
	for size, chance in chances do
		at -= math.max(0, chance)
		if at < 0 then
			return size
		end
	end
	return math.max(1, #chances)
end

function Visitors.between(range: { number }, roll: number): number
	return range[1] + (range[2] - range[1]) * unit(roll)
end

function Visitors.gap(near: boolean, roll: number): number
	return Visitors.between(if near then tune().NearEvery else tune().AwayEvery, roll)
end

-- ── The offer ───────────────────────────────────────────────────────────────

function Visitors.offerChance(kind: Kind): number
	return math.clamp(tune().Offer.Chance * math.max(0, kind.chance), 0, 1)
end

function Visitors.offerFactor(rank: number, hot: boolean, pay: number, roll: number): number
	local O = tune().Offer
	local x = O.Min + (O.Max - O.Min) * unit(roll) + O.Rare * math.max(0, (if finite(rank) then rank else 1) - 1)
		+ (if hot then O.Hot else 0) + math.max(0, if finite(pay) then pay else 0)
	return math.min(x, O.Top)
end

-- $ offered for a piece whose market price is `market`: × the factor, rounded up to $5 from $100 and $10 from $1,000,
-- always at least a dollar more than the market price.
function Visitors.offerPrice(market: number, rank: number, hot: boolean, pay: number, roll: number): number
	local base = math.max(1, math.floor(if finite(market) then market else 1))
	local raw = base * Visitors.offerFactor(rank, hot, pay, roll)
	local step = if raw >= 1000 then 10 elseif raw >= 100 then 5 else 1
	return math.max(base + 1, math.ceil(raw / step - 1e-9) * step)
end

-- ── The hall ────────────────────────────────────────────────────────────────

-- A podium's half extents along x and z (turned by its yaw: the box round it).
local function extent(p: { sx: number, sz: number, yaw: number? }): (number, number)
	local r = math.rad(p.yaw or 0)
	local c, s = math.abs(math.cos(r)), math.abs(math.sin(r))
	return (p.sx * c + p.sz * s) / 2, (p.sx * s + p.sz * c) / 2
end

local function onPodium(p: { x: number, z: number, sx: number, sz: number, yaw: number? }, x: number, z: number, grow: number): boolean
	local hx, hz = extent(p)
	return math.abs(x - p.x) <= hx + grow and math.abs(z - p.z) <= hz + grow
end

local function inRect(r: Rect, x: number, z: number, grow: number): boolean
	return x >= r.x0 - grow and x <= r.x1 + grow and z >= r.z0 - grow and z <= r.z1 + grow
end

-- Is the point within `margin` of the walls, a podium or the desk?
local function solidAt(input: HallInput, x: number, z: number, margin: number): boolean
	local r = input.inside
	if x < r.x0 + margin or x > r.x1 - margin or z < r.z0 + margin or z > r.z1 - margin then
		return true
	end
	for _, p in input.stands do
		if onPodium(p, x, z, margin) then
			return true
		end
	end
	local desk = input.desk
	return desk ~= nil and onPodium(desk, x, z, margin)
end

function Visitors.hall(input: HallInput): Hall
	local T = tune()
	local cell = T.Cell
	local inside = input.inside
	local nx = math.max(1, math.floor((inside.x1 - inside.x0) / cell))
	local nz = math.max(1, math.floor((inside.z1 - inside.z0) / cell))
	local x0 = (inside.x0 + inside.x1) / 2 - nx * cell / 2 -- (the grid centred on the floor)
	local z0 = (inside.z0 + inside.z1) / 2 - nz * cell / 2
	local blocked: { boolean } = table.create(nx * nz, false)
	for j = 1, nz do
		for i = 1, nx do
			blocked[i + (j - 1) * nx] = solidAt(input, x0 + (i - 0.5) * cell, z0 + (j - 0.5) * cell, T.Margin)
		end
	end
	local podiums: { [number]: Podium } = {}
	for _, p in input.stands do
		podiums[p.index] = p
	end
	return { input = input, cell = cell, x0 = x0, z0 = z0, nx = nx, nz = nz, blocked = blocked, podiums = podiums }
end

-- The cell (i, j) under a point, nil off the grid.
local function cellOf(hall: Hall, x: number, z: number): (number?, number?)
	if not finite(x) or not finite(z) then
		return nil, nil
	end
	local i = math.floor((x - hall.x0) / hall.cell) + 1
	local j = math.floor((z - hall.z0) / hall.cell) + 1
	if i < 1 or j < 1 or i > hall.nx or j > hall.nz then
		return nil, nil
	end
	return i, j
end

local function openCell(hall: Hall, i: number, j: number): boolean
	return i >= 1 and j >= 1 and i <= hall.nx and j <= hall.nz and not hall.blocked[i + (j - 1) * hall.nx]
end

local function centre(hall: Hall, i: number, j: number): Point
	return { x = hall.x0 + (i - 0.5) * hall.cell, z = hall.z0 + (j - 0.5) * hall.cell }
end

function Visitors.free(hall: Hall, x: number, z: number): boolean
	local i, j = cellOf(hall, x, z)
	return i ~= nil and j ~= nil and openCell(hall, i, j)
end

-- The walkable cell nearest a point (rings out to `reach` cells), nil for none.
local function nearestOpen(hall: Hall, x: number, z: number, reach: number): (number?, number?)
	local ci = math.clamp(math.floor((x - hall.x0) / hall.cell) + 1, 1, hall.nx)
	local cj = math.clamp(math.floor((z - hall.z0) / hall.cell) + 1, 1, hall.nz)
	if openCell(hall, ci, cj) then
		return ci, cj
	end
	for ring = 1, reach do
		local best: number? = nil
		local bi, bj = 0, 0
		for dj = -ring, ring do
			for di = -ring, ring do
				if math.max(math.abs(di), math.abs(dj)) == ring and openCell(hall, ci + di, cj + dj) then
					local p = centre(hall, ci + di, cj + dj)
					local d = (p.x - x) ^ 2 + (p.z - z) ^ 2
					if best == nil or d < best then
						best, bi, bj = d, ci + di, cj + dj
					end
				end
			end
		end
		if best then
			return bi, bj
		end
	end
	return nil, nil
end

-- Can a visitor walk straight from a to b (every point of the line on a walkable cell)?
local function clearLine(hall: Hall, a: Point, b: Point): boolean
	local dx, dz = b.x - a.x, b.z - a.z
	local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dz * dz) / (hall.cell * 0.34)))
	for k = 0, steps do
		local t = k / steps
		if not Visitors.free(hall, a.x + dx * t, a.z + dz * t) then
			return false
		end
	end
	return true
end

-- Is this a spot a visitor may stop at: walkable, clear of the podiums and the walls, out of the door's way and off
-- the desk's spot?
local function usable(hall: Hall, x: number, z: number): boolean
	local T = tune()
	local input = hall.input
	if not Visitors.free(hall, x, z) or solidAt(input, x, z, T.Margin * 0.75) then
		return false
	end
	local path = input.doorPath
	if path and inRect(path, x, z, 0.5) then
		return false
	end
	local desk = input.desk
	return not (desk and onPodium(desk, x, z, T.DeskClear))
end

function Visitors.spot(hall: Hall, stand: number, roll: number?): Spot?
	local p = hall.podiums[stand]
	if not p then
		return nil
	end
	local T = tune()
	local r = math.rad(p.yaw)
	local fx, fz = -math.sin(r), -math.cos(r) -- the way its piece looks (to its aisle)
	local ax, az = -fz, fx -- across it
	local front = p.sz / 2 + T.View
	local side = p.sx / 2 + T.View
	local shift = (unit(roll) - 0.5) * p.sx * 0.5 -- (a little to one side: two visitors never on one spot)
	local candidates: { { number } } = {
		{ fx * front + ax * shift, fz * front + az * shift },
		{ fx * front - ax * shift, fz * front - az * shift },
		{ fx * front, fz * front },
		{ ax * side, az * side },
		{ -ax * side, -az * side },
		{ -fx * front, -fz * front },
	}
	for _, c in candidates do
		local x, z = p.x + c[1], p.z + c[2]
		if usable(hall, x, z) then
			return { x = x, z = z, faceX = p.x, faceZ = p.z }
		end
	end
	return nil
end

-- A* on the grid (8 ways, no corner cut): the cells from the start to the goal (their numbers), nil for no way.
local function search(hall: Hall, si: number, sj: number, gi: number, gj: number): { number }?
	local nx = hall.nx
	local start, goal = si + (sj - 1) * nx, gi + (gj - 1) * nx
	local cost: { [number]: number } = { [start] = 0 }
	local came: { [number]: number } = {}
	local closed: { [number]: boolean } = {}
	local heapF: { number } = {}
	local heapN: { number } = {}
	local function push(f: number, n: number)
		local k = #heapF + 1
		heapF[k], heapN[k] = f, n
		while k > 1 do
			local up = k // 2
			if heapF[up] <= heapF[k] then
				break
			end
			heapF[up], heapF[k] = heapF[k], heapF[up]
			heapN[up], heapN[k] = heapN[k], heapN[up]
			k = up
		end
	end
	local function pop(): number
		local top = heapN[1]
		local last = #heapF
		heapF[1], heapN[1] = heapF[last], heapN[last]
		heapF[last], heapN[last] = nil :: any, nil :: any
		local k, size = 1, last - 1
		while true do
			local l, r = k * 2, k * 2 + 1
			local small = k
			if l <= size and heapF[l] < heapF[small] then
				small = l
			end
			if r <= size and heapF[r] < heapF[small] then
				small = r
			end
			if small == k then
				break
			end
			heapF[small], heapF[k] = heapF[k], heapF[small]
			heapN[small], heapN[k] = heapN[k], heapN[small]
			k = small
		end
		return top
	end
	local function guess(i: number, j: number): number
		local dx, dz = math.abs(i - gi), math.abs(j - gj)
		return math.max(dx, dz) + (SQRT2 - 1) * math.min(dx, dz)
	end
	push(guess(si, sj), start)
	while #heapF > 0 do
		local n = pop()
		if n == goal then
			local out = { n }
			while came[n] do
				n = came[n]
				table.insert(out, 1, n)
			end
			return out
		end
		if not closed[n] then
			closed[n] = true
			local i, j = (n - 1) % nx + 1, (n - 1) // nx + 1
			for dj = -1, 1 do
				for di = -1, 1 do
					if (di ~= 0 or dj ~= 0) and openCell(hall, i + di, j + dj) and (di == 0 or dj == 0 or (openCell(hall, i + di, j) and openCell(hall, i, j + dj))) then
						local m = (i + di) + (j + dj - 1) * nx
						local step = cost[n] + (if di ~= 0 and dj ~= 0 then SQRT2 else 1)
						if not closed[m] and (cost[m] == nil or step < cost[m] - 1e-9) then
							cost[m] = step
							came[m] = n
							push(step + guess(i + di, j + dj), m)
						end
					end
				end
			end
		end
	end
	return nil
end

function Visitors.route(hall: Hall, from: Point, to: Point): { Point }?
	local si, sj = nearestOpen(hall, from.x, from.z, 3)
	local gi, gj = nearestOpen(hall, to.x, to.z, 3)
	if not si or not sj or not gi or not gj then
		return nil
	end
	local cells = search(hall, si, sj, gi, gj)
	if not cells then
		return nil
	end
	local goal: Point = if Visitors.free(hall, to.x, to.z) then { x = to.x, z = to.z } else centre(hall, gi, gj)
	local points: { Point } = {}
	local startFree = Visitors.free(hall, from.x, from.z)
	table.insert(points, if startFree then { x = from.x, z = from.z } else centre(hall, si, sj))
	for index = 2, #cells - 1 do
		local n = cells[index]
		table.insert(points, centre(hall, (n - 1) % hall.nx + 1, (n - 1) // hall.nx + 1))
	end
	table.insert(points, goal)
	-- the legs: from each corner as far on as the line stays walkable
	local legs: { Point } = {}
	if not startFree then
		table.insert(legs, points[1]) -- (off the grid's free cells: first onto it)
	end
	local anchor = 1
	while anchor < #points do
		local reach = anchor + 1
		for k = #points, anchor + 2, -1 do
			if clearLine(hall, points[anchor], points[k]) then
				reach = k
				break
			end
		end
		table.insert(legs, points[reach])
		anchor = reach
	end
	return legs
end

function Visitors.doorway(hall: Hall, side: number): Doorway
	local T = tune()
	local door = hall.input.door
	local s = if side < 0 then -1 else 1
	local along = math.max(0, math.min(door.width / 2 - T.DoorEdge, T.DoorSide))
	local x = door.x + s * along
	local inner = hall.input.inside.z1 - T.Margin - hall.cell
	local i, j = nearestOpen(hall, x, inner, 4)
	local inside: Point = if i and j then centre(hall, i, j) else { x = x, z = inner }
	return {
		outside = { x = door.x + s * T.Outside[1], z = door.z + T.Outside[2] },
		threshold = { x = x, z = door.z + T.Threshold },
		inside = inside,
	}
end

-- ── The words ───────────────────────────────────────────────────────────────

local LINES: { [string]: { string } } = {
	greet = { "What a place!", "So this is the ZDC showroom!", "Let's have a look around." },
	look = { "Ooh, {a} {name}!", "Look at this {name}!", "Now that's a fine {name}.", "My gran had {a} {name} just like this.", "Is that a real {name}?", "What a lovely {name}…" },
	offer = { "I'll give you {price} for that {name}!", "{price} for the {name}? Deal?", "I must have it. {price} for the {name}?" },
	sold = { "Pleasure doing business!", "It's mine! Thank you!", "Wonderful, thank you!" },
	declined = { "No worries, I'll keep looking.", "Fair enough!", "Maybe next time." },
	expired = { "Never mind, then.", "Oh well. Maybe next time." },
	gone = { "Oh, it's gone!", "Hm, somebody was quicker." },
}
-- How often a visitor says something at each event (the rest of the time it keeps quiet).
local SAY_CHANCE: { [string]: number } = { greet = 0.35 }

local function article(word: string): string
	return if string.find(string.lower(string.sub(word, 1, 1)), "[aeiou]") then "an" else "a"
end

function Visitors.say(event: string, roll: number, name: string?, price: number?): string?
	local list = LINES[event]
	if not list then
		return nil
	end
	local chance = SAY_CHANCE[event]
	local u = unit(roll)
	if chance and u >= chance then
		return nil
	end
	local pick = if chance then u / chance else u
	local text = list[math.floor(pick * #list) + 1]
	local lower = if name then string.lower(name) else "piece"
	text = string.gsub(text, "{a}", article(lower))
	text = string.gsub(text, "{name}", function()
		return lower
	end)
	text = string.gsub(text, "{price}", function()
		return Market.money(price or 0)
	end)
	return text
end

function Visitors.toast(who: string, price: number, name: string): string
	return `🤝 The {string.lower(who)} offers {Market.money(price)} for your {name}`
end

function Visitors.cardLines(offer: Offer): { who: string, price: string, item: string, market: string }
	local more = if offer.base > 0 then math.floor((offer.price / offer.base - 1) * 100 + 0.5) else 0
	return {
		who = `The {string.lower(offer.who)} offers`,
		price = Market.money(offer.price),
		item = `for your {offer.name}`,
		market = `Market price {Market.money(offer.base)} · +{more}%`,
	}
end

local function shortString(value: any, most: number): boolean
	return type(value) == "string" and #value >= 1 and #value <= most
end

function Visitors.readOffer(raw: any): Offer?
	if type(raw) ~= "table" or not shortString(raw.id, MAX_ID) or not shortString(raw.name, MAX_NAME) or not shortString(raw.item, MAX_ID)
		or not shortString(raw.who, MAX_ID) then
		return nil
	end
	local price, base, seconds = raw.price, raw.base, raw.seconds
	if not finite(price) or price ~= math.floor(price) or price < 1 or price > MAX_PRICE or not finite(base) or base < 0 or base > MAX_PRICE
		or not finite(seconds) or seconds < 0 or seconds > 600 then
		return nil
	end
	return {
		id = raw.id,
		name = raw.name,
		item = raw.item,
		price = price,
		base = base,
		who = raw.who,
		seconds = seconds,
		rarity = if shortString(raw.rarity, MAX_ID) then raw.rarity else nil,
		market = if raw.market == "hot" or raw.market == "cold" then raw.market :: string else nil,
	}
end

return Visitors
