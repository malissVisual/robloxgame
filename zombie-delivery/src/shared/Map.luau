--!strict
-- The layout of the world, as plain numbers (x, z on the ground; -Z is north on the map). The server builds it
-- (server/World.luau), the client draws it (client/MapView.luau) and both ask it where the roads are.
--
--   Downtown   a 9 x 9 grid of blocks around the depot, the shops in the four blocks next to it (the safe zone)
--   Harbor     east, across the river (Rust Bridge, Old Bridge), docks on the sea
--   Suburbs    south, little houses
--   Highways   north to the Gas Station, through the mountain tunnel to the Military Base;
--              west to the Radio Station and the Old Farm
--
-- A district is a grid: block (i, j) is centred at (ox + i × CELL, oz + j × CELL); the roads run between the blocks
-- and around them (road k between block k and k + 1, centred at ox + (k + 0.5) × CELL).

local Config = require(script.Parent.Config)

local BLOCK = Config.City.BlockSize
local ROAD = Config.City.RoadWidth
local HIGHWAY = Config.City.HighwayWidth
local CELL = BLOCK + ROAD

local Map = {}

Map.Cell = CELL
Map.BlockSize = BLOCK
Map.RoadWidth = ROAD
Map.HighwayWidth = HIGHWAY
Map.RoadTop = 0.4
Map.WalkTop = 0.6

export type District = {
	id: string,
	name: string,
	style: string, -- downtown | harbor | suburbs
	ox: number,
	oz: number,
	i0: number,
	i1: number,
	j0: number,
	j1: number,
	streets: { string }, -- roads along X (constant z)
	avenues: { string }, -- roads along Z (constant x)
}

export type Segment = {
	ax: number,
	az: number,
	bx: number,
	bz: number,
	width: number,
	kind: string, -- street | grid | bridge | highway | ice
	name: string?,
}

export type Area = { id: string, name: string, x0: number, z0: number, x1: number, z1: number }

export type Place = {
	id: string,
	name: string,
	x: number,
	z: number,
	nx: number, -- the side the zombies wait on (0, 0 = all around)
	nz: number,
}

export type Address = {
	x: number,
	z: number,
	nx: number,
	nz: number,
	name: string,
	district: string,
	poi: boolean,
}

Map.Bounds = { x0 = -2150, z0 = -2950, x1 = 1900, z1 = 1500 }
Map.River = { x0 = 760, x1 = 920 }
Map.Sea = { x0 = 1660 }
Map.WaterLevel = -3
Map.Mountain = { x = 300, z = -1700, radius = 265, tunnelZ0 = -1960, tunnelZ1 = -1440 }
-- North of the mountain it is winter: snow, and a frozen lake the Lodge Road crosses on the ice.
Map.WinterZ = -1965
Map.Lake = { x0 = -490, x1 = -110, z0 = -2340, z1 = -2060 }

Map.Districts = {
	{
		id = "downtown",
		name = "Downtown",
		style = "downtown",
		ox = 0,
		oz = 0,
		i0 = -4,
		i1 = 4,
		j0 = -4,
		j1 = 4,
		streets = { "Maple St", "Oak St", "Grave St", "Elm St", "Bone St", "Main St", "Cedar St", "Ash St", "Hollow St", "Pine St" },
		avenues = { "1st Ave", "2nd Ave", "3rd Ave", "4th Ave", "5th Ave", "6th Ave", "7th Ave", "8th Ave", "9th Ave", "10th Ave" },
	},
	{
		id = "harbor",
		name = "Harbor",
		style = "harbor",
		ox = 1080,
		oz = 0,
		i0 = 0,
		i1 = 3,
		j0 = -3,
		j1 = 3,
		streets = { "Anchor Rd", "Salt Rd", "Gull Rd", "Cargo Rd", "Rope Rd", "Keel Rd", "Hull Rd", "Tide Rd" },
		avenues = { "Dock 1", "Dock 2", "Dock 3", "Dock 4", "Dock 5" },
	},
	{
		id = "suburbs",
		name = "Suburbs",
		style = "suburbs",
		ox = 0,
		oz = 900,
		i0 = -2,
		i1 = 2,
		j0 = 0,
		j1 = 2,
		streets = { "Willow Ln", "Daisy Ln", "Cherry Ln", "Birch Ln" },
		avenues = { "Hill Rd", "Brook Rd", "Fern Rd", "Moss Rd", "Lake Rd", "Rose Rd" },
	},
} :: { District }

-- Downtown blocks that are not ordinary city blocks.
Map.SpecialBlocks = {
	["0,0"] = "depot",
	["1,0"] = "dealer",
	["-1,0"] = "guns",
	["0,1"] = "mechanic",
	["0,-1"] = "supplies",
} :: { [string]: string }

