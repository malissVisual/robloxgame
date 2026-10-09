--!strict
-- 6.15, the fixed missions (the owner: "When you do missions, I want them to be about a number of zombies, and you have
-- to complete it, so the mission is always the same, not random."). Every mission plays the same route with the same
-- enemies at the same spots: every start, every replay, every player. Pure (Config, Map, Missions: no Roblox services;
-- tests/missionplan_test.luau), so the server, the MISSIONS window and the tests work out the same answers.
--
--   MissionPlan.seed(id)          a stable number from the mission id: the mission's dice (Map.lcg)
--   MissionPlan.origin()          where every mission's route is measured from: the depot (Map.Depot), never where START
--                                 was pressed
--   MissionPlan.route(def)        the addresses of its stops, rolled with those dice: the pick-ups (pickupAt, else an
--                                 address in the band server/Jobs.luau used round you, now round the depot; a rush's
--                                 too: it was "an address near you"), then the drops (dropAt for the last, else
--                                 addresses on the way). nil when a place is missing.
--   MissionPlan.parts(def)        how many enemies of which kind at which anchor, without the places (the MISSIONS
--                                 window's "🧟 20 zombies"; MissionPlan.size: the total and its word)
--   MissionPlan.make(def, stops)  the whole plan for the stops' circles: its groups (the anchor, the kind, the count, one
--                                 spot an enemy, HOLD OUT's wave), the total and its word: ZOMBIES, or ENEMIES when
--                                 bandits or gunners are in it
--
-- The counts (Config.Missions.Fixed; from the tier, the twists and the chapter, never the crew or the dice):
--   * the stops       Stops[tier] zombies (+ PerStop a stop past two), the last drop's horde Weight.Drop of them, a
--                     pick-up Weight.Pickup, a drop on the way Weight.OnTheWay; the tier's Kinds mix them
--   * guarded         HOT ZONE: the stops' zombies × Guarded, the pick-ups and the drops on the way × GuardedStop (a
--                     bigger horde at every stop, the biggest still at the drop)
--   * hunted          HUNTED: Roadblocks[tier] (× the mission's banditBoost) bandit roadblocks at fixed points of the
--                     route, RoadblockSize[tier] bandits each (a gunner among them from ★★★); no random chases
--   * gunner          SHOTGUN SEAT: Gunners[tier] gunners posted by the road (GunnerPosts points at most): something
--                     for the passengers to shoot
--   * defend          HOLD OUT: Defend[tier] zombies come at the last drop in #DefendSplit waves (the last the
--                     biggest); the hold-out clock stays, the count is fixed
--   * quiet, spotless, lift, pair, switches, night: their own rules, no enemies of their own
--   Everything × the chapter's growth (1 + ChapterGrow a story chapter after the first), then at most Max (every part
--   shrunk alike, each at least one), at least Min.
-- Where: a stop's enemies stand on the road by its circle (a yard's in a ring round it); a route point is on the road
-- at an even share of the route between the stops, FromStop studs from each; HOLD OUT's waves come from DefendRing
-- studs round the last drop, on the roads. Never in the safe zone or the water.

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local Missions = require(script.Parent.Missions)

local MissionPlan = {}

local Fixed = Config.Missions.Fixed

export type Spot = { x: number, z: number }

-- A stop of the mission as the plan needs it: its kind ("pickup" | "drop"), its circle (x, z), the way out of its block
-- to the road (nx, nz; 0, 0: a yard), its place's name.
export type StopInfo = { kind: string, x: number, z: number, nx: number, nz: number, name: string }

-- How many of one kind at one anchor (MissionPlan.parts).
export type Part = {
	anchor: string, -- "pickup" | "drop" (a stop's horde) | "route" (a point on the way) | "defend" (HOLD OUT's waves)
	stop: number, -- a stop's: its index in the stops (pick-ups first); defend: the last stop; route: 0 (make: the next stop)
	kind: string, -- a Config.Zombies kind
	count: number,
	wave: number?, -- defend: its wave, 1 …
	point: number?, -- route: its point, 1 …
	roadblock: boolean?, -- route: HUNTED's bandits behind a bandit car across the lane
}

