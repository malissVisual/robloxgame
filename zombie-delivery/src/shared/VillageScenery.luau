--!strict
-- 8.9 SANDBOX on the map; 9.4 the countryside (design/countryside/plan.py, plan.json); 10.6 the floating islands
-- (design/islands/plan.py, plan.json): where the map's art stands, as plain numbers, from shared/SandboxMap.luau's
-- ISLANDS section (tools/islands/sandboxmap.py writes it from the plan) and its Houses: shared/VillageLooks.luau's houses, the D5, the trees and the fields, shared/CountryLooks.luau's landmarks,
-- hedges, fences and the stream. Pure (no Roblox at its top level), deterministic: server/VillageWorld.luau makes the
-- parts, client/VillageTraffic.luau drives the D5's cars on its lanes, tests/villageworld_test.luau checks it all. Its
-- numbers are Config.VillageWorld's (and Config.Village's and Config.Country's, the art kits').
--
--   The houses     the places to empty but the farmstead (SandboxMap.Houses 2 … 6: server/SandboxWorld.luau builds
--                  them, their doors walked in; the farmstead its own look), each in its box turned by its yaw, rich,
--                  its dice its id's (VillageLooks.seedOf), in its look: VillageLooks.house's kind (9.5 every place's
--                  own: lookOf)
--   The landmarks  SandboxMap.Landmarks, each looking its own yaw: CountryLooks' kinds (the spots' surroundings, the
--                  railway and its halt), else VillageLooks' (the D5); the D5 and the railway are kept on every client
--                  (far = true: the D5's cars run on it, the railway crosses the whole map)
--   The trees      the tree lines' (windbreaks, alleys: VillageLooks.lineTrees), the orchard's (VillageLooks.orchard)
--                  and the woods' (a jittered grid, Config.Country.Woods), each where treeRule lets its crown stand:
--                  else moved off its spot (Config.VillageWorld.Trees: Step studs at a time across its line, then
--                  along it, at most Nudge), else left out
--   The lines      the hedges and fences of SandboxMap.TreeLines (CountryLooks.line; 10.6 every map island's low rim hedge
--                  on its walls)
--   The streams    SandboxMap.Streams (CountryLooks.stream: its bed and its water; 10.6 only the pieces on an island:
--                  the millrace ends at its island's edge, its waterfall a landmark)
--   The fields     SandboxMap.Fields, a tile each (VillageLooks.field: the ground in its crop's colour, its rows)
--   The far view   VillageLooks.horizon round SandboxMap.Bounds but its far roofs and church tower (no village on the
--                  horizon either), the railway going on past them (CountryLooks.farRails); 9.7: none while there are
--                  run zones (SandboxMap.Zones; 10.6 the sky round the islands)
-- 10.6 the floating islands (design/islands/plan.py): every piece on the map stands on its island's top
-- (server/VillageWorld.luau adds SandboxMap.groundAt to its y).
--
--   VillageScenery.houses(extra?)    { Placed }: the places to empty but the farmstead (rich): kind (the look drawn),
--                                    box, yaw, seed, opts, ids, street (extra: their PlanHouses, enter()'s; the same)
--   VillageScenery.enter()           the places to empty but the farmstead as VillageLooks PlanHouses (kind: lookOf)
--   VillageScenery.lookOf(look)      the look VillageLooks.house draws for a place's look: itself when VillageLooks
--                                    lists it (its Houses, 9.5 its Countryside), else "old" (an unknown one still
--                                    builds)
--   VillageScenery.emptied(placed)   the place to empty a Placed holds (SandboxMap.Houses'; nil: none)
--   VillageScenery.landmarks()       { Mark }: id, name, kind, box, yaw, seed, opts, far
--   VillageScenery.pieces(thing)     a house's or a landmark's pieces on the map (VillageLooks.place)
--   VillageScenery.trees()           { TreeSpot }: kind, x, z, seed, its crown's radius and height, where it is from
--                                    (a line, "orchard" or a wood's id)
--   VillageScenery.treeRule(x, z, r) why a crown r wide may not stand there (nil: it may): SandboxScenery.treeRule's
--                                    reasons (10.6 "edge": off an island's grass), then "house", "landmark", "auction"
--                                    (Keep studs off each), "stream" (its crown off the water by Config.Country.Streams
--                                    .Clear), "clearing" (in a wood's), 9.7 "zone" (10.6 over a map island's walls and
--                                    their rim hedge)
--   VillageScenery.onIsland(x, z, grow)   10.6: on an island's top (grown by `grow`)
--   VillageScenery.lines()           the hedges' and fences' pieces on the map
--   VillageScenery.streams()         the streams' pieces on the map
--   VillageScenery.fields()          { FieldTile }: kind, rect, seed
--   VillageScenery.lanes()           { Lane }: the D5's four lanes (x, the road's top y, z0 … z1 run Beyond past the
--                                    Bounds, dz: -1 northbound, 1 southbound; right-hand traffic)
--   VillageScenery.far()             the far view's pieces
--   VillageScenery.streamDistance(x, z)   how far (x, z) is from the nearest stream's middle line, less its half width
--                                    (≤ 0: in its water)

local AuctionHouseLayout = require(script.Parent.AuctionHouseLayout)
local Config = require(script.Parent.Config)
local CountryLooks = require(script.Parent.CountryLooks)
local SandboxMap = require(script.Parent.SandboxMap)
local SandboxScenery = require(script.Parent.SandboxScenery)
local VillageLooks = require(script.Parent.VillageLooks)

local VillageScenery = {}

export type Rect = SandboxMap.Rect
export type Placed = { id: string, kind: string, box: Rect, yaw: number, seed: number, opts: VillageLooks.Options, ids: { string }, street: string }
export type Mark = { id: string, name: string, kind: string, box: Rect, yaw: number, seed: number, opts: VillageLooks.Options, far: boolean }
export type TreeSpot = { kind: string, x: number, z: number, seed: number, radius: number, height: number, from: string }
export type FieldTile = { kind: string, rect: Rect, seed: number }
export type Lane = { x: number, y: number, z0: number, z1: number, dz: number }

local MAP = SandboxMap
local W = Config.VillageWorld
local CW = Config.Country

local function rect(r: { x0: number, x1: number, z0: number, z1: number }): Rect
	return { x0 = r.x0, x1 = r.x1, z0 = r.z0, z1 = r.z1 }
end

-- ── The houses and the landmarks ───────────────────────────────────────────

function VillageScenery.lookOf(look: string): string
	-- (9.5: every look of the map's is VillageLooks' now, the family houses' or the countryside's)
	local known = table.find(VillageLooks.Houses, look) ~= nil or table.find(VillageLooks.Countryside, look) ~= nil
	return if known then look else "old"
end

local enterCache: { VillageLooks.PlanHouse }? = nil
local houseCache: { Placed }? = nil

-- The places to empty but the farmstead (its own look) as PlanHouses (their look, box and yaw; the same list every time).
function VillageScenery.enter(): { VillageLooks.PlanHouse }
	if enterCache then
		return enterCache
	end
	local list: { VillageLooks.PlanHouse } = {}
	for index, h in MAP.Houses do
		if index > 1 then
			table.insert(list, { id = h.id, kind = VillageScenery.lookOf(h.look), box = rect(h.box), yaw = h.yaw, step = 1, enter = true, street = h.street })
		end
	end
	enterCache = list
	return list
end

-- (extra: today's callers hand enter() in; the list is the same either way)
function VillageScenery.houses(extra: { VillageLooks.PlanHouse }?): { Placed }
	if houseCache then
		return houseCache
	end
	local list: { Placed } = {}
	for _, h in VillageScenery.enter() do
		table.insert(list, { id = h.id, kind = h.kind, box = h.box, yaw = h.yaw, seed = VillageLooks.seedOf(h.id), opts = { rich = true }, ids = { h.id }, street = h.street or "" })
	end
	houseCache = list
	return list
end

function VillageScenery.emptied(placed: Placed): SandboxMap.House?
	for _, id in placed.ids do
		local h = MAP.house(id)
		if h and h ~= MAP.House then
			return h
		end
	end
	return nil
end

local FAR = { motorway = true, railway = true } -- (kept on every client)

local markCache: { Mark }? = nil

function VillageScenery.landmarks(): { Mark }
	if markCache then
		return markCache
	end
	local list: { Mark } = {}
	for _, l in MAP.Landmarks do
		table.insert(list, { id = l.id, name = l.name, kind = l.kind, box = rect(l), yaw = l.yaw, seed = VillageLooks.seedOf(l.id), opts = {}, far = FAR[l.kind] == true })
	end
	markCache = list
	return list
end

-- A house's or a landmark's pieces on the map.
function VillageScenery.pieces(thing: Placed | Mark): { VillageLooks.Piece }
	local made
	if (thing :: any).ids then
		made = VillageLooks.house(thing.kind, thing.box, thing.yaw, thing.seed, thing.opts)
	elseif table.find(CountryLooks.Landmarks, thing.kind) then
		made = CountryLooks.landmark(thing.kind, thing.box, thing.yaw, thing.seed)
	else
		made = VillageLooks.landmark(thing.kind, thing.box, thing.yaw, thing.seed, thing.opts)
	end
	return VillageLooks.place(made, thing.box, thing.yaw)
end

-- ── The trees ──────────────────────────────────────────────────────────────

-- How far (x, z) is from a segment.
local function segmentDistance(x: number, z: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local t = math.clamp(((x - ax) * dx + (z - az) * dz) / math.max(dx * dx + dz * dz, 1e-9), 0, 1)
	return math.sqrt((x - ax - dx * t) ^ 2 + (z - az - dz * t) ^ 2)
end

function VillageScenery.streamDistance(x: number, z: number): number
	local best = math.huge
	for _, s in MAP.Streams do
		for i = 1, #s.points - 1 do
			local a, b = s.points[i], s.points[i + 1]
			best = math.min(best, segmentDistance(x, z, a.x, a.z, b.x, b.z) - s.width / 2)
		end
	end
	return best
end

function VillageScenery.treeRule(x: number, z: number, r: number): string?
	local why = SandboxScenery.treeRule(x, z, r)
	if why then
		return why
	end
	local keep = r + W.Trees.Keep
	for _, h in MAP.Houses do -- (the places' boxes; their lots and curbs SandboxScenery.treeRule's)
		if SandboxScenery.rectDistance(h.box, x, z) < keep then
			return "house"
		end
	end
	for _, l in MAP.Landmarks do
		if SandboxScenery.rectDistance(rect(l), x, z) < keep then
			return "landmark"
		end
	end
	-- (the Auction House's site: built while Config.Auction.On, its place kept either way)
	if SandboxScenery.rectDistance(AuctionHouseLayout.site(), x, z) < keep then
		return "auction"
	end
	if VillageScenery.streamDistance(x, z) < r + CW.Streams.Clear then
		return "stream"
	end
	for _, wood in MAP.Woods do
		for _, c in wood.clearings do
			if SandboxScenery.rectDistance(c, x, z) < r * 0.5 then
				return "clearing"
			end
		end
	end
	-- 9.7: a crown never over a run zone's edge (10.6: a map island's walls and its rim hedge on them)
	for _, zone in MAP.Zones do
		local q = zone.rect
		local inside = x > q.x0 and x < q.x1 and z > q.z0 and z < q.z1
		local edge = if inside then math.min(x - q.x0, q.x1 - x, z - q.z0, q.z1 - z) else SandboxScenery.rectDistance(q, x, z)
		if edge < r + CW.Lines.Hedge.Width then
			return "zone"
		end
	end
	return nil
end

-- 10.6: is (x, z) on an island's top (grown by `grow`)?
function VillageScenery.onIsland(x: number, z: number, grow: number): boolean
	return MAP.islandAt(x, z, grow) ~= nil
end

local TREE_LINES = { windbreak = true, alley = true } -- (the tree lines of trees; the rest, hedges and fences, are lines())

local treeCache: { TreeSpot }? = nil

function VillageScenery.trees(): { TreeSpot }
	if treeCache then
		return treeCache
	end
	local T = W.Trees
	local list: { TreeSpot } = {}
	local function fits(x: number, z: number, radius: number): boolean
		if VillageScenery.treeRule(x, z, radius) then
			return false
		end
		for _, t in list do
			local apart = (t.radius + radius) * T.Apart
			if (t.x - x) ^ 2 + (t.z - z) ^ 2 < apart * apart then
				return false
			end
		end
		return true
	end
	-- a spot, or Step by Step off it: across its line (ax, az) first, either side, then along it
	local function plant(spot: VillageLooks.Spot, ax: number, az: number, from: string)
		local height, radius = VillageLooks.treeSize(spot.kind, spot.seed)
		local tries: { { number } } = { { 0, 0 } }
		for d = T.Step, T.Nudge, T.Step do
			table.insert(tries, { -az * d, ax * d })
			table.insert(tries, { az * d, -ax * d })
		end
		for d = T.Step, T.Nudge, T.Step do
			table.insert(tries, { ax * d, az * d })
			table.insert(tries, { -ax * d, -az * d })
		end
		for _, o in tries do
			local x, z = spot.x + o[1], spot.z + o[2]
			if fits(x, z, radius) then
				table.insert(list, { kind = spot.kind, x = x, z = z, seed = spot.seed, radius = radius, height = height, from = from })
				return
			end
		end
	end
	for n, line in MAP.TreeLines do
		if TREE_LINES[line.kind] then
			local a, b = line.points[1], line.points[#line.points]
			local length = math.max(math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2), 1e-9)
			for _, spot in VillageLooks.lineTrees(line.points, line.kind, n) do
				plant(spot, (b.x - a.x) / length, (b.z - a.z) / length, `{line.kind} {n}`)
			end
		end
	end
	for _, spot in VillageLooks.orchard(rect(MAP.Orchard), VillageLooks.seedOf("orchard")) do
		plant(spot, 1, 0, "orchard")
	end
	-- the woods: a jittered grid, each tree a kind of the mix, none in a clearing (treeRule)
	local Wd = CW.Woods
	for _, wood in MAP.Woods do
		local seed = VillageLooks.seedOf(wood.id)
		local n = 0
		local x = wood.x0 + Wd.Spacing / 2
		while x <= wood.x1 - Wd.Spacing / 4 do
			local z = wood.z0 + Wd.Spacing / 2
			while z <= wood.z1 - Wd.Spacing / 4 do
				n += 1
				local s = (seed + n * 7919) % 999983 + 1
				local jx = ((s * 37) % 1000 / 1000 - 0.5) * 2 * Wd.Jitter
				local jz = ((s * 91) % 1000 / 1000 - 0.5) * 2 * Wd.Jitter
				local kind = Wd.Mix[(s * 13) % #Wd.Mix + 1]
				plant({ x = x + jx, z = z + jz, kind = kind, seed = s }, 1, 0, wood.id)
				z += Wd.Spacing
			end
			x += Wd.Spacing
		end
	end
	treeCache = list
	return list
end

-- ── The lines, the streams, the ground and far away ────────────────────────

function VillageScenery.lines(): { VillageLooks.Piece }
	local out: { VillageLooks.Piece } = {}
	for n, line in MAP.TreeLines do
		if not TREE_LINES[line.kind] then
			for _, p in CountryLooks.line(line.kind, line.points, n) do
				table.insert(out, p)
			end
		end
	end
	return out
end

function VillageScenery.streams(): { VillageLooks.Piece }
	local out: { VillageLooks.Piece } = {}
	for n, s in MAP.Streams do
		for _, p in CountryLooks.stream(s.points, s.width, n) do
			-- (10.6: only on an island: a piece's middle on its top)
			if VillageScenery.onIsland(p.at[1], p.at[3], 0) then
				table.insert(out, p)
			end
		end
	end
	return out
end

function VillageScenery.fields(): { FieldTile }
	local list: { FieldTile } = {}
	for n, f in MAP.Fields do
		table.insert(list, { kind = f.kind, rect = rect(f), seed = n })
	end
	return list
end

-- (the horizon's far roofs and church tower are a village's: none on the countryside's horizon)
local VILLAGE_FAR = { FarHouse = true, FarRoof = true, FarChurch = true, FarSpire = true }

function VillageScenery.far(): { VillageLooks.Piece }
	local out: { VillageLooks.Piece } = {}
	if #MAP.Zones > 0 then
		return out -- (9.7: no far view: every run zone ends at its screen hedge, the lobby at its own)
	end
	for _, p in VillageLooks.horizon(MAP.Bounds, 1) do
		if not VILLAGE_FAR[p.name] then
			table.insert(out, p)
		end
	end
	local rails: { Rect } = {}
	for _, l in MAP.Landmarks do
		if l.kind == "railway" then
			table.insert(rails, rect(l))
		end
	end
	for _, p in CountryLooks.farRails(rails, MAP.Bounds) do
		table.insert(out, p)
	end
	return out
end

-- ── The D5's lanes ─────────────────────────────────────────────────────────

-- Each carriageway of the D5 (its pieces on the map), two lanes in it, Cars.Lanes of its width either side of its
-- middle, run Beyond past the Bounds at both ends (onto the far view's D5); the one east of the motorway's middle goes
-- north (right-hand traffic), the other south.
function VillageScenery.lanes(): { Lane }
	local C = W.Cars
	local out: { Lane } = {}
	for _, m in VillageScenery.landmarks() do
		if m.kind == "motorway" then
			local middle = (m.box.x0 + m.box.x1) / 2
			for _, p in VillageScenery.pieces(m) do
				if p.name == "Carriageway" then
					local x0, x1, _, y1, z0, z1 = VillageLooks.box(p)
					local cx, wide = (x0 + x1) / 2, x1 - x0
					for _, s in { -1, 1 } do
						table.insert(out, { x = cx + s * wide * C.Lanes, y = y1, z0 = z0 - C.Beyond, z1 = z1 + C.Beyond, dz = if cx > middle then -1 else 1 })
					end
				end
			end
		end
	end
	return out
end

return VillageScenery