-- The shops (their block centres); you must stand within Radius of one to use it.
Map.Shops = {
	depot = { name = "Depot Garage", x = 0, z = 0 },
	dealer = { name = "Dead End Motors", x = CELL, z = 0 },
	guns = { name = "Lead & Co.", x = -CELL, z = 0 },
	mechanic = { name = "Wrench Garage", x = 0, z = CELL },
	supplies = { name = "Last Stop Supplies", x = 0, z = -CELL },
} :: { [string]: { name: string, x: number, z: number } }
Map.ShopRadius = 80

-- Flat open areas at the ends of the highways.
Map.Yards = {
	{ id = "base", name = "Military Base", x0 = 40, z0 = -2840, x1 = 560, z1 = -2360 },
	{ id = "radio", name = "Radio Station", x0 = -1200, z0 = -660, x1 = -1000, z1 = -460 },
	{ id = "farm", name = "Old Farm", x0 = -2030, z0 = 370, x1 = -1730, z1 = 670 },
	{ id = "docks", name = "Harbor Docks", x0 = 1601, z0 = -200, x1 = 1656, z1 = 200 },
	{ id = "gas", name = "Gas Station", x0 = 92, z0 = -960, x1 = 200, z1 = -840 },
	{ id = "lodge", name = "Ski Lodge", x0 = -780, z0 = -2320, x1 = -530, z1 = -2080 },
} :: { Area }

-- Named destinations (the far, crazy deliveries).
Map.Places = {
	{ id = "base", name = "Military Base", x = 300, z = -2600, nx = 0, nz = 0 },
	{ id = "radio", name = "Radio Station", x = -1100, z = -560, nx = 0, nz = 0 },
	{ id = "farm", name = "Old Farm", x = -1880, z = 520, nx = 0, nz = 0 },
	{ id = "docks", name = "Harbor Docks", x = 1626, z = 0, nx = 0, nz = 0 },
	{ id = "gas", name = "Gas Station", x = 146, z = -900, nx = 0, nz = 0 },
	{ id = "lodge", name = "Ski Lodge", x = -655, z = -2200, nx = 0, nz = 0 },
} :: { Place }

-- ── Roads ──────────────────────────────────────────────────────────────────

local function districtEdges(d: District): (number, number, number, number)
	-- centre lines of the outer roads
	return d.ox + (d.i0 - 0.5) * CELL, d.ox + (d.i1 + 0.5) * CELL, d.oz + (d.j0 - 0.5) * CELL, d.oz + (d.j1 + 0.5) * CELL
end
Map.districtEdges = districtEdges

local connectors: { Segment } = {}
local function line(points: { { number } }, width: number, kind: string, name: string?)
	for n = 1, #points - 1 do
		local a, b = points[n], points[n + 1]
		table.insert(connectors, { ax = a[1], az = a[2], bx = b[1], bz = b[2], width = width, kind = kind, name = name })
	end
end

local downtownEdge = 4.5 * CELL + ROAD / 2 -- 665
local harborWest = 1080 - 0.5 * CELL - ROAD / 2 -- 991
line({ { downtownEdge, 0.5 * CELL }, { harborWest, 0.5 * CELL } }, ROAD, "bridge", "Rust Bridge")
line({ { downtownEdge, -2.5 * CELL }, { harborWest, -2.5 * CELL } }, ROAD, "bridge", "Old Bridge")
local suburbsNorth = 900 - 0.5 * CELL - ROAD / 2 -- 811
for k = -3, 2 do
	line({ { (k + 0.5) * CELL, downtownEdge }, { (k + 0.5) * CELL, suburbsNorth } }, ROAD, "street")
end
line({ { 0.5 * CELL, -downtownEdge }, { 0.5 * CELL, -1000 }, { 300, -1240 }, { 300, -2360 } }, HIGHWAY, "highway", "North Highway")
line({ { -downtownEdge, 1.5 * CELL }, { -1100, 1.5 * CELL }, { -1400, 520 }, { -1730, 520 } }, HIGHWAY, "highway", "West Highway")
line({ { -1100, 1.5 * CELL }, { -1100, -460 } }, HIGHWAY, "highway", "Radio Road")
line({ { 300 - HIGHWAY / 2, -2200 }, { Map.Lake.x1, -2200 } }, HIGHWAY, "highway", "Lodge Road")
line({ { Map.Lake.x1, -2200 }, { -530, -2200 } }, HIGHWAY, "ice", "Ice Road")

Map.Connectors = connectors

-- Every road centre line (the district grids and the connectors).
local segments: { Segment } = {}
for _, d in Map.Districts do
	local x0, x1, z0, z1 = districtEdges(d)
	for k = d.i0 - 1, d.i1 do
		local x = d.ox + (k + 0.5) * CELL
		table.insert(segments, { ax = x, az = z0, bx = x, bz = z1, width = ROAD, kind = "grid" })
	end
	for k = d.j0 - 1, d.j1 do
		local z = d.oz + (k + 0.5) * CELL
		table.insert(segments, { ax = x0, az = z, bx = x1, bz = z, width = ROAD, kind = "grid" })
	end
