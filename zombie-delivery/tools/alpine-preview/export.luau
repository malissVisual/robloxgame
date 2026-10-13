-- 7.1, the Alps: shared/AlpineLayout.luau's ring and forests (the same numbers server/Alpine.luau builds) as one JSON
-- object for render.py: the map's roads, districts, yards and water for context, the terrain's top on a grid (its
-- height and material, the glaciers and the scree over it), the cones, the silhouettes, the trees, the meadows, the
-- huts and the portal's parts, and a fine height grid of one stretch for the 3/4 view. render.py copies the shared
-- modules next to it (their requires made plain) and runs it in the Luau CLI:  luau export.luau [x0 z0 x1 z1 cell]
local AlpineLayout = require("./AlpineLayout")
local Config = require("./Config")
local Map = require("./Map")

local A = Config.Alpine

local function encode(v: any): string
	local t = type(v)
	if t == "string" then
		return string.format("%q", v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		if v == math.floor(v) and math.abs(v) < 1e15 then
			return tostring(math.floor(v))
		end
		return string.format("%.3f", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		local out = {}
		if #v > 0 or next(v) == nil then
			for _, x in v do
				table.insert(out, encode(x))
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in v do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in keys do
			table.insert(out, string.format("%q", k) .. ":" .. encode(v[k]))
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

local ring = AlpineLayout.ring()
local forest = AlpineLayout.forest()

-- The glacier slabs and the scree balls (their tops over the cones' layers).
type Slab = { x: number, y: number, z: number, w: number, l: number, t: number, yaw: number, pitch: number }
local slabs: { Slab } = {}
for _, f in ring.fills do
	if f.material == "Glacier" then
		table.insert(slabs, { x = f.x, y = f.y, z = f.z, w = f.a, l = f.c, t = f.b, yaw = f.yaw, pitch = f.pitch })
	end
end
local function glacierTop(x: number, z: number): number
	local best = -math.huge
	for _, s in slabs do
		-- into the slab's frame: its -Z (look) downhill
		local dx, dz = x - s.x, z - s.z
		local lx = dx * math.cos(s.yaw) - dz * math.sin(s.yaw)
		local lz = dx * math.sin(s.yaw) + dz * math.cos(s.yaw)
		local along = lz / math.cos(s.pitch)
		if math.abs(lx) <= s.w / 2 and math.abs(along) <= s.l / 2 then
			-- the top face: the middle's top raised along the slope
			local top = s.y + (s.t / 2) / math.cos(s.pitch) - lz * math.tan(s.pitch)
			best = math.max(best, top)
		end
	end
	return best
end

-- The terrain's top and its material at (x, z).
local function surface(x: number, z: number): (number, string)
	local h, cone = AlpineLayout.heightAt(ring, x, z)
	local material = "none"
	if cone then
		local i = math.floor((h - cone.floor) / A.Layer + 0.5)
		material = AlpineLayout.layerMaterial(cone, i, cone.floor + (i - 0.5) * A.Layer)
	end
	for _, s in ring.solids do
		local u = (x - s.x) * s.nx + (z - s.z) * s.nz
		local v = math.abs((x - s.x) * s.nz - (z - s.z) * s.nx)
		if u >= 0 and u <= s.depth and v <= s.width / 2 then
			local top = A.Floor + (s.height - A.Floor) * (1 - u / s.depth)
			if top >= h then
				material = "Rock"
			end
		end
	end
	for _, b in ring.scree do
		local d2 = (x - b.x) ^ 2 + (z - b.z) ^ 2
		if d2 < b.r * b.r then
			local top = b.y + math.sqrt(b.r * b.r - d2)
			if top > h then
				h, material = top, "Limestone"
			end
		end
	end
	local g = glacierTop(x, z)
	if g > h - 1 then
		h, material = math.max(h, g), "Glacier"
	end
	return h, material
end

local CODES = { none = 0, Grass = 1, Rock = 2, Limestone = 3, Snow = 4, Glacier = 5, Ground = 6 }

local function grid(x0: number, z0: number, x1: number, z1: number, cell: number)
	local nx, nz = math.floor((x1 - x0) / cell) + 1, math.floor((z1 - z0) / cell) + 1
	local heights, materials = table.create(nx * nz, 0), table.create(nx * nz, 0)
	for j = 0, nz - 1 do
		for i = 0, nx - 1 do
			local h, m = surface(x0 + i * cell, z0 + j * cell)
			heights[j * nx + i + 1] = if h == -math.huge then -999 else math.floor(h * 10 + 0.5) / 10
			materials[j * nx + i + 1] = CODES[m] or 0
		end
	end
	return { x0 = x0, z0 = z0, cell = cell, nx = nx, nz = nz, h = heights, m = materials }
end

local box = ring.box
local reach = 0
for _, c in ring.cones do
	reach = math.max(reach, AlpineLayout.boxDistance(box, c.x, c.z) + (c.radii[1] or 0))
end
local wide = grid(box.x0 - reach, box.z0 - reach, box.x1 + reach, box.z1 + reach, 20)

-- The 3/4 view's stretch (default: the West Pass, the Old Farm and the west mountains).
local args = { ... }
local sx0, sz0, sx1, sz1 = -3000, -60, -1600, 1160
local scell = 6
if #args >= 4 then
	sx0, sz0, sx1, sz1 = tonumber(args[1]) :: number, tonumber(args[2]) :: number, tonumber(args[3]) :: number, tonumber(args[4]) :: number
	scell = tonumber(args[5]) or scell
end
local stretch = grid(sx0, sz0, sx1, sz1, scell)

local roads = {}
for _, s in Map.Segments do
	table.insert(roads, { s.ax, s.az, s.bx, s.bz, s.width, s.kind })
end
local districts = {}
for _, d in Map.Districts do
	local x0, x1, z0, z1 = Map.districtEdges(d)
	table.insert(districts, { x0 - Map.RoadWidth / 2, z0 - Map.RoadWidth / 2, x1 + Map.RoadWidth / 2, z1 + Map.RoadWidth / 2, d.name })
end
local yards = {}
for _, y in Map.Yards do
	table.insert(yards, { y.x0, y.z0, y.x1, y.z1, y.name })
end
local plots = {}
for id, plot in Map.EstatePlots do
	if plot.tower == nil then
		local ax, az = Map.plotPoint(plot, -plot.w / 2, -plot.front)
		local bx, bz = Map.plotPoint(plot, plot.w / 2, plot.back)
		table.insert(plots, { math.min(ax, bx), math.min(az, bz), math.max(ax, bx), math.max(az, bz), id })
	end
end
local cones = {}
for _, c in ring.cones do
	table.insert(cones, { id = c.id, row = c.row, x = c.x, z = c.z, r = c.radii[1] or 0, top = c.floor + #c.radii * A.Layer, winter = c.winter })
end
local trees = {}
local treeSpecs = {} -- (7.1 review: the 3/4 view draws the stretch's trees from the layout's own parts)
for _, t in forest.trees do
	table.insert(trees, { t.x, t.y, t.z, t.height, t.variant, t.snowy, t.slope, t.yaw })
	if t.x > sx0 - 60 and t.x < sx1 + 60 and t.z > sz0 - 60 and t.z < sz1 + 60 then
		for _, spec in AlpineLayout.treeParts(t) do
			table.insert(treeSpecs, spec)
		end
	end
end
local patches = {}
for _, p in forest.patches do
	local flowers = {}
	for _, f in p.flowers do
		table.insert(flowers, { f.x, f.z, f.size, f.color })
	end
	table.insert(patches, { x = p.x, z = p.z, flowers = flowers })
end
local huts = {}
for _, hut in forest.huts do
	table.insert(huts, { hut = hut, parts = AlpineLayout.hutParts(hut) })
end
local portals = {}
for _, p in ring.portals do
	local parts, signs = AlpineLayout.portalParts(p)
	table.insert(portals, { portal = p, parts = parts, signs = signs })
end

local carSealed = AlpineLayout.sealed(ring, 25, false)
local swimSealed = AlpineLayout.sealed(ring, 25, true)

print(encode({
	box = { box.x0, box.z0, box.x1, box.z1 },
	bounds = { Map.Bounds.x0, Map.Bounds.z0, Map.Bounds.x1, Map.Bounds.z1 },
	river = { Map.River.x0, Map.River.x1 },
	sea = Map.Sea.x0,
	lake = { Map.Lake.x0, Map.Lake.z0, Map.Lake.x1, Map.Lake.z1 },
	winterZ = Map.WinterZ,
	mountain = { Map.Mountain.x, Map.Mountain.z, Map.Mountain.radius },
	roads = roads,
	districts = districts,
	yards = yards,
	plots = plots,
	cones = cones,
	silhouettes = ring.silhouettes,
	gorges = ring.gorges,
	portals = portals,
	waterfall = AlpineLayout.waterfallParts(ring),
	trees = trees,
	treeParts = if #forest.trees > 0 then AlpineLayout.treeParts(forest.trees[1]) else {},
	treeSpecs = treeSpecs,
	treePartCount = A.Trees.Parts,
	colors = A.Colors,
	treeColors = A.Trees.Colors,
	trunk = A.Trees.Trunk,
	snowy = A.Trees.Snowy,
	patches = patches,
	huts = huts,
	wide = wide,
	stretch = stretch,
	stats = {
		fills = #ring.fills,
		volume = AlpineLayout.volume(ring.fills),
		cones = #ring.cones,
		silhouettes = #ring.silhouettes,
		glaciers = #ring.glaciers,
		scree = #ring.scree,
		trees = #forest.trees,
		patches = #forest.patches,
		huts = #forest.huts,
		parts = AlpineLayout.parts(ring, forest),
		sealedCar = carSealed,
		sealedSwim = swimSealed,
	},
}))
