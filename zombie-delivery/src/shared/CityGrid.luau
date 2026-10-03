--!strict
-- The geometry of the city grid: where the blocks and roads are, the nearest road to a point and the delivery
-- addresses. Plain numbers (x, z on the ground), no Roblox API, so the server, the client and the tests share it.
--
--   block (i, j) is centred at (i × CELL, j × CELL), i, j ∈ -B … B, size BlockSize
--   road k runs between block k and k + 1, centred at (k + 0.5) × CELL, k ∈ -B-1 … B (the outer ring included)

local Config = require(script.Parent.Config)

local B = Config.City.Blocks
local BLOCK = Config.City.BlockSize
local ROAD = Config.City.RoadWidth
local CELL = BLOCK + ROAD

local CityGrid = {}

CityGrid.Blocks = B
CityGrid.BlockSize = BLOCK
CityGrid.RoadWidth = ROAD
CityGrid.Cell = CELL
CityGrid.Extent = (B + 0.5) * CELL -- centre line of the outer ring road
CityGrid.Edge = (B + 0.5) * CELL + ROAD / 2 -- outer edge of the asphalt

export type Address = {
	x: number,
	z: number,
	nx: number, -- the block side it lies on (unit normal pointing to the road)
	nz: number,
	i: number,
	j: number,
	name: string,
}

function CityGrid.blockCenter(i: number, j: number): (number, number)
	return i * CELL, j * CELL
end

function CityGrid.roadCenter(k: number): number
	return (k + 0.5) * CELL
end

local function nearestRoadIndex(v: number): number
	-- round(v / CELL - 0.5) = floor(v / CELL)
	return math.clamp(math.floor(v / CELL), -B - 1, B)
end

-- The closest point on a road centre line. axis = "x" when that road runs along X, "z" when along Z.
function CityGrid.nearestRoad(x: number, z: number): (number, number, string)
	local rx = CityGrid.roadCenter(nearestRoadIndex(x))
	local rz = CityGrid.roadCenter(nearestRoadIndex(z))
	local ext = CityGrid.Extent
	if math.abs(x - rx) <= math.abs(z - rz) then
		return rx, math.clamp(z, -ext, ext), "z"
	end
	return math.clamp(x, -ext, ext), rz, "x"
end

-- Inside the footprint of a block (grown by margin): somewhere a car cannot drive and a zombie should not spawn.
function CityGrid.inBlock(x: number, z: number, margin: number): boolean
	local i = math.floor(x / CELL + 0.5)
	local j = math.floor(z / CELL + 0.5)
	if math.abs(i) > B or math.abs(j) > B then
		return false
	end
	local half = BLOCK / 2 + margin
	return math.abs(x - i * CELL) < half and math.abs(z - j * CELL) < half
end

function CityGrid.onRoad(x: number, z: number): boolean
	local edge = CityGrid.Edge
	return math.abs(x) <= edge and math.abs(z) <= edge and not CityGrid.inBlock(x, z, 0)
end

function CityGrid.manhattan(ax: number, az: number, bx: number, bz: number): number
	return math.abs(ax - bx) + math.abs(az - bz)
end

-- A small deterministic generator (the same city on every server, also in the tests).
local function lcg(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end
CityGrid.lcg = lcg

local SIDES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local addressCache: { Address }? = nil

-- Two addresses on every block except the depot (0, 0), each on the road just outside one side of the block.
function CityGrid.addresses(): { Address }
	if addressCache then
		return addressCache
	end
	local rand = lcg(Config.City.Seed + 99)
	local list: { Address } = {}
	local streets = Config.Jobs.Streets
	local avenues = Config.Jobs.Avenues
	for i = -B, B do
		for j = -B, B do
			if i == 0 and j == 0 then
				continue
			end
			local first = math.floor(rand() * 4) + 1
			for n = 0, 1 do
				local side = SIDES[(first + n * 2 - 1) % 4 + 1] -- two different sides
				local nx, nz = side[1], side[2]
				local cx, cz = CityGrid.blockCenter(i, j)
				local along = (rand() - 0.5) * (BLOCK - 40)
				local out = BLOCK / 2 + 6
				local x = cx + nx * out + (nz ~= 0 and along or 0)
				local z = cz + nz * out + (nx ~= 0 and along or 0)
				local name: string
				local number = math.floor(rand() * 90) + 10
				if nz ~= 0 then
					-- the road along X (constant z) is a street
					local k = j + (nz > 0 and 0 or -1) + B + 1
					name = `{number} {streets[k % #streets + 1]} St`
				else
					local k = i + (nx > 0 and 0 or -1) + B + 1
					name = `{number} {avenues[k % #avenues + 1]} Ave`
				end
				table.insert(list, { x = x, z = z, nx = nx, nz = nz, i = i, j = j, name = name })
			end
		end
	end
	addressCache = list
	return list
end

return CityGrid
