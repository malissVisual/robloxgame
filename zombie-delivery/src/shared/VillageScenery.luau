--!strict
-- 8.9 SANDBOX, Jinočany step 1 on the map (design/jinocany/NAVRH.md §4): where shared/VillageLooks.luau's art stands,
-- as plain numbers, from shared/SandboxMap.luau's village section (tools/village/sandboxmap.py writes it from
-- design/jinocany/plan.json). Pure (no Roblox at its top level), deterministic: server/VillageWorld.luau makes the parts,
-- client/VillageTraffic.luau drives the D5's cars on its lanes, tests/villageworld_test.luau checks it all. Its numbers
-- are Config.VillageWorld's (and Config.Village's, the art kit's).
--
--   The houses     SandboxMap.Village (the moves' houses to empty are not in it: SandboxMap.Houses, the moves' own
--                  exteriors), each in its box turned by its yaw, its dice its id's (VillageLooks.seedOf); the terraced
--                  ones in their groups (VillageLooks.rowGroups: one body for up to four, the gap where a house to empty
--                  stands is a gap in the group)
--   The landmarks  SandboxMap.Landmarks looking Config.Village.Facing's way (the green round its chapel), and
--                  Hornická's ROAD CLOSED barrier at its west end (VillageLooks.barrierAt); the D5 is kept on every
--                  client (far = true: its cars run on it)
--   The trees      the tree lines' and the orchard's (VillageLooks.lineTrees, orchard: the census's dice), each where
--                  treeRule lets its crown stand: else moved off its spot (Config.VillageWorld.Trees: Step studs at a
--                  time across its line, then along it, at most Nudge), else left out
--   The fields     SandboxMap.Fields, a tile each (VillageLooks.field: the ground in its crop's colour, its rows)
--   The far view   VillageLooks.horizon round SandboxMap.Bounds
--
--   VillageScenery.houses(extra?)    { Placed }: a house (or a terraced group): kind, box, yaw, seed, opts, ids, street;
--                                    extra: the houses to empty, rich (their row's group rebuilt round one)
--   VillageScenery.landmarks()       { Mark }: id, name, kind, box, yaw, seed, opts, far
--   VillageScenery.pieces(thing)     a house's or a landmark's pieces on the map (VillageLooks.place)
--   VillageScenery.trees()           { TreeSpot }: kind, x, z, seed, its crown's radius and height, the line or "orchard"
--   VillageScenery.treeRule(x, z, r) why a crown r wide may not stand there (nil: it may): SandboxScenery.treeRule's
--                                    reasons, then "house", "landmark", "auction" (Keep studs off each)
--   VillageScenery.fields()          { FieldTile }: kind, rect, seed
--   VillageScenery.lanes()           { Lane }: the D5's four lanes (x, the road's top y, z0 … z1 run Beyond past the
--                                    Bounds, dz: -1 northbound, 1 southbound; right-hand traffic)
--   VillageScenery.far()             the far view's pieces

local AuctionHouseLayout = require(script.Parent.AuctionHouseLayout)
local Config = require(script.Parent.Config)
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
local V = Config.Village
local W = Config.VillageWorld

local function rect(r: { x0: number, x1: number, z0: number, z1: number }): Rect
	return { x0 = r.x0, x1 = r.x1, z0 = r.z0, z1 = r.z1 }
end

-- ── The houses and the landmarks ───────────────────────────────────────────

local houseCache: { Placed }? = nil

-- extra: the hook for the houses to empty (plan.json's enter: SandboxMap.Houses' exteriors, the moves'), each a
-- PlanHouse with enter = true: dressed rich (VillageLooks' "rich"), a terraced one in its row's group (the group's
-- richUnit). Without it the village's own houses alone (the same list every time).
function VillageScenery.houses(extra: { VillageLooks.PlanHouse }?): { Placed }
	if houseCache and not extra then
		return houseCache
	end
	local list: { Placed } = {}
	local rows: { VillageLooks.PlanHouse } = {}
	local streets: { [string]: string } = {}
	local all: { VillageLooks.PlanHouse } = {}
	for _, h in MAP.Village do
		table.insert(all, { id = h.id, kind = h.kind, box = rect(h), yaw = h.yaw, step = 1, enter = false, street = h.street })
	end
	if extra then
		for _, h in extra do
			table.insert(all, h)
		end
	end
	for _, h in all do
		streets[h.id] = h.street or ""
		if h.kind == "row" then
			table.insert(rows, h)
		else
			table.insert(list, { id = h.id, kind = h.kind, box = h.box, yaw = h.yaw, seed = VillageLooks.seedOf(h.id), opts = { rich = h.enter == true }, ids = { h.id }, street = h.street or "" })
		end
	end
	for _, g in VillageLooks.rowGroups(rows) do
		table.insert(list, { id = g.ids[1], kind = "row", box = g.box, yaw = g.yaw, seed = g.seed, opts = { units = #g.ids, rich = g.richUnit ~= nil, richUnit = g.richUnit }, ids = g.ids, street = streets[g.ids[1]] })
	end
	if not extra then
		houseCache = list
	end
	return list
end

local markCache: { Mark }? = nil

function VillageScenery.landmarks(): { Mark }
	if markCache then
		return markCache
	end
	local list: { Mark } = {}
	local chapel: Rect? = nil
	for _, l in MAP.Landmarks do
		if l.kind == "chapel" then
			chapel = rect(l)
		end
	end
	for _, l in MAP.Landmarks do
		local yaw = V.Facing[l.kind]
		if yaw then
			table.insert(list, { id = l.id, name = l.name, kind = l.kind, box = rect(l), yaw = yaw, seed = VillageLooks.seedOf(l.id), opts = { chapel = chapel }, far = l.kind == "motorway" })
		end
	end
	for _, road in MAP.Roads do
		if road.name == V.Barrier.Road then
			local box, yaw = VillageLooks.barrierAt(rect(road))
			table.insert(list, { id = "barrier", name = `{road.name}: road closed`, kind = "barrier", box = box, yaw = yaw, seed = VillageLooks.seedOf(road.name), opts = {}, far = false })
		end
	end
	markCache = list
	return list
end

-- A house's or a landmark's pieces on the map.
function VillageScenery.pieces(thing: Placed | Mark): { VillageLooks.Piece }
	local made = if (thing :: any).ids
		then VillageLooks.house(thing.kind, thing.box, thing.yaw, thing.seed, thing.opts)
		else VillageLooks.landmark(thing.kind, thing.box, thing.yaw, thing.seed, thing.opts)
	return VillageLooks.place(made, thing.box, thing.yaw)
end

-- ── The trees ──────────────────────────────────────────────────────────────

function VillageScenery.treeRule(x: number, z: number, r: number): string?
	local why = SandboxScenery.treeRule(x, z, r)
	if why then
		return why
	end
	local keep = r + W.Trees.Keep
	for _, h in MAP.Village do
		if SandboxScenery.rectDistance(rect(h), x, z) < keep then
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
	return nil
end

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
		local a, b = line.points[1], line.points[#line.points]
		local length = math.max(math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2), 1e-9)
		for _, spot in VillageLooks.lineTrees(line.points, line.kind, n) do
			plant(spot, (b.x - a.x) / length, (b.z - a.z) / length, `{line.kind} {n}`)
		end
	end
	for _, spot in VillageLooks.orchard(rect(MAP.Orchard), VillageLooks.seedOf("orchard")) do
		plant(spot, 1, 0, "orchard")
	end
	treeCache = list
	return list
end

-- ── The ground and far away ────────────────────────────────────────────────

function VillageScenery.fields(): { FieldTile }
	local list: { FieldTile } = {}
	for n, f in MAP.Fields do
		table.insert(list, { kind = f.kind, rect = rect(f), seed = n })
	end
	return list
end

function VillageScenery.far(): { VillageLooks.Piece }
	return VillageLooks.horizon(MAP.Bounds, 1)
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
