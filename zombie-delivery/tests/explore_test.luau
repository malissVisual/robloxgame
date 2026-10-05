-- Test of the discovered map's grid (shared/Explore.luau) in the standalone Luau CLI: the grid covers the whole world,
-- the save string survives a round trip (and an older grid's string maps onto the new one), the cells around a point
-- are the circle they should be, the depot's start square and the landmarks' cells.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local Explore = require("./Explore")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local S = Explore.Size
print(`grid {Explore.Cols} x {Explore.Rows} = {Explore.Count} cells of {S} studs, save {Explore.EncodedLength} characters`)

-- ── The bounds ─────────────────────────────────────────────────────────────

local B = Map.Bounds
local gx1, gz1 = Explore.X0 + Explore.Cols * S, Explore.Z0 + Explore.Rows * S
check("the grid covers Map.Bounds", Explore.X0 <= B.x0 and Explore.Z0 <= B.z0 and gx1 >= B.x1 and gz1 >= B.z1, `{Explore.X0},{Explore.Z0} … {gx1},{gz1}`)
check("the grid is padded, not much bigger", Explore.X0 < B.x0 and gx1 - B.x1 <= Config.Explore.Pad + S and gz1 - B.z1 <= Config.Explore.Pad + S)

-- Everything worth finding lies inside the grid, and not on a clamped edge cell.
local function inside(x: number, z: number): boolean
	return x > Explore.X0 and x < gx1 and z > Explore.Z0 and z < gz1
end
local outside = {}
for _, l in Map.Landmarks do
	if not inside(l.x, l.z) then
		table.insert(outside, l.id)
	end
end
for _, p in Map.Places do
	if not inside(p.x, p.z) then
		table.insert(outside, p.id)
	end
end
for _, y in Map.Yards do
	if not inside(y.x0, y.z0) or not inside(y.x1, y.z1) then
		table.insert(outside, y.id)
	end
end
for _, s in Map.Segments do
	if not inside(s.ax, s.az) or not inside(s.bx, s.bz) then
		table.insert(outside, s.name or s.kind)
	end
end
local lake, mountain = Map.Lake, Map.Mountain
if not inside(lake.x0, lake.z0) or not inside(lake.x1, lake.z1) then
	table.insert(outside, "lake")
end
if not inside(mountain.x - mountain.radius, mountain.z - mountain.radius) or not inside(mountain.x + mountain.radius, mountain.z + mountain.radius) then
	table.insert(outside, "mountain")
end
check("every landmark, place, yard, road, the lake and the mountain lie in the grid", #outside == 0, table.concat(outside, ", "))

-- cellOf / index / cell / centre agree.
local cx, cz = Explore.cellOf(0, 0)
local mx, mz = Explore.centre(cx, cz)
check("the depot's cell holds the depot", math.abs(mx) <= S / 2 and math.abs(mz) <= S / 2, `{mx},{mz}`)
local ix, iz = Explore.cell(Explore.index(cx, cz))
check("index and cell are inverse", ix == cx and iz == cz)
check("indexAt = index(cellOf)", Explore.indexAt(0, 0) == Explore.index(cx, cz))
local ex, ez = Explore.cellOf(-1e9, 1e9)
check("a point far outside clamps to the edge", ex == 0 and ez == Explore.Rows - 1, `{ex},{ez}`)
local nx, nz = Explore.cellOf(0 / 0, 0 / 0)
check("NaN does not break cellOf", nx >= 0 and nx < Explore.Cols and nz >= 0 and nz < Explore.Rows)
local roundOk = true
for k = 0, Explore.Count - 1, 37 do
	local a, b = Explore.cell(k)
	local x, z = Explore.centre(a, b)
	if Explore.indexAt(x, z) ~= k then
		roundOk = false
	end
end
check("every cell's centre is in that cell", roundOk)

-- ── The save string ────────────────────────────────────────────────────────

local function same(a: Explore.Set, b: Explore.Set): boolean
	for k in a do
		if not b[k] then
			return false
		end
	end
	for k in b do
		if not a[k] then
			return false
		end
	end
	return true
end

local empty = Explore.decode(Explore.encode({}))
check("an empty set round-trips", Explore.count(empty) == 0)
local full: Explore.Set = {}
for k = 0, Explore.Count - 1 do
	full[k] = true
end
local fullText = Explore.encode(full)
check("a full set round-trips", same(full, Explore.decode(fullText)))
check("the string has the expected length", #fullText == Explore.EncodedLength, #fullText)
check("the whole grid fits well under the 65536 characters of profile.explored", Explore.EncodedLength < 2000, Explore.EncodedLength)
check("only printable, DataStore-safe characters", string.match(fullText, "^[%w%-_]+$") ~= nil)
local rand = Map.lcg(777)
for trial = 1, 5 do
	local set: Explore.Set = {}
	for _ = 1, 40 * trial do
		set[math.floor(rand() * Explore.Count)] = true
	end
	set[0] = true
	set[Explore.Count - 1] = true
	check(`a random set round-trips ({trial})`, same(set, Explore.decode(Explore.encode(set))))
end
check("garbage decodes to an empty set", Explore.count(Explore.decode("hello")) == 0 and Explore.count(Explore.decode("")) == 0 and Explore.count(Explore.decode(nil)) == 0 and Explore.count(Explore.decode(42)) == 0)
check("a cut string keeps what it has", Explore.decode(string.sub(fullText, 1, 20))[0] == true)
local bad = string.sub(fullText, 1, 16) .. string.rep("!", 30)
check("bad characters are ignored", Explore.count(Explore.decode(bad)) == 0)

-- An older grid (here: cells twice as big, the same origin) maps onto this one: its uncovered area stays uncovered.
do
	local function n3(n: number): string
		local A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
		local function c(v: number): string
			return string.sub(A, v + 1, v + 1)
		end
		return c(n // 4096) .. c((n // 64) % 64) .. c(n % 64)
	end
	local cols, rows = math.ceil(Explore.Cols / 2), math.ceil(Explore.Rows / 2)
	-- One old cell: the one over the depot.
	local ocx, ocz = math.floor((0 - Explore.X0) / (2 * S)), math.floor((0 - Explore.Z0) / (2 * S))
	local oldIndex = ocz * cols + ocx
	local chars = {}
	for k = 0, math.ceil(cols * rows / 6) - 1 do
		local v = 0
		if oldIndex // 6 == k then
			v = 2 ^ (oldIndex % 6)
		end
		table.insert(chars, string.sub("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", v + 1, v + 1))
	end
	local old = "1" .. n3(2 * S) .. n3(Explore.X0 + 131072) .. n3(Explore.Z0 + 131072) .. n3(cols) .. n3(rows) .. table.concat(chars)
	local mapped = Explore.decode(old)
	check("an older grid's cell maps onto the four cells under it", Explore.count(mapped) == 4 and mapped[Explore.indexAt(0, 0)] == true, Explore.count(mapped))
end

-- ── The cells around ───────────────────────────────────────────────────────

local R = Config.Explore.Radius
local around = Explore.cellsAround(0, 0, R)
local own = Explore.indexAt(0, 0)
local hasOwn, allNear, unique = false, true, true
local seen = {}
for _, k in around do
	if k == own then
		hasOwn = true
	end
	if seen[k] then
		unique = false
	end
	seen[k] = true
	local x, z = Explore.centre(Explore.cell(k))
	if k ~= own and x * x + z * z > R * R then
		allNear = false
	end
end
check("the cells around include your own", hasOwn)
check("every other cell around has its centre within the radius", allNear)
check("no cell twice", unique)
local missed = 0
for k = 0, Explore.Count - 1 do
	local x, z = Explore.centre(Explore.cell(k))
	if x * x + z * z <= R * R and not seen[k] then
		missed += 1
	end
end
check("no cell within the radius is missed", missed == 0, missed)
check("the circle is a few cells, not the map", #around >= 4 and #around <= 16, #around)
local tiny = Explore.cellsAround(B.x0 + 1, B.z0 + 1, 0)
check("radius 0: just your cell", #tiny == 1 and tiny[1] == Explore.indexAt(B.x0 + 1, B.z0 + 1))
local corner = Explore.cellsAround(-1e5, -1e5, R)
local inGrid = true
for _, k in corner do
	if k < 0 or k >= Explore.Count then
		inGrid = false
	end
end
check("far off the grid: still only cells of the grid", inGrid and #corner >= 1)

-- The start: the cells over the safe zone (a new player is not lost).
local start: Explore.Set = {}
for _, k in Explore.cellsInSquare(0, 0, Config.Explore.StartHalf) do
	start[k] = true
end
local half = Config.City.SafeHalf
local safeCovered = start[Explore.indexAt(-half, -half)] and start[Explore.indexAt(half, half)] and start[Explore.indexAt(-half, half)] and start[Explore.indexAt(half, -half)] and start[own]
check("the start square covers the whole safe zone", safeCovered == true)
check("the start square is not much of the map", Explore.count(start) <= 49, Explore.count(start))

-- ── Landmarks ──────────────────────────────────────────────────────────────

local ids: { [string]: boolean } = {}
local duplicate: string? = nil
for _, l in Map.Landmarks do
	if ids[l.id] then
		duplicate = l.id
	end
	ids[l.id] = true
end
check("every landmark id is unique", duplicate == nil, duplicate)
local knownAtStart = Explore.known(start)
local knowsDepot = false
for _, id in knownAtStart do
	if id == "depot" then
		knowsDepot = true
	end
end
check("a new player knows the depot and its shops", knowsDepot and Explore.knows(start, "dealer") and Explore.knows(start, "guns") and Explore.knows(start, "mechanic") and Explore.knows(start, "supplies"))
check("a new player does not know the far places", not Explore.knows(start, "base") and not Explore.knows(start, "lodge") and not Explore.knows(start, "farm"))
check("an unknown id is never known", not Explore.knows(full, "no_such_place") and Explore.landmarkCell("no_such_place") == nil)
local listed = 0
for _, l in Map.Landmarks do
	local cell = Explore.landmarkCell(l.id)
	local list = cell and Explore.landmarksIn(cell)
	if list and table.find(list, l) then
		listed += 1
	end
end
check("every landmark is listed in its cell", listed == #Map.Landmarks, `{listed}/{#Map.Landmarks}`)
check("with every cell uncovered every landmark is known", #Explore.known(full) == #Map.Landmarks)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