end
for _, s in connectors do
	table.insert(segments, s)
end
Map.Segments = segments

local function closestOnSegment(s: Segment, x: number, z: number): (number, number, number)
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
	local px, pz = s.ax + dx * t, s.az + dz * t
	return px, pz, (x - px) ^ 2 + (z - pz) ^ 2
end

-- The closest point on any road centre line and that road's direction (unit) and width.
function Map.nearestRoad(x: number, z: number): (number, number, number, number, number)
	local best: Segment = segments[1]
	local bx, bz, bestD = closestOnSegment(best, x, z)
	for n = 2, #segments do
		local s = segments[n]
		local px, pz, d = closestOnSegment(s, x, z)
		if d < bestD then
			best, bx, bz, bestD = s, px, pz, d
		end
	end
	local dx, dz = best.bx - best.ax, best.bz - best.az
	local length = math.sqrt(dx * dx + dz * dz)
	return bx, bz, dx / length, dz / length, best.width
end

function Map.inYard(x: number, z: number): Area?
	for _, yard in Map.Yards do
		if x >= yard.x0 and x <= yard.x1 and z >= yard.z0 and z <= yard.z1 then
			return yard
		end
	end
	return nil
end

-- On asphalt: a road or a yard.
function Map.onRoad(x: number, z: number): boolean
	for _, s in segments do
		local _, _, d = closestOnSegment(s, x, z)
		if d <= (s.width / 2) ^ 2 + 1e-6 then
			return true
		end
	end
	return Map.inYard(x, z) ~= nil
end

function Map.isSafe(x: number, z: number): boolean
	local half = Config.City.SafeHalf
	return math.abs(x) < half and math.abs(z) < half
end

function Map.inWater(x: number, z: number): boolean
	return (x > Map.River.x0 and x < Map.River.x1) or x > Map.Sea.x0
end

function Map.isWinter(x: number, z: number): boolean
	return z < Map.WinterZ and x < Map.River.x0
end

function Map.onIce(x: number, z: number): boolean
	local lake = Map.Lake
	return x > lake.x0 and x < lake.x1 and z > lake.z0 and z < lake.z1
end

function Map.manhattan(ax: number, az: number, bx: number, bz: number): number
	return math.abs(ax - bx) + math.abs(az - bz)
end

-- The district (and block) a point is in, if any.
function Map.blockAt(x: number, z: number): (District?, number, number)
	for _, d in Map.Districts do
		local i = math.floor((x - d.ox) / CELL + 0.5)
		local j = math.floor((z - d.oz) / CELL + 0.5)
		if i >= d.i0 and i <= d.i1 and j >= d.j0 and j <= d.j1 then
			local cx, cz = d.ox + i * CELL, d.oz + j * CELL
			if math.abs(x - cx) < BLOCK / 2 and math.abs(z - cz) < BLOCK / 2 then
				return d, i, j
			end
		end
	end
	return nil, 0, 0
end

-- A small deterministic generator (the same world on every server, also in the tests).
function Map.lcg(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

local SIDES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local addressCache: { Address }? = nil

-- Two addresses on every ordinary block (on the road just outside one side of it) and every named place.
function Map.addresses(): { Address }
	if addressCache then
		return addressCache
	end
	local rand = Map.lcg(Config.City.Seed + 99)
	local list: { Address } = {}
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				if d.id == "downtown" and Map.SpecialBlocks[`{i},{j}`] then
					continue
				end
				local first = math.floor(rand() * 4) + 1
				for n = 0, 1 do
					local side = SIDES[(first + n * 2 - 1) % 4 + 1]
					local nx, nz = side[1], side[2]
					local cx, cz = d.ox + i * CELL, d.oz + j * CELL
					local along = (rand() - 0.5) * (BLOCK - 40)
					local out = BLOCK / 2 + 6
					local x = cx + nx * out + (if nz ~= 0 then along else 0)
					local z = cz + nz * out + (if nx ~= 0 then along else 0)
					local number = math.floor(rand() * 90) + 10
					local name: string
					if nz ~= 0 then
						local k = j + (if nz > 0 then 0 else -1) - d.j0 + 1
						name = `{number} {d.streets[k % #d.streets + 1]}`
					else
						local k = i + (if nx > 0 then 0 else -1) - d.i0 + 1
						name = `{number} {d.avenues[k % #d.avenues + 1]}`
					end
					if Map.isSafe(x, z) then
						continue
					end
					table.insert(list, { x = x, z = z, nx = nx, nz = nz, name = name, district = d.name, poi = false })
				end
			end
		end
	end
	for _, place in Map.Places do
		table.insert(list, { x = place.x, z = place.z, nx = place.nx, nz = place.nz, name = place.name, district = place.name, poi = true })
	end
	addressCache = list
	return list
end

return Map
