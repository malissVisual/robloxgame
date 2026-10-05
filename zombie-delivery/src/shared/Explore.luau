--!strict
-- 3.7: the discovered map's grid. The world (Map.Bounds and Config.Explore.Pad around it) is cut into square cells
-- Config.Explore.Cell studs wide; a player uncovers the ones around them (server/Explore.luau), the maps draw the rest
-- as fog (client/MapView.luau) and a landmark (Map.Landmarks: the shops, the employers, the far places, the towers,
-- the estate) is known once its cell is uncovered, so the save needs nothing but the cells.
--
-- A cell is (cx, cz), 0-based, cx along X (east), cz along Z (south); its index is cz × Cols + cx (0 … Count - 1).
-- A set of cells is { [index]: true }.
--
-- The save (profile.explored) is a printable string, safe in a DataStore and in JSON: "1" (the format), the grid it
-- was made on (the cell size, the origin, the columns and rows: 3 characters each) and then one character for every 6
-- cells (a bit each), in the URL-safe base64 alphabet. If the grid changes later (another cell size, other bounds),
-- an older string is mapped onto the new grid instead of being lost.
--
-- Pure Luau (tests/explore_test.luau runs it in the plain Luau CLI).

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)

local Explore = {}

export type Set = { [number]: boolean }

local SIZE = Config.Explore.Cell
local PAD = Config.Explore.Pad
local B = Map.Bounds
local X0 = B.x0 - PAD
local Z0 = B.z0 - PAD
local COLS = math.ceil((B.x1 + PAD - X0) / SIZE)
local ROWS = math.ceil((B.z1 + PAD - Z0) / SIZE)
local COUNT = COLS * ROWS

Explore.Size = SIZE
Explore.X0 = X0
Explore.Z0 = Z0
Explore.Cols = COLS
Explore.Rows = ROWS
Explore.Count = COUNT

-- ── Cells ──────────────────────────────────────────────────────────────────

-- The cell a point is in (a point outside the grid: the nearest cell on its edge).
function Explore.cellOf(x: number, z: number): (number, number)
	if x ~= x then
		x = 0 -- NaN
	end
	if z ~= z then
		z = 0
	end
	local cx = math.clamp(math.floor((x - X0) / SIZE), 0, COLS - 1)
	local cz = math.clamp(math.floor((z - Z0) / SIZE), 0, ROWS - 1)
	return cx, cz
end

function Explore.index(cx: number, cz: number): number
	return cz * COLS + cx
end

-- The cell of an index.
function Explore.cell(index: number): (number, number)
	return index % COLS, index // COLS
end

-- The index of the cell a point is in.
function Explore.indexAt(x: number, z: number): number
	local cx, cz = Explore.cellOf(x, z)
	return cz * COLS + cx
end

-- A cell's centre in the world.
function Explore.centre(cx: number, cz: number): (number, number)
	return X0 + (cx + 0.5) * SIZE, Z0 + (cz + 0.5) * SIZE
end

-- The cells whose centre lies within `radius` of the point, and always the point's own cell: what a player at (x, z)
-- uncovers (a radius of Config.Explore.Radius = 180 on 120-stud cells: about 3 × 3 cells, a circle of fog lifted).
function Explore.cellsAround(x: number, z: number, radius: number): { number }
	local cx, cz = Explore.cellOf(x, z)
	local list = { cz * COLS + cx }
	local reach = math.ceil(radius / SIZE) + 1
	local r2 = radius * radius
	for dz = -reach, reach do
		local iz = cz + dz
		if iz < 0 or iz >= ROWS then
			continue
		end
		local mz = Z0 + (iz + 0.5) * SIZE - z
		for dx = -reach, reach do
			local ix = cx + dx
			if ix < 0 or ix >= COLS or (dx == 0 and dz == 0) then
				continue
			end
			local mx = X0 + (ix + 0.5) * SIZE - x
			if mx * mx + mz * mz <= r2 then
				table.insert(list, iz * COLS + ix)
			end
		end
	end
	return list
end