-- A group of the plan: a part with its places.
export type Group = {
	id: number,
	anchor: string,
	stop: number, -- route: the stop it lies before
	kind: string,
	count: number,
	wave: number?,
	point: number?,
	x: number, -- the anchor's point (a stop's circle, the road at a route point; defend: the last stop's circle)
	z: number,
	spots: { Spot }, -- one an enemy
	road: boolean, -- stands at the road's height (a route point, HOLD OUT's waves); else on the stop's ground
	place: string, -- where, in words (the NEXT card while clearing)
	roadblock: { x: number, z: number, ax: number, az: number, lane: number }?, -- the bandit car: the road there, its way, the lane
}

export type Plan = {
	id: string,
	total: number,
	label: string, -- "ZOMBIES", or "ENEMIES" with bandits or gunners in it
	waves: number, -- HOLD OUT's waves (0: none)
	groups: { Group },
}

type Def = Missions.MissionDef

-- ── The dice ───────────────────────────────────────────────────────────────

-- A stable number for a mission id (the same on every server, every day): 1 … 2147483646.
function MissionPlan.seed(id: string): number
	local hash = 7
	for index = 1, #id do
		hash = (hash * 131 + string.byte(id, index)) % 2147483629
	end
	return hash % 2147483646 + 1
end

-- The mission's dice from a seed: Map.lcg with its first rolls thrown away (two ids one letter apart start with
-- seeds close together, and an LCG's first rolls of close seeds are close too).
function MissionPlan.dice(seed: number): () -> number
	local rand = Map.lcg(seed)
	for _ = 1, 4 do
		rand()
	end
	return rand
end

-- Where every mission's route is measured from: the depot's middle.
function MissionPlan.origin(): Spot
	return { x = Map.Depot.x, z = Map.Depot.z }
end

-- ── The route ──────────────────────────────────────────────────────────────

local function placeAddress(id: string): Map.Address?
	local name: string? = nil
	for _, place in Map.Places do
		if place.id == id then
			name = place.name
		end
	end
	for _, address in Map.addresses() do
		if address.poi and address.name == name then
			return address
		end
	end
	return nil
end