-- Every cell that overlaps the square of half-width `half` around (x, z) (the depot's area a new player starts with).
function Explore.cellsInSquare(x: number, z: number, half: number): { number }
	local ax, az = Explore.cellOf(x - half, z - half)
	local bx, bz = Explore.cellOf(x + half - 1e-6, z + half - 1e-6)
	local list = {}
	for iz = az, bz do
		for ix = ax, bx do
			table.insert(list, iz * COLS + ix)
		end
	end
	return list
end

function Explore.count(set: Set): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

-- ── The save string ────────────────────────────────────────────────────────

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local CHARS: { string } = {} -- value + 1 → its character
local VALUE: { [number]: number } = {} -- a character's byte → its value (0 … 63)
for n = 1, 64 do
	local c = string.sub(ALPHABET, n, n)
	CHARS[n] = c
	VALUE[string.byte(c)] = n - 1
end
local BITS = { 1, 2, 4, 8, 16, 32 }
local VERSION = "1"
local HEADER = 16 -- the version and five numbers of 3 characters
local OFFSET = 131072 -- the origin is stored + this (it is negative), in 3 characters (18 bits)

local function number3(n: number): string
	local v = math.clamp(math.floor(n), 0, 262143)
	return CHARS[v // 4096 + 1] .. CHARS[(v // 64) % 64 + 1] .. CHARS[v % 64 + 1]
end

local function read3(s: string, at: number): number?
	local a, b, c = VALUE[string.byte(s, at)], VALUE[string.byte(s, at + 1)], VALUE[string.byte(s, at + 2)]
	if a == nil or b == nil or c == nil then
		return nil
	end
	return a * 4096 + b * 64 + c
end

-- How long the string of a whole grid is (the header and a character per 6 cells).
Explore.EncodedLength = HEADER + math.ceil(COUNT / 6)

function Explore.encode(set: Set): string
	local parts = { VERSION, number3(SIZE), number3(X0 + OFFSET), number3(Z0 + OFFSET), number3(COLS), number3(ROWS) }
	for k = 0, math.ceil(COUNT / 6) - 1 do
		local v = 0
		local base = k * 6
		for b = 1, 6 do
			if set[base + b - 1] then
				v += BITS[b]
			end
		end
		table.insert(parts, CHARS[v + 1])
	end
	return table.concat(parts)
end

-- The cells of this grid whose centre lies in the rectangle, and the cell of its middle (an old grid's cell mapped
-- onto this one).
local function markRect(set: Set, ax: number, az: number, bx: number, bz: number)
	local cx0 = math.max(0, math.ceil((ax - X0) / SIZE - 0.5))
	local cx1 = math.min(COLS - 1, math.ceil((bx - X0) / SIZE - 0.5) - 1)
	local cz0 = math.max(0, math.ceil((az - Z0) / SIZE - 0.5))
	local cz1 = math.min(ROWS - 1, math.ceil((bz - Z0) / SIZE - 0.5) - 1)
	for iz = cz0, cz1 do
		for ix = cx0, cx1 do
			set[iz * COLS + ix] = true
		end
	end
	set[Explore.indexAt((ax + bx) / 2, (az + bz) / 2)] = true
end

-- The set a save string holds, on this grid. Anything that is not such a string (nil, an empty string, garbage): an
-- empty set.
function Explore.decode(s: any): Set
	local set: Set = {}
	if type(s) ~= "string" or #s < HEADER or string.sub(s, 1, 1) ~= VERSION then
		return set
	end
	local size, ox, oz, cols, rows = read3(s, 2), read3(s, 5), read3(s, 8), read3(s, 11), read3(s, 14)
	if not size or not ox or not oz or not cols or not rows or size < 1 or cols < 1 or rows < 1 then
		return set
	end
	ox -= OFFSET
	oz -= OFFSET
	local same = size == SIZE and ox == X0 and oz == Z0 and cols == COLS and rows == ROWS
	local total = cols * rows
	for k = 0, #s - HEADER - 1 do
		local v = VALUE[string.byte(s, HEADER + 1 + k)]
		if not v or v == 0 then
			continue
		end
		for b = 1, 6 do
			local index = k * 6 + b - 1
			if index >= total then
				break
			end
			if (v // BITS[b]) % 2 == 1 then
				if same then
					set[index] = true
				else
					local x = ox + (index % cols) * size
					local z = oz + (index // cols) * size
					markRect(set, x, z, x + size, z + size)
				end
			end
		end
	end
	return set
end

-- ── Landmarks ──────────────────────────────────────────────────────────────

-- Every landmark's cell, and the landmarks in each cell.
local landmarkCell: { [string]: number } = {}
local inCell: { [number]: { Map.Landmark } } = {}
for _, landmark in Map.Landmarks do
	local index = Explore.indexAt(landmark.x, landmark.z)
	landmarkCell[landmark.id] = index
	local list = inCell[index]
	if not list then
		list = {}
		inCell[index] = list
	end
	table.insert(list, landmark)
end

-- The cell a landmark is in (nil: not a landmark).
function Explore.landmarkCell(id: string): number?
	return landmarkCell[id]
end

-- The landmarks in a cell (nil: none).
function Explore.landmarksIn(index: number): { Map.Landmark }?
	return inCell[index]
end

-- Is the landmark known (its cell uncovered)?
function Explore.knows(set: Set, id: string): boolean
	local index = landmarkCell[id]
	return index ~= nil and set[index] == true
end

-- The ids of every known landmark, in Map.Landmarks' order.
function Explore.known(set: Set): { string }
	local list = {}
	for _, landmark in Map.Landmarks do
		if set[landmarkCell[landmark.id]] then
			table.insert(list, landmark.id)
		end
	end
	return list
end

return Explore