-- An ordinary address (no named place) `low` … `high` (manhattan) from a point, rolled with `rand`; with none in the
-- band, the one closest to it (server/Jobs.luau addressAround's rule).
local function around(x: number, z: number, low: number, high: number, avoid: { Map.Address }, rand: () -> number): Map.Address?
	local fits: { Map.Address } = {}
	local closest: Map.Address? = nil
	local closestGap = math.huge
	for _, address in Map.addresses() do
		if address.poi or table.find(avoid, address) then
			continue
		end
		local d = Map.manhattan(x, z, address.x, address.z)
		if d >= low and d <= high then
			table.insert(fits, address)
		end
		local gap = if d < low then low - d else d - high
		if gap < closestGap then
			closest, closestGap = address, gap
		end
	end
	if #fits > 0 then
		return fits[math.floor(rand() * #fits) + 1]
	end
	return closest
end

-- The addresses of the mission's stops: the pick-ups, then the drops (the bands of server/Jobs.luau jobOffer, from the
-- depot instead of the player). The same every time for a mission id; nil when a place is missing.
function MissionPlan.route(def: Def): { Map.Address }?
	local rand = MissionPlan.dice(MissionPlan.seed(def.id))
	local origin = MissionPlan.origin()
	local x, z = origin.x, origin.z
	local avoid: { Map.Address } = {}
	local out: { Map.Address } = {}
	local rush = def.timeLimit ~= nil
	for n = 1, def.pickups do
		local low = if n == 1 then (if rush then 100 else 120) else 90
		local high = if n == 1 then (if rush then 350 else 450) else 280
		local address = if def.pickupAt then placeAddress(def.pickupAt) else around(x, z, low, high, avoid, rand)
		if not address then
			return nil
		end
		table.insert(avoid, address)
		table.insert(out, address)
		x, z = address.x, address.z
	end
	for n = 1, def.drops do
		local last = n == def.drops
		local low = if def.drops > 1 then 150 elseif rush then 300 else 450
		local high = if def.drops > 1 then 450 elseif rush then 800 else 1100
		local address = if last and def.dropAt then placeAddress(def.dropAt) else around(x, z, low, high, avoid, rand)
		if not address then
			return nil
		end
		table.insert(avoid, address)
		table.insert(out, address)
		x, z = address.x, address.z
	end
	return out
end

-- The route's stops as the plan needs them, from the addresses (the tests and the MISSIONS window; the server gives
-- the real circles: a home's or a storefront's park).
function MissionPlan.stopsOf(def: Def): { StopInfo }?
	local addresses = MissionPlan.route(def)
	if not addresses then
		return nil
	end
	local out: { StopInfo } = {}
	for index, address in addresses do
		table.insert(out, { kind = if index <= def.pickups then "pickup" else "drop", x = address.x, z = address.z, nx = address.nx, nz = address.nz, name = address.name })
	end
	return out
end

-- ── The counts ─────────────────────────────────────────────────────────────

-- `total` shared by `weights` (the largest remainders; a tie to the first), every share at least `least`.
local function share(total: number, weights: { number }, least: number): { number }
	local count = #weights
	local out: { number } = table.create(count, least)
	local left = math.floor(total + 0.5) - least * count
	if count == 0 or left <= 0 then
		return out
	end
	local sum = 0
	for _, weight in weights do
		sum += math.max(0, weight)
	end
	if sum <= 0 then
		out[1] += left
		return out
	end
	local rests: { { index: number, rest: number } } = {}
	local given = 0
	for index, weight in weights do
		local exact = left * math.max(0, weight) / sum
		local whole = math.floor(exact + 1e-9)
		out[index] += whole
		given += whole
		table.insert(rests, { index = index, rest = exact - whole })
	end
	table.sort(rests, function(a, b)
		if math.abs(a.rest - b.rest) > 1e-9 then
			return a.rest > b.rest
		end
		return a.index < b.index
	end)
	for k = 1, left - given do
		out[rests[k].index] += 1
	end
	return out
end

-- `count` zombies mixed by `kinds` ({ kind = weight }), the kinds by name (a fixed order): only the ones that get any.
local function mix(count: number, kinds: { [string]: number }): { { kind: string, count: number } }
	local names: { string } = {}
	for name in kinds do
		table.insert(names, name)
	end
	table.sort(names)
	local weights: { number } = {}
	for _, name in names do
		table.insert(weights, kinds[name])
	end
	local out: { { kind: string, count: number } } = {}
	for index, n in share(count, weights, 0) do
		if n > 0 then
			table.insert(out, { kind = names[index], count = n })
		end
	end
	return out
end

local function round(value: number): number
	return math.floor(value + 0.5)
end

local function tierOf(def: Def): number
	return math.clamp(math.floor(def.tier or 1), 1, #Fixed.Stops)
end

-- The story chapter a campaign is (First Shift 1 … Last Convoy 10); the DUO side story counts as the story chapter at
-- its level.
function MissionPlan.chapter(campaignId: string): number
	local number = 0
	for _, entry in Missions.Campaigns do
		if not entry.duo then
			number += 1
		end
		if entry.id ~= campaignId then
			continue
		end
		if not entry.duo then
			return number
		end
		local at = 0
		for _, other in Missions.Campaigns do
			if not other.duo then
				at += 1
				if other.level >= entry.level then
					return at
				end
			end
		end
		return math.max(1, at)
	end
	return 1
end

-- How much more of everything a chapter has (1 for the first).
function MissionPlan.growth(def: Def): number
	return 1 + Fixed.ChapterGrow * (MissionPlan.chapter(def.campaign) - 1)
end

local function hasTwist(def: Def, twist: string): boolean
	local twists: { string } = def.twists or {}
	return table.find(twists, twist) ~= nil
end

-- One anchor's enemies before they are mixed into kinds: a stop's horde, a route point, a HOLD OUT wave.
type Piece = { anchor: string, stop: number, count: number, wave: number?, point: number?, roadblock: boolean?, kind: string? }

-- How many enemies of which kind at which anchor (see the header): the same for every start of the mission.
function MissionPlan.parts(def: Def): { Part }
	local tier = tierOf(def)
	local grow = MissionPlan.growth(def)
	local guarded = hasTwist(def, "guarded")
	local pickups = math.max(0, def.pickups)
	local stops = pickups + math.max(1, def.drops)
	local pieces: { Piece } = {}
	-- The stops' hordes.
	local weights: { number } = {}
	for n = 1, stops do
		local weight = if n == stops then Fixed.Weight.Drop elseif n <= pickups then Fixed.Weight.Pickup else Fixed.Weight.OnTheWay
		table.insert(weights, if guarded and n < stops then weight * Fixed.GuardedStop else weight)
	end
	local zombies = round((Fixed.Stops[tier] + Fixed.PerStop * math.max(0, stops - 2)) * grow * (if guarded then Fixed.Guarded else 1))
	for n, count in share(math.max(stops, zombies), weights, 1) do
		table.insert(pieces, { anchor = if n <= pickups then "pickup" else "drop", stop = n, count = count })
	end
	-- HUNTED: the roadblocks on the route.
	local point = 0
	if hasTwist(def, "hunted") then
		local blocks = math.clamp(round(Fixed.Roadblocks[tier] * math.max(1, def.banditBoost or 1)), 1, Fixed.RoadblocksMax)
		local size = math.max(1, round(Fixed.RoadblockSize[tier] * grow))
		for _ = 1, blocks do
			point += 1
			table.insert(pieces, { anchor = "route", stop = 0, count = size, point = point, roadblock = true })
		end
	end
	-- SHOTGUN SEAT: gunners by the road.
	if hasTwist(def, "gunner") then
		local gunners = math.max(1, round(Fixed.Gunners[tier] * grow))
		local posts = math.min(Fixed.GunnerPosts, gunners)
		for _, count in share(gunners, table.create(posts, 1), 0) do
			if count > 0 then
				point += 1
				table.insert(pieces, { anchor = "route", stop = 0, count = count, point = point, kind = "gunner" })
			end
		end
	end
	-- HOLD OUT: the waves at the last drop.
	if hasTwist(def, "defend") then
		local split = Fixed.DefendSplit
		for wave, count in share(math.max(#split, round(Fixed.Defend[tier] * grow)), split, 1) do
			table.insert(pieces, { anchor = "defend", stop = stops, count = count, wave = wave })
		end
	end
	-- At most Max (every anchor shrunk alike, at least one each), at least Min (the last drop's horde grows).
	local total = 0
	local counts: { number } = {}
	for _, piece in pieces do
		total += piece.count
		table.insert(counts, piece.count)
	end
	if total > Fixed.Max then
		for index, count in share(Fixed.Max, counts, 1) do
			pieces[index].count = count
		end
	elseif total < Fixed.Min then
		pieces[stops].count += Fixed.Min - total
	end
	-- The kinds: a horde or a wave by the tier's mix; a roadblock's bandits with one gunner from ★★★; a post's gunners.
	local parts: { Part } = {}
	for _, piece in pieces do
		local kinds: { { kind: string, count: number } }
		if piece.kind then
			kinds = { { kind = piece.kind, count = piece.count } }
		elseif piece.roadblock then
			local gunners = if tier >= 3 and piece.count >= 2 then 1 else 0
			kinds = { { kind = "bandit", count = piece.count - gunners }, { kind = "gunner", count = gunners } }
		else
			kinds = mix(piece.count, Fixed.Kinds[tier])
		end
		for _, entry in kinds do
			if entry.count > 0 then
				table.insert(parts, {
					anchor = piece.anchor,
					stop = piece.stop,
					kind = entry.kind,
					count = entry.count,
					wave = piece.wave,
					point = piece.point,
					roadblock = piece.roadblock,
				})
			end
		end
	end
	return parts
end

-- Bandits or gunners among these kinds: the HUD says ENEMIES (else ZOMBIES: the soldiers bite, they are zombies too).
function MissionPlan.labelOf(kinds: { string }): string
	for _, kind in kinds do
		local def = Config.Zombies[kind]
		if def and def.ranged then
			return "ENEMIES"
		end
	end
	return "ZOMBIES"
end

-- The mission's enemies in all and the HUD's word for them ("ZOMBIES" / "ENEMIES"), without working out the places.
function MissionPlan.size(def: Def): (number, string)
	local total = 0
	local kinds: { string } = {}
	for _, part in MissionPlan.parts(def) do
		total += part.count
		table.insert(kinds, part.kind)
	end
	return total, MissionPlan.labelOf(kinds)
end

-- ── The places ─────────────────────────────────────────────────────────────

local function bad(x: number, z: number): boolean
	return Map.isSafe(x, z) or Map.inWater(x, z)
end

-- A spot never in the safe zone or the water: else the other side of the anchor, else the anchor itself.
local function settle(x: number, z: number, ax: number, az: number): Spot
	if not bad(x, z) then
		return { x = x, z = z }
	end
	local mx, mz = 2 * ax - x, 2 * az - z
	if not bad(mx, mz) then
		return { x = mx, z = mz }
	end
	return { x = ax, z = az }
end

-- The spots of a stop's `n` enemies: on the road by its circle (spread along it, out from the block), or in a ring
-- round a yard's; shuffled, so the kinds stand mixed.
local function stopSpots(stop: StopInfo, n: number, rand: () -> number): { Spot }
	local out: { Spot } = {}
	local nx, nz = stop.nx, stop.nz
	local length = math.sqrt(nx * nx + nz * nz)
	if length < 0.5 then
		local outer = math.min(Fixed.RingMax, Fixed.Ring[2] + Fixed.RingPer * n)
		local start = rand() * math.pi * 2
		for k = 1, n do
			local angle = start + (k - 1 + (rand() - 0.5) * 0.6) / n * math.pi * 2
			local radius = Fixed.Ring[1] + (outer - Fixed.Ring[1]) * rand()
			table.insert(out, settle(stop.x + math.cos(angle) * radius, stop.z + math.sin(angle) * radius, stop.x, stop.z))
		end
	else
		nx, nz = nx / length, nz / length
		local ax, az = nz, -nx -- along the road
		local half = math.min(Fixed.SpreadAlong, 12 + 1.6 * n)
		for k = 1, n do
			local along = -half + 2 * half * (k - 0.5) / n + (rand() - 0.5) * 3
			local outward = 2 + (Fixed.SpreadOut - 2) * rand()
			table.insert(out, settle(stop.x + ax * along + nx * outward, stop.z + az * along + nz * outward, stop.x, stop.z))
		end
	end
	for k = #out, 2, -1 do
		local other = math.floor(rand() * k) + 1
		out[k], out[other] = out[other], out[k]
	end
	return out
end

local function distance(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

type RoutePoint = { x: number, z: number, ax: number, az: number, width: number, before: number }

local function lineLength(line: { Spot }): number
	local total = 0
	for i = 2, #line do
		total += distance(line[i - 1].x, line[i - 1].z, line[i].x, line[i].z)
	end
	return total
end

-- The route as a line through the stops' circles (`offset`: 1 when it starts at the depot), and the point `at`
-- (0 … 1) of its length: where, the line's way there and the stop it lies before.
local function onLine(line: { Spot }, offset: number, at: number): (number, number, number, number, number)
	local goal = lineLength(line) * at
	for i = 2, #line do
		local a, b = line[i - 1], line[i]
		local d = distance(a.x, a.z, b.x, b.z)
		if goal <= d or i == #line then
			local t = if d > 0 then math.clamp(goal / d, 0, 1) else 0
			local dx, dz = if d > 0 then (b.x - a.x) / d else 1, if d > 0 then (b.z - a.z) / d else 0
			return a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t, dx, dz, i - offset
		end
		goal -= d
	end
	local last = line[#line]
	return last.x, last.z, 1, 0, #line - offset
end

-- `count` points on the roads along the route, each near its even share of it: out of the safe zone and the water,
-- FromStop studs from every stop and 80 from each other (a short route: what it has room for; the depot's leg is
-- added to a route too short for them). The share nearest the even one that fits; else the one farthest from the
-- stops; never one in the safe zone (else by the last stop's circle).
local function routePoints(stops: { StopInfo }, count: number): { RoutePoint }
	local line: { Spot } = {}
	for _, stop in stops do
		table.insert(line, { x = stop.x, z = stop.z })
	end
	local offset = 0
	if #line < 2 or lineLength(line) < (count + 1) * Fixed.FromStop then
		table.insert(line, 1, MissionPlan.origin())
		offset = 1
	end
	local out: { RoutePoint } = {}
	if #line < 2 or #stops == 0 then
		return out
	end
	local room = math.min(Fixed.FromStop, lineLength(line) / (count + 1) * 0.8)
	local candidates: { RoutePoint } = {}
	local shares: { number } = {}
	for step = 1, 24 do
		local at = step / 25
		local px, pz, dx, dz, before = onLine(line, offset, at)
		local rx, rz, ax, az, width = Map.nearestRoad(px, pz)
		if ax * dx + az * dz < 0 then
			ax, az = -ax, -az -- the way the route goes
		end
		table.insert(candidates, { x = rx, z = rz, ax = ax, az = az, width = width, before = math.clamp(before, 1, #stops) })
		table.insert(shares, at)
	end
	for p = 1, count do
		local base = p / (count + 1)
		local best: RoutePoint? = nil
		local bestGap, bestFar = math.huge, -1
		local fallback: RoutePoint? = nil
		for index, point in candidates do
			if bad(point.x, point.z) then
				continue
			end
			local near = math.huge
			for _, stop in stops do
				near = math.min(near, distance(point.x, point.z, stop.x, stop.z))
			end
			local apart = true
			for _, other in out do
				apart = apart and distance(point.x, point.z, other.x, other.z) >= 80
			end
			local gap = math.abs(shares[index] - base)
			if near >= room and apart and gap < bestGap then
				best, bestGap = point, gap
			elseif near > bestFar then
				fallback, bestFar = point, near
			end
		end
		local chosen = best or fallback
		if not chosen then
			local stop = stops[#stops]
			local rx, rz, ax, az, width = Map.nearestRoad(stop.x + 40, stop.z + 40)
			chosen = { x = rx, z = rz, ax = ax, az = az, width = width, before = #stops }
		end
		table.insert(out, chosen :: RoutePoint)
	end
	return out
end

-- The whole plan for the mission's stops (server/Jobs.luau: the circles it made from MissionPlan.route; the tests:
-- MissionPlan.stopsOf). The same stops give the same plan, spot for spot.
function MissionPlan.make(def: Def, stops: { StopInfo }): Plan
	local rand = MissionPlan.dice(MissionPlan.seed(def.id) + 7919) -- (its own dice: the route's stay what they are)
	local parts = MissionPlan.parts(def)
	local groups: { Group } = {}
	local last = math.max(1, #stops)
	local function add(part: Part, x: number, z: number, spots: { Spot }, road: boolean, place: string, stop: number)
		table.insert(groups, {
			id = #groups + 1,
			anchor = part.anchor,
			stop = stop,
			kind = part.kind,
			count = part.count,
			wave = part.wave,
			point = part.point,
			x = x,
			z = z,
			spots = spots,
			road = road,
			place = place,
			roadblock = nil,
		})
	end
	local function stopAt(index: number): StopInfo
		return stops[math.clamp(index, 1, last)] or { kind = "drop", x = MissionPlan.origin().x, z = MissionPlan.origin().z, nx = 0, nz = 0, name = "the drop" }
	end
	-- The stops' hordes: one set of spots a stop, its kinds take them in turn.
	local byStop: { [number]: { Part } } = {}
	local points = 0
	for _, part in parts do
		if part.anchor == "pickup" or part.anchor == "drop" then
			local index = math.clamp(part.stop, 1, last)
			byStop[index] = byStop[index] or {}
			table.insert(byStop[index], part)
		elseif part.anchor == "route" then
			points = math.max(points, part.point or 0)
		end
	end
	for index = 1, last do
		local list = byStop[index]
		if not list then
			continue
		end
		local stop = stopAt(index)
		local n = 0
		for _, part in list do
			n += part.count
		end
		local spots = stopSpots(stop, n, rand)
		local nextSpot = 1
		for _, part in list do
			local mine: { Spot } = {}
			for _ = 1, part.count do
				table.insert(mine, spots[nextSpot])
				nextSpot += 1
			end
			add(part, stop.x, stop.z, mine, false, stop.name, index)
		end
	end
	-- The route's points: HUNTED's roadblocks (the bandits behind a car across the lane), the gunners' posts by the road.
	if points > 0 and #stops > 0 then
		local line = routePoints(stops, points)
		for p, point in ipairs(line) do
			local lane = if rand() < 0.5 then -1 else 1
			local sx, sz = -point.az, point.ax -- across the road
			local cx, cz = point.x + sx * lane * 7, point.z + sz * lane * 7
			local place = `the road to {stopAt(point.before).name}`
			for _, part in parts do
				if part.anchor ~= "route" or part.point ~= p then
					continue
				end
				local mine: { Spot } = {}
				for _ = 1, part.count do
					if part.roadblock then
						local back = 4 + 12 * rand()
						local side = -10 + 20 * rand()
						table.insert(mine, settle(cx + point.ax * back + sx * side, cz + point.az * back + sz * side, point.x, point.z))
					else
						local side = lane * (point.width / 2 + 5)
						local along = -8 + 16 * rand()
						table.insert(mine, settle(point.x + sx * side + point.ax * along, point.z + sz * side + point.az * along, point.x, point.z))
					end
				end
				add(part, point.x, point.z, mine, true, place, point.before)
				if part.roadblock then
					groups[#groups].roadblock = { x = point.x, z = point.z, ax = point.ax, az = point.az, lane = lane }
				end
			end
		end
	end
	-- HOLD OUT's waves: from DefendRing studs round the last drop, on the roads there.
	local waves = 0
	local drop = stopAt(last)
	for _, part in parts do
		if part.anchor ~= "defend" then
			continue
		end
		waves = math.max(waves, part.wave or 0)
		local mine: { Spot } = {}
		local start = rand() * math.pi * 2
		for k = 1, part.count do
			local angle = start + (k - 0.5 + (rand() - 0.5) * 0.5) / part.count * math.pi * 2
			local radius = Fixed.DefendRing[1] + (Fixed.DefendRing[2] - Fixed.DefendRing[1]) * rand()
			local px, pz = drop.x + math.cos(angle) * radius, drop.z + math.sin(angle) * radius
			local rx, rz, ax, az, width = Map.nearestRoad(px, pz)
			local lateral = (rand() - 0.5) * math.max(0, width - 8)
			local sx, sz = rx - az * lateral, rz + ax * lateral
			if bad(sx, sz) or distance(sx, sz, drop.x, drop.z) > Fixed.DefendRing[2] + 60 then
				table.insert(mine, settle(px, pz, drop.x, drop.z))
			else
				table.insert(mine, { x = sx, z = sz })
			end
		end
		add(part, drop.x, drop.z, mine, true, drop.name, last)
	end
	local total = 0
	local kinds: { string } = {}
	for _, group in groups do
		total += group.count
		table.insert(kinds, group.kind)
	end
	return { id = def.id, total = total, label = MissionPlan.labelOf(kinds), waves = waves, groups = groups }
end

return MissionPlan
